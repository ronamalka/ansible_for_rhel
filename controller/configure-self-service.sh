#!/usr/bin/env bash
# Configure Ansible Automation Platform for self-service access to DEMO templates.
# Creates demo user/team, RBAC, labels, descriptions, OAuth prerequisites.
# Run after job templates exist (see controller/job-templates.md).
set -euo pipefail

CONTROLLER="${CONTROLLER:-https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com}"
AAP_GATEWAY="${AAP_GATEWAY:-https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com}"
CONTROLLER_USER="${CONTROLLER_USER:-admin}"
CONTROLLER_PASSWORD="${CONTROLLER_PASSWORD:-}"
CONTROLLER_TOKEN="${CONTROLLER_TOKEN:-}"

DEMO_USER="${DEMO_USER:-demo-user}"
DEMO_USER_PASSWORD="${DEMO_USER_PASSWORD:?Set DEMO_USER_PASSWORD in the environment (not stored in Git)}"
DEMO_TEAM="${DEMO_TEAM:-Demo Self-Service}"
DEMO_LABEL="${DEMO_LABEL:-demo-self-service}"

ORGANIZATION_ID="${ORGANIZATION_ID:-1}"
DEMO_TEMPLATE_IDS="${DEMO_TEMPLATE_IDS:-11 12 13 14 15}"
WORKFLOW_TEMPLATE_ID="${WORKFLOW_TEMPLATE_ID:-16}"

OAUTH_APP_NAME="${OAUTH_APP_NAME:-Ansible Automation Portal}"
OAUTH_REDIRECT_URI="${OAUTH_REDIRECT_URI:-https://PLACEHOLDER/api/auth/rhaap/handler/frame}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gateway-oauth.lib.sh
. "${SCRIPT_DIR}/gateway-oauth.lib.sh"
METADATA_FILE="${METADATA_FILE:-${SCRIPT_DIR}/demo-template-metadata.json}"

if [[ -n "${CONTROLLER_TOKEN}" ]]; then
  auth=(-H "Authorization: Bearer ${CONTROLLER_TOKEN}")
elif [[ -n "${CONTROLLER_PASSWORD}" ]]; then
  auth=(-u "${CONTROLLER_USER}:${CONTROLLER_PASSWORD}")
else
  echo "Set CONTROLLER_TOKEN or CONTROLLER_PASSWORD" >&2
  exit 1
fi

if [[ -n "${CONTROLLER_TOKEN}" ]]; then
  gateway_auth=(-H "Authorization: Bearer ${CONTROLLER_TOKEN}")
elif [[ -n "${CONTROLLER_PASSWORD}" ]]; then
  gateway_auth=(-u "${CONTROLLER_USER}:${CONTROLLER_PASSWORD}")
else
  gateway_auth=("${auth[@]}")
fi

api_get() {
  curl -sk "${auth[@]}" "${CONTROLLER}$1"
}

api_post() {
  curl -sk "${auth[@]}" -o /tmp/aap_resp.txt -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' -d "$2" "${CONTROLLER}$1"
}

api_patch() {
  curl -sk "${auth[@]}" -o /tmp/aap_resp.txt -w '%{http_code}' \
    -X PATCH -H 'Content-Type: application/json' -d "$2" "${CONTROLLER}$1"
}

require_ok() {
  local code="$1" context="$2"
  if [[ "${code}" != "200" && "${code}" != "201" && "${code}" != "204" ]]; then
    echo "Failed: ${context} (HTTP ${code})" >&2
    cat /tmp/aap_resp.txt >&2
    exit 1
  fi
}

lookup_id() {
  local endpoint="$1" field="$2" value="$3"
  api_get "${endpoint}" | python3 -c "
import sys, json
field, value = '''${field}''', '''${value}'''
data = json.load(sys.stdin)
for item in data.get('results', []):
    if item.get(field) == value:
        print(item['id'])
        break
"
}

