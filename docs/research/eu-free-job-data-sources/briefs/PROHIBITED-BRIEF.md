# Brief: the list of explicitly prohibited sources

The operator wants an exact exclude list: every source whose own published rules explicitly forbid
what a job-search program would do. One small file per country (and one for the EU-wide layer)
holds that country's rows; `exclude_list.py` merges them into `EXCLUDE-LIST.md` and
`exclude-list.tsv`.

## What goes in

A source goes in only when BOTH hold:
1. its own terms of use, API terms or robots.txt explicitly forbid automated reading (bots,
   crawlers, scripts, scraping, automated queries), or copying or extracting its content or
   database, or any use beyond manual browsing; and
2. the clause was read on the publisher's own page (or its robots.txt) and can be quoted.

## What stays out

- "Unclear": terms silent, unread, or not found.
- A technical refusal with no clause read (HTTP 403, a challenge page, a CAPTCHA, 429).
- Paid or partner-only data, closed services, dead hosts: unavailable, not prohibited.
- A clause that only restricts redistribution, resale or commercial reuse.
- A clause known only from a third party (a blog, another project's notes): not exact.
- A robots.txt rule that names only particular crawlers (ClaudeBot, GPTBot and the like): it does
  not bind the operator's own program. Mention it in the file's notes, not as a row.

A robots.txt rule counts when it applies to every agent (`User-agent: *`) and closes the whole
site or the addresses that hold the vacancies (search, list or advert pages). Say exactly which
addresses in "What is forbidden".

## File: `prohibited/<CC>-<Name>.md` (same `<CC>-<Name>` as the country's other files; `00-EU-wide` for cross-border sources)

```
# <Name> (<CC>) - explicitly prohibited sources

Status: checked
(or: Status: first pass - not yet independently checked)
Date: <date the clauses were read>

| Hosts | Source | What is forbidden | Clause (quoted) | Clause read at | Kind |
|---|---|---|---|---|---|
```

- **Hosts**: the host names the rule covers, lower case, no scheme, no path, comma-separated
  (for example `cvkeskus.ee, cvmarket.lv`). Take them from the clause where it names them, else
  the host whose terms were read. This column is what an exclude list is built from: be exact.
- **What is forbidden**: in a few words, exactly as far as the clause goes - "automated queries",
  "robots and scrapers without written consent", "extracts and copies of the database",
  "all crawling (robots.txt Disallow: / for every agent)". Do not widen it.
- **Clause (quoted)**: the deciding words in the original language, in quotation marks, with its
  clause number if it has one. No "|" inside the cell (write "/" instead).
- **Clause read at**: the exact URL where it was read.
- **Kind**: `terms` or `robots.txt`.
- One row per source. A board that operates in several countries under one set of terms gets one
  row, in the file of the country where the terms were read, with every host the clause covers.
  Boards that are the same everywhere (Indeed, LinkedIn and the like) go in `00-EU-wide` only.
- If the country has none, write the header lines and, instead of the table, the single line
  `None found.`
- "Status: checked" only when the clause was confirmed by the independent check; otherwise
  "first pass". A file built from a check file takes rows only from claims the check confirmed or
  corrected, using the corrected wording.

No web requests are needed to build a file from existing research and check files: copy the
quotes exactly as they stand there.
