# Germany (DE) - free online job data sources: research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (`curl/8.14.1`, no added headers, one
capped GET per URL, redirects not followed automatically), web search for finding pages, and one page
(netzpolitik.org) read through the WebFetch tool. No account, key or login was used. Requests made, per host:
ckan.govdata.de 7 (open data portal), www.unternehmensregister.de 4 (two of them redirects), data.europa.eu 3,
www.arbeitsagentur.de 3, www.service.bund.de 3, interamt.de 3 (two redirects), www.stepstone.de 3 (two
redirects), dev.softgarden.de 3, erwin.atlassian.net 3 (eRecruiter's knowledge base), www.xing.com 2,
www.stellenmarkt.de 2, www.handelsregister.de 2 (one 404), www.ihk.de 2, help.join.com 2 (one redirect),
raw.githubusercontent.com 2, and 1 each to de.indeed.com, www.kleinanzeigen.de, themen.kleinanzeigen.de,
api.karriere.nrw, karriere.nrw, ckan.open.nrw.de, e-justice.europa.eu, offeneregister.de, api.gleif.org,
www.bitkom.org, www.haufe.de, static.dvinci-easy.com, support.dvinci.de (403), www.personio.de (429),
www.startbase.de (403), netzpolitik.org. `rest.arbeitsagentur.de` (the job search's data endpoint) was not
requested: the agency's terms forbid it (below). LinkedIn was not requested (terms read once for this study's
France file).

## Takeaway

Germany's largest vacancy database, the Bundesagentur für Arbeit's Jobsuche, is free to use by hand and closed to
programs: the agency publishes no API documentation, the interface a community project documents is the web
app's own back end, and the terms of use - changed on 10 November 2026 in exactly this paragraph - forbid
"Robots, Webspider oder ähnliche Technologien" and the unauthorised use of programming interfaces to read the
portal's content. What a program may read is the public sector: service.bund.de publishes an RSS feed of the
federal, Länder and municipal vacancies it holds (500 newest items, about two days' worth, most of them imported
from Interamt), and North Rhine-Westphalia's Karriere.NRW has a documented open-data JSON API (981 vacancies,
Datenlizenz Deutschland - Namensnennung 2.0). Among commercial boards only the small stellenmarkt.de offers
reading feeds (RSS, ten items per field); Indeed, Kleinanzeigen and LinkedIn forbid bots outright, StepStone's
and XING's terms could not be read on their German sites. For the employer route Germany is poor ground: the
commercial register is free since 1 August 2022 but only one company at a time through a web search (no bulk
file, no API, a stated limit of 60 retrievals an hour per third parties), it is not among Germany's published
high-value datasets, and the one open copy (OffeneRegister.de) is a snapshot from about 2018-2019.

## Sources

### Bundesagentur für Arbeit - Jobsuche (public employment service)
- Publisher: Bundesagentur für Arbeit (BA; Federal Employment Agency).
- Documentation: none from the agency for reading vacancies. Terms: https://www.arbeitsagentur.de/nutzungsbedingungen .
  Employers' and partners' upload interface: https://www.arbeitsagentur.de/unternehmen/arbeitskraefte/hr-ba-xml-schnittstelle .
  Third party: the community project bundesAPI documents the web app's back end,
  https://github.com/bundesAPI/jobsuche-api (README read from raw.githubusercontent.com), and opens with: "bietet
  die Bundesagentur für Arbeit dafür bis heute keine offizielle API an."
- Data or endpoint: https://www.arbeitsagentur.de/jobsuche/ (web). Per the community README (third party, not
  requested): `https://rest.arbeitsagentur.de/jobboerse/jobsuche-service/pc/v6/jobs` (also `/pc/v4/jobs`,
  `/pc/v4/app/jobs`), details at `/pc/v4/jobdetails/{base64(refnr)}`, sent with the web app's own client id as
  header `X-API-Key: jobboerse-jobsuche`.
- Holds: vacancies placed by employers, by private placement agencies and by temporary-work firms (the search
  has a filter for each of the two), and external adverts. Fields per the community README (third party): search
  filters `was`
  (title), `wo` (place), `umkreis`, `berufsfeld`, `arbeitgeber`, `angebotsart` (1 work, 2 self-employment,
  4 training, 34 internship/trainee), `befristung`, `arbeitszeit` (full time, part time, shift, home office,
  mini-job), `veroeffentlichtseit` (0-100 days), `zeitarbeit`, `pav`; in the detail record
  `stellenangebotsTitel`, `stellenangebotsBeschreibung`, `referenznummer`, `arbeitgeberKundennummerHash`; "Externe
  Stellenanzeigen können ein `externeUrl`-Feld in der Suchantwort enthalten."
