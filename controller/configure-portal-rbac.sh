#!/usr/bin/env bash
# Configure Self-Service Portal RBAC for demo-user / Demo Self-Service team.
# Run on the OpenShift bastion (requires oc access to rhaap-portal namespace).
#
# Uses the portal permission database (Casbin rules). Idempotent.
# Does not store passwords in git — set DEMO_USER_PASSWORD only for verification.
set -euo pipefail

OCP_NAMESPACE="${OCP_NAMESPACE:-rhaap-portal}"
PG_POD="${PG_POD:-redhat-rhaap-portal-postgresql-0}"
PG_DB="${PG_DB:-backstage_plugin_permission}"
ROLE_NAME="${ROLE_NAME:-demo-portal-users}"
DEMO_TAG="${DEMO_TAG:-demo-self-service}"

PORTAL_HOST="${PORTAL_HOST:-redhat-rhaap-portal-rhaap-portal.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com}"
ROUTER_BASE="${ROUTER_BASE:-cluster-jmvv9.jmvv9.sandbox3400.opentlc.com}"

DEMO_USER="${DEMO_USER:-demo-user}"
DEMO_USER_PASSWORD="${DEMO_USER_PASSWORD:-}"
VERIFY_OAUTH="${VERIFY_OAUTH:-0}"

command -v oc >/dev/null || { echo "oc required (run on bastion)" >&2; exit 1; }

pg_password() {
  local secret="${PG_SECRET:-redhat-rhaap-portal-postgresql}"
  oc get secret "${secret}" -n "${OCP_NAMESPACE}" \
    -o jsonpath='{.data.postgres-password}' 2>/dev/null | base64 -d
}

PGPASS="$(pg_password)"
[[ -n "${PGPASS}" ]] || { echo "Could not read postgres password from secret" >&2; exit 1; }

psql_exec() {
  oc exec -n "${OCP_NAMESPACE}" "${PG_POD}" -- \
    env PGPASSWORD="${PGPASS}" psql -U postgres -d "${PG_DB}" -v ON_ERROR_STOP=1 "$@"
}

role_ref="role:default/${ROLE_NAME}"
user_ref="user:default/${DEMO_USER}"
group_ref="group:default/demo-self-service"

echo "=== Checking existing RBAC for ${role_ref} ==="
existing="$(psql_exec -t -c \
  "SELECT count(*) FROM casbin_rule WHERE v0='${role_ref}' OR v1='${role_ref}';" | tr -d ' ')"

if [[ "${existing}" != "0" ]]; then
  echo "RBAC role ${role_ref} already has ${existing} rule(s)"
else
  echo "=== Creating portal RBAC role: ${ROLE_NAME} ==="
  psql_exec -c "INSERT INTO casbin_rule (ptype, v0, v1) VALUES ('g', '${user_ref}', '${role_ref}'), ('g', '${group_ref}', '${role_ref}');"
  psql_exec -c "INSERT INTO casbin_rule (ptype, v0, v1, v2, v3) VALUES
    ('p', '${role_ref}', 'catalog.entity.read', 'read', 'allow'),
    ('p', '${role_ref}', 'catalog-entity', 'read', 'allow'),
    ('p', '${role_ref}', 'scaffolder.template.parameter.read', 'read', 'allow'),
    ('p', '${role_ref}', 'scaffolder.template.step.read', 'read', 'allow'),
    ('p', '${role_ref}', 'scaffolder.action.execute', 'use', 'allow'),
    ('p', '${role_ref}', 'scaffolder.task.cancel', 'use', 'allow'),
    ('p', '${role_ref}', 'scaffolder.task.create', 'create', 'allow'),
    ('p', '${role_ref}', 'scaffolder.task.read', 'read', 'allow'),
    ('p', '${role_ref}', 'scaffolder-task', 'read', 'allow'),
    ('p', '${role_ref}', 'scaffolder-task', 'create', 'allow'),
    ('p', '${role_ref}', 'scaffolder-action', 'use', 'allow'),
    ('p', '${role_ref}', 'ansible.templates.view', 'read', 'allow'),
    ('p', '${role_ref}', 'ansible.history.view', 'read', 'allow');"
  echo "Inserted Casbin rules for ${role_ref}"
fi

psql_exec -c "INSERT INTO \"role-metadata\" (\"roleEntityRef\", source, description, author, \"modifiedBy\", \"createdAt\", \"lastModified\")
SELECT '${role_ref}', 'rest-api', 'Self-service portal users for RHEL DEMO templates', 'configure-portal-rbac.sh', 'configure-portal-rbac.sh', NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM \"role-metadata\" WHERE \"roleEntityRef\"='${role_ref}');" >/dev/null

cond_count="$(psql_exec -t -c \
  "SELECT count(*) FROM \"role-condition-policies\" WHERE \"roleEntityRef\"='${role_ref}';" | tr -d ' ')"

if [[ "${cond_count}" == "0" ]]; then
  echo "=== Adding conditional catalog filter: tag ${DEMO_TAG} ==="
  conditions_json='{"rule":"HAS_METADATA","resourceType":"catalog-entity","params":{"key":"tags","value":"'"${DEMO_TAG}"'"}}'
  psql_exec -c "INSERT INTO \"role-condition-policies\" (\"roleEntityRef\", result, \"pluginId\", \"resourceType\", permissions, \"conditionsJson\")
VALUES ('${role_ref}', 'CONDITIONAL', 'catalog', 'catalog-entity', 'read', '${conditions_json}');"
fi

echo "=== Current rules for ${ROLE_NAME} ==="
psql_exec -c "SELECT id, ptype, v0, v1, v2, v3 FROM casbin_rule
WHERE v0='${role_ref}' OR v1='${role_ref}' OR v0 IN ('${user_ref}', '${group_ref}')
ORDER BY id;"

