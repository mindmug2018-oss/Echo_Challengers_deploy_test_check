#!/bin/bash
# =============================================================
# 파일위치 : ~/project1-aws/chaos/inject.sh
# 목적     : AWS 환경 장애 주입 스크립트
# 실행위치 : ~/project1-aws/ 에서 실행
# 사용법   : ./chaos/inject.sh [시나리오]
#
# on-premise와의 차이점:
#   - SSH 키 파일 명시 필요 (EC2 접속 방식)
#   - 유저명 ec2-user (on-premise는 user1)
#   - IP를 terraform output에서 자동 읽기
#   - ALB DNS로 응답시간 측정
# =============================================================

set -e

# ── 설정 ──────────────────────────────────────────────────────
KEY="./terraform/proj-aws-key.pem"
RESULTS_DIR="./chaos/results"
SLACK="${SLACK_WEBHOOK_URL:-}"

# terraform output에서 IP/DNS 자동 읽기
# 이유: EC2는 재생성할 때마다 IP가 바뀌므로 하드코딩 금지
get_ip() {
    cd ./terraform && terraform output -raw "$1" 2>/dev/null && cd ..
}

# ── 색상 함수 ─────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
err()     { echo -e "${RED}[ERROR]${NC} $1"; }

# ── Slack 알림 함수 ───────────────────────────────────────────
notify() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg"
    if [ -n "$SLACK" ]; then
        curl -s -X POST "$SLACK" \
            -H 'Content-type: application/json' \
            --data "{\"text\":\"[CHAOS-AWS] $msg\"}" > /dev/null 2>&1
    fi
}

# ── SSH 실행 함수 ─────────────────────────────────────────────
# 이유: EC2는 키 파일(-i)과 유저명(ec2-user) 명시 필요
# Private subnet의 host (10.0.11.x, 10.0.12.x)는 자동으로 mgmt를 jump host로 경유
ssh_exec() {
    local host="$1"
    local cmd="$2"
    # Private IP면 mgmt를 jump host로 사용
    if [[ "$host" == 10.0.11.* ]] || [[ "$host" == 10.0.12.* ]]; then
        ssh -i "$KEY" \
            -o StrictHostKeyChecking=no \
            -o ConnectTimeout=10 \
            -o "ProxyCommand=ssh -i $KEY -o StrictHostKeyChecking=no -W %h:%p ec2-user@$MGMT_IP" \
            "ec2-user@${host}" "$cmd"
    else
        ssh -i "$KEY" \
            -o StrictHostKeyChecking=no \
            -o ConnectTimeout=10 \
            "ec2-user@${host}" "$cmd"
    fi
}

# ── IP 로드 ───────────────────────────────────────────────────
load_ips() {
    info "terraform output에서 IP 읽는 중..."
    WEB1_IP=$(get_ip "web1_public_ip")
    WEB2_IP=$(get_ip "web2_public_ip")
    ALB_DNS=$(get_ip "alb_dns_name")
    MGMT_IP=$(get_ip "mgmt_public_ip")

    if [ -z "$WEB1_IP" ] || [ -z "$ALB_DNS" ]; then
        err "IP 로드 실패 → 'make apply'를 먼저 실행하세요"
        exit 1
    fi
    info "WEB1: $WEB1_IP / WEB2: $WEB2_IP / ALB: $ALB_DNS"
}

# ── 메인 시나리오 ─────────────────────────────────────────────
mkdir -p "$RESULTS_DIR"
load_ips

