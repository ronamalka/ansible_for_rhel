# Self-Service Portal Setup

Configure Ansible Automation Platform so demo attendees can launch RHEL automations through a self-service experience without admin privileges.

## Overview

AAP 2.5+ provides two self-service options:

| Mode | URL | When to use |
|------|-----|-------------|
| **Automation Portal** (recommended) | `https://<portal-route>/` | Full AAP + OpenShift deployment with the self-service automation portal Helm chart |
| **Controller templates (limited)** | `https://<controller>/#/templates` | Fallback when portal is not deployed |

This repository configures **controller-side prerequisites** (user, team, RBAC, labels, descriptions, OAuth) required for both modes.

## Environment (OpenTLC jmvv9 — full AAP + OpenShift)

| Resource | Value |
|----------|-------|
| AAP Gateway (UI) | `https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com` |
| AAP Controller API | `https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com` |
| OpenShift Console | `https://console-openshift-console.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com` |
| Bastion | `ssh lab-user@bastion.jmvv9.sandbox3400.opentlc.com` |
| Organization | Default (id: 1) |
| Admin / token | `<admin-password>` / `<controller-token>` (lab environment — **never commit**) |

### Configured resource IDs (jmvv9 sandbox)

| Resource | ID |
|----------|-----|
| RHEL Demo Project | 43 |
| Workshop Inventory | 34 |
| Workshop Credential | 35 |
| DEMO job templates | 44–48 |
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
export OAUTH_CLIENT_SECRET=""   # public OAuth client — leave empty
export AAP_TOKEN="<controller-token>"
./controller/deploy-self-service-portal.sh
```

### 3. Install Helm chart

From **OpenShift Developer → Helm → Create → Automation Portal** (or equivalent chart name):

```yaml
redhat-developer-hub:
  global:
    clusterRouterBase: cluster-jmvv9.jmvv9.sandbox3400.opentlc.com
    pluginMode: oci
```

`clusterRouterBase` must match your OpenShift apps domain (not `apps.example.com`).

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

In the portal → **Administration → RBAC**, create a role (e.g. `demo-portal-users`):

- Assign **Demo Self-Service** team (or demo-user)
- **Catalog:** `catalog.entity.read`
- **Scaffolder:** `scaffolder.action.execute`, `scaffolder.task.*`, `scaffolder.template.*`
- Optional conditional access by tag `demo-self-service`

See [Red Hat initial portal RBAC setup](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/install-con_self_service_initial_rbac_setup).

### Portal URL

After deployment:

```
https://redhat-rhaap-portal-rhaap-portal.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/
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
| Portal URL | `https://redhat-rhaap-portal-rhaap-portal.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/` |
| OAuth redirect URI | Updated to portal `/api/auth/rhaap/handler/frame` |
| Portal RBAC for demo-user | **Manual** — assign Demo Self-Service team in portal Administration → RBAC |
| External DNS | Portal hostname may show `NXDOMAIN` briefly; route is reachable via OpenShift router |

Automated deploy on bastion:

```bash
export OAUTH_CLIENT_ID="7Njfd7j6xn58tDAb8C3Xjf6fUbssydjT22niynvT"
export AAP_TOKEN="<controller-token>"
./controller/deploy-self-service-portal.sh
```

Public OAuth clients require a non-empty `oauth-client-secret` in the OpenShift secret (the script uses a placeholder). OCI plug-in mode requires the `redhat-rhaap-portal-dynamic-plugins-registry-auth` secret built from cluster pull credentials or a local `auth.json`.

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

## Troubleshooting

| Issue | Resolution |
|-------|------------|
| API 401/403 with admin password | Use `CONTROLLER_TOKEN` instead |
| User/team create 403 | Create via Gateway UI or controller DB on OCP deployments |
| demo-user sees no templates | Re-run `configure-self-service.sh`; confirm Execute role |
| Portal login fails | Enable `ALLOW_OAUTH2_FOR_EXTERNAL_USERS`; verify OAuth redirect URI |
| Portal chart missing | Download from Red Hat Customer Portal or use OpenShift Helm catalog with registry auth |
| Jobs unreachable on node* | Provision RHEL VMs or add DNS/`/etc/hosts` for target hosts |

## References

- [Installing self-service automation portal (AAP 2.5)](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/installing_self-service_automation_portal/)
- [Using self-service automation portal (AAP 2.5)](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/using_self-service_automation_portal/)
- [Job templates configuration](job-templates.md)
- [Workflow setup](workflow-setup.md)
