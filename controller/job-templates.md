# Automation Controller Job Template Configuration

Use these settings when creating job templates in Ansible Automation Controller for this demo.

## Prerequisites

| Resource | Value |
|----------|-------|
| Controller URL | `https://ansible-1.4mrmx.sandbox3261.opentlc.com` |
| Inventory | **Workshop Inventory** (id: 2) |
| Credential | **Workshop Credential** (Machine, id: 4) |
| Execution Environment | Default execution environment |
| Project | Create **RHEL Demo Project** (see below) |

## Project Setup

| Parameter | Value |
|-----------|-------|
| Name | RHEL Demo Project |
| Controller project id | 10 |
| Organization | Default |
| SCM Type | Git |
| SCM URL | `https://github.com/ronamalka/ansible_for_rhel.git` |
| SCM Branch | `main` |
| Options | Clean, Delete, Update Revision on Launch |

This project is configured on the sandbox controller and syncs from the public GitHub repository above.

**CLI alternative:** Copy this repository to the bastion for ad hoc `ansible-playbook` runs:

```bash
# From your workstation
scp -r ansible_for_rhel/ student1@ansible-1.4mrmx.sandbox3261.opentlc.com:~/ansible_for_rhel/
```

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
| Extra Variables | `security_only: false` |

**Optional survey questions:**

| Question | Variable | Type | Default |
|----------|----------|------|---------|
| Security updates only? | `security_only` | Multiple Choice (true/false) | false |
| Reboot after patching? | `reboot_after_patch` | Multiple Choice (true/false) | false |

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
| Timeout | 3600 |

### 4. Deploy Web Application

| Parameter | Value |
|-----------|-------|
| Name | DEMO - Deploy Web Application |
| Inventory | Workshop Inventory |
| Project | RHEL Demo Project |
| Playbook | `playbooks/deploy_application.yml` |
| Credentials | Workshop Credential |
| Limit | `web` |
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
