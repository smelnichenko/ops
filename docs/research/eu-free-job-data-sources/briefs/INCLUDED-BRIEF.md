# Brief: the include list

The operator's rule: **a source that is not on the include list is excluded.** There is no middle:
"unclear", "partly", "probably fine" all mean excluded. The include list is therefore the one
list a program acts on; the exclude list (`briefs/PROHIBITED-BRIEF.md`) only records, with the
quoted clause, the sources that are explicitly forbidden.

## What goes in

A source goes in only when ALL hold:
1. the independent check confirmed it (a first-pass finding alone is not enough);
2. its verdict is "usable for own job search: yes" - an open licence, or the publisher's own
   statement that the data or interface is public for reading;
3. a program can read it today without anyone's approval: no key, or a key that is free and
   self-service;
4. it is not on the exclude list.

Everything else stays out: unclear or unread terms, a key that needs an application or a
contract, a technical refusal, a source that could not be verified, a source nobody researched.

## File: `included/<CC>-<Name>.md` (same `<CC>-<Name>` as the country's other files; `00-EU-wide` for cross-border sources)

```
# <Name> (<CC>) - included sources

Date: <date the check saw them>

| Hosts | Source | What it gives | How to read it | Key | Why it is allowed | Kind |
|---|---|---|---|---|---|---|
```

- **Hosts**: the host names a program would contact, lower case, no scheme, no path,
  comma-separated. For a vendor whose customers each have their own subdomain, a pattern with a
  leading `*.` (for example `*.recruitee.com`). Be exact: this column is what an allow list is
  built from.
- **What it gives**: in a few words - "live vacancies, full text", "past adverts since 2006,
  with employer and occupation", "basic data on every company, with activity code", "an
  employer's own vacancies".
- **How to read it**: "JSON API", "RSS feed", "bulk CSV, daily", with the address pattern where
  the inputs give one.
- **Key**: `none` or `free self-service`.
- **Why it is allowed**: the licence or the publisher's statement, in its own words where short
  ("CC0", "Licence Ouverte 2.0", "API nyckel eller registrering: Nej").
- **Kind**: `vacancies` (live adverts), `archive` (past adverts), `employer-feed` (a vendor's
  documented public feed of one employer's board), `company-register`.
- One row per source. Cross-border sources (vendors' feeds, aggregators) go in `00-EU-wide` only.
- If the country has none, write the header lines and, instead of the table, the single line
  `None.`

No web requests: the file is written from the checked material only.
