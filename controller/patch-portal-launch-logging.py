#!/usr/bin/env python3
"""Patch rhaap:launch-job-template to stream DEMO job output into the scaffolder log.

The stock portal 2.2 action uses launchJobTemplateNoWait + status polling only.
This patch adds incremental stdout polling so DEMO_*_PORTAL marker lines and
summary blocks appear in the Create Task step log while the job runs.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

MARKER = "PORTAL_LAUNCH_STDOUT_STREAMING"

OLD_BLOCK = """        if (waitForCompletion) {
          jobResult = await ansibleServiceRef.launchJobTemplateNoWait(
            launchPayload,
            token
          );
          logger.info(
            `Waiting for result of the executed job template (job ID: ${jobResult.id}).`
          );
          const pollingToken = serviceToken || token;
          if (!serviceToken) {
            logger.warn(
              "ansible.rhaap.token not configured - falling back to user token for polling. Long-running jobs may fail due to token expiry."
            );
          }
          logger.debug(
            `Polling job ${jobResult.id} with ${serviceToken ? "service" : "user"} token`
          );
          const POLL_INTERVAL_MS = 5e3;
          const MAX_POLLS = 720;
          let pollCount = 0;
          let currentStatus = jobResult.status?.toLowerCase();
          while (currentStatus && !["successful", "failed", "error", "canceled"].includes(
            currentStatus
          )) {
            if (pollCount >= MAX_POLLS) {
              const error = new Error(
                `Job ${jobResult.id} polling timeout after ${MAX_POLLS * (POLL_INTERVAL_MS / 1e3)} seconds. Last status: ${currentStatus}`
              );
              logger.error(error.message);
              throw error;
            }
            await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
            pollCount++;
            const statusUpdate = await ansibleServiceRef.getJobStatus(
              jobResult.id,
              pollingToken
            );
            currentStatus = statusUpdate.status?.toLowerCase();
            logger.debug(`Job ${jobResult.id} status: ${currentStatus}`);
            jobResult = { ...jobResult, ...statusUpdate };
          }
          logger.info(
            `Job ${jobResult.id} completed with status: ${jobResult.status}`
          );
          logger.debug(
            `Polling completed after ${pollCount} polls (${pollCount * (POLL_INTERVAL_MS / 1e3)}s)`
          );
          ctx.output("data", jobResult);"""

NEW_BLOCK = f"""        if (waitForCompletion) {{
          // {MARKER}
          jobResult = await ansibleServiceRef.launchJobTemplateNoWait(
            launchPayload,
            token
          );
          logger.info(
            `Waiting for result of the executed job template (job ID: ${{jobResult.id}}).`
          );
          const pollingToken = serviceToken || token;
          if (!serviceToken) {{
            logger.warn(
              "ansible.rhaap.token not configured - falling back to user token for polling. Long-running jobs may fail due to token expiry."
            );
          }}
          const POLL_INTERVAL_MS = 5e3;
          const MAX_POLLS = 720;
          let pollCount = 0;
          let currentStatus = jobResult.status?.toLowerCase();
          let lastStdoutLen = 0;
          const loggedLines = new Set();
          const ansiRegex = /\\u001b\\[[0-9;]*m/g;
          const demoLineRegex = /DEMO_(PATCH|DEPLOY|VERIFY)_PORTAL|DEMO (PATCH|DEPLOY|VERIFY) SUMMARY|===== (END )?DEMO|PATCH SUMMARY:|DEPLOY SUMMARY:|VERIFY SUMMARY:/i;
          const logDemoLines = (chunk) => {{
            for (const rawLine of chunk.split("\\n")) {{
              const line = rawLine.replace(ansiRegex, "").trim();
              if (!line || !demoLineRegex.test(line) || loggedLines.has(line)) {{
                continue;
              }}
              loggedLines.add(line);
              logger.info(line);
            }}
          }};
          const streamStdout = async () => {{
            try {{
              const stdoutResponse = await ansibleServiceRef.executeGetRequest(
                `api/controller/v2/jobs/${{jobResult.id}}/stdout/?format=txt`,
                pollingToken
              );
              const stdoutText = await stdoutResponse.text();
              if (stdoutText.length > lastStdoutLen) {{
                logDemoLines(stdoutText.slice(lastStdoutLen));
                lastStdoutLen = stdoutText.length;
              }}
            }} catch (_stdoutErr) {{
              // stdout may be unavailable until the job starts producing output
            }}
          }};
          while (currentStatus && !["successful", "failed", "error", "canceled"].includes(
            currentStatus
          )) {{
            if (pollCount >= MAX_POLLS) {{
              const error = new Error(
                `Job ${{jobResult.id}} polling timeout after ${{MAX_POLLS * (POLL_INTERVAL_MS / 1e3)}} seconds. Last status: ${{currentStatus}}`
              );
              logger.error(error.message);
              throw error;
            }}
            await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
            pollCount++;
            await streamStdout();
            const statusUpdate = await ansibleServiceRef.getJobStatus(
              jobResult.id,
              pollingToken
            );
            currentStatus = statusUpdate.status?.toLowerCase();
            logger.info(`Job ${{jobResult.id}} status: ${{statusUpdate.status}}`);
            jobResult = {{ ...jobResult, ...statusUpdate }};
          }}
          await streamStdout();
          try {{
            const stdoutResponse = await ansibleServiceRef.executeGetRequest(
              `api/controller/v2/jobs/${{jobResult.id}}/stdout/?format=txt`,
              pollingToken
            );
            const stdoutText = await stdoutResponse.text();
            const messageRegex = /"msg":\\s*"([^"]+)"|"msg":\\s*\\[(.*?)\\]/gs;
            for (const match of stdoutText.matchAll(messageRegex)) {{
              if (match[1]) {{
                logDemoLines(match[1].replace(/\\\\n/g, "\\n"));
              }} else if (match[2]) {{
                for (const item of match[2].matchAll(/"([^"]+)"/g)) {{
                  logDemoLines(item[1]);
                }}
              }}
            }}
          }} catch (_finalStdoutErr) {{
            // best-effort final parse
          }}
          logger.info(
            `Job ${{jobResult.id}} completed with status: ${{jobResult.status}}`
          );
          ctx.output("data", jobResult);"""


def patch_file(path: Path) -> str:
    text = path.read_text()
    if MARKER in text:
        return "already_patched"
    if OLD_BLOCK not in text:
        raise ValueError(f"expected launch handler block not found in {path}")
    path.write_text(text.replace(OLD_BLOCK, NEW_BLOCK, 1))
    return "patched"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <aapLaunchJobTemplate.cjs.js>", file=sys.stderr)
        return 2
    result = patch_file(Path(sys.argv[1]))
    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
