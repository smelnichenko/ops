# Poland (PL) - free online job data sources: research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (`curl/8.14.1`, no added headers, one
capped GET per URL, redirects not followed automatically; a redirect was followed by hand only where it stayed on
the same site) and web search for finding pages. No account, key or login was used. Requests made, per host:
api.dane.gov.pl 7, oferty.praca.gov.pl 3, grupapracuj.pl 3 (one a redirect, one refused by the 2 MB cap),
www.praca.pl 3 (one refused by the cap), dane.biznes.gov.pl 3 (two redirects), akademia.biznes.gov.pl 2,
api-krs.ms.gov.pl 2, api.stat.gov.pl 2 (one HEAD), data.europa.eu 2, zenodo.org 2, nabory.kprm.gov.pl 2,
rekrutacje.gov.pl 2 (both failed on the certificate), www.olx.pl 2, erecruiter.pl 2, sodapl.com 2, aplikuj.pl 2
(apex and www), piit.org.pl 2 (www and apex), and 1 each to pomoc.olx.pl, prs.ms.gov.pl, traffit.com,
api.traffit.com, www.pracuj.pl (403), nofluffjobs.com and justjoin.it. The last two are read by the production
system on this address: one request each, to robots.txt, none to their data paths.

## Takeaway

Poland's labour offices publish every vacancy in one system, ePraca (the former Central Job Offers Base, CBOP), and
the ministry offers the whole set through a free web service - but not to a private person: access is granted on a
signed application by a Polish-registered entity, for one of three purposes (an employment agency republishing,
research, the labour offices themselves), from a fixed IP address, between 17:00 and 07:00. The service's records
would be exactly what the employer route needs (employer name, NIP, REGON, website, occupation), so the terms are
the obstacle, not the data. The large commercial boards give nothing for programs: No Fluff Jobs closes its
adverts and API in robots.txt, aplikuj.pl bans scraping and bots in its terms, Pracuj.pl answers a plain client
with a Cloudflare challenge, and the terms of Pracuj.pl and Praca.pl could not be read (files over the 2 MB cap).
The employer route is well served: the National Court Register (KRS) has an open API with no key and no limits
(CC0) that returns, per company, name, legal form, NIP, REGON, address, activity codes and - where the company
filed them - its website and e-mail address; it has no search and no bulk file, only a daily list of changed
numbers. The Polish applicant-tracking vendor Traffit documents a public JSON feed of each customer's adverts
that needs no key. No free archive of past adverts with employer identifiers was found.

## Sources

### ePraca (formerly CBOP) - job-offer web service of the labour offices
- Publisher: Ministerstwo Rodziny, Pracy i Polityki Społecznej (Ministry of Family, Labour and Social Policy),
  for the public employment services (Publiczne Służby Zatrudnienia, PSZ: county and voivodeship labour offices).
