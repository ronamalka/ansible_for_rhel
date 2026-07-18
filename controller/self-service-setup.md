# Self-Service Portal Setup

Configure Ansible Automation Platform so demo attendees can launch RHEL automations through a self-service experience without admin privileges.

## Overview

AAP 2.5+ provides two self-service options:

| Mode | URL | When to use |
|------|-----|-------------|
| **Automation Portal** (recommended) | `https://redhat-rhaap-portal-rhaap-portal.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/` | Full AAP + OpenShift deployment with the self-service automation portal Helm chart |
| **Controller templates (limited)** | `https://<controller>/#/templates` | Fallback when portal is not deployed |

This repository configures **controller-side prerequisites** (user, team, RBAC, labels, descriptions, OAuth) required for both modes.

## Environment (OpenTLC jmvv9 — full AAP + OpenShift)

| Resource | Value |
|----------|-------|
| AAP Gateway (UI) | `https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com` |
| AAP Controller API | `https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com` |
| OpenShift Console | `https://console-openshift-console.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com` |
| Bastion | `ssh lab-user@bastion.jmvv9.sandbox3400.opentlc.com` |
| Automation Portal | `https://redhat-rhaap-portal-rhaap-portal.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/` |
| Organization | Default (id: 1) |
| Admin / token | `<admin-password>` / `<controller-token>` (lab environment — **never commit**) |

### Configured resource IDs (jmvv9 sandbox)

| Resource | ID |
|----------|-----|
| RHEL Demo Project | 43 |
| Workshop Inventory | 34 |
| Workshop Credential | 35 |
| DEMO job templates | 44–50 (+ OpenShift deploy when configured) |
| DEMO workflow | 49 |
| OAuth application | 1 |
| demo-user (controller) | 37 |

Template IDs vary per environment; re-run bootstrap to discover current IDs.

## Prerequisites

Run after DEMO job templates exist (bootstrap script creates them):

```bash
export CONTROLLER="https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com"
export CONTROLLER_TOKEN='<controller-token>'
export DEMO_USER_PASSWORD='<demo-user-password>'
export WORKSHOP_SSH_KEY_FILE="$HOME/.ssh/jmvv9key.pem"   # on bastion

./controller/setup-rhel-demo-environment.sh
```

Or configure RBAC only (templates already exist):

```bash
export DEMO_TEMPLATE_IDS="44 45 46 47 48"
export WORKFLOW_TEMPLATE_ID="49"
./controller/configure-self-service.sh
```

### AAP on OpenShift API notes

- Use the **direct controller route** (`aap-controller-aap…`) with `/api/v2/` for automation API calls.
- Use a **controller token** (`CONTROLLER_TOKEN`) — admin password basic auth may not work for write operations.
- User/team creation via controller API returns **403** on gateway-managed deployments. The bootstrap script creates `demo-user` and teams via controller database when needed; alternatively create users in **AAP Gateway → Access Management**.

## Quick setup (API script)

```bash
export CONTROLLER_TOKEN='<controller-token>'
export DEMO_USER_PASSWORD='<demo-user-password>'

./controller/configure-self-service.sh
```

The script is idempotent. Re-run safely after adding templates or rebuilding the controller.

### What the script configures

