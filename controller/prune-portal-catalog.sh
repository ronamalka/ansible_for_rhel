#!/usr/bin/env bash
# Remove specific templates from the automation portal catalog (jmvv9).
# Does not delete Controller job templates — only catalog visibility.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OCP_NAMESPACE="${OCP_NAMESPACE:-rhaap-portal}"
PG_POD="${PG_POD:-redhat-rhaap-portal-postgresql-0}"
APP_CONFIG_CM="${APP_CONFIG_CM:-redhat-rhaap-portal-app-config}"
HELM_RELEASE="${HELM_RELEASE:-redhat-rhaap-portal}"
CONTROLLER="${CONTROLLER:-https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com}"
CONTROLLER_TOKEN="${CONTROLLER_TOKEN:-${AAP_TOKEN:-}}"
DEMO_LABEL="${DEMO_LABEL:-demo-self-service}"
PATCH_APP_CONFIG="${PATCH_APP_CONFIG:-1}"
RESTART_PORTAL="${RESTART_PORTAL:-0}"

# Controller job template IDs to drop from portal (remove demo-self-service label)
UNPUBLISH_TEMPLATE_IDS="${UNPUBLISH_TEMPLATE_IDS:-44 47 48 51}"
# Keep visible via label filter (OpenSCAP + seed)
PUBLISH_TEMPLATE_IDS="${PUBLISH_TEMPLATE_IDS:-45 46 50}"

REMOVED_ENTITY_REFS=(
  "template:default/createvolumesnapshot"
  "template:default/demo--deploy-web-application"
  "template:default/demo-deploy-web-app-summary"
  "template:default/demo-job-template"
  "template:default/demo--patch-rhel-servers"
  "template:default/demo-patch-rhel-package-summary"
  "template:default/demo--verify-web-application"
  "template:default/demo-verify-web-app-summary"
  "template:default/patchroutewithcert"
  "template:default/setresourcequotaonnamespace"
)

command -v oc >/dev/null || { echo "oc required" >&2; exit 1; }

pg_password() {
  oc get secret redhat-rhaap-portal-postgresql -n "${OCP_NAMESPACE}" \
    -o jsonpath='{.data.postgres-password}' | base64 -d
}

psql_catalog() {
  local PGPASS
  PGPASS="$(pg_password)"
  oc exec -n "${OCP_NAMESPACE}" "${PG_POD}" -- \
    env PGPASSWORD="${PGPASS}" psql -U postgres -d backstage_plugin_catalog -v ON_ERROR_STOP=1 "$@"
}

api_label_id() {
  curl -sk -H "Authorization: Bearer ${CONTROLLER_TOKEN}" \
    "${CONTROLLER}/api/v2/labels/?name=${DEMO_LABEL}" \
    | python3 -c "import json,sys; r=json.load(sys.stdin)['results']; print(r[0]['id'] if r else '')"
}

if [[ -n "${CONTROLLER_TOKEN}" ]]; then
  label_id="$(api_label_id)"
  if [[ -n "${label_id}" ]]; then
    echo "=== Controller labels (${DEMO_LABEL} id=${label_id}) ==="
    for tid in ${UNPUBLISH_TEMPLATE_IDS}; do
      curl -sk -H "Authorization: Bearer ${CONTROLLER_TOKEN}" -H "Content-Type: application/json" \
        -X POST "${CONTROLLER}/api/v2/job_templates/${tid}/labels/" \
        -d "{\"disassociate\":true,\"id\":${label_id}}" >/dev/null
      echo "Removed label from job template ${tid}"
    done
    for tid in ${PUBLISH_TEMPLATE_IDS}; do
      curl -sk -H "Authorization: Bearer ${CONTROLLER_TOKEN}" -H "Content-Type: application/json" \
        -X POST "${CONTROLLER}/api/v2/job_templates/${tid}/labels/" \
        -d "{\"id\":${label_id}}" >/dev/null || true
      echo "Ensured label on job template ${tid}"
    done
  else
    echo "WARN: label ${DEMO_LABEL} not found; skip controller label updates" >&2
  fi
else
  echo "WARN: CONTROLLER_TOKEN not set; skip controller label updates" >&2
fi

if [[ "${PATCH_APP_CONFIG}" == "1" ]]; then
  echo "=== Patching ${APP_CONFIG_CM} jobTemplates label filter ==="
  tmp="$(mktemp)"
  oc get configmap "${APP_CONFIG_CM}" -n "${OCP_NAMESPACE}" -o jsonpath='{.data.app-config\.yaml}' >"${tmp}"
  python3 "${SCRIPT_DIR}/patch-portal-catalog-filter.py" "${tmp}"
  oc create configmap "${APP_CONFIG_CM}" \
    --from-file=app-config.yaml="${tmp}" \
    -n "${OCP_NAMESPACE}" --dry-run=client -o yaml | oc apply -f -
  rm -f "${tmp}"
  if [[ "${RESTART_PORTAL}" == "1" ]]; then
    oc rollout restart "deployment/${HELM_RELEASE}" -n "${OCP_NAMESPACE}"
    oc rollout status "deployment/${HELM_RELEASE}" -n "${OCP_NAMESPACE}" --timeout=300s || true
  fi
fi

echo "=== Deleting catalog entities from PostgreSQL ==="
refs_sql="$(printf "'%s'," "${REMOVED_ENTITY_REFS[@]}")"
refs_sql="${refs_sql%,}"
psql_catalog -c "DELETE FROM refresh_state WHERE entity_ref IN (${refs_sql});"

echo "=== Remaining portal templates ==="
psql_catalog -t -A -c "SELECT entity_ref FROM final_entities WHERE entity_ref LIKE 'template:%' ORDER BY 1;"

echo "=== Done. Custom Location entries orphan-delete when catalog-info.yaml is updated on GitHub. ==="
