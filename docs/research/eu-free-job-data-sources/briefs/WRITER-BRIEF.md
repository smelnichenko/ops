# Brief for the per-country report sections

You are writing one part of a report that answers: **for every EU member state, which job data
sources are available online for free - for one person's own job search and job applications?**
The reader is the person who asked, and developers of that person's own job-search tool: a program
that finds vacancies, reads them and prepares applications for that one person. The data is not
wanted for redistribution, publishing, resale, statistics or model training. They have not seen
the research. Per country they need to know what the program may read at no cost, on what terms,
how one applies, and which boards are for manual use only.

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
- **Terms are judged against the purpose, in four separate readings**, taken from the check's
  second table: job-seeker use; automated reading by a program; keeping a private copy; how one
  applies. A ban on bots or automated reading applies whatever the purpose: such a board is for
  manual use only, however openly it answers a request. A clause that only restricts
  redistribution, commercial reuse or resale does not block this purpose: mention it in a few
  words and do not count it against the source. "Not stated" stays "not stated"; do not turn
  silence into permission or into a ban. Quote the deciding clause.
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

| Readable by a program for own job search | Best source | How to read it | What its terms allow | Live vacancies | Full text and how to apply | Update cycle |
|---|---|---|---|---|---|---|
| Yes / Partly / No | name | e.g. "JSON API, no key" | e.g. "CC0" or "job search yes, bots not stated" | number, with whose figure | e.g. "full text; apply link to employer" | e.g. daily |

**In short.** Two to four sentences: what the tool should read, on what terms, how one applies, and the one thing most likely to trip a developer up.

### Sources a program may read

| Source | Publisher | Link | What it holds | Access | Key or registration | Terms for this purpose | How to apply | Updated | Check |
|---|---|---|---|---|---|---|---|---|---|

### Job boards: what their terms say

| Board | Link | Feed or API for reading | Automated reading under its terms | Private copy | How to apply | Check |
|---|---|---|---|---|---|---|

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
  then the cross-border sources that cover the country. "Terms for this purpose" gives the reading
  in a few words (for example "open licence CC0", "allowed with key, no forwarding", "not stated").
- "Job boards: what their terms say" lists the main commercial boards whatever their terms; it is
  where a reader sees which boards are for manual use only.
- "Not usable for this purpose": paid products, partner-only feeds, and sources whose terms forbid
  automated reading, each with the deciding clause.
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