1. Enables `ALLOW_OAUTH2_FOR_EXTERNAL_USERS` (required for automation portal OAuth login)
2. Creates **demo-user** (non-admin) and **Demo Self-Service** team (when API allows)
3. Grants organization **Member** role and **Execute** on all DEMO templates
4. Applies label `demo-self-service` for portal tag-based RBAC filtering
5. Sets human-readable descriptions on all DEMO templates
6. Creates **Ansible Automation Portal** OAuth application (update redirect URI after portal deploy)
7. Verifies demo-user can list DEMO templates via API

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CONTROLLER` | jmvv9 controller URL | AAP controller base URL |
| `CONTROLLER_TOKEN` | *(recommended)* | Bearer token for API writes |
| `CONTROLLER_PASSWORD` | *(optional)* | Admin password (legacy sandboxes) |
| `DEMO_USER` | `demo-user` | Self-service demo account |
| `DEMO_USER_PASSWORD` | *(required)* | Demo user password (lab-only) |
| `DEMO_TEMPLATE_IDS` | `44 45 46 47 48` | Job template IDs |
| `WORKFLOW_TEMPLATE_ID` | `49` | Workflow template ID |
| `OAUTH_REDIRECT_URI` | Placeholder | Update after portal deployment |

## Demo user credentials (presenter)

| Field | Value |
|-------|-------|
| Username | `demo-user` |
| Password | `<demo-user-password>` — set during lab setup via `DEMO_USER_PASSWORD` |
| Role | Non-admin; Execute on DEMO templates only |

## Automation Portal deployment (OpenShift)

### 1. Prepare OpenShift (bastion)

```bash
ssh lab-user@bastion.jmvv9.sandbox3400.opentlc.com
oc whoami   # expect system:admin
helm version
```

Install Helm 3.10+ if missing:

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### 2. Create secrets

```bash
export AAP_HOST_URL="https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com"
export OAUTH_CLIENT_ID="<from AAP OAuth application>"
export OAUTH_CLIENT_SECRET=""   # leave empty when using configure-self-service cache file
export AAP_TOKEN="<controller-token>"
./controller/deploy-self-service-portal.sh
```

### 3. Install Helm chart

From **OpenShift Developer → Helm → Create → Automation Portal** (or equivalent chart name):

```yaml
redhat-developer-hub:
  global:
    clusterRouterBase: apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com
    pluginMode: oci
```

`clusterRouterBase` must be the **apps ingress DNS suffix** for your cluster (for jmvv9: `apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com`). Do not omit the `apps.` segment on OpenTLC sandboxes.

### 4. Update OAuth redirect URI

In AAP → **Access Management → OAuth Applications → Ansible Automation Portal**:

```
https://<portal-route>/api/auth/rhaap/handler/frame
```

Get the route:

```bash
oc get route -n rhaap-portal
```

### 5. Configure portal RBAC

Portal RBAC is **separate** from controller RBAC. Non-admin users need a portal role with catalog + scaffolder permissions before synchronized templates appear.

#### Option A — Automated (bastion, recommended)

Run on the bastion after the portal pod is healthy (`oc get pods -n rhaap-portal`):

```bash
./controller/configure-portal-rbac.sh
```

The script is idempotent. It writes Casbin rules to the portal PostgreSQL database (`backstage_plugin_permission`) for role `demo-portal-users`:

| Binding | Entity reference |
|---------|------------------|
| User | `user:default/demo-user` |
| Team | `group:default/demo-self-service` |

Permissions granted:

| Plugin | Permissions |
|--------|-------------|
| Catalog | `catalog.entity.read` |
| Scaffolder | `scaffolder.template.parameter.read`, `scaffolder.template.step.read`, `scaffolder.action.execute`, `scaffolder.task.cancel`, `scaffolder.task.create`, `scaffolder.task.read` |
| Navigation | `ansible.templates.view`, `ansible.history.view` |

Conditional catalog filter (tag `demo-self-service`) limits visible templates to the six DEMO job/workflow templates.

**Do not** set `RESTART_PORTAL=1` on resource-constrained sandboxes (namespace CPU quota may block a second pod). Policies load from PostgreSQL without a restart.

Optional verification (requires `DEMO_USER_PASSWORD` in the environment — never commit):

```bash
export DEMO_USER_PASSWORD='<demo-user-password>'
export VERIFY_OAUTH=1
./controller/configure-portal-rbac.sh
```

#### Option B — Manual UI (admin login)

1. Sign in to the portal as an **AAP administrator** (user `admin` or member of `aap-admins`).
2. Open **Administration → RBAC → Create**.
3. Name: `demo-portal-users`.
4. **Users and Groups:** select **demo-user** and **Demo Self-Service** team (synced from AAP org `Default`).
5. **Catalog plugin:** enable `catalog.entity.read`.
   - Optional **Conditional:** rule `HAS_METADATA`, key `tags`, value `demo-self-service`.
6. **Scaffolder plugin:** enable all scaffolder permissions (`scaffolder.template.*`, `scaffolder.action.execute`, `scaffolder.task.*`).
7. Save the role.

See [Red Hat initial portal RBAC setup](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/install-con_self_service_initial_rbac_setup).

### Portal URL

After deployment:

```
https://redhat-rhaap-portal-rhaap-portal.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/
```

### Browser access (OpenTLC jmvv9)

OpenTLC lab DNS resolves **`*.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com`** to the OpenShift ingress load balancer. The portal Helm chart builds the route from `clusterRouterBase`; it must include the **`apps.`** prefix for this sandbox (see `deploy-self-service-portal.sh` default).

**Working URL (no `/etc/hosts` required):**

```
https://redhat-rhaap-portal-rhaap-portal.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/
```

If the chart was installed with `clusterRouterBase: cluster-jmvv9.jmvv9.sandbox3400.opentlc.com` (missing `apps.`), the route hostname does **not** match the lab wildcard and browsers show **DNS NXDOMAIN**. The app may still respond when you pin the router IP:

```bash
# Router IPs (same as other *.apps routes)
dig +short aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com

