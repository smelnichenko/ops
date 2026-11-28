# Netherlands (NL) - explicitly prohibited sources

Status: checked
Date: 2026-11-28

| Hosts | Source | What is forbidden | Clause (quoted) | Clause read at | Kind |
|---|---|---|---|---|---|
| jobbird.com, www.jobbird.com | Jobbird | reproducing or republishing the site or the information on it, in whole or in part, without written permission | "Artikel 3 [...] Het is nadrukkelijk verboden om zonder voorafgaande schriftelijke toestemming van de platforms verveelvoudiging of (her) publicatie van (een deel van) de website of de daarop vermelde informatie over te nemen." | https://www.jobbird.com/nl/algemene-voorwaarden | terms |
| nationalevacaturebank.nl, www.nationalevacaturebank.nl | Nationale Vacaturebank (DPG Media) | all crawling by the agent named ClaudeBot (Disallow: / for that agent only); for every agent the search, paging, apply and external-link addresses | "User-agent: ClaudeBot / Disallow: /" and, under "User-agent: *", "Disallow: /vacature/zoeken?*", "Disallow: /vacature/apply/", "Disallow: /vacature/external-url/", "Disallow: /solliciteren/" | https://www.nationalevacaturebank.nl/robots.txt | robots.txt |
| intermediair.nl, www.intermediair.nl | Intermediair (DPG Media) | all crawling by the agent named ClaudeBot (Disallow: / for that agent only) | "User-agent: ClaudeBot / Disallow: /" | https://www.intermediair.nl/robots.txt | robots.txt |

Notes for the reader of this file (not rows):
- The two DPG Media rows are narrow: the full ban names one agent, ClaudeBot. Other agents are shut out of search,
  paging and apply addresses only; vacancy pages are in the sites' sitemaps. The sites' terms were not read. If the
  reading program is not built on Claude, these two rows do not forbid it.
- Jobbird's clause is a ban on copying, not on robots as such; its robots.txt closes `/nl/vacature?*`, `/*/api`,
  `/*/export` and `/*/xml` for every agent.
- Left out on purpose: Werkzoeken.nl (technical refusal, no clause read); KVK's paid APIs (paid, not
  prohibited); werk.nl (no terms read; robots.txt closes `/webpublicaties` only).
- Indeed and LinkedIn are the same in every country and go in the EU-wide file.
