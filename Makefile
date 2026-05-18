# =============================================================
# 파일위치 : ~/project1-aws/Makefile
# 팀 프로젝트 Makefile
# 사용법: make [명령어]
# =============================================================

.PHONY: help setup check init plan apply destroy output clean

# 기본 실행 (make 입력 시)
help:
	@echo ""
	@echo "============================================="
	@echo "   팀 프로젝트 명령어 목록 (Project Root 실행)"
	@echo "   make 명령어 실행 위치: ~/project1-aws/"
	@echo "============================================="
	@echo ""
	@echo "  [ 초기 설정 ]"
	@echo "  make setup    AWS CLI + Terraform + Ansible 설치"
	@echo "  make check    환경 및 자격증명 상태 확인"
	@echo ""
	@echo "  [ Terraform ]"
	@echo "  make init     Terraform 초기화"
	@echo "  make plan     인프라 변경 미리보기 (실제 적용 안 함)"
	@echo "  make apply    인프라 생성 + Ansible 자동 실행"
	@echo "  make output   생성된 서버 IP 주소 출력"
	@echo "  make destroy  인프라 전체 삭제 (비용 절감)"
	@echo ""
	@echo "  [ 정리 ]"
	@echo "  make clean    자동 생성 파일 삭제 (pem, inventory 등)"
	@echo ""

# ── 초기 설정 ─────────────────────────────────────────────
setup:
	@echo "권한 설정 및 환경 설치 시작..."
	@chmod +x setup.sh check.sh   # 실행 전 권한을 강제로 부여 (안전장치)
	./setup.sh

check:
	@chmod +x check.sh           # check만 따로 실행할 경우를 대비한 안전장치
	@echo "환경 상태 확인 중..."
	./check.sh

# ── Terraform ─────────────────────────────────────────────
init:
	cd terraform && terraform init

plan:
	cd terraform && terraform plan

# 병렬 작업을 3개로 제한하고 자동 승인 옵션 추가
apply:
	cd terraform && terraform apply --auto-approve -parallelism=3

output:
	@echo ""
	@echo "=== 생성된 서버 IP 주소 ==="
	cd terraform && terraform output
	@echo ""

# 삭제 시에도 자동 승인 옵션 추가
destroy:
	@echo ""
	@echo "⚠️  모든 인프라가 삭제됩니다."
	@echo "   실습 후 반드시 실행하여 비용을 절감하세요."
	@echo ""
	cd terraform && terraform destroy --auto-approve

# ── 정리 ──────────────────────────────────────────────────
clean:
	@echo "자동 생성 파일 삭제 중..."
	# Terraform이 생성한 키 파일
	rm -f terraform/*.pem
	rm -f ansible/roles/common/files/*.pem.pub
	# Terraform이 생성한 Ansible 실행 파일
	rm -f terraform/inventory.yml
	rm -f terraform/ansible.cfg
	# Terraform state 파일
	rm -f terraform/terraform.tfstate
	rm -f terraform/terraform.tfstate.backup
	# Terraform 초기화 파일
	rm -rf terraform/.terraform
	rm -f terraform/.terraform.lock.hcl
	@echo "정리 완료"