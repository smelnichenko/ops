# Czechia (CZ) - free online job data sources: research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (`curl/8.14.1`, no added headers, one
capped GET per URL, redirects not followed automatically; followed by hand where they led to the same
publisher's own page) and web search for finding pages. No account, key or login was used. Requests made, per
host: data.mpsv.cz 10 (two HEAD, one 6 kB range; the limit for an open-data host), data.europa.eu 2 (plus two
shared with the Poland file), mf.gov.cz 2, dataor.justice.cz 3, docs.recruitis.io 3, www.jobs.cz 2, www.lmc.eu 2
(both redirects), and 1 each to ares.gov.cz, www.almacareer.com (redirect), www.almacareer.legal, www.prace.cz,
www.startupjobs.cz, feedback.startupjobs.cz, portal.isoss.cz (name does not resolve), portal.isoss.gov.cz (403),
www.ictu.cz and ictu.cz (404).

## Takeaway

Czechia has the best free vacancy source of this group: the Labour Office's whole register of published
vacancies as one open-data file on data.mpsv.cz, rebuilt daily, with no key, and declared free of copyright and
of database rights. Each record names the employer with its company number (IČO), the CZ-ISCO occupation, skills,
pay, place, dates and - where the employer gave one - the URL of the employer's own page for the vacancy. Beside
it stands a file of each day's changes, kept since 31 October 2024: a two-year archive of adverts with the same
fields. The business register is as open: ARES answers per company and by search (name, activity code, legal
form) without a key, and the justice ministry publishes the public register in bulk; neither carries a website
or e-mail address for ordinary companies. The commercial boards (Jobs.cz and Prace.cz of Alma Career,
StartupJobs) offer no feed for reading; their product terms are silent on robots and Alma Career's general terms
could not be read by a plain client.

## Sources

### Úřad práce ČR - "Volná místa za celou ČR" (open data of the labour ministry)
- Publisher: Ministerstvo práce a sociálních věcí (MPSV; Ministry of Labour and Social Affairs); provider of
  the data: Úřad práce ČR (Labour Office of the Czech Republic).
- Documentation: https://data.mpsv.cz/web/data/volna-mista-za-celou-cr ; JSON schema
  https://data.mpsv.cz/od/soubory/volna-mista/volna-mista.schema.json ; terms
  https://data.mpsv.cz/web/data/podminky-uziti .
- Data or endpoint: https://data.mpsv.cz/od/soubory/volna-mista/volna-mista.json (also `.jsonld`); a SPARQL
  endpoint https://data.mpsv.cz/sparql/ is listed as a further distribution in the national catalogue (not
  tried).
- Holds: "Datová sada obsahuje volná místa určená ke zveřejnění na portálu JPŘ PSV, která byla schválená
  pracovištěm ÚP ČR." Per record (schema and a sample): `portalId`, `referencniCislo`, `pozadovanaProfese`
  (job title as text), `profeseCzIsco` (CZ-ISCO code), `pozadovanaDovednost` (skills, coded and described),
  `pozadovanaJazykovaZnalost`, `pozadovaneVzdelani`, `mesicniMzdaOd` / `mesicniMzdaDo` with `typMzdy`,
  `pocetMist`, `pocetHodinTydne`, `smennost`, `pracovnePravniVztahy`, `terminZahajeniPracovnihoPomeru`,
  `datumVlozeni`, `datumZmeny`, `expirace`, `upresnujiciInformace` (free text), `mistoVykonuPrace` (workplace
  with address codes), `zamestnavatel.nazev` and **`zamestnavatel.ico`** (employer's name and company number),
  **`urlAdresa`** ("URL adresa zaměstnavatele, kde lze nalézt další informace k danému volnému místu"),
  `prvniKontaktSeZamestnavatelem` (whom and where to contact: name, telephone, e-mail, address),
  `statniSpravaSamosprava` (a post in public administration), flags for foreign workers (`cizinecMimoEu`,
  `zamestnaneckaKarta`, `modraKarta`, `azylant`).
- Access: bulk file (one JSON document, key `polozky`); byte ranges are honoured.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): https://data.mpsv.cz/web/data/podminky-uziti - "Pro všechny
  distribuce všech datových sad v rámci otevřených dat MPSV a ÚP ČR platí následující: Autorské dílo: Distribuce
  datové sady neobsahuje autorská díla. Originální databáze: Distribuce datové sady není autorskoprávně chráněnou
  databází. Zvláštní právo pořizovatele databáze: Distribuce datové sady není chráněna zvláštním právem
  pořizovatele databáze. Osobní údaje: Distribuce datové sady neobsahuje osobní údaje." (last updated 4. 5.
  2022).
