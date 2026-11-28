# Austria (AT) - free online job data sources: research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (`curl/8.14.1`, no added headers, one
capped GET per URL, redirects not followed automatically) and web search for finding pages. No account, key or
login was used. Requests made, per host: data.europa.eu 9 (used in place of data.gv.at's own catalogue API,
which answered 404), justizonline.gv.at 6 (two of them HEAD), www.jobboerse.gv.at 3, firmen.wko.at 3 (one a
redirect), data.statistik.gv.at 3, erwin.atlassian.net 3 (eRecruiter's knowledge base; shared with the Germany
file), zenodo.org 3, www.ams.at 2, jobs.ams.at 2, www.karriere.at 2, www.willhaben.at 2, www.stepstone.at 2,
www.wko.at 2 (one a redirect), www.justiz.gv.at 2 (one a redirect), www.bmwet.gv.at 2, and 1 each to
www.data.gv.at (404) and e-justice.europa.eu. Indeed and LinkedIn were not requested (terms read for the Germany
and France files). No employer's job board was requested, including the two that are published as open data
(below).

## Takeaway

Austria's one comprehensive source, the AMS job search engine "alle jobs", is closed to programs in plain words:
it may be used "ausschließlich zur eigenen, manuellen Suche", automated mechanisms "keinesfalls", and its
robots.txt shuts every path below the entry page. The two largest commercial boards say the same (karriere.at:
"Sämtliche Formen der automatisierten Auswertung unserer Plattform sind verboten"; willhaben forbids spiders in
the first line of its robots.txt). What is free and licensed for reuse is small: two public employers, the City
of Linz and the federal computing centre BRZ, publish the XML feeds of their own career portals on data.gv.at
under CC BY 4.0, and the Land of Carinthia lists single vacancy notices there. The employer route is better
served than in Germany. The Firmenbuch is published as a high-value dataset: a free SOAP interface on
JustizOnline gives name, seat, address and legal form per company, a search by name and a list of changes per
day - but only with a token that the justice ministry grants on application, and applying requires an ID Austria.
Without any key, Statistik Austria publishes every active Firmenbuch number with its ÖNACE activity code as one
CSV (CC BY 4.0, monthly), and the applicant-tracking system eRecruiter, which both open-data feeds run on,
documents an XML/RSS job feed on every customer portal.

## Sources

### AMS - "alle jobs" (public employment service)
- Publisher: Arbeitsmarktservice Österreich (AMS; Public Employment Service Austria).
- Documentation: "alle jobs - Hilfe und rechtliche Informationen",
  https://www.ams.at/arbeitsuchende/arbeitslos-was-tun/jobsuche-online-und-mobil/ams-jobsuche-hilfe ; for
  employers' software, "AMS HR-API", https://www.ams.at/unternehmen/service-zur-personalsuche/ams-hr-api .
- Data or endpoint: https://jobs.ams.at/public/emps/ (web application). No open-data dump, no documented reading
  API, no feed.
- Holds: "alle jobs = AMS-Stellenangebote + Stellenangebote aus dem Internet": vacancies reported to the AMS and
  kept by its advisers; vacancies sent by employers' recruiting software through the HR-API; vacancies employers
  enter themselves in the eJob-Room; adverts "aus dem Internet von in Österreich tätigen Unternehmen und
  Institutionen", which "werden durch einen sogenannten Crawler aus dem Internet extrahiert und gesammelt oder
  durch eine Schnittstelle eingespielt"; and selected vacancies from Germany (Bundesagentur für Arbeit), South
  Tyrol and Trentino. The full-text search covers "Jobtitel", "Unternehmensname", "Berufsgruppe", "Inserat",
  "Stellenbeschreibung", "Unternehmensbeschreibung"; filters for working time, date, kind of contract and
  education. Adverts from the internet have no detail page at the AMS: "Die Details werden immer auf der
  jeweiligen Webseite des Fundortes angezeigt", with the source in the field "gefunden bei" and a link "zum
  externen Stellenangebot".
- Access: web only. The HR-API runs the other way: "bieten wir Unternehmen, die eine Recruiting-Software nutzen,
  die Möglichkeit zu einer Datenanbindung an das AMS", and its specification is handed out "bei Freischaltung
  des Services HR-API in Ihrem eAMS-Konto".
