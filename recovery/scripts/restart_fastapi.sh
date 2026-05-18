#!/bin/bash
# 파일위치 : ~/project1-aws/recovery/scripts/restart_fastapi.sh
# 목적     : FastAPI 서비스 재시작 (mgmt에서 SSH로 대상 서버에 실행)
# 실행방식 : webhook_server.py가 SSH stdin으로 전달

SERVICE="fastapi"
LOG_TAG="[RECOVERY]"

echo "$LOG_TAG 시작: $SERVICE 재시작 시도"

# 현재 상태 확인
STATUS=$(systemctl is-active $SERVICE 2>/dev/null)
echo "$LOG_TAG 현재 상태: $STATUS"

# 재시작
sudo systemctl restart $SERVICE
sleep 5

# 재시작 후 상태 확인
FINAL=$(systemctl is-active $SERVICE 2>/dev/null)
echo "$LOG_TAG 재시작 후 상태: $FINAL"

if [ "$FINAL" = "active" ]; then
    echo "$LOG_TAG 성공: $SERVICE 정상 실행 중"
    exit 0
else
    echo "$LOG_TAG 실패: $SERVICE 상태 = $FINAL"
    # 마지막 로그 10줄 출력 (디버깅용)
    sudo journalctl -u $SERVICE -n 10 --no-pager
    exit 1
fi