# Free online job data sources, EU-27 - research behind the report

Question: for every EU member state, which job data sources (job vacancies and postings, and
official vacancy statistics) are available online for free, and on what terms? Same method as
`../eu-free-address-data-sources/`. Started 2026-11-28.

**State: see [STATUS.md](STATUS.md)** - per country, whether its research, its independent check
and its report section exist, with the check's verdict counts.

## Layout

| Path | What | Written by |
|---|---|---|
| `research/<CC>-<Name>.md`, `research/00-EU-wide.md` | First layer: what a researcher found, with what it could not confirm | one researcher per zone, one file per country as it goes |
| `check/<CC>-<Name>.md`, `check/00-EU-wide.md` | Second layer: an independent re-check, claim by claim, corrections listed at the top | one checker per zone |
| `report/<CC>-<Name>.md`, `report/00-EU-wide.md`, `report/INTRO.md` | The report's sections, written from research + check | one writer per zone |
| `briefs/` | The instructions each layer worked under | |
| `status.py` | Rebuilds STATUS.md | |
| `checkpoint.sh` | Rebuilds STATUS.md and commits this folder locally when something changed; never pushes | run after every step and every few minutes while a pass runs |
| `build_report.py` | Joins `report/` into `docs/eu-free-job-data-sources.md` | |

Zones: EU-wide (EURES, aggregators' APIs, applicant-tracking vendors' public feeds, remote-job
feeds, Eurostat, Cedefop); Nordics and Baltics (DK EE FI LT LV SE); Western Europe (BE FR IE LU NL);
Germany and Austria; Central Europe (CZ HU PL SI SK); Southwest Europe (ES IT MT PT); Southeast
Europe (BG CY GR HR RO).

## How to read a verdict

- CONFIRMED: the checker requested the source itself and saw it.
- CORRECTED / WRONG: the research was off; the right value is in the check file. The research
  files are left as written.
- UNVERIFIED: could not be checked (site refused the client, login or key needed, timeout).
  Nothing was bypassed: no accounts created, no keys requested, no spoofed headers, no TLS override.
- NOT DISPROVED: a negative claim ("no API", "no open dataset") that a search failed to disprove.
  Not proof of absence.

## Limits set on the work

- Job boards and vendors are read by a production system from the same public address, so every
  pass was held to three requests per host, one at a time, no paging.
- "Free" was judged from published terms and from what answers without an account. No key was
  requested, so anything behind a free key is described from its documentation only.
