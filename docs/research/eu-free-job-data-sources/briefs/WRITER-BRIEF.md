# Brief for the per-country report sections

You are writing one part of a report that answers: **for every EU member state, which job data
sources are available online for free?** "Job data" means job vacancies and postings, and
secondarily official vacancy statistics. Readers: the operator who asked, and developers who will
build one vacancy import per country from it. They have not seen the research. They need to know,
per country, what can be read by a program at no cost, on what terms, and what is not there.

## Inputs

For each country you are given two files:
1. `research/<CC>-<Name>.md` - what a first researcher found.
2. `check/<CC>-<Name>.md` - a second reader's verdict on each claim, made by re-requesting the
   sources. Start with its "Corrections and unverified claims" list and its "Found beyond the
   research" list.

The check overrides the research. For the cross-border sources that also cover the country (EURES,
aggregators, vendors' feeds), read the two tables "Cross-border sources compared" and "Coverage by
country" in `report/00-EU-wide.md`, and nothing else from that file.

## Rules for every statement

- CONFIRMED claim: state it plainly.
- CORRECTED or WRONG claim: use the checked value only. Do not repeat the wrong one.
- UNVERIFIED claim: either leave it out or put it under "Could not be verified" with the reason.
  Never state it as fact elsewhere, never soften it into "reportedly".
- NOT DISPROVED (a negative such as "no API exists"): write "none found" and say where was
  searched. Do not write "does not exist".
- A claim in the research with no row in the check: treat as unverified.
- Something the check found beyond the research: use it, as confirmed.
- Terms of use are part of the answer. Where a site's terms or robots.txt forbid automated reading
  or reuse, say so in plain words and quote the clause; a source that answers a request but whose
  terms forbid reuse is NOT a free source.
- A source that needs a key: say whether the key is free and self-service, needs approval, or
  needs a contract, exactly as the inputs say. Nothing behind a key was tested; say "per its
  documentation" for what it returns.
- Every source gets its exact URL, copied from the inputs. Do not invent, shorten or "fix" a URL.
- Do not add knowledge of your own. If the inputs do not say it, it is not in the report.
- Do not make web requests. This is a writing task over the saved material.

## Output: one file per country, written as soon as that country is done

Write `report/<CC>-<Name>.md` (same `<CC>-<Name>` as the input files) with exactly this structure:

```
## <Name> (<CC>)

| Free machine-readable vacancies | Best free source | How to get it | Terms of reuse | Volume | Salary and full text | Update cycle |
|---|---|---|---|---|---|---|
| Yes / Partly / No | name | e.g. "JSON API, no key" | licence or terms in a few words | live vacancies, with whose figure | e.g. "full text yes, salary sometimes" | e.g. daily |

**In short.** Two to four sentences: what a developer should read, on what terms, and the one thing most likely to trip them up.

### Sources

| Source | Publisher | Link | What it holds | Access | Key or registration | Terms of reuse | Updated | Check |
|---|---|---|---|---|---|---|---|---|

### Commercial job boards

| Board | Link | Free feed or API for reading | What its terms say about automated reading and reuse | Check |
|---|---|---|---|---|

### Official vacancy statistics

### Caveats and recent changes

### Not free or not allowed

### Could not be verified
```

- The first table has exactly one data row; keep each cell under about 12 words and put no "|"
  inside a cell.
  - **Yes** = a national source publishes vacancies as a bulk file, API or feed that a program can
    read at no cost and whose terms allow reuse; a key counts only if it is free and self-service.
  - **Partly** = free but limited; name the limit in the next cell (key needs approval, one sector
    only, stale, terms silent or unclear on reuse, statistics but no adverts).
  - **No** = web pages only or reuse forbidden; nothing machine-readable and reusable found.
- "Check" column: confirmed / corrected / unverified / none found.
- Sources table: the public employment service first, then public-sector portals, open-data
  datasets, then the cross-border sources that cover the country.
- Bullets under the last four headings; write "None." under a heading with nothing to say.
- Plain English, short sentences, no filler, no first person, and no mention of "the research",
  "the researcher" or "the checker" - just what is known and how firmly. Where a figure was not
  recounted, call it "the publisher's figure" or "a first-pass count". Native names in their own
  language with an English gloss on first use.
- Write each country file as soon as that country is finished, before starting the next. No git
  commands, and no edits outside `report/`.

Final message: one line per country - the file written, the "Free machine-readable vacancies"
value, and anything in the inputs that was contradictory or that you could not place.
