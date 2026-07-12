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
| AAP Gateway (UI) | `https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com` |
| AAP Controller API | `https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com` |
| OpenShift Console | `https://console-openshift-console.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com` |
| OpenShift API | `https://api.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com:6443` |
| Bastion SSH | `ssh lab-user@bastion.jmvv9.sandbox3400.opentlc.com` |
| Admin / bastion password | `<admin-password>` (see lab environment — **never commit**) |
| Controller API token | `<controller-token>` (see lab environment — **never commit**) |
| Git repository | `https://github.com/ronamalka/ansible_for_rhel` |
| Inventory | Workshop Inventory (Controller) / `inventories/workshop/hosts` (CLI) |
| Bastion SSH key for RHEL hosts | `~/.ssh/jmvv9key.pem` |

### Target RHEL Hosts

| Host | FQDN | Group | Stage |
|------|------|-------|-------|
| node1 | `node1.example.com` | web | dev |
| node2 | `node2.example.com` | web | prod |
| node3 | `node3.example.com` | web | dev |

All hosts run **RHEL 8.7**. Managed user: `ec2-user` with key `~/.ssh/jmvv9key.pem` on the bastion.

> **OpenTLC note:** The full AAP + OpenShift lab (`jmvv9`) ships controller, EDA, and OpenShift — but **RHEL target VMs are not pre-provisioned** in this sandbox type. DNS for `node*.example.com` does not resolve until separate RHEL nodes are added or `/etc/hosts` entries are configured. Job templates launch and connect with the Workshop Credential; jobs fail at SSH until targets exist.

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
│   ├── setup-rhel-demo-environment.sh # Bootstrap project/templates on fresh AAP
│   ├── deploy-self-service-portal.sh  # OpenShift portal secrets + Helm prep
│   ├── demo-template-metadata.json    # Template descriptions for portal
│   └── patch-rhel-survey.json
└── monitoring/
    └── automation-dashboard.md        # Dashboard demo script
```

## Quick Start (CLI on Bastion)

### 1. Copy the demo to the bastion

```bash
scp -r ansible_for_rhel/ lab-user@bastion.jmvv9.sandbox3400.opentlc.com:~/
```

### 2. SSH to the bastion

```bash
ssh lab-user@bastion.jmvv9.sandbox3400.opentlc.com
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
ansible-playbook playbooks/openscap_remediate.yml --limit node2
```

**What happens:**
1. Runs `oscap xccdf eval --remediate` against the demo tailored CIS profile (auto-remediable controls only)
2. Parses and displays compliance scores before and after remediation
3. Re-scans to produce a post-remediation comparison report (target: **100%** on demo profile)

**Controller:** Launch **DEMO - OpenSCAP Remediate** with limit `node2`.

#### Demo mode vs full CIS (honest presentation)

| Mode | Profile | Typical score after remediate | Use when |
|------|---------|-------------------------------|----------|
| **Scan (template 12)** | Full CIS | ~97.4% | Show real-world CIS baseline; 11 rules need manual/disk changes |
| **Remediate (template 13)** | Demo tailored CIS | **100%** | Show automated remediation success on achievable controls |

The 11 full-CIS failures that do not change after remediate are structural or manual-only: separate `/home`, `/tmp`, `/var`, `/var/log`, `/var/log/audit`, `/var/tmp` partitions; GRUB password; root password policy; passwordless sudo (skipped for Ansible); SSH user allow-lists; SELinux daemon confinement.

For the strongest before/after story on the demo profile, reset sandbox VMs or use a host that has not yet been remediated. On an already-remediated host, the demo profile may already read 100% before remediate; the job output still shows the full CIS baseline (~97%) for context.

Disable demo mode (full CIS only):

```bash
ansible-playbook playbooks/openscap_remediate.yml -e openscap_demo_mode=false
```

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

### Initial Demo Setup Checklist (full AAP + OpenShift)

| Step | Action | Script / Doc |
|------|--------|--------------|
| 1 | SSH to bastion; confirm `oc` access and `jmvv9key.pem` | This guide, Environment |
| 2 | Bootstrap AAP (project, inventory, templates, RBAC) | `controller/setup-rhel-demo-environment.sh` |
| 3 | Provision or register RHEL target VMs (`node1`–`node3`) | OpenTLC lab guide / DNS or `/etc/hosts` |
| 4 | Verify Patch + Deploy job templates launch | Controller UI or API |
| 5 | Deploy self-service automation portal on OpenShift | `controller/deploy-self-service-portal.sh` |
| 6 | Update OAuth redirect URI after portal deploy | [self-service-setup.md](controller/self-service-setup.md) |
| 7 | Configure portal RBAC for demo-user | [self-service-setup.md](controller/self-service-setup.md) |
| 8 | Verify demo-user sees templates in portal | [self-service-setup.md](controller/self-service-setup.md) |

Legacy controller-only checklist (single VM sandboxes): see [job-templates.md](controller/job-templates.md).

### Self-Service Portal

Non-admin users can launch DEMO automations without full controller access.

| Mode | URL | Notes |
|------|-----|-------|
| AAP Gateway UI | `https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com` | Full AAP 2.5 (gateway + controller + EDA) |
| Controller templates | `https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/#/templates` | Direct controller route |
| Automation Portal | `https://<portal-route>/` | Deploy via OpenShift Helm (see self-service-setup.md) |

