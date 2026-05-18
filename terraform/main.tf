# project1-aws/terraform/main.tf

# ──────────────────────────────────────────────
# 버전 고정 (팀 프로젝트 표준)
# ──────────────────────────────────────────────
terraform {
  required_version = ">= 1.14.0, < 2.0.0"
  required_providers {
    aws       = { source = "hashicorp/aws", version = "~> 6.0" }
    tls       = { source = "hashicorp/tls", version = "~> 4.0" }
    local     = { source = "hashicorp/local", version = "~> 2.0" }
    tailscale = { source = "tailscale/tailscale", version = "~> 0.17" }
  }
}

# ──────────────────────────────────────────────
# 1. 네트워크 구성
# ──────────────────────────────────────────────

provider "aws" {
  region = var.region
}

# Tailscale Provider 등록 (변수 등록 필요)
provider "tailscale" {
  api_key = var.tailscale_api_key
  tailnet = var.tailnet_name
}

locals {
  # tailscale 이 사용할 서버 host name
  host_name = "${var.project_name}-mgmt"
}

# Mgmt 서버가 자동으로 가입할 때 사용할 Auth Key 생성
resource "tailscale_tailnet_key" "ec2_join_key" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = 3600
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Public Subnets
resource "aws_subnet" "public_az1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-public-az1" }
}

resource "aws_subnet" "public_az2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-public-az2" }
}

# Private Subnets
resource "aws_subnet" "private_az1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = { Name = "${var.project_name}-private-az1" }
}

resource "aws_subnet" "private_az2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags              = { Name = "${var.project_name}-private-az2" }
}

# Routing
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public_az1" {
  subnet_id      = aws_subnet.public_az1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_az2" {
  subnet_id      = aws_subnet.public_az2.id
  route_table_id = aws_route_table.public_rt.id
}

# ──────────────────────────────────────────────
# NAT Instance (비용 절감: NAT GW → t3.micro EC2)
# 이유: 학습/시연 환경에서 비용 78% 절감 ($43/월 → $9.4/월)
# 트레이드오프: 단일 장애 지점(SPOF), 운영 환경에는 부적합
# ──────────────────────────────────────────────

# NAT Instance용 Security Group
resource "aws_security_group" "nat_sg" {
  name   = "${var.project_name}-nat-sg"
  vpc_id = aws_vpc.main.id

  # SSH 관리용
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # VPC 내부 트래픽 전면 허용 (NAT 역할의 핵심)
  # Private Subnet에서 NAT로 들어오는 모든 트래픽 통과
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # Private Subnet에서 나가는 임의 트래픽
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-nat-sg" }
}

# NAT Instance EC2 (Public Subnet에 배치)
resource "aws_instance" "nat_ec2" {
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_az1.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.nat_sg.id]
  key_name                    = aws_key_pair.kp.key_name

  # NAT 인스턴스 필수 설정
  # 이유: 자기 IP가 아닌 패킷도 받아서 전달하기 위해
  source_dest_check = false

  # 부팅 시 NAT 설정 (iptables MASQUERADE)
  user_data = <<-EOF
    #!/bin/bash
    set -eux

    # 1. IP 포워딩 활성화
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-nat.conf
    sysctl -p /etc/sysctl.d/99-nat.conf

    # 2. iptables 설치 및 포워딩 허용
    dnf install -y iptables iptables-services
    systemctl enable --now iptables
    iptables -P FORWARD ACCEPT
    iptables -I FORWARD -j ACCEPT

    # 3. 내부망(10.0.0.0/16) → 인터넷 마스커레이드
    iptables -t nat -A POSTROUTING -s ${var.vpc_cidr} -j MASQUERADE
    service iptables save
  EOF

  tags = { Name = "${var.project_name}-nat-instance", Role = "nat" }
}

# Private Subnet 라우팅 테이블 — 인터넷 트래픽을 NAT Instance로
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.nat_ec2.primary_network_interface_id
  }
  tags = { Name = "${var.project_name}-private-rt" }
}

