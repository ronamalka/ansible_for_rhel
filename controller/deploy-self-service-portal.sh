#!/usr/bin/env bash
# Deploy the AAP self-service automation portal on OpenShift (AAP 2.5+).
# Run on the bastion after controller OAuth and RBAC are configured.
set -euo pipefail

OCP_NAMESPACE="${OCP_NAMESPACE:-rhaap-portal}"
HELM_RELEASE="${HELM_RELEASE:-redhat-rhaap-portal}"
CHART_VERSION="${CHART_VERSION:-2.2.0}"
APP_CONFIG_CM="${APP_CONFIG_CM:-${HELM_RELEASE}-app-config}"
CLUSTER_ROUTER_BASE="${CLUSTER_ROUTER_BASE:-cluster-jmvv9.jmvv9.sandbox3400.opentlc.com}"

AAP_HOST_URL="${AAP_HOST_URL:-https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com}"
CONTROLLER="${CONTROLLER:-https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com}"
OAUTH_CLIENT_ID="${OAUTH_CLIENT_ID:?Set OAUTH_CLIENT_ID from AAP OAuth application}"
# Public OAuth clients have no secret; Backstage still requires a non-empty string.
OAUTH_CLIENT_SECRET="${OAUTH_CLIENT_SECRET:-public-client-no-secret}"
AAP_TOKEN="${AAP_TOKEN:?Set AAP_TOKEN (controller token with write access)}"
CONTROLLER_TOKEN="${CONTROLLER_TOKEN:-${AAP_TOKEN}}"
OAUTH_APP_ID="${OAUTH_APP_ID:-1}"
REPAIR_APP_CONFIG="${REPAIR_APP_CONFIG:-0}"

repair_app_config_configmap() {
  local cm="$1" ns="$2"
  if ! oc get configmap "${cm}" -n "${ns}" >/dev/null 2>&1; then
    echo "ConfigMap ${cm} not found in ${ns}; skip app-config repair" >&2
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  oc get configmap "${cm}" -n "${ns}" -o jsonpath='{.data.app-config\.yaml}' >"${tmp}"

  python3 - "${tmp}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

block = re.search(
    r"(?ms)^(\s+)production:\n(\1\s+orgs:\n(?:\1\s+- .+\n)+)",
    text,
)
if not block:
    sys.exit(0)

indent, orgs_block = block.group(1), block.group(0)
quoted = re.search(
    rf"(?ms)^{re.escape(indent)}'production':\n",
    text,
)
if not quoted:
    sys.exit(0)

text = text.replace(orgs_block, "", 1)
text = text.replace(f"{indent}'production':", f"{indent}production:", 1)
path.write_text(text)
print("Removed duplicate catalog.providers.rhaap.production block from app-config")
PY

  if python3 - "${tmp}" <<'PY' 2>/dev/null
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
rhaap = re.search(r"(?ms)^  providers:\n    rhaap:\n(.*?)(?=^  rules:)", text)
if not rhaap:
    sys.exit(1)
prod = len(re.findall(r"^\s+production:\s*$", rhaap.group(1), re.M))
sys.exit(0 if prod <= 1 else 1)
PY
  then
    oc create configmap "${cm}" \
      --from-file=app-config.yaml="${tmp}" \
      -n "${ns}" --dry-run=client -o yaml | oc apply -f -
    oc rollout restart "deployment/${HELM_RELEASE}" -n "${ns}" || true
    echo "=== Repaired ${cm} and restarted ${HELM_RELEASE} ==="
  else
    echo "app-config still has duplicate catalog.providers.rhaap.production keys; fix values overlay" >&2
    exit 1
  fi
  rm -f "${tmp}"
}