- Documentation: dataset "Oferty pracy PSZ" on the national open data portal,
  https://dane.gov.pl/pl/dataset/538 (API record https://api.dane.gov.pl/1.4/datasets/538); its resources:
  "Warunki udostępniania przez Ministerstwo Rodziny Pracy i Polityki Społecznej ofert pracy upowszechnianych w
  ePraca" (PDF, 88,582 bytes, dated 2026-11-02,
  `https://api.dane.gov.pl/media/resources/20261102/Warunki_udostępniania_przez_Ministerstwo_Rodziny_Pracy_i_Polityki_Społecznej_ofert_pracy_upowszechnianych_w_ePraca.pdf`)
  and "Instrukcja pobierania danych z CBOP" (PDF, 24 pages, dated Warsaw 30 November 2020,
  https://api.dane.gov.pl/media/resources/20210315/instrukcja_pobierania_danych_z_cbop.pdf).
- Data or endpoint: SOAP web service `https://oferty.praca.gov.pl/integration/services/oferta` (WSDL at `?wsdl`);
  a second version with a language choice at `.../integration/services/v2/oferta`.
- Holds: every active offer of the labour offices, as zipped JSON files of at most 1,000 offers each, for the
  whole country, one voivodeship or one labour office; in Polish, English, Ukrainian, Belarusian or Russian. The
  2020 instruction lists 166 fields, among them: `stanowisko` (job title), `zakresObowiazkow` (duties), `zawod`
  ("Nazwa zawodu wg klasyfikacji zawodów i specjalności"), required and desired occupations, skills, languages
  and licences with code details, `rodzajZatrudnienia`, `wynagrodzenieBrutto`, place of work down to street,
  `dataDodaniaOferty`, `ofertaWaznaDo`, `dataAktualizacji`, `identyfikatorOferty`, `link` ("Link do oferty w
  bazie CBOP") - and on the employer: `pracodawca` (name), `nip`, `regon`, `adresWww` ("Adres WWW
  pracodawcy"), `profilDzialanosci`, address, `sposobAplikowania` (through the labour office 'U', directly to
  the employer 'P', to an agency 'A' ...), contact person, telephone and e-mail. Employer details are present
  only where the employer agreed to publication (`publikowacDanePracodawcy`).
- Access: API (SOAP request, answer is a base64 zip of JSON files). No bulk file is published.
- Registration or key: a partner name issued by the ministry (`<Partner>`; without it the answer is
  "Niepoprawna autoryzacja"). To get it, the terms must be filled in, signed "podpisem potwierdzonym profilem
  zaufanym lub kwalifikowanym podpisem elektronicznym osoby reprezentującej Podmiot/ Publiczne Służby
  Zatrudnienia" and e-mailed to apiepraca@praca.gov.pl, stating name, NIP, REGON, KRS, the fixed IP address
  ("Stały adres IP sprzętu komputerowego, z którego realizowany będzie dostęp do usługi WebService") and the
  purpose. Not self-service: "Ministerstwo nada dostęp do usługi WebService dla systemu ePraca Podmiotowi/ PSZ,
  który/e spełnia/ją warunki formalne".
- Cost: free ("dostęp do ofert pracy z systemu ePraca jest bezpłatny").
- Licence or terms (exact wording, with URL): the catalogue record states CC BY 4.0 with the added condition
  "Zakres odpowiedzialności określono w załączniku pt. "Warunki udostępniania informacji o ofertach pracy z
  CBOP"". The terms of 2026-11-02 (URL above): § 1.10 "Podmiot zagraniczny, który nie ma nadanych numerów
  identyfikacyjnych: NIP, REGON lub KRS nie jest uprawniony do ubiegania się o nadanie dostępu do usługi
  WebService dla systemu ePraca."; § 1.6: an entity that means to collect and publish the offers must hold an
  entry in the register of employment agencies (KRAZ); § 1.7: an entity processing them "wyłącznie w celach
  naukowych/ badawczych" needs none; § 5.1 point 13 offers three purposes to choose from - (a) collected and
  published by an employment agency, (b) "wyłącznie w celach naukowych lub badawczych i nie będą publikowane",
  (c) processed by or for the PSZ; § 2.2: do not alter the offers, "publikować wyłącznie aktualne oferty pracy",
  mark each published offer with the ePraca logo; § 3.1: downloads only "w godzinach od 17:00 do 07:00 każdego
  dnia"; § 3.2: state of the system at 16:00; § 3.3: "nie więcej niż 20 zapytań w danym cyklu udostępniania";
  § 4.7: an offer whose employer did not agree to dissemination outside ePraca is not shared (except for
  research and PSZ users).
- Usable for own job search: no - for approved applicants only: "Podmiot zagraniczny, który nie ma nadanych
  numerów identyfikacyjnych: NIP, REGON lub KRS nie jest uprawniony do ubiegania się o nadanie dostępu do usługi
  WebService dla systemu ePraca", and the form admits only three purposes (agency publishing, research, the
  labour offices).
- Volume: not stated in the documents read. On EURES 15,122 vacancies had a workplace in Poland on 2026-11-28
  (this study's EU-wide file).
- Update cycle: daily ("Codziennie" in the record; the service serves the state at 16:00).
- Seen on 2026-11-28: GET of the dataset search and of the resource list on api.dane.gov.pl -> 200,
  application/vnd.api+json (record modified 2026-11-02, 5,489 views, 2,703 downloads, four resources); GET of
  the terms PDF -> 200, application/pdf, 88,582 bytes, 5 pages; GET of the instruction PDF -> 200, 439,944
  bytes; GET `https://oferty.praca.gov.pl/integration/services/oferta?wsdl` -> 200, text/xml, 4,781 bytes
  (service `CbopOferta`, operation `Dane`, address `https://oferty.praca.gov.pl/integration/services/oferta`).
  The service itself was not called (no partner name).
- Caveats: the instruction on the portal is the CBOP one of 2020; the new terms name an "Instrukcja pobierania
  danych z systemu ePraca" as their annex, which is not among the record's files, so the field list may have
  changed with the move to ePraca. The legal basis cited is new (act of 20 March 2025 on the labour market and
  employment services). The address the instruction used to have on the portal
  (`https://oferty.praca.gov.pl/portal/instrukcja_pobierania_danych_z_cbop.pdf`) now returns the ePraca web
  application's HTML instead (200, text/html, 85,523 bytes, last modified 2026-11-20).

### ePraca - the web portal
- Publisher: as above.
- Documentation: none found for reading the portal by program.
- Data or endpoint: https://oferty.praca.gov.pl/portal/ (a script-built application, title "ePraca").
- Holds: the same offers, for people. Not examined (no vacancy data in the HTML received).
- Access: web only. Registration or key: none to search. Cost: free.
- Licence or terms (exact wording, with URL): not found. https://oferty.praca.gov.pl/robots.txt -> 404 (no
  robots.txt).
