# project1-aws — 팀 공통 인프라 코드

각자의 AWS 계정에서 이 코드를 실행하면 동일한 인프라가 자동으로 구축됩니다.

---

## 📑 목차

- [🏗️ 아키텍처](#️-아키텍처)
- [📁 폴더 구조](#-폴더-구조)
- [👥 팀 구성 및 담당](#-팀-구성-및-담당)
- [🌱 Git 협업 워크플로우](#-git-협업-워크플로우)
- [🚀 시작하기 (최초 1회)](#-시작하기-최초-1회)
- [⚙️ 인프라 배포](#️-인프라-배포)
- [🔍 시연 및 동작 확인](#-시연-및-동작-확인)
- [🛠️ 장애 시나리오 시연](#️-장애-시나리오-시연)
- [🔐 보안 설정](#-보안-설정)
- [❗ 트러블슈팅](#-트러블슈팅)

---

## 🏗️ 아키텍처

```
                    인터넷
                       │
                       ▼
              ┌────────────────┐
              │      ALB       │  ← Application Load Balancer (HTTP :80)
              └────────┬───────┘
                       │
        ┌──────────────┴──────────────┐
        │                             │
        ▼                             ▼
  ┌──────────┐                  ┌──────────┐
  │   web1   │                  │   web2   │  ← Nginx + FastAPI
  │ (AZ1)    │                  │ (AZ2)    │     + Node Exporter
  │ Public   │                  │ Public   │
  └────┬─────┘                  └────┬─────┘
       │                             │
       │     ┌──────────────────┐    │
       │     │      mgmt        │    │
       │     │     (AZ1)        │    │  ← Prometheus + Grafana
       │     │     Public       │    │     + AlertManager
       │     │                  │    │     + Recovery Webhook
       │     └─────────┬────────┘    │
       │               │             │
       │     ┌─────────▼────────┐    │
       │     │    NAT Gateway   │    │  ← Private 서버의 인터넷 경유
       │     └─────────┬────────┘    │
       │               │             │
       └───────────────┼─────────────┘
                       │
                       ▼
              ┌────────────────┐
              │      db        │  ← PostgreSQL 16
              │   (AZ1)        │     + Node Exporter
              │  Private       │
              └────────────────┘
```

### On-premise vs AWS 주요 차이

| 항목 | On-premise | AWS |
|---|---|---|
| 로드밸런서 | HAProxy (직접 설치) | ALB (관리형) |
| DB 위치 | Host-only `172.16.1.x` | Private Subnet `10.0.11.x` |
| SSH 키 | `project.pem` (수동 생성) | `proj-key.pem` (Terraform 자동 생성) |
| 네트워크 | VMware Host-only | VPC / Subnet (AZ 분리) |
| IP 관리 | 고정 IP | Terraform output 동적 확인 |
| DB 접근 | 직접 접속 | mgmt를 jump host로 경유 |
| 외부 노출 | Cloudflare Tunnel | ALB DNS 직접 |

---

## 📁 폴더 구조

```
project1-aws/
├── setup.sh                      ← AWS CLI + Terraform + Ansible 자동 설치
├── check.sh                      ← 환경 상태 확인
├── Makefile                      ← 자주 쓰는 명령어 단축키
├── README.md                     ← 이 파일
│
├── ansible/
│   ├── site.yml                  ← Ansible 전체 실행 진입점
│   ├── group_vars/
│   │   ├── all.yml               ← 공통 변수 (GitHub 관리)
│   │   ├── secrets.yml           ← Slack URL, DB 비밀번호 (gitignore)
│   │   └── secrets.yml.example   ← secrets.yml 작성 예시 (GitHub 관리)
│   ├── playbooks/
│   │   ├── db.yml
│   │   ├── web.yml
│   │   └── mgmt.yml              ← monitoring role 포함
│   └── roles/
│       ├── common/               ← user1 생성, vim/motd, 타임존
│       ├── fastapi/              ← Python 앱 배포
│       ├── monitoring/           ← Prometheus + Grafana + AlertManager + Recovery
│       ├── nginx/                ← FastAPI 리버스 프록시
│       ├── node_exporter/        ← OS 메트릭 수집기
│       └── postgresql/           ← DB + 테이블 자동 생성
│
├── terraform/
│   ├── main.tf                   ← 인프라 전체 정의 (VPC, EC2, ALB, NAT GW)
│   ├── variables.tf              ← AMI, instance type, admin IP 등
│   ├── outputs.tf                ← IP/DNS 출력 정의
│   ├── backend.tf                ← 로컬 state 명시
│   └── .gitignore
│
├── chaos/
│   ├── inject.sh                 ← 장애 주입 스크립트 (8가지 시나리오)
│   └── results/                  ← 응답시간 측정 결과 (gitignore)
│
└── recovery/
     ├── controller/               ← 공식 Recovery Controller 실행 구조
     │   ├── app.py
     │   ├── config/
     │   └── scripts/
     ├── reference/                ← 기존 webhook_server.py 참고 구현
     │   └── webhook_server.py
```

---

## 👥 팀 구성 및 담당

| 담당 영역 | 팀원 | 주요 파일 |
|---|---|---|
| **팀장 / 통합** | 조휘정 | `main` 브랜치 관리, PR 리뷰, 릴리즈 |
| **인프라 구축** | 신준한 (`dev`), 한지우 (`feature/*`) | `terraform/`, `ansible/roles/common/`, `ansible/roles/postgresql/`, `ansible/roles/fastapi/`, `ansible/roles/nginx/` |
| **장애 탐지·알림·복구** | 이지윤 (`feature/*`), 김민규 (`feature/*`) | `ansible/roles/monitoring/`, `recovery/`, `chaos/`, `ansible/roles/node_exporter/` |

### 브랜치 전략

```
main ──────────●─────────●─────────●─────────●─────  (조휘정, 보호 브랜치)
                ▲         ▲         ▲         ▲
                │PR       │PR       │PR       │PR
                │merge    │merge    │merge    │merge
dev ────────────●─────────●─────────●─────────●─────  (신준한)
                ▲         ▲         ▲
                │PR       │PR       │PR
                │merge    │merge    │merge
feature/* ──────●─────────●─────────●────────────── (한지우, 이지윤, 김민규)
```

**원칙:**
- `main`: 검증 완료된 코드만 (조휘정만 머지 권한)
- `dev`: 통합 테스트 브랜치 (신준한이 관리)
- `feature/*`: 각자 작업 브랜치 — `feature/추가-monitoring-alert`, `feature/fix-pg-hba` 등

---

## 🌱 Git 협업 워크플로우

### 🔹 STEP 1 · 최초 1회: 레포지토리 클론

```bash
# 1. SSH 키 등록 확인 (GitHub Settings → SSH keys)
ssh -T git@github.com
# Hi <username>! You've successfully authenticated...

# 2. 클론
git clone git@github.com:EchoChallengers/project1-aws.git
cd project1-aws

# 3. 본인 정보 설정 (선택, 글로벌이 아닌 이 레포만)
git config user.name "본인이름"
git config user.email "본인@email.com"

# 4. 현재 브랜치 확인
git branch -a
# * main
#   remotes/origin/main
#   remotes/origin/dev
```

---

### 🔹 STEP 2 · 작업 시작: 본인 작업 브랜치 만들기

#### 신준한 (dev 브랜치 작업)

```bash
# dev 브랜치로 전환 + 최신화
git checkout dev
git pull origin dev

# 작업 시작 (dev에서 바로)
```

#### 한지우, 이지윤, 김민규 (feature 브랜치 작업)

```bash
# 1. 최신 dev 기반으로 feature 브랜치 생성
git checkout dev
git pull origin dev
git checkout -b feature/작업명

# 예시:
# git checkout -b feature/add-grafana-dashboard
# git checkout -b feature/fix-pg-hba-cidr
# git checkout -b feature/add-cpu-recovery-polling
```

**브랜치 이름 규칙:**

| 작업 종류 | 접두사 | 예시 |
|---|---|---|
| 새 기능 추가 | `feature/` | `feature/add-grafana-dashboard` |
| 버그 수정 | `fix/` | `fix/pg-hba-cidr-mismatch` |
| 문서 작업 | `docs/` | `docs/update-readme` |
| 리팩터링 | `refactor/` | `refactor/extract-vpc-cidr-var` |

---

### 🔹 STEP 3 · 작업 중: 변경사항 commit

```bash
# 1. 변경된 파일 확인
git status
git diff

# 2. 변경 파일 stage
git add <변경한_파일>
# 또는 전체 변경 stage
git add .

# 3. commit (메시지 컨벤션 준수)
git commit -m "feat: Grafana CPU 대시보드 패널 추가

- node_cpu_seconds_total 쿼리 추가
- 응답시간 패널과 나란히 배치
- annotation으로 firing 시점 표시"
```

**Commit 메시지 컨벤션 (Conventional Commits):**

| 접두사 | 용도 | 예시 |
|---|---|---|
| `feat:` | 새 기능 추가 | `feat: HighCPU 자동복구 추가` |
| `fix:` | 버그 수정 | `fix: pg_hba CIDR을 10.0.0.0/16으로 수정` |
| `docs:` | 문서 변경 | `docs: README에 git 워크플로우 추가` |
| `refactor:` | 동작 변경 없는 리팩터링 | `refactor: VPC CIDR을 변수로 추출` |
| `chore:` | 빌드/설정/기타 | `chore: .gitignore에 terraform.tfvars 추가` |
| `security:` | 보안 관련 | `security: SSH 22번을 본인 IP로 제한` |

---

### 🔹 STEP 4 · 작업 완료: Push + Pull Request

```bash
# 1. 본인 브랜치를 원격에 push
git push origin feature/작업명
# 또는 (신준한)
git push origin dev
```

**처음 push 시:**
```bash
git push -u origin feature/작업명
# -u 옵션으로 upstream 설정 → 이후 git push만으로 충분
```

#### Pull Request 생성 (GitHub 웹)

1. GitHub 레포 페이지 접속
2. 노란색 "Compare & pull request" 버튼 클릭 (또는 Pull requests 탭 → New PR)
3. PR 설정:

```
[제목]
feat: HighCPU 자동복구 사이클 + Prometheus 폴링 추가

[Base ← Compare]
feature 작업자: base=dev, compare=feature/작업명
신준한 (dev → main): base=main, compare=dev

[설명 템플릿]
## 변경 내용
- Prometheus 폴링 로직은 reference 구현(webhook_server.py)에 포함
- CPU < 80% 확인 후 복구 완료 발송
- pkill -x로 자기 자신 죽이는 버그 수정

## 테스트
- [x] make plan / make apply 성공
- [x] ./chaos/inject.sh cpu_both 정상 동작
- [x] Slack에 "복구 완료 ✅" 메시지 정상 수신

## 영향 범위
- recovery/controller/*
- recovery/reference/webhook_server.py
- recovery/controller/scripts/*
- ansible/roles/monitoring/tasks/main.yml
  (.env / inventory / recovery.service 배포 구조 변경)

## 리뷰어
@조휘정 @신준한
```

4. **Reviewer 지정**: 팀장(조휘정) + 같은 영역 담당자
5. **Labels** (선택): `bug`, `enhancement`, `documentation` 등
6. **Create pull request** 클릭

---

### 🔹 STEP 5 · Code Review 후 머지

#### 리뷰어 (조휘정, 신준한)가 할 일

```bash
# 로컬에서 해당 PR 코드 받아서 테스트
git fetch origin
git checkout feature/작업명
make plan      # 변경 영향 확인
# 필요시 직접 테스트
```

GitHub PR 페이지에서:
- "Files changed" 탭에서 코드 검토
- 라인별 코멘트 가능
- **Review** 버튼 → **Approve** / **Request changes** / **Comment**

#### 머지 (조휘정 권한)

리뷰 통과 후:
- **Squash and merge** (권장): 여러 commit을 1개로 합쳐서 머지 → main 히스토리 깔끔
- **Merge pull request**: commit 그대로 머지
- **Rebase and merge**: 선형 히스토리 유지

머지 후:
```bash
# feature 브랜치 삭제 (GitHub에서 "Delete branch" 버튼)
# 로컬 브랜치도 삭제
git checkout dev
git pull origin dev
git branch -d feature/작업명
```

---

### 🔹 STEP 6 · 다른 사람 작업과 동기화 (수시로)

#### 매일 작업 시작 전

```bash
# 본인 브랜치로 전환
git checkout feature/작업명

# dev의 최신 변경을 본인 브랜치에 가져오기
git fetch origin
git merge origin/dev
# 또는 더 깔끔하게 rebase
# git rebase origin/dev
```

#### 충돌(Conflict) 발생 시

```bash
# 충돌 파일 확인
git status
# both modified: ansible/roles/monitoring/tasks/main.yml

# 파일 열어서 <<<<<<< ... ======= ... >>>>>>> 부분 직접 해결
vim ansible/roles/monitoring/tasks/main.yml

# 해결 후
git add ansible/roles/monitoring/tasks/main.yml
git commit -m "resolve: dev 머지 시 monitoring tasks 충돌 해결"
git push origin feature/작업명
```

---

### 🔹 전체 흐름 요약 다이어그램

```
┌─────────────────────────────────────────────────────────────┐
│ 작업자 (한지우/이지윤/김민규/신준한)                            │
└─────────────────────────────────────────────────────────────┘
        │
        │ ① git clone (최초 1회)
        ▼
   [로컬 레포]
        │
        │ ② git checkout dev && git pull
        │ ③ git checkout -b feature/작업명  (※ 신준한은 dev에서 작업)
        ▼
   [feature 브랜치 작업]
        │
        │ ④ git add . && git commit
        ▼
   [로컬 commit]
        │
        │ ⑤ git push origin feature/작업명
        ▼
   [원격 feature 브랜치]
        │
        │ ⑥ GitHub PR 생성 (Base: dev, Compare: feature/작업명)
        ▼
   [Pull Request]
        │
        │ ⑦ 리뷰어 리뷰 (Approve / Request changes)
        ▼
   [Approved]
        │
        │ ⑧ Squash and merge
        ▼
   [dev 브랜치 업데이트]
        │
        │ ⑨ 신준한 → 조휘정에게 dev → main PR 요청
        ▼
   [main 브랜치 업데이트 / 릴리즈]
```

---

### 🔹 자주 쓰는 Git 명령어 치트시트

```bash
# 현재 상태 확인
git status                    # 변경 파일 보기
git log --oneline -10         # 최근 10개 commit
git branch -a                 # 모든 브랜치
git remote -v                 # 원격 저장소 주소

# 브랜치 작업
git checkout dev              # 브랜치 전환
git checkout -b feature/x     # 새 브랜치 생성 + 전환
git branch -d feature/x       # 머지된 브랜치 삭제
git branch -D feature/x       # 강제 삭제

# 변경 관리
git diff                      # 변경 내용 보기
git diff --staged             # stage된 변경 보기
git restore <파일>             # 작업 되돌리기 (stage 전)
git restore --staged <파일>    # unstage

# 동기화
git fetch origin              # 원격 정보만 가져오기
git pull origin dev           # fetch + merge
git push origin <브랜치>       # 푸시

# 실수 복구
git reset HEAD~1              # 마지막 commit 취소 (변경은 유지)
git reset --hard HEAD~1       # 마지막 commit + 변경 모두 취소 (위험!)
git revert <commit-id>        # 특정 commit을 되돌리는 새 commit 생성
```

---

## 🚀 시작하기 (최초 1회)

### ✅ 사전 준비물

| 항목 | 비고 |
|---|---|
| Rocky Linux 8 VMware | 개인 PC에 설치 |
| AWS 계정 | 개인 프리티어 계정 |
| AWS Access Key + Secret Key | IAM에서 발급 |
| GitHub SSH 키 등록 | `ssh -T git@github.com`으로 확인 |
| Slack Webhook URL (2개) | `#monitoring`, `#critical-alerts` 채널용 |

> **Access Key 발급 방법:**  
> AWS 콘솔 → IAM → Users → 본인계정 → Security credentials → Access keys → Create access key → Use case: CLI 선택 → 키 복사

> **Slack Webhook 발급 방법:**  
> [api.slack.com/apps](https://api.slack.com/apps) → Create New App → Incoming Webhooks → ON → Add New Webhook to Workspace → 채널 선택 → URL 복사

---

### 🔹 STEP A · 코드 받기

```bash
git clone git@github.com:EchoChallengers/project1-aws.git
cd project1-aws
git checkout dev    # 또는 본인 작업 브랜치
```

---

### 🔹 STEP B · 환경 도구 설치

AWS CLI v2 + Terraform + Ansible 자동 설치:

```bash
make setup
```

설치 완료 출력 예시:
```
✅ AWS CLI  : aws-cli/2.x.x
✅ Terraform: Terraform v1.14.x
✅ Ansible  : ansible [core 2.16.x]
```

> 권한 문제 발생 시: `chmod +x setup.sh check.sh` 먼저 실행

---

### 🔹 STEP C · AWS 자격증명 등록

```bash
aws configure
```

입력 항목:
```
AWS Access Key ID     : [본인 키]
AWS Secret Access Key : [본인 시크릿]
Default region name   : ap-northeast-2    ← 반드시 서울
Default output format : json
```

---

### 🔹 STEP D · Slack Webhook + 비밀번호 등록

```bash
# 1. secrets 파일 생성
cp ansible/group_vars/secrets.yml.example \
   ansible/group_vars/secrets.yml

# 2. 본인 정보 입력
vi ansible/group_vars/secrets.yml
```

입력 내용:
```yaml
slack_webhook_default:  "https://hooks.slack.com/services/본인_일반알림_URL"
slack_webhook_critical: "https://hooks.slack.com/services/본인_긴급알림_URL"
db_password:            "본인이정한복잡한DB비밀번호"
grafana_admin_password: "본인이정한복잡한Grafana비밀번호"
```

> ⚠️ `secrets.yml`은 `.gitignore`에 등록되어 있으니 GitHub에 절대 올라가지 않습니다. 팀원끼리 메신저로 공유.

---

### 🔹 STEP E · 환경 상태 확인

```bash
make check
```

체크리스트:
- ✅ AWS CLI, Terraform, Ansible 설치
- ✅ AWS 자격증명 유효
- ✅ 리전이 `ap-northeast-2`
- ✅ `secrets.yml` 존재

모든 항목 ✅이면 다음 단계로.

---

## ⚙️ 인프라 배포

### 🔹 STEP F · Terraform 실행

```bash
make init     # Terraform 초기화
make plan     # 변경 미리보기 (실제 적용 안 함)
make apply    # 인프라 생성 + Ansible 자동 실행 (약 5~7분 소요)
```

배포 진행 중:
```
[1] VPC + Subnet + Security Group 생성     ← 약 30초
[2] EC2 4대 + NAT GW + ALB 생성             ← 약 90초
[3] SSH 접속 대기 (60초)                    ← 자동
[4] Ansible 실행 (Playbook site.yml)        ← 약 3~4분
   - common role (모든 서버)
   - web servers (fastapi + nginx + node_exporter)
   - mgmt server (prometheus + grafana + alertmanager + recovery)
   - db server (postgresql + node_exporter)
```

배포 완료 후 IP/DNS 확인:

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

> 자동 생성된 파일들:
> - `terraform/proj-key.pem` (SSH 개인키, gitignore)
> - `terraform/inventory.yml` (Ansible 인벤토리, gitignore)
> - `terraform/ansible.cfg` (Ansible 설정, gitignore)

---

### 🔹 STEP G · 실습 후 반드시 삭제

```bash
make destroy
```

> ⚠️ **비용 주의:** EC2 4대 + ALB + NAT Gateway는 시간당 비용 발생  
> - t2.micro × 4 = 프리티어 750h/월 (4대 동시 → 약 7일치)  
> - NAT Gateway는 프리티어 미적용 (시간당 $0.059 + 데이터 $0.059/GB)  
> - 실습 끝나면 **반드시 `make destroy`** 실행

---

## 🔍 시연 및 동작 확인

### 1️⃣ 웹 서비스 및 로드밸런싱

| 확인 항목 | URL | 기대 결과 |
|---|---|---|
| ALB 헬스체크 | `http://[ALB-DNS]/health` | `{"status":"ok","server":"...","database":"connected"}` |
| ALB 로드밸런싱 | `http://[ALB-DNS]/test` (반복 새로고침) | web1 ↔ web2 번갈아 표시 |
| FastAPI DB 연동 | `http://[ALB-DNS]/items` | items 테이블 데이터 JSON |
| 직접 접근 (web1) | `http://[WEB1-IP]/test` | web1 카드 UI |
| 직접 접근 (web2) | `http://[WEB2-IP]/test` | web2 카드 UI |

### 2️⃣ 모니터링 시스템

| 서비스 | URL | 확인 |
|---|---|---|
| **Grafana** | `http://[MGMT-IP]:3000` | admin / `secrets.yml`의 grafana_admin_password |
| **Prometheus** | `http://[MGMT-IP]:9090/targets` | 모든 타겟 **UP** 상태 |
| **AlertManager** | `http://[MGMT-IP]:9093` | Status: ready |
| **ALB Target Group** | AWS 콘솔 → EC2 → Target Groups | web1, web2 **healthy** |

### 3️⃣ 메트릭 수집 경로

```
Node Exporter   : http://[각-서버-IP]:9100/metrics     (OS 메트릭)
FastAPI Metrics : http://[WEB-서버-IP]/metrics         (App 메트릭)
```

### 4️⃣ DB 접속 확인

DB는 Private subnet에 있어 mgmt를 jump host로 경유:

```bash
ssh -i terraform/proj-key.pem \
    -o ProxyCommand='ssh -i terraform/proj-key.pem -W %h:%p ec2-user@[MGMT-IP]' \
    ec2-user@[DB-PRIVATE-IP]

# 접속 후
sudo -u postgres psql -d appdb -c "SELECT * FROM items;"
```

---

## 🛠️ 장애 시나리오 시연

```bash
# 도움말
./chaos/inject.sh

# 전체 상태 확인
./chaos/inject.sh status
```

### 시나리오 목록

| 시나리오 | 명령 | 예상 동작 |
|---|---|---|
| **A1. FastAPI 단일 장애** | `./chaos/inject.sh fastapi1` | ALB가 web2로 트래픽 집중, 30s 후 FastAPIDown firing |
| **A2. Nginx 장애** | `./chaos/inject.sh nginx1` | ALB 헬스체크 실패 → 트래픽 분리 |
| **B. DB 장애** | `./chaos/inject.sh db` | `/items` 호출 시 500 에러 |
| **C1. CPU 단일 부하** | `./chaos/inject.sh cpu1` | 1분 후 HighCPU firing |
| **C2. CPU 양쪽 부하** | `./chaos/inject.sh cpu_both` | ALB 분산 효과 상쇄, 응답시간 크게 증가 |
| **C3. 응답시간 벤치마크** | `./chaos/inject.sh benchmark` | warmup → normal → stressed → recovered 4단계 자동 측정 |
| **부하 해제** | `./chaos/inject.sh cpu_stop` | stress-ng 프로세스 강제 종료 |
| **전체 복구** | `./chaos/inject.sh all` | 모든 서비스 재시작 |

### 핵심 시연: 셀프힐링 사이클

```bash
# 양쪽 노드 동시 부하 + 자동복구 사이클
./chaos/inject.sh benchmark
```

기대 흐름:
```
[Phase 0] Warmup 5회 (측정 제외)
[Phase 1] Normal 10회 측정     → 평균 ~20ms
[Phase 2] CPU 100% 부하 + 45회 → 평균 ~90ms (4.5배 증가)
   ↓ (약 65초 후)
   Slack: [CRITICAL] HighCPU 알림
   Slack: 자동복구 시작 (web1)
   Slack: 자동복구 시작 (web2)
   ↓ (Prometheus 폴링으로 CPU < 80% 확인)
   Slack: 복구 완료 ✅ CPU 정상화 확인@web1
   Slack: 복구 완료 ✅ CPU 정상화 확인@web2
[Phase 3] Recovered 10회 측정  → 평균 ~20ms (완전 회복)
```

---

## 🔐 보안 설정

### 🔹 gitignore 처리된 파일

| 파일 | 이유 |
|---|---|
| `terraform/proj-key.pem` | EC2 SSH 개인키 |
| `terraform/inventory.yml` | 서버 IP 정보 |
| `terraform/ansible.cfg` | 로컬 실행 경로 |
| `terraform/terraform.tfstate*` | AWS 계정 정보 포함 |
| `ansible/group_vars/secrets.yml` | Slack URL, DB 비밀번호 |
| `chaos/results/` | 측정 결과 데이터 |

### 🔹 보안 정책 — 학습 환경 기준

본 프로젝트는 **단기 학습/시연 환경**을 가정합니다. 다음은 의도적인 트레이드오프입니다:

| 항목 | 현재 설정 | 운영 환경 권장 | 트레이드오프 이유 |
|---|---|---|---|
| SSH 22 (web/mgmt) | `0.0.0.0/0` | 본인 IP만 (`x.x.x.x/32`) | apply/destroy 반복 시 IP 갱신 부담 |
| Grafana/Prometheus/AlertManager | `0.0.0.0/0` | 본인 IP만 | 동일 |
| DB SSH 22 | VPC 내부만 (`10.0.0.0/16`) | ✅ 동일 | Private subnet으로 보호 |
| DB 5432 | VPC 내부만 | ✅ 동일 | FastAPI 외 접근 차단 |
| PostgreSQL 권한 | `LOGIN, CREATEDB` | ✅ 동일 | SUPERUSER 제거 적용 |
| Secrets 분리 | secrets.yml | ✅ 동일 | gitignore 처리 |
| IAM Role | S3 ReadOnly만 | ✅ 동일 | FullAccess 제거 |
| Grafana 기본 비번 | secrets.yml의 비번으로 변경 | ✅ 동일 | admin/admin 금지 |

### 🔹 실 운영 환경 적용 시 대안

`0.0.0.0/0` 부분을 운영 환경에 옮길 때는 다음 중 하나를 고려:

```
1. SSM Session Manager   (권장) — SSH 포트 자체를 닫고 AWS API로 접속
2. Bastion Host + IAM    — mgmt를 단일 진입점으로 만들고 IAM으로 권한 분리
3. VPN / Direct Connect  — 회사 네트워크에서만 접근
4. 동적 IP 등록 스크립트  — 작업 시작 시 본인 IP를 SG에 자동 추가
```

### 🔹 secrets.yml 관리 원칙

```
✅ 팀원끼리 메신저로 직접 공유
✅ 각자 로컬에서만 보관
❌ GitHub commit 절대 금지 (.gitignore에 등록되어 있어도 주의)
❌ Slack public 채널에 공유 금지
```

---

## ❗ 트러블슈팅

| 증상 | 해결 방법 |
|---|---|
| `aws: command not found` | `make setup` 재실행 |
| `terraform: command not found` | `make setup` 재실행 |
| `Permission denied` (스크립트) | `chmod +x *.sh` 실행 |
| `Unable to locate credentials` | `aws configure` 재실행 |
| 리전이 서울이 아님 | `aws configure` → `ap-northeast-2` 입력 |
| `Error: creating EC2 Instance` | AWS 콘솔에서 프리티어 한도 확인 |
| Slack 알림 미수신 | `secrets.yml`의 webhook URL 확인 |
| Prometheus 타겟 DOWN | 해당 서버 `systemctl status node_exporter` 확인 |
| FastAPI 500 에러 | DB 서버 PostgreSQL 상태 + `items` 테이블 권한 확인 |
| ALB 504 Gateway Timeout | Target Group 헬스체크 상태 확인 |
| Nginx 접속 불가 | Security Group 80포트 확인 |
| DB SSH 접속 불가 | NAT Gateway 상태 + ProxyCommand 설정 확인 |
| Grafana 로그인 실패 | `secrets.yml`의 `grafana_admin_password` 확인 |
| `Error: pg_hba.conf entry` | VPC CIDR(`10.0.0.0/16`) 매칭 확인 |
| Webhook 자동복구 안 됨 | mgmt 서버에서 `sudo journalctl -u recovery -f` 확인 |

### 🔹 자주 쓰는 디버깅 명령

```bash
# Ansible 재실행 (인프라는 그대로, 설정만 다시 적용)
cd terraform && ansible-playbook -i inventory.yml ../ansible/site.yml

# 특정 서버에 SSH 접속
ssh -i terraform/proj-key.pem ec2-user@[서버IP]

# DB 서버 접속 (jump host 경유)
ssh -i terraform/proj-key.pem \
    -o ProxyCommand='ssh -i terraform/proj-key.pem -W %h:%p ec2-user@[MGMT-IP]' \
    ec2-user@[DB-PRIVATE-IP]

# 서비스 로그 확인
sudo journalctl -u prometheus -n 50 --no-pager
sudo journalctl -u recovery -f               # 실시간

# Prometheus 쿼리 테스트
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq

# AlertManager 활성 알림 확인
curl -s http://localhost:9093/api/v2/alerts | jq
```

---

## 💾 Terraform State 관리

```
✅ 각자 로컬에서 독립 관리 (terraform.tfstate)
❌ GitHub commit 금지 (.gitignore 등록)
❌ S3 remote backend 사용 금지 (공유 비용 발생)
```

각자 자기 AWS 계정에서 독립적으로 실행되므로 state 공유 불필요.

---

## 🔗 참고 자료

- [AWS VPC 가이드](https://docs.aws.amazon.com/vpc/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/tips_tricks/index.html)
- [Prometheus Configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)
- [GitHub Flow](https://docs.github.com/en/get-started/quickstart/github-flow)
- [Conventional Commits](https://www.conventionalcommits.org/)

---

## 📝 주요 변경 이력

| 날짜 | 내용 | 담당 |
|---|---|---|
| 2026-05-11 | 코드 리뷰 후 18개 항목 수정 (보안, 버그, 시연 차별점) | 신준한 |
| 2026-05-11 | README 재작성 + 팀 협업 가이드 추가 | 신준한 |
| 2026-05-08 | On-premise 발표 완료 후 AWS 환경 작성 시작 | 팀 전체 |

---

**문의:** Team5. EchoChallengers