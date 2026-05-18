# project1-aws — 첫 배포 실행 매뉴얼

> **상황**: terraform, ansible, AWS CLI 모두 미설치 상태에서 시작  
> **목표**: `make apply`로 인프라 + Ansible 자동 배포까지  
> **소요 시간**: 약 15~20분 (네트워크 속도에 따라)

---

## 📋 전체 흐름

```
[Phase 1] 코드 받기                       (2분)
   ↓
[Phase 2] 환경 도구 설치                  (5분)
   ↓
[Phase 3] AWS 자격증명 + Slack 설정       (3분)
   ↓
[Phase 4] 수정된 파일 적용                (2분)
   ↓
[Phase 5] 환경 점검                       (1분)
   ↓
[Phase 6] 인프라 배포                     (7분)
   ↓
[Phase 7] 동작 확인                       (3분)
   ↓
[Phase 8] 사용 후 destroy                 (5분)
```

---

## Phase 1: 코드 받기

### Step 1-1. GitHub SSH 키 등록 확인

```bash
ssh -T git@github.com
```

기대 응답:
```
Hi <username>! You've successfully authenticated, but GitHub does not provide shell access.
```

만약 실패하면 GitHub SSH 키 등록 (Settings → SSH and GPG keys) 필요.

### Step 1-2. 레포 클론 + 브랜치 전환

```bash
cd ~
git clone git@github.com:EchoChallengers/project1-aws.git
cd project1-aws

# 본인 작업 브랜치로 전환 (신준한이라면 dev)
git checkout dev
git pull origin dev
```

### Step 1-3. 실행 권한 부여

```bash
chmod +x setup.sh check.sh chaos/inject.sh
```

---

## Phase 2: 환경 도구 설치

### Step 2-1. setup.sh로 일괄 설치

```bash
bash setup.sh
```


설치 진행 항목 (자동):
- AWS CLI v2 (`/usr/local/bin/aws`)
- Terraform (~1.14.x)
- Ansible (core 2.16+)

### Step 2-2. 설치 확인

```bash
aws --version          # aws-cli/2.x.x
terraform -version     # Terraform v1.14.x 이상 버전 OK!
ansible --version      # ansible [core 2.16.x] 이상
```

> ⚠️ Rocky Linux 8 외 환경(Ubuntu, macOS 등)에서는 setup.sh가 실패할 수 있어요. 수동 설치 안내는 setup.sh 상단 주석 참고.

---

## Phase 3: AWS 자격증명 + Slack 설정

### Step 3-1. AWS Access Key 발급

1. AWS 콘솔 로그인 → IAM → Users → 본인 계정 클릭
2. **Security credentials** 탭
3. **Access keys** 섹션 → **Create access key**
4. Use case: **Command Line Interface (CLI)** 선택
5. 키 ID + Secret Key 복사 (Secret은 이 화면에서만 확인 가능)

### Step 3-2. aws configure 실행

```bash
aws configure
```

입력:
```
AWS Access Key ID     : [발급받은 Access Key ID]
AWS Secret Access Key : [발급받은 Secret Access Key]
Default region name   : ap-northeast-2
Default output format : json
```

### Step 3-3. 자격증명 동작 확인

```bash
aws sts get-caller-identity
```

기대 응답:
```json
{
    "UserId": "...",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/(콘솔 로그인 ID명)"
}
```

### Step 3-4. Slack Webhook URL 발급 (2개 필요)

