#!/usr/bin/env python3
"""Query .claude/internal-clauses.md by heading, citation, or body text.

Usage: python3 scripts/clause.py <pattern> [pattern ...]

Prints whole entries (### heading through next heading of same-or-higher
level) whose heading, citation line, or body matches any pattern
(case-insensitive substring). Entry boundary = a line starting with one or
more '#'.
"""
import re
import sys
from pathlib import Path

CLAUSES_PATH = Path(__file__).resolve().parent.parent / ".claude" / "internal-clauses.md"


def parse_entries(text: str):
    lines = text.splitlines()
    entries = []
    current = None
    for line in lines:
        if re.match(r"^#{2,6}\s", line):
            if current is not None:
                entries.append(current)
            current = [line]
        elif current is not None:
            current.append(line)
    if current is not None:
        entries.append(current)
    return entries


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    patterns = [p.lower() for p in sys.argv[1:]]
    text = CLAUSES_PATH.read_text()
    entries = parse_entries(text)

    matched = []
    for entry in entries:
        # only ### (decision-level) and deeper headings count as entries;
        # ## section headers alone (no body) are skipped as noise
        if not re.match(r"^#{3,6}\s", entry[0]):
            continue
        blob = "\n".join(entry).lower()
        if any(p in blob for p in patterns):
            matched.append(entry)

    if not matched:
        print(f"no entries matched: {', '.join(sys.argv[1:])}")
        sys.exit(1)

    print("\n\n".join("\n".join(e) for e in matched))
    print(f"\n---\n{len(matched)} entr{'y' if len(matched)==1 else 'ies'} matched", file=sys.stderr)


if __name__ == "__main__":
    main()
