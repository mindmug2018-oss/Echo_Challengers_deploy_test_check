# project1-aws — Git 협업 워크플로우

> **상황**: 신준한이 작성한 초기 코드를 GitHub 레포에 올리고, 팀원들이 받아서 작업하는 전 과정  
> **레포**: `git@github.com:EchoChallengers/project1-aws.git`  
> **브랜치 전략**: `main` (조휘정) ← `dev` (신준한) ← `feature/*` (팀원)

---

## 📋 전체 흐름

```
[1단계] 신준한 — 최초 코드 업로드           (15분)
   ↓
[2단계] 팀장 조휘정 — 검수 및 dev 브랜치 생성   (10분)
   ↓
[3단계] 팀원 한지우/이지윤/김민규 — 클론 및 작업   (반복)
```

---

# 🟢 [1단계] 신준한: 최초 코드 업로드 (1회만)

## Step 1-1. GitHub 레포 준비 상태 확인

> ⚠️ **사전 확인**: 조휘정이 GitHub에서 `EchoChallengers/project1-aws` 레포를 **빈 상태**로 생성해 주어야 합니다.  
> README나 .gitignore를 미리 만들지 말고 완전 빈 상태여야 충돌이 없습니다.

조휘정이 해야 할 일 (GitHub 웹):
1. https://github.com/EchoChallengers → **New repository**
2. Repository name: `project1-aws`
3. Visibility: **Private** (팀 프로젝트 보안)
4. ❌ **Add a README file** 체크 안 함
5. ❌ **Add .gitignore** 추가 안 함
6. ❌ **Choose a license** 추가 안 함
7. **Create repository**
8. 신준한, 한지우, 이지윤, 김민규를 Collaborator로 초대

---

## Step 1-2. 로컬 코드 정리

신준한 PC에서:

```bash
cd ~/project1-aws

# 1. 현재 폴더가 git 레포인지 확인
ls -la .git
```

### Case A: `.git` 폴더가 없는 경우 (Git 초기화 안 됨)

```bash
cd ~/project1-aws

# Git 초기화
git init

# 기본 브랜치를 main으로 설정
git branch -M main

# 본인 정보 설정 (이 레포 한정)
git config user.name "신준한"
git config user.email "본인@email.com"
```

### Case B: `.git` 폴더가 이미 있는 경우 (이미 초기화됨)

```bash
cd ~/project1-aws

# 기존 원격 저장소가 있는지 확인
git remote -v

# 있으면 제거 (다른 레포에 잘못 연결되어 있을 수 있음)
git remote remove origin 2>/dev/null || true

# 기존 commit이 있다면 그대로 사용
git log --oneline -5
```

---

## Step 1-3. .gitignore 최종 확인

GitHub에 절대 올라가면 안 되는 파일들이 잘 등록되어 있는지 확인:

```bash
cat .gitignore | grep -E "tfstate|pem|secrets|inventory"
```

기대 출력:
```
terraform/terraform.tfstate
terraform/terraform.tfstate.backup
terraform/*.pem
terraform/*.key
terraform/inventory.yml
ansible/group_vars/secrets.yml
```

만약 빠진 항목이 있으면 추가:

```bash
cat >> .gitignore << 'EOF'

# 추가 보안
*.pem
*.key
**/secrets.yml
EOF
```

---

## Step 1-4. 민감 파일 정리

혹시 실수로 만든 파일이 있을 수 있어요. 확인:

```bash
# 다음 파일들이 폴더에 없는지 확인 (있으면 안 됨)
ls terraform/proj-key.pem 2>/dev/null
ls terraform/terraform.tfstate 2>/dev/null
ls terraform/inventory.yml 2>/dev/null
ls ansible/group_vars/secrets.yml 2>/dev/null

# 만약 secrets.yml에 실제 URL이 들어있다면 → 삭제 후 재생성
# (.gitignore에 등록되어 있어도 안전을 위해)
rm -f ansible/group_vars/secrets.yml
```

> ⚠️ `secrets.yml.example`은 GitHub에 올라가는 게 정상입니다. `secrets.yml`만 gitignore 처리.

---

## Step 1-5. 첫 commit 준비

```bash
# 현재 git이 추적할 파일 확인
git status
```

기대: 파일들이 빨간색(untracked)으로 표시됨.

