# Ansible for RHEL — Operations Demo

End-to-end demonstration of managing Red Hat Enterprise Linux servers with Ansible and Ansible Automation Platform. Structured after the [Ansible for RHEL Workshop](https://labs.demoredhat.com/exercises/ansible_rhel/) labs.

## Demo Scope

| Capability | Status | Implementation |
|------------|--------|----------------|
| Deploying RHEL VMs | Out of scope | Pre-provisioned sandbox hosts |
| Patching machines | In scope | `playbooks/patch_rhel.yml` |
| OpenSCAP scan + remediation | In scope | `playbooks/openscap_scan.yml`, `openscap_remediate.yml` |
| Application deployment | In scope | `playbooks/deploy_application.yml` |
| Monitoring / dashboard | In scope | `monitoring/automation-dashboard.md` |

## Environment

| Resource | Value |
|----------|-------|
| Controller | `https://ansible-1.4mrmx.sandbox3261.opentlc.com` |
| Controller user | `admin` (password: see lab environment or Ansible Vault) |
| Bastion SSH | `ssh student1@ansible-1.4mrmx.sandbox3261.opentlc.com` |
| Bastion password | `<bastion-password>` (see lab environment) |
| Git repository | `https://github.com/ronamalka/ansible_for_rhel` |
| Inventory | Workshop Inventory (Controller) / `inventories/workshop/hosts` (CLI) |

### Target RHEL Hosts

| Host | FQDN | Group | Stage |
|------|------|-------|-------|
| node1 | `node1.example.com` | web | dev |
| node2 | `node2.example.com` | web | prod |
| node3 | `node3.example.com` | web | dev |

All hosts run **RHEL 8.7**. Managed user: `ec2-user` with key `~/.ssh/4mrmxkey.pem` on the bastion.

## Repository Structure

```
ansible_for_rhel/
├── README.md                          # This guide
├── ansible.cfg
├── requirements.yml
├── inventories/workshop/
│   ├── hosts                          # Environment inventory
│   ├── group_vars/web.yml
│   └── host_vars/node2.yml
├── playbooks/
│   ├── patch_rhel.yml
│   ├── openscap_scan.yml
│   ├── openscap_remediate.yml
│   ├── deploy_application.yml
│   ├── verify_application.yml
│   └── site.yml                       # Full CLI pipeline
├── roles/
│   ├── rhel_patching/
│   ├── openscap/
│   └── web_application/
├── controller/
│   ├── job-templates.md               # AAP job template config
│   ├── workflow-setup.md              # Workflow visualizer guide
│   ├── self-service-setup.md          # Self-service portal setup guide
│   ├── configure-demo-job-templates.sh
│   ├── configure-self-service.sh      # Idempotent self-service RBAC script
│   ├── demo-template-metadata.json    # Template descriptions for portal
│   └── patch-rhel-survey.json
└── monitoring/
    └── automation-dashboard.md        # Dashboard demo script
```

## Quick Start (CLI on Bastion)

### 1. Copy the demo to the bastion

```bash
scp -r ansible_for_rhel/ student1@ansible-1.4mrmx.sandbox3261.opentlc.com:~/
```

### 2. SSH to the bastion

```bash
ssh student1@ansible-1.4mrmx.sandbox3261.opentlc.com
cd ~/ansible_for_rhel
```

### 3. Install collections

```bash
ansible-galaxy collection install -r requirements.yml
```

### 4. Verify connectivity

```bash
ansible web -m ping
```

### 5. Run the full demo pipeline

```bash
ansible-playbook playbooks/site.yml
```

Or run phases individually:

```bash
ansible-playbook playbooks/patch_rhel.yml
ansible-playbook playbooks/openscap_scan.yml
ansible-playbook playbooks/openscap_remediate.yml
ansible-playbook playbooks/deploy_application.yml
ansible-playbook playbooks/verify_application.yml
```

## Step-by-Step Demo Walkthrough

### Phase 1: Patching (~5-10 min)

**Story:** Operations team needs to keep RHEL servers current with the latest packages.

```bash
ansible-playbook playbooks/patch_rhel.yml
```

**Key talking points:**
- Idempotent package management with the `package` module
- Optional security-only patching: `-e security_only=true`
- Optional reboot: `-e reboot_after_patch=true`
- `needs-restarting -r` detects if a reboot is required

**Controller:** Launch job template **DEMO - Patch RHEL Servers** (see `controller/job-templates.md`).

### Phase 2: OpenSCAP Compliance Scan (~5-15 min per host)

**Story:** Security team requires CIS baseline compliance reporting.

```bash
ansible-playbook playbooks/openscap_scan.yml
```

**What happens:**
1. Installs `openscap-scanner` and `scap-security-guide`
2. Runs CIS profile scan against RHEL 8 SCAP content
3. Generates HTML and XML reports under `/var/log/ansible-demo/openscap/`

**Verify reports:**

```bash
ansible web -m shell -a "ls -la /var/log/ansible-demo/openscap/"
```

Exit codes: `0` = pass, `1` = error, `2` = failures found (expected on first scan).

**Controller:** Launch **DEMO - OpenSCAP Scan**.

### Phase 3: OpenSCAP Remediation (~10-30 min)

**Story:** Automatically fix compliance findings where remediations exist.

```bash
ansible-playbook playbooks/openscap_remediate.yml
```

**What happens:**
1. Runs `oscap xccdf eval --remediate` with the CIS profile
2. Re-scans to produce a post-remediation comparison report

**Controller:** Launch **DEMO - OpenSCAP Remediate**.

### Phase 4: Application Deployment (~3-5 min)

**Story:** Deploy Apache with environment-specific content (dev vs prod).

```bash
ansible-playbook playbooks/deploy_application.yml \
  -e 'dev_content="Dev demo content" prod_content="Prod demo content"'
```

**What happens:**
1. Installs `httpd` and `firewalld`
2. Opens HTTP in the firewall
3. Deploys templated `index.html` with stage-specific content
4. Verifies HTTP 200 response

**Check in browser or curl:**

```bash
curl http://node1.example.com    # dev content
curl http://node2.example.com    # prod content
curl http://node3.example.com    # dev content
```

**Controller:** Launch **DEMO - Deploy Web Application** with survey for content customization.

### Phase 5: Verification (~1 min)

```bash
ansible-playbook playbooks/verify_application.yml
```

Confirms each host serves the expected content via the `uri` module.

### Phase 6: Monitoring (~5 min)

Follow the script in `monitoring/automation-dashboard.md`:

1. Open Automation Dashboard before/after the workflow
2. Drill into job stdout and timing
3. Review OpenSCAP HTML reports
4. Query the API for job metrics

## Automation Controller Setup

Detailed configuration is in:

- `controller/job-templates.md` — five job templates with surveys
- `controller/workflow-setup.md` — chained workflow visualizer
- `controller/self-service-setup.md` — self-service portal and demo-user RBAC

### Initial Demo Setup Checklist

| Step | Action | Script / Doc |
|------|--------|--------------|
| 1 | Sync **RHEL Demo Project** from GitHub | [job-templates.md](controller/job-templates.md) |
| 2 | Create DEMO job templates (11–15) | [job-templates.md](controller/job-templates.md) |
| 3 | Attach Workshop Credential | `controller/configure-demo-job-templates.sh` |
| 4 | Configure Patch survey | `controller/patch-rhel-survey.json` |
| 5 | Create workflow pipeline (16) | [workflow-setup.md](controller/workflow-setup.md) |
| 6 | Configure self-service RBAC | `controller/configure-self-service.sh` |
| 7 | Verify demo-user template access | [self-service-setup.md](controller/self-service-setup.md) |

### Self-Service Portal

Non-admin users can launch DEMO automations without full controller access.

| Mode | URL | Notes |
|------|-----|-------|
| Controller templates | `https://ansible-1.4mrmx.sandbox3261.opentlc.com/#/templates` | Works on controller-only sandboxes |
| Automation Portal | `https://<portal-host>/` | Requires separate portal deployment |

**Demo user:** `demo-user` / `<demo-user-password>` (set via `DEMO_USER_PASSWORD` during setup — not stored in Git)

```bash
export CONTROLLER_PASSWORD='<controller-admin-password>'
export DEMO_USER_PASSWORD='<demo-user-password>'
./controller/configure-self-service.sh
```

All six DEMO templates (patch, OpenSCAP scan/remediate, deploy, verify, and the full workflow pipeline) are exposed with Execute permission. See `controller/self-service-setup.md` for verification steps and automation portal deployment.

### Workflow Overview

```
Patch → OpenSCAP Scan → OpenSCAP Remediate → Deploy App → Verify
```

Launch as **DEMO - RHEL Operations Pipeline** for the full demo from the Controller UI.

### Existing Environment Resources

The sandbox already has:
- **Workshop Inventory** with groups `web` and `control`
- **Workshop Credential** (Machine credential for SSH)
- **RHEL Demo Project** (id: 10) synced from `https://github.com/ronamalka/ansible_for_rhel.git`
- **DEMO job templates** (ids 11–15) for patch, OpenSCAP, deploy, and verify playbooks
- **DEMO - RHEL Operations Pipeline** workflow (id: 16)
- **Self-service** demo user `demo-user` with Execute on DEMO templates (see `controller/self-service-setup.md`)
- **Ansible official demo project** pointing to RedHatGov/product-demos
- **SECURITY / Hardening** job template (`linux/hardening.yml`)

## Demo Timing

| Phase | Duration |
|-------|----------|
| Patching | 5-10 min |
| OpenSCAP Scan | 5-15 min |
| OpenSCAP Remediate | 10-30 min |
| App Deploy | 3-5 min |
| Verify + Monitoring | 5 min |
| **Total** | **~30-60 min** |

For a shorter demo, skip remediation or limit to a single host with `--limit node1`.

## Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `security_only` | `false` | Patch only security updates |
| `reboot_after_patch` | `false` | Reboot if kernel updated |
| `openscap_profile` | CIS | SCAP evaluation profile |
| `stage` | `dev` (group), `prod` (node2) | Environment label for web content |
| `dev_content` | See group_vars | Development page body text |
| `prod_content` | See group_vars | Production page body text |

## Troubleshooting

| Issue | Resolution |
|-------|------------|
| SSH connection refused | Verify `~/.ssh/4mrmxkey.pem` exists on bastion |
| OpenSCAP timeout | Increase job template timeout to 3600s; use `--limit node1` |
| OpenSCAP exit code 2 | Expected on first scan — failures found, not an Ansible error |
| Apache not reachable | Check firewalld: `firewall-cmd --list-services` |
| Collection not found | Run `ansible-galaxy collection install -r requirements.yml` |

## References

- [Ansible RHEL Workshop Deck](https://labs.demoredhat.com/decks/ansible_rhel.pdf)
- [Ansible RHEL Workshop Exercises](https://labs.demoredhat.com/exercises/ansible_rhel/)
- [OpenSCAP RHEL 8 Guide](https://www.redhat.com/en/blog/openscap-rhel8)
- [Ansible Automation Platform Docs](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform)
