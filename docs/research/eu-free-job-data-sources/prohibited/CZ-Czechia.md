# Czechia (CZ) - explicitly prohibited sources

Status: first pass - not yet independently checked
Date: 2026-11-28

| Hosts | Source | What is forbidden | Clause (quoted) | Clause read at | Kind |
|---|---|---|---|---|---|
| prace.cz, www.prace.cz | Prace.cz (Alma Career Czechia) | crawling of the search pages (`/hledat/`) and of account and reply-form paths, for every agent; the rest of the site stays open and a sitemap index is offered | "User-Agent: * Disallow: /auth/ Disallow: /muj/ Disallow: /asmt/ Disallow: /hledat/ Disallow: /odpovedni-formular/ Disallow: /presmerovani-na-formular/ Disallow: /odpoved-odeslana/" | https://www.prace.cz/robots.txt | robots.txt-partial |

Notes for the reader of this file (not rows):
- Prace.cz: robots.txt only. The product terms of Jobs.cz and Prace.cz (in force from 1. 8. 2022) have no
  clause on robots or copying; Alma Career's general terms, to which they refer, could not be read by a plain
  client (a script page), so no row rests on terms.
- Left out on purpose: Jobs.cz (robots.txt closes `/api/`, `/iapi/`, account and technical paths for every
  agent - not search, list or advert pages; terms as above); StartupJobs.cz (terms silent, robots.txt admits
  every agent); the ISoSS civil-service portal (HTTP 403 - a technical refusal, no clause read); Recruitis
  boards (a token of the employer is needed: unavailable, not prohibited).
- No Fluff Jobs' Czech edition (`/cz/posting/`) is covered by the row in the Poland file.
- The official sources (MPSV vacancy files, ARES, the public register's open data) carry no prohibition; ARES
  sets operating limits (more than 500 queries a minute, repeated identical queries, random probing of the
  database may lead to a block).
- Indeed and LinkedIn are the same in every country and go in the EU-wide file.
