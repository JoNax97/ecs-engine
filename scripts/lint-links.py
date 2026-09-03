#!/usr/bin/env python3
"""Check markdown cross-references in docs/ and .claude/.

Two kinds of reference are checked:

  markdown links     [text](File.md#anchor)  or  [text](#anchor)
  backtick citations `File.md#anchor`        or  `#anchor`

Reports dead anchors, dead file paths, duplicate anchors, and backtick
citations that name no file (those must be qualified, since a bare anchor
in a rationale file has no reliable owning document).

Fenced code blocks are ignored for headings and references alike.

Usage: python3 scripts/lint-links.py [dir ...]   (default: docs .claude)
Exit status is 1 if any problem was found.
"""

import re
import sys
from pathlib import Path
from urllib.parse import unquote

FENCE = re.compile(r"^\s*(```|~~~)")
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
LABEL = re.compile(r"^\*\*(.+?)\*\*")
LINK = re.compile(r"(?<!\!)\[[^\]]*\]\(\s*([^)\s]+)")
# A citation is a backtick span that is *only* a doc reference, so ordinary
# inline code containing a '#' is not mistaken for one.
CITATION = re.compile(r"`([A-Za-z0-9 %._-]*\.md#[\w-]+|#[\w-]+)`")
# Files whose backtick anchors are references rather than code.
CITES = re.compile(r"(^|[\\/])\.claude[\\/]")
INLINE = re.compile(r"`|\*\*|\*|__|_|~~")
EXTERNAL = re.compile(r"^(https?|mailto|ftp):", re.I)


def slugify(text):
    """GitHub's heading-to-anchor rule."""
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)  # links keep their text
    text = INLINE.sub("", text)
    text = text.strip().lower()
    text = re.sub(r"[^\w\s-]", "", text)
    # Each whitespace character becomes its own hyphen; runs are not collapsed,
    # so "Queries & Systems" -> "queries--systems".
    return re.sub(r"\s", "-", text)


def scan(path):
    """Return (anchors, duplicates, refs) for one file.

    anchors   -- set of resolvable slugs, including GitHub's -1/-2 suffixes
    duplicates-- list of (line, slug) whose base slug collided
    refs      -- list of (line, target, kind), kind in {"link", "citation"}
    """
    anchors, seen, duplicates, refs = set(), {}, [], []
    cites = bool(CITES.search(str(path)))
    in_fence = False
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        heading = HEADING.match(line)
        # In a rationale file a bold entry label is the addressable unit, so it
        # defines an anchor the same way a heading does. Such a line still
        # carries its own citations, so anchor registration does not end it.
        label = LABEL.match(line) if cites and not heading else None
        title = heading.group(2) if heading else (label.group(1) if label else None)
        if title is not None:
            base = slugify(title)
            if base:
                count = seen.get(base, 0)
                seen[base] = count + 1
                if count:
                    duplicates.append((lineno, base))
                anchors.add(base if count == 0 else f"{base}-{count}")
            if heading:
                continue
        for target in LINK.findall(line):
            if not EXTERNAL.match(target):
                refs.append((lineno, target, "link"))
        for target in CITATION.findall(line):
            refs.append((lineno, target, "citation"))
    return anchors, duplicates, refs


def main(argv):
    roots = [Path(a) for a in argv[1:]] or [Path("docs"), Path(".claude"), Path("CLAUDE.md")]
    files = sorted(
        {f for r in roots if r.is_dir() for f in r.rglob("*.md")}
        | {r for r in roots if r.is_file()}
    )
    if not files:
        print(f"no markdown files under {', '.join(str(r) for r in roots)}")
        return 1

    scanned = {f: scan(f) for f in files}
    by_name = {}
    for f in files:
        by_name.setdefault(f.name, []).append(f)

    def resolve(path, file_part):
        """Find the scanned file a reference names, or None."""
        dest = (path.parent / file_part).resolve()
        for f in files:
            if f.resolve() == dest:
                return f
        # A rationale file in .claude/ cites docs by bare name, not by a path
        # relative to itself; accept that when the name is unambiguous.
        candidates = by_name.get(Path(file_part).name, [])
        return candidates[0] if len(candidates) == 1 else None

    problems = []

    for path, (_, duplicates, _) in scanned.items():
        for lineno, slug in duplicates:
            problems.append(f"{path}:{lineno}: duplicate anchor '#{slug}'")

    for path, (_, _, refs) in scanned.items():
        for lineno, target, kind in refs:
            file_part, _, anchor = target.partition("#")
            file_part = unquote(file_part)
            if file_part:
                match = resolve(path, file_part)
                if match is None:
                    problems.append(f"{path}:{lineno}: dead path '{target}'")
                    continue
            elif kind == "citation" and not CITES.search(str(path)):
                # Outside the rationale files a bare backtick anchor is code,
                # not a reference — `#ifdef` is a preprocessor directive.
                continue
            elif kind == "citation" and anchor not in scanned[path][0]:
                # A bare citation inherited its document from context, which is
                # what let these drift; require the file to be named unless the
                # target is an entry in this same file.
                problems.append(f"{path}:{lineno}: unqualified citation '{target}'")
                continue
            else:
                match = path
            if anchor and anchor not in scanned[match][0]:
                problems.append(f"{path}:{lineno}: dead {kind} '{target}'")

    for problem in sorted(problems):
        print(problem)
    counts = {"link": 0, "citation": 0}
    for _, _, refs in scanned.values():
        for _, _, kind in refs:
            counts[kind] += 1
    print(
        f"\n{len(files)} files, {counts['link']} links, "
        f"{counts['citation']} citations, {len(problems)} problems",
        file=sys.stderr,
    )
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
