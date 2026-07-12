# Demo Narrative: Automation Dashboard & Analytics (jmvv9)

Presenter-ready walkthrough for the **Automation Dashboard & Analytics** product on the OpenTLC full AAP + OpenShift lab (`jmvv9`). This is **not** the Controller Jobs/Activity Stream story from [demo-narrative-first-environment.md](demo-narrative-first-environment.md) — it targets ROI, savings, and usage analytics via the dedicated dashboard product.

| Resource | Value |
|----------|-------|
| AAP Gateway (UI) | `https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com` |
| Controller (direct) | `https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com` |
| Admin user | `admin` (lab password — **never commit**) |
| Bastion | `ssh lab-user@bastion.jmvv9.sandbox3400.opentlc.com` |
| Platform version | **AAP 2.5.3** (Controller 4.6.2) — operator channel `stable-2.5` |
| DEMO templates | 44 Patch, 45 Scan, 46 Remediate, 47 Deploy, 48 Verify, 49 Workflow |
| DEMO project | **RHEL Demo Project** (id: 43) |
| Self-service portal | `https://redhat-rhaap-portal-rhaap-portal.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com` (Helm deploy; OAuth redirect still required) |

**Timing:** ~10–15 minutes once Automation Dashboard is enabled and has collected data (6-hourly schedule on native 2.7; configurable sync on standalone utility).

---

## Environment status (2026-07-12)

| Check | Result |
|-------|--------|
| AAP operator / platform | `aap-operator.v2.5.0` → platform **2.5.3** |
| Metrics service pods | **Not deployed** — requires AAP **2.7+** |
| `FEATURE_DASHBOARD_COLLECTION_ENABLED` | **Not set** on `AnsibleAutomationPlatform/aap` CR |
| Gateway `/api/metrics/v1/dashboard_reports/` | **404** (metrics service absent) |
| Gateway services registered | gateway, controller, eda only |
| Operator upgrade to 2.7 | **Blocked** — lab catalog `olm-snapshot-redhat-catalog` (namespace `aap`) exposes channels **stable-2.4** and **stable-2.5** only |
| Standalone dashboard on bastion | **Not installed** — RHEL 9.7 bastion is suitable, but installer bundle not present |
| DEMO job history | **9+** jobs recorded (templates 44–47 launched; failures expected until RHEL VMs exist) |
| Self-service portal | Pod **Running** in `rhaap-portal`; route exists; TLS/cert may block external curl from some networks |

**Presenter honesty:** On this sandbox today, **Automation Dashboard & Analytics is not live**. Use this narrative for the *target* demo once enabled, and the **Interim segment** below for what you can show now.

---

## Product overview: two deployment models

Red Hat documents two ways to deliver Automation Dashboard & Analytics:

| Model | AAP versions | Where it runs | Gateway integration |
|-------|--------------|---------------|---------------------|
| **Native (2.7+)** | 2.7.0+ | Metrics service + dashboard UI inside platform | Unified Gateway navigation; API base `https://<gateway>/api/metrics/v1/dashboard_reports/` |
| **Standalone utility (2.6+)** | 2.4, 2.5, 2.6, 2.7 | Dedicated **RHEL 9** host (containerized); default HTTPS port **8447** | OAuth2 app on Gateway; dashboard pulls read-only data from Controller API |

