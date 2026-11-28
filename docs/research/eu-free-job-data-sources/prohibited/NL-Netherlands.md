# Netherlands (NL) - explicitly prohibited sources

Status: checked
Date: 2026-11-28

| Hosts | Source | What is forbidden | Clause (quoted) | Clause read at | Kind |
|---|---|---|---|---|---|
| jobbird.com, www.jobbird.com | Jobbird | reproducing or republishing the site or the information on it, in whole or in part, without written permission | "Artikel 3 [...] Het is nadrukkelijk verboden om zonder voorafgaande schriftelijke toestemming van de platforms verveelvoudiging of (her) publicatie van (een deel van) de website of de daarop vermelde informatie over te nemen." | https://www.jobbird.com/nl/algemene-voorwaarden | terms |
| nationalevacaturebank.nl, www.nationalevacaturebank.nl | Nationale Vacaturebank (DPG Media) | for every agent: crawling the search addresses (`/vacature/zoeken?`, `/vacature/uitgebreid-zoeken`), paged lists (`/vacatures/*?page=`), the apply addresses (`/vacature/apply/`, `/solliciteren/`), the external-link addresses (`/vacature/external-url/`) and `/archief/`; the vacancy pages themselves are not closed | "User-agent: *", "Disallow: /vacature/zoeken?*", "Disallow: /vacature/uitgebreid-zoeken", "Disallow: /vacatures/*?page=", "Disallow: /vacature/apply/", "Disallow: /solliciteren/", "Disallow: /vacature/external-url/", "Disallow: /archief/" | https://www.nationalevacaturebank.nl/robots.txt | robots.txt-partial |

Notes for the reader of this file (not rows):
- Rules that name only particular crawlers, not rows: Nationale Vacaturebank's and Intermediair's robots.txt
  both carry "User-agent: ClaudeBot" with "Disallow: /" (read on 2026-11-28 at
  https://www.nationalevacaturebank.nl/robots.txt and https://www.intermediair.nl/robots.txt). They bind that
  crawler only.
- Intermediair is not a row: its every-agent rules were not transcribed by the check (the research says the file
  has the same structure as Nationale Vacaturebank's), and its terms were not read.
- Jobbird's clause is a ban on copying, not on robots as such. Its robots.txt, for every agent, also closes
  `/nl/vacature?*`, `/*/api`, `/*/export`, `/*/xml`, `/*/job_contact`, `/*/job_mail` and `/outgoing/*`.
- Left out on purpose: Werkzoeken.nl (technical refusal, no clause read); KVK's paid APIs (paid, not
  prohibited); werk.nl (no terms read; its robots.txt closes `/webpublicaties` only); Werken voor Nederland
  (robots.txt closes `/login` only; content under CC0).
- Indeed and LinkedIn are the same in every country and go in the EU-wide file.
