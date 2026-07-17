#!/usr/bin/env python3
"""Validate the repository's portable Agent Skills without external packages."""

from __future__ import annotations

import re
import sys
from pathlib import Path

NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
ROOT = Path(__file__).resolve().parents[1]
SKILLS_ROOT = ROOT / "skills"


def parse_frontmatter(path: Path) -> tuple[dict[str, str], str]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        raise ValueError("SKILL.md must begin with YAML frontmatter")

    try:
        end = lines.index("---", 1)
    except ValueError as exc:
        raise ValueError("SKILL.md frontmatter is not closed") from exc

    fields: dict[str, str] = {}
    for line in lines[1:end]:
        if not line or line.startswith((" ", "\t", "#")):
            continue
        if ":" not in line:
            raise ValueError(f"invalid top-level frontmatter line: {line!r}")
        key, value = line.split(":", 1)
        fields[key.strip()] = value.strip().strip('"').strip("'")

    body = "\n".join(lines[end + 1 :]).strip()
    return fields, body


def validate_skill(path: Path) -> list[str]:
    errors: list[str] = []
    parent_name = path.parent.name

    try:
        fields, body = parse_frontmatter(path)
    except (OSError, UnicodeError, ValueError) as exc:
        return [str(exc)]

    name = fields.get("name", "")
    description = fields.get("description", "")

    if not name:
        errors.append("missing required frontmatter field: name")
    elif len(name) > 64:
        errors.append("name exceeds 64 characters")
    elif not NAME_RE.fullmatch(name):
        errors.append("name must contain only lowercase letters, digits, and single hyphens")
    elif name != parent_name:
        errors.append(f"name {name!r} must match parent directory {parent_name!r}")

    if not description:
        errors.append("missing required frontmatter field: description")
    elif len(description) > 1024:
        errors.append("description exceeds 1024 characters")

    if not body:
        errors.append("instruction body is empty")

    if len(path.read_text(encoding="utf-8").splitlines()) > 500:
        errors.append("SKILL.md exceeds the recommended 500-line limit")

    return errors


def main() -> int:
    if not SKILLS_ROOT.is_dir():
        print(f"ERROR: skills directory not found: {SKILLS_ROOT}", file=sys.stderr)
        return 1

    skill_files = sorted(SKILLS_ROOT.glob("*/SKILL.md"))
    if not skill_files:
        print("ERROR: no skills/*/SKILL.md files found", file=sys.stderr)
        return 1

    skill_dirs = sorted(path for path in SKILLS_ROOT.iterdir() if path.is_dir())
    missing = [path for path in skill_dirs if not (path / "SKILL.md").is_file()]

    failures = 0
    for directory in missing:
        failures += 1
        print(f"FAIL {directory.relative_to(ROOT)}: missing SKILL.md")

    names: set[str] = set()
    for skill_file in skill_files:
        errors = validate_skill(skill_file)
        try:
            fields, _ = parse_frontmatter(skill_file)
            name = fields.get("name", "")
        except ValueError:
            name = ""

        if name and name in names:
            errors.append(f"duplicate skill name: {name}")
        elif name:
            names.add(name)

        relative = skill_file.relative_to(ROOT)
        if errors:
            failures += 1
            print(f"FAIL {relative}")
            for error in errors:
                print(f"  - {error}")
        else:
            print(f"PASS {relative}")

    if failures:
        print(f"Skill validation failed: {failures} item(s)", file=sys.stderr)
        return 1

    print(f"Skill validation passed: {len(skill_files)} skill(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
