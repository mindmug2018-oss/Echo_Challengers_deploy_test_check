#!/bin/bash
# =============================================================
# 파일위치 : ~/project1-aws/check.sh
# AWS 자격증명 및 전체 환경 상태 확인 스크립트
# 실행 : bash check.sh
# =============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✅ $1${NC}"; }
fail() { echo -e "  ${RED}❌ $1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠️  $1${NC}"; }

echo ""
echo "============================================="
echo "  팀 프로젝트 환경 상태 확인"
echo "============================================="
echo ""


# ── 1. 필수 도구 설치 여부 ─────────────────────────────────
echo "[ 1 ] 필수 도구 설치 확인"

if command -v aws &>/dev/null; then
    ok "AWS CLI : $(aws --version 2>&1 | awk '{print $1}')"
else
    fail "AWS CLI : 미설치 → bash setup.sh 실행 필요"
fi

if command -v terraform &>/dev/null; then
    ok "Terraform : $(terraform -version | head -1)"
else
    fail "Terraform : 미설치 → bash setup.sh 실행 필요"
fi

# 이유: Ansible 버전까지 확인하고, 권장 버전(2.14+) 미만이면 경고 표시
if command -v ansible &>/dev/null; then
    ANSIBLE_VER=$(ansible --version | head -1 | grep -oP '\d+\.\d+\.\d+' | head -1)
    ANSIBLE_MINOR=$(echo "$ANSIBLE_VER" | cut -d. -f2)
    if [ "${ANSIBLE_MINOR}" -ge 14 ] 2>/dev/null; then
        ok "Ansible : $(ansible --version | head -1) ✓ 권장버전 이상"
    else
        warn "Ansible : $(ansible --version | head -1) — 권장버전(2.14+) 미만"
        warn "업그레이드: sudo dnf install -y ansible"
    fi
else
    fail "Ansible : 미설치"
    echo "       → make setup 실행 후 재확인하세요"
fi

echo ""


# ── 2. AWS 자격증명 확인 ───────────────────────────────────
echo "[ 2 ] AWS 자격증명 확인"

if aws sts get-caller-identity &>/dev/null; then
    ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    USER=$(aws sts get-caller-identity --query Arn --output text)
    REGION=$(aws configure get region)
    ok "자격증명 유효"
    echo "       계정 ID : $ACCOUNT"
    echo "       사용자  : $USER"
    echo "       리전    : $REGION"

    if [ "$REGION" != "ap-northeast-2" ]; then
        warn "리전이 ap-northeast-2(서울)이 아닙니다!"
        warn "aws configure 재실행 후 ap-northeast-2 입력 필요"
    else
        ok "리전 정상 : ap-northeast-2 (서울)"
    fi
else
    fail "자격증명 없음 또는 만료"
    echo "       → aws configure 실행 후 키 입력 필요"
fi

echo ""


# ── 3. 프리티어 EC2 한도 안내 ──────────────────────────────
echo "[ 3 ] 프리티어 안내"
echo "  - t2.micro : 월 750시간 무료"
echo "  - 4대 동시 실행 시 약 4배 소모 → 약 7일치"
echo "  - 실습 후 반드시 terraform destroy 실행"
echo ""


# ── 4. 프로젝트 폴더 확인 ──────────────────────────────────
echo "[ 4 ] 프로젝트 폴더 확인"

if [ -d "$HOME/project1-aws/terraform" ]; then
    ok "폴더 존재 : ~/project1-aws/terraform"
else
    fail "폴더 없음 : ~/project1-aws/terraform"
    echo "       → mkdir -p ~/project1-aws/terraform 실행 필요"
fi

echo ""
echo "============================================="
echo "  확인 완료"
echo "============================================="
echo ""