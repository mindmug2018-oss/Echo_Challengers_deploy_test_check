# project1-aws/terraform/variables.tf

# ──────────────────────────────────────────────
# [고려사항 1] AMI ID 명시적 고정
# 최신 AMI 자동 검색 대신 검증된 AMI ID를 변수로 고정합니다.
# 팀원 전체가 동일한 OS 환경에서 실행되도록 보장합니다.
#
# AMI ID 확인 방법:
# aws ec2 describe-images \
#   --region ap-northeast-2 \
#   --owners amazon \
#   --filters "Name=name,Values=al2023-ami-*-x86_64" \
#             "Name=state,Values=available" \
#   --query "sort_by(Images,&CreationDate)[-1].[ImageId,Name]" \
#   --output table
# ──────────────────────────────────────────────
variable "ami_id" {
  description = <<-EOT
    Amazon Linux 2023 AMI ID (ap-northeast-2 서울 리전 고정)
    팀원 전체 동일 버전 사용을 위해 명시적으로 고정합니다.
    변경이 필요한 경우 팀 전체 합의 후 업데이트하세요.
    확인: aws ec2 describe-images --region ap-northeast-2 \
          --owners amazon \
          --filters "Name=name,Values=al2023-ami-*-x86_64" \
          --query "sort_by(Images,&CreationDate)[-1].ImageId" \
          --output text
  EOT
  type        = string
  default     = "ami-0b6cacee0430cdb2c" # al2023-ami-2023.11.20260509.0 (Amazon Linux 2023, kernel 6.1)
}

variable "instance_type" {
  description = "EC2 인스턴스 타입 (프리티어: t2.micro)"
  type        = string
  default     = "t3.micro"
}

variable "region" {
  description = "AWS 리전 (팀 전체 서울 리전 고정)"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "프로젝트 이름 (리소스 태그에 사용)"
  type        = string
  default     = "proj-aws"
}

variable "vpc_cidr" {
  description = "VPC CIDR 블록 (전체 사설 IP 대역)"
  type        = string
  default     = "10.0.0.0/16"
}


# ──────────────────────────────────────────────────────────
# ~/project1-aws/terraform/terraform.tfvars.example 파일 참조
# ~/project1-aws/terraform/ 에 terraform.tfvars 파일 생성
# tailnet_name, tailscale_auth_key, tailscale_api_key 입력
# ──────────────────────────────────────────────────────────

variable "tailnet_name" {
  description = "Tailscale Organization 이름(가입한 이메일 주소)"
  type        = string
}

variable "tailscale_auth_key" {
  description = "Tail Scale Auth Key"
  type        = string
  sensitive   = true
}

variable "tailscale_api_key" {
  description = "Tail Scale API Key"
  type        = string
  sensitive   = true
}

variable "slack_webhook_monitoring" {
  description = "Slack webhook URL for monitoring alerts"
  type        = string
  sensitive   = true
  default     = ""
}

variable "slack_webhook_recovery" {
  description = "Slack webhook URL for recovery notifications"
  type        = string
  sensitive   = true
  default     = ""
}