- Registration or key: none to search ("kostenfrei und ohne Registrierung").
- Cost: free ("Sie müssen kein Entgelt für die Nutzung von "alle jobs" zahlen.").
- Licence or terms (exact wording, with URL): the help page, section "Rechtliches: Nutzungsbedingungen":
  "Unzulässigkeit der Verwendung automatisierter Mechanismen: Sie dürfen "alle jobs" ausschließlich zur eigenen,
  manuellen Suche nach Stellenangeboten verwenden. Keinesfalls dürfen automatisierte Mechanismen verwendet
  werden, beispielsweise um Daten der gelisteten Stellenangebote für Ihre eigenen Zwecke zu verwenden." and
  "Keine Verwendung von Texten und Logos zu eigenen Interessen und Zwecken: Die angezeigten Texte und Logos sind
  urheberrechtlich und markenrechtlich geschützt." robots.txt (https://jobs.ams.at/robots.txt), whole file:
  "user-agent: LinkedInBot Allow: /public/emps/ Disallow:" and "user-agent: * Allow: /public/emps/$ Disallow:
  /public/emps/".
- Usable for own job search: no - "Sie dürfen "alle jobs" ausschließlich zur eigenen, manuellen Suche nach
  Stellenangeboten verwenden. Keinesfalls dürfen automatisierte Mechanismen verwendet werden".
