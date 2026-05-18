# 💻 중앙 집중형 장애 주입 및 모니터링 검증 가이드 (Fault Injection Guide)

> ⚠️ **팀원 필독 (완전 자동화 시연 안내)**
> 본 스크립트는 테라폼의 `output` 장부에서 현재 가동 중인 서버의 IP를 실시간으로 자동으로 긁어와서 명령어를 실행합니다.
> 따라서 **어떠한 IP 주소도 수동으로 입력하거나 수정할 필요가 없습니다.**
> `make apply` 완료 후, 아래 명령어를 그대로 복사해서 `[user1@proj-mgmt project1-aws]$` 위치에서 실행해 주세요!

---

## 🚀 Scenario 1. CPU 과부하 폭주 (High CPU Usage)
* **설명:** 수동 IP 입력 불필요. 테라폼 output에서 실시간으로 IP를 추출해 `web1`과 `web2`에 동시에 부하를 주입하고 동시 복구합니다.
* **장애 주입 명령어 (두 서버 동시 폭주):**
```bash
ssh -i ~/project1-aws/terraform/proj-key.pem -o StrictHostKeyChecking=no ec2-user@$(cd terraform && terraform output -raw web1_public_ip) "nohup cat /dev/urandom | gzip -9 > /dev/null & nohup cat /dev/urandom | gzip -9 > /dev/null &" & ssh -i ~/project1-aws/terraform/proj-key.pem -o StrictHostKeyChecking=no ec2-user@$(cd terraform && terraform output -raw web2_public_ip) "nohup cat /dev/urandom | gzip -9 > /dev/null & nohup cat /dev/urandom | gzip -9 > /dev/null &" &
정상화 및 복구 명령어 (한 줄로 두 서버 동시 복구 슛):
ssh -i ~/project1-aws/terraform/proj-key.pem -o StrictHostKeyChecking=no ec2-user@$(cd terraform && terraform output -raw web1_public_ip) "sudo pkill -9 gzip" & ssh -i ~/project1-aws/terraform/proj-key.pem -o StrictHostKeyChecking=no ec2-user@$(cd terraform && terraform output -raw web2_public_ip) "sudo pkill -9 gzip" &

🌐 Scenario 2. 웹 서비스 다운 (Nginx Down)
설명: 수동 IP 입력 불필요. web1 서버의 Nginx 프로세스를 원격으로 중지시킵니다. (※ 자가 치유 웹훅이 돌면 즉시 자동 복구됩니다.)

장애 주입 명령어:
ssh -i ~/project1-aws/terraform/proj-key.pem -o StrictHostKeyChecking=no ec2-user@$(cd terraform && terraform output -raw web1_public_ip) "sudo systemctl stop nginx"

정상화 및 복구 명령어: (수동 복구 필요 시 실행)
ssh -i ~/project1-aws/terraform/proj-key.pem -o StrictHostKeyChecking=no ec2-user@$(cd terraform && terraform output -raw web1_public_ip) "sudo systemctl start nginx"

🧠 Scenario 3. 임시 메모리 고갈 (High Memory Usage)
설명: 수동 IP 입력 불필요. 리눅스 시스템의 임시 메모리 공간(/dev/shm)에 1GB 더미 파일을 채워 안전하게 경보 센서만 발동시킵니다.

장애 주입 명령어:
ssh -i ~/project1-aws/terraform/proj-key.pem -o StrictHostKeyChecking=no ec2-user@$(cd terraform && terraform output -raw web1_public_ip) "dd if=/dev/zero of=/dev/shm/memory_bomb bs=1M count=1024"
정상화 및 복구 명령어
ssh -i ~/project1-aws/terraform/proj-key.pem -o StrictHostKeyChecking=no ec2-user@$(cd terraform && terraform output -raw web1_public_ip) "rm -f /dev/shm/memory_bomb"

📊 Scenario 4. 모니터링 수집기 다운 (Nginx Exporter Down)
설명: 수동 IP 입력 불필요. 메트릭 수집기(nginx_exporter)만 콕 집어 중지시킵니다.

장애 주입 명령어:
ssh -i ~/project1-aws/terraform/proj-key.pem -o StrictHostKeyChecking=no ec2-user@$(cd terraform && terraform output -raw web1_public_ip) "sudo systemctl stop nginx_exporter"
정상화 및 복구 명령어:
ssh -i ~/project1-aws/terraform/proj-key.pem -o StrictHostKeyChecking=no ec2-user@$(cd terraform && terraform output -raw web1_public_ip) "sudo systemctl start nginx_exporter"

🗄️ Scenario 5. 데이터베이스 커넥션 폭주 (PostgreSQL High Connections)    ----이 친구 잘안됨...
설명: 수동 IP 입력 불필요. Private Subnet에 격리된 DB 서버(db_private_ip) 내부 로컬 권한을 빌려 100개의 세션을 강제로 묶어 장애를 유발합니다.

장애 주입 명령어:
ssh -i ~/project1-aws/terraform/proj-key.pem -o StrictHostKeyChecking=no ec2-user@$(cd terraform && terraform output -raw db_private_ip) "sudo -u postgres python3 -c \"import psycopg2, time; conns = [psycopg2.connect(dbname='postgres', host='localhost') for _ in range(100)]; time.sleep(60)\"" &
정상화 및 복구 명령어:
ssh -i ~/project1-aws/terraform/proj-key.pem -o StrictHostKeyChecking=no ec2-user@$(cd terraform && terraform output -raw db_private_ip) "sudo pkill -f psycopg2"
