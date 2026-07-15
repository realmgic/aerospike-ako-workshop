#!/usr/bin/env python3
"""Validate relative markdown links resolve inside the workshop tree."""
from __future__ import annotations

import os
import re
import sys

WORKSHOP_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))


def iter_markdown_files(root: str):
    for dirpath, _, files in os.walk(root):
        for name in files:
            if name.endswith(".md"):
                yield os.path.join(dirpath, name)


def check_links() -> list[tuple[str, str, str]]:
    broken: list[tuple[str, str, str]] = []
    link_re = re.compile(r"\]\(([^)#]+)(#[^)]*)?\)")

    for path in iter_markdown_files(WORKSHOP_ROOT):
        text = open(path, encoding="utf-8").read()
        for match in link_re.finditer(text):
            target = match.group(1).strip()
            if target.startswith(("http://", "https://", "mailto:")):
                continue
            if target == "link":
                continue  # authoring placeholder in templates
            resolved = os.path.normpath(os.path.join(os.path.dirname(path), target))
            if not os.path.exists(resolved):
                rel = os.path.relpath(path, WORKSHOP_ROOT)
                broken.append((rel, target, os.path.relpath(resolved, WORKSHOP_ROOT)))

    return broken


def main() -> int:
    broken = check_links()
    if not broken:
        print("OK  all relative markdown links resolve under workshop/")
        return 0

    print("FAIL broken relative markdown links:", file=sys.stderr)
    for src, target, resolved in sorted(broken):
        print(f"  {src} -> {target} (missing: {resolved})", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
