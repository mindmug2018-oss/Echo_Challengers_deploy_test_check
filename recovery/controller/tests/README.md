# Test Alert Payloads

Recovery Controller 테스트용 Alert JSON 모음.

## 파일 목록

### nginx_down_alert.json

* alertname: NginxDown
* 목적: nginx 장애 Alert 수신 및 Recovery Policy 분기 테스트
* 확인 범위:

  * recovery_map.yml 정책 조회
  * nginx recovery script 실행
  * verify command 기반 nginx active 상태 확인
  * recovery.log SUCCESS 기록

### exporter_down_alert.json

* alertname: NginxExporterDown
* 목적: nginx_exporter 장애 Alert 수신 및 Recovery Policy 분기 테스트

### unknown_alert.json

* alertname: UnknownAlert
* 목적: recovery_map.yml에 없는 Alert 처리 테스트
* 예상 결과: critical.log에 [NO_MAP] 기록

### retry_fail_alert.json

* alertname: RetryFailTest
* 목적: Retry / Critical Handling 테스트
* 예상 결과:

  * recovery.log에 [RETRY] 기록
  * critical.log에 [FAILED] 기록
  * reason 기반 retry / failed 로그 확인 가능

    * reason=verify_failed
    * reason=recovery_command_failed
    * reason=script_timeout

## 테스트 명령어 예시

```bash
curl -X POST http://localhost:5001/webhook \
-H "Content-Type: application/json" \
-d @tests/nginx_down_alert.json
```

## 참고

현재 payload 테스트는 Recovery Controller 단독 기능 검증 목적이다.

실제 운영 흐름 검증은 이후 Chaos / stress 기반 장애 주입을 통해 수행한다.