- Access: web pages only, as far as the agency documents it. The HR-BA-XML interface is for sending vacancies
  in, under a cooperation agreement and a client certificate ("Sie haben mit der BA eine Kooperationsvereinbarung
  abgeschlossen"; "Neben Arbeitgebenden können auch Stellenbörsen, Öffentlich-rechtliche Institutionen (ÖR) sowie
  zugelassene kommunale Träger (zkT) die HR-BA-XML-Schnittstelle nutzen. Dafür stehen jeweils eigene
  Kooperationsmodelle zur Verfügung."). No open-data dump, no feed.
- Registration or key: none to search by hand. The back end expects the web app's client id (community README);
  no key is issued to the public.
- Cost: free ("Die Nutzung des Portals ist unentgeltlich.").
- Licence or terms (exact wording, with URL): https://www.arbeitsagentur.de/nutzungsbedingungen , section 2a(3):
  "Aktivitäten, die nicht dem vorgesehenen Nutzen des Portals und der Apps dienen und zu einer hohen Belastung
  der Infrastruktur führen können, sind zu unterlassen. Es ist insbesondere nicht zulässig: Robots, Webspider
  oder ähnliche Technologien einzusetzen[;] unautorisiert Kommunikations- bzw. Programmierschnittstellen
  einzurichten oder zu nutzen und so Inhalte des Portals oder der Apps zum Zweck der Datensammlung und
  -auswertung auszulesen oder darüber Inhalte/Daten in das Portal oder den Apps einzuspielen[;]
  Sicherheitsmaßnahmen zu umgehen oder zu durchbrechen". Section 4: "Die BA behält sich vor, bei missbräuchlicher
  Nutzung des Portals oder der Apps Schadenersatzansprüche gegen Verursacher geltend zu machen." Section 3: "Das
  Urheberrecht an dem Portal, der dahinterliegenden Struktur des Portals, der Inhalte des Portals [...] liegt in
  seiner Gesamtheit bei der BA." The page's change history lists, for 10.11.2026: "2a Nutzung des Portals -
  Anpassung Absatz 3", "4 Maßnahmen und Schadensersatz - Ergänzung des 3. Absatzes", "6b Nutzungsrechte [...] -
  Inhaltliche Anpassung". robots.txt (https://www.arbeitsagentur.de/robots.txt), whole file: "User-agent: *
  Disallow: Allow: /" and three sitemaps.
- Usable for own job search: no - a ban on bots and on unauthorised use of the interfaces: "Es ist insbesondere
  nicht zulässig: Robots, Webspider oder ähnliche Technologien einzusetzen" and "unautorisiert Kommunikations-
  bzw. Programmierschnittstellen einzurichten oder zu nutzen und so Inhalte des Portals [...] auszulesen".
  (By hand the search is free and open to everyone.)
- Volume: not read from the agency. A search engine's copy of the job search page carries the title "738.908
  Jobs" (undated). On EURES 660,831 vacancies had a workplace in Germany on 2026-11-28 (this study's EU-wide file).
- Update cycle: continuous.
- Seen on 2026-11-28: GET /nutzungsbedingungen -> 200, text/html, 165,259 bytes; GET /robots.txt -> 200,
  text/plain, 208 bytes; GET of the HR-BA-XML page -> 200, 96,955 bytes; GET of the community README -> 200,
  5,503 bytes. No request to `rest.arbeitsagentur.de`.
- Caveats: the agency's stance is on record since 2021: asked about the community documentation it said the
  interface was "nur für eine komfortablere Suche und für registrierte Nutzer:innen eingerichtet" and not "für
  einen massenhaften Zugriff bzw. eine massenhafte Auswertung mit technischen Mitteln konzipiert", and it added
  captchas (netzpolitik.org, 30 November 2021, third party, read through a summarising tool). At least nine
  scrapers of this interface are listed on apify.com (search results), one titled "Official API"; the agency
  offers no such thing. The agency's
  separate statistics API (https://statistik.arbeitsagentur.de/DE/Navigation/Service/API/API-Start-Nav.html ,
  search result, not requested) serves aggregate figures only.

### service.bund.de - vacancies of the federal, Länder and municipal administrations
- Publisher: Bundesverwaltungsamt (Federal Office of Administration); the feed's editor address is
  redaktion-support@bva.bund.de.
- Documentation: none read for the feed (the site's footer names pages "RSS-Feeds" and "Open Data"; neither was
  requested - the three requests were spent). Imprint: https://www.service.bund.de/Content/DE/Service/Impressum/impressum_node.html
- Data or endpoint: RSS https://www.service.bund.de/Content/Globals/Functions/RSSFeed/RSSGenerator_Stellen.xml ;
  web search under https://www.service.bund.de/Content/DE/Stellen/Suche/ (closed to robots, below).
- Holds: vacancies that authorities enter themselves or that are imported from partner portals. Per item: title,
  link to the advert's page on service.bund.de, publication date, and in the description the employer
  ("Arbeitgeber"), postcode and place ("Ort"), application deadline ("Bewerbungsfrist") and end of publication
  ("Veröffentlichungsende"). No salary, no description text, no occupation code in the feed.
- Access: feed (RSS 2.0, `<ttl>60</ttl>`), web pages.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): imprint: "Das Copyright für Texte und Bilder liegt bei eigenen
  Inhalten beim Bundesverwaltungsamt. Bei den Inhalten anderweitiger Anbieter verbleibt das Copyright bei der
  einstellenden Behörde. Auf dem Portal zur Verfügung gestellte Texte, Textteile, Grafiken, Tabellen oder
  Bildmaterialien dürfen, soweit diese urheberrechtlich geschützt sind, ohne vorherige Zustimmung des
  Bundesverwaltungsamtes nicht vervielfältigt, nicht verbreitet und nicht ausgestellt werden." and "service.bund.de
  ist als reine Bekanntmachungsplattform analog einer Litfaßsäule konzipiert, eine Langzeitarchivierung von
  Stellenangeboten, Ausschreibungen und Behördendaten erfolgt nicht." robots.txt
  (https://www.service.bund.de/robots.txt), all agents: "Disallow: /Content/DE/Behoerden/Suche/", "Disallow:
  /Content/DE/Stellen/Suche/", "Disallow: /Content/DE/Ausschreibungen/Suche/", "Disallow: /SiteGlobals/" (three
  sub-paths allowed), "Crawl-delay: 30".
- Usable for own job search: yes - the publisher's own RSS feed, no key, no clause against automated reading; the
  search pages are closed in robots.txt and a 30-second crawl delay is asked.
