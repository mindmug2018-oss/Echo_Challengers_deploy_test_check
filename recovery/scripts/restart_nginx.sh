#!/bin/bash
# 파일위치 : ~/project1-aws/recovery/scripts/restart_nginx.sh

SERVICE="nginx"
LOG_TAG="[RECOVERY]"

echo "$LOG_TAG 시작: $SERVICE 재시작 시도"

STATUS=$(systemctl is-active $SERVICE 2>/dev/null)
echo "$LOG_TAG 현재 상태: $STATUS"

# 설정 문법 검사 후 재시작
# 이유: 문법 오류가 있으면 재시작해도 실패 → 미리 확인
if sudo nginx -t 2>/dev/null; then
    sudo systemctl restart $SERVICE
    sleep 3
    FINAL=$(systemctl is-active $SERVICE 2>/dev/null)
    echo "$LOG_TAG 재시작 후 상태: $FINAL"
    [ "$FINAL" = "active" ] && exit 0 || exit 1
else
    echo "$LOG_TAG Nginx 설정 오류 — 수동 확인 필요"
    exit 1
fi