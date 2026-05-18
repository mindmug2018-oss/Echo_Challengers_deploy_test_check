"""
파일위치 : ~/project1-aws/recovery/reference/webhook_server.py

목적: AlertManager의 webhook 요청을 받아 자동복구 실행
실행: uvicorn webhook_server:app --host 0.0.0.0 --port 9080

on-premise와의 차이점:
  - SSH 키 파일 경로: ./terraform/proj-key.pem
  - SSH 유저명: ec2-user (on-premise는 user1)
  - IP를 환경변수로 관리 (EC2 재생성 시 IP 변경 대응)
  - /var/log/recovery.log에 타임라인 기록
"""
import asyncio
import subprocess
import os
import logging
from fastapi import FastAPI
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime
import httpx

# ── 로그 설정 ──────────────────────────────────────────────────
logging.basicConfig(
    filename="/var/log/recovery.log",
    level=logging.INFO,
    format="%(asctime)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
log = logging.getLogger(__name__)

app = FastAPI(title="Auto Recovery Webhook Server")

# ── 환경변수 설정 ─────────────────────────────────────────────
# 이유: EC2 재생성 시 IP가 바뀌므로 하드코딩 금지
# Ansible role에서 systemd EnvironmentFile로 주입
SLACK           = os.getenv("SLACK_WEBHOOK_URL", "")
SSH_KEY         = os.getenv("SSH_KEY_PATH", "./terraform/proj-key.pem")
SSH_USER        = os.getenv("SSH_USER", "ec2-user")
WEB1_IP         = os.getenv("WEB1_IP", "")
WEB2_IP         = os.getenv("WEB2_IP", "")
DB_IP           = os.getenv("DB_IP", "")
PROMETHEUS_URL  = os.getenv("PROMETHEUS_URL", "http://localhost:9090")


# ── Alert 이름 → 복구 정보 매핑 테이블 ───────────────────────
# alert.rules.yml의 alert 이름과 정확히 일치해야 함
RECOVERY_MAP = {
    "FastAPIDown": {
        "service": "fastapi",
        "script":  "restart_fastapi.sh",
        "description": "FastAPI 서비스 자동 재시작"
    },
    "NodeDown": {
        "service": "node_exporter",
        "script":  "restart_fastapi.sh",   # node_exporter 포함
        "description": "Node Exporter 자동 재시작"
    },
}

# CPU 부하형 복구 매핑 추가 (기존 RECOVERY_MAP 옆에)
CPU_RECOVERY_MAP = {
    "HighCPU": "sudo pkill -9 -x stress-ng || true",
}

# Prometheus job 이름 → 대상 호스트 IP 매핑
# 이유: Alert의 labels.instance(IP:port)에서 IP를 추출해서 어느 서버인지 판단
def get_host_by_instance(instance: str) -> str:
    """instance 값(예: '1.2.3.4:8000')에서 IP를 추출해 해당 서버 IP 반환"""
    ip = instance.split(":")[0]
    if ip == WEB1_IP:
        return WEB1_IP
    elif ip == WEB2_IP:
        return WEB2_IP
    elif ip == DB_IP:
        return DB_IP
    return ip  # 알 수 없는 경우 그대로 반환


# ── Pydantic 모델 ─────────────────────────────────────────────
class Alert(BaseModel):
    status: str
    labels: dict
    annotations: dict = {}
    startsAt: Optional[str] = None

class Payload(BaseModel):
    alerts: List[Alert]


# ── 메인 Webhook 엔드포인트 ───────────────────────────────────
@app.post("/alert")
async def handle_alert(payload: Payload):
    for alert in payload.alerts:
        if alert.status != "firing":
            continue

        alert_name = alert.labels.get("alertname", "")
        instance   = alert.labels.get("instance", "")
        host       = get_host_by_instance(instance)
        rule       = RECOVERY_MAP.get(alert_name)
        ts         = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

         # ─── CPU 부하형 복구 ───
        if alert_name in CPU_RECOVERY_MAP:
            cmd = CPU_RECOVERY_MAP[alert_name]
            
            if not host:
                msg = f"호스트 매핑 없음: {alert_name} / instance={instance}"
                log.warning(msg)
                await notify(f"UNKNOWN {msg}")
                continue
            
            log.info(f"부하 제거 시작: {alert_name} | {host} | {ts}")
            await notify(f"자동복구 시작: *{alert_name}*\n서버: {host} | 액션: stress-ng kill | {ts}")
            
            # SSH 명령 실행 (async 함수이므로 await 필수)
            ok = await run_ssh_command(host, cmd)
            if not ok:
                msg = f"복구 실패 ❌: {alert_name} @ {host} — 명령 실행 실패"
                log.warning(msg)
                await notify(msg)
                continue
            
            # Prometheus 폴링으로 실제 정상화 확인
            log.info(f"메트릭 회복 대기 시작: {host}")
            recovered = await wait_for_cpu_recovery(instance, threshold=80, max_wait=180)
            
            ts_done = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            if recovered:
                msg = f"복구 완료 ✅: {alert_name} | CPU 정상화 확인@{host} | {ts_done}"
            else:
                msg = f"복구 미확인 ⚠️: {alert_name} | {host} — 메트릭 회복 미확인"
            
            log.info(msg)
            await notify(msg)
            continue    

        if not rule:
            msg = f"알 수 없는 Alert: {alert_name} — 수동 확인 필요"
            log.warning(msg)
            await notify(f"UNKNOWN {msg}")
            continue

        if not host:
            msg = f"복구 대상 호스트 불명: {alert_name} / instance={instance}"
            log.warning(msg)
            await notify(f"HOST_UNKNOWN {msg}")
            continue

        log.info(f"복구 시작: {alert_name} | {rule['service']}@{host} | {ts}")
        await notify(
            f"자동복구 시작\n"
            f"> Alert: *{alert_name}*\n"
            f"> 서버: `{host}`\n"
            f"> 작업: {rule['description']}\n"
            f"> 시각: {ts}"
        )

        ok = run_recovery_script(host, rule["script"])

        if ok:
            result = f"복구 완료 ✅: {alert_name} @ {host}"
        else:
            result = f"복구 실패 ❌: {alert_name} @ {host} — 수동 개입 필요"

        log.info(result)
        await notify(result)

    return {"ok": True}


@app.get("/health")
def health():
    return {"status": "ok", "server": "recovery-webhook"}


# ── 복구 스크립트 SSH 실행 ────────────────────────────────────
def run_recovery_script(host: str, script: str) -> bool:
    """
    mgmt 서버에서 대상 서버로 SSH 접속해 복구 스크립트 실행
    스크립트 위치: ~/project1-aws/recovery/scripts/
    """
    script_path = os.path.join(
        os.path.dirname(__file__), "scripts", script
    )

    cmd = [
        "ssh",
        "-i", SSH_KEY,
        "-o", "StrictHostKeyChecking=no",
        "-o", "ConnectTimeout=10",
        f"{SSH_USER}@{host}",
        f"bash -s"  # 스크립트를 stdin으로 전달
    ]

    try:
        with open(script_path, "r") as f:
            script_content = f.read()

        result = subprocess.run(
            cmd,
            input=script_content,
            capture_output=True,
            text=True,
            timeout=60
        )

        if result.returncode != 0:
            log.error(f"복구 스크립트 오류: {result.stderr.strip()}")

        return result.returncode == 0

    except FileNotFoundError:
        log.error(f"스크립트 없음: {script_path}")
        return False
    except subprocess.TimeoutExpired:
        log.error(f"SSH 타임아웃: {host}")
        return False
    except Exception as e:
        log.error(f"예외 발생: {e}")
        return False


# ── Slack 알림 ────────────────────────────────────────────────
async def notify(msg: str):
    if not SLACK:
        return
    try:
        async with httpx.AsyncClient() as c:
            await c.post(
                SLACK,
                json={"text": msg},
                timeout=5
            )
    except Exception as e:
        log.error(f"Slack 알림 실패: {e}")

# 파일 하단에 새 함수 추가
async def run_ssh_command(host: str, cmd: str) -> bool:
    """SSH로 명령만 실행 (스크립트 파일 없이)"""
    try:
        result = subprocess.run(
            ["ssh", "-i", SSH_KEY,
             "-o", "StrictHostKeyChecking=no",
             "-o", "ConnectTimeout=10",
             f"{SSH_USER}@{host}", cmd],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            timeout=30
        )
        if result.returncode != 0:
            log.error(f"SSH 오류: {result.stderr.strip()}")
        return result.returncode == 0
    except Exception as e:
        log.error(f"SSH 예외: {e}")
        return False


async def wait_for_cpu_recovery(
    instance: str,
    threshold: float = 80.0,
    max_wait: int = 180,
    poll_interval: int = 5
) -> bool:
    """Prometheus 폴링으로 CPU 정상화 확인"""
    # AWS 환경: instance는 'IP:port' 형식
    ip = instance.split(":")[0]
    query = (
        f'100 - (avg by(instance) '
        f'(irate(node_cpu_seconds_total{{mode="idle",instance=~"{ip}.*"}}[30s])) '
        f'* 100)'
    )
    elapsed = 0
    
    async with httpx.AsyncClient() as client:
        while elapsed < max_wait:
            try:
                resp = await client.get(
                    f"{PROMETHEUS_URL}/api/v1/query",
                    params={"query": query},
                    timeout=5
                )
                data = resp.json()
                results = data.get("data", {}).get("result", [])
                
                if results:
                    cpu_value = float(results[0]["value"][1])
                    log.info(f"폴링 [{elapsed}s]: {ip} CPU = {cpu_value:.1f}%")
                    if cpu_value < threshold:
                        return True
            except Exception as e:
                log.warning(f"Prometheus 폴링 예외: {e}")
            
            await asyncio.sleep(poll_interval)
            elapsed += poll_interval
    
    log.warning(f"정상화 미확인: {ip} {max_wait}초 초과")
    return False