- Volume: the feed holds the 500 newest items; today they span 26 November 10:47 to 28 November 14:00, so about
  two days. Total live vacancies not read (a third-party site speaks of about 1,200 job offers on average; not
  confirmed).
- Update cycle: continuous (feed built on request: `lastBuildDate` equalled the time of the request).
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 281 bytes; GET of the feed -> 200, text/xml, 342,242
  bytes, 500 items - by the path of their links 347 imported from Interamt, 93 entered in the site's own editor,
  33 under `stellenmarkt_nrw`, 17 `bundeswehr`, 8 `bpol`, 1 `dwd`, 1 `stadt-nue` (employer "Stadt Nürnberg"); GET
  of the imprint -> 200, 21,341 bytes.
- Caveats: to keep all vacancies a program must read the feed at least daily (500 items are about two days). No
  advert page was requested, so the apply path and whether the page links on to the authority are unknown. The
  imprint's copyright clause restricts copying and distribution of protected content without consent.

### Interamt - public-service job portal
- Publisher: not read today (a search summary names DVZ Datenverarbeitungszentrum Mecklenburg-Vorpommern GmbH
  as operator; not confirmed).
- Documentation: none found.
- Data or endpoint: https://interamt.de/koop/app/ (web application).
- Holds: vacancies of federal, Länder and municipal employers. Not examined.
- Access: web only as far as seen; its adverts also appear in the service.bund.de feed (347 of today's 500 items).
- Registration or key: not established. Cost: free to browse.
- Licence or terms (exact wording, with URL): terms not read (see Seen). robots.txt (https://interamt.de/robots.txt,
  last modified 7 March 2025): "User-agent: * Disallow: /cms/"; YandexBot, Jooblebot, AhrefsBot and MJ12bot
  "Disallow: /koop/*"; facebookexternalhit and meta-externalagent "Disallow: /*".
- Usable for own job search: unclear - the terms could not be read; robots.txt leaves the application path open
  to unnamed agents.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 283 bytes; GET / -> 302 to /koop/app/ ; GET /koop/app/
  -> 302 to `/koop/app/?wicket-crypt=...` (a session address; not followed, third request spent).
- Caveats: the site is a session-bound web application; no feed or API was found by search.

### Karriere.NRW - open-data API of North Rhine-Westphalia's public-service vacancies
- Publisher: Ministerium der Finanzen des Landes NRW (publisher), Landesamt für Finanzen NRW (contact), on
  Open.NRW; harvested by GovData and data.europa.eu.
- Documentation: https://karriere.nrw/karriere.nrw-opendata-api.pdf ("Karriere.NRW: RESTful API (JSON) zur
  Bereitstellung von Stellenangeboten als OpenData", "Stand: 04.09.2020", 6 pages); catalogue record
  https://ckan.open.nrw.de/dataset/0aa5b729-bddd-4dc8-a4dc-e19622bf19ad .
- Data or endpoint: search `https://api.karriere.nrw/v1.0/opennrw/suche` (GET; documented parameters `text`,
  `ort`, `umkreis`, `laufbahngruppe`, `arbeitszeit`, `taetigkeitsfeld` - value 3 is "IT und Telekommunikation" -,
  `benefits`); detail `https://api.karriere.nrw/v1.0/opennrw/stellenausschreibungen/<uuid>`.
- Holds: "Aktuell auf Karriere.NRW ausgeschriebene Stellen der Landes- und Kommunalverwaltungen
  Nordrhein-Westfalens" - only externally advertised posts that the portal's editors released as open data
  (documentation). Search record as returned today: `uuid`, `title`, `authority`, `contracting_authority`,
  `deadline`, `published`, `jobtype`, `location`, `careergroup`, `fixedterm`, `benefit`, `careerfield`,
  `workingtime`, `employer`, `target_group`, `apprenticeship_type`. Detail record per the documentation:
  `titel_der_stelle`, `stellenbeschreibung` (HTML), `ergaenzende_inhalte`, `anzahl_offener_stellen`,
  `erscheinungsdatum`, `bewerbungsfrist`, `laufbahngruppe`, `besoldung_entgelt` (pay groups), `befristung`,
  `arbeitszeit`, `ansprechpartner` (name, e-mail, telephone), `jetzt_bewerben` ("Link oder Email zum Bewerben"),
  address, coordinates, `url` (the advert on karriere.nrw).
- Access: API (JSON), paged (10 records a page).
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): "Datenlizenz Deutschland Namensnennung 2.0"
  (`http://dcat-ap.de/def/licenses/dl-by-de/2.0`, catalogue record). Documentation: "Drittanbieter und
  Interessierte können über diese API die Stellenangebote des Stellenmarkt.NRW in eigene Anwendungen und Portale
  integrieren und erhöhen damit die Reichweite der Stellenangebote."
- Usable for own job search: yes - an open-data API under an attribution licence, offered for use in third
  parties' applications.
- Volume: `count` 981, `pages` 99 on 2026-11-28.
- Update cycle: continuous (newest record published 2026-11-28).
- Seen on 2026-11-28: GET of the search without parameters -> 200, application/json, 4,445 bytes, 10 records; GET
  of the documentation -> 200, application/pdf, 143,438 bytes; GET of the Open.NRW record -> 200, 6,494 bytes.
- Caveats: one Land only, public sector only. Today's field names (English) differ from the 2020 documentation
  (German: `titel_der_stelle`, `ausschreibende_behoerde`, `results_count`); the detail call was not requested,
  so its present fields are unconfirmed.