curl -vk --resolve 'redhat-rhaap-portal-rhaap-portal.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com:443:3.146.240.130' \
  'https://redhat-rhaap-portal-rhaap-portal.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/'
```

**Fix:** upgrade the release so the route uses the `apps.` domain:

```bash
helm upgrade redhat-rhaap-portal openshift-helm-charts/redhat-rhaap-portal \
  --version 2.2.0 -n rhaap-portal --reuse-values \
  --set redhat-developer-hub.global.clusterRouterBase=apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com
```

Then update the OAuth redirect URI to `https://<new-portal-host>/api/auth/rhaap/handler/frame`.

**Temporary workaround (`/etc/hosts`):** add one router IP from `dig +short aap-aap.apps...` and the **exact** route hostname from `oc get route -n rhaap-portal`.

Verify from your laptop:

```bash
curl -skI 'https://redhat-rhaap-portal-rhaap-portal.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/' | head -1
# Expect: HTTP/1.1 200 OK
```


Sign in with **demo-user** credentials (same as controller). Configure portal RBAC (step 5 above) before templates appear for non-admin users.

### jmvv9 deployment status (2026-07-12)

| Check | Result |
|-------|--------|
| Controller OAuth + RBAC | Configured (demo-user sees 6 DEMO templates) |
| OpenShift `oc` on bastion | `system:admin` |
| Helm on bastion | Installed (v3.21+) |
| Portal Helm chart | `openshift-helm-charts/redhat-rhaap-portal` v2.2.0 (`helm search repo openshift-helm-charts/redhat-rhaap-portal -l`) |
| `registry.redhat.io` image pull | Works via cluster `openshift-config/pull-secret` (lab pool credentials) |
| Helm release | `redhat-rhaap-portal` in namespace `rhaap-portal` |
| Portal URL | `https://redhat-rhaap-portal-rhaap-portal.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/` |
| OAuth redirect URI | Updated to portal `/api/auth/rhaap/handler/frame` |
| Portal RBAC for demo-user | **Configured** — role `demo-portal-users` (15 Casbin rules + tag filter `demo-self-service`) via `configure-portal-rbac.sh` |
| External DNS | Use `apps.` in `clusterRouterBase`; see **Browser access** above |
| Known pitfall | Duplicate `catalog.providers.rhaap.production` in merged app-config → `REPAIR_APP_CONFIG=1 ./controller/deploy-self-service-portal.sh` |
| Known pitfall | Login page offers **Sign in with GitHub** — disable guest auth plugins: `DISABLE_GUEST_AUTH=1 ./controller/deploy-self-service-portal.sh` (included in full deploy) |
| Automation Dashboard | **Not enabled** — separate product; see `monitoring/demo-narrative-jmvv9-automation-dashboard.md` |

Automated deploy on bastion:

```bash
export OAUTH_CLIENT_ID="$(curl -sk -u admin:$CONTROLLER_PASSWORD \
  "$AAP_HOST_URL/api/gateway/v1/applications/" | python3 -c "import sys,json; [print(i['client_id']) for i in json.load(sys.stdin)['results'] if i['name']=='Ansible Automation Portal']")"
export AAP_TOKEN="<controller-token>"
./controller/deploy-self-service-portal.sh
```

Gateway **public** OAuth apps must use an **empty** `oauth-client-secret` in `secrets-rhaap-portal` (sending `public-client-no-secret` causes `invalid_client` and the UI error **Failed to post data**). **Confidential** Gateway apps require the real secret from `/api/gateway/v1/applications/` (set `OAUTH_CLIENT_SECRET` before deploy). OCI plug-in mode requires the `redhat-rhaap-portal-dynamic-plugins-registry-auth` secret built from cluster pull credentials or a local `auth.json`.

