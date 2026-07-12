#!/usr/bin/env bash
# Trigger a Controller SCM sync for the RHEL Demo Project (default id 43 on jmvv9).
set -euo pipefail

CONTROLLER="${CONTROLLER:-https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com}"
CONTROLLER_USER="${CONTROLLER_USER:-admin}"
CONTROLLER_PASSWORD="${CONTROLLER_PASSWORD:-}"
CONTROLLER_TOKEN="${CONTROLLER_TOKEN:-}"
PROJECT_ID="${PROJECT_ID:-43}"

if [[ -n "${CONTROLLER_TOKEN}" ]]; then
  auth=(-H "Authorization: Bearer ${CONTROLLER_TOKEN}")
elif [[ -n "${CONTROLLER_PASSWORD}" ]]; then
  auth=(-u "${CONTROLLER_USER}:${CONTROLLER_PASSWORD}")
else
  echo "Set CONTROLLER_TOKEN or CONTROLLER_PASSWORD" >&2
  exit 1
fi

echo "=== Syncing Controller project ${PROJECT_ID} from SCM ==="
code="$(curl -sk "${auth[@]}" -o /tmp/sync-demo-project.txt -w '%{http_code}' \
  -X POST -H 'Content-Type: application/json' \
  -d '{}' \
  "${CONTROLLER}/api/v2/projects/${PROJECT_ID}/update/")"

if [[ "${code}" != "200" && "${code}" != "201" ]]; then
  echo "Project sync failed (HTTP ${code})" >&2
  cat /tmp/sync-demo-project.txt >&2
  exit 1
fi

python3 - <<'PY'
import json
from pathlib import Path

data = json.loads(Path("/tmp/sync-demo-project.txt").read_text())
print(f"Sync job id: {data.get('id')}")
print(f"Status: {data.get('status')}")
print(f"Project: {data.get('summary_fields', {}).get('project', {}).get('name', data.get('project'))}")
PY

echo "=== Project sync launched ==="