RESTART_PORTAL="${RESTART_PORTAL:-0}"
if [[ "${RESTART_PORTAL}" == "1" ]]; then
  echo "=== Restarting portal backend to reload policies ==="
  oc rollout restart "deployment/redhat-rhaap-portal" -n "${OCP_NAMESPACE}" || true
  oc rollout status "deployment/redhat-rhaap-portal" -n "${OCP_NAMESPACE}" --timeout=300s || {
    echo "Note: rollout status timed out; Casbin policies are read from PostgreSQL without restart"
    oc get pods -n "${OCP_NAMESPACE}" -l app.kubernetes.io/component=backstage
  }
else
  echo "=== Skipping portal restart (RESTART_PORTAL=0). Policies apply from PostgreSQL on next request. ==="
fi

if [[ "${VERIFY_OAUTH}" == "1" && -n "${DEMO_USER_PASSWORD}" ]]; then
  echo "=== Verifying ${DEMO_USER} OAuth + catalog access ==="
  ROUTER_IP="$(dig +short "router-default.apps.${ROUTER_BASE}" | head -1)"
  [[ -n "${ROUTER_IP}" ]] || { echo "Could not resolve router IP" >&2; exit 1; }
  RESOLVE=(--resolve "${PORTAL_HOST}:443:${ROUTER_IP}")

  # Obtain portal bearer token via AAP OAuth (authorization code flow)
  python3 - "${PORTAL_HOST}" "${DEMO_USER}" "${DEMO_USER_PASSWORD}" "${RESOLVE[@]}" <<'PY'
import re, sys, json, urllib.parse, http.cookiejar
import urllib.request

portal, user, password = sys.argv[1:4]
resolve_args = sys.argv[4:]

# Use curl for TLS/SNI resolve (simpler than Python SSL context hacks)
import subprocess

def curl(args, check=True):
    cmd = ["curl", "-sk", "-L", "--max-redirs", "20"] + resolve_args + args
    return subprocess.run(cmd, capture_output=True, text=True, check=check)

# Start OAuth — capture redirect chain ending at AAP login
start_url = f"https://{portal}/api/auth/rhaap/start?scope=openid%20profile%20email%20offline_access&origin=https%3A%2F%2F{portal}%2F&flow=popup&env=production"
jar = "/tmp/portal-oauth-cookies.txt"
subprocess.run(["rm", "-f", jar], check=False)

# Get AAP authorize URL
r = subprocess.run(
    ["curl", "-sk", "-D", "-", "-o", "/dev/null", "-c", jar] + resolve_args + [start_url],
    capture_output=True, text=True,
)
loc = ""
for line in r.stdout.splitlines():
    if line.lower().startswith("location:"):
        loc = line.split(":", 1)[1].strip()
if not loc:
    print("OAuth start did not redirect", file=sys.stderr)
    print(r.stdout[:500], file=sys.stderr)
    sys.exit(1)

# Follow to login page, submit credentials
login_page = subprocess.run(
    ["curl", "-sk", "-c", jar, "-b", jar] + resolve_args + [loc],
    capture_output=True, text=True,
)
csrf = re.search(r'name="csrfmiddlewaretoken" value="([^"]+)"', login_page.stdout)
if not csrf:
    print("CSRF token not found on AAP login page", file=sys.stderr)
    sys.exit(1)
csrf = csrf.group(1)
login_post = subprocess.run(
    ["curl", "-sk", "-c", jar, "-b", jar, "-X", "POST",
     "-d", f"csrfmiddlewaretoken={urllib.parse.quote(csrf)}&username={urllib.parse.quote(user)}&password={urllib.parse.quote(password)}&next=",
     "-D", "-", "-o", "/dev/null"] + resolve_args + [loc.split("?")[0].replace("/authorize/", "/login/") if "/authorize/" in loc else loc],
    capture_output=True, text=True,
)
# Follow authorize approval if needed
for _ in range(5):
    auth = subprocess.run(
        ["curl", "-sk", "-c", jar, "-b", jar, "-D", "-", "-o", "/dev/null"] + resolve_args + [loc],
        capture_output=True, text=True, check=False,
    )
    m = re.search(r"location:\s*(\S+)", auth.stdout, re.I)
    if not m:
        break
    loc = m.group(1)

# Exchange session cookie for backstage token
refresh = subprocess.run(
    ["curl", "-sk", "-b", jar, "-c", jar] + resolve_args +
    ["-X", "POST", f"https://{portal}/api/auth/rhaap/refresh?env=production",
     "-H", "Content-Type: application/json", "-d", "{}"],
    capture_output=True, text=True,
)
try:
    data = json.loads(refresh.stdout)
    token = data.get("backstageIdentity", {}).get("token") or data.get("providerInfo", {}).get("accessToken")
    if not token:
        token = data.get("token")
except json.JSONDecodeError:
    print("Refresh response:", refresh.stdout[:500], file=sys.stderr)
    sys.exit(1)

if not token:
    print("No backstage token in refresh response", file=sys.stderr)
    print(json.dumps(data, indent=2)[:800], file=sys.stderr)
    sys.exit(1)

# Query catalog templates
cat = subprocess.run(
    ["curl", "-sk"] + resolve_args +
    ["-H", f"Authorization: Bearer {token}",
     f"https://{portal}/api/catalog/entities?filter=kind=template"],
    capture_output=True, text=True,
)
entities = json.loads(cat.stdout)
names = sorted(e.get("metadata", {}).get("name", "?") for e in entities)
print(f"demo-user catalog templates ({len(names)}):")
for n in names:
    print(f"  - {n}")
if len(names) < 6:
    sys.exit(2)
PY
fi

echo "=== Portal RBAC configuration complete ==="
