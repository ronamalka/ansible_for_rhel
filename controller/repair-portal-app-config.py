#!/usr/bin/env python3
"""Remove duplicate catalog.providers.rhaap.production keys from portal app-config.yaml."""
from __future__ import annotations

import re
import sys
from pathlib import Path


def repair(text: str) -> tuple[str, bool]:
    match = re.search(
        r"(?ms)(^catalog:\n.*?^  providers:\n    rhaap:\n)(.*?)(?=^  rules:)",
        text,
    )
    if not match:
        return text, False

    rhaap_body = match.group(2)
    if not re.search(r"(?m)^      'production':\s*$", rhaap_body):
        return text, False
    if not re.search(r"(?m)^      production:\s*$", rhaap_body):
        return text, False

    minimal = re.search(
        r"(?ms)^      production:\n        orgs:\n        - Default\n",
        rhaap_body,
    )
    if not minimal:
        return text, False

    new_rhaap = rhaap_body.replace(minimal.group(0), "", 1)
    new_rhaap = new_rhaap.replace("'production':", "production:", 1)
    new_text = text[: match.start(2)] + new_rhaap + text[match.end(2) :]

    if len(re.findall(r"(?m)^      production:\s*$", new_rhaap)) > 1:
        raise ValueError("duplicate production keys remain under catalog.providers.rhaap")

    return new_text, True


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: repair-portal-app-config.py <app-config.yaml>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    original = path.read_text()
    try:
        updated, changed = repair(original)
    except ValueError as exc:
        print(exc, file=sys.stderr)
        return 1
    if changed:
        path.write_text(updated)
        print("repaired")
    else:
        print("unchanged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
