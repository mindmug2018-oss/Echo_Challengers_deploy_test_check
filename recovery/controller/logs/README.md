# Recovery Logs

## recovery.log

정상 Recovery 흐름 기록.

포함 항목:
- SUCCESS
- RETRY
- SKIP (cooldown)
- reason 기반 retry 로그

예시:
- Recovery 성공
- Retry 시도
- Cooldown 활성화로 Recovery Skip


## critical.log

비정상/예외 상황 기록.

포함 항목:
- FAILED
- NO_MAP
- ERROR

예시:
- Recovery 실패
- recovery_map.yml에 없는 alertname
- invalid JSON 요청

### FAILED / RETRY reason 예시

Recovery retry / failed 로그는 reason 기준으로 구분 가능하다.

예시:
- reason=verify_failed
- reason=recovery_command_failed
- reason=script_timeout