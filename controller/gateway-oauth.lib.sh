# Shared Gateway OAuth helpers for AAP 2.5+ self-service portal.
# Portal Sign in with RHAAP uses the Gateway /o/authorize/ endpoint, not Controller.
#
# Public OAuth apps reject client_secret at /o/token/ (invalid_client) while Backstage
# requires a non-empty auth.providers.rhaap.*.clientSecret — use confidential apps.

AAP_GATEWAY_OAUTH_CACHE="${AAP_GATEWAY_OAUTH_CACHE:-/tmp/aap_gateway_oauth_app.json}"

gateway_oauth_api_get() {
  curl -sk "${gateway_auth[@]}" "${AAP_GATEWAY}$1"
}

gateway_oauth_api_post() {
  curl -sk "${gateway_auth[@]}" -o /tmp/aap_gateway_resp.txt -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' -d "$2" "${AAP_GATEWAY}$1"
}

gateway_oauth_api_patch() {
  curl -sk "${gateway_auth[@]}" -o /tmp/aap_gateway_resp.txt -w '%{http_code}' \
    -X PATCH -H 'Content-Type: application/json' -d "$2" "${AAP_GATEWAY}$1"
}

gateway_oauth_lookup_id() {
  local field="$1" value="$2"
  gateway_oauth_api_get "/api/gateway/v1/applications/" | python3 -c "
import sys, json
field, value = sys.argv[1], sys.argv[2]
data = json.load(sys.stdin)
for item in data.get('results', []):
    if item.get(field) == value:
        print(item['id'])
        break
" "$field" "$value"
}

require_gateway_oauth_ok() {
  local code="$1" context="$2"
  if [[ "${code}" != "200" && "${code}" != "201" && "${code}" != "204" ]]; then
    echo "Failed: ${context} (HTTP ${code})" >&2
    cat /tmp/aap_gateway_resp.txt >&2
    exit 1
  fi
}

write_gateway_oauth_cache() {
  local client_id="$1" client_secret="$2" app_id="${3:-}"
  python3 - "${AAP_GATEWAY_OAUTH_CACHE}" "${client_id}" "${client_secret}" "${app_id}" <<'PY'
import json, os, sys
path, client_id, client_secret, app_id = sys.argv[1:5]
payload = {"client_id": client_id, "client_secret": client_secret}
if app_id:
    payload["id"] = int(app_id)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
os.chmod(path, 0o600)
PY
  echo "Gateway OAuth credentials cached at ${AAP_GATEWAY_OAUTH_CACHE} (use for deploy; do not commit)" >&2
}

read_gateway_oauth_client_secret() {
  if [[ -z "${OAUTH_CLIENT_SECRET:-}" && -f "${AAP_GATEWAY_OAUTH_CACHE}" ]]; then
    OAUTH_CLIENT_SECRET="$(python3 - "${AAP_GATEWAY_OAUTH_CACHE}" <<'PY'
import json, sys
print(json.load(open(sys.argv[1])).get("client_secret", ""))
PY
)"
  fi
  if [[ -z "${OAUTH_CLIENT_SECRET:-}" ]]; then
    echo "Set OAUTH_CLIENT_SECRET or recreate Gateway OAuth app (confidential) so ${AAP_GATEWAY_OAUTH_CACHE} is written" >&2
    return 1
  fi
  printf '%s' "${OAUTH_CLIENT_SECRET}"
}

