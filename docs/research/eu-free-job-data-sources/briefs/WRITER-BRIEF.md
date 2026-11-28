# Brief for the per-country report sections

You are writing one part of a report that answers: **for every EU member state, which job data
sources are available online for free - for one person's own job search and job applications?**
The reader is the person who asked, and developers of that person's own job-search tool: a program
that finds vacancies, reads them and prepares applications for that one person. The data is not
wanted for redistribution, publishing, resale, statistics or model training. They have not seen
the research. Per country they need to know what the program may read at no cost, on what terms,
and which boards are for manual use only.

## Inputs

For each country you are given two files:
1. `research/<CC>-<Name>.md` - what a first researcher found.
2. `check/<CC>-<Name>.md` - a second reader's verdict on each claim, made by re-requesting the
   sources. Start with its "Corrections and unverified claims" list, its table "For a personal job
   search and applications", and its "Found beyond the research" list.

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
- **Terms get one verdict per source: usable for own job search - yes / no / unclear.** Take it
  from the check's table "For a personal job search and applications" (older check files have
  several columns there: reduce them to the one verdict - "no" where automated reading is
  forbidden or the source is paid or partner-only, "unclear" where the terms are silent or unread,
  otherwise "yes"). Quote the deciding clause for a "no". A clause that only restricts
  redistribution or commercial reuse does not count against a source. No further analysis.
- A source that needs a key: say whether the key is free and self-service, needs approval, or
  needs a contract, exactly as the inputs say. Nothing behind a key was tested; say "per its
  documentation" for what it returns.
- Every source gets its exact URL, copied from the inputs. Do not invent, shorten or "fix" a URL.
- Do not add knowledge of your own, and give no legal advice: the report states what published
  terms say. If the inputs do not say it, it is not in the report.
- Leave vacancy statistics out; they do not serve this purpose.
- Do not copy any person's name, phone number or e-mail address from the inputs.
- Do not make web requests. This is a writing task over the saved material.

## Output: one file per country, written as soon as that country is done

Write `report/<CC>-<Name>.md` (same `<CC>-<Name>` as the input files) with exactly this structure:

```
## <Name> (<CC>)

| Readable by a program for own job search | Best source | How to read it | Terms in short | Live vacancies | Full text | Update cycle |
|---|---|---|---|---|---|---|
| Yes / Partly / No | name | e.g. "JSON API, no key" | e.g. "CC0" or "bots not mentioned" | number, with whose figure | yes / snippets / no | e.g. daily |

**In short.** Two to four sentences: what the tool should read, on what terms, and the one thing most likely to trip a developer up.

### Sources a program may read

| Source | Publisher | Link | What it holds | Access | Key or registration | Usable for own job search | Updated | Check |
|---|---|---|---|---|---|---|---|---|

### Job boards: what their terms say

| Board | Link | Feed or API for reading | Usable for own job search (why) | Check |
|---|---|---|---|---|

### Through the employers

| Company register free | Register and how to get it | Licence | Website or e-mail in the data | Activity codes |
|---|---|---|---|---|
| Yes / Partly / No | name; e.g. "bulk CSV and API, no key" | licence | e.g. "website and e-mail" or "neither" | e.g. "NACE, yes" |

- **Company register:** link, what is free and what is not, which fields, update cycle.
- **Where links to employers' own pages come from:** the free sources that carry them, or "none found".
- **Past adverts (which employers hire for which skills):** free archives of old adverts, with years, size, licence and whether they name the employer and the occupation or skills; or "none found".

| Applicant-tracking vendor | Public feed for an employer's board | Documentation | Check |
|---|---|---|---|

### Caveats and recent changes

### Not usable for this purpose

### Could not be verified
```

- The first table has exactly one data row; keep each cell under about 12 words and put no "|"
  inside a cell.
  - **Yes** = a source with broad national coverage can be read by a program at no cost (bulk
    file, API or feed; a key only if free and self-service) and its terms allow that, either by an
    open licence or in so many words.
  - **Partly** = readable at no cost but with a limit that matters here; name it in the next cell
    (key needs approval, one sector or region only, snippets without full text, terms silent on
    automated reading, copies may not be kept, stale).
  - **No** = web pages for manual use only: nothing a program may read was found, or the terms
    forbid automated reading.
- "Sources a program may read" holds only sources whose terms allow or do not forbid automated
  reading: the public employment service first, then public-sector portals, open-data datasets,
  then the cross-border sources that cover the country.
- "Job boards: what their terms say" lists the main commercial boards whatever their terms; it is
  where a reader sees which boards are for manual use only.
- "Not usable for this purpose": paid products, partner-only feeds, and sources whose terms forbid
  automated reading, each with the deciding clause.
- "Through the employers" is the second route: a list of companies, then each employer's own
  careers feed, with the application going straight to the employer. Write it from the inputs'
  section of the same name. If the inputs have none, write "Not researched." under the heading.
  A vendor counts as having a public feed only if its own documentation says so.
  Archives of past adverts are valuable here, not waste: they show which companies hire in a
  given skills area. Never describe one as useless for being old.
  Its first table has exactly one data row, short cells, no "|" inside a cell. Countries differ
  here, so state this country's facts and never what EU law requires in place of them:
  **Yes** = basic data on every company is free in bulk or by API without approval;
  **Partly** = free with a limit (one company per request, search only, a partial extract, a key
  that needs approval, a fee for bulk); **No** = paid or not published; "Not researched" if the
  inputs have no such section.
- "Check" column: confirmed / corrected / unverified / none found.
- Bullets under the last three headings; write "None." under a heading with nothing to say.
- Plain English, short sentences, no filler, no first person, and no mention of "the research",
  "the researcher" or "the checker" - just what is known and how firmly. Where a figure was not
  recounted, call it "the publisher's figure" or "a first-pass count". Native names in their own
  language with an English gloss on first use.
- Write each country file as soon as that country is finished, before starting the next. No git
  commands, and no edits outside `report/`.

Final message: one line per country - the file written, the "Readable by a program for own job
search" value, and anything in the inputs that was contradictory or that you could not place.