echo "=== Prerequisites ==="
command -v oc >/dev/null || { echo "oc required" >&2; exit 1; }
command -v helm >/dev/null || { echo "helm required (install Helm 3.10+)" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 required for app-config repair" >&2; exit 1; }
oc whoami >/dev/null

helm repo add openshift-helm-charts https://charts.openshift.io/ 2>/dev/null || true
helm repo update openshift-helm-charts

echo "=== OpenShift project: ${OCP_NAMESPACE} ==="
oc get project "${OCP_NAMESPACE}" >/dev/null 2>&1 || oc new-project "${OCP_NAMESPACE}"

echo "=== Secret: secrets-rhaap-portal ==="
oc delete secret secrets-rhaap-portal -n "${OCP_NAMESPACE}" --ignore-not-found
oc create secret generic secrets-rhaap-portal \
  --from-literal=aap-host-url="${AAP_HOST_URL}" \
  --from-literal=oauth-client-id="${OAUTH_CLIENT_ID}" \
  --from-literal=oauth-client-secret="${OAUTH_CLIENT_SECRET}" \
  --from-literal=aap-token="${AAP_TOKEN}" \
  -n "${OCP_NAMESPACE}"

echo "=== Registry auth for OCI plug-ins ==="
registry_auth_file="$(mktemp)"
if [[ -f auth.json ]]; then
  cp auth.json "${registry_auth_file}"
else
  oc get secret -n openshift-config pull-secret \
    -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d > "${registry_auth_file}"
fi
oc delete secret "${HELM_RELEASE}-dynamic-plugins-registry-auth" -n "${OCP_NAMESPACE}" --ignore-not-found
oc create secret generic "${HELM_RELEASE}-dynamic-plugins-registry-auth" \
  --from-file=auth.json="${registry_auth_file}" \
  -n "${OCP_NAMESPACE}"
rm -f "${registry_auth_file}"

if [[ "${REPAIR_APP_CONFIG}" == "1" ]]; then
  echo "=== Repairing portal app-config ConfigMap ==="
  repair_app_config_configmap "${APP_CONFIG_CM}" "${OCP_NAMESPACE}"
  exit 0
fi

values_file="$(mktemp)"
cat > "${values_file}" <<EOF
redhat-developer-hub:
  global:
    clusterRouterBase: ${CLUSTER_ROUTER_BASE}
    pluginMode: oci
    imageTagInfo: "2.2"
  upstream:
    backstage:
      extraContainers:
        - command: [adt, server]
          image: registry.redhat.io/ansible-automation-platform-25/ansible-dev-tools-rhel9:latest
          imagePullPolicy: IfNotPresent
          name: ansible-devtools-server
          ports:
            - containerPort: 8000
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
EOF

echo "=== Helm install/upgrade ${HELM_RELEASE} (chart ${CHART_VERSION}) ==="
if helm status "${HELM_RELEASE}" -n "${OCP_NAMESPACE}" >/dev/null 2>&1; then
  helm upgrade "${HELM_RELEASE}" openshift-helm-charts/redhat-rhaap-portal \
    --version "${CHART_VERSION}" \
    --namespace "${OCP_NAMESPACE}" \
    -f "${values_file}" \
    --wait --timeout 15m
else
  helm install "${HELM_RELEASE}" openshift-helm-charts/redhat-rhaap-portal \
    --version "${CHART_VERSION}" \
    --namespace "${OCP_NAMESPACE}" \
    -f "${values_file}" \
    --wait --timeout 15m
fi
rm -f "${values_file}"

portal_host="$(oc get route "${HELM_RELEASE}" -n "${OCP_NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null || true)"
if [[ -z "${portal_host}" ]]; then
  portal_host="$(oc get route -n "${OCP_NAMESPACE}" -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)"
fi
portal_url="https://${portal_host}/"
redirect_uri="https://${portal_host}/api/auth/rhaap/handler/frame"

echo "=== Portal route ==="
oc get route -n "${OCP_NAMESPACE}"
echo "Portal URL: ${portal_url}"

if [[ -n "${portal_host}" && -n "${CONTROLLER_TOKEN}" ]]; then
  echo "=== Updating OAuth redirect URI (application id ${OAUTH_APP_ID}) ==="
  http_code="$(curl -sk -o /dev/null -w '%{http_code}' -X PATCH \
    -H "Authorization: Bearer ${CONTROLLER_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"redirect_uris\": \"${redirect_uri}\"}" \
    "${CONTROLLER}/api/v2/applications/${OAUTH_APP_ID}/")"
  echo "OAuth redirect update HTTP ${http_code}: ${redirect_uri}"
fi

cat <<EOF

=== Next steps ===
1. Configure portal RBAC in Administration → RBAC for demo-user / Demo Self-Service team
2. Sign in at ${portal_url} with demo-user credentials
3. If duplicate app-config keys cause CrashLoopBackOff: REPAIR_APP_CONFIG=1 $0

EOF