`.gitignore`에 등록된 파일들이 목록에 안 보이는지 한번 더 확인:

```bash
# 다음 명령이 빈 결과여야 함
git status | grep -E "tfstate|\.pem$|secrets\.yml$|inventory\.yml"
```

빈 결과면 OK. 만약 무언가 보이면 `.gitignore`를 점검해야 함.

---

## Step 1-6. 첫 commit 생성

```bash
# 1. 전체 스테이지
git add .

# 2. 한번 더 확인 — 무엇이 commit될지
git status

# 3. 첫 commit
git commit -m "feat: project1-aws 초기 인프라 코드

[인프라]
- Terraform: VPC, Subnet, EC2, ALB, NAT GW, IAM Role
- Ansible: common, fastapi, nginx, postgresql, node_exporter, monitoring

[애플리케이션]
- FastAPI: /health, /items 엔드포인트 + Prometheus metrics
- Nginx: FastAPI 리버스 프록시
- PostgreSQL: appdb + items 테이블 + 샘플 데이터

[모니터링]
- Prometheus: 메트릭 수집 + alert rules (5종)
- AlertManager: Slack #monitoring + #critical-alerts 라우팅
- Grafana: Prometheus datasource 자동 등록
- Recovery Webhook: AlertManager → SSH 자동복구
- CPU 부하 자동복구: Prometheus 폴링으로 정상화 확인 후 발송

[장애 시연]
- chaos/inject.sh: 8가지 시나리오 (fastapi/nginx/db/cpu 부하/benchmark)
- recovery/scripts: 서비스 재시작 스크립트 3종

[보안]
- secrets.yml 분리 (gitignore)
- DB 유저는 LOGIN, CREATEDB 권한만 (SUPERUSER 제거)
- PostgreSQL 접근은 VPC 내부(10.0.0.0/16)에서만

[On-premise와의 차이]
- HAProxy → ALB (관리형)
- DB를 Private subnet으로 격리 + jump host 경유
- IP는 Terraform output으로 동적 관리
- SSH 키는 Terraform이 자동 생성"
```

---

## Step 1-7. 원격 저장소 연결 + push

```bash
# 1. 원격 저장소 등록
git remote add origin git@github.com:EchoChallengers/project1-aws.git

# 2. 등록 확인
git remote -v
# origin  git@github.com:EchoChallengers/project1-aws.git (fetch)
# origin  git@github.com:EchoChallengers/project1-aws.git (push)

# 3. SSH 키 동작 확인
ssh -T git@github.com
# Hi <username>! You've successfully authenticated...

# 4. main 브랜치로 push (첫 push는 -u 옵션으로 upstream 설정)
git push -u origin main
```

기대 출력:
```
Enumerating objects: XX, done.
Counting objects: 100% (XX/XX), done.
Delta compression using up to 4 threads
Compressing objects: 100% (XX/XX), done.
Writing objects: 100% (XX/XX), XX.XX KiB | XX.XX MiB/s, done.
Total XX (delta X), reused 0 (delta 0), pack-reused 0
To github.com:EchoChallengers/project1-aws.git
 * [new branch]      main -> main
branch 'main' set up to track 'origin/main'.
```

---

## Step 1-8. GitHub 웹에서 확인 + dev 브랜치 생성

### GitHub 웹 확인

브라우저에서 `https://github.com/EchoChallengers/project1-aws` 접속:
- ✅ 모든 폴더/파일이 정상 업로드되었는지
- ✅ `.gitignore`에 있는 파일들(`*.pem`, `secrets.yml`, `terraform.tfstate` 등)이 **안 보이는지**
- ✅ commit 메시지가 정상 표시되는지

### dev 브랜치 생성 (신준한이 작업할 브랜치)

```bash
# 로컬에서 dev 브랜치 생성 + 전환
git checkout -b dev

# 원격에 dev 브랜치 push
git push -u origin dev
```

---

## Step 1-9. 팀원들에게 공지

Slack 또는 메신저로 공유:

```
📢 project1-aws 레포 업로드 완료!

레포 주소: git@github.com:EchoChallengers/project1-aws.git
브랜치:
- main (조휘정 머지 권한)
- dev  (신준한 작업)

다음 단계:
1. 팀장(조휘정) — 검수 후 main 브랜치 보호 설정
2. 팀원들 — clone 받아서 본인 feature 브랜치 생성

secrets.yml에 들어갈 Slack URL 2개는 별도 메신저로 공유합니다.
```