The deploy script automatically disables GitHub/GitLab guest auth provider plugins so the login page shows **Sign in with RHAAP** (AAP OAuth) only. OAuth redirect URI is set from the live OpenShift route host (must include `apps.` on OpenTLC sandboxes).

## Controller-only self-service (fallback)

When no automation portal is deployed:

1. Open `https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com`
2. Sign in as **demo-user**
3. Go to **Automation Execution → Templates**
4. Only the six DEMO templates appear (RBAC filtered)

## Verification

### API check (as demo-user)

```bash
CONTROLLER="https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com"
export DEMO_USER_PASSWORD='<demo-user-password>'

curl -sk -u "demo-user:${DEMO_USER_PASSWORD}" \
  "${CONTROLLER}/api/v2/unified_job_templates/?search=DEMO&order_by=name" \
  | python3 -c "import sys,json; [print(r['name']) for r in json.load(sys.stdin)['results']]"
```

Expected: six DEMO templates.

### Launch permission check

```bash
curl -sk -u "demo-user:${DEMO_USER_PASSWORD}" \
  "${CONTROLLER}/api/v2/job_templates/44/launch/" | python3 -m json.tool | head -5
```

Should return survey/launch schema (not 403).

### Portal check (demo-user after OAuth)

1. Open `https://redhat-rhaap-portal-rhaap-portal.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/`
2. Click **Sign in with RHAAP** (not GitHub).
3. Authenticate as **demo-user** (password set via `DEMO_USER_PASSWORD` during setup).
4. Open **Templates** — expect six DEMO templates (tag `demo-self-service`).
5. Launch **DEMO - Patch RHEL Servers** — wizard should open; job starts if inventory hosts are reachable.

Confirm RBAC rules on bastion:

```bash
oc exec -n rhaap-portal redhat-rhaap-portal-postgresql-0 -- \
  env PGPASSWORD="$(oc get secret redhat-rhaap-portal-postgresql -n rhaap-portal -o jsonpath='{.data.postgres-password}' | base64 -d)" \
  psql -U postgres -d backstage_plugin_permission \
  -c "SELECT count(*) FROM casbin_rule WHERE v1='role:default/demo-portal-users' OR v0 LIKE '%demo-user%';"
```

Expected: **15** rows.

## Portal job output in the launch step log

Auto-generated portal templates (synced from Controller job templates) use `rhaap:launch-job-template`. Stock portal 2.2 only logs job ID and final status during **Create Task** — not per-host Ansible output.

Custom summary templates use a **single** `rhaap:launch-job-template` step (no `fetch-stdout`, `http:backstage:request`, or `fetch:plain`). Per-host details stream into the launch step log when `configure-portal-launch-logging.sh` patches the scaffolder action to poll job stdout and emit `DEMO_*_PORTAL` marker lines.

### rhaap scaffolder actions (portal 2.2)

Registered by `ansible-plugin-scaffolder-backend-module-backstage-rhaap`:

| Action | Purpose | Key inputs | Output |
|--------|---------|------------|--------|
| `rhaap:launch-job-template` | Launch and wait for a Controller job template | `token`, `values.template`, `values.extraVariables`, optional `waitForCompletion` (default `true`) | `data.id`, `data.status`, `data.url` |
| `rhaap:create-job-template` | Create a job template | `token`, `values` | `data` record |
| `rhaap:create-project` | Create a project | `token`, `values` | `data` record |
| `rhaap:create-execution-environment` | Create an EE | `token`, `values` | `data` record |
| `rhaap:clean-up` | Delete demo resources | `token`, `values` | — |
| `ansible:content-create` | Scaffold Ansible collection/playbook | config-driven | — |

`rhaap:launch-job-template` does **not** expose `showStdout`, `logOutput`, `pollEvents`, or `waitAndLog` template inputs. The bundled `AAPClient.launchJobTemplate()` can parse stdout `"msg"` fields, but the stock scaffolder action calls `launchJobTemplateNoWait()` + status polling only. The launch-logging patch adds incremental stdout polling during the wait loop.

### Enable launch-step stdout streaming (once per portal)

On the bastion:

```bash
./controller/configure-portal-launch-logging.sh
```

This adds an init container that patches `aapLaunchJobTemplate.cjs.js` after dynamic plugins install. Idempotent across pod restarts.

### Example launch step log (patch template)

