# EU-wide (00) - explicitly prohibited sources

Status: first pass - not yet independently checked
Date: 2026-11-28

| Hosts | Source | What is forbidden | Clause (quoted) | Clause read at | Kind |
|---|---|---|---|---|---|
| indeed.com, de.indeed.com, at.indeed.com, fr.indeed.com, be.indeed.com, nl.indeed.com, ie.indeed.com | Indeed (every country site) | any automated system (bots, scrapers, spiders, AI or agentic AI) to access the site, mine data or submit content without Indeed's express written permission (crawling is permitted only as its robots.txt describes; that file was not read); crawling, scraping, extracting data from, or copying any part of the site | "ein beliebiges automatisiertes System (Bots, Scraper, Spider, KI oder agentische KI) verwenden, um ohne die ausdrückliche schriftliche Erlaubnis von Indeed auf die Website zuzugreifen, Data-Mining durchzuführen oder Inhalte an die Website zu übermitteln" and "Sie dürfen keinen Teil der Website crawlen, scrapen, Daten extrahieren, reproduzieren, duplizieren, kopieren" | https://de.indeed.com/legal | terms |
| linkedin.com, www.linkedin.com | LinkedIn | software, devices, scripts, robots or any other means or processes (crawlers, browser plugins and add-ons among them) to scrape or copy the Services | 8.2 "Develop, support or use software, devices, scripts, robots or any other means or processes (such as crawlers, browser plugins and add-ons or any other technology) to scrape or copy the Services" | https://www.linkedin.com/legal/user-agreement | terms |

Notes for the reader of this file (not rows):
- Neither row comes from the EU-wide research file, which quotes no terms of Indeed or LinkedIn; both come from
  the country files, as boards that are the same everywhere. Indeed: quoted from the Germany research file,
  which read the German terms ("Letzte Aktualisierung: 29. Juni 2026") on de.indeed.com. LinkedIn: quoted from
  the Germany research file, which points to the France file; the address is the one the France file gives
  (User Agreement "Effective on November 3, 2025").
- The France check confirmed both: Indeed's French terms on https://fr.indeed.com/legal ("Dernière mise à jour :
  1er avril 2026") and LinkedIn's agreement, each read once. This file still says "first pass" because the
  EU-wide layer has no check of its own. The two Indeed pages carry different dates; not resolved.
- Indeed hosts: de.indeed.com and fr.indeed.com were read; at.indeed.com, be.indeed.com, nl.indeed.com and
  ie.indeed.com are named in the country files as under the same terms and were not requested; indeed.com is
  their common parent. Other country sites are not named in any file.
- Left out on purpose: the EURES portal (no clause on automated reading; its privacy statement says crawlers are
  logged and misuse may be investigated; robots.txt asks a crawl delay only); Careerjet's partner API (a
  publisher key is needed; its terms forbid collecting listings in bulk for other ends than showing them to
  jobseekers, and building an independent job database - a limit on purpose, on a partner service); Adzuna's,
  Himalayas' and Remotive's API terms (conditions on display, credit and passing on, not a ban on reading);
  Jooble, The Muse, We Work Remotely and Cedefop (403: technical refusals, no clause read);
  Landing.jobs, Welcome to the Jungle / Otta, Wellfound, Arc.dev, Glassdoor and Facebook ("terms forbid" is
  known from the production system's notes only, no clause quoted - Welcome to the Jungle has a row in the
  France file); No Fluff Jobs, JustJoin.it and Remotive (robots.txt closes `/api/` only); Web Data Commons
  ("for research purposes only": a limit on purpose).