Reference: [Automation Dashboard architecture (AAP 2.7)](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/whats_new-con_understand_automation_dashboard_architecture), [Standalone install (AAP 2.6)](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/install-assembly_view_key_metrics), [Solution guide](https://access.redhat.com/articles/7136383).

### Native 2.7 components

1. **Metrics service** — collects hourly metrics and (when flagged) dashboard ROI data every 6 hours from the Controller DB.
2. **Feature flag** — `FEATURE_DASHBOARD_COLLECTION_ENABLED: true` on the `AnsibleAutomationPlatform` CR.
3. **Gateway** — exposes dashboard UI and REST APIs under `/api/metrics/v1/dashboard_reports/`.
4. **Backfill** — up to 90 days of Controller job history when enabled post-install.

### Standalone utility components

1. **RHEL 9 host** — bastion in this lab qualifies (`RHEL 9.7`, Podman 5.6).
2. **Installer bundle** — `ansible-automation-dashboard-containerized-setup-bundle-*.tar.gz` from Red Hat Customer Portal.
3. **OAuth2 application** on Gateway (`/access/applications`) — client id `automation-dashboard`, authorization-code grant, redirect `https://<DASHBOARD_FQDN>/auth-callback`.
4. **Personal access token** on Gateway (`/access/tokens`) for `clusters.yaml` sync.
5. **Dashboard URL** — `https://<bastion-or-host>:8447/` (port configurable at install).

---

## Setup steps performed / required

### Attempted on jmvv9 (2026-07-12)

1. Inspected `aap` namespace — Gateway, Controller, EDA healthy; **no metrics** pods or routes.
2. Patched operator subscription to `stable-2.7` — **failed** (`ResolutionFailed`: channel not in lab catalog). Reverted to `stable-2.5`.
3. Launched DEMO jobs via API (templates 44, 45, 47) to seed Controller job history for future dashboard backfill.
4. Verified portal Helm release — `redhat-rhaap-portal` pod Running (does not block dashboard; separate product).

### Path A — Enable native dashboard (requires AAP 2.7 catalog)

When the cluster catalog includes `stable-2.7`:

```bash
# 1. Upgrade operator channel (cluster admin)
oc patch subscription ansible-automation-platform-operator -n aap \
  --type merge -p '{"spec":{"channel":"stable-2.7"}}'

# 2. Enable metrics + dashboard on the platform CR
oc edit AnsibleAutomationPlatform aap -n aap
```

Add under `spec:`:

```yaml
  feature_flags:
    FEATURE_DASHBOARD_COLLECTION_ENABLED: true
  metrics:
    disabled: false
    name: aap-metrics
```

Wait ~2 minutes for reconciliation. Confirm metrics pods and Gateway route. Dashboard API smoke test:

```bash
curl -sk -u "admin:<password>" \
  "https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/api/metrics/v1/dashboard_reports/report/?period=last_30_days"
```

Docs: [Enable dashboard post-install (2.7)](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/whats_new-task_enable_automation_dashboard_post_installation).

### Path B — Standalone dashboard on bastion (works with AAP 2.5)

On `bastion.jmvv9.sandbox3400.opentlc.com` (RHEL 9):

1. Download bundle from [Customer Portal](https://access.redhat.com/downloads/content/480).
2. Create OAuth app on Gateway → **Access Management → Applications** (`https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/access/applications`).
3. Create token → **Access Management → Tokens**.
4. Run `ansible.containerized_installer.dashboard_install` with inventory pointing at Gateway FQDN.
5. Open **`https://bastion.jmvv9.sandbox3400.opentlc.com:8447/`** (or configured host/port).

Ensure firewall allows **8447** ingress to the bastion and **443** egress from bastion to Gateway.

---

## Target URLs once enabled

| Surface | URL (jmvv9) |
|---------|-------------|
| **Native Automation Dashboard (2.7+)** | Gateway → left nav **Automation Dashboard** (or **Views → Automation Dashboard**) at `https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com` |
| Dashboard REST API | `https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/api/metrics/v1/dashboard_reports/` |
| Report summary | `.../report/details/?period=last_90_days` |
| **Standalone utility (2.5 lab)** | `https://<dashboard-host>:8447/` |
| Controller operational metrics (Prometheus) | `https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/api/v2/metrics/` (not ROI dashboard) |

---

## Scene-by-scene script (Automation Dashboard product)

Use after dashboard is enabled **and** at least one collection cycle has run (native: up to 6 hours after enable; backfill may take hours for 90-day history).

### Scene 0 — Open with the analytics gap (~1 min)

> *Controller tells you **what ran**. Automation Dashboard tells you **what automation is worth** — time saved, cost avoided, adoption by team, and which templates deliver the most ROI.*

Contrast with 4mrmx: there we used Job Status graphs and Activity Stream. Here we elevate to executive-friendly analytics.

### Scene 1 — Gateway login and navigation (~1 min)

1. Browse to **`https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com`**
2. Sign in as **`admin`**
3. **Native 2.7:** Left sidebar → **Automation Dashboard** (Technology Preview badge may appear)
4. **Standalone utility:** Open **`https://<dashboard-host>:8447/`** and sign in via OAuth (redirects through Gateway)

Confirm the page loads **Usage**, **Savings**, or **ROI** widgets — not the Controller “Job Status” pie chart.

### Scene 2 — Executive summary / report details (~2 min)

**Navigation (native):** Automation Dashboard → default landing / **Overview**

**API equivalent:**

```bash
export GATEWAY="https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com"
curl -sk -u "admin:<password>" \
  "${GATEWAY}/api/metrics/v1/dashboard_reports/report/details/?period=last_90_days"
```

**Call out:**

- Total jobs executed in period
- Aggregate **time saved** and **cost savings** (after subscription cost configuration)
- Top users and top projects charts

**Talk track:** “Leadership sees adoption trends without exporting CSVs from Controller.”

### Scene 3 — Filter to DEMO automations (~3 min)

**Navigation:** Dashboard filters → **Templates** or **Projects**

1. Filter **Project** → **RHEL Demo Project** (id 43)
2. Or filter **Template** → individual DEMO templates:
   - **DEMO - Patch RHEL Servers** (44)
   - **DEMO - OpenSCAP Scan** (45)
   - **DEMO - OpenSCAP Remediate** (46)
   - **DEMO - Deploy Web Application** (47)
   - **DEMO - Verify Web Application** (48)

**Presenter script per template type:**

| Template | Analytics story |
|----------|-----------------|
| **Patch (44)** | Repeatable patching volume; manual effort avoided vs SSH patching |
| **OpenSCAP Scan (45)** | Compliance automation frequency; audit-ready run count |
| **OpenSCAP Remediate (46)** | Remediation savings vs manual hardening |
| **Deploy (47)** | Application rollout automation; reduced change-window labor |
| **Verify (48)** | Quality-gate automation bundled with deploy pipeline |
| **Workflow (49)** | End-to-end pipeline — filter workflow job template if exposed in template list |

Set period to **Last 30 days** or **Last 90 days** to match executive reporting windows.

### Scene 4 — Cost and ROI configuration (~2 min)

**Navigation:** Automation Dashboard → **Settings** / **Cost configuration** (or **Subscription costs**)

Configure:

- Infrastructure cost per hour
- Currency
- Optional **template metadata** — manual effort minutes per run (feeds “time saved”)

**API:**

```bash
curl -sk -u "admin:<password>" \
  "${GATEWAY}/api/metrics/v1/dashboard_reports/subscription_costs/"
```

**Talk track:** “ROI is configurable — align costs with your cloud tariff or internal chargeback model.”

### Scene 5 — Export and share (~1 min)

**Navigation:** Report view → **Export PDF** or **Export CSV**

Mention BI tool ingestion for finance or GRC teams.

### Scene 6 — Tie back to operational evidence (~2 min)

Split screen or tab switch:

1. **Automation Dashboard** — aggregate savings for **DEMO - OpenSCAP Scan**
2. **Gateway → Automation Execution → Jobs** → open the same template’s latest job → **Stdout** / **Timing**

> *Analytics proves value; Controller proves execution. Together they satisfy ops and audit.*

Optional: **Gateway → Activity Stream** — who launched DEMO jobs (`admin` vs `demo-user`).

---

## Interim segment (AAP 2.5 — dashboard not yet enabled)

If Automation Dashboard cannot be installed before the session, show **what exists today** and name the gap:

1. **Gateway home** — `https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com`
2. **Automation Execution → Jobs** — filter `DEMO`; show jobs **23, 25, 26** (patch/scan/deploy launches)
3. **Automation Execution → Templates** — open template **44** → **Jobs** tab
4. **Controller Dashboard** (direct route) — `https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com/#/home` — Job Status chart (operational, not ROI)
5. State clearly: **Automation Dashboard & Analytics** requires Path A (2.7 upgrade) or Path B (standalone on RHEL 9)

Do **not** claim ROI numbers from Controller Job Status — that view lacks cost/savings analytics.

---

## Data prerequisites for a compelling demo

| Prerequisite | jmvv9 status | Action |
|--------------|--------------|--------|
| Job template executions | 9+ DEMO jobs | Re-launch 44–49 after RHEL nodes exist for successful runs |
| RHEL target hosts | **Missing** — `node*.example.com` unresolved | Provision VMs or `/etc/hosts` on bastion + EE |
| Dashboard collection | **Off** | Enable per Path A or B above |
| Collection window | 0 h (native) | Wait ≥1 collection cycle (6 h) or complete standalone sync |
| Subscription costs configured | N/A | Set in dashboard Settings before ROI scene |

Launch workflow for bulk history:

```bash
export CONTROLLER="https://aap-controller-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com"
export CONTROLLER_TOKEN="<token>"

# Patch — survey expects string booleans
curl -sk -X POST -H "Authorization: Bearer ${CONTROLLER_TOKEN}" -H "Content-Type: application/json" \
  -d '{"extra_vars":{"security_only":"false","reboot_after_patch":"false"}}' \
  "${CONTROLLER}/api/v2/job_templates/44/launch/"

# Full pipeline
curl -sk -X POST -H "Authorization: Bearer ${CONTROLLER_TOKEN}" -H "Content-Type: application/json" \
  -d '{}' "${CONTROLLER}/api/v2/workflow_job_templates/49/launch/"
```

---

## Comparison: observability products in this repo

| Product | 4mrmx narrative | jmvv9 Controller/Gateway | jmvv9 Automation Dashboard |
|---------|-----------------|--------------------------|----------------------------|
| Job stdout / timing | Yes | Yes | No (aggregate only) |
| Activity Stream / audit | Yes | Yes (Gateway) | No |
| ROI / cost / savings | No | No | **Yes** (when enabled) |
| Self-service portal | No | Yes (separate Helm) | No |

See also [demo-narrative-first-environment.md](demo-narrative-first-environment.md) and [automation-dashboard.md](automation-dashboard.md).

---

## Blockers and mitigations

| Blocker | Impact | Mitigation |
|---------|--------|------------|
| Lab catalog capped at AAP **2.5** | Cannot enable native metrics/dashboard via operator upgrade | Request 2.7 catalog snapshot, or use **standalone utility** on bastion |
| No dashboard installer bundle | Standalone path stalled | Download from Customer Portal with lab entitlement |
| No RHEL target VMs | DEMO jobs fail at SSH | Jobs still appear in Controller DB for backfill; operational stdout demo weak |
| Portal route TLS from some clients | Self-service segment unreliable | Use Controller templates for `demo-user`; fix OAuth redirect URI |
| 6-hourly collection (native 2.7 TP) | Dashboard empty immediately after enable | Pre-enable day before demo; or use standalone with manual sync |
| Technology Preview (2.7 native) | Not production SLA | Disclose TP status to audience |

---

## References

- [Red Hat Automation Dashboard & Analytics product page](https://www.redhat.com/en/technologies/management/ansible/automation-dashboard-analytics)
- [Understand automation dashboard architecture (2.7)](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/whats_new-con_understand_automation_dashboard_architecture)
- [Enable automation dashboard post-install (2.7)](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/whats_new-task_enable_automation_dashboard_post_installation)
- [Metrics service requirements (2.7)](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/install-ref_metrics_service_deployment_requirements)
- [Standalone dashboard install (2.6)](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/install-assembly_view_key_metrics)
- [Customer Portal solution guide](https://access.redhat.com/articles/7136383)
