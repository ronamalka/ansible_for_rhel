#!/usr/bin/env bash
# Bootstrap RHEL demo on a fresh OpenTLC AAP + OpenShift environment.
# Creates project, inventory, credential, job templates, workflow, and self-service RBAC.
# Requires: CONTROLLER_PASSWORD, DEMO_USER_PASSWORD; optional SSH key via WORKSHOP_SSH_KEY_FILE.
set -euo pipefail

CONTROLLER="${CONTROLLER:-https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com}"
CONTROLLER_USER="${CONTROLLER_USER:-admin}"
CONTROLLER_PASSWORD="${CONTROLLER_PASSWORD:-}"
CONTROLLER_TOKEN="${CONTROLLER_TOKEN:-}"
DEMO_USER_PASSWORD="${DEMO_USER_PASSWORD:?Set DEMO_USER_PASSWORD}"

ORGANIZATION_ID="${ORGANIZATION_ID:-1}"
PROJECT_NAME="${PROJECT_NAME:-RHEL Demo Project}"
PROJECT_SCM_URL="${PROJECT_SCM_URL:-https://github.com/ronamalka/ansible_for_rhel.git}"
INVENTORY_NAME="${INVENTORY_NAME:-Workshop Inventory}"
CREDENTIAL_NAME="${CREDENTIAL_NAME:-Workshop Credential}"
EE_ID="${EE_ID:-2}"
WORKSHOP_SSH_KEY_FILE="${WORKSHOP_SSH_KEY_FILE:-}"
WORKSHOP_SSH_USER="${WORKSHOP_SSH_USER:-ec2-user}"

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
  curl -sk "${auth[@]}" -o /tmp/aap_setup_resp.txt -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' -d "$2" "${CONTROLLER}$1"
}
api_patch() {
  curl -sk "${auth[@]}" -o /tmp/aap_setup_resp.txt -w '%{http_code}' \
    -X PATCH -H 'Content-Type: application/json' -d "$2" "${CONTROLLER}$1"
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

require_ok() {
  local code="$1" ctx="$2"
  if [[ "${code}" != "200" && "${code}" != "201" && "${code}" != "204" ]]; then
    echo "Failed: ${ctx} (HTTP ${code})" >&2
    cat /tmp/aap_setup_resp.txt >&2
    exit 1
  fi
}

echo "=== Controller: ${CONTROLLER} ==="

echo "=== Ensuring project: ${PROJECT_NAME} ==="
project_id="$(lookup_id "/api/v2/projects/" "name" "${PROJECT_NAME}")"
if [[ -z "${project_id}" ]]; then
  payload=$(python3 -c "
import json
print(json.dumps({
    'name': '''${PROJECT_NAME}''',
    'organization': ${ORGANIZATION_ID},
    'scm_type': 'git',
    'scm_url': '''${PROJECT_SCM_URL}''',
    'scm_branch': 'main',
    'scm_clean': True,
    'scm_delete_on_update': True,
    'scm_update_on_launch': True,
}))
")
  code=$(api_post "/api/v2/projects/" "${payload}")
  require_ok "${code}" "create project"
  project_id="$(lookup_id "/api/v2/projects/" "name" "${PROJECT_NAME}")"
fi
echo "Project id: ${project_id}"
code=$(api_post "/api/v2/projects/${project_id}/update/" "{}")
echo "Project sync launched (HTTP ${code})"

echo "=== Ensuring inventory: ${INVENTORY_NAME} ==="
inventory_id="$(lookup_id "/api/v2/inventories/" "name" "${INVENTORY_NAME}")"
if [[ -z "${inventory_id}" ]]; then
  payload=$(python3 -c "
import json
print(json.dumps({'name': '''${INVENTORY_NAME}''', 'organization': ${ORGANIZATION_ID}}))
")
  code=$(api_post "/api/v2/inventories/" "${payload}")
  require_ok "${code}" "create inventory"
  inventory_id="$(lookup_id "/api/v2/inventories/" "name" "${INVENTORY_NAME}")"
fi
echo "Inventory id: ${inventory_id}"

create_host() {
  local name="$1" ansible_host="$2"
  local host_id
  host_id="$(lookup_id "/api/v2/inventories/${inventory_id}/hosts/" "name" "${name}")"
  if [[ -z "${host_id}" ]]; then
    payload=$(python3 -c "
import json
print(json.dumps({'name': '${name}', 'variables': json.dumps({'ansible_host': '${ansible_host}'})}))
")
    code=$(api_post "/api/v2/inventories/${inventory_id}/hosts/" "${payload}")
    require_ok "${code}" "create host ${name}"
    echo "Created host ${name}"
  fi
}
create_host node1 node1.example.com
create_host node2 node2.example.com
create_host node3 node3.example.com

web_group_id="$(lookup_id "/api/v2/inventories/${inventory_id}/groups/" "name" "web")"
if [[ -z "${web_group_id}" ]]; then
  code=$(api_post "/api/v2/inventories/${inventory_id}/groups/" '{"name": "web"}')
  require_ok "${code}" "create web group"
  web_group_id="$(lookup_id "/api/v2/inventories/${inventory_id}/groups/" "name" "web")"
fi
for name in node1 node2 node3; do
  hid="$(lookup_id "/api/v2/inventories/${inventory_id}/hosts/" "name" "${name}")"
  api_post "/api/v2/groups/${web_group_id}/hosts/" "{\"id\": ${hid}}" >/dev/null || true
done
echo "Inventory hosts and web group configured"

echo "=== Ensuring credential: ${CREDENTIAL_NAME} ==="
cred_id="$(lookup_id "/api/v2/credentials/" "name" "${CREDENTIAL_NAME}")"
if [[ -z "${cred_id}" ]]; then
  if [[ -z "${WORKSHOP_SSH_KEY_FILE}" || ! -f "${WORKSHOP_SSH_KEY_FILE}" ]]; then
    echo "WORKSHOP_SSH_KEY_FILE required to create ${CREDENTIAL_NAME}" >&2
    exit 1
  fi
  payload=$(python3 - "${WORKSHOP_SSH_KEY_FILE}" "${CREDENTIAL_NAME}" "${ORGANIZATION_ID}" "${WORKSHOP_SSH_USER}" <<'PY'
import json, sys
key_file, name, org, user = sys.argv[1:5]
ssh_key = open(key_file).read()
print(json.dumps({
    "name": name,
    "organization": int(org),
    "credential_type": 1,
    "inputs": {"username": user, "ssh_key_data": ssh_key},
}))
PY
)
  code=$(api_post "/api/v2/credentials/" "${payload}")
  require_ok "${code}" "create credential"
  cred_id="$(lookup_id "/api/v2/credentials/" "name" "${CREDENTIAL_NAME}")"
else
  echo "Credential already exists (id ${cred_id})"
fi
echo "Credential id: ${cred_id}"

create_job_template() {
  local name="$1" playbook="$2" limit="$3" timeout="${4:-0}" tags="${5:-}" ask_limit="${6:-false}"
  local tid
  tid="$(lookup_id "/api/v2/job_templates/" "name" "${name}")"
  if [[ -n "${tid}" ]]; then
    echo "${tid}"
    return
  fi
  payload=$(python3 -c "
import json
d = {
    'name': '''${name}''',
    'job_type': 'run',
    'inventory': ${inventory_id},
    'project': ${project_id},
    'playbook': '''${playbook}''',
    'limit': '''${limit}''',
    'become_enabled': True,
    'ask_limit_on_launch': '''${ask_limit}''' == 'true',
    'execution_environment': ${EE_ID},
}
if ${timeout} > 0: d['timeout'] = ${timeout}
if '''${tags}''': d['job_tags'] = '''${tags}'''
print(json.dumps(d))
")
  code=$(api_post "/api/v2/job_templates/" "${payload}")
  require_ok "${code}" "create job template ${name}"
  lookup_id "/api/v2/job_templates/" "name" "${name}"
}

echo "=== Ensuring DEMO job templates ==="
T_PATCH=$(create_job_template "DEMO - Patch RHEL Servers" "playbooks/patch_rhel.yml" "web" 0 "" false)
T_SCAN=$(create_job_template "DEMO - OpenSCAP Scan" "playbooks/openscap_scan.yml" "web" 1800 "scan" true)
T_REM=$(create_job_template "DEMO - OpenSCAP Remediate" "playbooks/openscap_remediate.yml" "web" 3600 "remediate" true)
T_DEP=$(create_job_template "DEMO - Deploy Web Application" "playbooks/deploy_application.yml" "web" 0 "" true)
T_VER=$(create_job_template "DEMO - Verify Web Application" "playbooks/verify_application.yml" "web" 0 "" true)
echo "Template IDs: patch=${T_PATCH} scan=${T_SCAN} remediate=${T_REM} deploy=${T_DEP} verify=${T_VER}"

for tid in ${T_PATCH} ${T_SCAN} ${T_REM} ${T_DEP} ${T_VER}; do
  code=$(api_post "/api/v2/job_templates/${tid}/credentials/" "{\"id\": ${cred_id}}")
  echo "Attached credential to template ${tid} (HTTP ${code})"
done

code=$(curl -sk "${auth[@]}" -o /tmp/aap_setup_resp.txt -w '%{http_code}' \
  -X POST -H 'Content-Type: application/json' \
  -d @"${SCRIPT_DIR}/patch-rhel-survey.json" \
  "${CONTROLLER}/api/v2/job_templates/${T_PATCH}/survey_spec/")
echo "Patch survey (HTTP ${code})"
code=$(api_patch "/api/v2/job_templates/${T_PATCH}/" '{"survey_enabled": true, "extra_vars": "security_only: false\nreboot_after_patch: false"}')
echo "Patch survey enabled (HTTP ${code})"

code=$(api_patch "/api/v2/job_templates/${T_VER}/" '{"become_enabled": false}')

wf_id="$(lookup_id "/api/v2/workflow_job_templates/" "name" "DEMO - RHEL Operations Pipeline")"
if [[ -z "${wf_id}" ]]; then
  payload=$(python3 -c "
import json
print(json.dumps({'name': 'DEMO - RHEL Operations Pipeline', 'organization': ${ORGANIZATION_ID}, 'inventory': ${inventory_id}}))
")
  code=$(api_post "/api/v2/workflow_job_templates/" "${payload}")
  require_ok "${code}" "create workflow"
  wf_id="$(lookup_id "/api/v2/workflow_job_templates/" "name" "DEMO - RHEL Operations Pipeline")"
fi
echo "Workflow id: ${wf_id}"

# Workflow nodes (recreate if empty)
node_count=$(api_get "/api/v2/workflow_job_templates/${wf_id}/workflow_nodes/" | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))")
if [[ "${node_count}" == "0" ]]; then
  declare -a NODES=(${T_PATCH} ${T_SCAN} ${T_REM} ${T_DEP} ${T_VER})
  prev=""
  for i in "${!NODES[@]}"; do
    uid="${NODES[$i]}"
    payload=$(python3 -c "
import json
print(json.dumps({'unified_job_template': ${uid}, 'identifier': 'node${i}'}))
")
    code=$(api_post "/api/v2/workflow_job_templates/${wf_id}/workflow_nodes/" "${payload}")
    require_ok "${code}" "workflow node ${i}"
    nid=$(api_get "/api/v2/workflow_job_templates/${wf_id}/workflow_nodes/" | python3 -c "
import sys,json
for r in json.load(sys.stdin)['results']:
    if r.get('identifier')=='node${i}': print(r['id']); break
")
    if [[ -n "${prev}" ]]; then
      api_post "/api/v2/workflow_job_template_nodes/${prev}/success_nodes/" "{\"id\": ${nid}}" >/dev/null
    fi
    prev="${nid}"
  done
  echo "Workflow nodes linked"
fi

export CONTROLLER CONTROLLER_USER CONTROLLER_PASSWORD CONTROLLER_TOKEN DEMO_USER_PASSWORD
export DEMO_TEMPLATE_IDS="${T_PATCH} ${T_SCAN} ${T_REM} ${T_DEP} ${T_VER}"
export WORKFLOW_TEMPLATE_ID="${wf_id}"
export WORKSHOP_CREDENTIAL_ID="${cred_id}"

python3 - "${SCRIPT_DIR}/demo-template-metadata.json" <<PY
import json, os, subprocess, sys
meta_path = sys.argv[1]
with open(meta_path) as f:
    meta = json.load(f)
# Remap hardcoded ids to discovered ids
ids = [int(x) for x in os.environ["DEMO_TEMPLATE_IDS"].split()]
wf = int(os.environ["WORKFLOW_TEMPLATE_ID"])
meta["job_templates"] = {str(ids[i]): list(meta["job_templates"].values())[i] for i in range(len(ids))}
meta["workflow_job_templates"] = {str(wf): list(meta["workflow_job_templates"].values())[0]}
with open("/tmp/demo-template-metadata-runtime.json", "w") as f:
    json.dump(meta, f, indent=2)
PY
export METADATA_FILE="/tmp/demo-template-metadata-runtime.json"
"${SCRIPT_DIR}/configure-self-service.sh"

cat <<EOF

=== Setup complete ===
Project id:        ${project_id}
Inventory id:      ${inventory_id}
Credential id:     ${cred_id}
Job templates:     ${T_PATCH} ${T_SCAN} ${T_REM} ${T_DEP} ${T_VER}
Workflow id:       ${wf_id}
Controller URL:    ${CONTROLLER}
EOF
