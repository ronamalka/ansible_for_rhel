#!/usr/bin/env bash
# Deploy the AAP self-service automation portal on OpenShift (AAP 2.5+).
# Run on the bastion after controller OAuth and RBAC are configured.
set -euo pipefail

OCP_NAMESPACE="${OCP_NAMESPACE:-rhaap-portal}"
HELM_RELEASE="${HELM_RELEASE:-redhat-rhaap-portal}"
CLUSTER_ROUTER_BASE="${CLUSTER_ROUTER_BASE:-cluster-jmvv9.jmvv9.sandbox3400.opentlc.com}"

# Gateway URL (not the direct controller route)
AAP_HOST_URL="${AAP_HOST_URL:-https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com}"
OAUTH_CLIENT_ID="${OAUTH_CLIENT_ID:?Set OAUTH_CLIENT_ID from AAP OAuth application}"
OAUTH_CLIENT_SECRET="${OAUTH_CLIENT_SECRET:-}"
AAP_TOKEN="${AAP_TOKEN:?Set AAP_TOKEN (controller token with write access)}"

echo "=== Prerequisites ==="
command -v oc >/dev/null || { echo "oc required" >&2; exit 1; }
command -v helm >/dev/null || { echo "helm required (install Helm 3.10+)" >&2; exit 1; }
oc whoami >/dev/null

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

echo "=== Registry auth for OCI plug-ins (if using OCI mode) ==="
if [[ -f auth.json ]]; then
  oc create secret generic "${HELM_RELEASE}-dynamic-plugins-registry-auth" \
    --from-file=auth.json=./auth.json \
    -n "${OCP_NAMESPACE}" --dry-run=client -o yaml | oc apply -f -
fi

cat <<EOF

=== Helm install (manual step) ===
Install the Automation Portal chart from the OpenShift Developer catalog (Helm → Automation Portal)
or from a downloaded chart package. Example values:

  redhat-developer-hub:
    global:
      clusterRouterBase: ${CLUSTER_ROUTER_BASE}
      pluginMode: oci

Then update the OAuth redirect URI on AAP:
  Access Management → OAuth Applications → Ansible Automation Portal
  Redirect URI: https://<portal-route>/api/auth/rhaap/handler/frame

Portal route: oc get route -n ${OCP_NAMESPACE}

EOF