### GovData and data.europa.eu - vacancy datasets
- Publisher: GovData (the national open data portal); each dataset belongs to its authority.
- Documentation: https://www.govdata.de ; CKAN API `https://ckan.govdata.de/api/3/action/package_search`.
- Holds: for vacancies, one usable dataset - Karriere.NRW (above). `q=Stellenangebote` -> 2 records (Karriere.NRW
  and "Jobcenter", a geodata layer of Kreis Borken); `q=Stellenausschreibungen` -> 2 (Karriere.NRW and a Saxon
  equal-opportunities table); `q=Stellenanzeigen` -> 1 ("Auswertung der Stellenanzeigen des Fachportals
  H-Soz-Kult", an analysis, not listings); `title:Stellen*` -> 37, staffing plans ("Stellenplan") and statistics
  apart from Karriere.NRW; `q=Stellenbörse` -> 0. No dataset of the Bundesagentur's vacancies.
- On data.europa.eu: `q=Stellenangebote` limited to Germany -> the same 2 records (catalogue `govdata`).
- Access: catalogue API; no key. Cost: free. Licence: per dataset.
- Usable for own job search: yes for what is there (Karriere.NRW); nothing else found.
- Seen on 2026-11-28: six GovData searches -> 200, application/json; one data.europa.eu search -> 200, 58,663 bytes.
- Caveats: keyword searches only; a municipal vacancy feed under another title would be missed.

### StepStone.de
- Publisher: The Stepstone Group Deutschland GmbH, Düsseldorf (name and seat from a search summary of the terms).
- Documentation: terms at https://www.stepstone.de/ueber-stepstone/rechtliche-hinweise/nutzungsbedingungen/ (not
  read, see Seen); a search summary names a current PDF "Nutzungsbedingungen_Stepstone_06.11.2025.pdf".