---

# 🟡 [2단계] 팀장 조휘정: 검수 및 브랜치 보호 설정

## Step 2-1. 레포 clone

조휘정 PC에서:

```bash
cd ~
git clone git@github.com:EchoChallengers/project1-aws.git
cd project1-aws

# 현재 브랜치와 원격 브랜치 확인
git branch -a
# * main
#   remotes/origin/HEAD -> origin/main
#   remotes/origin/dev
#   remotes/origin/main
```

---

## Step 2-2. 코드 검수 (로컬에서 문법만 체크)

> ⚠️ 실제 `terraform apply`는 하지 않습니다. AWS 비용 발생 + state 충돌 위험.  
> 코드 자체의 문법과 구조만 검토.

```bash
# 1. Python 문법
python3 -c "import ast; ast.parse(open('recovery/reference/webhook_server.py').read())" && echo "Python OK"

# 2. Bash 문법
bash -n chaos/inject.sh && echo "inject.sh OK"
bash -n setup.sh && echo "setup.sh OK"
bash -n check.sh && echo "check.sh OK"

# 3. YAML 문법 (Ansible)
find ansible -name "*.yml" -o -name "*.yaml" | while read f; do
    python3 -c "import yaml; list(yaml.safe_load_all(open('$f')))" 2>/dev/null && echo "✅ $f" || echo "❌ $f"
done
```

---

## Step 2-3. 폴더 구조 + 핵심 파일 확인

```bash
# 폴더 구조
tree -L 3 -I '.git' 2>/dev/null || find . -type d -not -path './.git*' | head -30

# .gitignore에 등록된 파일이 정말 git에 안 들어갔는지 확인
git ls-files | grep -E "tfstate|\.pem$|secrets\.yml$|inventory\.yml" || echo "✅ 민감 파일 모두 제외됨"

# 핵심 파일 존재 확인
for f in \
    terraform/main.tf \
    terraform/variables.tf \
    terraform/outputs.tf \
    ansible/site.yml \
    ansible/group_vars/secrets.yml.example \
    recovery/reference/webhook_server.py \
    chaos/inject.sh \
    setup.sh check.sh Makefile README.md
do
    [ -f "$f" ] && echo "✅ $f" || echo "❌ $f 누락!"
done
```

---

## Step 2-4. README.md 가독성 확인

```bash
# Markdown 미리보기 (terminal에서)
cat README.md | head -50

# 또는 GitHub 웹에서 렌더링 확인
# https://github.com/EchoChallengers/project1-aws
```

---

## Step 2-5. main 브랜치 보호 설정 (GitHub 웹)

`https://github.com/EchoChallengers/project1-aws/settings/branches` 접속:

1. **Add branch protection rule** 클릭
2. **Branch name pattern**: `main`
3. 다음 옵션 체크:
   - ✅ **Require a pull request before merging**
     - Required number of approvals: `1`
     - ✅ Dismiss stale pull request approvals when new commits are pushed
   - ✅ **Require status checks to pass before merging** (선택, CI 도입 시)
   - ✅ **Require conversation resolution before merging**
   - ✅ **Do not allow bypassing the above settings**
4. **Create** 클릭

이렇게 하면:
- 직접 push 불가 (PR 필수)
- 최소 1명 approve 필요
- 해결되지 않은 코멘트 있으면 머지 불가

---

## Step 2-6. dev 브랜치도 동일하게 보호 (선택)

같은 방식으로 `dev` 브랜치도 보호:
- Branch name pattern: `dev`
- Require a pull request before merging
- Required approvals: `1` (신준한이 머지 권한 가짐)

---

## Step 2-7. Collaborator 권한 부여

`https://github.com/EchoChallengers/project1-aws/settings/access`:

1. **Add people** 클릭
2. 팀원 GitHub 계정 추가:
   - 신준한: **Maintain** 권한 (dev 브랜치 관리)
   - 한지우, 이지윤, 김민규: **Write** 권한

---

## Step 2-8. 팀원들에게 검수 완료 공지