ensure_gateway_oauth_application() {
  local app_name="$1" redirect_uri="$2" org_id="$3"
  echo "=== Ensuring Gateway OAuth application (portal uses Gateway /o/authorize/) ==="
  local oauth_id
  oauth_id="$(gateway_oauth_lookup_id name "${app_name}")"
  if [[ -z "${oauth_id}" ]]; then
    if [[ "${redirect_uri}" == *PLACEHOLDER* ]]; then
      echo "Warning: redirect URI is still a placeholder; create Gateway OAuth app after portal deploy" >&2
      return 0
    fi
    local payload
    payload=$(python3 -c "
import json
print(json.dumps({
    'name': '''${app_name}''',
    'description': 'OAuth for self-service automation portal (Gateway)',
    'client_type': 'confidential',
    'authorization_grant_type': 'authorization-code',
    'redirect_uris': '''${redirect_uri}''',
    'organization': int('''${org_id}'''),
    'skip_authorization': True,
}))
")
    local code
    code=$(gateway_oauth_api_post "/api/gateway/v1/applications/" "${payload}")
    require_gateway_oauth_ok "${code}" "create Gateway OAuth application"
    python3 - "${AAP_GATEWAY_OAUTH_CACHE}" <<'PY' < /tmp/aap_gateway_resp.txt
import json, sys
path = sys.argv[1]
data = json.load(sys.stdin)
with open(path, "w", encoding="utf-8") as fh:
    json.dump({"id": data["id"], "client_id": data["client_id"], "client_secret": data["client_secret"]}, fh)
import os
os.chmod(path, 0o600)
print(data.get("client_id", ""))
PY
    echo "Saved Gateway OAuth client_secret to ${AAP_GATEWAY_OAUTH_CACHE}" >&2
    return 0
  fi

  echo "Gateway OAuth application ${app_name} already exists (id ${oauth_id})"
  if [[ "${redirect_uri}" != *PLACEHOLDER* ]]; then
    local payload
    payload=$(python3 -c "import json; print(json.dumps({'redirect_uris': '''${redirect_uri}''', 'skip_authorization': True}))")
    local code
    code=$(gateway_oauth_api_patch "/api/gateway/v1/applications/${oauth_id}/" "${payload}")
    require_gateway_oauth_ok "${code}" "update Gateway OAuth redirect URI"
    echo "Updated Gateway OAuth redirect URI to ${redirect_uri}"
  fi
  gateway_oauth_api_get "/api/gateway/v1/applications/${oauth_id}/" | python3 -c "import sys,json; print(json.load(sys.stdin).get('client_id',''))"
}

resolve_gateway_oauth_client_id() {
  local app_name="$1"
  local client_id
  client_id="$(gateway_oauth_api_get "/api/gateway/v1/applications/" | python3 -c "
import sys, json
name = sys.argv[1]
for item in json.load(sys.stdin).get('results', []):
    if item.get('name') == name:
        print(item.get('client_id', ''))
        break
" "${app_name}")"
  if [[ -z "${client_id}" ]]; then
    echo "No Gateway OAuth application named '${app_name}'. Run configure-self-service.sh with OAUTH_REDIRECT_URI set." >&2
    return 1
  fi
  printf '%s' "${client_id}"
}

ensure_gateway_catalog_token() {
  # Portal catalog sync calls /api/gateway/v1/* with AAP_TOKEN — Controller tokens do not work.
  local description="${1:-Portal catalog sync}"
  echo "=== Ensuring Gateway API token for portal catalog (AAP_TOKEN) ===" >&2
  local code
  code=$(gateway_oauth_api_post "/api/gateway/v1/tokens/" \
    "$(python3 -c "import json; print(json.dumps({'description': '''${description}''', 'user': 2, 'scope': 'write'}))")")
  require_gateway_oauth_ok "${code}" "create Gateway API token"
  python3 - <<'PY' < /tmp/aap_gateway_resp.txt
import json, sys
print(json.load(sys.stdin).get("token", ""))
PY
}

ensure_gateway_org_member() {
  local gateway_user_id="$1" org_id="${2:-1}"
  local role_def
  role_def="$(gateway_oauth_api_get "/api/gateway/v1/role_definitions/?name=Organization%20Member" | python3 -c "
import sys, json
for item in json.load(sys.stdin).get('results', []):
    if item.get('name') == 'Organization Member':
        print(item['id'])
        break
")"
  [[ -n "${role_def}" ]] || { echo "Organization Member role definition not found on Gateway" >&2; return 1; }
  local payload
  payload=$(python3 -c "import json; print(json.dumps({'user': int('''${gateway_user_id}'''), 'role_definition': int('''${role_def}'''), 'object_id': str('''${org_id}'''), 'content_type': 'shared.organization'}))")
  local code
  code=$(gateway_oauth_api_post "/api/gateway/v1/role_user_assignments/" "${payload}")
  if [[ "${code}" == "201" || "${code}" == "200" ]]; then
    echo "Gateway organization member role assigned to user id ${gateway_user_id}" >&2
  else
    echo "Note: Gateway org member assignment HTTP ${code} (may already exist)" >&2
  fi
}
