# Automation Dashboard and Monitoring

This section covers how to demonstrate monitoring capabilities in Ansible Automation Platform during the RHEL demo.

## Automation Dashboard

The Automation Dashboard provides a high-level view of automation activity across your organization.

### Access

1. Log in to the controller: `https://ansible-1.4mrmx.sandbox3261.opentlc.com`
2. Navigate to **Views → Automation Dashboard** (or **Automation Dashboard** in the left navigation, depending on AAP version)

### Demo Talking Points

| Dashboard Area | What to Show |
|----------------|--------------|
| Job runs | Total successful/failed jobs after running the workflow |
| Most used templates | DEMO templates appearing after repeated runs |
| Recent jobs | Timeline of Patch → Scan → Remediate → Deploy → Verify |
| Host status | Success rate across node1, node2, node3 |

### Before/After Comparison

1. Note the dashboard metrics **before** launching the workflow
2. Launch `DEMO - RHEL Operations Pipeline`
3. Refresh the dashboard and highlight:
   - New job count
   - Duration trends
   - Success rate changes

## Per-Job Monitoring

Each job template execution provides detailed monitoring:

### Job Detail Page

| Section | Demo Value |
|---------|------------|
| **Details** | Shows inventory, project, playbook, credential, and SCM revision |
| **Jobs** | Child jobs for multi-host runs |
| **Stdout** | Live playbook output — expand per-host for task details |
| **Timing** | Task-level duration breakdown |

### Key Metrics to Highlight

```
Job: DEMO - OpenSCAP Scan
├── Duration: ~5-15 min per host (CIS profile)
├── Changed tasks: package install, oscap scan
├── Host breakdown: node1, node2, node3
└── Artifacts: reports at /var/log/ansible-demo/openscap/
```

## Host-Level Artifacts

After OpenSCAP jobs complete, verify reports on managed hosts:

```bash
# Ad hoc command via Controller or SSH
ls -la /var/log/ansible-demo/openscap/
```

Reports generated per host:

| File | Purpose |
|------|---------|
| `{hostname}-report.html` | Human-readable compliance report |
| `{hostname}-results.xml` | Machine-readable results |
| `{hostname}-post-remediate-report.html` | Post-remediation comparison |

To view HTML reports during a demo, copy one to the bastion:

```bash
scp ec2-user@node1.example.com:/var/log/ansible-demo/openscap/node1-report.html /tmp/
```

## API-Based Monitoring

Query job status programmatically:

```bash
CONTROLLER="https://ansible-1.4mrmx.sandbox3261.opentlc.com"
AUTH="admin:<REDACTED>"

# Recent jobs
curl -sk -u "$AUTH" \
  "$CONTROLLER/api/v2/jobs/?order_by=-finished&page_size=10" \
  | python3 -m json.tool

# Job metrics
curl -sk -u "$AUTH" \
  "$CONTROLLER/api/v2/metrics/" \
  | python3 -m json.tool
```

### Useful API Endpoints

| Endpoint | Data |
|----------|------|
| `/api/v2/jobs/` | Job history, status, duration |
| `/api/v2/job_events/` | Per-task events for a specific job |
| `/api/v2/metrics/` | Prometheus-style controller metrics |
| `/api/v2/workflow_jobs/` | Workflow execution history |

## Event-Driven Monitoring (Stretch Goal)

For advanced demos, mention integration options:

- **Webhook notifications** — notify Slack/Teams on job failure
- **External monitoring** — scrape `/api/v2/metrics/` with Prometheus/Grafana
- **Log aggregation** — forward job events to Splunk or ELK

These are not pre-configured in the sandbox but illustrate production patterns.

## Demo Script: Monitoring Segment (~5 minutes)

1. **Show Automation Dashboard** — baseline metrics
2. **Launch workflow** — narrate each phase
3. **Click into OpenSCAP Scan job** — show per-host stdout and timing
4. **Run ad hoc command** — `ls /var/log/ansible-demo/openscap/` on node1
5. **Return to dashboard** — show updated job counts
6. **Run Verify template** — show URI check output confirming app health