```
Beginning step DEMO - Patch RHEL Servers
Job launched with ID: 92
Waiting for result of the executed job template (job ID: 92).
Job 92 status: running
DEMO_PATCH_PORTAL | host=node1 | packages=openssl-libs
DEMO_PATCH_PORTAL | host=node2 | packages=none
===== DEMO PATCH PACKAGE SUMMARY (portal) =====
node1: openssl-libs
node2: none
===== END DEMO PATCH PACKAGE SUMMARY (portal) =====
Job 92 status: successful
Job 92 completed with status: successful
Finished step DEMO - Patch RHEL Servers
```

## Portal patch job output (per-node packages)

### Approach

| Layer | What it does |
|-------|----------------|
| `roles/rhel_patching` | Per-host banners plus `DEMO_PATCH_PORTAL` marker lines; sets `rhel_patching_updated_package_names` |
| `playbooks/patch_rhel.yml` | Final play on `web` (run_once) prints `DEMO PATCH PACKAGE SUMMARY (portal)` block for all `web` hosts |
| Custom portal template | `controller/portal-templates/patch-rhel-package-summary.yaml` — single `rhaap:launch-job-template` step for template 44 |
| Launch-logging patch | `configure-portal-launch-logging.sh` streams `DEMO_*` lines into the scaffolder step log |

Presenters launch **DEMO - Patch RHEL Servers (with package summary)** instead of the auto-generated tile. Per-node package names appear in the **Create Task** log during the launch step.

## Portal deploy job output (per-node details)

Auto-generated **Deploy Web Application** portal templates show the same high-level scaffolder log as patching (job ID and status only). Per-host deploy details live in Controller job stdout unless you use the custom portal template.

### Approach

| Layer | What it does |
|-------|----------------|
| `roles/web_application` | Per-host banners plus `DEMO_DEPLOY_PORTAL` marker lines; sets `web_app_deploy_*` facts (packages, stage, services, URL, content) |
| `playbooks/deploy_application.yml` | Final play on `web` (run_once) prints `DEMO DEPLOY SUMMARY (portal)` block for all `web` hosts |
| Custom portal template | `controller/portal-templates/deploy-web-app-summary.yaml` — single `rhaap:launch-job-template` step for template 47 |

### Register custom portal templates (once per portal)

1. On the bastion, enable launch-step stdout streaming:

   ```bash
   ./controller/configure-portal-launch-logging.sh
   ```

2. Sign in to the portal as an AAP administrator.
3. **Templates** → **Add template**.
4. Git URL:

   `https://github.com/ronamalka/ansible_for_rhel/blob/main/controller/portal-templates/catalog-info.yaml`

5. Click **Analyze** → **Import** (imports patch, deploy, verify, and OpenShift deploy summary templates).
6. Grant `demo-portal-users` catalog read on the new templates (or rely on tag filter if configured).

After updating template YAML in Git, re-import or wait for catalog refresh (~30 minutes). Templates use only `rhaap:launch-job-template` — no separate stdout fetch step.

Presenters launch **DEMO - Deploy Web Application (with deploy summary)** instead of the auto-generated tile. Per-node deploy details appear in the **Create Task** launch step log:

```
===== DEMO DEPLOY SUMMARY (portal) =====
node1: packages=httpd, firewalld | stage=dev | services=httpd=running, firewalld=running | url=http://node1/ | content=Development content deployed by Ansible
node2: packages=httpd, firewalld | stage=prod | services=httpd=running, firewalld=running | url=http://node2/ | content=Production content deployed by Ansible
node3: packages=httpd, firewalld | stage=dev | services=httpd=running, firewalld=running | url=http://node3/ | content=Development content deployed by Ansible
===== END DEMO DEPLOY SUMMARY (portal) =====
```

## Portal verify job output (per-node checks)

Auto-generated **Verify Web Application** portal templates show the same high-level scaffolder log as patching and deploy (job ID and status only). Per-host URL, HTTP status, and content checks live in Controller job stdout unless you use the custom portal template.

### Approach

| Layer | What it does |
|-------|----------------|
| `playbooks/verify_application.yml` | Per-host URI check plus `DEMO_VERIFY_PORTAL` marker lines; sets `web_verify_*` facts (url, status, stage, content) |
| `playbooks/verify_application.yml` | Final play on `web` (run_once) prints `DEMO VERIFY SUMMARY (portal)` block for all `web` hosts |
| Custom portal template | `controller/portal-templates/verify-web-app-summary.yaml` — single `rhaap:launch-job-template` step for template 48 |

