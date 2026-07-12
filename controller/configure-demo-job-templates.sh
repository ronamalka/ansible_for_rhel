#!/usr/bin/env bash
# Attach Workshop Credential to DEMO job templates on Ansible Automation Controller.
# Run after creating templates from controller/job-templates.md (credentials are not in Git).
set -euo pipefail

CONTROLLER="${CONTROLLER:-https://ansible-1.4mrmx.sandbox3261.opentlc.com}"
CONTROLLER_USER="${CONTROLLER_USER:-admin}"
CONTROLLER_PASSWORD="${CONTROLLER_PASSWORD:?Set CONTROLLER_PASSWORD in the environment}"

WORKSHOP_CREDENTIAL_ID="${WORKSHOP_CREDENTIAL_ID:-4}"
# DEMO template IDs on the sandbox (Patch, Scan, Remediate, Deploy, Verify)
DEMO_TEMPLATE_IDS="${DEMO_TEMPLATE_IDS:-11 12 13 14 15}"

auth=(-u "${CONTROLLER_USER}:${CONTROLLER_PASSWORD}")

for template_id in ${DEMO_TEMPLATE_IDS}; do
  code=$(curl -sk "${auth[@]}" -o /dev/null -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' \
    -d "{\"id\": ${WORKSHOP_CREDENTIAL_ID}}" \
    "${CONTROLLER}/api/v2/job_templates/${template_id}/credentials/")
  if [[ "${code}" == "204" || "${code}" == "200" ]]; then
    echo "Attached Workshop Credential to job template ${template_id}"
  else
    echo "Failed to attach credential to job template ${template_id} (HTTP ${code})" >&2
    exit 1
  fi
done