- Data or endpoint: https://www.stepstone.de ; no feed or API for reading adverts is offered.
- Holds: adverts of paying employers. Not examined.
- Access: web only. Registration or key: none to browse. Cost: free for candidates.
- Licence or terms (exact wording, with URL): not read on the German site. From a search summary of the German
  terms (version of 27.04.2022): "Die diesen Nutzungsbedingungen unterstehenden Dienstleistungen sind nur für die
  individuelle Arbeitssuche natürlicher Personen als Angestellte oder Freiberufler vorgesehen." The group's
  Austrian terms, read today (this pass's Austria file), forbid in 4.3.4 "Scraping- oder vergleichbare Techniken
  zu benutzen, um Inhalte zu erfassen und für einen anderen Zweck zu verwenden, wieder zu veröffentlichen oder
  auf andere Art als den vorgesehenen Zweck der Dienstleistungen zu nutzen". robots.txt
  (https://www.stepstone.de/robots.txt, "last updated 06 08 26") opens: "Any other use of robots or failure to
  obey the robots exclusion standards set forth at <http://www.robotstxt.org/wc/exclusion.html> is strictly
  prohibited."; for all agents it disallows among others "/?*", "/*?*", "/5/ergebnisliste.html",
  "/5/resultlistpage", "/5/jobapply", "/public-api/", "/jobagent/", "/search-results", "/listing",
  "*/application/", "/jobs/*?*" (with "Allow: /jobs/*?q=*" and "Disallow: /jobs/*?q*&*").
- Usable for own job search: unclear - the German terms could not be read; the group's wording elsewhere ties
  its scraping ban to other purposes than the individual job search, and robots.txt closes result lists and
  nearly every address with a query string.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 3,250 bytes; GET of the terms address -> 301 to
  /ueber-stepstone/nutzungsbedingungen/ ; GET of that -> 301 to
  /ueber-stepstone/rechtliche-hinweise/nutzungsbedingungen-2021-08-05/ (not followed: third request spent).
- Caveats: the second redirect points at a page named after the terms of 5 August 2021 while a search summary
  shows a version of 6 November 2025; which one is in force was not established.

### Indeed (Germany)
- Publisher: Indeed (the contracting entity depends on the user's country).
- Documentation: https://de.indeed.com/legal ("Letzte Aktualisierung: 29. Juni 2026").
- Data or endpoint: https://de.indeed.com ; no reading API (this study's EU-wide file).
- Holds: adverts posted on Indeed and adverts it collects from employers' sites. Not examined.
- Access: web only. Registration or key: none to browse. Cost: free for job seekers.
- Licence or terms (exact wording, with URL): "Als Jobsuchender dürfen Sie die Website und deren Inhalte für Ihren
  persönlichen, nicht kommerziellen Zweck der Jobsuche oder Suche nach Informationen im Zusammenhang mit Ihrer
  Jobsuche nutzen." Forbidden: "ein beliebiges automatisiertes System (Bots, Scraper, Spider, KI oder agentische
  KI) verwenden, um ohne die ausdrückliche schriftliche Erlaubnis von Indeed auf die Website zuzugreifen,
  Data-Mining durchzuführen oder Inhalte an die Website zu übermitteln [...] (wir erteilen die Erlaubnis zum
  Crawlen der Website ausschließlich wie in unserer Datei robots.txt beschrieben). Sie dürfen keinen Teil der
  Website crawlen, scrapen, Daten extrahieren, reproduzieren, duplizieren, kopieren [...]". On applying: "Die
  Verwendung von Automatisierung, Scripting oder Bots zur Automatisierung des Indeed Bewerbungsprozesses,
  abgesehen von den offiziellen Anbietern und den Tools von Indeed, ist untersagt."
- Usable for own job search: no - "ein beliebiges automatisiertes System (Bots, Scraper, Spider, KI oder
  agentische KI) [...] ohne die ausdrückliche schriftliche Erlaubnis von Indeed".
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET https://de.indeed.com/legal -> 200, text/html, 661,388 bytes. One request to Indeed by
  this pass (a host this study's production neighbour names); robots.txt not requested.
- Caveats: the German page is dated 29 June 2026; this study's France file recorded the French page as "1er
  avril 2026". Either the French page was older or it was misread; not resolved here.

### XING
- Publisher: XING (New Work SE, Hamburg - from memory and search results, not read today).
- Documentation: https://www.xing.com/terms (rendered by script; the HTML returned to this client holds no
  terms text).
- Data or endpoint: https://www.xing.com/jobs/ ; no public reading feed found.
- Holds: job adverts; XING also indexes adverts found by its own crawler (search summary of a trade-press
  article). Not examined.
- Access: web only. Registration or key: none seen for the job search; an account for most other use. Cost: free tier.
- Licence or terms (exact wording, with URL): terms not read. robots.txt (https://www.xing.com/robots.txt): for
  all agents "Disallow: /jobs/search/", "Disallow: /jobs/search?*", "Disallow: /graphql/", "Disallow:
  */external-application", "Disallow: /xing-one/api"; a separate group for "GPTBot", "GPTUser", "ClaudeBot",
  "Claude-User", "Claude-SearchBot", "PerplexityBot", "Perplexity-User" reads "Allow: /jobs/search/" and "Allow:
  /jobs/search?*".
- Usable for own job search: unclear - the terms could not be read; robots.txt closes the job search to
  ordinary robots and opens it to seven named AI agents.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 5,576 bytes; GET /terms -> 200, text/html, 50,579
  bytes, no terms text in it.
- Caveats: none beyond the above.

### Kleinanzeigen (jobs section)
- Publisher: Kleinanzeigen (legal entity not read).
- Documentation: https://themen.kleinanzeigen.de/nutzungsbedingungen/ ("Diese Nutzungsbedingungen gelten ab dem
  17. Februar 2024.").
- Data or endpoint: https://www.kleinanzeigen.de (category "Jobs"); no reading feed (robots.txt disallows
  `/s-feed.rss`).
- Holds: classified adverts, among them job offers of small employers. Not examined.
- Access: web only. Registration or key: none to browse. Cost: free.
- Licence or terms (exact wording, with URL): § 5: the user must refrain from "ohne die ausdrückliche
  schriftliche Zustimmung von Kleinanzeigen Crawler, Spider, Scraper oder andere automatisierte Mechanismen zu
  nutzen, um auf die Kleinanzeigen-Dienste zuzugreifen und Inhalte zu sammeln" and from copying adverts beyond
  "die bestimmungsgemäße Nutzung". robots.txt (https://www.kleinanzeigen.de/robots.txt): long disallow list for
  all agents (search, result pages from page 6 on, `/s-feed.rss`); "OAI-SearchBot", "GPTBot", "ChatGPT-User" and
  "PerplexityBot" get "Allow: /".
- Usable for own job search: no - "ohne die ausdrückliche schriftliche Zustimmung von Kleinanzeigen Crawler,
  Spider, Scraper oder andere automatisierte Mechanismen zu nutzen".
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, 11,256 bytes; GET of the terms -> 200, text/html, 80,826 bytes.
- Caveats: none.

### LinkedIn (Germany)
- Same agreement as recorded in this study's France file (`FR-France.md`, User Agreement "Effective on November
  3, 2025", section 8.2).
- Usable for own job search: no - "Develop, support or use software, devices, scripts, robots or any other means
  or processes (such as crawlers, browser plugins and add-ons or any other technology) to scrape or copy the
  Services". No request was made by this pass.

### stellenmarkt.de - RSS feeds per occupational field
- Publisher: stellenmarkt.de (operator not read).
- Documentation: https://www.stellenmarkt.de/rss.php ("Job-Feeds/RSS").
- Data or endpoint: one feed per field, `https://www.stellenmarkt.de/rss/smrssbf<N>.xml` - for example
  https://www.stellenmarkt.de/rss/smrssbf6.xml ("IT-Telekommunikation"), `smrssbf5.xml` ("Ingenieur - und
  technische Berufe"), `smrssbf1.xml` ("Controlling / Rechnungswesen").
- Holds: per item title, link to the advert on stellenmarkt.de, a teaser of about 300 characters, guid. No
  employer field, no place field, no date.
- Access: feed (RSS 2.0). Registration or key: none. Cost: free.
- Licence or terms (exact wording, with URL): the feed page: "Aktuelle Jobangebote auf Ihrer Homepage? Binden Sie
  unsere Job-Feeds ein! Jeden Tag aktualisieren wir unsere Job-Feeds, die Sie als sogenannte "RSS-Channel" in
  ihre Homepage integrieren können." Terms of use and robots.txt not read.
- Usable for own job search: yes - feeds the publisher offers for embedding, no key; small.
- Volume: 10 items in the IT feed. Update cycle: daily, per the page.
- Seen on 2026-11-28: GET /rss.php -> 200, text/html, 24,430 bytes; GET of the IT feed -> 200, application/xml,
  6,387 bytes, 10 items.
- Caveats: ten items a field is a sample of the board, not its content; how many adverts the board holds was
  not read.

### Arbeitnow (one line)
- A Berlin job board with a keyless JSON API, in practice all German postings; described in this study's
  EU-wide file (topic 4). Not requested by this pass (a host the production neighbour's files name).

### Official vacancy statistics
- Skipped by the brief. The agency's statistics API is named under the Jobsuche block's caveats.

## Through the employers

### Business register
- Publisher: the register courts of the Länder (Handelsregister, with the Genossenschafts-, Partnerschafts-,
  Gesellschafts- and Vereinsregister), reached through the Länder's common portal handelsregister.de (service
  point at Amtsgericht Hagen); and the Unternehmensregister, run by Bundesanzeiger Verlag GmbH, Cologne.
- Documentation: https://www.handelsregister.de/rp_web/welcome.xhtml ; https://www.unternehmensregister.de/de ;
  Germany's own description on the European e-Justice Portal,
  https://e-justice.europa.eu/topics/registers-business-insolvency-land/business-registers-eu-countries/de_de
  ("Letzte Aktualisierung: 09/10/2025").
- Data or endpoint: web search only - handelsregister.de "Normale Suche" and "Erweiterte Suche";
  unternehmensregister.de "Schnellsuche" (company name or EUID).
- Holds: per company the register entry and the filed documents. The e-Justice page: entries concern "die
  Existenz eines Unternehmens, d.h. seine Errichtung und Beendigung (etwa durch Auflösung, Abwicklung oder
  Liquidation und Löschung), seine Vertretungsverhältnisse [...], die Haftungsverhältnisse" and changes of
  shareholders of a GmbH; search is by name or keywords, place of establishment or seat, register type, number
  and court, and in the advanced search by address. Read against the eight minimum attributes, these descriptions
  cover the name, the registration number with its court, the legal form (a search criterion), seat and address
  (search criteria), establishment and termination (entered facts) and, trivially, the Member State. None of
  them mentions an activity code such as NACE, a website, an e-mail address, a telephone number or a head-count.
  No extract was opened, so this is what the publishers describe, not what a record was seen to hold.
- Access: **one company per request, through a web form; no bulk file and no API.** The portal's start page
  offers only the two searches and the register announcements, and warns: "Aktuell kommt es durch hohe
  Abrufzahlen im Registerportal wiederholt zu Überlastungen einzelner Bundesländer und als Folge davon zur
  temporären Nichtverfügbarkeit bei Abrufen von Daten aus diesen Ländern." and "Soweit in den Ländern
  strukturierte Informationen zum Abruf zur Verfügung gestellt werden, handelt es sich um einen unverbindlichen
  Service." The Unternehmensregister's terms mention a "Großkundenschnittstelle" for connected "Datenverarbeiter"
  (large-customer interface; conditions not published on the page).
- Registration or key: none for searching and for retrieving register entries and documents; registration at
  the Unternehmensregister only for paid retrievals.
- Cost: free. e-Justice page: "Jeder kann in das Handels- und Unternehmensregister Einsicht nehmen, ohne dass ein
  besonderes Interesse nachgewiesen werden muss." and "Registerauszüge und im Handelsregister gespeicherte
  Dokumente wie Satzungen, Gesellschaftsverträge etc. können kostenfrei in elektronischer Form beim
  Registerportal abgerufen werden." and "Auch der Abruf von Rechnungslegungsunterlagen im Unternehmensregister
  ist kostenfrei, lediglich für den Abruf hinterlegter Bilanzen von Kleinstunternehmen entsteht eine Gebühr in
  Höhe von EUR 1,00 je Bilanz." It dates the change to 1 August 2022 ("In Umsetzung der Digitalisierungsrichtlinie
  erfolgt seit dem 1. August 2022 die Offenlegung von Registereintragungen bereits mit ihrer erstmaligen
  Abrufbarkeit über das Registerportal.").
- Licence or terms (exact wording, with URL): the portal's "Nutzungsordnung" could not be read: the address third
  parties cite (https://www.handelsregister.de/rp_web/information.xhtml) answers 404 to a plain request (the
  portal is a session-bound application). Third parties on its content: the community project
  bundesAPI/handelsregister - "wobei es unzulässig ist, mehr als 60 Abrufe pro Stunde zu tätigen (vgl.
  Nutzungsordnung)"; IHK Köln - "Seitens des Registerportals ist der unbegrenzte Zugriff auf die Registerdaten
  bereits jetzt dadurch erschwert, dass die Zahl der Anfragen auf 60 pro Stunde begrenzt ist und pro Anfrage kein
  Dokumentenpaket [...] sondern nur einzelne Dokumente heruntergeladen werden können."; a vendor's blog, quoted
  in a search summary - "Systematische Abrufe, um parallele Voll- oder Teilregister aufzubauen, auszubauen oder
  zu aktualisieren, sind unzulässig." OffeneRegister.de says of the official site: "Gesamt-Download: Nein",
  "Programmier-Schnittstelle: Nein", "Freie Weiterverwendung: Nein, in Nutzungsbedingungen ausgeschlossen".
- Usable for own job search: unclear - looking one company up by hand is free and open to everyone; the usage
  rules could not be read at the source, and third parties report a cap of 60 retrievals an hour and a ban on
  systematic retrieval. As a list of employers it cannot serve: there is no bulk file.
- High-value dataset: **not published as one.** On data.europa.eu Germany has 18,084 datasets flagged as
  high-value, 6 records (5 distinct) in the category "Unternehmen und Eigentümerschaft von Unternehmen", and none
  of them comes from a register court or a justice ministry: a Hamburg INSPIRE layer of industrial installations
  (twice), two truck-parking offers and a 3-D aircraft model from the Mobilithek portal, and "Gewerberegister der
  Stadt Oldenburg" - one city's trade register (XLSX and CSV, Datenlizenz Deutschland - Namensnennung 2.0;
  columns described: company name, address of the establishment in Oldenburg, self-described activity in free
  text), whose record says: "Die Veröffentlichung erfolgt aufgrund einer gesetzlichen Verpflichtung gemäß der
  EU-Durchführungsverordnung 2023/138." GovData's search for "Gewerberegister" finds one more, the city of Hamm
  (a map service).