- Usable for own job search: yes - open data, no key, declared free of copyright and database rights.
- Volume: the file is 186,523,592 bytes (last modified 2026-11-27 22:05 GMT); the number of records was not
  counted. On EURES 41,094 vacancies had a workplace in Czechia on 2026-11-28 (EU-wide file).
- Update cycle: "Opendatová sada 1x denně".
- Seen on 2026-11-28: GET of the dataset page -> 200, text/html, 94,803 bytes; GET of the schema -> 200,
  application/json, 35,068 bytes; HEAD of the JSON -> 200, application/json, Content-Length 186,523,592; GET of
  bytes 0-5999 -> 206 (first record: `portalId` 67314322, inserted 2026-11-24, a waiter's post, employer with
  IČO, CZ-ISCO 51310, `urlAdresa` null); GET of the terms -> 200, 56,628 bytes. The older address
  `/web/data/volna-mista-v-cr` -> 404.
- Caveats: "Pro některá volná místa zaměstnavatel požaduje zveřejnění bez uvedení informací o zaměstnavateli
  [...] Pro tato volná místa export dat neobsahuje údaje o zaměstnavateli" (no name, IČO, address, URL or place).
  Only vacancies approved by the office and marked for publication are included. Despite the terms' statement,
  records carry contact persons' names and telephone numbers. Period covered: "V závislosti na permanentním
  filtru, nyní 12/2014 - do současnosti". The register holds what employers report to the labour office - by
  the first records, mostly manual and service work; the share of IT posts was not measured.

### Civil-service vacancies: ISoSS portal
- Publisher: Ministerstvo vnitra (Ministry of the Interior), Informační systém o státní službě.
- Data or endpoint: the address in the ministry's pages, https://portal.isoss.cz/ , no longer resolves; the
  portal answers at portal.isoss.gov.cz (the ministry announced the move to the gov.cz domain - search summary).
- Access: web only as far as known; no feed or dataset found by search.
- Licence or terms (exact wording, with URL): not read.
- Usable for own job search: unclear - the portal refused this client and nothing about it could be read.
- Seen on 2026-11-28: GET https://portal.isoss.cz/robots.txt -> no answer (curl error 6, host not found); GET
  https://portal.isoss.gov.cz/robots.txt -> **403** "Forbidden"; the host was dropped.
- Caveats: posts in public administration reported to the labour office are in the MPSV file
  (`statniSpravaSamosprava`).

### Other vacancy datasets in the national catalogue (data.gov.cz, read through data.europa.eu)
- "Přírůstky volných míst za celou ČR" (MPSV): see "Archives of past adverts".
- "Volná místa v ČSÚ" (Czech Statistical Office): its own vacancies as JSON-LD,
  `https://csu.gov.cz/pdi-ws/external/zdroj/statistika/volna-mista`, "continuous".
- "Volná pracovní místa" (Česká obchodní inspekce): CSV and XLSX at
  `http://www.coi.cz/userdata/files/dokumenty-ke-stazeni/open-data/pracovni-mista.csv`.
- "Volná pracovní místa na ÚMČ Praha 8": a web page and one CSV of 2017.
- Each distribution points to its own terms record at data.gov.cz (not opened). None was requested: single
  public employers' own vacancies. Usable for own job search: yes as open data, terms records unread.
