from flask import Flask, request, jsonify
import yaml
import subprocess
from datetime import datetime
from pathlib import Path
import time
import os
import requests

app = Flask(__name__)

BASE_DIR = Path(__file__).resolve().parent
SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")
MAP_FILE = BASE_DIR / "config" / "recovery_map.yml"
RECOVERY_LOG = BASE_DIR / "logs" / "recovery.log"
CRITICAL_LOG = BASE_DIR / "logs" / "critical.log"

# 같은 Alert가 너무 자주 반복될 때 복구를 중복 실행하지 않기 위한 메모리 저장소
LAST_RECOVERY_TIME = {}


def load_recovery_map():
    with open(MAP_FILE, "r") as f:
        return yaml.safe_load(f) or {}


def write_log(log_file, message):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(log_file, "a") as f:
        f.write(f"{timestamp} {message}\n")

def send_slack(message):
    if not SLACK_WEBHOOK_URL:
        return

    try:
        requests.post(
            SLACK_WEBHOOK_URL,
            json={"text": message},
            timeout=5
        )

    except requests.RequestException as e:
        write_log(
            CRITICAL_LOG,
            f"[SLACK_ERROR] error={str(e)}"
        )


def is_cooldown_active(alertname, instance, cooldown):
    key = f"{alertname}:{instance}"
    now = time.time()
    last_time = LAST_RECOVERY_TIME.get(key)

    if last_time is None:
        return False, 0

    elapsed = now - last_time
    remaining = cooldown - elapsed

    if remaining > 0:
        return True, int(remaining)

    return False, 0


def update_recovery_time(alertname, instance):
    key = f"{alertname}:{instance}"
    LAST_RECOVERY_TIME[key] = time.time()

def clean_log_output(output):
    if not output:
        return ""

    return " | ".join(output.strip().splitlines())

def run_verify(verify_info):
    if not verify_info:
        return True, "verify skipped"

    command = verify_info.get("command")

    if not command:
        return True, "verify command not defined"

    try:
        result = subprocess.run(
            command,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            timeout=30
        )
    except subprocess.TimeoutExpired:
        return False, "verify_timeout"

    if result.returncode == 0:
        return True, clean_log_output(result.stdout)

    return False, clean_log_output(result.stderr or result.stdout)


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "running"}), 200


@app.route("/webhook", methods=["POST"])
def webhook():
    start_time = time.time()

    recovery_map = load_recovery_map()

    data = request.get_json(silent=True)

    if not data:
        write_log(CRITICAL_LOG, "[ERROR] invalid or empty JSON received")
        return jsonify({"status": "error", "message": "invalid json"}), 400

    alerts = data.get("alerts", [])

    for alert in alerts:
        labels = alert.get("labels", {})

        status = alert.get("status", "firing")

        if status != "firing":
            duration = round(time.time() - start_time, 2)
            write_log(
                RECOVERY_LOG,
                f"[SKIP] duration={duration}s alertname={labels.get('alertname', 'UNKNOWN')} status={status} reason=not_firing"
            )
            continue

        alertname = labels.get("alertname")
        instance = labels.get("instance")
        severity = labels.get("severity", "unknown")

        recovery_info = recovery_map.get(alertname)

        if not recovery_info:
            duration = round(time.time() - start_time, 2)
            write_log(
                CRITICAL_LOG,
                f"[NO_MAP] duration={duration}s alertname={alertname} instance={instance} severity={severity}"
            )

            send_slack(
                f"⚠️ [NO_MAP]\n"
                f"alertname={alertname}\n"
                f"instance={instance}\n"
                f"duration={duration}s"
            )
            continue

        script_path = BASE_DIR / recovery_info.get("script", "")
        target_group = recovery_info.get("target_group", "")
        service_name = recovery_info.get("service_name", "")
        retry = recovery_info.get("retry", 1)
        cooldown = recovery_info.get("cooldown", 0)

        cooldown_active, remaining = is_cooldown_active(
            alertname,
            instance,
            cooldown
        )

        if cooldown_active:
            duration = round(time.time() - start_time, 2)
            write_log(
                RECOVERY_LOG,
                f"[SKIP] duration={duration}s alertname={alertname} instance={instance} target_group={target_group} service_name={service_name} reason=cooldown_active remaining={remaining}s"
            )
            continue

        if not script_path.exists():
            write_log(
                CRITICAL_LOG,
                f"[SCRIPT_NOT_FOUND] alertname={alertname} script={script_path}"
            )
            continue

        command = [str(script_path)]

        if target_group:
            command.append(target_group)

        if service_name:
            command.append(service_name)

        last_result = None
        last_failure_reason = "unknown_error"

        for attempt in range(1, retry + 1):

            try:
                result = subprocess.run(
                    command,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    universal_newlines=True,
                    timeout=60
                )

            except subprocess.TimeoutExpired:
                last_failure_reason = "script_timeout"
                duration = round(time.time() - start_time, 2)
                write_log(
                    RECOVERY_LOG,
                    f"[RETRY] duration={duration}s alertname={alertname} instance={instance} "
                    f"target_group={target_group} service_name={service_name} "
                    f"severity={severity} attempt={attempt}/{retry} "
                    f"reason=script_timeout"
                )

                continue

            last_result = result

            clean_output = " | ".join(
                line.strip()
                for line in result.stdout.strip().splitlines()
                if line.strip()
            )

            if result.returncode == 0:
                verify_info = recovery_info.get("verify", {})
                verify_success, verify_output = run_verify(verify_info)

                if verify_success:
                    update_recovery_time(alertname, instance)
                    duration = round(time.time() - start_time, 2)
                    write_log(
                        RECOVERY_LOG,
                        f"[SUCCESS] duration={duration}s alertname={alertname} instance={instance} target_group={target_group} service_name={service_name} severity={severity} attempt={attempt}/{retry} cooldown={cooldown} verify={verify_output} output={clean_output}"
                    )

                    send_slack(
                        f"✅ [RECOVERY SUCCESS]\n"
                        f"alertname={alertname}\n"
                        f"instance={instance}\n"
                        f"service={service_name}\n"
                        f"duration={duration}s"
                    )

                    break

                last_failure_reason = "verify_failed"
                duration = round(time.time() - start_time, 2)
                write_log(
                    RECOVERY_LOG,
                    f"[RETRY] duration={duration}s alertname={alertname} instance={instance} target_group={target_group} service_name={service_name} severity={severity} attempt={attempt}/{retry} reason=verify_failed verify_error={verify_output}"
                )

                continue

            last_failure_reason = "recovery_command_failed"
            duration = round(time.time() - start_time, 2)
            write_log(
                RECOVERY_LOG,
                f"[RETRY] duration={duration}s reason=recovery_command_failed alertname={alertname} instance={instance} target_group={target_group} service_name={service_name} severity={severity} attempt={attempt}/{retry} error={result.stderr.strip()}"
            )

        else:
            duration = round(time.time() - start_time, 2)
            write_log(
                CRITICAL_LOG,
                f"[FAILED] duration={duration}s reason={last_failure_reason} alertname={alertname} instance={instance} target_group={target_group} service_name={service_name} severity={severity} retry={retry} error={last_result.stderr.strip() if last_result else 'unknown error'}"
            )

            send_slack(
                    f"🚨 [RECOVERY FAILED]\n"
                    f"alertname={alertname}\n"
                    f"instance={instance}\n"
                    f"service={service_name}\n"
                    f"reason={last_failure_reason}\n"
                    f"duration={duration}s"
            )

    return jsonify({"status": "ok"}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)