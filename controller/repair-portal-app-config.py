#!/usr/bin/env python3
"""Remove duplicate catalog.providers.rhaap.production keys from portal app-config.yaml."""
from __future__ import annotations

import re
import sys
from pathlib import Path


def repair(text: str) -> tuple[str, bool]:
    block = re.search(
        r"(?ms)^(\s+)production:\n(\1\s+orgs:\n(?:\1\s+- .+\n)+)",
        text,
    )
    if not block:
        return text, False

    indent, orgs_block = block.group(1), block.group(0)
    if not re.search(rf"(?m)^{re.escape(indent)}'production':\s*$", text):
        return text, False

    text = text.replace(orgs_block, "", 1)
    text = text.replace(f"{indent}'production':", f"{indent}production:", 1)

    rhaap = re.search(r"(?ms)^  providers:\n    rhaap:\n(.*?)(?=^  rules:)", text)
    if not rhaap:
        raise ValueError("catalog.providers.rhaap section missing")
    if len(re.findall(r"^\s+production:\s*$", rhaap.group(1), re.M)) > 1:
        raise ValueError("duplicate production keys remain under catalog.providers.rhaap")

    return text, True


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
