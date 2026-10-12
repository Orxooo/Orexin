#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Orxooo
"""Extract literal Chinese UI strings for the macOS translation generator."""
import ast
import json
import re
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: extract-localization-keys.py OUTPUT.json")

source = Path(__file__).resolve().parent.parent / "Sources" / "WakeMac"
literal = re.compile(r'"(?:\\.|[^"\\])*"')
han = re.compile(r"[\u3400-\u9fff]")
keys = set()
for path in source.glob("*.swift"):
    for match in literal.finditer(path.read_text()):
        raw = match.group()
        if not han.search(raw) or r"\(" in raw:
            continue
        try:
            keys.add(ast.literal_eval(raw))
        except (SyntaxError, ValueError):
            keys.add(raw[1:-1])
Path(sys.argv[1]).write_text(json.dumps(sorted(keys), ensure_ascii=False) + "\n")
print(f"Extracted {len(keys)} keys")
