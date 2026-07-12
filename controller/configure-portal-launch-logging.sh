#!/usr/bin/env bash
# Patch rhaap:launch-job-template so DEMO job output streams into the scaffolder step log.
# Adds an init container after install-dynamic-plugins (idempotent). Run on the bastion.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OCP_NAMESPACE="${OCP_NAMESPACE:-rhaap-portal}"
HELM_RELEASE="${HELM_RELEASE:-redhat-rhaap-portal}"
DEPLOYMENT="${DEPLOYMENT:-${HELM_RELEASE}}"
PATCH_SCRIPT="${PATCH_SCRIPT:-${SCRIPT_DIR}/patch-portal-launch-logging.py}"
INIT_NAME="${INIT_NAME:-patch-portal-launch-logging}"

command -v oc >/dev/null || { echo "oc required (run on bastion)" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 1; }
[[ -f "${PATCH_SCRIPT}" ]] || { echo "missing ${PATCH_SCRIPT}" >&2; exit 1; }

patch_cm="${HELM_RELEASE}-launch-logging-patch"
oc create configmap "${patch_cm}" \
  --from-file=patch-portal-launch-logging.py="${PATCH_SCRIPT}" \
  -n "${OCP_NAMESPACE}" --dry-run=client -o yaml | oc apply -f -

python3 - "${DEPLOYMENT}" "${OCP_NAMESPACE}" "${INIT_NAME}" "${patch_cm}" <<'PY'
import json
import subprocess
import sys
import tempfile

deployment, namespace, init_name, patch_cm = sys.argv[1:5]
raw = subprocess.check_output(
    ["oc", "get", "deployment", deployment, "-n", namespace, "-o", "json"],
    text=True,
)
doc = json.loads(raw)
spec = doc["spec"]["template"]["spec"]
init_containers = spec.get("initContainers") or []
existing_idx = next((i for i, c in enumerate(init_containers) if c.get("name") == init_name), None)

install_idx = next(
    (i for i, c in enumerate(init_containers) if c.get("name") == "install-dynamic-plugins"),
    len(init_containers),
)
install = init_containers[install_idx] if init_containers else {}
image = install.get("image", "registry.redhat.io/rhdh/rhdh-hub-rhel9:1.9")

patch_resources = {
    "limits": {"cpu": "250m", "memory": "256Mi"},
    "requests": {"cpu": "100m", "memory": "128Mi"},
}

patch_init = {
    "name": init_name,
    "image": image,
    "imagePullPolicy": install.get("imagePullPolicy", "IfNotPresent"),
    "command": ["/bin/bash", "-ec"],
    "args": [
        """
target="/dynamic-plugins-root/ansible-plugin-scaffolder-backend-module-backstage-rhaap/dist/actions/aapLaunchJobTemplate.cjs.js"
if [[ ! -f "${target}" ]]; then
  echo "launch action not found: ${target}" >&2
  exit 1
fi
cp /patch/patch-portal-launch-logging.py /tmp/patch-portal-launch-logging.py
python3 /tmp/patch-portal-launch-logging.py "${target}"
"""
    ],
    "resources": patch_resources,
    "volumeMounts": [
        {"name": "dynamic-plugins-root", "mountPath": "/dynamic-plugins-root"},
        {"name": "launch-logging-patch", "mountPath": "/patch", "readOnly": True},
    ],
}

if existing_idx is not None:
    current = init_containers[existing_idx]
    if current.get("resources") == patch_resources and current.get("args") == patch_init["args"]:
        print("unchanged")
        sys.exit(0)
    init_containers[existing_idx] = {**current, **patch_init}
else:
    init_containers.insert(install_idx + 1, patch_init)
spec["initContainers"] = init_containers

volumes = spec.get("volumes") or []
if not any(v.get("name") == "launch-logging-patch" for v in volumes):
    volumes.append(
        {
            "name": "launch-logging-patch",
            "configMap": {"name": patch_cm},
        }
    )
spec["volumes"] = volumes

# Quota-constrained namespaces cannot run old and new portal pods concurrently.
spec.setdefault("strategy", {})
spec["strategy"]["type"] = "RollingUpdate"
spec["strategy"]["rollingUpdate"] = {"maxSurge": 0, "maxUnavailable": 1}

with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
    json.dump(doc, handle)
    tmp_path = handle.name

subprocess.check_call(["oc", "apply", "-f", tmp_path])
print("patched")
PY

echo "=== Restarting portal to apply launch-logging patch ==="
oc delete pod -n "${OCP_NAMESPACE}" \
  -l "app.kubernetes.io/instance=${HELM_RELEASE},app.kubernetes.io/component=backstage" \
  --wait=false 2>/dev/null || true
oc rollout restart "deployment/${DEPLOYMENT}" -n "${OCP_NAMESPACE}"
oc rollout status "deployment/${DEPLOYMENT}" -n "${OCP_NAMESPACE}" --timeout=600s
echo "=== Portal launch-logging patch applied ==="
