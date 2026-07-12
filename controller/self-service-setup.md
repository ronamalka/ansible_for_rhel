# Self-Service Portal Setup

Configure Ansible Automation Platform so demo attendees can launch RHEL automations through a self-service experience without admin privileges.

## Overview

AAP 2.5+ provides two self-service options:

| Mode | URL | When to use |
|------|-----|-------------|
| **Automation Portal** (recommended) | `https://<portal-host>/` | Full AAP deployment with the self-service automation portal component on OpenShift |
| **Controller templates (limited)** | `https://<controller>/#/templates` | Controller-only sandboxes; demo user sees only templates they can execute |

This repository configures **controller-side prerequisites** (user, team, RBAC, labels, descriptions, OAuth) required for both modes.

## Prerequisites

| Resource | Sandbox value |
|----------|---------------|
| Controller | `https://ansible-1.4mrmx.sandbox3261.opentlc.com` |
| Organization | Default (id: 1) |
| DEMO job templates | ids 11–15 |
| DEMO workflow | id 16 |
| Admin credentials | Set via environment (never commit) |

Run after:

1. [Job templates](job-templates.md) exist and Workshop Credential is attached (`configure-demo-job-templates.sh`)
2. [Workflow](workflow-setup.md) is configured (template id 16)

## Quick setup (API script)

```bash
export CONTROLLER_PASSWORD='<controller-admin-password>'
export DEMO_USER_PASSWORD='<demo-user-password>'   # set in lab, not in Git

./controller/configure-self-service.sh
```

The script is idempotent. Re-run safely after adding templates or rebuilding the controller.

### What the script configures

1. Enables `ALLOW_OAUTH2_FOR_EXTERNAL_USERS` (required for automation portal OAuth login)
2. Creates **demo-user** (non-admin) and **Demo Self-Service** team
3. Grants organization **Member** role and **Execute** on all DEMO templates (11–16)
4. Applies label `demo-self-service` for portal tag-based RBAC filtering
5. Sets human-readable descriptions on all DEMO templates
6. Creates **Ansible Automation Portal** OAuth application (update redirect URI after portal deploy)
7. Verifies demo-user can list DEMO templates via API

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CONTROLLER` | Sandbox controller URL | AAP controller base URL |
| `CONTROLLER_USER` | `admin` | Admin username for API setup |
| `CONTROLLER_PASSWORD` | *(required)* | Admin password |
| `DEMO_USER` | `demo-user` | Self-service demo account |
| `DEMO_USER_PASSWORD` | *(required)* | Demo user password (lab-only) |
| `DEMO_TEAM` | `Demo Self-Service` | Team name |
| `DEMO_TEMPLATE_IDS` | `11 12 13 14 15` | Job template IDs |
| `WORKFLOW_TEMPLATE_ID` | `16` | Workflow template ID |
| `OAUTH_REDIRECT_URI` | Placeholder | Update after portal deployment |

## Demo user credentials (presenter)

| Field | Value |
|-------|-------|
| Username | `demo-user` |
| Password | `<demo-user-password>` — set during lab setup via `DEMO_USER_PASSWORD` |
| Role | Non-admin; Execute on DEMO templates only |

Presenters should share the demo password verbally or via the lab guide, not in Git.

## Templates exposed to self-service

| ID | Name | Type | Survey |
|----|------|------|--------|
| 11 | DEMO - Patch RHEL Servers | Job | Yes (`security_only`, `reboot_after_patch`) |
| 12 | DEMO - OpenSCAP Scan | Job | No |
| 13 | DEMO - OpenSCAP Remediate | Job | No |
| 14 | DEMO - Deploy Web Application | Job | Optional extra vars |
| 15 | DEMO - Verify Web Application | Job | No |
| 16 | DEMO - RHEL Operations Pipeline | Workflow | Inherits node surveys |

All templates are labeled `demo-self-service` for portal tag filtering.

## Automation Portal deployment (full AAP)

The sandbox controller at `ansible-1.4mrmx.sandbox3261.opentlc.com` is **controller-only** — the separate automation portal component is not installed. Controller-side RBAC is configured and ready when a portal is deployed.

### Post-portal steps

1. Deploy automation portal per [Red Hat AAP 2.6 install docs](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/installing_on_openshift_container_platform/index)
2. Update OAuth redirect URI:
   - **Access Management → OAuth Applications → Ansible Automation Portal**
   - Set **Redirect URIs** to: `https://<portal-url>/api/auth/rhaap/handler/frame`