Presenters launch **DEMO - Verify Web Application (with verify summary)** instead of the auto-generated tile. Per-node verify checks appear in the **Create Task** launch step log:

```
===== DEMO VERIFY SUMMARY (portal) =====
node1: url=http://127.0.0.1 | status=200 | stage=dev | content=<!DOCTYPE html> <html lang="en"> <head> <meta charset="UTF-8"> <title>node1 - DEV</title>...
node2: url=http://127.0.0.1 | status=200 | stage=prod | content=<!DOCTYPE html> <html lang="en"> <head> <meta charset="UTF-8"> <title>node2 - PROD</title>...
node3: url=http://127.0.0.1 | status=200 | stage=dev | content=<!DOCTYPE html> <html lang="en"> <head> <meta charset="UTF-8"> <title>node3 - DEV</title>...
===== END DEMO VERIFY SUMMARY (portal) =====
```

## Portal OpenShift deploy job output

Auto-generated **Deploy App on OpenShift** portal templates show the same high-level scaffolder log as other DEMO tiles unless you use the custom portal template.

### Approach

| Layer | What it does |
|-------|----------------|
| `roles/openshift_app_deploy` | Validates namespace; Tekton or direct deploy; `DEMO_OCP_DEPLOY_PORTAL` marker lines |
| `playbooks/deploy_openshift_app.yml` | Runs on `localhost` with OpenShift API credential |
| Custom portal template | `controller/portal-templates/deploy-openshift-app-summary.yaml` — single `rhaap:launch-job-template` step |
| Launch-logging patch | `configure-portal-launch-logging.sh` streams `DEMO_OCP_*` lines into the scaffolder step log |

Presenters launch **DEMO - Deploy App on OpenShift (with deploy summary)** instead of the auto-generated tile. Deploy method, route URL, and content check appear in the **Create Task** launch step log:

```
DEMO_OCP_DEPLOY_PORTAL | namespace=demo-web-lab | app=demo-web | method=direct | url=https://demo-web-demo-web-lab.apps.cluster-jmvv9... | content=<html>...
===== DEMO OCP DEPLOY SUMMARY (portal) =====
namespace=demo-web-lab | app=demo-web | method=direct | url=https://demo-web-demo-web-lab.apps... | content=...
===== END DEMO OCP DEPLOY SUMMARY (portal) =====
```

### Sync Controller project after Git push

On the bastion (with `CONTROLLER_TOKEN` or `CONTROLLER_PASSWORD` set):

```bash
./controller/sync-demo-project.sh
# PROJECT_ID=43 by default on jmvv9
```

## Troubleshooting

| Issue | Resolution |
|-------|------------|
| API 401/403 with admin password | Use `CONTROLLER_TOKEN` instead |
| User/team create 403 | Create via Gateway UI or controller DB on OCP deployments |
| demo-user sees no templates (controller) | Re-run `configure-self-service.sh`; confirm Execute role |
| demo-user sees no templates (portal) | Run `./controller/configure-portal-rbac.sh` on bastion; confirm 15 Casbin rules; sign in with RHAAP OAuth |
| Portal login shows GitHub instead of AAP | Helm chart enables `backstage-plugin-auth-backend-module-github-provider` by default; run `DISABLE_GUEST_AUTH=1 ./controller/deploy-self-service-portal.sh` or re-run full deploy script |
| Portal login fails / **Failed to post data** | Check `backstage-backend` logs for `invalid_client` on `/o/token/`; align `oauth-client-id` with **Gateway** app (`curl -sk -u admin:$PASS $AAP_HOST_URL/api/gateway/v1/applications/`); public apps need empty `oauth-client-secret`; confidential apps need the matching secret; enable `ALLOW_OAUTH2_FOR_EXTERNAL_USERS`; redirect URI must match portal route (`apps.` on OpenTLC) |
| Portal `CrashLoopBackOff` / `YAMLParseError duplicate production` | Do not merge a second `catalog.providers.rhaap.production` block; run `REPAIR_APP_CONFIG=1 ./controller/deploy-self-service-portal.sh` |
| Portal chart missing | Download from Red Hat Customer Portal or use OpenShift Helm catalog with registry auth |
| Jobs unreachable on node* | Provision RHEL VMs or add DNS/`/etc/hosts` for target hosts |
| Portal shows job ID only, no packages | Use custom template **DEMO - Patch RHEL Servers (with package summary)** and run `./controller/configure-portal-launch-logging.sh` on bastion |
| Portal shows job ID only, no deploy details | Use custom template **DEMO - Deploy Web Application (with deploy summary)** and run `./controller/configure-portal-launch-logging.sh` |
| Portal shows job ID only, no verify details | Use custom template **DEMO - Verify Web Application (with verify summary)** and run `./controller/configure-portal-launch-logging.sh` |
| Portal shows job ID only, no OpenShift deploy details | Use custom template **DEMO - Deploy App on OpenShift (with deploy summary)** and run `./controller/configure-portal-launch-logging.sh` |
| OpenShift deploy job fails auth | Attach **OpenShift Credentials** (id 34) to template; verify token on credential |
| Launch log still shows only job ID/status | Re-run `./controller/configure-portal-launch-logging.sh`; confirm init container `patch-portal-launch-logging` succeeded; re-import templates from Git |