- Usable for own job search: unclear - no terms of the portal could be read; the ministry's documented way for
  programs is the web service above, which is closed to private persons.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: see the block above (one page, robots.txt, the WSDL - three requests, the limit for the
  host).
- Caveats: third parties sell scrapers of the portal's own search interface on apify.com (search results); not
  tested and not a documented interface.

### Civil-service vacancies: nabory.kprm.gov.pl, replaced by rekrutacje.gov.pl
- Publisher: Kancelaria Prezesa Rady Ministrów (Chancellery of the Prime Minister), Civil Service Department.
- Documentation: none for reading by program.
- Data or endpoint: https://nabory.kprm.gov.pl/ (old base); https://rekrutacje.gov.pl/ (new system).
- Holds: recruitment notices of government offices; search by office, place, status ("Aktywne" / "Archiwalne -
  ogłoszenia o pracę, w których minął już termin na składanie dokumentów"), remote recruitment, open to
  foreigners; results of recruitments. Each notice also exists as a PDF (search results show
  `https://nabory.kprm.gov.pl/<voivodeship>/<town>/<title>,<number>,v7.pdf`).
- Access: web only; no feed or API found in the page.
- Registration or key: none to read. Cost: free.
- Licence or terms (exact wording, with URL): none read. https://nabory.kprm.gov.pl/robots.txt, whole file:
  "User-agent: * Disallow:" (nothing closed).
- Usable for own job search: unclear - robots.txt closes nothing, no terms were found; the base is being wound
  down and the new system could not be reached.
- Volume: "Liczba ofert pracy 24 w 23 urzędach, w 22 miejscowościach" on the old base.
- Update cycle: the old base takes no new notices: "UWAGA! Od 6 listopada nowe ogłoszenia o naborach będą
  publikowane tylko w nowym systemie rekrutacje.gov.pl. Wyniki naborów ogłoszonych w dotychczas działającej
  bazie będą tutaj dostępne do przyszłego roku." (notice of 03.11.2026).
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 23 bytes; GET / -> 200, text/html, 51,123 bytes. GET
  https://rekrutacje.gov.pl/robots.txt and GET https://rekrutacje.gov.pl/ -> no answer: curl error 60 ("SSL
  certificate problem: unable to get local issuer certificate"); verification was not switched off, the host was
  dropped.
- Caveats: rekrutacje.gov.pl is therefore undescribed here - feed, terms and volume unknown.

### Vacancy datasets on dane.gov.pl
- "Oferty pracy PSZ" (dataset 538): the web service above.
- "Oferty pracy Urzędu Miasta Poznania i jednostek organizacyjnych" (dataset 292), publisher Urząd Miasta
  Poznania: formats json and xml, type "api", update "Codziennie", CC BY 4.0, source page
  http://bip.poznan.pl/bip/oferty-pracy/ ; record created 2016-08-22, resources last changed 2019-09-04. One
  city's own vacancies. Usable for own job search: yes (CC BY 4.0) - whether the address still answers was not
  tested.
- "Siemianowice Śląskie: Oferty pracy" (dataset 38085): one xlsx, CC BY 4.0, changed 2026-02-09. Not opened.
- A title search for the phrase "oferty pracy" returned these three and no other; a free-text search for the
  same words returned 1,270 records, mostly unrelated. On data.europa.eu no Polish dataset carries the
  high-value flag at all (one facet request for PL, CZ, SK, HU and SI together: only SK and CZ have flagged
  records).
- Seen on 2026-11-28: GET `https://api.dane.gov.pl/1.4/datasets?title[phrase]=oferty pracy&per_page=50` -> 200,
  7,620 bytes, 3 records.

### Pracuj.pl
- Publisher: Grupa Pracuj S.A., ul. Prosta 68, 00-838 Warszawa (KRS 0000913770).
- Documentation: users' terms "REGULAMIN świadczenia usług drogą elektroniczną w ramach serwisów należących do
  Grupy Pracuj S.A.", https://grupapracuj.pl/prywatnosc/regulamin , which links one PDF
  (https://grupapracuj.pl/file/fc438d2b-fd43-4a47-abb1-0fc5039532b3, file name
  `Regulamin_GP_22092026_FINAL.pdf`).
- Data or endpoint: https://www.pracuj.pl ; no feed or API for reading adverts was found.
- Holds: adverts of paying employers. Not examined.
- Access: web only; a plain program is refused. Registration or key: none to browse. Cost: free for job seekers.
- Licence or terms (exact wording, with URL): not read - the terms PDF is 3,066,698 bytes, over this pass's
  2 MB cap, and was not downloaded.
- Usable for own job search: unclear - the terms could not be read; the site itself answered this client with a
  Cloudflare challenge.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET https://www.pracuj.pl/robots.txt -> **403**, text/html, 5,359 bytes ("Just a
  moment...", Cloudflare managed challenge); the host was dropped after this one request. GET
  https://grupapracuj.pl/grupa-kapitalowa/regulamin -> 301 to /prywatnosc/regulamin -> 200, text/html, 26,499
  bytes (title and one link, no terms text); GET of the PDF -> refused by the cap (Content-Length 3,066,698,
  last modified 2026-09-08).
- Caveats: Grupa Pracuj's site lists its brands: Pracuj.pl, Robota.ua, the:protocol, No Fluff Jobs, eRecruiter,
  softgarden, Kadromierz, worksmile, absence. Scrapers of Pracuj.pl are sold on apify.com (search results); one
  listing says the site "uses anti-bot protection".

### OLX Praca (jobs section of OLX.pl)
- Publisher: Grupa OLX sp. z o.o., Poznań.
- Documentation: "Regulamin Serwisu OLX.pl" in force from 13 March 2026, with annex 1 "OLX Praca" (PDF, 490,777
  bytes, https://pomoc.olx.pl/olxplhelp/sfc/servlet.shepherd/document/download/069Wy00000MFKzdIAH ; the help
  centre's "Aktualny regulamin" article was not opened). A partner API exists for posting and managing adverts
  (developer.olx.pl, search result; not opened).
- Data or endpoint: https://www.olx.pl/praca/ ; no documented feed for reading adverts.
- Holds: classified job adverts. Not examined.
- Access: web only. Registration or key: none to browse. Cost: free.
- Licence or terms (exact wording, with URL): terms 2.3: "Treści publikowane w Serwisie, w tym w szczególności
  Ogłoszenia [...] są przedmiotem ochrony praw własności intelektualnej [...]. Zabrania się jakiegokolwiek
  wykorzystywania tych treści bez pisemnej zgody uprawnionych. Zabrania się jakiegokolwiek agregowania i
  przetwarzania danych oraz innych informacji dostępnych w Serwisie w celu ich dalszego udostępniania osobom
  trzecim w ramach innych serwisów internetowych jak i poza Internetem." The terms contain no clause on robots,
  scripts or automated queries (searched for automat, robot, skrypt, bot, crawl, scrap). robots.txt
  (https://www.olx.pl/robots.txt), all agents: "Disallow: /api/", "Disallow: */ajax/", "Disallow: */rss/",
  "Disallow: /*?q=", ... and "Allow: /api/v1/offers/", "Allow: /api/v1/targeting/", "Allow:
  /api/v1/friendly-links/", "Allow: /".
- Usable for own job search: no - "Zabrania się jakiegokolwiek wykorzystywania tych treści bez pisemnej zgody
  uprawnionych." (a general ban on any use of the adverts' content, not a clause on robots; robots.txt for its
  part admits robots to `/api/v1/offers/`).
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET https://www.olx.pl/robots.txt -> 200, text/plain, 690 bytes; GET
  https://www.olx.pl/regulamin/ -> 404 (162,358 bytes of the site's error page); GET of the terms PDF on
  pomoc.olx.pl -> 200, application/pdf, 490,777 bytes, 8 pages (file name "Regulamin Serwisu OLX od 13 marca
  2026 r..pdf").
- Caveats: the verdict rests on a general intellectual-property clause; a reader who takes that clause to
  concern republication only would call this source "unclear". Annex 1 (OLX Praca) was not read line by line.

### No Fluff Jobs
- Publisher: No Fluff Jobs (a Grupa Pracuj brand per grupapracuj.pl); legal entity not read.
- Documentation: none read; its terms page renders by script (masi's investigation of 2026-11-10).
- Data or endpoint: https://nofluffjobs.com ; no documented feed.
- Holds: IT adverts with salary ranges; editions for Poland, Hungary, Czechia, Slovakia, the Netherlands and
  Ukraine (paths `/pl/`, `/hu/`, `/cz/`, `/sk/`, `/nl/`, `/ua/` in robots.txt). Not examined.
- Access: web only. Registration or key: none to browse. Cost: free for job seekers.
- Licence or terms (exact wording, with URL): https://nofluffjobs.com/robots.txt (last modified 2026-11-06),
  whole file: "User-agent: * Allow: / Disallow: /pdf/ Disallow: /not-found* Disallow: */job/job/* Disallow:
  /api/ Disallow: /posting/ Disallow: /pl/posting/ Disallow: /hu/posting/ Disallow: /ua/posting/ Disallow:
  /cz/posting/ Disallow: /sk/posting/ Disallow: /nl/posting/ Disallow: /ua-ru/posting/ Disallow: /signal".
- Usable for own job search: no - robots.txt, every agent: "Disallow: /api/" and "Disallow: /posting/" (the
  adverts' own pages, in every country edition).
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 300 bytes. Nothing else was requested (host read by
  the production system). The web search tool reported the domain as closed to its own crawler.
- Caveats: the terms of use were not read.

### Just Join IT
- Publisher: Just Join IT sp. z o.o., Gdańsk (search summary of its privacy policy of 14.07.2026; it also runs
  rocketjobs.pl).
- Documentation: terms at https://justjoin.it/terms-and-privacy-policies - not requested: robots.txt closes
  that path to robots. An older terms PDF of 21.04.2020 is indexed at
  `https://public.justjoin.it/Regulamin_Just_Join_IT_21.04.2020.pdf` (search result; not opened).
- Data or endpoint: https://justjoin.it ; no documented feed. robots.txt names seven sitemaps, among them
  `https://justjoin.it/sitemaps/active-jobs.xml` and `https://justjoin.it/sitemaps/top-companies.xml` (not
  requested).
- Holds: IT adverts with salary ranges. Not examined.
- Access: web only. Registration or key: none to browse. Cost: free for job seekers.
- Licence or terms (exact wording, with URL): https://justjoin.it/robots.txt, all agents: "Disallow:
  /oferty-pracy/*,*", "Disallow: /api/", "Disallow: /profile", "Disallow: /terms-and-privacy-policies",
  "Disallow: /pdf/", "Disallow: /devs", "Disallow: /admin/" and technical paths. Advert pages
  (`/job-offer/...`) are not closed.
- Usable for own job search: unclear - the terms were not read; robots.txt closes `/api/` and the terms page but
  leaves the adverts' pages open and lists a sitemap of active jobs.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 715 bytes. Nothing else was requested (host read by
  the production system).
- Caveats: none.

### Praca.pl
- Publisher: Praca.pl Sp. z o.o.
- Documentation: https://www.praca.pl/regulamin.html , which links the terms as a PDF
  (https://www.praca.pl/files/regulation/Regulamin_Serwisu_Praca_06_11_2026.pdf; four older versions listed).
- Data or endpoint: https://www.praca.pl ; no documented feed for reading. The site offers employers a "Widget
  z ofertami pracy".
- Holds: adverts; expired adverts stay reachable ("Oferta pracy jest nieaktualna, zobacz podobne") and are
  listed per employer under `archiwum_...` addresses (search results; not requested).
- Access: web only. Registration or key: none to browse. Cost: free for job seekers.
- Licence or terms (exact wording, with URL): the terms PDF was not read (3,631,037 bytes, over the 2 MB cap).
  Notice at the foot of the terms page: "Wszelkie prawa zastrzeżone. Powielanie, drukowanie, kopiowanie lub
  rozpowszechnianie w jakikolwiek sposób materiałów zawartych na stronach Praca.pl jest zabronione."
  robots.txt (https://www.praca.pl/robots.txt): for all agents only account, application and `/api/` paths are
  closed; a second group names GPTBot, ChatGPT-User, OAI-SearchBot, ClaudeBot, Claude-Web, PerplexityBot,
  Google-Extended, CCBot and anthropic-ai with "Allow: /" and the same short list of closed paths.
- Usable for own job search: no - "Powielanie, drukowanie, kopiowanie lub rozpowszechnianie w jakikolwiek sposób
  materiałów zawartych na stronach Praca.pl jest zabronione." (a notice against copying, not a clause on
  robots; robots.txt admits robots, AI crawlers by name).
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 1,221 bytes; GET /regulamin.html -> 200, text/html,
  159,201 bytes; GET of the PDF -> refused by the cap (Content-Length 3,631,037).
- Caveats: the verdict rests on a copyright notice, with the terms proper unread; the notice and robots.txt
  point in opposite directions.

### aplikuj.pl
- Publisher: Aplikuj.pl sp. z o.o., Bielsko-Biała.
- Documentation: "Regulamin dla Kandydatów", https://www.aplikuj.pl/regulamin (in force since 01.12.2022).
- Data or endpoint: https://www.aplikuj.pl ; no feed for reading found.
- Holds: adverts. Not examined. Access: web only. Registration or key: none to browse. Cost: free.
- Licence or terms (exact wording, with URL): 1.8: "Użytkownik korzystający z Serwisu zobowiązany jest do: [...]
  f. przestrzegania zakazu dokonywania ekstrakcji danych internetowych (web scraping) oraz uruchamiania
  jakichkolwiek skryptów, botów lub podobnych narzędzi w ramach Serwisu."
- Usable for own job search: no - "zakazu dokonywania ekstrakcji danych internetowych (web scraping) oraz
  uruchamiania jakichkolwiek skryptów, botów lub podobnych narzędzi w ramach Serwisu".
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET https://aplikuj.pl/regulamin -> 301 to www; GET https://www.aplikuj.pl/regulamin ->
  200, text/html, 75,851 bytes.
- Caveats: robots.txt not requested.

### EURES
- Offers pass both ways: the ePraca record has `udostepnionoDoEURES` ("Informacja czy oferta została
  udostępniona do EURES, czyli jest to krajowa oferta pracy, w której pracodawca jest szczególnie zainteresowany
  zatrudnieniem cudzoziemców z krajów UE/EOG"), `dataUdostepnieniaOferty` ("Data udostępnienia oferty na portal
  EURES") and `zagranicznaEures` (a foreign offer that came from the EURES network). By that wording only offers
  whose employer wants EU/EEA workers go to EURES. EURES listed 15,122 vacancies with a workplace in Poland on
  2026-11-28 (EU-wide file).

### Official vacancy statistics
- Skipped by the brief.

## Through the employers

### Business register
- Publisher: Ministerstwo Sprawiedliwości (Ministry of Justice) for the National Court Register (Krajowy Rejestr
  Sądowy, KRS: companies, partnerships, cooperatives, associations, foundations). Two other registers stand
  beside it: REGON at Statistics Poland (GUS; every entity of the national economy) and CEIDG at the Ministry of
  Development and Technology (sole traders).
- Documentation: KRS - https://prs.ms.gov.pl/krs/openApi (a script page; no text for a plain client) and the
  catalogue record "API Krajowego Rejestru Sądowego (API KRS)", https://api.dane.gov.pl/1.4/datasets/27606 .
  REGON - https://api.stat.gov.pl/Home/RegonApi . CEIDG - https://dane.biznes.gov.pl/ and
  https://akademia.biznes.gov.pl/portal/004856 .
- Data or endpoint: KRS - `https://api-krs.ms.gov.pl/api/krs/OdpisAktualny/{KRS number}?rejestr=P&format=json`
  (current extract; `OdpisPelny` for the full one) and `https://api-krs.ms.gov.pl/api/Krs/Biuletyn/{yyyy-mm-dd}`
  (numbers changed on a day). REGON - SOAP service BIR1 (address in its instruction). CEIDG - "API HD"
  of the data warehouse.
- Holds:
  - KRS, per company (seen in one answer): number (`numerKRS`), name (`nazwa`), legal form (`formaPrawna`), NIP
    and REGON, date of registration (`dataRejestracjiWKRS`), date and number of the last entry, state of the
    entry (`stanPozycji`), seat and address (`siedzibaIAdres`), **e-mail (`adresPocztyElektronicznej`) and
    website (`adresStronyInternetowej`)** where filed, the address for electronic delivery, capital, main and
    other activities with PKD codes (`przedmiotPrzewazajacejDzialalnosci`: `kodDzial`, `kodKlasa`,
    `kodPodklasa`, `opis`), bodies and their members, filed accounts (mentions), mergers. Against the eight
    minimum attributes: all eight (the Member State trivially). Beyond them: website and e-mail; no telephone,
    no number of employees.
  - REGON (from its page only): search by REGON, NIP or KRS number; fields not confirmed (the technical
    instruction is a 4,150,160-byte zip, over the cap).
  - CEIDG: sole traders; fields not confirmed (documentation is a .7z archive, not opened).
- Access: **KRS - API, one company per request by its number; no search by name or activity and no bulk file;
  the daily bulletin lists the numbers that changed.** REGON - API, one entity per request by identifier. CEIDG -
  API and reports behind an account.
- Registration or key: KRS - none: "API nie wymaga tokenu i nie posiada limitów pobrań." REGON - a user key by
  e-mail to regon_bir@stat.gov.pl giving the entity's full name, its REGON number, a contact person and IP
  addresses (so the applicant is an entity with a REGON number). CEIDG - "Aby skorzystać z Hurtowni danych
  CEIDG i Biznes.gov.pl musisz posiadać konto"; "Logowanie do Hurtowni danych jest możliwe po zarejestrowaniu i
  przy użyciu Profilu Zaufanego" (Poland's trusted profile); the API key arrives by e-mail after registration.
- Cost: free, all three (REGON: "Usługa i dane udostępniane są bezpłatnie.").
- Licence or terms (exact wording, with URL): KRS - "Dane udostępniane są w domenie publicznej." and CC0 1.0
  (record 27606). REGON - CC BY 4.0 (record 544, "Dostęp do danych rejestrowych REGON poprzez usługę sieciową -
  interfejsy API"); limits per user from 6,000 calls an hour by day to 10,000 by night, "Przekroczenie limitów
  nie skutkuje natychmiastową blokadą". CEIDG - not read.
- Usable for own job search: yes for KRS (no key, no limits, public domain); unclear for REGON and CEIDG (free,
  but the key or account presupposes a Polish-registered entity or a trusted profile).
- High-value dataset: the KRS record carries Poland's own flag for high-value data (`has_high_value_data: true`)
  but not the flag for the Commission's list (`has_high_value_data_from_ec_list: false`); the REGON record
  carries neither. On data.europa.eu no Polish dataset is flagged high-value. The register is thus open and
  free through an API, without the bulk download the EU rule also asks for.
- Volume: KRS - "liczba zmian wynosi średnio około 2 tys. wpisów dziennie"; the bulletin for 2026-11-27 listed
  3,829 numbers. Total not stated. REGON service: "25 525 zarejestrowanych użytkowników".
- Update cycle: KRS - "Dane aktualizowane są na bieżąco"; daily and hourly bulletins. REGON - daily.
- Seen on 2026-11-28: GET `https://api-krs.ms.gov.pl/api/krs/OdpisAktualny/0000006865?rejestr=P&format=json` ->
  200, application/json, 50,510 bytes (CD PROJEKT RED S.A.: website "WWW.CDPROJEKT.COM", an e-mail address, PKD
  62.10.A); GET `https://api-krs.ms.gov.pl/api/Krs/Biuletyn/2026-11-27` -> 200, application/json, 36,067 bytes,
  an array of 3,829 numbers; GET https://prs.ms.gov.pl/krs/openApi -> 200, 24,152 bytes (script shell); GET of
  record 27606 -> 200. GET https://api.stat.gov.pl/Home/RegonApi -> 200, text/html, 23,075 bytes; HEAD of its
  instruction zip -> 200, 4,150,160 bytes. GET https://dane.biznes.gov.pl/ -> 302 -> 302 -> 200 (39,771 bytes);
  GET https://akademia.biznes.gov.pl/hurtownia-danych-instrukcje-i-dokumentacja/ -> 302 -> 200 (38,474 bytes,
  updated 10.11.2026).
- Caveats: without a search, a list of companies must come from elsewhere (the daily bulletins, or numbers
  taken from adverts and directories); KRS numbers run in sequence, but walking them was not tried. The extract
  includes personal data of board members (names, PESEL numbers appear as fields). Sole traders are not in KRS.

### Applicant-tracking vendors seen in the country

| Vendor | Local or international | Public feed for an employer's board (format, key?) | Documentation URL | Basis for "used here" |
|---|---|---|---|---|
| Traffit | Polish (Traffit Sp. z o.o.; the site is in Polish) | JSON, no key: "Public API endpoints do not require authorization and are safe to call from a browser (for example from your own career page)". `GET https://<name>.traffit.com/public/an/list/?limit=..&offset=..` ("Get list of currently active job posts - the same list that is displayed on your career page"; 1-100 per page; fields include `url`, `applicationForm`, `validStart`, `validEnd`, `updatedAt` and the advert's template fields) and `GET https://<name>.traffit.com/public/job_posts/published` (paged by `X-Request-Page-Size` / `X-Request-Current-Page` headers; description, requirements, responsibilities, geolocation). Exception: "on instances where the feed is protected with the public_advert_list scope, the request must contain an access token" | https://api.traffit.com/ | The vendor's own site, Polish-language and Polish-registered; no market-share source |
| eRecruiter (Grupa Pracuj) | Polish. Not the Austrian product of the same name in this study's Austria file | None documented publicly as far as found | https://erecruiter.pl/en/polish-market-leader/ (vendor page, no technical documentation) | The vendor's own claim: "We are a leader of the Polish recruitment market", "2,000 clients", "We are a part of Grupa Pracuj" |

No employer's board and no vendor data endpoint was requested. Terms of use of the two vendors were not read.
softgarden is listed by Grupa Pracuj among its brands (see this study's Germany file for its feed).

### Links to employers' own pages
- ePraca web service: `adresWww` (the employer's website), `sposobAplikowania` and the application address per
  offer - closed to private persons (above).
- KRS open API: `adresStronyInternetowej` and `adresPocztyElektronicznej` per company, where filed; free, no
  key.
- Traffit feeds: `url` and `applicationForm` per advert, found only by knowing an employer's Traffit name.
- Just Join IT: robots.txt lists `sitemaps/top-companies.xml` and `sitemaps/active-jobs.xml` (not requested;
  terms unread).
- EURES: the vacancy record carries the employer's name, legal ID and website (EU-wide file).

### Employer directories
- SoDA - Software Development Association Poland, https://sodapl.com/czlonkowie/ : "Do SoDA dołączyło już 100
  firm technologicznych"; each member card has a "Strona firmy" link to the company's site (17 distinct outside
  links in the first page's HTML; the rest loads further). Terms and robots.txt not read. GET /members/ -> 301
  to /czlonkowie/ -> 200, text/html, 220,335 bytes.
- PIIT (Polish Chamber of Information Technology and Telecommunications): the member list was not found - GET
  https://piit.org.pl/o-izbie/lista-czlonkow -> 404; the site's menu has an item "Nasi członkowie" (address not
  followed).
- The KRS extract's activity codes select companies by activity only once their numbers are known.

### Archives of past adverts
None found with employer identifiers and a free licence. What exists:
- ePraca: the record has a status value "H - archiwalna", but the web service serves active offers only
  ("Pobranie wszystkich aktywnych ofert pracy") and its terms require republishing "wyłącznie aktualne oferty
  pracy". No archive file on dane.gov.pl.
- nabory.kprm.gov.pl: civil-service notices past their deadline can be searched with the status "Archiwalne";
  web only, and the base stays up only "do przyszłego roku". Employer = the office; no skills field seen.
- Zenodo record 11636825, "Job Ads in Retail and E-commerce sectors for INAIR project countries" (M. Paliński,
  published 2024-06-13, CC BY 4.0, open): five CSV files, one of them `pracujpl.csv` (15,599,063 bytes) with
  adverts from Pracuj.pl; "Data was collected three times during the period from March to May 2024, resulting in
  a total of 44,494 job offers" (all five countries together). Columns seen in the first 3,000 bytes:
  `current_date, job_title, employer, workplace, responsibilities, requirements, technologies, optional_req,
  specialty, expiration_date, position_lvl, txt, is_english, trans...` - employer by name (first row: "GroupM
  Sp. z o.o.", dated 2024-02-17), no registration number, a technologies field. Two sectors only. GET of the
  record -> 200, application/json, 6,039 bytes; GET of bytes 0-2999 of the file -> 206.
- Praca.pl keeps pages of expired adverts, listed per employer (search results only; copying forbidden by the
  site's notice).
- Third-party statements, not checked: a Kaggle dataset of No Fluff Jobs AI adverts 2022-2024 (title, company,
  location, salary); job-offer data of the Human Capital Balance study (BKL, PARP) for 2010-2015, drawn from
  labour offices and Careerjet; quarterly "Badanie internetowych ofert pracy" reports of the Rzeszów voivodeship
  labour office (statistics).

## Not free or not allowed

- ePraca web service: free but only for approved Polish-registered entities with one of three purposes; a
  private person or a foreign entity cannot apply.
- No Fluff Jobs: adverts' pages and API closed to all robots in robots.txt.
- aplikuj.pl: web scraping, scripts and bots forbidden by the terms.
- OLX: any use of the adverts' content without written consent forbidden (terms 2.3); aggregation for passing
  on to third parties forbidden.
- Praca.pl: copying of the pages' materials forbidden (notice); terms proper unread.
- Pracuj.pl: a plain client gets HTTP 403 (Cloudflare challenge) - a technical refusal; terms unread.
- REGON API key and CEIDG data warehouse account: free, but tied to an entity with a REGON number or to a
  trusted profile.
- Scrapers of ePraca, Pracuj.pl, Just Join IT, No Fluff Jobs and OLX are sold on apify.com (search results only).

## Gaps

- **ePraca**: the number of live offers; the portal's own terms; the current instruction for ePraca (the one
  read is the CBOP instruction of 2020); whether the ministry would accept an individual's application at all
  (the form has no purpose that fits). The web service was not called.
- **rekrutacje.gov.pl**: not reachable with certificate verification on; everything about the new civil-service
  system is unknown. Municipal and BIP vacancy pages other than the two catalogue records were not looked at.
- **Pracuj.pl, Praca.pl**: terms PDFs over the 2 MB cap, unread. **No Fluff Jobs, Just Join IT**: terms unread
  (one request each allowed). the:protocol, Rocket Jobs, Bulldogjob, Jooble, Indeed's and LinkedIn's Polish
  pages: not checked.
- **OLX**: annex 1 (OLX Praca) and the partner API's terms were not read.
- **KRS**: the documentation page's text (script-rendered) was not read; whether the API really has no rate
  limit was not tested; `OdpisPelny` was not requested. **REGON, CEIDG**: field lists unconfirmed; whether a
  foreign private person can get a key or an account was not established.
- **Vendors**: only Traffit's documentation was read. HRlink, Element, tomHRM and other Polish systems were not
  examined; no evidence on which systems Polish employers use most. Traffit's and eRecruiter's terms unread.
- **Directories**: SoDA's terms unread; PIIT's list not found; no startup register was opened.
- **Archives**: Kaggle, RepOD and the BKL data were not opened; the Zenodo file was sampled in its first 3,000
  bytes only (row count for Poland unknown).