# Private Subnet들을 Private 라우팅 테이블에 연결
resource "aws_route_table_association" "private_az1" {
  subnet_id      = aws_subnet.private_az1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_az2" {
  subnet_id      = aws_subnet.private_az2.id
  route_table_id = aws_route_table.private_rt.id
}

# ──────────────────────────────────────────────────────
# Tailscale 하이브리드 라우팅 (AWS -> VMware 172.16.1.0/24)
# ──────────────────────────────────────────────────────
# Public Subnet에서 172.16.1.0/24 로 갈 때 aws-mgmt 서버를 거치도록 설정
resource "aws_route" "to_onpremise_public" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "172.16.1.0/24"
  network_interface_id   = aws_instance.mgmt.primary_network_interface_id
}

# Private Subnet에서 172.16.1.0/24 로 갈 때 aws-mgmt 서버를 거치도록 설정
resource "aws_route" "to_onpremise_private" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "172.16.1.0/24"
  network_interface_id   = aws_instance.mgmt.primary_network_interface_id
}


# ──────────────────────────────────────────────
# 2. SSH 키 관리
# ──────────────────────────────────────────────

resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "kp" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.pk.public_key_openssh
}

resource "local_file" "ssh_key" {
  filename        = "${path.module}/${var.project_name}-key.pem"
  content         = tls_private_key.pk.private_key_pem
  file_permission = "0600"
}

# 공개키 저장 전에 폴더가 없으면 자동 생성
resource "terraform_data" "create_common_files_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/../ansible/roles/common/files"
  }
}

resource "local_file" "ssh_pub_key" {
  # ~/project1-aws/ansible/roles/common/files 경로에 직접 저장
  filename        = "${path.module}/../ansible/roles/common/files/${var.project_name}-key.pem.pub"
  content         = tls_private_key.pk.public_key_openssh
  file_permission = "0644"
}

# ──────────────────────────────────────────────
# 3. 보안 그룹 (포트별 상세 주석 추가)
# ──────────────────────────────────────────────

