#!/usr/bin/env bash
# Create/update DEMO - Deploy App on OpenShift job template on jmvv9.
set -euo pipefail

CONTROLLER="${CONTROLLER:-https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com}"
CONTROLLER_USER="${CONTROLLER_USER:-admin}"
CONTROLLER_PASSWORD="${CONTROLLER_PASSWORD:-}"
CONTROLLER_TOKEN="${CONTROLLER_TOKEN:-}"

PROJECT_ID="${PROJECT_ID:-43}"
INVENTORY_ID="${INVENTORY_ID:-1}"
CREDENTIAL_ID="${CREDENTIAL_ID:-34}"
EE_ID="${EE_ID:-2}"
DEMO_LABEL_ID="${DEMO_LABEL_ID:-}"

TEMPLATE_NAME="${TEMPLATE_NAME:-DEMO - Deploy App on OpenShift}"
PLAYBOOK="${PLAYBOOK:-playbooks/deploy_openshift_app.yml}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${CONTROLLER_TOKEN}" ]]; then
  auth=(-H "Authorization: Bearer ${CONTROLLER_TOKEN}")
elif [[ -n "${CONTROLLER_PASSWORD}" ]]; then
  auth=(-u "${CONTROLLER_USER}:${CONTROLLER_PASSWORD}")
else
  echo "Set CONTROLLER_TOKEN or CONTROLLER_PASSWORD" >&2
  exit 1
fi

api_get() { curl -sk "${auth[@]}" "${CONTROLLER}$1"; }
api_post() {
  curl -sk "${auth[@]}" -o /tmp/ocp_deploy_setup_resp.txt -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' -d "$2" "${CONTROLLER}$1"
}
api_patch() {
  curl -sk "${auth[@]}" -o /tmp/ocp_deploy_setup_resp.txt -w '%{http_code}' \
    -X PATCH -H 'Content-Type: application/json' -d "$2" "${CONTROLLER}$1"
}

require_ok() {
  local code="$1" ctx="$2"
  if [[ "${code}" != "200" && "${code}" != "201" && "${code}" != "204" ]]; then
    echo "Failed: ${ctx} (HTTP ${code})" >&2
    cat /tmp/ocp_deploy_setup_resp.txt >&2
    exit 1
  fi
}

lookup_id() {
  local endpoint="$1" field="$2" value="$3"
  api_get "${endpoint}" | python3 -c "
import sys, json
field, value = '''${field}''', '''${value}'''
for item in json.load(sys.stdin).get('results', []):
    if item.get(field) == value:
        print(item['id']); break
"
}

echo "=== Ensuring job template: ${TEMPLATE_NAME} ==="
template_id="$(lookup_id "/api/v2/job_templates/" "name" "${TEMPLATE_NAME}")"
if [[ -z "${template_id}" ]]; then
  payload=$(python3 -c "
import json
print(json.dumps({
    'name': '''${TEMPLATE_NAME}''',
    'description': 'Deploy the demo Flask web application on OpenShift in a survey-selected namespace. Uses Tekton when Pipelines is installed, otherwise direct Deployment/Service/Route. Emits DEMO_OCP_DEPLOY_PORTAL markers for the portal.',
    'job_type': 'run',
    'inventory': ${INVENTORY_ID},
    'project': ${PROJECT_ID},
    'playbook': '''${PLAYBOOK}''',
    'become_enabled': False,
    'execution_environment': ${EE_ID},
}))
")
  code=$(api_post "/api/v2/job_templates/" "${payload}")
  require_ok "${code}" "create job template"
  template_id="$(lookup_id "/api/v2/job_templates/" "name" "${TEMPLATE_NAME}")"
  echo "Created job template id: ${template_id}"
else
  payload=$(python3 -c "
import json
print(json.dumps({
    'playbook': '''${PLAYBOOK}''',
    'inventory': ${INVENTORY_ID},
    'project': ${PROJECT_ID},
    'become_enabled': False,
}))
")
  code=$(api_patch "/api/v2/job_templates/${template_id}/" "${payload}")
  require_ok "${code}" "update job template"
  echo "Updated job template id: ${template_id}"
fi

code=$(api_post "/api/v2/job_templates/${template_id}/credentials/" "{\"id\": ${CREDENTIAL_ID}}")
if [[ "${code}" == "204" || "${code}" == "200" ]]; then
  echo "Attached OpenShift credential ${CREDENTIAL_ID} to template ${template_id}"
else
  echo "Credential attach returned HTTP ${code} (may already be attached)"
fi

echo "=== Configuring survey ==="
code=$(curl -sk "${auth[@]}" -o /tmp/ocp_deploy_setup_resp.txt -w '%{http_code}' \
  -X POST -H 'Content-Type: application/json' \
  -d @"${SCRIPT_DIR}/deploy-openshift-app-survey.json" \
  "${CONTROLLER}/api/v2/job_templates/${template_id}/survey_spec/")
require_ok "${code}" "survey spec"
code=$(api_patch "/api/v2/job_templates/${template_id}/" '{"survey_enabled": true}')
require_ok "${code}" "enable survey"
echo "Survey configured"

if [[ -z "${DEMO_LABEL_ID}" ]]; then
  DEMO_LABEL_ID="$(lookup_id "/api/v2/labels/" "name" "demo-self-service")"
fi
if [[ -n "${DEMO_LABEL_ID}" ]]; then
  code=$(api_post "/api/v2/job_templates/${template_id}/labels/" "{\"id\": ${DEMO_LABEL_ID}}")
  echo "Applied label demo-self-service (HTTP ${code})"
fi

demo_user_id="$(lookup_id "/api/v2/users/" "username" "demo-user")"
if [[ -n "${demo_user_id}" ]]; then
  execute_role_id="$(api_get "/api/v2/job_templates/${template_id}/object_roles/" | python3 -c "
import sys, json
for role in json.load(sys.stdin).get('results', []):
    if role.get('name') == 'Execute':
        print(role['id']); break
")"
  if [[ -n "${execute_role_id}" ]]; then
    code=$(api_post "/api/v2/roles/${execute_role_id}/users/" "{\"id\": ${demo_user_id}}")
    echo "Execute on template ${template_id} for demo-user (HTTP ${code})"
  fi
fi

cat <<EOF

=== OpenShift deploy job template configured ===
Job template id:  ${template_id}
Inventory id:     ${INVENTORY_ID} (localhost)
Credential id:    ${CREDENTIAL_ID} (OpenShift API token)
Playbook:         ${PLAYBOOK}

Example survey values:
  target_namespace: demo-web-lab
  app_name: demo-web
  create_namespace: true

Route URL pattern after deploy:
  https://<app_name>-<target_namespace>.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/

Portal tile: import controller/portal-templates/deploy-openshift-app-summary.yaml
EOF
