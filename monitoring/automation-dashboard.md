# Automation Dashboard and Monitoring

Monitoring and observability for the RHEL Operations demo. For a **presenter-ready scene-by-scene script** tied to the 4mrmx sandbox and actual DEMO job IDs, see **[demo-narrative-first-environment.md](demo-narrative-first-environment.md)**.

## Controller-only vs full platform

| Environment | Primary UI | Automation Dashboard (ROI/analytics) |
|-------------|------------|--------------------------------------|
| **4mrmx** (controller VM, ~AAP 4.5.x) | Controller **Dashboard**, **Jobs**, **Activity Stream**, **Host Metrics** | Not included — use Jobs/Dashboard for observability |
| **jmvv9** (full AAP 2.5+ on OpenShift) | AAP Gateway + controller route | **Not enabled** on current lab (AAP 2.5.3; catalog lacks 2.7). See [demo-narrative-jmvv9-automation-dashboard.md](demo-narrative-jmvv9-automation-dashboard.md) |

The standalone [Automation Dashboard utility](https://access.redhat.com/articles/7136383) (AAP 2.6+) is a separate install that syncs from Controller API. Do not expect **Views → Automation Dashboard** on the legacy 4mrmx controller-only sandbox.

## Automation Dashboard & Analytics (jmvv9 — product, not Controller Jobs)

**Status (2026-07-12):** jmvv9 runs **AAP 2.5.3**. Native Automation Dashboard requires **AAP 2.7+** with metrics service (`FEATURE_DASHBOARD_COLLECTION_ENABLED: true`). The OpenTLC lab catalog only exposes operator channels through **stable-2.5**, so in-cluster upgrade to 2.7 is blocked. Gateway `/api/metrics/v1/dashboard_reports/` returns **404**.

**Paths to enable:**

| Path | Requirement |
|------|-------------|
| Native (2.7+) | Operator channel `stable-2.7`, metrics enabled on `AnsibleAutomationPlatform` CR, dashboard via Gateway |
| Standalone utility | RHEL 9 host (bastion qualifies) + Customer Portal installer bundle + Gateway OAuth app |

**Presenter narrative:** [demo-narrative-jmvv9-automation-dashboard.md](demo-narrative-jmvv9-automation-dashboard.md)

**Target URLs when enabled:**

- Native: `https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com` → Automation Dashboard
- API: `.../api/metrics/v1/dashboard_reports/report/?period=last_90_days`
- Standalone: `https://<dashboard-host>:8447/`

## Controller Dashboard (4mrmx and all Controller installs)

### Access

1. Log in: `https://ansible-1.4mrmx.sandbox3261.opentlc.com` (admin — lab password, never commit)
2. Open **Dashboard** (home) or **Views → Dashboard**

### Demo talking points

| Dashboard area | What to show |
|----------------|--------------|
| Job Status chart | Successful vs failed job runs after the workflow |
| Recent Jobs | Timeline: Patch → Scan → Remediate → Deploy → Verify |
| Recent Templates | DEMO templates 11–16 after repeated runs |

### Before/after comparison

1. Note dashboard metrics **before** launching the workflow
2. Launch **DEMO - RHEL Operations Pipeline** (template 16)
3. Refresh the dashboard and highlight new job count and success/failure mix

## Per-job monitoring

Each job template execution provides detailed monitoring on the job detail page.

| Section | Demo value |
|---------|------------|
| **Details** | Inventory, project, playbook, credential name, SCM revision, survey/extra vars |
| **Stdout** | Live playbook output — expand per-host; search for scores and exit codes |
| **Timing** | Task-level duration (OpenSCAP scan/remediate) |
| **Facts** | Host facts where gathered |

### Key metrics (OpenSCAP)

```
Job: DEMO - OpenSCAP Scan
├── Duration: ~5–15 min per host (CIS profile)
├── Exit code 2: failures found (expected on first scan — not an Ansible error)
├── Host breakdown: node1, node2, node3
└── Artifacts: /var/log/ansible-demo/openscap/
```

## Host-level artifacts

After OpenSCAP jobs complete, verify reports on managed hosts:

```bash
# From 4mrmx bastion or Controller ad hoc command
ls -la /var/log/ansible-demo/openscap/
```

| File | Purpose |
|------|---------|
| `{hostname}-report.html` | Human-readable compliance report |
| `{hostname}-results.xml` | Machine-readable results |
| `{hostname}-post-remediate-report.html` | Post-remediation comparison |

Copy an HTML report to the bastion for browser viewing:

```bash
scp -i ~/.ssh/4mrmxkey.pem ec2-user@node1.example.com:/var/log/ansible-demo/openscap/node1-report.html /tmp/
```

## API-based monitoring

Query job status programmatically (same data as the UI):

```bash
CONTROLLER="https://ansible-1.4mrmx.sandbox3261.opentlc.com"
export CONTROLLER_USER="${CONTROLLER_USER:-admin}"
export CONTROLLER_PASSWORD="${CONTROLLER_PASSWORD:?set CONTROLLER_PASSWORD}"
AUTH="${CONTROLLER_USER}:${CONTROLLER_PASSWORD}"

# Recent jobs
curl -sk -u "$AUTH" \
  "$CONTROLLER/api/v2/jobs/?order_by=-finished&page_size=10" \
  | python3 -m json.tool

# Job stdout
curl -sk -u "$AUTH" \
  "$CONTROLLER/api/v2/jobs/JOB_ID/stdout/?format=txt"

# Controller metrics (Prometheus format)
curl -sk -u "$AUTH" \
  "$CONTROLLER/api/v2/metrics/" \
  | python3 -m json.tool
```

### Useful API endpoints

| Endpoint | Data |
|----------|------|
| `/api/v2/jobs/` | Job history, status, duration |
| `/api/v2/job_events/` | Per-task events for a specific job |
| `/api/v2/metrics/` | Prometheus-style controller metrics |
| `/api/v2/workflow_jobs/` | Workflow execution history |
| `/api/v2/activity_stream/` | Audit trail of launches and config changes |

## Event-driven monitoring (stretch goal)

For advanced demos on full AAP installs:

- **Webhook notifications** — notify Slack/Teams on job failure
- **External monitoring** — scrape `/api/v2/metrics/` with Prometheus/Grafana
- **EDA rules** — react to job failure events (jmvv9)
- **Log aggregation** — forward job events to Splunk or ELK

## Demo script: monitoring segment

**Full narrative:** [demo-narrative-first-environment.md](demo-narrative-first-environment.md)

**Short checklist (~5–8 min):**

1. Controller Dashboard — baseline Job Status and Recent Jobs
2. Patch job — survey vars, package stdout, Timing
3. OpenSCAP Scan — Timing tab, exit code 2, compliance score in stdout
4. OpenSCAP Remediate (node2) — before/after scores
5. Deploy + Verify — changed tasks, HTTP 200 in stdout
6. Workflow job — visualizer graph and child job correlation
7. Activity Stream — filter by `demo-user` for RBAC audit