**Demo user:** `demo-user` / `<demo-user-password>` (set via `DEMO_USER_PASSWORD` during setup — not stored in Git)

```bash
export CONTROLLER="https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com"
export CONTROLLER_TOKEN='<controller-token>'
export DEMO_USER_PASSWORD='<demo-user-password>'
./controller/setup-rhel-demo-environment.sh
```

All six DEMO templates (patch, OpenSCAP scan/remediate, deploy, verify, and the full workflow pipeline) are exposed with Execute permission. See `controller/self-service-setup.md` for verification steps and automation portal deployment.

### Workflow Overview

```
Patch → OpenSCAP Scan → OpenSCAP Remediate → Deploy App → Verify
```

Launch as **DEMO - RHEL Operations Pipeline** for the full demo from the Controller UI.

### Existing Environment Resources (jmvv9 sandbox)

Configured on the OpenTLC full AAP + OpenShift lab:

| Resource | ID / details |
|----------|----------------|
| Project | **RHEL Demo Project** (id: 43) → GitHub repo |
| Inventory | **Workshop Inventory** (id: 34) — hosts node1, node2, node3 |
| Credential | **Workshop Credential** (id: 35) — `jmvv9key.pem` |
| Job templates | DEMO Patch (44), Scan (45), Remediate (46), Deploy (47), Verify (48) |
| Workflow | **DEMO - RHEL Operations Pipeline** (id: 49) |
| Self-service | demo-user with Execute on templates 44–49 |
| OAuth app | **Ansible Automation Portal** (id: 1) — update redirect URI after portal deploy |
| Automation Portal | **Not yet deployed** — requires Helm chart + `registry.redhat.io` access |

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
| `openscap_profile` | CIS | Full CIS SCAP profile (scan template) |
| `openscap_demo_mode` | `false` (scan), `true` (remediate playbook) | Use tailored auto-remediable CIS profile |
| `openscap_demo_profile` | `xccdf_org.ssgproject.content_profile_cis_workshop` | Tailored profile ID for demo mode |
| `openscap_show_cis_baseline` | `true` | When demo mode, also scan/report full CIS score |
| `openscap_reboot_after_remediate` | `false` | Reboot after remediate (some rules need it) |
| `stage` | `dev` (group), `prod` (node2) | Environment label for web content |
| `dev_content` | See group_vars | Development page body text |
| `prod_content` | See group_vars | Production page body text |

## Troubleshooting

### Sandbox recovery (OpenTLC)

If **OpenSCAP Remediate** ran on all `web` hosts before the skip rules were in Git, `ec2-user` may lose passwordless sudo (`sudo -n` fails; `/etc/sudoers.d/90-cloud-init-users` is gone). SSH from the bastion still works; Ansible jobs fail at **Gathering Facts** with `Missing sudo password`.

1. **Reset or rebuild** the sandbox RHEL VMs from the OpenTLC lab environment (no in-band recovery without root).
2. On the Controller, **sync** RHEL Demo Project (id 10) and confirm **Workshop Credential** (id 4) includes the bastion SSH private key.
3. Re-run demos with API/UI **limit** `node1` on templates 12–15 (`ask_limit_on_launch` enabled). For API launches use `{"limit": "node1"}` plus job tags `scan` / `remediate` where applicable.
4. Do not store lab passwords in Git; use the lab-provided credentials only on the bastion and Controller.


| Issue | Resolution |
|-------|------------|
| SSH connection refused | Verify `~/.ssh/jmvv9key.pem` on bastion; confirm RHEL VM DNS/hosts |
| Hostname not resolved (`node*.example.com`) | RHEL VMs not provisioned in this lab type — add targets or `/etc/hosts` |
| `Missing sudo password` on RHEL nodes | CIS remediate removed `/etc/sudoers.d/90-cloud-init-users`; restore VMs via **OpenTLC sandbox reset** (cannot be fixed over SSH without a root password). After reset, run OpenSCAP remediate with **limit `node1`** only; repo skips `sudo_remove_nopasswd`. |
| OpenSCAP timeout | Increase job template timeout to 3600s; use `--limit node1` |
| OpenSCAP exit code 2 | Expected on first scan — failures found, not an Ansible error |
| Apache not reachable | Check firewalld: `firewall-cmd --list-services` |
| Collection not found | Run `ansible-galaxy collection install -r requirements.yml` |

## References

- [Ansible RHEL Workshop Deck](https://labs.demoredhat.com/decks/ansible_rhel.pdf)
- [Ansible RHEL Workshop Exercises](https://labs.demoredhat.com/exercises/ansible_rhel/)
- [OpenSCAP RHEL 8 Guide](https://www.redhat.com/en/blog/openscap-rhel8)
- [Ansible Automation Platform Docs](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform)


See [cross-sandbox-connectivity.md](controller/cross-sandbox-connectivity.md) for legacy sandbox connectivity notes.