# 웹서버용 보안 그룹
resource "aws_security_group" "web_sg" {
  name   = "${var.project_name}-web-sg"
  vpc_id = aws_vpc.main.id
  # SSH 원격 접속
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # HTTP 웹 서비스 (Nginx)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Application 서버 (FastAPI 등)
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Prometheus Node Exporter (모니터링 데이터 수집)
  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Nginx Exporter (nginx 메트릭 수집)
  ingress {
    description = "Allow nginx exporter from VPC"
    from_port   = 9113
    to_port     = 9113
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # 외부로 나가는 모든 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-web-sg" }
}

# Mgmt 서버용 보안 그룹
resource "aws_security_group" "mgmt_sg" {
  name   = "${var.project_name}-mgmt-sg"
  vpc_id = aws_vpc.main.id
  # SSH 원격 접속
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Prometheus 웹 UI
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Grafana 대시보드
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Alertmanager (경고 알림 관리)
  ingress {
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Loki (로그 수집 서버)
  ingress {
    from_port   = 9080
    to_port     = 9080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  # Mgmt 서버 자체 모니터링 (Node Exporter)
  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  # 외부로 나가는 모든 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-mgmt-sg" }
}

# DB용 보안 그룹
resource "aws_security_group" "db_sg" {
  name   = "${var.project_name}-db-sg"
  vpc_id = aws_vpc.main.id
  # PostgreSQL 데이터베이스 접속
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  # VPC 내부 SSH (웹/매니지먼트 서버로부터의 접속)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  # DB 서버 모니터링 (Node Exporter)
  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  # 외부로 나가는 모든 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-db-sg" }
}

# ──────────────────────────────────────────────
# 4. IAM Role & Profile
# ──────────────────────────────────────────────

resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# s3 사용시 주석 해제
# resource "aws_iam_role_policy_attachment" "s3_access" {
#   role       = aws_iam_role.ec2_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
# }

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}


# ──────────────────────────────────────────────
# 5. EC2 생성 (Mgmt 서버 Tailscale 연동 반영)
# ──────────────────────────────────────────────

resource "aws_instance" "mgmt" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_az1.id
  vpc_security_group_ids = [aws_security_group.mgmt_sg.id]
  key_name               = aws_key_pair.kp.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  # 다른 EC2의 패킷을 받아 Tailscale로 넘겨야 하므로 필수!
  source_dest_check = false

  # Tailscale 자동 설치 및 설정 (Subnet Router)
  user_data = <<-EOF
    #!/bin/bash
    exec > >(tee -a /var/log/user_data_tailscale.log) 2>&1

    # 1. 호스트네임 설정 (테라폼이 장비를 쉽게 찾게 하기 위함)
    hostnamectl set-hostname "${local.host_name}"
    echo "127.0.0.1 ${local.host_name}" >> /etc/hosts

    # 2. 인터넷 대기 (NAT 준비 대기)
    until ping -c 1 8.8.8.8 &> /dev/null; do
        sleep 5
    done

    # 3. Tailscale 설치
    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable --now tailscaled

    # 4. IP Forwarding 활성화
    cat <<EOT > /etc/sysctl.d/99-tailscale.conf
    net.ipv4.ip_forward = 1
    net.ipv6.conf.all.forwarding = 1
    EOT
    sysctl -p /etc/sysctl.d/99-tailscale.conf

    # 5. Tailscale 가입 및 AWS 대역(10.0.0.0/16) 광고
    # --accept-routes=true를 통해 proj-mgmt(VMware)가 광고하는 172.16.1.0/24를 받아옵니다.
    tailscale up --authkey=${tailscale_tailnet_key.ec2_join_key.key} \
                 --advertise-routes=${var.vpc_cidr} \
                 --accept-routes=true
  EOF
  tags      = { Name = "${var.project_name}-mgmt", Role = "management" }
}

# ──────────────────────────────────────────────
# Mgmt 서버 Tailscale Route 자동 승인
# ──────────────────────────────────────────────
# 테라폼이 기기를 찾고 라우팅을 승인하는 부분
data "tailscale_device" "mgmt_device" {
  hostname   = local.host_name
  wait_for   = "180s" # 기기가 Tailscale에 등록될 때까지 대기
  depends_on = [aws_instance.mgmt]
}
# vpc 로 가는 길 뚫어 주기
resource "tailscale_device_subnet_routes" "approve_vpc_routes" {
  device_id = data.tailscale_device.mgmt_device.id
  routes    = [var.vpc_cidr]
}

resource "aws_instance" "web1" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_az1.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = aws_key_pair.kp.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  tags                   = { Name = "${var.project_name}-web1", Role = "webserver" }
}

resource "aws_instance" "web2" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_az2.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = aws_key_pair.kp.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  tags                   = { Name = "${var.project_name}-web2", Role = "webserver" }
}

resource "aws_instance" "db" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_az1.id
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  key_name               = aws_key_pair.kp.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  tags                   = { Name = "${var.project_name}-db", Role = "database" }
}

# ──────────────────────────────────────────────
# 6. ALB 구성
# ──────────────────────────────────────────────

resource "aws_lb" "alb" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.public_az1.id, aws_subnet.public_az2.id]
  tags               = { Name = "${var.project_name}-alb" }
}

resource "aws_lb_target_group" "web_tg" {
  name     = "${var.project_name}-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 10
  }
}

