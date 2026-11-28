# Germany (DE) - explicitly prohibited sources

Status: first pass - not yet independently checked
Date: 2026-11-28

| Hosts | Source | What is forbidden | Clause (quoted) | Clause read at | Kind |
|---|---|---|---|---|---|
| arbeitsagentur.de, www.arbeitsagentur.de, rest.arbeitsagentur.de | Bundesagentur für Arbeit - Jobsuche | robots, web spiders or similar technologies; unauthorised setting up or use of communication or programming interfaces to read out the content of the portal or the apps for collecting and analysing data | 2a(3) "Es ist insbesondere nicht zulässig: Robots, Webspider oder ähnliche Technologien einzusetzen" and "unautorisiert Kommunikations- bzw. Programmierschnittstellen einzurichten oder zu nutzen und so Inhalte des Portals oder der Apps zum Zweck der Datensammlung und -auswertung auszulesen" | https://www.arbeitsagentur.de/nutzungsbedingungen | terms |
| kleinanzeigen.de, www.kleinanzeigen.de | Kleinanzeigen (jobs section) | crawlers, spiders, scrapers or other automated mechanisms to access the services and collect content, without Kleinanzeigen's express written consent | § 5 "ohne die ausdrückliche schriftliche Zustimmung von Kleinanzeigen Crawler, Spider, Scraper oder andere automatisierte Mechanismen zu nutzen, um auf die Kleinanzeigen-Dienste zuzugreifen und Inhalte zu sammeln" | https://themen.kleinanzeigen.de/nutzungsbedingungen/ | terms |

Notes for the reader of this file (not rows):
- Bundesagentur: the terms were read on www.arbeitsagentur.de. `rest.arbeitsagentur.de` is the job search's own
  data interface; that host name comes from a community project's documentation (a third party), and the
  research did not request it because of this clause. The agency's robots.txt closes nothing.
- Kleinanzeigen: the terms sit on themen.kleinanzeigen.de and speak of "die Kleinanzeigen-Dienste"; the row lists
  the site itself.
- Indeed and LinkedIn are the same in every country and go in the EU-wide file.
- Left out on purpose: StepStone.de (terms not read on the German site; robots.txt closes result lists and
  query addresses, not the site, and says any other use of robots "is strictly prohibited"); XING (terms
  unread - a script page; robots.txt closes the job search paths only); Interamt (terms not read; robots.txt
  closes some paths and some named agents); service.bund.de (its own RSS feed is offered; the imprint only
  reserves copyright - no copying of protected content without consent; robots.txt closes the search pages and
  asks a crawl delay); the commercial register (usage rules known from third parties only; not a job source);
  softgarden, d.vinci and JOIN (key or token needed: unavailable, not prohibited); www.personio.de,
  support.dvinci.de and www.startbase.de (429 or 403: technical refusals, no clause read).
