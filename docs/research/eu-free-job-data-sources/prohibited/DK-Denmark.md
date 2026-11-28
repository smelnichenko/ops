# Denmark (DK) - explicitly prohibited sources

Status: checked
Date: 2026-11-28

| Hosts | Source | What is forbidden | Clause (quoted) | Clause read at | Kind |
|---|---|---|---|---|---|
| ofir.dk, www.ofir.dk | Ofir (site closed, per the Internet Archive copy of 2026-10-10) | all crawling (robots.txt Disallow: / for every agent; only /.well-known/ is allowed) | "User-agent: * Allow: /.well-known/ Disallow: /" | https://www.ofir.dk/robots.txt | robots.txt |

Notes for the reader of this file (not rows):
- Ofir is both closed and prohibited: the robots.txt was read live (200, the whole file is the three lines
  quoted); the archived front page answers 410, "Ofir.dk er lukket, besøg Jobindex i stedet". The row rests on
  the robots.txt.
- Left out on purpose: Jobindex and it-jobbank.dk (no clause on automated reading in the terms; robots.txt
  closes `/api/` and paged or filtered search addresses, and three named agents outright, not the site);
  jobbank.dk (pages answered 500, terms unread; robots.txt closes some paths only); Jobnet (no terms for
  readers, no robots.txt); STAR's JobannonceService (by signed agreement only: unavailable, not prohibited);
  Workindenmark (no robots.txt, no terms of use).
