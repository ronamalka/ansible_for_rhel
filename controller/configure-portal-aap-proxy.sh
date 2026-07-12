#!/usr/bin/env bash
# Add Backstage proxy route for AAP Gateway so portal templates can fetch job stdout
# via the http:backstage:request scaffolder action (Authorization header from user token).
# Run on the OpenShift bastion. Idempotent.
set -euo pipefail

OCP_NAMESPACE="${OCP_NAMESPACE:-rhaap-portal}"
APP_CONFIG_CM="${APP_CONFIG_CM:-redhat-rhaap-portal-app-config}"
HELM_RELEASE="${HELM_RELEASE:-redhat-rhaap-portal}"
AAP_HOST_URL="${AAP_HOST_URL:-https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com}"
PROXY_PATH="${PROXY_PATH:-/aap-gateway}"

command -v oc >/dev/null || { echo "oc required (run on bastion)" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 1; }

if ! oc get configmap "${APP_CONFIG_CM}" -n "${OCP_NAMESPACE}" >/dev/null 2>&1; then
  echo "ConfigMap ${APP_CONFIG_CM} not found in ${OCP_NAMESPACE}" >&2
  exit 1
fi

tmp="$(mktemp)"
oc get configmap "${APP_CONFIG_CM}" -n "${OCP_NAMESPACE}" -o jsonpath='{.data.app-config\.yaml}' >"${tmp}"

result="$(python3 - "${tmp}" "${PROXY_PATH}" "${AAP_HOST_URL}" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
proxy_path = sys.argv[2]
target = sys.argv[3].rstrip("/")
text = path.read_text()

if f"  '{proxy_path}':" in text and target in text:
    print("unchanged")
    sys.exit(0)

block_lines = [
    "proxy:",
    f"  '{proxy_path}':",
    f"    target: '{target}'",
    "    changeOrigin: true",
    "    secure: true",
]

if "proxy:" in text:
    lines = text.splitlines()
    out: list[str] = []
    i = 0
    while i < len(lines):
        if lines[i].startswith("proxy:"):
            out.extend(block_lines)
            i += 1
            while i < len(lines) and (lines[i].startswith("  ") or lines[i].strip() == ""):
                i += 1
            continue
        out.append(lines[i])
        i += 1
    text = "\n".join(out)
else:
    lines = text.splitlines()
    insert_at = next((i for i, line in enumerate(lines) if line.startswith("catalog:")), len(lines))
    lines[insert_at:insert_at] = block_lines + [""]
    text = "\n".join(lines)

if not text.endswith("\n"):
    text += "\n"
path.write_text(text)
print("repaired")
PY
)"

if [[ "${result}" == "repaired" ]]; then
  oc create configmap "${APP_CONFIG_CM}" \
    --from-file=app-config.yaml="${tmp}" \
    -n "${OCP_NAMESPACE}" --dry-run=client -o yaml | oc apply -f -
  oc rollout restart "deployment/${HELM_RELEASE}" -n "${OCP_NAMESPACE}"
  oc rollout status "deployment/${HELM_RELEASE}" -n "${OCP_NAMESPACE}" --timeout=300s
  echo "=== AAP Gateway proxy ${PROXY_PATH} -> ${AAP_HOST_URL} configured ==="
else
  echo "=== AAP Gateway proxy already configured (${PROXY_PATH}) ==="
fi

rm -f "${tmp}"
