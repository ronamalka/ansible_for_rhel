# Shared Gateway OAuth helpers for AAP 2.5+ self-service portal.
# Portal Sign in with RHAAP uses the Gateway /o/authorize/ endpoint, not Controller.

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
    'client_type': 'public',
    'authorization_grant_type': 'authorization-code',
    'redirect_uris': '''${redirect_uri}''',
    'organization': int('''${org_id}'''),
    'skip_authorization': False,
}))
")
    local code
    code=$(gateway_oauth_api_post "/api/gateway/v1/applications/" "${payload}")
    require_gateway_oauth_ok "${code}" "create Gateway OAuth application"
    oauth_id="$(gateway_oauth_lookup_id name "${app_name}")"
    echo "Created Gateway OAuth application ${app_name} (id ${oauth_id})"
  else
    echo "Gateway OAuth application ${app_name} already exists (id ${oauth_id})"
    if [[ "${redirect_uri}" != *PLACEHOLDER* ]]; then
      local payload
      payload=$(python3 -c "import json; print(json.dumps({'redirect_uris': '''${redirect_uri}'''}))")
      local code
      code=$(gateway_oauth_api_patch "/api/gateway/v1/applications/${oauth_id}/" "${payload}")
      require_gateway_oauth_ok "${code}" "update Gateway OAuth redirect URI"
      echo "Updated Gateway OAuth redirect URI to ${redirect_uri}"
    fi
  fi
  if [[ -n "${oauth_id}" ]]; then
    gateway_oauth_api_get "/api/gateway/v1/applications/${oauth_id}/" | python3 -c "import sys,json; print(json.load(sys.stdin).get('client_id',''))"
  fi
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
