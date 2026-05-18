#!/bin/bash
# =============================================================
# 파일위치 : ~/project1-aws/setup.sh 
# 팀 프로젝트 환경 설정 스크립트
# 대상 OS : Rocky Linux 8.x
# 목적    : AWS CLI v2 + Terraform + ansible 설치 및 검증
# 실행    : bash setup.sh
# =============================================================

set -e  # 오류 발생 시 즉시 중단

# OS 호환성 체크
if [ ! -f /etc/redhat-release ] && [ ! -f /etc/rocky-release ]; then
    echo "⚠️  이 스크립트는 Rocky Linux 8 기반입니다."
    echo "    다른 OS의 경우 아래 도구를 수동 설치하세요:"
    echo "    - AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    echo "    - Terraform: https://developer.hashicorp.com/terraform/downloads"
    echo "    - Ansible: https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html"
    echo ""
    read -p "계속 진행하시겠습니까? (y/N): " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# ── 색상 출력 함수 ──────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}    $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC}   $1"; exit 1; }

echo ""
echo "============================================="
echo "  팀 프로젝트 환경 설정 시작"
echo "  Rocky Linux 8 | AWS CLI v2 | Terraform"
echo "============================================="
echo ""


# ── STEP 1 : 기존 설치 확인 ────────────────────────────────
info "STEP 1/5 : 기존 설치 여부 확인 중..."

AWS_INSTALLED=false
TF_INSTALLED=false
ANSIBLE_INSTALLED=false

# AWS CLI 확인 로직
if command -v aws &>/dev/null; then
    AWS_VER=$(aws --version 2>&1 | awk '{print $1}')
    warning "AWS CLI 이미 설치됨: $AWS_VER → 재설치 건너뜀"
    AWS_INSTALLED=true
fi

# Terraform 확인 로직
if command -v terraform &>/dev/null; then
    TF_VER=$(terraform -version | head -1)
    warning "Terraform 이미 설치됨: $TF_VER → 재설치 건너뜀"
    TF_INSTALLED=true
fi

# Ansible 확인 로직
if command -v ansible &>/dev/null; then
    ANS_VER=$(ansible --version | head -1)
    warning "Ansible 이미 설치됨: $ANS_VER → 재설치 건너뜀"
    ANSIBLE_INSTALLED=true
fi

# ── STEP 1.5 : Make 패키지 확인 및 설치 (추가) ────────────────
info "STEP 1.5/5 : 인프라 관리 도구(make) 확인 중..."

if ! command -v make &>/dev/null; then
    info "  make 패키지가 없습니다. 설치를 시작합니다..."
    # Rocky Linux / Amazon Linux 공용 (dnf)
    sudo dnf install -y make -q || error "make 설치 실패"
    success "make 설치 완료: $(make -v | head -1)"
else
    info "  make가 이미 설치되어 있습니다."
fi

# ── STEP 2 : AWS CLI v2 설치 ───────────────────────────────
if [ "$AWS_INSTALLED" = false ]; then
    info "STEP 2/5 : AWS CLI v2 설치 중..."

    # 임시 작업 디렉토리
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"

    info "  설치 파일 다운로드 중..."
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
        -o "awscliv2.zip" || error "AWS CLI 다운로드 실패"

    info "  압축 해제 도구 설치 중..."
    sudo yum -y install unzip -q

    info "  압축 해제 중..."
    unzip -q awscliv2.zip

    info "  AWS CLI 설치 중..."
    sudo ./aws/install

    # 임시 폴더 정리
    cd ~
    rm -rf "$TMP_DIR"

    # 설치 확인
    if command -v aws &>/dev/null; then
        success "AWS CLI 설치 완료: $(aws --version 2>&1 | awk '{print $1}')"
    else
        error "AWS CLI 설치 실패"
    fi
else
    info "STEP 2/5 : AWS CLI 건너뜀 (이미 설치됨)"
fi


# ── STEP 3 : Terraform 설치 ────────────────────────────────
if [ "$TF_INSTALLED" = false ]; then
    info "STEP 3/5 : Terraform 설치 중..."

    info "  yum-utils 설치 중..."
    sudo dnf install -y yum-utils -q

    info "  HashiCorp 공식 저장소 추가 중..."
    sudo yum-config-manager \
        --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo \
        -q 2>/dev/null || true

    info "  Terraform 설치 중..."
    sudo dnf install -y terraform -q

    # 설치 확인
    if command -v terraform &>/dev/null; then
        success "Terraform 설치 완료: $(terraform -version | head -1)"
        
        # [추가된 부분] 자동 완성 기능 활성화
        info "  Terraform 자동 완성 설정 적용 중..."
        terraform -install-autocomplete 2>/dev/null || true
    else
        error "Terraform 설치 실패"
    fi
else
    info "STEP 3/5 : Terraform 건너뜀 (이미 설치됨)"
fi


# ── STEP 4 : Ansible 설치 ──────────────────────────────────
if [ "$ANSIBLE_INSTALLED" = false ]; then
    info "STEP 4/5 : Ansible 설치 중..."

    info "  EPEL 저장소 설치 중..."
    sudo dnf install -y epel-release -q

    info "  Ansible 설치 중..."
    sudo dnf install -y ansible -q

    if command -v ansible &>/dev/null; then
        success "Ansible 설치 완료: $(ansible --version | head -1)"
    else
        error "Ansible 설치 실패"
    fi
else
    info "STEP 4/5 : Ansible 건너뜀 (이미 설치됨)"
fi


# ── STEP 5 : 버전 검증 ─────────────────────────────────────
info "STEP 5/5 : 설치 결과 최종 검증 중..."
echo ""
echo "  ┌─────────────────────────────────────────┐"
echo "  │               설치 결과 요약              │"
echo "  ├─────────────────────────────────────────┤"

# AWS CLI 검증
if command -v aws &>/dev/null; then
    AWS_VER=$(aws --version 2>&1)
    echo "  │ ✅ AWS CLI : $AWS_VER"
else
    echo "  │ ❌ AWS CLI : 설치 실패"
fi

# Terraform 검증
if command -v terraform &>/dev/null; then
    TF_VER=$(terraform -version | head -1)
    echo "  │ ✅ Terraform : $TF_VER"
else
    echo "  │ ❌ Terraform : 설치 실패"
fi

# Ansible 검증
if command -v ansible &>/dev/null; then
    ANS_VER=$(ansible --version | head -1 | awk '{print $2}' | tr -d ']')
    echo "  │ ✅ Ansible : $ANS_VER"
else
    echo "  │ ❌ Ansible : 설치 실패"
fi

echo "  └─────────────────────────────────────────┘"
echo ""


# ── 다음 단계 안내 ─────────────────────────────────────────
echo "============================================="
success "환경 설치 완료!"
echo "============================================="
echo ""
echo "  다음 단계: AWS 자격증명 등록"
echo ""
echo "  1. AWS 콘솔에서 Access Key 발급"
echo "     IAM → Users → 본인계정"
echo "     → Security credentials → Create access key"
echo ""
echo "  2. 아래 명령어 실행 후 키 입력"
echo ""
echo "     aws configure"
echo ""
echo "  3. 입력 항목"
echo "     AWS Access Key ID     : [발급받은 키]"
echo "     AWS Secret Access Key : [발급받은 시크릿]"
echo "     Default region name   : ap-northeast-2"
echo "     Default output format : json"
echo ""
echo "  4. 설정 확인"
echo "     aws sts get-caller-identity"
echo ""
echo "============================================="
echo ""