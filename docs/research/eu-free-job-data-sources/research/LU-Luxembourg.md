# Luxembourg (LU) - free online job data sources: research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (`curl/8.14.1`, no added headers, one
capped GET per URL), and web search for finding pages. No account, key or login was used. Requests made, per
host: data.public.lu 9 (the open data portal's API and one page), adem.public.lu 3, govjobs.public.lu 3,
www.moovijob.com 2 (the second answered 403), and 1 each to gouvernement.lu, download.data.public.lu (a
2,500-byte range), www.jobs.lu, en.jobs.lu (404), www.jobfinder.lu, www.monster.lu, www.lbr.lu,
e-justice.europa.eu. Indeed and LinkedIn were not requested again (terms read once for the France file).

Per the brief's simplification of 28 November, each source has one line "Usable for own job search" in place
of the four separate readings of its terms.

## Takeaway

Luxembourg has no open feed or dataset of live vacancies. The employment agency's JobBoard is in transition:
the old one was taken offline for good after a security incident, and a first version of a new one went live
on 29 October 2026 with about 2,500 offers - only those whose employers allow direct applications - open to
anyone, with a second version announced for early December 2026; it is a web application, and ADEM's only
vacancy dataset on the open data portal holds closed vacancies (skills analysis, CC0). The State's own portal
GovJobs (253 offers) is web-only too; both sites' legal notices allow consulting, downloading and printing "à
titre personnel [...] dans un cadre strictement privé" and say nothing about programs. Of the commercial
boards, Moovijob answered a bot challenge, jobs.lu has no robots.txt at the address its redirect names, and
Monster's Luxembourg site now redirects to monster.com. For the employer route there is no free bulk file of
basic company data: the register (LBR) is searchable free one company at a time, and the only company
high-value datasets published are the annual-accounts files, which do carry each filer's name and RCS number.

## Sources

### ADEM JobBoard (public employment service)
- Publisher: ADEM, Agence pour le développement de l'emploi (the national employment agency), with the State's
  IT centre CTIE.
- Documentation: https://adem.public.lu/fr/jobboard.html ; government press release of 29.10.2026,
  https://gouvernement.lu/fr/actualites/toutes_actualites/communiques/2026/10-octobre/29-jobboard.html ; legal
  notice https://adem.public.lu/fr/support/aspects-legaux.html
- Data or endpoint: the JobBoard is reached from the page above; the application's own address was not found in
  the page's HTML.
- Holds: "l'ensemble des offres d'emploi pour lesquelles les employeurs ont autorisé une candidature directe".
  Offers without direct application stay with ADEM's advisers ("les conseillers de l'ADEM continueront à
  procéder aux assignations de candidats"). Fields not examined.
- Access: web application only. No API, feed or dump was found.
- Registration or key: none to read: "Toutes les personnes à la recherche d'un emploi, qu'elles soient inscrites
  ou non à l'ADEM, peuvent dès à présent y consulter" the offers.
- Cost: free.
- Licence or terms (exact wording, with URL): legal notice: "aucune reproduction des informations ou Services,
  totale ou partielle, sous quelque forme que ce soit et par quelque moyen que ce soit, n'est permise sans
  l'autorisation écrite préalable de l'Organisme. Sauf indication contraire, l'usager est autorisé à consulter,
  télécharger et imprimer les documents et informations disponibles aux conditions suivantes : Les documents ne
  peuvent être utilisés qu'à titre personnel, pour information et dans un cadre strictement privé ; [...] Les
  documents et informations ne peuvent être diffusés en dehors du site." robots.txt
  (https://adem.public.lu/robots.txt): several SEO bots shut out; for all agents "Disallow: /*?*" with "Allow:
  /*?b=*", and search paths disallowed.
- Usable for own job search: unclear - personal, private use is allowed in so many words, but nothing says
  whether a program may do the reading, and the JobBoard application itself was not seen.
- Volume: "2.500 offres d'emploi sont actuellement disponibles" (29.10.2026). On EURES 3,223 vacancies had a
  workplace in Luxembourg on 2026-11-28 (this study's EU-wide file).
- Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 529 bytes; GET /fr/jobboard.html -> 200, text/html,
  78,189 bytes (site navigation; no offer and no link to the application in the HTML); GET of the legal notice ->
  200, 96,141 bytes; GET of the press release -> 200, 90,801 bytes.
- Caveats: recent and announced changes - "À la suite de l'incident informatique ayant entraîné la mise hors
  ligne définitive de l'ancien JobBoard [...] Une première version du nouveau JobBoard de l'ADEM a été mise en
  ligne ce matin"; "Ce dispositif restera en place jusqu'à la mise en ligne d'une deuxième version du JobBoard,
  prévue pour début décembre 2026." Anything written about the JobBoard before November 2026 describes the old
  system. Employers in Luxembourg must declare vacancies to ADEM (dataset description below), so ADEM holds more
  than it shows.

### "Skills required in ADEM job vacancies" (open dataset; closed vacancies only)
- Publisher: ADEM.
- Documentation: https://data.public.lu/fr/datasets/skills-required-in-adem-job-vacancies/
- Data or endpoint: CSV files per two-year period, e.g.
  https://download.data.public.lu/resources/skills-required-in-adem-job-vacancies/20261120-100202/datasc-skills-vacancies-2025-2026.csv
  (130,986,979 bytes; not downloaded).
- Holds: "Each row of the dataset corresponds to a vacancy-skill combination"; vacancy id, skill (ESCO), number
  of positions, canton, occupation, sector, month and year of publication. "Active job ads (i.e., vacancies that
  are currently open) are not displayed." No title text, employer or link.
- Access: bulk files. Registration or key: none. Cost: free.
- Licence or terms (exact wording, with URL): `cc-zero` (CC0) on the dataset record.
- Usable for own job search: no - it leaves out open vacancies by design ("Active job ads [...] are not
  displayed") and names no employer.
- Volume: six files, 97-147 MB each, vacancies since 2015. Update cycle: quarterly (last 2026-11-20).
- Seen on 2026-11-28: GET https://data.public.lu/api/1/datasets/skills-required-in-adem-job-vacancies/ -> 200,
  application/json, 10,579 bytes. A search of the portal for "ADEM" returned this dataset only.
- Caveats: listed on data.europa.eu (this study's EU-wide file names it among Luxembourg's three matches).

### GovJobs - the State's job portal
- Publisher: the State of Luxembourg (civil service recruitment).
- Documentation: https://govjobs.public.lu/fr/support/aspects-legaux.html
- Data or endpoint: https://govjobs.public.lu/fr/postuler/postes-ouverts.html (not requested); municipal posts
  under `/fr/secteur-communal/postes-ouverts.html`.
- Holds: State vacancies, posts abroad, internal mobility, student jobs, and municipal vacancies and exams.
  Fields not examined.
- Access: web only; no feed or API found on the home page.
- Registration or key: none to read. Cost: free.
- Licence or terms (exact wording, with URL): the same State text as ADEM's: "l'usager est autorisé à consulter,
  télécharger et imprimer les documents et informations disponibles [...] Les documents ne peuvent être utilisés
  qu'à titre personnel, pour information et dans un cadre strictement privé". robots.txt identical to ADEM's
  ("Disallow: /*?*" for all agents, with the `?b=` exception).
- Usable for own job search: unclear - personal, private use allowed; automated reading not mentioned.
- Volume: "Nous avons 253 offres d'emploi" (home page).
- Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, 529 bytes; GET /fr.html -> 200, text/html, 45,031 bytes; GET of the
  legal notice -> 200, 49,236 bytes.
- Caveats: "Depuis le 15 septembre 2026, le parcours de recrutement dans la Fonction publique a évolué" (home
  page); how one applies was not read.

### jobs.lu, Moovijob, Jobfinder.lu, Monster.lu (commercial boards)
- Publisher: jobs.lu (Stepstone group, from memory); Moovijob; Jobfinder.lu; Monster.
- Documentation: none read.
- Data or endpoint: https://www.jobs.lu ; https://www.moovijob.com ; https://www.jobfinder.lu
- Holds: job adverts. Not examined. Access: web only as far as checked; no reading feed found.
- Registration or key: none to browse. Cost: free to browse.
- Licence or terms (exact wording, with URL): none read. Moovijob's robots.txt disallows for all agents
  `/cvtheque/`, `/offer/page/*`, `/offer/category*`, `/offer/tag/*` and old event paths. Jobfinder.lu's robots.txt,
  whole file: "User-agent: * Disallow: /backoffice/*" and "User-agent: * Allow: /".
- Usable for own job search: unclear - terms not read; Moovijob refuses a plain client (403, bot challenge).
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET https://www.jobs.lu/robots.txt -> 301 to https://en.jobs.lu/robots.txt -> 404, 103
  bytes; GET https://www.moovijob.com/robots.txt -> 200, 2,320 bytes; GET
  https://www.moovijob.com/conditions-generales-utilisation (a guessed address) -> **403**, Cloudflare "Just a
  moment..." (`cf-mitigated: challenge`; host not asked again); GET https://www.jobfinder.lu/robots.txt -> 200, 117
  bytes; HEAD https://www.monster.lu/ -> 301 to https://www.monster.com/fr/.
- Caveats: Monster's Luxembourg company was reported headed for liquidation with Monster's other European
  entities in 2025 (Paperjam, via a search summary).

### Indeed and LinkedIn in Luxembourg
- Usable for own job search: no for a program - Indeed's terms (1 April 2026) forbid using "un système automatisé
  (bots, agrégateurs (« scrapers »), « spiders », IA ou IA agentique) pour accéder, extraire des données" without
  written permission; LinkedIn's User Agreement forbids "software, devices, scripts, robots or any other means or
  processes [...] to scrape or copy the Services". Read once for this pass's France file (`FR-France.md`).

### Official vacancy statistics (one line)
- STATEC and ADEM labour-market tables are on data.public.lu under CC0 (seen in a portal search for "emploi");
  aggregates only.

## Through the employers

### Business register
- Publisher: Luxembourg Business Registers (LBR), which runs the Registre de commerce et des sociétés (RCS) under
  the Minister of Justice - one national register. Accounts data: STATEC's Centrale des bilans.
- Documentation: https://www.lbr.lu (redirects to `/mjrcs-web-front/`);
  https://e-justice.europa.eu/topics/registers-business-insolvency-land/business-registers-eu-countries/lu_en ;
  Luxembourg's high-value dataset fact sheet https://data.public.lu/en/pages/fact-sheets/hvd/
- Data or endpoint: RCS search on lbr.lu (web, one entity at a time; not requested). Bulk: the datasets tagged
  `companies-and-company-ownership` on data.public.lu, e.g.
  https://download.data.public.lu/resources/hvd-annex-5-companies-and-company-ownership-annual-deposits-2026/20261025-042629/hvd.annualdeposits2026.json
- Holds: **no free bulk file of basic company data was found.** The fact sheet assigns "Basic company
  information: LBR" and "Company documents and accounts: "Centrale des bilans" / STATEC", but the 15 datasets
  under the company tag are all STATEC's "HVD - Annex 5 Companies and Company Ownership - Annual deposits
  <year>" (2012-2026). One record of the 2026 file holds `RcsNumber`, `LegalUnitName` and the filed accounts
  (period, deposit date, currency, balance-sheet lines). So of the eight minimum attributes the free bulk data
  carries two - name and registration number - and only for entities that filed accounts; status, registration
  date, registered office address, legal form, Member State and activity code are not in the record seen, nor
  website, e-mail, phone or number of employees. The full register data (name, registered office, capital,
  representatives, per the e-Justice page) is free to look up one entity at a time on lbr.lu: "Public searches
  are done by registration number or by name"; "Documents filed with the Trade and Companies Register are
  available free of charge"; extracts and certificates are paid.
- Access: web search (free, one company per request); bulk JSON for accounts only. No API for basic data found.
- Registration or key: none for the bulk files; viewing filed documents needs a login "with or without creating
  a personal account" (e-Justice page).
- Cost: free, except extracts and certified copies.
- Licence or terms (exact wording, with URL): the accounts datasets are `cc-by` on their records; LBR's own terms
  were not read.
- Usable for own job search: partly - the accounts files give a free list of company names and RCS numbers
  (CC BY); nothing free gives addresses, activity codes or websites in bulk.
- Volume: 15 yearly files of 143-272 MB. Update cycle: quarterly by the description; files dated 2026-10-25.
- Seen on 2026-11-28: GET https://data.public.lu/api/1/datasets/?tag=companies-and-company-ownership -> 200,
  application/json, 98,254 bytes (15 datasets); GET of the 2026 file with a byte range 0-2499 -> 206,
  application/json, 2,500 bytes (the first record and part of the second); GET of the fact sheet -> 200, 115,316
  bytes; GET https://www.lbr.lu/ -> 200, 619 bytes (a redirect page); GET of the e-Justice page -> 200, 75,077
  bytes. Portal searches for "RCS" and "Luxembourg Business Registers" returned no dataset.
- Caveats: the fact sheet points to an "HVD Catalog" on catalog.inspire.geoportail.lu, which was not opened - a
  basic-information service from LBR may be listed there. Third-party guides say the beneficial-owner register
  is closed to the general public.

### Applicant-tracking vendors seen in the country

| Vendor | Local or international | Public feed for an employer's board (format, key?) | Documentation URL | Basis for "used here" |
|---|---|---|---|---|
| (none established) | - | - | - | No source read today names the systems Luxembourg employers use |
| Teamtailor, Greenhouse, Lever, SmartRecruiters, Workable, Recruitee, Personio, Workday | International | See this study's `00-EU-wide.md`, topic 5 | there | Not established for Luxembourg |

A Luxembourg-based recruiting-software vendor (Skeeled) is known to me from memory only; nothing about it was
read.

### Links to employers' own pages
- None found. ADEM's open dataset has no employer or link; the JobBoard was not seen at offer level.

### Employer directories
- None verified. Candidates known from memory only (not requested, terms not read): Luxinnovation's startup
  directory, the Chamber of Commerce's member services, the commercial directories Editus and Paperjam's
  business guide.

## Not free or not allowed

- ADEM: no API, feed or dataset of open vacancies; reproduction beyond personal, private use needs written
  permission.
- Indeed, LinkedIn: automated reading forbidden.
- Moovijob: 403 bot challenge to a plain client.
- LBR: extracts and certificates are paid; no free bulk basic data found.

## Gaps

- **ADEM JobBoard**: the application's address, fields, apply path and any interface behind it were not seen;
  the second version due in early December 2026 may change all of it. Whether ADEM passes all vacancies or only
  some to EURES is not established (3,223 on EURES against 2,500 on the JobBoard).
- **GovJobs**: the list of open posts and how to apply were not read.
- **jobs.lu, Moovijob, Jobfinder.lu**: terms not read; jobs.lu's robots.txt not found. Other boards (e.g. the
  newspapers' job sections) not checked.
- **Business register**: LBR's site was not read beyond its redirect page; the HVD catalogue was not opened;
  the field list of the accounts files comes from one record.
- **Applicant-tracking vendors and employer directories**: nothing verified.
- **data.europa.eu**: Luxembourg's entries were not requested again (the EU-wide file counts three for "job
  vacancies").
