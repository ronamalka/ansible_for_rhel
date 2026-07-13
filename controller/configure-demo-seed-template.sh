#!/usr/bin/env bash
# Create/update DEMO seed job template and prepend it to workflow 49 on jmvv9.
# Also refreshes the patch template survey (seed_demo_packages question).
set -euo pipefail

CONTROLLER="${CONTROLLER:-https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com}"
CONTROLLER_USER="${CONTROLLER_USER:-admin}"
CONTROLLER_PASSWORD="${CONTROLLER_PASSWORD:-}"
CONTROLLER_TOKEN="${CONTROLLER_TOKEN:-}"

PROJECT_ID="${PROJECT_ID:-43}"
INVENTORY_ID="${INVENTORY_ID:-34}"
CREDENTIAL_ID="${CREDENTIAL_ID:-35}"
EE_ID="${EE_ID:-2}"
PATCH_TEMPLATE_ID="${PATCH_TEMPLATE_ID:-44}"
WORKFLOW_ID="${WORKFLOW_ID:-49}"

SEED_TEMPLATE_NAME="${SEED_TEMPLATE_NAME:-DEMO - Seed Patch Demo Packages}"
SEED_PLAYBOOK="${SEED_PLAYBOOK:-playbooks/seed_patch_demo.yml}"

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
  curl -sk "${auth[@]}" -o /tmp/seed_setup_resp.txt -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' -d "$2" "${CONTROLLER}$1"
}
api_patch() {
  curl -sk "${auth[@]}" -o /tmp/seed_setup_resp.txt -w '%{http_code}' \
    -X PATCH -H 'Content-Type: application/json' -d "$2" "${CONTROLLER}$1"
}

