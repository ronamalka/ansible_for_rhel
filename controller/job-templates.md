# Automation Controller Job Template Configuration

Use these settings when creating job templates in Ansible Automation Controller for this demo.

## Prerequisites

| Resource | Value |
|----------|-------|
| Controller URL | `https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com` |
| Gateway URL | `https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com` |
| Inventory | **Workshop Inventory** (id: 34 on jmvv9) |
| Credential | **Workshop Credential** (Machine, id: 35) |
| Execution Environment | Default execution environment (id: 2) |
| Project | **RHEL Demo Project** (id: 43) |

## Project Setup

| Parameter | Value |
|-----------|-------|
| Name | RHEL Demo Project |
| Controller project id | 43 |
| Organization | Default |
| SCM Type | Git |
| SCM URL | `https://github.com/ronamalka/ansible_for_rhel.git` |
| SCM Branch | `main` |
| Options | Clean, Delete, Update Revision on Launch |

This project is configured on the sandbox controller and syncs from the public GitHub repository above.

**CLI alternative:** Copy this repository to the bastion for ad hoc `ansible-playbook` runs:

```bash
# From your workstation
scp -r ansible_for_rhel/ lab-user@bastion.jmvv9.sandbox3400.opentlc.com:~/ansible_for_rhel/
```

## Post-create: attach SSH credential

Job templates do not store SSH keys in Git. After creating the DEMO templates, attach **Workshop Credential** (Machine, id 4 on the sandbox):

```bash
export CONTROLLER_TOKEN='<controller-token>'
./controller/configure-demo-job-templates.sh
```

Without this step, jobs connect as `root` with no key and fail with `Permission denied (publickey,...)`.

## Self-service access

After templates exist, configure the demo self-service user and RBAC:

```bash
export CONTROLLER_TOKEN='<controller-token>'
export DEMO_USER_PASSWORD='<demo-user-password>'
./controller/configure-self-service.sh
```

See `controller/self-service-setup.md` for portal deployment, verification, and the full initial setup checklist.

## Job Templates

Create each template via **Automation Execution → Templates → Create template → Create job template**.

### 1. Patch RHEL Servers

| Parameter | Value |
|-----------|-------|
| Name | DEMO - Patch RHEL Servers |
| Inventory | Workshop Inventory |
| Project | RHEL Demo Project |
| Playbook | `playbooks/patch_rhel.yml` |
| Credentials | Workshop Credential |
| Limit | `web` |
| Privilege Escalation | Enabled |
| Extra Variables | `security_only: false` (fallback; survey overrides at launch) |
| Survey enabled | Yes (configured on controller, template id 11) |

**Survey questions** (shown at launch; values are passed as extra vars):

| Label | Variable | Type | Choices | Default |
|-------|----------|------|---------|---------|
| Security updates only? | `security_only` | Multiple Choice | `false`, `true` | `false` |
| Reboot after patching? | `reboot_after_patch` | Multiple Choice | `false`, `true` | `false` |

Survey answers are strings (`"true"` / `"false"`). The playbook maps them with `| default(false)` and the role evaluates them with `| bool`, so choosing **true** for reboot runs `ansible.builtin.reboot` only when `needs-restarting -r` reports a reboot is required.

Configure or update the survey via API:

```bash
export CONTROLLER_PASSWORD='<controller-admin-password>'
curl -sk -u "admin:${CONTROLLER_PASSWORD}" -X POST -H 'Content-Type: application/json' \
  "https://ansible-1.4mrmx.sandbox3261.opentlc.com/api/v2/job_templates/11/survey_spec/" \
  -d @controller/patch-rhel-survey.json

curl -sk -u "admin:${CONTROLLER_PASSWORD}" -X PATCH -H 'Content-Type: application/json' \
  "https://ansible-1.4mrmx.sandbox3261.opentlc.com/api/v2/job_templates/11/" \
  -d '{"survey_enabled": true}'
```

### 2. OpenSCAP Compliance Scan

| Parameter | Value |
|-----------|-------|
| Name | DEMO - OpenSCAP Scan |
| Inventory | Workshop Inventory |
| Project | RHEL Demo Project |
| Playbook | `playbooks/openscap_scan.yml` |
| Credentials | Workshop Credential |
| Limit | `web` |
| Privilege Escalation | Enabled |
| Job Tags | `scan` |
| Ask limit on launch | Yes (use `node1` for faster demos) |
| Timeout | 1800 |

