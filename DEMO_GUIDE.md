# 💻 중앙 집중형 장애 주입 및 모니터링 검증 가이드 (Fault Injection)

> ⚠️ **팀원 필독 (시연 전 주의사항)**
> `make apply`를 실행할 때마다 AWS Public IP 주소가 매번 새로 갱신됩니다. 
> 아래 명령어의 **`[여기에_..._IP_입력]`** 부분을 테라폼 output으로 나온 실제 IP 주소로 꼭 변경한 뒤 터미널에 실행해 주세요!

---

## 🚀 Scenario 1. CPU 과부하 폭주 (High CPU)
# 🚨 실행 전 [여기에_WEB1_IP_입력] 및 [여기에_WEB2_IP_입력] 자리에 실제 AWS IP를 넣으세요!
ssh -i ~/project1-aws/terraform/proj-key.pem -o StrictHostKeyChecking=no ec2-user@[여기에_WEB1_IP_입력] "nohup cat /dev/urandom | gzip -9 > /dev/null & nohup cat /dev/urandom | gzip -9 > /dev/null &" & ssh -i ~/project1-aws/terraform/proj-key.pem -o StrictHostKeyChecking=no ec2-user@[여기에_WEB2_IP_입력] "nohup cat /dev/urandom | gzip -9 > /dev/null & nohup cat /dev/urandom | gzip -9 > /dev/null &" &

## 🌐 Scenario 2. 웹 서비스 다운 (Nginx Down)
# 🚨 실행 전 [여기에_WEB1_IP_입력] 자리에 실제 AWS IP를 넣으세요!
ssh -i ~/project1-aws/terraform/proj-key.pem -o StrictHostKeyChecking=no ec2-user@[여기에_WEB1_IP_입력] "sudo systemctl stop nginx"

## 🧠 Scenario 3. 임시 메모리 고갈 (High Memory)
# 🚨 실행 전 [여기에_WEB1_IP_입력] 자리에 실제 AWS IP를 넣으세요!
ssh -i ~/project1-aws/terraform/proj-key.pem -o StrictHostKeyChecking=no ec2-user@[여기에_WEB1_IP_입력] "dd if=/dev/zero of=/dev/shm/memory_bomb bs=1M count=1024"

## 📊 Scenario 4. 모니터링 수집기 다운 (Nginx Exporter Down)
# 🚨 실행 전 [여기에_WEB1_IP_입력] 자리에 실제 AWS IP를 넣으세요!
ssh -i ~/project1-aws/terraform/proj-key.pem -o StrictHostKeyChecking=no ec2-user@[여기에_WEB1_IP_입력] "sudo systemctl stop nginx_exporter"

## 🗄️ Scenario 5. 데이터베이스 커넥션 폭주 (PostgreSQL Connections)
# 🚨 실행 전 [여기에_DB_PRIVATE_IP_입력] 자리에 실제 테라폼 DB 내부 IP(10.0.xx.xx)를 넣으세요!
ssh -i ~/project1-aws/terraform/proj-key.pem -o StrictHostKeyChecking=no ec2-user@[여기에_DB_PRIVATE_IP_입력] "sudo -u postgres python3 -c \"import psycopg2, time; conns = [psycopg2.connect(dbname='postgres', host='localhost') for _ in range(100)]; time.sleep(60)\"" &



