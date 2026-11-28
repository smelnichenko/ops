# Poland (PL) - explicitly prohibited sources

Status: first pass - not yet independently checked
Date: 2026-11-28

| Hosts | Source | What is forbidden | Clause (quoted) | Clause read at | Kind |
|---|---|---|---|---|---|
| nofluffjobs.com | No Fluff Jobs | crawling of the adverts' own pages (`/posting/`, in every country edition) and of `/api/`, for every agent; the rest of the site is allowed | "User-agent: * Allow: / [...] Disallow: /api/ Disallow: /posting/ Disallow: /pl/posting/ Disallow: /hu/posting/ Disallow: /ua/posting/ Disallow: /cz/posting/ Disallow: /sk/posting/ Disallow: /nl/posting/ Disallow: /ua-ru/posting/" | https://nofluffjobs.com/robots.txt | robots.txt-partial |
| justjoin.it | Just Join IT | crawling of `/api/` and of list addresses with a comma in the path (`/oferty-pracy/*,*`), for every agent; the adverts' own pages (`/job-offer/...`) and the other list pages stay open, and a sitemap of active jobs is offered | "User-agent: * [...] Disallow: /oferty-pracy/*,* Disallow: /api/ Disallow: /profile [...] Disallow: /terms-and-privacy-policies Disallow: /pdf/ Disallow: /devs Disallow: /admin/" | https://justjoin.it/robots.txt | robots.txt-partial |
| aplikuj.pl, www.aplikuj.pl | aplikuj.pl | web scraping and running any scripts, bots or similar tools within the service | 1.8 f: "przestrzegania zakazu dokonywania ekstrakcji danych internetowych (web scraping) oraz uruchamiania jakichkolwiek skryptów, botów lub podobnych narzędzi w ramach Serwisu." | https://www.aplikuj.pl/regulamin | terms |
| olx.pl, www.olx.pl | OLX.pl (with its jobs section OLX Praca) | any use of the published content (adverts above all) without the right holders' written consent; any aggregating and processing of the service's data in order to pass it on to third parties | 2.3: "Zabrania się jakiegokolwiek wykorzystywania tych treści bez pisemnej zgody uprawnionych. Zabrania się jakiegokolwiek agregowania i przetwarzania danych oraz innych informacji dostępnych w Serwisie w celu ich dalszego udostępniania osobom trzecim w ramach innych serwisów internetowych jak i poza Internetem." | https://pomoc.olx.pl/olxplhelp/sfc/servlet.shepherd/document/download/069Wy00000MFKzdIAH | terms |
| praca.pl, www.praca.pl | Praca.pl | duplicating, printing, copying or distributing in any way the materials on the site's pages | "Wszelkie prawa zastrzeżone. Powielanie, drukowanie, kopiowanie lub rozpowszechnianie w jakikolwiek sposób materiałów zawartych na stronach Praca.pl jest zabronione." | https://www.praca.pl/regulamin.html | terms |

Notes for the reader of this file (not rows):
- No Fluff Jobs: the rule is in robots.txt only (last modified 2026-11-06) and closes paths, not the whole
  site; the paths are the adverts themselves and the API. Its terms of use were not read. The one site serves
  Poland, Czechia, Slovakia, Hungary, the Netherlands and Ukraine, so this is its only row.
- Just Join IT: robots.txt only; its terms of use were not read (robots.txt closes the terms page itself).
  The closed list addresses are those with a comma in the path; whether a program needs them is for the
  operator to judge.
- OLX: the clause is a general ban on using the content, in the terms in force from 13 March 2026 (a PDF on
  the help site); the terms have no clause on robots or scripts. robots.txt, for every agent, closes `/api/`
  (but admits `/api/v1/offers/`), `*/ajax/`, `*/rss/` and query addresses (`/*?q=`, `/*&q=`). The second
  sentence of the clause concerns passing data on only.
- Praca.pl: the sentence is the notice at the foot of the terms page; the terms proper (a PDF of 3.6 MB) were
  not read. robots.txt closes account and `/api/` paths only and admits AI crawlers by name.
- Left out on purpose: the ePraca web service of the labour offices (free, but for approved Polish-registered
  entities only: unavailable, not prohibited); the ePraca portal (no terms found, no robots.txt); Pracuj.pl
  (HTTP 403 with a Cloudflare challenge - a technical refusal; its terms PDF was over the size cap and unread);
  nabory.kprm.gov.pl (robots.txt closes nothing); the REGON API and the CEIDG data warehouse (key or account
  needed: unavailable, not prohibited).
- Praca.pl's robots.txt has a group that names AI crawlers (GPTBot, ClaudeBot and others) - with "Allow: /",
  so no restriction follows from it.
- Indeed and LinkedIn are the same in every country and go in the EU-wide file.