### 3. OpenSCAP Remediation

| Parameter | Value |
|-----------|-------|
| Name | DEMO - OpenSCAP Remediate |
| Inventory | Workshop Inventory |
| Project | RHEL Demo Project |
| Playbook | `playbooks/openscap_remediate.yml` |
| Credentials | Workshop Credential |
| Limit | `web` |
| Privilege Escalation | Enabled |
| Job Tags | `remediate` |
| Ask limit on launch | Yes (use `node2` for demo; `node1` for faster runs) |
| Timeout | 3600 |

The remediate playbook enables `openscap_demo_mode: true` by default. Job stdout shows **full CIS baseline** (~97%) plus **demo profile** before/after scores (target 100%). Override with extra var `openscap_demo_mode: false` for full CIS only.

### 4. Deploy Web Application

| Parameter | Value |
|-----------|-------|
| Name | DEMO - Deploy Web Application |
| Inventory | Workshop Inventory |
| Project | RHEL Demo Project |
| Playbook | `playbooks/deploy_application.yml` |
| Credentials | Workshop Credential |
| Limit | `web` |
| Ask limit on launch | Yes (use `node1` for faster demos) |
| Privilege Escalation | Enabled |
| Extra Variables | See below |

Default extra variables:

```yaml
dev_content: "Development content deployed by Ansible"
prod_content: "Production content deployed by Ansible"
```

**Optional survey questions:**

| Question | Variable | Type |
|----------|----------|------|
| Development page content | `dev_content` | Text |
| Production page content | `prod_content` | Text |

### 5. Verify Web Application

| Parameter | Value |
|-----------|-------|
| Name | DEMO - Verify Web Application |
| Inventory | Workshop Inventory |
| Project | RHEL Demo Project |
| Playbook | `playbooks/verify_application.yml` |
| Credentials | Workshop Credential |
| Limit | `web` |
| Ask limit on launch | Yes (use `node1` for faster demos) |
| Privilege Escalation | Disabled |

## Existing Controller Resources

The environment already includes:

| Resource | Details |
|----------|---------|
| Inventory | Workshop Inventory — hosts: node1, node2, node3, ansible-1 |
| Groups | `web` (node1, node2, node3), `control` (ansible-1) |
| Project | Ansible official demo project → `https://github.com/RedHatGov/product-demos` |
| Project | **RHEL Demo Project** (id: 10) → `https://github.com/ronamalka/ansible_for_rhel.git` |
| Job Template | SECURITY / Hardening → `linux/hardening.yml` |
| Job Templates | DEMO - Patch RHEL Servers (11), OpenSCAP Scan (12), OpenSCAP Remediate (13), Deploy Web Application (14), Verify Web Application (15) |
| Self-service | demo-user with Execute on templates 11–16 (see `self-service-setup.md`) |

You can keep the existing hardening template for comparison alongside the DEMO templates from this repo.

## Ad Hoc Commands (Post-Demo Verification)

From **Workshop Inventory → Hosts → Run Command**:

```bash
# Verify Apache is running
systemctl status httpd

# Check OpenSCAP reports exist
ls -la /var/log/ansible-demo/openscap/

# Curl the deployed application
curl http://node1.example.com
curl http://node2.example.com
curl http://node3.example.com
```

## API Quick Reference

```bash
CONTROLLER="https://ansible-1.4mrmx.sandbox3261.opentlc.com"
# Set from environment — never commit credentials
export CONTROLLER_USER="${CONTROLLER_USER:-admin}"
export CONTROLLER_PASSWORD="${CONTROLLER_PASSWORD:?set CONTROLLER_PASSWORD}"
AUTH="${CONTROLLER_USER}:${CONTROLLER_PASSWORD}"

# List inventories
curl -sk -u "$AUTH" "$CONTROLLER/api/v2/inventories/"

# List job templates
curl -sk -u "$AUTH" "$CONTROLLER/api/v2/job_templates/"

# Launch a job template (replace TEMPLATE_ID)
curl -sk -u "$AUTH" -X POST "$CONTROLLER/api/v2/job_templates/TEMPLATE_ID/launch/"
```