resource "aws_lb_target_group_attachment" "web1" {
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = aws_instance.web1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "web2" {
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = aws_instance.web2.id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# ──────────────────────────────────────────────
# 7. Ansible 파일 자동 생성 및 실행 (수업 패턴 유지)
# ──────────────────────────────────────────────

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/inventory.yml"
  content = yamlencode({
    all = {
      vars = {
        # group_vars/all.yml의 내용을 inventory에 직접 포함
        # 이유: Ansible이 terraform/ 디렉토리에서 실행되어 ansible/group_vars/를 못 찾음
        project_name = var.project_name
        vpc_cidr     = var.vpc_cidr
        db_name      = "appdb"
        db_user      = "appuser"
      }
      children = {
        mgmt = {
          hosts = {
            "${aws_instance.mgmt.public_ip}" = {
              ansible_user                 = "ec2-user"
              ansible_ssh_private_key_file = "./${var.project_name}-key.pem"
              private_ip                   = "${aws_instance.mgmt.private_ip}"
            }
          }
        }
        webservers = {
          hosts = {
            "${aws_instance.web1.public_ip}" = {
              ansible_user                 = "ec2-user"
              ansible_ssh_private_key_file = "./${var.project_name}-key.pem"
              private_ip                   = "${aws_instance.web1.private_ip}"
            }
            "${aws_instance.web2.public_ip}" = {
              ansible_user                 = "ec2-user"
              ansible_ssh_private_key_file = "./${var.project_name}-key.pem"
              private_ip                   = "${aws_instance.web2.private_ip}"
            }
          }
        }
        databases = {
          hosts = {
            "${aws_instance.db.private_ip}" = {
              ansible_user                 = "ec2-user"
              ansible_ssh_private_key_file = "./${var.project_name}-key.pem"
              private_ip                   = "${aws_instance.db.private_ip}"
              ansible_ssh_common_args      = "-o ProxyCommand='ssh -i ./${var.project_name}-key.pem -o StrictHostKeyChecking=no -W %h:%p ec2-user@${aws_instance.mgmt.public_ip}'"
            }
          }
        }
      }
    }
  })
}

resource "local_file" "ansible_config" {
  filename = "${path.module}/ansible.cfg"
  content  = <<-EOF
    [defaults]
    inventory         = ./inventory.yml
    host_key_checking = False
    remote_user       = ec2-user
    private_key_file  = ./${var.project_name}-key.pem
    roles_path        = ../ansible/roles
    # group_vars 위치 명시 (terraform/ 에서 실행되므로 상위 경로 지정)
    # 이유: secrets.yml의 db_password, slack URL을 못 찾는 문제 해결
    inventory_plugins = ../ansible/plugins/inventory
    
    stdout_callback   = yaml

    [privilege_escalation]
    become          = True
    become_method   = sudo
    become_user     = root
    become_ask_pass = False
  EOF
}

resource "terraform_data" "wait_for_instance" {
  depends_on       = [aws_instance.mgmt, aws_instance.web1, aws_instance.web2, aws_instance.db, local_file.ansible_inventory, local_file.ansible_config]
  triggers_replace = [aws_instance.mgmt.id, aws_instance.web1.id, aws_instance.web2.id, aws_instance.db.id]
  provisioner "local-exec" { command = "sleep 60" }
}

resource "terraform_data" "ansible_run" {
  depends_on = [terraform_data.wait_for_instance]
  
  triggers_replace = {
    instance_ids = join(",", [aws_instance.mgmt.id, aws_instance.web1.id, aws_instance.web2.id, aws_instance.db.id])
    always_run   = timestamp()
  }

  provisioner "local-exec" {
    # group_vars/*.yml을 명시적으로 -e 옵션으로 주입
    # 이유: terraform/ 디렉토리에서 실행되어 ../ansible/group_vars/를 자동으로 못 찾음
    command = <<EOT
      ANSIBLE_SSH_PIPELINING=1 ansible-playbook \
        -i inventory.yml \
        -e @../ansible/group_vars/all.yml \
        $([ -f ../ansible/group_vars/secrets.yml ] && echo "-e @../ansible/group_vars/secrets.yml" || echo "-e db_password=$DB_PASSWORD_SECRET") \
        ../ansible/site.yml
    EOT
  }
}