1. [api.slack.com/apps](https://api.slack.com/apps) → **Create New App** → From scratch
2. App name: `project1-monitoring`, Workspace 선택
3. 좌측 **Incoming Webhooks** → **Activate Incoming Webhooks** ON
4. **Add New Webhook to Workspace**
   - 채널 1: `#monitoring` → URL 복사 (이걸 `default`로)
   - 다시 **Add New Webhook to Workspace** 클릭
   - 채널 2: `#critical-alerts` → URL 복사 (이걸 `critical`로)

> 💡 `#critical-alerts` 채널이 없으면 Slack에서 먼저 생성

### Step 3-5. secrets.yml 작성

```bash
cp ansible/group_vars/secrets.yml.example \
   ansible/group_vars/secrets.yml

vi ansible/group_vars/secrets.yml
```

입력 내용 (실제 발급받은 URL로 교체):
```yaml
slack_webhook_default:  "https://hooks.slack.com/services/Txx/Bxx/실제URL1"
slack_webhook_critical: "https://hooks.slack.com/services/Txx/Bxx/실제URL2"
db_password:            "apppass123"
```

> ⚠️ `secrets.yml`은 `.gitignore`에 등록되어 있어서 GitHub에 절대 안 올라갑니다.

---

## Phase 4: 수정된 파일 적용 ⭐

> **이번 코드 리뷰에서 발견된 치명적 버그 3개**가 있어서, 다음 파일들로 교체해야 자동복구가 정상 동작합니다.

### Step 4-1. 3개 파일 교체

다음 파일들을 다운로드 받은 수정본으로 교체:

| 원본 경로 | 교체 대상 |
|---|---|
| `recovery/reference/webhook_server.py` | 다운로드한 `webhook_server.py` |
| `chaos/inject.sh` | 다운로드한 `inject.sh` |
| `ansible/group_vars/secrets.yml.example` | 다운로드한 `secrets.yml.example` |

**수정 내용 요약:**

| 파일 | 무엇이 바뀌었나 |
|---|---|
| `webhook_server.py` | (1) `ts` 변수 정의 위치를 분기 전으로 이동 (2) `run_ssh_command`에 `await` 추가 |
| `inject.sh` | (1) `ssh_exec`가 Private IP 자동 감지 → jump host 경유 (2) `db_public_ip` → `db_private_ip` (3) 사용법 메시지에 `benchmark` 추가 |
| `secrets.yml.example` | YAML 형식 오류 정리 |

### Step 4-2. 실행 권한 재부여 (inject.sh)

```bash
chmod +x chaos/inject.sh
```

### Step 4-3. 문법 검증 (선택)

```bash
# Python 문법
python3 -c "import ast; ast.parse(open('recovery/reference/webhook_server.py').read())" && echo "Python OK"

# Bash 문법
bash -n chaos/inject.sh && echo "inject.sh OK"

# YAML 문법
python3 -c "import yaml; yaml.safe_load(open('ansible/group_vars/secrets.yml.example'))" && echo "YAML OK"
```

세 줄 모두 OK 출력되면 적용 완료.

---

## Phase 5: 환경 점검

### Step 5-1. check.sh 실행

```bash
make check
```

체크리스트:
- ✅ AWS CLI 설치됨
- ✅ Terraform 설치됨
- ✅ Ansible 설치됨 (권장 버전 이상)
- ✅ AWS 자격증명 유효 + 리전 = `ap-northeast-2`
- ✅ 프로젝트 폴더 존재

모든 항목 ✅이면 다음으로.

### Step 5-2. secrets.yml 존재 확인

```bash
test -f ansible/group_vars/secrets.yml && echo "secrets.yml 존재 OK"
grep -q "여기에_" ansible/group_vars/secrets.yml && echo "⚠️ Slack URL 미입력!" || echo "Slack URL 입력 완료"
```

---

## Phase 6: 인프라 배포

### Step 6-1. Terraform 초기화 (최초 1회)

```bash
make init
```

또는:
```bash
cd terraform && terraform init && cd ..
```

기대 출력: `Terraform has been successfully initialized!`

### Step 6-2. 변경 미리보기 (실제 적용 안 함)

```bash
make plan
```

또는:
```bash
cd terraform && terraform plan && cd ..
```

기대 출력: `Plan: 37 to add, 0 to change, 0 to destroy.` (대략)

생성될 리소스:
- VPC 1 + Subnet 4 + Route Table 2 + Route Table Association 4 + IGW 1 + NAT GW 1 + EIP 1
- Security Group 3
- EC2 4 + Key Pair 1
- ALB 1 + Target Group 1 + Listener 1 + Attachments 2
- IAM Role 1 + Instance Profile 1
- Local file 4

### Step 6-3. 실제 배포 ⭐

```bash
make apply
```

또는:
```bash
cd terraform && terraform apply --auto-approve -parallelism=3 && cd ..
```

진행 단계:
```
[1단계] VPC, Subnet, SG 생성        ← 약 30초
[2단계] EC2 4대 + ALB + NAT 생성    ← 약 90초  
[3단계] SSH 접속 대기 (60초)        ← 자동 sleep
[4단계] Ansible 실행                ← 약 3~4분
  - common role (4대 모두)
  - web servers (rocky 2대)
  - mgmt server (monitoring 스택)
  - db server (PostgreSQL)
```

전체 소요: 약 5~7분

중간에 에러날 경우, 다음의 코드 순서대로 입력 
```bash
cd ~/project1-aws
make destroy
make clean
make init
make apply
```

### Step 6-4. 배포 완료 확인

```bash
make output
```

출력 예시:
```
alb_dns_name     = "proj-alb-xxx.ap-northeast-2.elb.amazonaws.com"
alb_url          = "http://proj-alb-xxx.ap-northeast-2.elb.amazonaws.com"
mgmt_public_ip   = "x.x.x.x"
grafana_url      = "http://x.x.x.x:3000"
prometheus_url   = "http://x.x.x.x:9090"
alertmanager_url = "http://x.x.x.x:9093"
web1_public_ip   = "x.x.x.x"
web2_public_ip   = "x.x.x.x"
db_private_ip    = "10.0.11.x"
```

> 💡 이 IP들을 기록해 두세요. 다음 단계에서 사용합니다.

---

## Phase 7: 동작 확인

### Step 7-1. ALB 헬스체크

```bash
curl -s $(cd terraform && terraform output -raw alb_url)/health
```

기대:
```json
{"status":"ok","server":"...","database":"connected"}
```

### Step 7-2. 로드밸런싱 확인 (5번 새로고침)

```bash
for i in {1..5}; do curl -s $(cd terraform && terraform output -raw alb_url)/test | grep -o 'Server Name: <span class="highlight">[^<]*' ; done
```

기대: `web1`과 `web2`가 번갈아 나타남

### Step 7-3. 모니터링 대시보드 접속

브라우저에서:

| 서비스 | URL | 계정 |
|---|---|---|
| Grafana | `make output`에서 `grafana_url` | admin / admin (첫 로그인 시 변경) |
| Prometheus | `make output`에서 `prometheus_url` | - |
| AlertManager | `make output`에서 `alertmanager_url` | - |

확인:
- Prometheus → Status → Targets: 모두 **UP**
- Grafana → Connections → Data sources → Prometheus: ✅ 자동 등록됨

### Step 7-4. 자동복구 동작 확인

```bash
# 전체 서비스 상태 (DB가 jump host 경유 잘 되는지 확인)
./chaos/inject.sh status
```

기대 출력:
```
=== AWS 서비스 상태 ===
  FastAPI web1 : active
  Nginx   web1 : active
  FastAPI web2 : active
  Nginx   web2 : active
  PostgreSQL   : active     ← DB가 active이면 jump host 정상
  Prometheus   : active
  Grafana      : active
  AlertManager : active
  Recovery     : active
```

만약 **PostgreSQL : 접속실패**이면 jump host 로직 점검 필요 (`MGMT_IP` 변수 등).

### Step 7-5. CPU 부하 + 자동복구 시연

```bash
./chaos/inject.sh cpu_both
```

약 1~2분 후 Slack `#critical-alerts` 채널에:
1. `[CRITICAL] HighCPU` 알림
2. `자동복구 시작: HighCPU 서버: ...`
3. `복구 완료 ✅: HighCPU | CPU 정상화 확인@...`

이 3개 메시지가 모두 도착하면 **모든 시스템 정상**입니다.

---

## Phase 8: 사용 후 destroy ⚠️ 필수

### Step 8-1. 인프라 삭제

```bash
make destroy
```

또는:
```bash
cd terraform && terraform destroy --auto-approve && cd ..
```

> ⚠️ **비용 주의:**  
> EC2 4대 + ALB + NAT Gateway는 시간당 비용 발생  
> - NAT Gateway는 프리티어 미적용 (시간당 $0.059 + 데이터 $0.059/GB)  
> - 미사용 시간이 길어지면 한 달에 $30~$50까지 발생 가능  
> **실습 끝나면 반드시 destroy**

### Step 8-2. 자동 생성 파일 정리 (선택)

```bash
make clean
```

삭제 대상:
- `terraform/proj-key.pem`
- `terraform/inventory.yml`
- `terraform/ansible.cfg`
- `terraform/terraform.tfstate*`
- `terraform/.terraform/`

> 💡 다음 배포 시에는 `make init`부터 다시 시작

---

## 🚨 문제 발생 시 빠른 대응

### Q1. `make apply` 도중 Ansible이 실패

```bash
# 실패한 시점부터 다시 실행 (인프라는 그대로)
cd terraform
ANSIBLE_SSH_PIPELINING=1 ansible-playbook -i inventory.yml ../ansible/site.yml
```

### Q2. 특정 EC2에 SSH로 접속해서 디버깅

```bash
# Public 서버 (web1, web2, mgmt)
ssh -i terraform/proj-key.pem ec2-user@$(cd terraform && terraform output -raw web1_public_ip)

# DB 서버 (Private, jump host 경유)
ssh -i terraform/proj-key.pem \
    -o "ProxyCommand=ssh -i terraform/proj-key.pem -W %h:%p ec2-user@$(cd terraform && terraform output -raw mgmt_public_ip)" \
    ec2-user@$(cd terraform && terraform output -raw db_private_ip)
```

### Q3. webhook_server 동작 안 함

```bash
# mgmt 서버 접속 후
sudo systemctl status recovery
sudo journalctl -u recovery -n 50 --no-pager

# .env 확인
sudo cat /opt/recovery/.env
```

### Q4. 비용이 걱정될 때 — 부분 정지

EC2만 stop (NAT GW는 계속 비용 발생):
```bash
# 인스턴스 ID 확인
aws ec2 describe-instances --filters "Name=tag:Name,Values=proj-*" --query "Reservations[].Instances[].InstanceId" --output text

# 중지
aws ec2 stop-instances --instance-ids i-xxxx i-yyyy i-zzzz i-wwww

# 다시 시작
aws ec2 start-instances --instance-ids i-xxxx i-yyyy i-zzzz i-wwww
```

> ⚠️ EC2 stop/start 시 **Public IP가 바뀝니다**. `terraform apply`로 inventory.yml 재생성 권장.  
> 그래서 **destroy + apply가 더 깔끔**한 경우가 많아요.

---

## 📌 정리 — 최초 1회 실행 순서

```bash
# 1. 코드 받기
cd ~
git clone git@github.com:EchoChallengers/project1-aws.git
cd project1-aws
git checkout dev
chmod +x setup.sh check.sh chaos/inject.sh

# 2. 환경 도구 설치
make setup

# 3. AWS 자격증명
aws configure
aws sts get-caller-identity

# 4. Slack URL 등록
cp ansible/group_vars/secrets.yml.example ansible/group_vars/secrets.yml
vi ansible/group_vars/secrets.yml   # Slack URL 2개 입력

# 5. 수정된 파일 3개 교체 (Phase 4 참고)

# 6. 환경 점검
make check

# 7. 배포
make init
make plan
make apply

# 8. 동작 확인
make output
./chaos/inject.sh status
./chaos/inject.sh cpu_both          # 자동복구 시연

# 9. 사용 후 삭제 (필수!)
make destroy
```

---

*문서 작성: 2026-05-11*