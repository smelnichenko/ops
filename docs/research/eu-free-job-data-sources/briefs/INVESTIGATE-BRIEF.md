# Brief: the list for future investigation

Three lists, one place for every source the study found:
1. **Include list** (`briefs/INCLUDED-BRIEF.md`): what a program may read. Not on it = excluded.
2. **Exclude list** (`briefs/PROHIBITED-BRIEF.md`): explicitly forbidden, with the quoted clause.
3. **This list**: sources that are excluded today only because something is still open. It says
   what is open and what would settle it, so that someone can pick it up later.

## What goes in

A source that could serve one person's own job search (live vacancies, past adverts, an
employer's feed, a company register), is NOT explicitly prohibited, and did not meet the include
rule for one of these reasons - the "Obstacle" column:

- `terms-unclear`: its terms are silent on reading by a program, or could not be read or found.
- `needs-approval`: reading needs a key or access that someone must grant (an application, an
  agreement, an organisation as applicant), or new access is suspended.
- `refused`: the host refused the request (403, 429, a challenge page, a CAPTCHA), so nothing
  could be established.
- `unverified`: the first pass reported it but the independent check could not confirm it (a
  login wall, a script-only page, the request budget spent, a page not found).

## What stays out

- Anything on the include list or the exclude list.
- Closed or dead services, and official statistics (counts are of no use here).
- Paid products: paying is not something to investigate.

## File: `pending/<CC>-<Name>.md` (same `<CC>-<Name>` as the country's other files; `00-EU-wide` for cross-border sources)

```
# <Name> (<CC>) - sources for future investigation

Date: <date of the check>

| Hosts | Source | What it would give | Why it is not included | What would settle it | Obstacle |
|---|---|---|---|---|---|
```

- **Hosts**: host names, lower case, no scheme, no path, comma-separated; a leading `*.` for a
  vendor's per-customer subdomains.
- **What it would give**: a few words - "live vacancies of Wallonia, with a link to each advert".
- **Why it is not included**: the fact, exactly - "answered 429 to both passes", "terms page is a
  script shell", "key issued to organisations on application".
- **What would settle it**: one concrete next step - "retry after the daily quota resets
  (00:00 UTC)", "read the terms at <URL> in a browser", "ask the publisher whether programs may
  read the feed", "apply for access at <URL>".
- **Obstacle**: one of the four values above.
- One row per source. If the country has none, write the header lines and the single line `None.`

No web requests: the file is written from the research and check files only.
