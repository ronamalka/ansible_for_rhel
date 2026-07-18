# Ansible for RHEL — Operations Demo

End-to-end demonstration of managing Red Hat Enterprise Linux servers with Ansible and Ansible Automation Platform. Structured after the [Ansible for RHEL Workshop](https://labs.demoredhat.com/exercises/ansible_rhel/) labs.

## Demo Scope

| Capability | Status | Implementation |
|------------|--------|----------------|
| Deploying RHEL VMs | Out of scope | Pre-provisioned sandbox hosts |
| Patching machines | In scope | `playbooks/patch_rhel.yml` |
| OpenSCAP scan + remediation | In scope | `playbooks/openscap_scan.yml`, `openscap_remediate.yml` |
| Application deployment | In scope | `playbooks/deploy_application.yml` |
| OpenShift app deployment | In scope | `playbooks/deploy_openshift_app.yml`, `apps/demo-web/` |
| Monitoring / dashboard | In scope | `monitoring/demo-narrative-first-environment.md` (4mrmx), `monitoring/demo-narrative-jmvv9-automation-dashboard.md` (jmvv9 product), `monitoring/automation-dashboard.md` |

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
| Bastion automation SSH key | `~/.ssh/ansible_jmvv9_demo` (generated on bastion; pubkey on RHEL `authorized_keys`) |

### Target RHEL Hosts

| Host | FQDN | Group | Stage |
|------|------|-------|-------|
| node1 | `rhel9.4vkbf.sandbox1878.opentlc.com` | web | dev |
| node2 | `rhel9.gkmvw.sandbox5326.opentlc.com` | web | prod |
| node3 | *(not provisioned)* | — | — |

Both targets run **RHEL 9.6**. Managed user: `lab-user` with passwordless sudo. AAP **Workshop Credential** (id 35) uses the bastion automation key (`~/.ssh/ansible_jmvv9_demo`, not stored in Git). For ad-hoc runs from the bastion, use the same key path.

> **Two-host lab:** Inventory and AAP list `node1` and `node2` only. Add `node3` to `inventories/workshop/hosts` and the Controller inventory when a third RHEL VM is available.

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
│   ├── deploy_openshift_app.yml
│   ├── verify_application.yml
│   └── site.yml                       # Full CLI pipeline
├── apps/
│   └── demo-web/                      # Sample containerized Flask app for OpenShift
├── ocp/
│   └── tekton/                        # Tekton pipeline (build + deploy)
├── roles/
│   ├── rhel_patching/
│   ├── openscap/
│   ├── web_application/
│   └── openshift_app_deploy/
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
    ├── demo-narrative-first-environment.md  # Presenter script (4mrmx monitoring segment)
    └── automation-dashboard.md              # API, artifacts, dashboard reference
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
2. Runs CIS profile scan against RHEL 9 SCAP content (`ssg-rhel9-ds.xml`)
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
curl http://rhel9.4vkbf.sandbox1878.opentlc.com    # node1 dev content
curl http://rhel9.gkmvw.sandbox5326.opentlc.com    # node2 prod content
```

**Controller:** Launch **DEMO - Deploy Web Application** with survey for content customization.

### Phase 4b: OpenShift Application Deployment (~3-5 min)

**Story:** Deploy a containerized demo web app on OpenShift in a namespace chosen at launch time.

```bash
# Requires OpenShift API token and kubernetes.core collection
export host="https://api.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com:6443"
export oauth_token="<openshift-token>"
ansible-playbook playbooks/deploy_openshift_app.yml \
  -e target_namespace=demo-web-lab -e app_name=demo-web -e create_namespace=true
```

**What happens:**
1. Validates namespace name (DNS-1123)
2. Creates namespace when `create_namespace=true`
3. Uses Tekton pipeline when OpenShift Pipelines is installed; otherwise applies Deployment/Service/Route directly
4. Waits for Route and verifies `Hello from <namespace>` over HTTPS

**Route URL pattern:**

```
https://<app_name>-<target_namespace>.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/
```

**Controller:** Launch **DEMO - Deploy App on OpenShift** (Demo Inventory + OpenShift credential). See `controller/job-templates.md`.

### Phase 5: Verification (~1 min)

```bash
ansible-playbook playbooks/verify_application.yml
```

Confirms each host serves the expected content via the `uri` module.

### Phase 6: Monitoring (~8 min)

**4mrmx (controller-only):** [monitoring/demo-narrative-first-environment.md](monitoring/demo-narrative-first-environment.md) — Controller Dashboard, Jobs, Activity Stream, Host Metrics.

**jmvv9 (Automation Dashboard & Analytics product):** [monitoring/demo-narrative-jmvv9-automation-dashboard.md](monitoring/demo-narrative-jmvv9-automation-dashboard.md) — ROI/savings analytics via metrics service (AAP 2.7+) or standalone utility on RHEL 9. **Not enabled** on current jmvv9 lab (AAP 2.5.3; operator catalog capped at stable-2.5).

Reference [monitoring/automation-dashboard.md](monitoring/automation-dashboard.md) for API endpoints and artifacts.

| Segment | Environment | What to show |
|---------|-------------|--------------|
| Operational observability | 4mrmx or jmvv9 | Job Status, stdout, workflow visualizer, Activity Stream |
| Analytics / ROI | jmvv9 (when enabled) | Gateway → Automation Dashboard; `/api/metrics/v1/dashboard_reports/` |

> **Note:** Controller **Dashboard** (job graphs) ≠ **Automation Dashboard** (ROI analytics). The latter requires AAP 2.7 native metrics or the standalone dashboard utility ([solution guide](https://access.redhat.com/articles/7136383)).

## Automation Controller Setup

Detailed configuration is in:

- `controller/job-templates.md` — five job templates with surveys
- `controller/workflow-setup.md` — chained workflow visualizer
- `controller/self-service-setup.md` — self-service portal and demo-user RBAC

### Initial Demo Setup Checklist (full AAP + OpenShift)

| Step | Action | Script / Doc |
|------|--------|--------------|
| 1 | SSH to bastion; confirm `~/.ssh/ansible_jmvv9_demo` reaches node1/node2 | This guide, Environment |
| 2 | Bootstrap AAP (project, inventory, templates, RBAC) | `controller/setup-rhel-demo-environment.sh` |
| 3 | *(done for jmvv9)* node1/node2 registered in AAP inventory 34 | This guide |
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
| Automation Portal | `https://redhat-rhaap-portal-rhaap-portal.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/` | Helm release `redhat-rhaap-portal` in `rhaap-portal` |
**Portal browser URL:** `https://redhat-rhaap-portal-rhaap-portal.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/` — requires `clusterRouterBase` with the `apps.` prefix (see [self-service-setup.md](controller/self-service-setup.md#browser-access-opentlc-jmvv9)).


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
Seed → Patch → OpenSCAP Scan → OpenSCAP Remediate → Deploy App → Verify
```

Launch as **DEMO - RHEL Operations Pipeline** for the full demo from the Controller UI. The workflow seeds host-specific downgrades before patching so `DEMO_PATCH_PORTAL` lines show per-node package names.

### Existing Environment Resources (jmvv9 sandbox)

Configured on the OpenTLC full AAP + OpenShift lab:

| Resource | ID / details |
|----------|----------------|
| Project | **RHEL Demo Project** (id: 43) → GitHub repo |
| Inventory | **Workshop Inventory** (id: 34) — hosts node1, node2 (`ansible_host` = OpenTLC FQDNs) |
| Credential | **Workshop Credential** (id: 35) — `lab-user` + bastion automation private key |
| Job templates | DEMO Seed (50), Patch (44), Scan (45), Remediate (46), Deploy (47), Verify (48), **OpenShift Deploy** |
| Workflow | **DEMO - RHEL Operations Pipeline** (id: 49) — Seed → Patch → … |
| Self-service | demo-user with Execute on templates 44–50 and workflow 49 |
| OAuth app | **Ansible Automation Portal** (id: 1) — redirect URI set to portal route |
| Automation Portal | **Deployed** — `redhat-rhaap-portal` v2.2.0 in `rhaap-portal` namespace |
| Automation Dashboard | **Not enabled** — AAP 2.5.3; see [monitoring/demo-narrative-jmvv9-automation-dashboard.md](monitoring/demo-narrative-jmvv9-automation-dashboard.md) |

## Patch demo: seeded pending updates (automated)

When RHEL nodes are fully patched, **DEMO Patch** (template 44) reports `packages=none`. For live demos, pending updates are created by downgrading **different** packages on each web host. **Do not downgrade `httpd`** — the web app demo must keep serving.

| Host | Inventory name | FQDN | Seeded packages (installed → pending upgrade) |
|------|----------------|------|-----------------------------------------------|
| node1 | `node1` | `rhel9.4vkbf.sandbox1878.opentlc.com` | `curl`, `tar` (`vim-minimal` optional) |
| node2 | `node2` | `rhel9.gkmvw.sandbox5326.opentlc.com` | `sudo`, `gzip` |

Package versions and NEVRAs live in `inventories/workshop/host_vars/node1.yml` and `node2.yml`. The `demo_patch_seed` role downgrades only when a package is **not** already in `dnf list updates` (idempotent re-runs).

### Trigger from Controller or portal

| Goal | How |
|------|-----|
| Full pipeline with seed | Launch workflow **49** — seed runs as the first node |
| Patch only, re-seed first | Launch template **44**, survey **Prepare demo updates first?** = `true` |
| Seed only (between demos) | Launch template **DEMO - Seed Patch Demo Packages** |

Job stdout includes `DEMO_PATCH_SEED` marker lines and a `DEMO PATCH SEED SUMMARY (portal)` block. After seeding, launch patch (or the workflow) and confirm `DEMO_PATCH_PORTAL` lines list the expected packages.

**Controller API** (after `git push` and project sync):

```bash
export CONTROLLER_TOKEN='<controller-token>'
./controller/configure-demo-seed-template.sh
./controller/sync-demo-project.sh
```

**Verified (2026-07-12):** Manual downgrades produced node1 pending **2** (`curl`, `tar`) and node2 pending **2** (`gzip`, `sudo`); patch job stdout showed matching `DEMO_PATCH_PORTAL` lines. Automated seeding replaces bastion `dnf downgrade` commands.

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
| `seed_demo_packages` | `false` | Run `demo_patch_seed` before patch (patch template survey) |
| `demo_patch_seed_packages` | per host_vars | NEVRAs to downgrade for patch demo seeding |
| `openscap_profile` | CIS | Full CIS SCAP profile (scan template) |
| `openscap_demo_mode` | `false` (scan), `true` (remediate playbook) | Use tailored auto-remediable CIS profile |
| `openscap_demo_profile` | `xccdf_org.ssgproject.content_profile_cis_workshop` | Tailored profile ID for demo mode |
| `openscap_show_cis_baseline` | `true` | When demo mode, also scan/report full CIS score |
| `openscap_reboot_after_remediate` | `false` | Reboot after remediate (some rules need it) |
| `stage` | `dev` (group), `prod` (node2) | Environment label for web content |
| `dev_content` | See group_vars | Development page body text |
| `prod_content` | See group_vars | Production page body text |
| `target_namespace` | `demo-web` | OpenShift namespace (OpenShift deploy survey) |
| `app_name` | `demo-web` | OpenShift resource name (OpenShift deploy survey) |
| `create_namespace` | `true` | Create OpenShift namespace before deploy |
| `deploy_method` | `auto` | `auto`, `tekton`, or `direct` (playbook extra var) |

## Troubleshooting

### Sandbox recovery (OpenTLC)

If **OpenSCAP Remediate** ran on all `web` hosts before the skip rules were in Git, `lab-user` may lose passwordless sudo (`sudo -n` fails; `/etc/sudoers.d/90-cloud-init-users` is gone). SSH from the bastion still works; Ansible jobs fail at **Gathering Facts** with `Missing sudo password`.

1. **Reset or rebuild** the sandbox RHEL VMs from the OpenTLC lab environment (no in-band recovery without root).
2. On the Controller, **sync** RHEL Demo Project (id 10) and confirm **Workshop Credential** (id 4) includes the bastion SSH private key.
3. Re-run demos with API/UI **limit** `node1` on templates 12–15 (`ask_limit_on_launch` enabled). For API launches use `{"limit": "node1"}` plus job tags `scan` / `remediate` where applicable.
4. Do not store lab passwords in Git; use the lab-provided credentials only on the bastion and Controller.


| Issue | Resolution |
|-------|------------|
| SSH connection refused | Verify `~/.ssh/ansible_jmvv9_demo` on bastion; confirm OpenTLC FQDN resolves from bastion |
| Hostname not resolved (`node*.example.com`) | RHEL VMs not provisioned in this lab type — add targets or `/etc/hosts` |
| `Missing sudo password` on RHEL nodes | CIS remediate removed `/etc/sudoers.d/90-cloud-init-users`; restore VMs via **OpenTLC sandbox reset** (cannot be fixed over SSH without a root password). After reset, run OpenSCAP remediate with **limit `node1`** only; repo skips `sudo_remove_nopasswd`. |
| OpenSCAP timeout | Increase job template timeout to 3600s; use `--limit node1` |
| OpenSCAP exit code 2 | Expected on first scan — failures found, not an Ansible error |
| Apache not reachable | Check firewalld: `firewall-cmd --list-services` |
| Collection not found | Run `ansible-galaxy collection install -r requirements.yml` |

## References

- [Ansible RHEL Workshop Deck](https://labs.demoredhat.com/decks/ansible_rhel.pdf)
- [Ansible RHEL Workshop Exercises](https://labs.demoredhat.com/exercises/ansible_rhel/)
- [OpenSCAP RHEL 9 Guide](https://www.redhat.com/en/blog/openscap-rhel9)
- [Ansible Automation Platform Docs](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform)


See [cross-sandbox-connectivity.md](controller/cross-sandbox-connectivity.md) for legacy sandbox connectivity notes.
