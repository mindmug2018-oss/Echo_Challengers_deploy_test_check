#!/bin/bash
# 파일위치 : ~/project1-aws/recovery/scripts/restart_postgres.sh

SERVICE="postgresql"
LOG_TAG="[RECOVERY]"

echo "$LOG_TAG 시작: $SERVICE 재시작 시도"

STATUS=$(systemctl is-active $SERVICE 2>/dev/null)
echo "$LOG_TAG 현재 상태: $STATUS"

sudo systemctl restart $SERVICE
sleep 10   # PostgreSQL은 시작 시간이 FastAPI보다 김

FINAL=$(systemctl is-active $SERVICE 2>/dev/null)
echo "$LOG_TAG 재시작 후 상태: $FINAL"

if [ "$FINAL" = "active" ]; then
    echo "$LOG_TAG 성공"
    exit 0
else
    echo "$LOG_TAG 실패"
    sudo journalctl -u $SERVICE -n 10 --no-pager
    exit 1
fi