- Seen on 2026-11-28: GET of the data.europa.eu search `q=volná pracovní místa`, country cz -> 200,
  application/json, 1,102,362 bytes, 648 hits (most unrelated; the MPSV code lists for the vacancy file are
  also there: "Obory činnosti pro volná místa", "Výhody volného místa", "Typy změn volných míst", "Způsoby
  zveřejnění volného místa").

### Jobs.cz and Prace.cz
- Publisher: Alma Career Czechia s.r.o. (the product terms still name "LMC s.r.o., se sídlem Menclova 2538/2,
  Libeň, 180 00 Praha 8, IČO 26441381"; ARES gives that number's present name as Alma Career Czechia s.r.o.).
- Documentation: "PRODUKTOVÉ PODMÍNKY JOBS.CZ A PRACE.CZ PRO UŽIVATELE", https://www.jobs.cz/poradna/podminky-uziti/
  (in force from 1. 8. 2022); they refer to the general "Podmínky používání Elektronických systémů LMC" at
  https://www.lmc.eu/cs/podminky-pouzivani-sluzeb , which now redirects to
  https://www.almacareer.legal/user/czechia/documents/podminky-pouzivani-elektronickych-systemu-alma-career-pro-uzivatele-ces .
- Data or endpoint: https://www.jobs.cz , https://www.prace.cz ; no feed or API for reading adverts was found.
- Holds: adverts of paying employers. Not examined.
- Access: web only. Registration or key: none to browse. Cost: free for job seekers ("Služba je poskytována ze
  strany společnosti LMC zdarma").
- Licence or terms (exact wording, with URL): the product terms contain no clause on robots, automated reading,
  copying or the database (searched for robot, automat, strojov, skript, databáz, kopírov, stahov). The general
  terms could not be read: the Alma Career legal site returns a script page with no text (5,029 bytes).
  robots.txt: https://www.jobs.cz/robots.txt - all agents: "Disallow: /muj/", "/asmt/", "/api/", "/iapi/",
  "/status/", "/translations/", "/js/", "/nabidky-podle-cv/", "/session-log/", two query addresses;
  https://www.prace.cz/robots.txt - "User-Agent: * Disallow: /auth/ Disallow: /muj/ Disallow: /asmt/ Disallow:
  /hledat/ Disallow: /odpovedni-formular/ Disallow: /presmerovani-na-formular/ Disallow: /odpoved-odeslana/" and
  "Sitemap: https://d2260mt3awrr7p.cloudfront.net/prace.cz/sitemap-index.xml".
- Usable for own job search: unclear - the general terms could not be read; the product terms are silent.
  Prace.cz's robots.txt closes its search pages ("Disallow: /hledat/") to every agent while offering a sitemap;
  Jobs.cz closes only account and API paths.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET https://www.jobs.cz/robots.txt -> 200, text/plain, 349 bytes; GET of the product
  terms -> 200, text/html, 94,477 bytes; GET https://www.lmc.eu/cs/podminky-pouzivani-sluzeb/ -> 308 -> 307 to
  www.almacareer.com -> 308 to www.almacareer.legal -> 200, text/html, 5,029 bytes (title "Alma Career Legal
  Documents", no terms text). GET https://www.prace.cz/robots.txt -> 200, text/plain, 255 bytes.
- Caveats: the same legal site holds Alma Career's terms for its other countries (Slovakia among them), so the
  gap repeats there. Scrapers of Jobs.cz are sold on apify.com (search results).

### StartupJobs.cz
- Publisher: StartupJobs.com s.r.o., Company ID No. 29153786, Prague.
- Documentation: "Terms and Conditions for Users of StartupJobs.cz",
  https://feedback.startupjobs.cz/legal/vop-b2c-en.pdf (in effect from 18 July 2025).
- Data or endpoint: https://www.startupjobs.cz ; no documented feed or API for reading was found.
- Holds: adverts of startups and technology firms. Not examined.
- Access: web only. Registration or key: none to browse. Cost: free for users.
- Licence or terms (exact wording, with URL): the user terms have no clause on robots, scraping, automated
  access or copying of the database (searched for robot, automat, scrap, crawl, script, spider, extract,
  database). robots.txt (https://www.startupjobs.cz/robots.txt), whole file: "User-agent: * Allow: / Allow:
  /admin/onboarding Disallow: /admin/ Disallow: /superadmin/ Sitemap:
  https://www.startupjobs.cz/sitemap_index.xml".
- Usable for own job search: unclear - the terms are silent on automated reading; robots.txt admits every agent
  to everything but the admin paths.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, 143 bytes; GET of the terms PDF -> 200, application/pdf, 84,592
  bytes.
- Caveats: the Czech version of the terms and the terms for companies were not read.

### No Fluff Jobs (Czech edition)
- The Polish board's Czech edition (`/cz/`): its robots.txt closes `/cz/posting/` and `/api/` to every agent -
  see this study's Poland file. Usable for own job search: no (same clause).

### EURES
- 41,094 vacancies with a workplace in Czechia on 2026-11-28 (EU-wide file). The MPSV record has no EURES
  field; how the Labour Office passes vacancies on was not read.

### Official vacancy statistics
- Skipped by the brief.

## Through the employers

### Business register
- Publisher: Ministerstvo financí (Ministry of Finance) for ARES, the Administrative Register of Economic
  Subjects, which joins the public register kept by the courts (VR), the trade register (RŽP), the statistical
  register (RES) and others; Ministerstvo spravedlnosti (Ministry of Justice) for the open data of the public
  register.
- Documentation: ARES - https://mf.gov.cz/cs/ministerstvo/informacni-systemy/ares (updated 31.8.2026), with the
  API specification `AresRestApi-verejne` (OpenAPI, "ARES: REST API - veřejné - verze 1.4.0", generated 20
  August 2026, https://mf.gov.cz/assets/attachments/2023-08-01_AresRestApi-verejne_v08.zip) and a technical
  catalogue (PDF, 2.7 MB, not downloaded). Public register - https://dataor.justice.cz/ (a script page) and its
  API `https://dataor.justice.cz/api/3/action/...`.
- Data or endpoint: ARES - `https://ares.gov.cz/ekonomicke-subjekty-v-be/rest/ekonomicke-subjekty/{IČO}` (one
  subject), `POST .../ekonomicke-subjekty/vyhledat` (search), and the same pair per source register
  (`-vr`, `-res`, `-rzp`, `-ros`, ...). Public register - `http://dataor.justice.cz/api/file/<set>.csv.gz` (also
  `.xml.gz`, `.csv`, `.xml`), sets named `<legal form>-<full|actual>-<court>-<year>`.
- Holds:
  - ARES, per subject (seen): `ico`, `obchodniJmeno`, `pravniForma`, `datumVzniku`, `datumAktualizace`, `dic`
    (tax number), `sidlo` (registered office), `czNace` (activity codes), `seznamRegistraci` (state in each
    source register: `AKTIVNI`, `ZANIKLY`, `NEEXISTUJICI`), `adresaDorucovaci`. The search filter takes a name,
    numbers, an address, `pravniFormaRos` and `czNace` ("CZ-NACE_2025 ekonomického subjektu - kód"), with paging
    (`start`, `pocet`). The statistical-register record has `kategoriePoctuPracovniku` (size class by number of
    workers). **No website, e-mail or telephone for ordinary companies**: the specification has contact fields
    (`www`, `email`, `telefon`) only in the records of health-care providers (NRPZS) and schools (RŠ).
  - Public register sets, per the record read: "spisová značka, právní forma, název, sídlo, identifikační číslo,
    statutární orgán, [...] základní kapitál, [...] předměty činnosti / podnikání"; optional: branches, EUID,
    liquidation, insolvency. No contact fields named.
  - Against the eight minimum attributes: ARES carries all eight (status per source register; the Member State
    as `kodStatu`). Beyond them: the size class; no website or e-mail.
- Access: ARES - **API, one subject per request, and search with filters**; no bulk file of ARES itself was
  found. Public register - **bulk files** by legal form, court and year.
- Registration or key: none for either.
- Cost: free.
- Licence or terms (exact wording, with URL): ARES - "Služby může využívat každý, pokud bude respektovat podmínky
  provozu. Jsou nastaveny určité limity pro počty dotazů, které může jeden uživatel do ARES poslat." The
  ministry may restrict users who, among other things, "odešlou k vyřízení více než 500 dotazů za minutu",
  "opakovaně posílají stejné dotazy", "obcházejí povolené limity využíváním dotazování z většího množství IP
  adres" or "automatizovaně propátrávají databázi náhodnými údaji"; "Všechny informace zpřístupněné systémem ARES
  mají pouze informativní charakter". No licence is named on the page. Public register - no licence field in the
  dataset record; terms not read.
- Usable for own job search: yes for ARES (open to everyone within the stated limits, no key); yes for the
  public-register files (official open data without a key; licence wording not read).
- High-value dataset: not established as one. On data.europa.eu Czechia has 284 datasets flagged high-value,
  none of them under "Basic company information: key attributes" (the two records there are Slovak); whether
  the Czech national catalogue flags ARES or the public register was not checked.
- Volume: public register - 9,496 sets (about 40 legal forms x "full" and "actual" x 7 courts x the years
  2005-2026). ARES - not stated.
- Update cycle: public register sets "DAILY"; ARES `datumAktualizace` per subject.
- Seen on 2026-11-28: GET `https://ares.gov.cz/ekonomicke-subjekty-v-be/rest/ekonomicke-subjekty/26441381` ->
  200, application/json, 4,708 bytes (Alma Career Czechia s.r.o., CZ-NACE 78100 and others); GET of the ARES
  page -> 200, 199,774 bytes; GET of the specification zip -> 200, 22,210 bytes (one JSON of 333,972 bytes, 26
  operations). GET https://dataor.justice.cz/ -> 200, 2,114 bytes (script shell); GET
  `.../api/3/action/package_list` -> 200, application/json, 276,667 bytes, 9,496 names; GET
  `.../package_show?id=as-actual-praha-2026` -> 200, 3,713 bytes (four files, frequency "DAILY", publisher
  "MSP").
- Caveats: the ARES search was not called (a POST with a filter); its result limit was not read. No file of the
  public register was opened, so its columns are known from the record's description only.

### Applicant-tracking vendors seen in the country

| Vendor | Local or international | Public feed for an employer's board (format, key?) | Documentation URL | Basis for "used here" |
|---|---|---|---|---|
| Recruitis.io | Czech (the application's own paths and change log are in Czech) | JSON API at `https://app.recruitis.io/api2/`, **token needed**: "The documentation is based on authorization using a token"; an employer can issue a `public_access` token ("A token with mostly read-only privileges. This token can be publicly exposed, for example when using JavaScript"), optionally tied to a domain whitelist. No keyless feed is documented | https://docs.recruitis.io/api/ (specification at `docs/openapi/openapi.yaml`, 457,828 bytes) | The vendor's own documentation; no market-share source |

No employer's board and no vendor data endpoint was requested. Teamio (Alma Career's own system) was not
examined.

### Links to employers' own pages
- The MPSV vacancy file: `urlAdresa` per vacancy - the employer's own page for the post, where given (null in
  the first record seen; the share filled was not measured) - plus contact e-mail addresses, whose domains point
  to employers' sites.
- ARES and the public register: no website field for ordinary companies.
- Prace.cz: a sitemap index is named in robots.txt (not requested).
- EURES: the vacancy record carries the employer's name, legal ID and website (EU-wide file).

### Employer directories
- ARES search by activity code (`czNace`, e.g. 62) and legal form is the nearest thing to a free directory:
  names, numbers and addresses, no websites.
- The MPSV file itself lists every employer with a published vacancy, by name and IČO.
- ICT Unie (the ICT industry association): the member list was not found at the address tried (GET
  https://www.ictu.cz/clenove/ -> 301 -> 404). No other directory was opened.

### Archives of past adverts
- **"Přírůstky volných míst za celou ČR"** (MPSV, same terms as the vacancy file): one file per day with "Záznamy
  vložené, změněné nebo zrušené v den uvedený v názvu souboru", in the same structure as the main file
  (employer name and IČO, CZ-ISCO, skills, place, dates). Directory
  `https://data.mpsv.cz/od/soubory/volna-mista-prirustek/` lists `volna-mista-prirustek-YYYY-MM-DD.json` (and
  `.json.gz`, `.jsonld`, `.jsonld.gz`) for **562 days from 2024-10-31 to 2026-11-27** (of 758 calendar days: some
  days are missing, e.g. only 4 files for December 2024). The file for 2026-11-27 is 360,408 bytes gzipped.
  Documentation https://data.mpsv.cz/web/data/prirustky-volnych-mist-za-celou-cr , schema
  `.../volna-mista-prirustek/volna-mista-prirustek.schema.json` (not fetched). Usable for own job search: yes.
  Seen on 2026-11-28: GET of the page -> 200, 95,858 bytes; GET of the directory listing -> 200, text/html,
  236,715 bytes; HEAD of the latest `.json.gz` -> 200. No increment file was opened, so how a cancelled vacancy
  is marked is not confirmed.
- The main file itself reaches back: live vacancies carry their insertion date, "nyní 12/2014 - do současnosti".
- Nothing else was found (no search of Kaggle, Zenodo or the Czech research repositories was made).

## Not free or not allowed

- No Fluff Jobs (Czech edition): adverts' pages and API closed to every robot in robots.txt.
- Prace.cz: search pages closed to every robot in robots.txt.
- ISoSS portal: HTTP 403 to this client (a technical refusal).
- Recruitis boards: readable only with a token the employer issues.
- Nothing of the official data (vacancy file, ARES, public register) is paid or keyed.

## Gaps

- **MPSV file**: record count, the share of records with `urlAdresa` or without employer data, and the share of
  IT posts were not measured (the file is 186 MB; only its first 6 kB were read). The SPARQL endpoint was not
  tried. The Labour Office's own search pages (uradprace.cz) and their terms were not looked at.
- **Alma Career's general terms** (for Jobs.cz and Prace.cz): unreadable for a plain client; whether they forbid
  robots is unknown.
- **ISoSS**: not readable; whether it has a feed is unknown.
- **Boards not checked**: Profesia.cz, Práce za rohem, Indeed's and LinkedIn's Czech pages, Jooble.
- **ARES**: search limits and the bulk question (the 2.7 MB technical catalogue was not read); whether a
  national high-value flag exists. **Public register**: licence and columns unread.
- **Vendors**: only Recruitis' documentation was read; Teamio, Datacruit and others were not examined; no
  evidence on which systems Czech employers use most.
- **Directories**: none confirmed with websites.
- **Archives**: the increment files' content was not sampled.
