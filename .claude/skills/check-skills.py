#!/usr/bin/env python3
"""Fail CI when a skill would be silently dropped by Claude Code: missing or unparsable
frontmatter, a name that differs from its directory, or an empty/oversized description."""
import pathlib
import sys

import yaml

MAX_DESCRIPTION = 1024
root = pathlib.Path(__file__).resolve().parent
errors = []
for skill in sorted(root.glob("*/SKILL.md")):
    text = skill.read_text(encoding="utf-8")
    if not text.startswith("---\n") or "\n---\n" not in text[4:]:
        errors.append(f"{skill}: no frontmatter block")
        continue
    front = text[4:].split("\n---\n", 1)[0]
    try:
        meta = yaml.safe_load(front) or {}
    except yaml.YAMLError as e:
        errors.append(f"{skill}: frontmatter does not parse: {e}")
        continue
    name = meta.get("name")
    desc = meta.get("description")
    if name != skill.parent.name:
        errors.append(f"{skill}: name {name!r} != directory {skill.parent.name!r}")
    if not isinstance(desc, str) or not desc.strip():
        errors.append(f"{skill}: description missing")
    elif len(desc) > MAX_DESCRIPTION:
        errors.append(f"{skill}: description {len(desc)} chars > {MAX_DESCRIPTION}")
for e in errors:
    print(e)
print(f"checked {len(list(root.glob('*/SKILL.md')))} skills, {len(errors)} errors")
sys.exit(1 if errors else 0)