- Volume: not read (the page is built by script). On EURES 57,261 vacancies had a workplace in Austria on
  2026-11-28 (this study's EU-wide file).
- Update cycle: internet adverts "mehrmals täglich aktualisiert"; expired ones leave "grundsätzlich innerhalb
  eines Tages".
- Seen on 2026-11-28: GET of the help page -> 200, text/html, 95,393 bytes; GET of the HR-API page -> 200, 53,005
  bytes; GET https://jobs.ams.at/robots.txt -> 200, text/plain, 116 bytes; GET https://jobs.ams.at/public/emps/ ->
  200, text/html, 19,860 bytes (title "alle jobs - die Stellensuche des AMS", no vacancy data in the HTML). No
  request to the application's data paths.
- Caveats: several scrapers of jobs.ams.at are sold on apify.com (search results); one listing says the back end
  is "guarded by short-lived signed tokens" (third party, not tested). The AMS's open data are counts only: on
  data.gv.at "Offene Stellen nach Berufen - Bestand" and sister tables (CSV at
  `https://www.arbeitsmarktdatenbank.at/opendata/...`, CC BY 4.0, last changed 2026-11-02; not requested).

### Jobbörse der Republik Österreich - federal public-service vacancies
- Publisher: the federal government's job exchange (a search summary places it with the Bundeskanzleramt; the
  site's imprint was not read).
- Documentation: none found for reading vacancies.
- Data or endpoint: https://www.jobboerse.gv.at/ (WordPress site with "Jobsuche", "Mein Profil", "Jobagent").
- Holds: vacancies of the federal service and of EU institutions (per the site's navigation and a search
  summary). Fields not examined.
- Access: web only as far as found. The site's RSS feed (https://www.jobboerse.gv.at/feed/) carries eight
  articles on occupations from March 2021, not vacancies.
- Registration or key: none to browse; applying online needs ID Austria (search summary of the
  Bundeskanzleramt's page).
- Cost: free.
- Licence or terms (exact wording, with URL): not read. robots.txt (https://www.jobboerse.gv.at/robots.txt, last
  modified 21 June 2023), all agents: "Disallow: /wp-admin/", "Disallow: /bundensinterne-ausschreibungen",
  "Disallow: /statische-jobsuche", two sitemaps.
- Usable for own job search: unclear - no terms read and no vacancy feed found; robots.txt closes the path
  "/statische-jobsuche".
- Volume: not read. Update cycle: not read.
- Seen on 2026-11-28: GET /robots.txt -> 200, 314 bytes; GET / -> 200, text/html, 116,573 bytes; GET /feed/ ->
  200, application/rss+xml, 7,372 bytes, 8 items dated 5 March 2021.
- Caveats: the home page links a WordPress REST interface (`/wf-rest-api/`); whether it lists vacancies was not
  tried (three requests spent).

### Open-data vacancy feeds on data.gv.at: City of Linz and Bundesrechenzentrum
- Publisher: Stadt Linz ("Offene Stellen (Linz)"); Bundesrechenzentrum, the federal computing centre ("Offene
  Stellen des Bundesrechenzentrum"). Both records sit in the national catalogue data.gv.at.
- Documentation: the catalogue records (read through data.europa.eu, datasets
  `6d07f9fa-8f43-446d-9770-1b950e020f77` and `b53d4563-9242-44c5-b2a9-e1d1370efaf6`); the feed format is the
  vendor's, https://erwin.atlassian.net/wiki/spaces/ERECRUITER/pages/262570/Job+Feed (see the vendor table).
- Data or endpoint: Linz - XML `https://jobs.linz.at/Syndication/Xml?referrer=Homepage`, RSS
  `https://jobs.linz.at/Syndication/Rss?referrer=Homepage`; BRZ - XML
  `https://www.brz-jobs.at/Syndication/Xml?referrer=BRZ%20Portal` (and the same with `&format=html`).
- Holds: Linz - "Offene Stellenausschreibungen aus dem Karriereportal der Stadt Linz" ("Bitte beachten, dass Jobs
  der Unternehmensgruppe Linz nicht enthalten sind"); BRZ - "Maschinenlesbarer Datensatz aller auf
  https://www.brz-jobs.at verfügbaren Stellenausschreibungen". Fields per the vendor's documentation: `id`,
  `name`, `subTitle`, `companyDescription`, `description`, `requirements`, `additionalText`, `location`, `region`,
  `jobCountry`, `jobZipCode`, `jobProfile`, `occupationType`, `careerLevel`, `url`, `applyUrl`,
  `dateSinceOnline`, `dateOfUpdate`, contact person and e-mail.
- Access: feed (XML, RSS).
- Registration or key: none stated.
- Cost: free.
- Licence or terms (exact wording, with URL): both records give "https://creativecommons.org/licenses/by/4.0/"
  (CC BY 4.0).
- Usable for own job search: yes - published as open data under CC BY 4.0 by the employers themselves.
- Volume: not read (two employers' own vacancies).
- Update cycle: Linz record issued 2022-06-29, changed 2022-11-24; BRZ record issued 2023-02-15, changed
  2024-06-10, frequency "irregular". The feeds themselves are live views of the portals, per the format.
- Seen on 2026-11-28: the two catalogue records, in data.europa.eu search answers -> 200, application/json. **The
  feeds were not requested**: they are employers' own boards on a vendor's platform, which this pass was told
  never to request.
- Caveats: the records are two and four years old; whether the addresses still answer is unconfirmed. One
  employer of interest for IT work (BRZ) and one city.

### Other vacancy records on data.gv.at
- Land Kärnten publishes single vacancy notices as catalogue records, e.g. "Stellenausschreibung Land Kärnten
  (149570/2026)" and "(149415/2026)" of 2026-11-26 ("Straßenmeisterei Villach / Straßenfacharbeiter:in"), each
  linking to the Land's own page (`https://www.ktn.gv.at/Service/Stellenausschreibungen/Details?id=...`), CC BY
  4.0. A phrase search found 5 such records; single municipalities do the same (e.g. Gemeinde Engerwitzdorf, JSON
  and PDF).
- Searches on data.europa.eu limited to Austria: `Stellenangebote` -> 3 records (two Vorarlberg statistics
  pages and Linz); `Stellenausschreibungen` -> 12 (the above, BRZ, Linz, Graz's official gazette); `offene
  Stellen` and `Jobs` -> beyond these only AMS count tables, funding contracts and procurement records.
- Usable for own job search: yes (CC BY 4.0), but a handful of notices, not a vacancy source.
- Seen on 2026-11-28: six search requests -> 200. GET
  `https://www.data.gv.at/katalog/api/3/action/package_search?q=Stellenangebote` -> **404** (the portal's former
  catalogue address; its present API was not looked for).

### karriere.at
- Publisher: karriere.at (karriere.at GmbH per search results; the terms name Linz as place of jurisdiction).
- Documentation: https://www.karriere.at/nutzungsbedingungen
- Data or endpoint: https://www.karriere.at ; no feed or API for reading adverts is offered.
- Holds: adverts of paying employers. Not examined.
- Access: web only. Registration or key: none to search or to apply ("Du kannst dich auch ohne Registrierung auf
  ein Inserat bewerben"). Cost: free for job seekers.
- Licence or terms (exact wording, with URL): "Du darfst die Informationen auf unserer Website bloß für deine
  persönliche Jobsuche und den privaten Gebrauch verwenden. Sämtliche Formen der automatisierten Auswertung
  unserer Plattform sind verboten." robots.txt (https://www.karriere.at/robots.txt): "User-agent: BLEXBot
  Disallow: /", "User-agent: AhrefsBot Disallow: /", "User-agent: * Disallow:" (nothing closed), and 13 sitemaps,
  among them `sitemap-jobs-https.xml` and `sitemap-firmen-https.xml`.
- Usable for own job search: no - "Sämtliche Formen der automatisierten Auswertung unserer Plattform sind
  verboten."
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 1,043 bytes; GET /nutzungsbedingungen -> 200, text/html,
  128,666 bytes.
- Caveats: the terms and robots.txt disagree (robots.txt admits every agent but two); the terms are the stricter
  text. The terms also say: "Einzelne Unternehmen verlinken dich für deine Bewerbung auf ihre entsprechende
  Unternehmensseite."

### willhaben (jobs section)
- Publisher: willhaben (legal entity not read).
- Documentation: https://www.willhaben.at/iad/nutzungsbedingungen
- Data or endpoint: https://www.willhaben.at/jobs/ ; no reading feed (robots.txt closes `/jobs/webapi/`,
  `/webapi/`, `/restapi/`, `/rest/`).
- Holds: classified adverts; the page's counter shows "Jobs 14.800". Not examined.
- Access: web only. Registration or key: none to browse. Cost: free.
- Licence or terms (exact wording, with URL): "Die auf willhaben angezeigten Inhalte dürfen ohne vorherige
  Zustimmung der Rechteinhaber weder kopiert, bearbeitet, verbreitet, veröffentlicht oder öffentlich zur Verfügung
  gestellt werden (Online-Veröffentlichung) noch in sonstiger Weise genutzt werden. Dies gilt auch für ein
  Kopieren durch "Robot/Crawler" Suchmaschinentechnologien oder durch sonstige automatische Mechanismen". robots.txt
  (https://www.willhaben.at/robots.txt) opens: "# It is expressively forbidden to use spiders, search robots or
  other automatic methods to access willhaben.at. Only if willhaben.at has given such access is allowed." and
  disallows, among others, "/jobs/suche?*" and "/jobs/suche*?similarAdvert*".
- Usable for own job search: no - "It is expressively forbidden to use spiders, search robots or other automatic
  methods to access willhaben.at."
- Volume: 14,800 job adverts (counter on the terms page). Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, 3,926 bytes; GET of the terms -> 200, text/html, 158,428 bytes.
- Caveats: none.

### StepStone.at
- Publisher: The Stepstone Group Österreich GmbH, Prinz-Eugen-Straße 8-10, 1040 Wien.
- Documentation: https://www.stepstone.at/ueber-stepstone/rechtliche-hinweise/nutzungsbedingungen/ ("Allgemeine
  Nutzungsbedingungen für Bewerber"; no date on the page).
- Data or endpoint: https://www.stepstone.at ; no feed or API for reading adverts is offered.
- Holds: adverts of paying employers. Not examined.
- Access: web only. Registration or key: none to browse. Cost: free for candidates.
- Licence or terms (exact wording, with URL): 1.2: "Die diesen Nutzungsbedingungen unterstehenden
  Dienstleistungen sind nur für die individuelle Arbeitssuche, beziehungsweise Arbeitsvermittlung im Sinne des §
  2 Absatz 3 Arbeitsmarktförderungsgesetz (AMFG) natürlicher Personen als Angestellte oder Freiberufler
  vorgesehen. Es ist nicht zulässig, unsere Dienstleistungen auf andere Weise kommerziell zu nutzen". 4.3.4: not
  permitted "Scraping- oder vergleichbare Techniken zu benutzen, um Inhalte zu erfassen und für einen anderen
  Zweck zu verwenden, wieder zu veröffentlichen oder auf andere Art als den vorgesehenen Zweck der
  Dienstleistungen zu nutzen". robots.txt (https://www.stepstone.at/robots.txt) opens: "Any other use of robots or
  failure to obey the robots exclusion standards [...] is strictly prohibited." and disallows for all agents,
  among others, "/?*", "/5/ergebnisliste.html", "/5/resultlistpage", "/5/jobapply".
- Usable for own job search: unclear - the scraping ban is tied to "einen anderen Zweck" than the individual job
  search, not to every program; robots.txt closes the result lists and query addresses.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET of the terms -> 200, text/html, 122,823 bytes; GET /robots.txt -> 200, text/plain, 2,242
  bytes.
- Caveats: same group and near-identical wording as the Belgian terms in this study's Belgium file.

### Indeed and LinkedIn in Austria
- Same terms as recorded elsewhere in this study: Indeed's German terms ("Letzte Aktualisierung: 29. Juni 2026",
  read for the Germany file) and LinkedIn's User Agreement (France file).
- Usable for own job search: no - Indeed: "ein beliebiges automatisiertes System (Bots, Scraper, Spider, KI oder
  agentische KI) [...] ohne die ausdrückliche schriftliche Erlaubnis von Indeed"; LinkedIn: "software, devices,
  scripts, robots or any other means or processes [...] to scrape or copy the Services". No request was made to
  at.indeed.com or to LinkedIn.

### Official vacancy statistics
- Skipped by the brief. (The AMS count tables on data.gv.at are named under the AMS block.)

## Through the employers

### Business register
- Publisher: Bundesministerium für Justiz (BMJ); the Firmenbuch is kept by the regional courts and served
  through JustizOnline; the interface is documented by the "Firmenbuch-Team" at the Bundesrechenzentrum
  (firmenbuch@brz.gv.at). A second, separate publisher: Statistik Austria.
- Documentation: JustizOnline, "Informationen zur Informationsweiterverwendung",
  https://justizonline.gv.at/jop/web/iwg (rendered by script; its German text was read from the page's own text
  file, https://justizonline.gv.at/jop/web/assets/i18n/de.json); interface description
  https://justizonline.gv.at/jop/web/assets/iwg/WebService-HVD.zip ("FBW-WebServices (HVD)
  Schnittstellenbeschreibung", version 1.3 of 22.5.2025, with twelve XML schemas; the archive was last changed
  on 26 November 2026); catalogue record "High Value Datasets (HVD) des Firmenbuchs" on data.gv.at (issued
  2025-03-17, changed 2025-06-02, contact justizonline-iwg@brz.gv.at). Statistik Austria:
  https://data.statistik.gv.at/web/meta.jsp?dataset=OGDEXT_HVD_FBNR_OENACE_1 .
- Data or endpoint: SOAP web service `https://justizonline.gv.at/jop/api/at.gv.justiz.fbw/ws` (WSDL at
  `.../ws/fbw.wsdl`); bulk file https://data.statistik.gv.at/data/OGDEXT_HVD_FBNR_OENACE_1.csv .
- Holds:
  - Firmenbuch interface, six operations: extract ("Auszug V2") by Firmenbuch number and reference date - for
    this free interface only in the scope "Kurzinformation" (schema note: "JustizOnline-HVD nur
    "Kurzinformation""); company search ("Firmensuche") by name with wildcards, exact or phonetic, limited by
    court, legal form or municipality/district/Land code, returning `FNR`, `STATUS`, `NAME`, `SITZ`, `RECHTSFORM`,
    `RECHTSEIGENSCHAFT`, `GERICHT`; changes ("Veränderungen Firmen") between two dates, optionally by court and
    legal form, returning the numbers of the companies changed with date and kind of change; and three
    operations on filed documents (search, changes, retrieval - e.g. annual accounts as XML).
  - The extract schema carries the name (`BEZEICHNUNG`), the address (`STELLE`, `PLZ`, `ORT`, `STAAT`), the seat
    (`SITZ`), the legal form (`RECHTSFORM`), the number (`FNR`), the European identifier (`EUID`), the dates of
    entries (`VOLLZUGSDATUM`) and whether an entry stands (`AUFRECHT`), a key `KUR` ("Key des
    Unternehmensregisters zur Firmenbuchnummer"), persons and their functions - and an optional element
    `HOMEPAGE`. The documentation's
    example of a short extract shows name and address; **whether the short extract fills `HOMEPAGE` is not
    confirmed**. The schemas hold no element for an e-mail address, a telephone number or an activity code
    (one free-text group, `FI_DKZ05`, carries no label and was not identified).
  - Statistik Austria's file: two columns, `FB_NUMMER;OENACE_ZUORD` (e.g. `000196p;62100`) - "Firmenbuchnummer mit
    ÖNACE Zuordnung; Grundmasse: alle aktiv im Firmenbuch eingetragenen Unternehmen mit aktiv zugeordneter
    Wirtschaftstätigkeit. Unternehmen ohne zugeordnete ÖNACE sind nicht enthalten."
  - Against the eight minimum attributes: number and activity code in the bulk file; name, registered office
    address, legal form, status and dates through the interface; Member State trivially. Beyond them: possibly
    the website (above); no e-mail, telephone or head-count.
- Access: **API, one company or one search per call, no bulk file of names** - plus the bulk CSV of numbers and
  activity codes. The interface answers "HTTP-Statuscode 429 (Too Many Requests)" when its load limit is
  exceeded; the limit is not stated.
- Registration or key: a token is needed, sent as header `X-API-KEY`. JustizOnline: "Daten, die auf JustizOnline
  öffentlich zur Verfügung gestellt werden, können nach einer Antragstellung und der Genehmigung des Antrages via
  Schnittstelle in maschinenlesbarer Form erhalten werden." and "Um einen Antrag auf Weiterverwendung nach dem
  Informationsweiterverwendungsgesetz (IWG) über JustizOnline stellen zu können, ist eine ID Austria erforderlich.
  [...] Dieser Antrag richtet sich an das Bundesministerium für Justiz (BMJ), das in weiterer Folge darüber
  entscheidet." and "Sofern Sie einen Antrag [...] gestellt haben und dieser genehmigt wurde, erhalten Sie einen
  Token auf JustizOnline." So: free, but not self-service - an application with subject, reason and e-mail
  address, a decision by the ministry, and Austria's electronic identity to apply. Statistik Austria's file: no
  key.
- Cost: free. "Der Abruf über eine standardisierte Schnittstelle wird kostenlos zur Verfügung gestellt."; the list
  of interfaces "die kostenfrei genutzt werden können" names "Unternehmensdaten gemäß Anhang 5. der DV (EU)
  2023/138 [...] (High Value Datasets (HVD) des Firmenbuchs)". Outside this interface the register stays paid:
  the ministry's page says "Das Firmenbuch kann kostenpflichtig über JustizOnline abgefragt werden", and Austria's
  text on the e-Justice Portal (last updated 26/01/2022): "Die Abfrage von Daten aus der Firmenbuchdatenbank ist
  - abgesehen von der kostenlosen Kurzinformation, welche die wichtigsten Informationen über einen Rechtsträger
  enthält - kostenpflichtig." and "Die zuvor erwähnte Kurzinformation kann hingegen ohne weitere Voraussetzungen
  abgerufen werden." (the short information on the web, one company at a time).
- Licence or terms (exact wording, with URL): Firmenbuch HVD - "https://creativecommons.org/licenses/by/4.0/"
  (catalogue record); applicants must also accept the "Nutzungsbedingungen zur Informationsweiterverwendung"
  (their text is shown inside the application and was not seen). Statistik Austria - "Creative Commons
  Namensnennung 4.0 International", citation "Datenquelle: Statistik Austria - data.statistik.gv.at".
- Usable for own job search: unclear for the Firmenbuch interface - free and licensed CC BY 4.0, but the key
  comes only with the ministry's approval and an ID Austria; yes for Statistik Austria's file of numbers and
  activity codes (no key, CC BY 4.0).
- High-value dataset: **yes, published as one** - the record is titled "High Value Datasets (HVD) des Firmenbuchs"
  and cites Annex 5 of Regulation 2023/138; Statistik Austria's file is flagged high-value with the Regulation as
  applicable legislation. (On data.europa.eu the Firmenbuch record itself is not flagged, and Austria's category
  "companies and company ownership" holds 49 records that are all procurement-information notices - a labelling
  matter in the catalogue.)
- Volume: not stated. The first 2 MB of Statistik Austria's file held 133,331 companies, numbers up to 398901w,
  and the file goes on.
- Update cycle: interface - current register; the changes operation lists changes by day. Statistik Austria -
  "monatlich", last changed 2026-11-05.
- Seen on 2026-11-28: GET https://justizonline.gv.at/jop/web/iwg -> 200, text/html, 4,395 bytes (an empty
  script page); HEAD and GET of the page's script -> 200, 1,859,253 bytes; GET of its text file -> 200,
  application/json, 203,197 bytes; HEAD and GET of the documentation archive -> 200, application/zip, 313,664
  bytes (one PDF of 13 pages, twelve schemas); the interface itself was not called (no token). Statistik Austria:
  HEAD of the CSV -> 200, text/csv; GET with a 400-byte range -> the server ignored the range and the transfer
  was cut by the client's 2 MB cap (2,000,000 bytes received, the partial file deleted); GET of the metadata ->
  200, application/json, 2,091 bytes. Three data.europa.eu searches -> 200. GET of the ministry's Firmenbuch page
  -> 302, then 200, 33,427 bytes; GET of the e-Justice page -> 200, 78,527 bytes.
- Caveats: a third party (Kyckr, search summary) says the need for an Austrian ID puts the interface "out of
  reach for most non-Austrians"; whether an ID Austria can be had by a non-resident was not looked into. The
  free trade register is a different thing: the Gewerbeinformationssystem GISA
  (https://www.bmwet.gv.at/Themen/Unternehmen/GISA_Gewerbeinformationssystem/GISA_Schnittstelle.html) has a
  free interface - "Für die Verwendung der Schnittstelle sind keine Gebühren oder Kosten zu entrichten", stage 1
  "keine Authentifizierung erforderlich", stage 2 with a key obtained by "Bürgercard bzw. Handysignatur" - but it
  "erfüllt daher ausschließlich den Zweck der Validierung" and offers no "Massenabfragen wie Branchen- oder
  Gründerlisten". GET -> 200, 199,553 bytes.

### Applicant-tracking vendors seen in the country

| Vendor | Local or international | Public feed for an employer's board (format, key?) | Documentation URL | Basis for "used here" |
|---|---|---|---|---|
| eRecruiter | Austrian (the documentation's examples are Linz and Vienna) | XML and RSS, no key mentioned: "There are some routes available on the applicant-portal to generate different kind of feeds", pattern `(http\|https)://my.portal.url/Syndication/{format}` - `Syndication/Xml`, `Syndication/Rss`, `Syndication/Xml/All` ("Load all published jobs in a chronological descending order"); parameters `channel`, `filter`, `jobProfiles`, `regions`, `format`, `culture`; tags `id`, `name`, `description`, `requirements`, `location`, `region`, `jobCountry`, `jobZipCode`, `occupationType`, `url`, `applyUrl`, `dateSinceOnline`, `dateOfUpdate`, `publishedOn`. "The XML-Feed is used to publish jobs to 3rd-Party applications" | https://erwin.atlassian.net/wiki/spaces/ERECRUITER/pages/262570/Job+Feed (page updated 6 March 2023) | Two Austrian public employers publish feeds of exactly this pattern as open data on data.gv.at: Stadt Linz (`jobs.linz.at/Syndication/...`) and Bundesrechenzentrum (`www.brz-jobs.at/Syndication/...`). Also named in the ICR ranking 2026 reported by Haufe (see the Germany file) |
| Personio, softgarden, d.vinci, JOIN | German or not read | See this pass's Germany file: Personio XML without key; softgarden, d.vinci and JOIN only with the employer's key or token | there | Not established for Austria |

The AMS says of its HR-API that "Integrationspartner" among recruiting-software makers keep adding it, without
naming them on the page read. No market-share source for Austria was found.

### Links to employers' own pages
- AMS "alle jobs": adverts crawled from employers' sites are shown only as a pointer - source in "gefunden bei",
  link "zum externen Stellenangebot" - which is exactly a list of employers' own advert pages; automated reading
  is forbidden by the terms.
- eRecruiter portals: the feed gives `url` and `applyUrl` per job; found only by knowing the employer's portal
  address (two are published: Linz, BRZ).
- karriere.at: "Einzelne Unternehmen verlinken dich für deine Bewerbung auf ihre entsprechende Unternehmensseite";
  automated evaluation forbidden.
- Land Kärnten's catalogue records link to the Land's own advert pages.
- EURES: the vacancy record carries the employer's name, legal ID and website (this study's EU-wide file).
- Firmenbuch: an optional `HOMEPAGE` element exists in the extract schema (see the register block).

### Employer directories
- WKO Firmen A-Z (Austrian Economic Chambers), https://firmen.wko.at : the chambers' members. Per the WKO's FAQ
  (13.04.2026, https://www.wko.at/service/faq-firmen-a-z) the address comes from the trade authority ("Die Adresse
  zu Ihrer Gewerbeberechtigung wird von der zuständigen Behörde übermittelt") and firms add the rest themselves
  ("Ergänzen Sie Ihre Kontaktdaten, Firmenlogos, Bilder, Videos und vieles mehr") and may hide their entry.
  robots.txt (https://firmen.wko.at/robots.txt): "User-agent: * Allow: /" with filter parameters disallowed
  (`/*branchenname=`, `/*categoryid=`, `/*filter=`, ...), a sitemap index
  (`https://firmen.wko.at/sitemap/sitemap_index.xml`), and a dozen named robots shut out. The directory's own
  terms were not found: the page reached (`nutzungsbedingungen.aspx?inserattypid=1`) holds the terms of the
  chambers' "Nachfolgebörse", which forbid reading other users' content "systematisch [...] (z.B. durch ein
  Programm oder durch bloßes Kopieren)". No entry page was requested, so which fields an entry shows (website,
  e-mail) is from the FAQ only.
- Startup Landscape Austria (BMWET with the Wirtschaftskammer): "Diese Plattform bietet einen tagesaktuellen
  Überblick über das österreichische Startup-Ökosystem. Interessierte können kostenlos durch einfache Such- und
  Filterfunktionen Informationen zu Startups, Investoren sowie Akzeleratoren einsehen."
  (https://www.bmwet.gv.at/Themen/Wirtschaftsstandort-Oesterreich/Startups.html). The platform itself and its
  terms were not opened.
- Statistik Austria's file (above) is not a directory but selects companies by activity: every Firmenbuch number
  with an ÖNACE code, for example 62100.

### Archives of past adverts
**None found.** Looked in: data.europa.eu limited to Austria (the searches above), Zenodo (`q=Stelleninserate`:
1 record, a history book; a wider query returned nothing relevant on its first page), web search, and the AMS
pages read. What exists:
- AMS: no archive of expired adverts; its open data are monthly counts (vacancies by four-digit occupation and
  labour-market district, by education, by ÖNACE, by kind of contract; CSV, CC BY 4.0) - no employer in them. A
  search summary mentions an AMS-internal "Jobfeed" platform of Austrian online adverts (AMS info 339); nothing
  public was found.
- University of Graz, "JobAds" project (FWF P35783): job adverts from digitised newspapers of the national
  library's ANNO corpus, "the Austrian labor market from 1850 to 1950". On Zenodo there is a paper about it
  (record 14943168, CC BY 4.0, two files of 27 kB and 192 kB), not the corpus; a search summary says a corrected
  set of about 12,500 adverts is to be made available. A century too early for picking today's employers.
- The two open feeds (Linz, BRZ) show only live vacancies.
- EU-wide sources are in this study's EU-wide file (topic 8). Paid (search results only): Techmap's Austrian
  job-postings feed on AWS Data Exchange, with data back to January 2020 sold as a one-time purchase.

## Not free or not allowed

- AMS "alle jobs": manual search only; automated mechanisms forbidden; robots.txt closes the application.
- karriere.at, willhaben, Indeed, LinkedIn: automated reading forbidden by their terms (willhaben also in
  robots.txt).
- StepStone.at: scraping for any purpose other than the individual job search forbidden; result lists closed in
  robots.txt.
- Firmenbuch: full extracts and documents outside the free interface are paid (JustizOnline, clearing houses
  called "Verrechnungsstellen"); the free interface needs an approved application and an ID Austria.
- GISA interface: validation of single businesses only, no lists.
- AMS HR-API: for employers sending vacancies in, specification only inside an eAMS account.
- Scrapers of jobs.ams.at, karriere.at, willhaben and firmen.wko.at are sold on apify.com (search results only).

## Gaps

- **AMS**: the number of live vacancies was not read. The eJob-Room's own terms and the AMS job app's terms
  (a separate page) were not read.
- **Jobbörse der Republik Österreich**: imprint, terms, vacancy fields, volume and the WordPress REST interface
  were not examined; the vacancy search's address was not found in the home page's HTML.
- **Linz and BRZ feeds**: not requested, so it is unconfirmed that they answer today, without a key, in the
  documented format. Other eRecruiter customers are not listed anywhere found.
- **Länder and cities**: no portal of a Land or of Vienna was opened (Carinthia is known only from its catalogue
  records). The present catalogue API of data.gv.at was not found; searches ran on data.europa.eu's copy.
- **Boards not checked**: hokify, derStandard Jobs, Metajob, jobs.at, devjobs.at; Indeed's and LinkedIn's
  Austrian pages.
- **Firmenbuch**: the interface was not called; what the short extract really returns (in particular `HOMEPAGE`),
  the load limit, the time the ministry takes to decide, the text of the reuse terms, and whether a non-resident
  can get an ID Austria are all unknown. The WSDL was not fetched. Statistik Austria's file size and row count
  are unknown beyond the first 2 MB.
- **WKO Firmen A-Z**: its terms of use and an entry's fields were not read. **Startup Landscape Austria**: not
  opened. No IT trade association list (e.g. of software companies) was found.
- **Applicant-tracking vendors**: onlyfy (formerly Prescreen) was not examined - no vendor documentation was
  found by search; hokify and others not examined. No evidence on which systems Austrian employers use most.
- **Archives**: Kaggle and Hugging Face were not searched directly for Austrian data; the Graz corpus's
  availability was not established.