get_execute_role_id() {
  local resource_type="$1" template_id="$2"
  api_get "/api/v2/${resource_type}/${template_id}/object_roles/" | python3 -c "
import sys, json
for role in json.load(sys.stdin).get('results', []):
    if role.get('name') == 'Execute':
        print(role['id'])
        break
"
}

get_org_member_role_id() {
  api_get "/api/v2/organizations/${ORGANIZATION_ID}/object_roles/" | python3 -c "
import sys, json
for role in json.load(sys.stdin).get('results', []):
    if role.get('name') == 'Member':
        print(role['id'])
        break
"
}

echo "=== Enabling OAuth for external users (required for automation portal) ==="
code=$(api_patch "/api/v2/settings/all/" '{"ALLOW_OAUTH2_FOR_EXTERNAL_USERS": true}')
require_ok "${code}" "enable ALLOW_OAUTH2_FOR_EXTERNAL_USERS"

echo "=== Ensuring demo user: ${DEMO_USER} ==="
user_id="$(lookup_id "/api/v2/users/" "username" "${DEMO_USER}")"
if [[ -z "${user_id}" ]]; then
  payload=$(python3 -c "
import json
print(json.dumps({
    'username': '''${DEMO_USER}''',
    'password': '''${DEMO_USER_PASSWORD}''',
    'first_name': 'Demo',
    'last_name': 'User',
    'is_superuser': False,
}))
")
  code=$(api_post "/api/v2/users/" "${payload}")
  require_ok "${code}" "create user ${DEMO_USER}"
  user_id="$(lookup_id "/api/v2/users/" "username" "${DEMO_USER}")"
  echo "Created user ${DEMO_USER} (id ${user_id})"
else
  echo "User ${DEMO_USER} already exists (id ${user_id})"
fi

echo "=== Ensuring team: ${DEMO_TEAM} ==="
team_id="$(lookup_id "/api/v2/teams/" "name" "${DEMO_TEAM}")"
if [[ -z "${team_id}" ]]; then
  payload=$(python3 -c "
import json
print(json.dumps({
    'name': '''${DEMO_TEAM}''',
    'description': 'Self-service portal users for RHEL demo automations',
    'organization': ${ORGANIZATION_ID},
}))
")
  code=$(api_post "/api/v2/teams/" "${payload}")
  require_ok "${code}" "create team ${DEMO_TEAM}"
  team_id="$(lookup_id "/api/v2/teams/" "name" "${DEMO_TEAM}")"
  echo "Created team ${DEMO_TEAM} (id ${team_id})"
else
  echo "Team ${DEMO_TEAM} already exists (id ${team_id})"
fi

code=$(api_post "/api/v2/teams/${team_id}/users/" "{\"id\": ${user_id}}")
if [[ "${code}" != "204" && "${code}" != "200" ]]; then
  echo "Note: add user to team returned HTTP ${code} (may already be a member)"
fi

echo "=== Ensuring label: ${DEMO_LABEL} ==="
label_id="$(lookup_id "/api/v2/labels/" "name" "${DEMO_LABEL}")"
if [[ -z "${label_id}" ]]; then
  payload=$(python3 -c "
import json
print(json.dumps({'name': '''${DEMO_LABEL}''', 'organization': ${ORGANIZATION_ID}}))
")
  code=$(api_post "/api/v2/labels/" "${payload}")
  require_ok "${code}" "create label ${DEMO_LABEL}"
  label_id="$(lookup_id "/api/v2/labels/" "name" "${DEMO_LABEL}")"
  echo "Created label ${DEMO_LABEL} (id ${label_id})"
else
  echo "Label ${DEMO_LABEL} already exists (id ${label_id})"
fi

echo "=== Granting organization membership ==="
member_role_id="$(get_org_member_role_id)"
code=$(api_post "/api/v2/roles/${member_role_id}/users/" "{\"id\": ${user_id}}")
if [[ "${code}" != "204" && "${code}" != "200" ]]; then
  echo "Note: org member role returned HTTP ${code} (may already be assigned)"
fi

echo "=== Gateway organization membership (required for portal OAuth sign-in) ==="
gateway_user_id="$(gateway_oauth_api_get "/api/gateway/v1/users/?username=${DEMO_USER}" | python3 -c "
import sys, json
results = json.load(sys.stdin).get('results', [])
print(results[0]['id'] if results else '')
")"
if [[ -n "${gateway_user_id}" ]]; then
  ensure_gateway_org_member "${gateway_user_id}" "${ORGANIZATION_ID}"
else
  echo "Warning: Gateway user ${DEMO_USER} not found; portal login may fail until org membership is assigned" >&2
fi

echo "=== Granting Execute on DEMO job templates ==="
for template_id in ${DEMO_TEMPLATE_IDS}; do
  role_id="$(get_execute_role_id "job_templates" "${template_id}")"
  code=$(api_post "/api/v2/roles/${role_id}/users/" "{\"id\": ${user_id}}")
  if [[ "${code}" == "204" || "${code}" == "200" ]]; then
    echo "Execute on job template ${template_id} (role ${role_id})"
  else
    echo "Note: Execute on job template ${template_id} returned HTTP ${code}"
  fi
done

echo "=== Granting Execute on workflow template ${WORKFLOW_TEMPLATE_ID} ==="
wf_role_id="$(get_execute_role_id "workflow_job_templates" "${WORKFLOW_TEMPLATE_ID}")"
code=$(api_post "/api/v2/roles/${wf_role_id}/users/" "{\"id\": ${user_id}}")
if [[ "${code}" == "204" || "${code}" == "200" ]]; then
  echo "Execute on workflow ${WORKFLOW_TEMPLATE_ID} (role ${wf_role_id})"
else
  echo "Note: Execute on workflow ${WORKFLOW_TEMPLATE_ID} returned HTTP ${code}"
fi

echo "=== Updating descriptions and labels from ${METADATA_FILE} ==="
python3 - "${METADATA_FILE}" "${label_id}" <<'PY'
import json, subprocess, sys

metadata_file, label_id = sys.argv[1], sys.argv[2]
with open(metadata_file) as f:
    meta = json.load(f)

controller = __import__("os").environ.get("CONTROLLER", "https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com")
token = __import__("os").environ.get("CONTROLLER_TOKEN", "")
user = __import__("os").environ.get("CONTROLLER_USER", "admin")
password = __import__("os").environ.get("CONTROLLER_PASSWORD", "")

def curl_auth_cmd():
    if token:
        return ["-H", f"Authorization: Bearer {token}"]
    return ["-u", f"{user}:{password}"]

def curl(method, path, data=None):
    cmd = ["curl", "-sk"] + curl_auth_cmd() + ["-o", "/dev/null", "-X", method, "-H", "Content-Type: application/json"]
    if data is not None:
        cmd += ["-d", json.dumps(data)]
    cmd.append(f"{controller}{path}")
    subprocess.run(cmd, check=True)

for tid, info in meta.get("job_templates", {}).items():
    curl("PATCH", f"/api/v2/job_templates/{tid}/", {"description": info["description"]})
    result = subprocess.run(
        ["curl", "-sk"] + curl_auth_cmd() + ["-o", "/dev/null", "-w", "%{http_code}",
         "-X", "POST", "-H", "Content-Type: application/json",
         "-d", json.dumps({"id": int(label_id)}),
         f"{controller}/api/v2/job_templates/{tid}/labels/"],
        capture_output=True, text=True,
    )
    print(f"Updated job template {tid}: {info['name']} (label HTTP {result.stdout.strip()})")

for tid, info in meta.get("workflow_job_templates", {}).items():
    curl("PATCH", f"/api/v2/workflow_job_templates/{tid}/", {"description": info["description"]})
    result = subprocess.run(
        ["curl", "-sk"] + curl_auth_cmd() + ["-o", "/dev/null", "-w", "%{http_code}",
         "-X", "POST", "-H", "Content-Type: application/json",
         "-d", json.dumps({"id": int(label_id)}),
         f"{controller}/api/v2/workflow_job_templates/{tid}/labels/"],
        capture_output=True, text=True,
    )
    print(f"Updated workflow template {tid}: {info['name']} (label HTTP {result.stdout.strip()})")
PY

echo "=== Ensuring OAuth application for automation portal ==="
oauth_id="$(lookup_id "/api/v2/applications/" "name" "${OAUTH_APP_NAME}")"
if [[ -z "${oauth_id}" ]]; then
  payload=$(python3 -c "
import json
print(json.dumps({
    'name': '''${OAUTH_APP_NAME}''',
    'description': 'OAuth application for self-service automation portal (update redirect URI after portal deployment)',
    'client_type': 'public',
    'authorization_grant_type': 'authorization-code',
    'redirect_uris': '''${OAUTH_REDIRECT_URI}''',
    'organization': ${ORGANIZATION_ID},
}))
")
  code=$(api_post "/api/v2/applications/" "${payload}")
  require_ok "${code}" "create OAuth application"
  echo "Created OAuth application ${OAUTH_APP_NAME}"
else
  echo "OAuth application ${OAUTH_APP_NAME} already exists (id ${oauth_id})"
  if [[ "${OAUTH_REDIRECT_URI}" != *PLACEHOLDER* ]]; then
    payload=$(python3 -c "
import json
print(json.dumps({'redirect_uris': '''${OAUTH_REDIRECT_URI}'''}))
")
    code=$(api_patch "/api/v2/applications/${oauth_id}/" "${payload}")
    require_ok "${code}" "update OAuth redirect URI"
    echo "Updated OAuth redirect URI to ${OAUTH_REDIRECT_URI}"
  fi
fi

PORTAL_OAUTH_CLIENT_ID="$(ensure_gateway_oauth_application "${OAUTH_APP_NAME}" "${OAUTH_REDIRECT_URI}" "${ORGANIZATION_ID}")"

echo "=== Verifying ${DEMO_USER} can see DEMO templates ==="
demo_auth=(-u "${DEMO_USER}:${DEMO_USER_PASSWORD}")
count=$(curl -sk "${demo_auth[@]}" \
  "${CONTROLLER}/api/v2/unified_job_templates/?search=DEMO" | python3 -c "
import sys, json
print(json.load(sys.stdin).get('count', 0))
")
expected=$(( $(echo ${DEMO_TEMPLATE_IDS} | wc -w | tr -d ' ') + 1 ))
if [[ "${count}" -ge "${expected}" ]]; then
  echo "Verification passed: ${DEMO_USER} sees ${count} DEMO template(s)"
else
  echo "Verification warning: ${DEMO_USER} sees ${count} template(s), expected at least ${expected}" >&2
fi

echo "=== Self-service controller configuration complete ==="
echo "Demo user: ${DEMO_USER}"
echo "Templates exposed: DEMO job templates ${DEMO_TEMPLATE_IDS} and workflow ${WORKFLOW_TEMPLATE_ID}"
echo "Controller templates URL: ${CONTROLLER}/#/templates"
if [[ -n "${PORTAL_OAUTH_CLIENT_ID}" ]]; then
  echo "Portal OAUTH_CLIENT_ID (Gateway — use in deploy-self-service-portal.sh): ${PORTAL_OAUTH_CLIENT_ID}"
else
  echo "Portal OAUTH_CLIENT_ID: set after Gateway OAuth app exists (see controller/self-service-setup.md)" >&2
fi
echo "Automation portal: deploy with Gateway client_id; OAUTH_CLIENT_SECRET from ${AAP_GATEWAY_OAUTH_CACHE} if app was just created"
echo "Set AAP_GATEWAY_TOKEN or let deploy script create a Gateway API token for secrets-rhaap-portal aap-token"
