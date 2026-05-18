# Recovery Controller

## 개요

현재 구조는 on-mgmt + AWS mgmt + Tailscale 기반 Hybrid 운영 환경 기준으로 동작한다.

* AlertManager Webhook 기반 자동 복구 시스템
* Alert 수신 후 정책 기반 Recovery 실행


## 전체 흐름

```text
AlertManager
→ Flask Webhook
→ recovery_map.yml 정책 조회
→ Cooldown 확인
→ Recovery Script 실행
→ Verify
→ Retry / SUCCESS / FAILED Logging
```

## 주요 기능

* YAML 기반 Recovery Policy
* Retry / Cooldown
* Verify 구조
* Mock / Ansible 모드 지원
* recovery.log / critical.log 분리
* alertname 기반 Recovery 정책 분기

## 디렉토리 구조

```text
recovery/controller/
├── app.py
├── config/
├── logs/
├── scripts/
├── tests/
```

## 실행 방법

### Flask 실행

```bash
cd /opt/recovery
python3 app.py
```

### Recovery service 확인

sudo systemctl status recovery --no-pager

### Alert 테스트

curl -X POST http://localhost:5001/webhook \
-H "Content-Type: application/json" \
-d @tests/nginx_down_alert.json

### Log 확인

tail -f logs/recovery.log
tail -f logs/critical.log

## Recovery Policy 예시

```yaml
NginxDown:
  target_group: webservers
  service_name: nginx
  script: scripts/recover_service.sh
  retry: 3
  cooldown: 60
  verify:
    command: "ansible webservers -i /home/user1/project1-aws/terraform/inventory.yml -m shell -a 'systemctl is-active nginx' | grep active"
```

## Verify 구조

* Recovery 실행 이후 실제 서비스 정상 상태 여부를 추가 확인
* verify command 성공 시 Recovery SUCCESS 처리
* verify 실패 시 retry 정책 기준으로 재시도 수행

* 현재 verify는 process-level 기준(systemctl is-active)으로 수행
* Prometheus scrape 정상 여부 및 alert resolve 여부까지는 포함하지 않음

## Chaos / Stress 기반 장애 시나리오

현재 Recovery Controller는 다음 장애 시나리오 기반 Recovery 구조를 포함한다.

### Service 장애
- nginx stop
- nginx_exporter stop

### Resource 장애
- CPU stress
- Memory pressure

### Failure Handling
- retry / FAILED handling
- critical.log 기반 failure tracking

현재 payload 기반 Recovery 기능 검증을 우선 수행하고 있으며,
이후 Chaos 기반 실제 장애 흐름 검증으로 확장 가능하다.

## 로그 구조

* recovery.log

  * Recovery 성공 / retry / cooldown skip 기록

* critical.log

  * Recovery 실패 / unknown alert / script 오류 기록

* retry / failed 로그는 reason 기반으로 구분 가능

  * reason=verify_failed
  * reason=recovery_command_failed
  * reason=script_timeout