require_ok() {
  local code="$1" ctx="$2"
  if [[ "${code}" != "200" && "${code}" != "201" && "${code}" != "204" ]]; then
    echo "Failed: ${ctx} (HTTP ${code})" >&2
    cat /tmp/seed_setup_resp.txt >&2
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

echo "=== Ensuring seed job template: ${SEED_TEMPLATE_NAME} ==="
seed_id="$(lookup_id "/api/v2/job_templates/" "name" "${SEED_TEMPLATE_NAME}")"
if [[ -z "${seed_id}" ]]; then
  payload=$(python3 -c "
import json
print(json.dumps({
    'name': '''${SEED_TEMPLATE_NAME}''',
    'description': 'Downgrade host-specific packages so DEMO patch shows per-node pending updates. Idempotent; emits DEMO_PATCH_SEED portal markers.',
    'job_type': 'run',
    'inventory': ${INVENTORY_ID},
    'project': ${PROJECT_ID},
    'playbook': '''${SEED_PLAYBOOK}''',
    'limit': 'web',
    'become_enabled': True,
    'execution_environment': ${EE_ID},
}))
")
  code=$(api_post "/api/v2/job_templates/" "${payload}")
  require_ok "${code}" "create seed job template"
  seed_id="$(lookup_id "/api/v2/job_templates/" "name" "${SEED_TEMPLATE_NAME}")"
  echo "Created seed template id: ${seed_id}"
else
  payload=$(python3 -c "
import json
print(json.dumps({
    'playbook': '''${SEED_PLAYBOOK}''',
    'limit': 'web',
    'become_enabled': True,
    'project': ${PROJECT_ID},
    'inventory': ${INVENTORY_ID},
}))
")
  code=$(api_patch "/api/v2/job_templates/${seed_id}/" "${payload}")
  require_ok "${code}" "update seed job template"
  echo "Updated seed template id: ${seed_id}"
fi

code=$(api_post "/api/v2/job_templates/${seed_id}/credentials/" "{\"id\": ${CREDENTIAL_ID}}")
if [[ "${code}" == "204" || "${code}" == "200" ]]; then
  echo "Attached credential to seed template ${seed_id}"
else
  echo "Credential attach on seed template returned HTTP ${code} (may already be attached)"
fi

echo "=== Refreshing patch template survey (template ${PATCH_TEMPLATE_ID}) ==="
code=$(curl -sk "${auth[@]}" -o /tmp/seed_setup_resp.txt -w '%{http_code}' \
  -X POST -H 'Content-Type: application/json' \
  -d @"${SCRIPT_DIR}/patch-rhel-survey.json" \
  "${CONTROLLER}/api/v2/job_templates/${PATCH_TEMPLATE_ID}/survey_spec/")
require_ok "${code}" "patch survey spec"
code=$(api_patch "/api/v2/job_templates/${PATCH_TEMPLATE_ID}/" '{"survey_enabled": true}')
require_ok "${code}" "enable patch survey"
echo "Patch survey updated"

find_workflow_nodes() {
  python3 -c "
import json, sys
data = json.load(sys.stdin)
seed_tid = int('''${seed_id}''')
patch_tid = int('''${PATCH_TEMPLATE_ID}''')
seed_node = patch_node = ''
for node in data.get('results', []):
    tid = node.get('unified_job_template') or node.get('summary_fields', {}).get('unified_job_template', {}).get('id')
    if tid == seed_tid:
        seed_node = str(node['id'])
    if tid == patch_tid:
        patch_node = str(node['id'])
print(f'seed={seed_node}')
print(f'patch={patch_node}')
" <<< "${wf_nodes_json}"
}

echo "=== Ensuring workflow ${WORKFLOW_ID} starts with seed → patch ==="
wf_nodes_json="$(api_get "/api/v2/workflow_job_templates/${WORKFLOW_ID}/workflow_nodes/")"
_wf_out="$(find_workflow_nodes)"
existing_seed_node="$(printf '%s\n' "${_wf_out}" | sed -n 's/^seed=//p')"
existing_patch_node="$(printf '%s\n' "${_wf_out}" | sed -n 's/^patch=//p')"

if [[ -z "${existing_seed_node}" ]]; then
  payload=$(python3 -c "
import json
print(json.dumps({'unified_job_template': ${seed_id}, 'identifier': 'seed'}))
")
  code=$(api_post "/api/v2/workflow_job_templates/${WORKFLOW_ID}/workflow_nodes/" "${payload}")
  require_ok "${code}" "create workflow seed node"
  wf_nodes_json="$(api_get "/api/v2/workflow_job_templates/${WORKFLOW_ID}/workflow_nodes/")"
  _wf_out="$(find_workflow_nodes)"
  existing_seed_node="$(printf '%s\n' "${_wf_out}" | sed -n 's/^seed=//p')"
  existing_patch_node="$(printf '%s\n' "${_wf_out}" | sed -n 's/^patch=//p')"
  echo "Created workflow seed node ${existing_seed_node}"
fi

if [[ -z "${existing_patch_node}" ]]; then
  echo "Patch node not found in workflow ${WORKFLOW_ID}; link seed manually in the visualizer." >&2
else
  # Find nodes that currently point to the patch node (workflow parents)
  parent_ids="$(python3 -c "
import json, sys
patch_node = int('''${existing_patch_node}''')
parents = []
for node in json.load(sys.stdin).get('results', []):
    if patch_node in node.get('success_nodes', []) or patch_node in node.get('always_nodes', []):
        parents.append(str(node['id']))
print(','.join(parents))
" <<< "${wf_nodes_json}")"
  if [[ -n "${parent_ids}" ]]; then
    IFS=',' read -ra PIDS <<< "${parent_ids}"
    for pid in "${PIDS[@]}"; do
      [[ -z "${pid}" ]] && continue
      api_post "/api/v2/workflow_job_template_nodes/${pid}/success_nodes/" "{\"id\": ${existing_patch_node}, \"associate\": false}" >/dev/null || true
    done
  fi
  code=$(api_post "/api/v2/workflow_job_template_nodes/${existing_seed_node}/success_nodes/" "{\"id\": ${existing_patch_node}}")
  if [[ "${code}" == "204" || "${code}" == "201" || "${code}" == "200" ]]; then
    echo "Linked seed node ${existing_seed_node} -> patch node ${existing_patch_node} (HTTP ${code})"
  else
    echo "Warning: link seed -> patch returned HTTP ${code}; verify workflow ${WORKFLOW_ID} in the visualizer" >&2
    cat /tmp/seed_setup_resp.txt >&2 || true
  fi

  wf_nodes_json="$(api_get "/api/v2/workflow_job_templates/${WORKFLOW_ID}/workflow_nodes/")"
  seed_parents="$(python3 -c "
import json, sys
seed_node = int('''${existing_seed_node}''')
parents = []
for node in json.load(sys.stdin).get('results', []):
    if seed_node in node.get('success_nodes', []) or seed_node in node.get('always_nodes', []):
        parents.append(str(node['id']))
print(','.join(parents))
" <<< "${wf_nodes_json}")"
  if [[ -n "${seed_parents}" ]]; then
    IFS=',' read -ra SPIDS <<< "${seed_parents}"
    for pid in "${SPIDS[@]}"; do
      [[ -z "${pid}" ]] && continue
      api_post "/api/v2/workflow_job_template_nodes/${pid}/success_nodes/" "{\"id\": ${existing_seed_node}, \"associate\": false}" >/dev/null || true
    done
  fi
fi

cat <<EOF

=== Seed automation configured ===
Seed job template id:  ${seed_id}
Patch job template id: ${PATCH_TEMPLATE_ID}
Workflow id:           ${WORKFLOW_ID}
Workflow order:        Seed (${seed_id}) -> Patch (${PATCH_TEMPLATE_ID}) -> Scan -> Remediate -> Deploy -> Verify

Portal / Controller:
  - Full pipeline: launch workflow ${WORKFLOW_ID} (seed runs automatically first)
  - Patch only with re-seed: launch template ${PATCH_TEMPLATE_ID}, survey "Prepare demo updates first?" = true
  - Seed only: launch template ${seed_id}
EOF

echo "=== Granting demo-user Execute on seed template ${seed_id} ==="
demo_user_id="$(lookup_id "/api/v2/users/" "username" "demo-user")"
if [[ -n "${demo_user_id}" ]]; then
  execute_role_id="$(api_get "/api/v2/job_templates/${seed_id}/object_roles/" | python3 -c "
import sys, json
for role in json.load(sys.stdin).get('results', []):
    if role.get('name') == 'Execute':
        print(role['id']); break
")"
  if [[ -n "${execute_role_id}" ]]; then
    code=$(api_post "/api/v2/roles/${execute_role_id}/users/" "{\"id\": ${demo_user_id}}")
    echo "Execute on seed template ${seed_id} for demo-user (HTTP ${code})"
  fi
else
  echo "Note: demo-user not found; grant Execute on template ${seed_id} manually"
fi
