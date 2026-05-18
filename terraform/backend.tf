# project1-aws/terraform/backend.tf

# ──────────────────────────────────────────────
# [고려사항 3] Terraform State 로컬 관리 명시
#
# 이 프로젝트는 팀원 각자의 개인 AWS 계정에서 독립적으로 실행합니다.
# 따라서 state 파일은 각자의 로컬에서 관리합니다.
#
# ❌ remote backend (S3) 사용 금지
#    → 한 사람의 state가 다른 팀원에게 영향을 줄 수 있음
#    → 공유 비용이 발생함
#
# ✅ 로컬 state 사용 (기본값)
#    → terraform.tfstate 파일이 각자 로컬에 생성됨
#    → .gitignore에 반드시 추가해서 GitHub에 올라가지 않도록 주의
# ──────────────────────────────────────────────
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}