- Volume: not stated on the pages read. Update cycle: entries are public from the moment they can be retrieved.
- What is free instead, in bulk:
  - **OffeneRegister.de** (Open Knowledge Foundation Deutschland with OpenCorporates), https://offeneregister.de/ :
    the whole register as a download - line-delimited JSON "~ 250 MB als bzip2", SQLite "~740 MB als gzip" - and a
    SQL API; "Die Daten können unter der Creative Commons Attribution License 4.0 mit Attribution an
    OpenCorporates weiterverwendet werden." The page describes the content as "Daten zum Sitz, Rechtsform und
    vertretungsberechtigten Personen" and carries no date of the data; OpenSanctions (search summary) calls it
    "recent until end of 2018", and the press coverage found is from 2019. So: free, bulk, about eight years old,
    not updated. Files not downloaded.
  - **GLEIF** (the global LEI register, not German and not complete): 244,086 active records with a legal address
    in Germany in the golden copy of 2026-11-28; fields include legal name, legal and headquarters address, the
    register reference (`registeredAt`, `registeredAs`, e.g. "HRB 96340"), legal form and status; no website
    field. Keyless API `https://api.gleif.org/api/v1/lei-records`; licence not re-read today.
  - Commercial products (search results only, not examined): handelsregister.ai, companydata.com, North Data,
    OpenRegister, Implisense, and scrapers on apify.com.
