#!/bin/bash
# 파일: ~/project1-aws/bootstrap_tailscale.sh
# 목적: proj-mgmt(VMware)에 Tailscale 설치 + VMware ↔ AWS VPN 연결
# 실행: 
#   [방법 1] TAILSCALE_AUTHKEY=tskey-auth-xxxxx ./bootstrap_tailscale.sh
#   [방법 2] echo 'TAILSCALE_AUTHKEY=tskey-auth-xxxxx' > ~/.tailscale_authkey
#           chmod 600 ~/.tailscale_authkey
#           ./bootstrap_tailscale.sh

set -euo pipefail

# 팀 환경에 맞게 대역 수정 가능
VMWARE_CIDR="172.16.1.0/24"
SYSCTL_CONF="/etc/sysctl.d/99-tailscale.conf"

echo "============================================="
echo "  proj-mgmt → Tailscale VPN 설정 시작"
echo "============================================="

# 1. OS 확인 (RHEL/Rocky 기반)
if [ ! -f /etc/redhat-release ]; then
    echo "[Error] 이 스크립트는 RHEL/Rocky Linux용입니다."
    exit 1
fi

# 2. Auth Key 확인 (환경변수 또는 파일에서)
if [ -z "${TAILSCALE_AUTHKEY:-}" ]; then
    AUTHKEY_FILE="${HOME}/.tailscale_authkey"
    if [ -f "$AUTHKEY_FILE" ]; then
        echo "[INFO] $AUTHKEY_FILE 에서 Auth Key 로드 중..."
        # shellcheck disable=SC1090
        source "$AUTHKEY_FILE"
    fi
fi

if [ -z "${TAILSCALE_AUTHKEY:-}" ]; then
    echo ""
    echo "============================================="
    echo "[Error] Tailscale Auth Key가 필요합니다."
    echo "============================================="
    echo ""
    echo "📌 발급 방법:"
    echo "   1. https://login.tailscale.com/admin/settings/keys"
    echo "   2. 'Generate auth key' 클릭"
    echo "   3. 옵션 체크:"
    echo "      - Reusable: ON (팀원 여러명이 공유)"
    echo "      - Pre-approved: ON (라우팅 자동 승인)"
    echo "      - Expiration: 90 days (기본)"
    echo "   4. 'tskey-auth-xxxxx' 복사"
    echo ""
    echo "📌 사용 방법 (둘 중 하나):"
    echo ""
    echo "   [방법 1] 환경변수로 1회 실행:"
    echo "     TAILSCALE_AUTHKEY=tskey-auth-xxxxx ./bootstrap_tailscale.sh"
    echo ""
    echo "   [방법 2] 파일에 저장 (재사용):"
    echo "     echo 'TAILSCALE_AUTHKEY=tskey-auth-xxxxx' > ~/.tailscale_authkey"
    echo "     chmod 600 ~/.tailscale_authkey"
    echo "     ./bootstrap_tailscale.sh"
    echo "============================================="
    exit 1
fi

echo "[OK] Auth Key 확인됨"

# 3. Tailscale 설치 (이미 설치되어 있으면 skip)
if ! command -v tailscale &> /dev/null; then
    echo "[INFO] Tailscale 리포지토리 등록 및 설치 중..."
    sudo dnf config-manager --add-repo https://pkgs.tailscale.com/stable/rhel/9/tailscale.repo
    sudo dnf install -y tailscale
else
    echo "[OK] Tailscale 이미 설치됨: $(tailscale version | head -1)"
fi

# 4. IP Forwarding 활성화 (idempotent)
if [ ! -f "$SYSCTL_CONF" ]; then
    echo "[INFO] IP forwarding 설정 중..."
    sudo tee "$SYSCTL_CONF" > /dev/null <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
    sudo sysctl -p "$SYSCTL_CONF"
else
    echo "[OK] sysctl 설정 이미 존재: $SYSCTL_CONF"
fi

# 5. Tailscale 서비스 시작
sudo systemctl enable --now tailscaled

# 6. Tailscale 가입 (인증 자동화)
# proj-mgmt는 subnet router : 172.16.1.0/24 대역 사용
# --accept-routes=false --> ec2 에서 proj-mgmt 접근 불가
echo "[INFO] Tailscale 가입 및 라우트 광고 중..."
sudo tailscale up \
    --authkey="$TAILSCALE_AUTHKEY" \
    --advertise-routes="$VMWARE_CIDR" \
    --accept-dns=false \
    --accept-routes=false \
    --reset

# 검증: AdvertiseRoutes가 실제로 적용됐는지 확인
# 일부 경우 --reset이 --advertise-routes를 무력화시키는 quirk가 있어 재시도 로직 추가
sleep 3
if ! sudo tailscale debug prefs 2>/dev/null | grep -A 2 "AdvertiseRoutes" | grep -q "$VMWARE_CIDR"; then
    echo "[WARN] Advertise routes 미적용 감지, 재설정 중..."
    sudo tailscale set --advertise-routes="$VMWARE_CIDR"
    sleep 2
fi

# 7. 최종 상태 출력
echo ""
echo "============================================="
echo "✅ 설정 완료! 현재 연결 상태:"
echo "============================================="
sudo tailscale status | head -n 10
echo ""
echo "📌 라우팅 승인 확인:"
echo "   - Auth Key에서 Pre-approved 체크했다면 자동 승인됨"
echo "   - 'Subnets ⓘ' 경고가 보이면 수동 승인 필요:"
echo "     https://login.tailscale.com/admin/machines"
echo "     → proj-mgmt → ⋮ → Edit route settings → $VMWARE_CIDR 체크 → Save"
echo ""
echo "📌 다음 단계:"
echo "   - terraform/main.tf NAT instance + Tailscale 통합"
echo "   - make apply 로 AWS 인프라 + Tailscale 통합 배포"
echo "============================================="