```
✅ project1-aws 검수 완료

레포 상태:
- 코드 구조 정상
- 민감 파일 모두 .gitignore 처리됨
- main 브랜치 보호 설정 완료 (PR + 1 approval 필수)

팀원 권한:
- 신준한 (Maintain): dev 브랜치 관리
- 한지우/이지윤/김민규 (Write): feature 브랜치 작업

다음 단계: 각자 clone 받아서 feature 브랜치 생성
```

---

# 🔵 [3단계] 팀원: 클론 및 작업 (한지우/이지윤/김민규)

> ⚠️ **신준한은 dev 브랜치에서 직접 작업**하므로 별도 안내.  
> 이 섹션은 한지우, 이지윤, 김민규 기준.

## Step 3-1. 최초 1회: 레포 clone

```bash
# 1. SSH 키 등록 확인
ssh -T git@github.com
# Hi <username>! You've successfully authenticated...

# 2. 클론
cd ~
git clone git@github.com:EchoChallengers/project1-aws.git
cd project1-aws

# 3. 본인 정보 설정 (이 레포 한정)
git config user.name "본인이름"
git config user.email "본인@email.com"

# 4. 모든 브랜치 확인
git branch -a
# * main
#   remotes/origin/main
#   remotes/origin/dev
```

---

## Step 3-2. 작업 시작: feature 브랜치 생성

작업할 때마다 새 브랜치를 만듭니다.

### 브랜치 이름 규칙

| 작업 종류 | 접두사 | 예시 |
|---|---|---|
| 새 기능 | `feature/` | `feature/add-grafana-dashboard` |
| 버그 수정 | `fix/` | `fix/pg-hba-cidr-mismatch` |
| 문서 | `docs/` | `docs/update-team-guide` |
| 리팩터링 | `refactor/` | `refactor/extract-ssh-helper` |
| 보안 | `security/` | `security/secrets-vault` |

### 담당 영역별 예시

**인프라 (한지우)**:
```bash
git checkout -b feature/add-vpc-flow-logs
git checkout -b fix/postgresql-pg-hba-cidr
git checkout -b refactor/separate-network-tf
```

**모니터링·복구 (이지윤, 김민규)**:
```bash
git checkout -b feature/grafana-cpu-dashboard
git checkout -b feature/add-disk-alert
git checkout -b feature/recovery-circuit-breaker
git checkout -b fix/alertmanager-channel-config
```

### 브랜치 생성 명령

```bash
# 1. dev 브랜치 기준으로 시작 (항상 dev에서!)
git checkout dev
git pull origin dev   # 최신 상태로

# 2. 새 feature 브랜치 생성 + 전환
git checkout -b feature/작업명

# 3. 본인 브랜치인지 확인
git branch
# * feature/작업명
#   dev
#   main
```

---

## Step 3-3. 작업 + commit

### 작업 중 수시로 변경사항 확인

```bash
# 어떤 파일이 변경되었나
git status

# 무엇이 변경되었나 (라인 단위)
git diff
```

### 변경사항 commit

```bash
# 1. 변경 파일 stage
git add <변경한_파일>
# 또는 전체
git add .

# 2. stage된 내용 최종 확인
git status

# 3. commit
git commit -m "feat: Grafana CPU 대시보드 패널 추가

- node_cpu_seconds_total{mode='idle'} 쿼리 기반
- 4개 노드(web1, web2, mgmt, db) 동시 표시
- 80% 임계치 빨간 점선 표시"
```

### Commit 메시지 컨벤션 (Conventional Commits)

| 접두사 | 용도 |
|---|---|
| `feat:` | 새 기능 |
| `fix:` | 버그 수정 |
| `docs:` | 문서 |
| `refactor:` | 동작 변경 없는 리팩터링 |
| `chore:` | 빌드/설정 |
| `security:` | 보안 |
| `test:` | 테스트 코드 |

---

## Step 3-4. push + Pull Request 생성

### 원격에 push

```bash
# 첫 push (upstream 설정 필요)
git push -u origin feature/작업명

# 이후 push (간단)
git push
```

### Pull Request 생성

1. **GitHub 웹에서 PR 생성**: 
   - 푸시 후 GitHub 메인 페이지에 노란 배너 표시 → **Compare & pull request** 클릭
   - 또는 Pull requests 탭 → **New pull request**

2. **Base와 Compare 설정** ⭐
   ```
   base: dev               ← 머지될 대상
   compare: feature/작업명  ← 본인 브랜치
   ```
   > ⚠️ Base를 `main`이 아닌 **`dev`로 설정**해야 함!

