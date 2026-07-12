# Demo Narrative: Automation Observability (4mrmx First Environment)

Presenter-ready walkthrough for the **monitoring segment** of the RHEL Operations demo. Uses the legacy OpenTLC controller-only sandbox where all DEMO jobs were run against live RHEL nodes.

| Resource | Value |
|----------|-------|
| Controller | `https://ansible-1.4mrmx.sandbox3261.opentlc.com` |
| Admin user | `admin` (lab password — **never commit**) |
| Bastion | `ssh student1@ansible-1.4mrmx.sandbox3261.opentlc.com` |
| RHEL hosts | `node1.example.com`, `node2.example.com`, `node3.example.com` |
| DEMO templates | 11 Patch, 12 Scan, 13 Remediate, 14 Deploy, 15 Verify, 16 Workflow |
| Self-service user | `demo-user` (Execute on templates 11–16, label `demo-self-service`) |

**Timing:** ~8–12 minutes as a standalone segment, or ~5 minutes woven into Phase 6 after the workflow completes.

---

## Story arc: why monitoring matters

Open with the problem your audience knows:

> *Before automation:* patching, compliance scans, and app deploys happen over SSH or change tickets. Success is a Slack message. Failure is discovered hours later. Auditors ask “who changed what, when, and with what approval?” — and the answer is spread across shell history and ticket comments.

Then pivot to the **after** picture this demo proves:

1. **Repeatability** — the same job template runs the same playbook, with the same credential and SCM revision, every time.
2. **Accountability** — every launch records *who* ran it, *when*, against *which inventory*, with *which extra vars/survey answers*.
3. **Compliance audit trail** — OpenSCAP jobs leave scores, exit codes, and artifact paths in stdout; workflow history shows the full patch → scan → remediate → deploy chain.
4. **Self-service governance** — `demo-user` can launch labeled templates without admin access; Activity Stream and job history still attribute actions to that user.

Close the arc:

> *Automation without observability is just faster chaos. The Controller turns every run into searchable, attributable evidence — the same data auditors and ops leads need, without extra tooling.*

---

## AAP 4.5.2 controller-only: what is (and is not) available

This sandbox runs **Automation Controller only** (VM install, ~AAP 4.5.x). Be precise with the audience:

| Capability | 4mrmx (controller-only) | Full AAP 2.5+ (jmvv9) |
|------------|-------------------------|------------------------|
| **Controller Dashboard** (Job Status graph, Recent Jobs, Recent Templates) | Yes — home screen after login | Yes — via Gateway or direct controller route |
| **Jobs / Workflow job history** | Yes | Yes |
| **Stdout, Timing, Facts per job** | Yes | Yes |
| **Workflow Visualizer** | Yes | Yes |
| **Activity Stream** | Yes | Yes |
| **Host Metrics** | Yes (Views → Host Metrics) | Yes |
| **Automation Dashboard** (ROI / org-wide analytics) | **No** — requires separate [Automation Dashboard utility](https://access.redhat.com/articles/7136383) (AAP 2.6+) or native dashboard + metrics service (AAP 2.7+) | Available when metrics service + dashboard collection enabled on platform install |
| **EDA / event-driven rules** | No | Yes (jmvv9) |
| **AAP Gateway unified UI** | No | Yes (jmvv9) |

**Presenter note:** Do not promise “Views → Automation Dashboard” on 4mrmx. Use the **Controller Dashboard** and **Jobs** views as the primary observability story; mention Automation Dashboard as the upgrade path on full platform installs.

---

## Navigation path (exact UI clicks)

Log in as `admin` at the controller URL. Navigation labels match Controller 4.x / AAP 2.4+ layout (left sidebar).

### Baseline — before narrating individual jobs

1. **Dashboard** (click logo or **Views → Dashboard**)
   - **Job Status** chart — filter time range (e.g. Last 30 days) and job types (Job Runs).
   - **Recent Jobs** panel — note count and mix of success/failed before your story.
   - **Recent Templates** — DEMO templates 11–16 should appear after repeated runs.

2. **Views → Jobs**
   - Sort by **Finished** (descending).
   - Use **Search** to filter: `job_template.name:DEMO` or template name fragments.
   - Point out columns: Status, Job type, Started, Finished, Launched by.

3. **Activity Stream** (clock icon, top-right, or **Views → Activity Stream**)
   - Filter by user `demo-user` vs `admin` to show RBAC attribution.
   - Filter by object type **Job Template** to see launches vs config changes.

### Per-template drill-down

4. **Templates** → open a DEMO template → **Jobs** tab (history for that template only).

5. Click any **Job** row → Job detail:
   - **Details** — inventory, project, playbook, credential *name* (not secret), SCM revision, extra vars, limit, labels.
   - **Stdout** — live/historical playbook output; expand hosts; use **Search** in stdout.
   - **Timing** — task-level duration (critical for OpenSCAP).
   - **Facts** — post-run facts where gathered.

6. **Workflow** — **Templates** → **DEMO - RHEL Operations Pipeline** (id 16) → **Visualizer** (before launch) or open a **Workflow Job** → graph view (during/after run).

### Optional deep cuts

7. **Views → Host Metrics** — automation frequency / per-host run data (if populated in your sandbox).

8. **Inventories → Workshop Inventory → Sources / Sync history** — inventory sync jobs as auditable events.

9. **Projects → RHEL Demo Project → Sync** — SCM revision pinned on each job’s Details tab.

---

## Scene-by-scene script (tied to DEMO jobs you ran)

Use **Jobs → Search** to find these by template name or job ID. IDs below are from the live demo session; re-run launches will create new IDs.

| Template | ID | Example job IDs (demo session) | Host limit (typical) |
|----------|-----|--------------------------------|----------------------|
| DEMO - Patch RHEL Servers | 11 | 9, 155 | `web` |
| DEMO - OpenSCAP Scan | 12 | 99, 36 | `web` or `node1` |
| DEMO - OpenSCAP Remediate | 13 | *(node2 run)* | `node2` |
| DEMO - Deploy Web Application | 14 | 155 | `web` |
| DEMO - Verify Web Application | 15 | *(after deploy)* | `web` |
| DEMO - RHEL Operations Pipeline | 16 | workflow job | `web` |

---

### Scene 1 — Patch (`DEMO - Patch RHEL Servers`, ~2 min)

**Navigate:** Jobs → filter `DEMO - Patch RHEL Servers` → open job **#9** or **#155**.

**Say:**

> “Operations didn’t SSH to three nodes individually. One template applied the same patching role everywhere — and the Controller captured exactly what happened.”

**Highlight on Details:**

- **Launched by** — admin vs demo-user (if re-run as self-service).
- **Inventory** — Workshop Inventory, limit `web`.
- **Survey / extra vars** — `security_only`, `reboot_after_patch` (Patch template 11 has survey enabled).
- **Credential** — Workshop Credential (name only).
- **Labels** — `demo-self-service` when configured.

**Highlight on Stdout** (per host):

- `Report pending package updates` — package names listed before apply.
- `Report patching summary` — security-only mode, reboot required flag, packages updated.

**Highlight on Timing:**

- Longest tasks: `Update all packages` / `Update security-related packages only`.
- Compare duration across node1/2/3 if job slicing or serial strategy differs.

**Host status:** Stdout host picker — all green for success; expand any failed host for unreachable/sudo errors.

---

### Scene 2 — OpenSCAP Scan (`DEMO - OpenSCAP Scan`, ~2 min)

**Navigate:** Jobs → open scan job **#99** or **#36**.

**Say:**

> “Compliance isn’t a PDF emailed once a quarter. Every scan is a recorded job with scores, exit codes, and artifact paths.”

**Highlight on Timing:**

- `Run OpenSCAP compliance scan` — often 5–15 minutes per host; show which host dominates duration.
- CIS profile evaluation is CPU/disk heavy — Timing tab proves why template timeout is 1800s.

**Highlight on Stdout:**

- `Display scan exit code summary` block:
  - Compliance score (~97% on full CIS first scan).
  - **Exit code: 2** — *failures found*, not an Ansible failure.
- Explain: `0` = pass, `1` = scanner error, `2` = findings (expected on first scan).

**Search stdout:** type `Exit code` or `Compliance score` to show searchable logs.

**Artifacts (call out paths, verify on bastion if time):**

```text
/var/log/ansible-demo/openscap/{hostname}-report.html
/var/log/ansible-demo/openscap/{hostname}-results.xml
```

---

### Scene 3 — OpenSCAP Remediate on node2 (`DEMO - OpenSCAP Remediate`, ~2 min)

**Navigate:** Jobs → Remediate template → job with **Limit: node2**.

**Say:**

> “Remediation is automated, but we still need proof of before/after for auditors. Demo mode shows full CIS baseline plus tailored profile scores in one stdout paper trail.”

**Highlight on Stdout:**

- **Before:** demo profile score and full CIS baseline (~97.4%).
- **After remediate:** demo profile **100%** (tailored auto-remediable controls).
- Post-remediation report path: `{hostname}-post-remediate-report.html`.

**Teaching moment (node1 sudo story):**

If a prior remediate run hit **node1** without skip rules, jobs fail at **Gathering Facts** with `Missing sudo password`. Show:

- Workflow or job graph — failed node vs successful siblings.
- Stdout on failed host — sudo/become error.
- **Correlation:** one compliance job broke automation identity on that host; monitoring surfaced it immediately, not at next month’s patch window.

**Recovery narrative:** reset sandbox VMs or limit remediate to `node2` only; repo skips `sudo_remove_nopasswd` — see README troubleshooting.

---

### Scene 4 — Deploy + Verify (~2 min)

**Deploy — Navigate:** Jobs → `DEMO - Deploy Web Application` (e.g. job **#155** if that was deploy in your session; confirm template name on Details).

**Highlight:**

- **Changed** tasks in stdout: `Install httpd`, firewalld, template deploy.
- **Extra vars / survey** — `dev_content`, `prod_content` visible on Details.
- **Details → SCM revision** — Git commit proves which playbook version ran.

**Verify — Navigate:** latest `DEMO - Verify Web Application` job.

**Highlight on Stdout:**

- `Check HTTP response from each host` — `status_code: 200`.
- `Display page content` — truncated page body proves stage-specific content (dev vs prod on node2).

**Say:**

> “Deploy and verify are separate jobs in the workflow — so a green deploy with a broken HTTP endpoint still fails the pipeline at verify, with URI module evidence in stdout.”

---

### Scene 5 — Workflow pipeline (`DEMO - RHEL Operations Pipeline`, template 16, ~2 min)

**Navigate:** Jobs → type **Workflow Job** → open latest workflow run OR Templates → template 16 → Launch → Visualizer (preview) then open completed workflow job.

**Say:**

> “This is the full ops story in one audit record: patch, scan, remediate, deploy, verify — with failure boundaries between stages.”

**Highlight:**

- **Visualizer graph** — five nodes, On Success edges.
- **Click each node** — jumps to child job stdout/timing without losing workflow context.
- **Failure correlation** — if node1 failed at remediate, downstream deploy/verify may not run; graph shows skipped vs failed.
- **Job slicing** — each stage is a separate job ID in history (independent retry/relaunch).

**Dashboard callback:** Return to **Dashboard → Recent Jobs** — workflow + child jobs appear in timeline; Job Status chart increments.

---

## What to highlight for the audience

| Theme | Where to show it |
|-------|------------------|
| **Job history** | Views → Jobs; template **Jobs** tab |
| **Stdout search** | Job → Stdout → Search (`Exit code`, `Compliance score`, `status_code`) |
| **Timing tab** | OpenSCAP scan/remediate — task duration per host |
| **Facts** | Post-patch or post-deploy facts (where gathered) |
| **Inventory sync** | Inventories → Sources → sync jobs in Activity Stream |
| **Credential usage** | Job Details → Credentials section (names/types, never reveal secrets) |
| **Labels** | `demo-self-service` on templates — portal/RBAC filtering |
| **RBAC audit** | Activity Stream filtered by `demo-user`; job **Launched by** column |
| **SCM revision** | Job Details — reproducible playbook version |
| **Success rate / volume** | Dashboard Job Status chart; count successful vs failed in Jobs list |
| **Most-used templates** | Dashboard Recent Templates; sort Jobs by template |

---

## Screens and metrics to call out

On **Controller Dashboard** (4mrmx):

1. **Job Status** — success vs failed over selected period; narrow to **Job Runs** after DEMO day.
2. **Recent Jobs** — Patch → Scan → Remediate → Deploy → Verify ordering.
3. **Recent Templates** — DEMO templates rise after repeated presenter runs.

On **Jobs** list:

- Filter failed jobs — tie to OpenSCAP exit 2 vs real failures (unreachable, sudo).
- **Elapsed time** column — compare patch (~minutes) vs scan (~tens of minutes).

On **Host Metrics** (if enabled):

- Hosts with most automation runs — node1/2/3 after full workflow.

**Do not fabricate ROI/cost metrics** on controller-only — that is Automation Dashboard / metrics service territory.

---

## Talking points — Red Hat AAP value prop

- **Governance** — RBAC + job history + Activity Stream = who can run what, and who did run it.
- **Repeatability** — templates pin playbook, inventory, credentials, and EE; surveys standardize operator input.
- **Audit** — compliance scores, exit codes, and report paths in stdout; workflow jobs preserve stage order.
- **Operational resilience** — failure at one node or stage is isolated, visible, and relaunchable without rerunning the whole pipeline.
- **Path to enterprise** — same API/data model scales to full AAP (Gateway, EDA, Analytics/Automation Dashboard on 2.7+).

---

## Optional CLI / API correlation

Same data as the UI — useful for “integrate with SIEM/ticketing” closing slide.

```bash
CONTROLLER="https://ansible-1.4mrmx.sandbox3261.opentlc.com"
export CONTROLLER_USER="${CONTROLLER_USER:-admin}"
export CONTROLLER_PASSWORD="${CONTROLLER_PASSWORD:?set CONTROLLER_PASSWORD from lab — never commit}"
AUTH="${CONTROLLER_USER}:${CONTROLLER_PASSWORD}"
```

**Recent jobs (matches Jobs view):**

```bash
curl -sk -u "$AUTH" \
  "$CONTROLLER/api/v2/jobs/?order_by=-finished&page_size=10" \
  | python3 -m json.tool
```

**Specific job stdout events:**

```bash
JOB_ID=99   # OpenSCAP scan example
curl -sk -u "$AUTH" \
  "$CONTROLLER/api/v2/jobs/${JOB_ID}/stdout/?format=txt"
```

**Workflow job and nodes:**

```bash
curl -sk -u "$AUTH" \
  "$CONTROLLER/api/v2/workflow_jobs/?order_by=-finished&page_size=5" \
  | python3 -m json.tool
```

**Prometheus-style controller metrics:**

```bash
curl -sk -u "$AUTH" "$CONTROLLER/api/v2/metrics/"
```

**Activity / audit (template launches):**

```bash
curl -sk -u "$AUTH" \
  "$CONTROLLER/api/v2/activity_stream/?order_by=-timestamp&page_size=20" \
  | python3 -m json.tool
```

**On-controller CLI (admin SSH to ansible-1 bastion):**

```bash
sudo awx-manage list_instances
sudo awx-manage check_license
```

Use API tokens for automation integrations in production; basic auth is acceptable for lab demos only.

---

## Brief comparison: jmvv9 (new environment)

| Topic | 4mrmx (this narrative) | jmvv9 |
|-------|--------------------------|-------|
| **UI entry** | Controller URL directly | AAP Gateway + controller route |
| **RHEL targets** | node1–3 live in VPC | Not pre-provisioned — jobs fail at SSH until nodes exist |
| **Self-service** | Controller templates as `demo-user` | Gateway + optional Automation Portal on OpenShift |
| **EDA** | Not available | Event-Driven Ansible controller |
| **Analytics** | Controller Dashboard only | Metrics service + Automation Dashboard when enabled (2.7+) |
| **Template IDs** | 11–16 | 44–49 |

**Presenter transition:** “We ran the full story on 4mrmx where RHEL nodes exist. The jmvv9 sandbox shows the same templates and RBAC on modern AAP — plus Gateway and EDA — once RHEL VMs are registered in that VPC.”

See [cross-sandbox-connectivity.md](../controller/cross-sandbox-connectivity.md).

---

## Suggested flow (~8 minutes)

| Min | Action |
|-----|--------|
| 0–1 | Dashboard — Job Status + Recent Jobs baseline |
| 1–3 | Patch job — Details (survey), stdout package summary, Timing |
| 3–5 | OpenSCAP scan — Timing, exit code 2, score in stdout |
| 5–6 | Remediate node2 — before/after scores; optional node1 failure story |
| 6–7 | Deploy + Verify — changed tasks, HTTP 200 stdout |
| 7–8 | Workflow job graph → Dashboard refresh; Activity Stream as `demo-user` |

---

## Related docs

- [automation-dashboard.md](automation-dashboard.md) — API reference, artifacts, controller vs platform dashboard
- [../controller/workflow-setup.md](../controller/workflow-setup.md) — workflow visualizer setup
- [../controller/job-templates.md](../controller/job-templates.md) — template IDs and surveys
- [../controller/self-service-setup.md](../controller/self-service-setup.md) — demo-user RBAC and labels