case "${1:-}" in

  # ── 시나리오 A: 단일 서버 FastAPI 장애 ──────────────────────
  fastapi1)
    notify "장애 주입: web1 FastAPI 중지 ($WEB1_IP)"
    ssh_exec "$WEB1_IP" "sudo systemctl stop fastapi"
    success "완료 → 30초 후 FastAPIDown Alert 발생 예정"
    ;;

  fastapi2)
    notify "장애 주입: web2 FastAPI 중지 ($WEB2_IP)"
    ssh_exec "$WEB2_IP" "sudo systemctl stop fastapi"
    success "완료 → 30초 후 FastAPIDown Alert 발생 예정"
    ;;

  # ── 시나리오 A-2: Nginx 장애 ────────────────────────────────
  nginx1)
    notify "장애 주입: web1 Nginx 중지 ($WEB1_IP)"
    ssh_exec "$WEB1_IP" "sudo systemctl stop nginx"
    success "완료 → ALB 헬스체크 실패로 트래픽 web2로 집중"
    ;;

  nginx2)
    notify "장애 주입: web2 Nginx 중지 ($WEB2_IP)"
    ssh_exec "$WEB2_IP" "sudo systemctl stop nginx"
    ;;

  # ── 시나리오 B: DB 장애 ──────────────────────────────────────
  db)
    DB_IP=$(get_ip "db_private_ip")
    notify "장애 주입: DB PostgreSQL 중지 ($DB_IP, jump host: $MGMT_IP)"
    # ssh_exec 함수가 Private IP 자동 감지 → mgmt 경유
    ssh_exec "$DB_IP" "sudo systemctl stop postgresql"
    success "완료 → FastAPI /items 요청 시 500 에러 발생 예정"
    ;;

  # ── 시나리오 C: CPU 과부하 (개인 주제) ──────────────────────
  cpu1)
    notify "장애 주입: web1 CPU 과부하 120초 ($WEB1_IP)"
    ssh_exec "$WEB1_IP" \
        "nohup stress-ng --cpu \$(nproc) --timeout 120s > /dev/null 2>&1 &"
    success "완료 → 1분 후 HighCPU Alert 발생 예정"
    warn "응답시간 측정: ./chaos/inject.sh response_test"
    ;;

  cpu2)
    notify "장애 주입: web2 CPU 과부하 120초 ($WEB2_IP)"
    ssh_exec "$WEB2_IP" \
        "nohup stress-ng --cpu \$(nproc) --timeout 120s > /dev/null 2>&1 &"
    ;;

  cpu_both)
    notify "장애 주입: web1+web2 동시 CPU 과부하 120초"
    ssh_exec "$WEB1_IP" \
        "nohup stress-ng --cpu \$(nproc) --timeout 120s > /dev/null 2>&1 &"
    ssh_exec "$WEB2_IP" \
        "nohup stress-ng --cpu \$(nproc) --timeout 120s > /dev/null 2>&1 &"
    success "완료 → 양쪽 서버 동시 과부하"
    ;;

    # pkill -f stress-ng 2>/dev/null --> pkill -9 -x stress-ng
  cpu_stop)
    notify "CPU 과부하 해제"
    ssh_exec "$WEB1_IP" "sudo pkill -9 -x stress-ng || true"
    ssh_exec "$WEB2_IP" "sudo pkill -9 -x stress-ng || true"
    success "완료"
    ;;

  # ── 응답시간 측정 (개인 주제 핵심 데이터) ───────────────────
  # 이유: ALB DNS로 요청 → 과부하 전/중/후 응답시간 비교
  response_test)
    TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
    RESULT_FILE="$RESULTS_DIR/response_${TIMESTAMP}.txt"

    echo "=== 응답시간 측정 시작 (30회 / ALB: $ALB_DNS) ===" | tee "$RESULT_FILE"
    echo "시작시각: $(date)" | tee -a "$RESULT_FILE"
    echo "" | tee -a "$RESULT_FILE"

    TOTAL=0
    for i in $(seq 1 30); do
        RESP=$(curl -o /dev/null -s -w "%{time_total}" \
            --connect-timeout 5 \
            "http://${ALB_DNS}/health" 2>/dev/null || echo "0")
        MS=$(echo "$RESP * 1000" | bc 2>/dev/null | cut -d. -f1)
        LINE="요청 $(printf '%02d' $i): ${MS}ms"
        echo "$LINE" | tee -a "$RESULT_FILE"
        TOTAL=$((TOTAL + MS))
        sleep 1
    done

    AVG=$((TOTAL / 30))
    echo "" | tee -a "$RESULT_FILE"
    echo "=== 평균 응답시간: ${AVG}ms ===" | tee -a "$RESULT_FILE"
    echo "결과 저장: $RESULT_FILE"
    ;;

  # ── 응답시간 측정 (개선판: warmup + 3단계 측정) ─────────────
  benchmark)
    TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
    RESULT_FILE="$RESULTS_DIR/benchmark_${TIMESTAMP}.csv"
    
    echo "phase,seq,ms,timestamp" > "$RESULT_FILE"
    
    measure() {
      local PHASE=$1
      local COUNT=$2
      echo "=== [$PHASE] $COUNT회 측정 ===" 
      for i in $(seq 1 $COUNT); do
        T=$(date '+%H:%M:%S')
        RESP=$(curl -o /dev/null -s -w "%{time_total}" \
          --max-time 10 "http://${ALB_DNS}/items" 2>/dev/null || echo "10.0")
        MS=$(echo "$RESP * 1000" | bc | cut -d. -f1)
        printf "  %s | %2d/%d: %5d ms\n" "$T" "$i" "$COUNT" "$MS"
        echo "$PHASE,$i,$MS,$T" >> "$RESULT_FILE"
        sleep 1
      done
    }
    
    # Phase 0: Warmup (cold start 효과 제거)
    echo ">>> Warmup (5회, 측정 제외)"
    for i in $(seq 1 5); do
      curl -o /dev/null -s --max-time 10 "http://${ALB_DNS}/items" 2>/dev/null || true
      sleep 0.3
    done
    sleep 1
    
    # Phase 1: 정상 측정
    measure "normal" 10
    
    # Phase 2: 부하 주입 + 측정
    echo ">>> CPU 부하 주입 (web1 + web2 동시)"
    ssh_exec "$WEB1_IP" "nohup stress-ng --cpu \$(nproc) --timeout 180s > /dev/null 2>&1 &"
    ssh_exec "$WEB2_IP" "nohup stress-ng --cpu \$(nproc) --timeout 180s > /dev/null 2>&1 &"
    sleep 3
    measure "stressed" 45
    
    # Phase 3: 안정화 대기 + 복구 측정
    echo ">>> 안정화 대기 (60초)"
    sleep 60
    measure "recovered" 10
    
    # 요약 출력
    echo ""
    echo "=== 측정 완료 — 요약 ==="
    awk -F',' 'NR>1 {sum[$1]+=$3; cnt[$1]++; if($3>max[$1])max[$1]=$3} END {
      for (p in sum) printf "  %-10s 평균 %.1f ms / 최대 %d ms\n", p, sum[p]/cnt[p], max[p]
    }' "$RESULT_FILE"
    echo "결과 파일: $RESULT_FILE"
    ;;

  # ── 전체 복구 ────────────────────────────────────────────────
  all)
    notify "전체 서비스 복구 시작"
    DB_IP=$(get_ip "db_private_ip")

    ssh_exec "$WEB1_IP" "sudo systemctl start fastapi nginx" && \
        success "web1 fastapi+nginx 복구"
    ssh_exec "$WEB2_IP" "sudo systemctl start fastapi nginx" && \
        success "web2 fastapi+nginx 복구"
    ssh_exec "$DB_IP"   "sudo systemctl start postgresql" && \
        success "DB postgresql 복구"

    notify "전체 복구 완료"
    ;;

  # ── 전체 서비스 상태 확인 ────────────────────────────────────
  status)
    DB_IP=$(get_ip "db_private_ip")
    echo ""
    echo "=== AWS 서비스 상태 ==="
    echo -n "  FastAPI web1 : " && \
        ssh_exec "$WEB1_IP" "systemctl is-active fastapi" 2>/dev/null || echo "접속실패"
    echo -n "  Nginx   web1 : " && \
        ssh_exec "$WEB1_IP" "systemctl is-active nginx" 2>/dev/null || echo "접속실패"
    echo -n "  FastAPI web2 : " && \
        ssh_exec "$WEB2_IP" "systemctl is-active fastapi" 2>/dev/null || echo "접속실패"
    echo -n "  Nginx   web2 : " && \
        ssh_exec "$WEB2_IP" "systemctl is-active nginx" 2>/dev/null || echo "접속실패"
    echo -n "  PostgreSQL   : " && \
        ssh_exec "$DB_IP"   "systemctl is-active postgresql" 2>/dev/null || echo "접속실패"
    echo -n "  Prometheus   : " && \
        ssh_exec "$MGMT_IP" "systemctl is-active prometheus" 2>/dev/null || echo "접속실패"
    echo -n "  Grafana      : " && \
        ssh_exec "$MGMT_IP" "systemctl is-active grafana-server" 2>/dev/null || echo "접속실패"
    echo -n "  AlertManager : " && \
        ssh_exec "$MGMT_IP" "systemctl is-active alertmanager" 2>/dev/null || echo "접속실패"
    echo -n "  Recovery     : " && \
        ssh_exec "$MGMT_IP" "systemctl is-active recovery" 2>/dev/null || echo "접속실패"
    echo ""
    ;;

  *)
    echo ""
    echo "사용법: ./chaos/inject.sh [시나리오]"
    echo ""
    echo "  [시나리오 A] 단일 서버 장애"
    echo "  fastapi1    web1 FastAPI 중지"
    echo "  fastapi2    web2 FastAPI 중지"
    echo "  nginx1      web1 Nginx 중지"
    echo "  nginx2      web2 Nginx 중지"
    echo ""
    echo "  [시나리오 B] DB 장애"
    echo "  db          PostgreSQL 중지"
    echo ""
    echo "  [시나리오 C] CPU 과부하 (개인 주제)"
    echo "  cpu1          web1 CPU 과부하 120초"
    echo "  cpu2          web2 CPU 과부하 120초"
    echo "  cpu_both      양쪽 동시 CPU 과부하"
    echo "  cpu_stop      CPU 과부하 해제 (pkill -x)"
    echo "  response_test ALB 응답시간 30회 측정 → results/ 저장"
    echo "  benchmark     warmup + 정상/부하/복구 3단계 자동 측정 (CSV)"
    echo ""
    echo "  [공통]"
    echo "  all         전체 서비스 복구"
    echo "  status      전체 서비스 상태 확인"
    echo ""
    ;;
esac