3. **PR 제목 + 설명 작성**

   **제목**: commit 메시지와 동일하거나 더 명확하게
   
   **설명 템플릿**:
   ```markdown
   ## 변경 내용
   - Grafana 대시보드에 CPU 사용률 패널 추가
   - 4개 노드를 한 화면에 표시
   - 임계치 80% 빨간 점선 표시
   
   ## 테스트
   - [x] YAML 문법 체크 통과
   - [x] 로컬 ansible-playbook --syntax-check 통과
   - [ ] 실제 배포 후 Grafana에서 확인 (조휘정/신준한 검증 필요)
   
   ## 영향 범위
   - ansible/roles/monitoring/templates/grafana-dashboard.json
   - ansible/roles/monitoring/tasks/main.yml (dashboard provisioning 추가)
   
   ## 리뷰어
   @조휘정 @신준한
   ```

4. **Reviewer 지정** (우측 사이드바):
   - 인프라 작업 → `신준한`, `조휘정`
   - 모니터링·복구 작업 → `신준한`(통합 관점), `조휘정`(최종)

5. **Labels** (선택, 권장):
   - `feature`, `bug`, `documentation`, `security` 등

6. **Create pull request** 클릭

---

## Step 3-5. 리뷰 대기 + 수정 대응

### 리뷰 요청을 받으면 (Approve, Request changes, Comment)

```bash
# 1. 본인 브랜치에서 수정
git checkout feature/작업명
# 파일 수정...

# 2. 수정 내용 commit + push
git add .
git commit -m "fix: 리뷰 코멘트 반영 — 변수명 변경"
git push

# 같은 PR에 자동으로 추가됨 (다시 PR 만들 필요 없음)
```

### 리뷰 통과되면 (Approve)

조휘정(또는 신준한)이 **Squash and merge** 또는 **Merge pull request** 클릭.

---

## Step 3-6. 머지 완료 후 정리

```bash
# 1. dev 브랜치로 이동 + 최신화
git checkout dev
git pull origin dev

# 2. 머지된 feature 브랜치 로컬에서 삭제
git branch -d feature/작업명

# 3. 원격 브랜치도 삭제 (GitHub 웹에서 "Delete branch" 클릭하거나)
git push origin --delete feature/작업명
```

---

## Step 3-7. 매일 작업 시작 전 — 동기화

다른 사람이 dev에 머지한 내용을 본인 브랜치에 가져오기:

```bash
# 1. dev 최신화
git checkout dev
git pull origin dev

# 2. 본인 작업 브랜치로 전환
git checkout feature/본인작업

# 3. dev의 변경을 본인 브랜치에 머지
git merge dev

# 또는 더 깔끔하게 (히스토리 직선화)
# git rebase dev
```

### 충돌(Conflict) 발생 시

```bash
# 어떤 파일에 충돌이 났는지 확인
git status
# both modified: ansible/roles/monitoring/tasks/main.yml

# 파일을 열어서 충돌 마커 직접 해결
vim ansible/roles/monitoring/tasks/main.yml
# <<<<<<< HEAD
# 본인이 작성한 코드
# =======
# dev에 있던 코드
# >>>>>>> dev
# 위 마커를 보고 어떤 부분을 살릴지 결정해서 직접 편집

# 충돌 해결 후
git add ansible/roles/monitoring/tasks/main.yml
git commit -m "resolve: dev 머지 시 monitoring tasks 충돌 해결"
git push
```

---

# 📊 전체 흐름 다이어그램

```
[1단계: 신준한 — 최초 업로드]
   git init → 첫 commit → main push → dev push

[2단계: 팀장 조휘정 — 검수]
   git clone → 코드 검수 → main 브랜치 보호 → Collaborator 추가

[3단계: 팀원 — 작업 반복]
   git clone (최초 1회)
       ↓
   git checkout dev && git pull
       ↓
   git checkout -b feature/작업명
       ↓
   [작업]
       ↓
   git add . && git commit
       ↓
   git push -u origin feature/작업명
       ↓
   GitHub에서 PR 생성 (base: dev, compare: feature/작업명)
       ↓
   리뷰 → Approve → Squash merge
       ↓
   git checkout dev && git pull
       ↓
   git branch -d feature/작업명
```

---