## References

- [Installing self-service automation portal (AAP 2.5)](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/installing_self-service_automation_portal/)
- [Using self-service automation portal (AAP 2.5)](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/using_self-service_automation_portal/)
- [Job templates configuration](job-templates.md)
- [Workflow setup](workflow-setup.md)

## Portal catalog curation (jmvv9)

The portal catalog is built from three sources:

| Source | Config | Notes |
|--------|--------|-------|
| RHAAP job template sync | `catalog.providers.rhaap.production.sync.jobTemplates` in `redhat-rhaap-portal-app-config` | Syncs Controller job templates in org `Default` |
| Git Location | `catalog.locations` pointing at `controller/portal-templates/catalog-info.yaml` | Custom scaffolder templates (summary launchers) |
| Upstream sample | `ansible-rhdh-templates` EE builder URL | Optional; not tagged for demo RBAC |

### Templates removed from the jmvv9 portal catalog (2026-07)

These remain in **Controller** but are **not** listed in the self-service portal:

| Portal title | Entity name(s) | Method |
|--------------|----------------|--------|
| create-volume-snapshot | `createvolumesnapshot` | Label filter on RHAAP sync + DB prune |
| DEMO - Deploy Web Application | `demo--deploy-web-application`, `demo-deploy-web-app-summary` | Removed `demo-self-service` label from template 47; dropped custom YAML from `catalog-info.yaml`; DB prune |
| Demo Job Template | `demo-job-template` | Label filter + DB prune |
| DEMO - Patch RHEL Servers | `demo--patch-rhel-servers`, `demo-patch-rhel-package-summary` | Removed label from template 44; dropped custom YAML; DB prune |
| DEMO - Verify Web Application | `demo--verify-web-application`, `demo-verify-web-app-summary` | Removed label from template 48; dropped custom YAML; DB prune |
| patch-route-with-cert | `patchroutewithcert` | Label filter + DB prune |
| set-resource-quota-on-namespace | `setresourcequotaonnamespace` | Label filter + DB prune |

**Still in catalog:** OpenSCAP scan/remediate (45-46), seed patch demo packages (50), **DEMO - Deploy App on OpenShift (with deploy summary)** via `deploy-openshift-app-summary.yaml` only.

### How to hide or restore portal templates

1. **RHAAP-synced Controller templates** — only job templates with label `demo-self-service` are imported when the app-config filter is applied:

   ```bash
   export CONTROLLER_TOKEN='<token>'
   PATCH_APP_CONFIG=1 RESTART_PORTAL=0 ./controller/prune-portal-catalog.sh
   ```

   `patch-portal-catalog-filter.py` inserts `jobTemplates.filters.labels.include: [demo-self-service]` under `catalog.providers.rhaap.production.sync`.

2. **Custom summary templates** — edit `controller/portal-templates/catalog-info.yaml` targets, push to Git, then re-import the Location in the portal UI or wait for `catalog.processingInterval` (30 minutes). `orphanStrategy: delete` removes stale entities.

3. **Immediate removal** — delete rows from `backstage_plugin_catalog.refresh_state` for the `template:default/...` entity ref (cascades to `final_entities`). Re-run `prune-portal-catalog.sh` for the standard removal set.

4. **demo-user visibility** — `configure-portal-rbac.sh` adds a conditional catalog read policy requiring tag `demo-self-service` on catalog entities. Keep that tag on Controller labels and on custom Template YAML metadata for anything demo-user should launch.

