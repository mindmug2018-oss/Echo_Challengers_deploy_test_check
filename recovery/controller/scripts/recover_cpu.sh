#!/bin/bash

TARGET_GROUP="$1"
SERVICE_NAME="${2:-cpu}"
MODE="${RECOVERY_MODE:-mock}"
INVENTORY="${ANSIBLE_INVENTORY:-/home/user1/project1-aws/terraform/inventory.yml}"

if [ -z "$TARGET_GROUP" ]; then
  echo "[ERROR] target_group is empty" >&2
  exit 1
fi

echo "[RECOVERY START]"
echo "mode=${MODE}"
echo "target_group=${TARGET_GROUP}"
echo "service_name=${SERVICE_NAME}"
echo "action=kill_cpu_stress_process"

if [ "$MODE" = "mock" ]; then
  echo "[MOCK] ansible ${TARGET_GROUP} -i ${INVENTORY} -m shell -a 'sudo pkill -f stress-ng || sudo pkill -f stress || true'"
  exit 0
fi

if [ "$MODE" = "ansible" ]; then
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/bin

  ANSIBLE_HOST_KEY_CHECKING=False \
  ANSIBLE_PYTHON_INTERPRETER=auto_silent \
  /usr/bin/ansible "$TARGET_GROUP" \
    -i "$INVENTORY" \
    -m shell \
    -a "sudo pkill -f stress-ng || sudo pkill -f stress || true"

  exit $?
fi