# 🚨 자주 발생하는 실수와 대응

## Q1. 실수로 main 브랜치에서 작업했어요

```bash
# 1. 현재 변경사항을 임시 저장
git stash

# 2. main을 원래 상태로 돌리기
git reset --hard origin/main

# 3. dev로 전환 + 새 feature 브랜치 생성
git checkout dev
git pull origin dev
git checkout -b feature/작업명

# 4. 임시 저장한 변경사항 복원
git stash pop

# 5. 정상 작업 진행
```

## Q2. 실수로 secrets.yml을 commit했어요

```bash
# ⚠️ 절대 그냥 push하지 마세요!

# 1. 마지막 commit 취소 (변경 자체는 유지)
git reset --soft HEAD~1

# 2. secrets.yml unstage
git restore --staged ansible/group_vars/secrets.yml

# 3. .gitignore에 추가되어 있는지 확인
grep "secrets.yml" .gitignore
# 없으면 추가
echo "ansible/group_vars/secrets.yml" >> .gitignore

# 4. 다시 commit (secrets.yml 없이)
git add .
git commit -m "feat: ..."

# 5. push
git push
```

만약 이미 push해 버렸다면:
- Slack URL 즉시 재발급 (`api.slack.com/apps` → Regenerate)
- DB 비밀번호 변경
- 팀에 알림

## Q3. PR 생성했는데 Base가 main으로 잘못 설정됐어요

GitHub PR 페이지에서:
1. 제목 위쪽의 `base: main ← compare: feature/...` 표시 찾기
2. `base: main` 클릭 → `dev`로 변경
3. 자동으로 diff 갱신됨

## Q4. PR 머지 후 로컬 브랜치가 정리 안 돼요

```bash
# 머지된 모든 브랜치 일괄 정리
git checkout dev
git pull origin dev
git branch --merged | grep -v "main\|dev\|\*" | xargs -n 1 git branch -d
```

## Q5. push가 거부됐어요 ("Updates were rejected")

원격이 본인보다 앞서있다는 뜻:

```bash
# 1. 원격 최신 가져오기
git pull origin feature/작업명 --rebase

# 2. 충돌 있으면 해결

# 3. 다시 push
git push
```

---

# 🎯 권장 작업 패턴

## 작은 단위로 자주 commit

```bash
❌ 나쁜 예: 일주일 작업 한번에 commit
✅ 좋은 예: 1~2시간 단위로 의미 있는 작업이 끝날 때마다 commit
```

## 작은 단위로 자주 PR

```bash
❌ 나쁜 예: 200줄 변경된 거대한 PR
✅ 좋은 예: 50줄 이하의 PR을 여러 번
```

작은 PR이 좋은 이유:
- 리뷰가 빠름 (5분 vs 1시간)
- 충돌이 적음
- 문제 발생 시 어디서 그랬는지 추적 쉬움
- merge revert가 쉬움

## 매일 작업 시작 전 + 끝나기 전 동기화

```bash
# 아침 (작업 시작)
git checkout dev && git pull
git checkout feature/본인작업
git merge dev

# 저녁 (작업 끝)
git push
```

---

# 📌 자주 쓰는 Git 명령어 치트시트

```bash
# 상태 확인
git status                    # 변경 파일
git log --oneline -10         # 최근 commit
git branch -a                 # 모든 브랜치
git remote -v                 # 원격 저장소

# 브랜치
git checkout dev              # 전환
git checkout -b feature/x     # 생성 + 전환
git branch -d feature/x       # 머지된 브랜치 삭제

# 변경 관리
git diff                      # 변경 내용
git diff --staged             # stage된 변경
git restore <파일>             # 변경 되돌리기
git restore --staged <파일>    # unstage

# 동기화
git fetch origin              # 원격 정보만
git pull origin dev           # fetch + merge
git push                      # 푸시 (upstream 설정 후)
git push -u origin <브랜치>    # 첫 푸시 (upstream 설정)

# 실수 복구
git reset HEAD~1              # 마지막 commit 취소 (변경 유지)
git reset --hard HEAD~1       # 마지막 commit + 변경 모두 취소 ⚠️
git revert <commit-id>        # 특정 commit 되돌리는 새 commit
git stash                     # 작업 임시 저장
git stash pop                 # 임시 저장 복원
```

---

*작성: 2026-05-11*