3. Configure portal RBAC (Administration → RBAC):
   - Create role (e.g. `demo-portal-users`)
   - Assign **Demo Self-Service** team
   - Enable **Catalog** `catalog.entity.read`
   - Enable **Scaffolder** permissions: `scaffolder.action.execute`, `scaffolder.task.*`, `scaffolder.template.*`
4. Optional: conditional access by tag `demo-self-service` (see Red Hat RBAC docs)

### Portal URL

After deployment: `https://<your-portal-host>/`

Sign in with **demo-user** credentials (same as controller).

## Controller-only self-service (sandbox)

When no automation portal is deployed, demo-user can launch templates from the controller UI:

1. Open `https://ansible-1.4mrmx.sandbox3261.opentlc.com`
2. Sign in as **demo-user**
3. Go to **Automation Execution → Templates**
4. Only the six DEMO templates appear (RBAC filtered)

This demonstrates RBAC without the portal tile UI. For customer demos, prefer the automation portal when available.

## Verification

### API check (as demo-user)

```bash
CONTROLLER="https://ansible-1.4mrmx.sandbox3261.opentlc.com"
export DEMO_USER_PASSWORD='<demo-user-password>'

curl -sk -u "demo-user:${DEMO_USER_PASSWORD}" \
  "${CONTROLLER}/api/v2/unified_job_templates/?search=DEMO&order_by=name" \
  | python3 -c "import sys,json; [print(r['name']) for r in json.load(sys.stdin)['results']]"
```

Expected output (6 templates):

```
DEMO - Deploy Web Application
DEMO - OpenSCAP Remediate
DEMO - OpenSCAP Scan
DEMO - Patch RHEL Servers
DEMO - RHEL Operations Pipeline
DEMO - Verify Web Application
```

### Launch permission check

```bash
curl -sk -u "demo-user:${DEMO_USER_PASSWORD}" \
  "${CONTROLLER}/api/v2/job_templates/11/launch/" | python3 -m json.tool | head -5
```

Should return survey/launch schema (not 403).

## Initial demo setup checklist

Complete these steps in order for a fresh controller:

| Step | Action | Reference |
|------|--------|-----------|
| 1 | Sync **RHEL Demo Project** from GitHub | [job-templates.md](job-templates.md) |
| 2 | Create DEMO job templates (11–15) | [job-templates.md](job-templates.md) |
| 3 | Attach Workshop Credential | `configure-demo-job-templates.sh` |
| 4 | Configure Patch survey | `patch-rhel-survey.json` |
| 5 | Create workflow pipeline (16) | [workflow-setup.md](workflow-setup.md) |
| 6 | Configure self-service RBAC | `configure-self-service.sh` |
| 7 | Verify demo-user template access | This guide, Verification section |
| 8 | (Optional) Deploy automation portal | Red Hat AAP install docs |

## Troubleshooting

| Issue | Resolution |
|-------|------------|
| demo-user sees no templates | Re-run `configure-self-service.sh`; confirm Execute role on templates |
| demo-user gets 403 on launch | Verify Execute (not just Read) role assignment |
| Portal login fails | Enable `ALLOW_OAUTH2_FOR_EXTERNAL_USERS`; verify OAuth redirect URI |
| Portal shows no templates | Grant portal RBAC role; ensure AAP Execute permissions exist |
| Templates missing descriptions | Re-run script; metadata in `demo-template-metadata.json` |

## References

- [Using self-service automation portal (AAP 2.5)](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/using_self-service_automation_portal/)
- [Initial portal RBAC setup (AAP 2.6)](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/install-con_self_service_initial_rbac_setup)
- [Job templates configuration](job-templates.md)
- [Workflow setup](workflow-setup.md)
