#!/usr/bin/env python3
"""Assemble the per-country report from report/*.md.

Reads report/00-EU-wide.md and report/<CC>-<Name>.md (one per EU country), builds the overview
table from each country's one-row summary table, and writes the whole report to the paths given
on the command line (default: ../../eu-free-address-data-sources.md).

    python3 -I build_report.py [output.md ...]

Exits 1 and writes nothing if a country file is missing or its summary row cannot be read.
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PARTS = HERE / "report"
COUNTRIES = [
    ("AT", "Austria"), ("BE", "Belgium"), ("BG", "Bulgaria"), ("CY", "Cyprus"), ("CZ", "Czechia"),
    ("DE", "Germany"), ("DK", "Denmark"), ("EE", "Estonia"), ("ES", "Spain"), ("FI", "Finland"),
    ("FR", "France"), ("GR", "Greece"), ("HR", "Croatia"), ("HU", "Hungary"), ("IE", "Ireland"),
    ("IT", "Italy"), ("LT", "Lithuania"), ("LU", "Luxembourg"), ("LV", "Latvia"), ("MT", "Malta"),
    ("NL", "Netherlands"), ("PL", "Poland"), ("PT", "Portugal"), ("RO", "Romania"), ("SE", "Sweden"),
    ("SI", "Slovenia"), ("SK", "Slovakia"),
]
SUMMARY_COLUMNS = 7  # Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle


def summary_row(text):
    """The single data row of the first table in a country file, as a list of cells."""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.startswith("|") and i + 2 < len(lines) and set(lines[i + 1].replace("|", "").strip()) <= set("-: "):
            cells = [c.strip() for c in lines[i + 2].strip().strip("|").split("|")]
            return cells if len(cells) == SUMMARY_COLUMNS else None
    return None


def anchor(code, name):
    return f"{name.lower()}-{code.lower()}"


def main(outputs):
    problems, bodies, rows = [], [], []
    eu = PARTS / "00-EU-wide.md"
    if not eu.exists():
        problems.append("missing report/00-EU-wide.md")
    for code, name in sorted(COUNTRIES, key=lambda c: c[1]):
        path = PARTS / f"{code}-{name}.md"
        if not path.exists():
            problems.append(f"missing {path.name}")
            continue
        text = path.read_text(encoding="utf-8").strip()
        if not text.startswith(f"## {name} ({code})"):
            problems.append(f"{path.name}: does not start with '## {name} ({code})'")
        cells = summary_row(text)
        if cells is None:
            problems.append(f"{path.name}: summary table row not found or not {SUMMARY_COLUMNS} cells")
            continue
        rows.append(f"| [{name}](#{anchor(code, name)}) | " + " | ".join(cells) + " |")
        bodies.append(text)
    if problems:
        print("NOT BUILT:")
        for p in problems:
            print(" -", p)
        return 1

    counts = {"Yes": 0, "Partly": 0, "No": 0}
    for row in rows:
        first = row.split("|")[2].strip()
        for key in counts:
            if first.startswith(key):
                counts[key] += 1
    intro = (HERE / "report" / "INTRO.md").read_text(encoding="utf-8").strip()
    doc = [intro, "",
           "## Overview by country", "",
           f"Free national address data: {counts['Yes']} yes, {counts['Partly']} partly, {counts['No']} no "
           "(as each country section defines it).", "",
           "| Country | Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |",
           "|---|---|---|---|---|---|---|---|",
           *rows, "",
           eu.read_text(encoding="utf-8").strip(), "",
           "# Countries", ""]
    for body in bodies:
        doc += [body, ""]
    text = "\n".join(doc).rstrip("\n") + "\n"
    for out in outputs:
        out = Path(out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text, encoding="utf-8")
        print(f"wrote {out} ({len(text)} bytes, {len(bodies)} countries)")
    if sum(counts.values()) != len(rows):
        print("NOTE: some summary rows do not start with Yes / Partly / No")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or [HERE.parent.parent / "eu-free-address-data-sources.md"]))