- Seen on 2026-11-28: GET of the portal's start page -> 200, text/html, 50,253 bytes; GET
  /rp_web/information.xhtml -> 404, 1,071 bytes; GET https://www.unternehmensregister.de/ureg/ -> 308, then 307,
  then /de -> 200, 574,168 bytes; GET of its general terms
  (https://www.unternehmensregister.de/i18n-doc/D061_UReg_nutz_0118_de.pdf) -> 200, application/pdf, 216,373
  bytes (no clause on automated retrieval found in it; it deals with filings and fees); GET of the e-Justice
  page -> 200, 74,020 bytes; GET https://offeneregister.de/ -> 200, 24,674 bytes; two data.europa.eu searches ->
  200; GET of the GLEIF API (one record) -> 200, application/vnd.api+json, 2,991 bytes; GET of the IHK Köln page
  -> 200, 32,615 bytes.
- Caveats: no search was run on the register and no extract opened, so the field list rests on descriptions.
  Whether Germany reports a company dataset under Regulation 2023/138 somewhere other than GovData was not
  established; a search summary of a Bundesrat paper of May 2023 mentions talks between the federal justice
  ministry and the Länder on "Massenabrufe" (not read).

### Applicant-tracking vendors seen in the country

| Vendor | Local or international | Public feed for an employer's board (format, key?) | Documentation URL | Basis for "used here" |
|---|---|---|---|---|
| Personio | German | XML, no key: "Current open job postings can be retrieved in XML format under `myaccount.jobs.personio.de/xml`" - as recorded in this study's EU-wide file, whose pass opened the page today; not opened again by this pass | https://developer.personio.de/docs/retrieving-open-job-positions | Not established: the vendor's customer page (https://www.personio.de/kunden/) answered 429 ("Vercel Security Checkpoint"); host dropped |
| eRecruiter | Austrian (the documentation's examples are Linz and Vienna) | XML and RSS, no key mentioned: "There are some routes available on the applicant-portal to generate different kind of feeds", pattern `(http\|https)://my.portal.url/Syndication/{format}` - `Syndication/Xml`, `Syndication/Rss`, `Syndication/Xml/All` ("Load all published jobs in a chronological descending order"); tags include `name`, `description`, `requirements`, `location`, `region`, `jobCountry`, `url`, `applyUrl`, `dateSinceOnline`, `occupationType` | https://erwin.atlassian.net/wiki/spaces/ERECRUITER/pages/262570/Job+Feed (page updated 6 March 2023) | ICR ranking 2026 as reported by Haufe (below): second place for employers with 51-100 hires a year |
| softgarden | German (documentation at dev.softgarden.de; seat not read) | JSON API "Frontend API v3" ("Jobs of a Channel", "Single Job by ID"), **key needed**: "Newer API clients are so called Public Clients that do not need a client secret anymore. [...] Else you use the Basic Authorization method." - a client ID issued for the employer's channel | https://dev.softgarden.de/frontend-v3/authentifizierung/ | ICR ranking 2026 (Haufe): third place for 101-500 hires a year |
| d.vinci | German (seat not read) | REST API `https://{customer}.dvinci-hr.com/restApi/` with a "Job Publications API", **key needed**: "For authentication it is required to pass custom HTTP-Headers for every request. Dvinci-API-User [...] Dvinci-API-Token"; no keyless feed in the reference | https://static.dvinci-easy.com/files/d.vinci%20rest-api.html (version 1.74) | ICR ranking 2026 (Haufe): first place for 101-500 and for over 500 hires a year |
| JOIN | not read | REST API `https://api.join.com/v3` (e.g. `/v3/jobs`), **key needed**: "To validate your API requests, JOIN requires an API token", "available only on the Advanced and Enterprise plans" | https://help.join.com/integrations-and-api/api-documentation | Not established from a source read today |

Basis: Haufe, "HR-Software: Die besten Bewerbermanagementsysteme 2026" (7 October 2026),
https://www.haufe.de/personal/hr-management/hr-software-die-besten-bewerbermanagement-systeme_80_471524.html ,
reporting the yearly test of the Institute for Competitive Recruiting (ICR) in which "über 3.500 Recruiterinnen
und Recruiter die gängigsten Systeme" rate their system. It is a satisfaction ranking, not a market-share table.
It names, besides the rows above, Coveto, Recruitee, Beesite, Workday, On Apply, SmartRecruiters and MHM; their
documentation was not opened by this pass (Recruitee, Workday and SmartRecruiters are in the EU-wide file).
No source with market shares was found.

### Links to employers' own pages
- Karriere.NRW API: the detail record documents `jetzt_bewerben` ("Link oder Email zum Bewerben"), `url` and the
  contact person's e-mail. Free to read (above). Public employers of one Land only.
- Bundesagentur Jobsuche: per the community README an external advert can carry `externeUrl` in the search
  answer - the one large source of links to employers' own adverts, and closed to programs by the terms.
- service.bund.de feed: links go to the portal's own advert pages; the employer is named in the item. Whether
  the advert page links to the authority's site was not checked.
- EURES: the vacancy record carries the employer's name, legal ID and website (this study's EU-wide file); for
  Germany that is the Bundesagentur's data passed on.
- Employers' boards themselves: an eRecruiter portal's feed gives `url` and `applyUrl`; a Personio feed gives
  the positions (EU-wide file). Both are found only by knowing the employer's portal address.
- stellenmarkt.de feeds link to the board's own pages.

### Employer directories
- Bitkom (digital industry association), member list https://www.bitkom.org/Bitkom/Mitgliedschaft/Mitgliederliste :
  company names by letter (`?letter=`), with marks for new and associated members; **no website or address in
  the list** (no outbound company link in the page's HTML). Terms not read. GET -> 200, 101,520 bytes.
- Chambers of commerce (IHK): no national directory; each chamber decides. IHK Berlin: "Die
  Unternehmensdatenbank firmen.berlin wurde zum 01.12.2025 eingestellt und ist nicht mehr abrufbar."
  (https://www.ihk.de/berlin/ueber-uns/unternehmensdatenbank-2257214 , GET -> 200). A search summary says the
  Ostthüringen chamber's free database ends with 2025. Other chambers not checked.
- Startbase (start-ups; Startup-Verband and Börse Stuttgart, per search summaries "über 11.000 registrierte
  Unternehmen", registration free): GET https://www.startbase.de/tos/ -> **403**; host dropped, terms not read.
- Open municipal trade registers (Oldenburg, above) name businesses with address and activity, city by city,
  without websites.

## Not free or not allowed

- Bundesagentur für Arbeit Jobsuche: robots, web spiders and unauthorised use of its interfaces forbidden by the
  terms (2a(3), changed 10 November 2026); damages reserved. Feeds only inward, for partners with a cooperation
  agreement and certificate (HR-BA-XML).
- Indeed, Kleinanzeigen, LinkedIn: automated reading forbidden by their terms.
- StepStone.de: robots.txt closes result lists and query addresses and declares any other use of robots
  "strictly prohibited"; terms not read.
- Handelsregister: no bulk file, no API; per third parties 60 retrievals an hour and no systematic retrieval.
  Named commercial resellers exist (not examined).
- softgarden, d.vinci, JOIN: job data only with the employer's key or token.
- Refused a plain client today: www.personio.de (429, security checkpoint), support.dvinci.de (403, "Just a
  moment..."), www.startbase.de (403).
- Scrapers of the Bundesagentur's interface, of StepStone, stellenmarkt.de and handelsregister.de are sold on
  apify.com (search results only).

## Gaps

- **Bundesagentur**: the number of live vacancies was not read from the agency (the page is script-built and the
  data endpoint was not requested). Whether the agency would authorise a personal program on request was not
  asked. The cooperation models for job boards (what flows back to partners) are not published on the page read.
- **service.bund.de**: the "RSS-Feeds" and "Open Data" pages named in the footer were not read (request cap), so
  further feeds (by Land, by field) and any open-data statement are unknown; no advert page was opened.
- **Interamt**: nothing read beyond robots.txt (session redirects); terms, volume and any feed unknown.
- **StepStone.de**: terms not read (two redirects used up the cap). **XING**: terms not readable without a
  browser. **meinestadt.de, Jobware, stellenanzeigen.de, Monster.de, Yourfirm, HeyJobs, GermanTechJobs**: not
  checked.
- **Länder and municipal portals** other than Karriere.NRW (Bavaria, Baden-Württemberg, Berlin, Hamburg and the
  rest): no feed or dataset found by search; none requested. A Berlin authority's page embeds an RSS feed of the
  Land's career portal (search summary); its address was not found.
- **Karriere.NRW**: detail endpoint not requested; present field names unconfirmed.
- **Business register**: the Nutzungsordnung was not read at the source (404 for a plain request); the 60-an-hour
  limit and the ban on systematic retrieval are third-party statements. No register search was run, so the
  fields (in particular: no NACE code, no website) rest on descriptions. OffeneRegister's data date is a
  third-party statement; its files were not opened. GLEIF's licence was not re-read.
- **Applicant-tracking vendors**: Personio's documentation was not re-opened and its customer page refused the
  client; d.vinci's support article on its "Job Publication API" answered 403; rexx systems, Coveto, Beesite,
  onlyfy, BITE, Haufe/umantis, SAP SuccessFactors and others were not examined (no vendor documentation found or
  opened). No market-share source.
- **Employer directories**: none with websites was verified; Startbase refused the client.
- **Indeed**: the date of the terms differs between this file (29 June 2026, German page) and the France file
  (1 April 2026, French page).
