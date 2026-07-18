#!/usr/bin/env python3
"""Add demo-self-service label filter to RHAAP job template catalog sync in app-config.yaml."""
from __future__ import annotations

import sys
from pathlib import Path

import re

FILTER_BLOCK = """            filters:
              labels:
                include:
                - demo-self-service
"""


def patch(text: str) -> tuple[str, bool]:
    if "filters:" in text and "demo-self-service" in text and "jobTemplates:" in text:
        # Already has a label include for job templates
        if re.search(r"jobTemplates:.*?filters:.*?demo-self-service", text, re.S):
            return text, False

    pattern = re.compile(
        r"(?m)^          jobTemplates:\n            enabled: true\n",
        re.MULTILINE,
    )
    if not pattern.search(text):
        raise ValueError("jobTemplates.enabled block not found in app-config")

    def repl(m: re.Match[str]) -> str:
        return m.group(0) + FILTER_BLOCK

    updated, count = pattern.subn(repl, text, count=1)
    if count != 1:
        raise ValueError("failed to insert jobTemplates label filter")
    return updated, True


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch-portal-catalog-filter.py <app-config.yaml>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    original = path.read_text()
    try:
        updated, changed = patch(original)
    except ValueError as exc:
        print(exc, file=sys.stderr)
        return 1
    if changed:
        path.write_text(updated)
        print("patched")
    else:
        print("unchanged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
