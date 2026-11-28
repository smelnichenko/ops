# Netherlands (NL) - free online job data sources: research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (`curl/8.14.1`, no added headers, one
capped GET per URL), and web search for finding pages. No account, key or login was used. Requests made, per
host: www.werkenvoornederland.nl 3, data.overheid.nl 3 (open data portal), www.werk.nl 2, www.kvk.nl 2,
www.nationalevacaturebank.nl 2, www.jobbird.com 2, help.homerun.co 2 (one a redirect), and 1 each to
developers.kvk.nl, opendata.kvk.nl, developer.overheid.nl (404), oss.developer.overheid.nl (404), api.cso20.net
(503), www.intermediair.nl, www.werkzoeken.nl (403), www.monsterboard.nl, developers.homerun.co. Indeed and
LinkedIn were not requested again: their terms were read once for the France file of this pass.

## Takeaway

The Netherlands has no open feed of the labour market's vacancies. UWV's werk.nl offers neither a dump nor an
API - UWV said so itself in an answer on the national data portal ("geen API vanuit het UWV"), adding that
scraping the site is possible in principle - and its only open data are weekly aggregates. The one source whose
terms plainly allow a program to read and keep the adverts is the central government's job site Werken voor
Nederland: about 1,500 vacancies, content under CC0 ("hergebruik van de inhoud van deze site is toegestaan"),
a vacancy sitemap and a robots.txt that asks for at most 10 requests a second; the JSON API that used to serve
it ("CSO Vacature API") is gone from the government API register and its address answers 503. The commercial
boards give no reading feed: Indeed and LinkedIn forbid bots, Jobbird forbids copying, Werkzoeken.nl blocked
the client, and Monsterboard now redirects to monster.com. For the employer route the country is the hardest of
the five: the Chamber of Commerce's free open dataset deliberately leaves out company names, KVK numbers and
addresses, so no free list of companies exists; named data costs a subscription and a fee per query.

## Sources

### UWV - werk.nl (public employment service)
- Publisher: UWV (Uitvoeringsinstituut Werknemersverzekeringen, the Employee Insurance Agency), UWV WERKbedrijf.
- Documentation: none for reading vacancies. UWV's answer to a data request on the national portal:
  https://data.overheid.nl/community/datarequest/vacatures-werk-nl (request of 25-08-2020, status "Afgehandeld").
- Data or endpoint: https://www.werk.nl/werkzoekenden/vacatures/ (web).
- Holds: vacancies placed by employers on werk.nl and vacancies collected from other sites (a UWV specification,
  per a search summary, speaks of "gescrapete vacatures"). Fields not examined.
- Access: web only. UWV's answer: "Werk.nl beschikt helaas niet over een API van alle vacatures. Werk.nl is een
  aanvulling op de markt en het bestaat uit open data. In principe is het volgens het UWV mogelijk om de data te
  scrapen. Dit vergt wel enige technische kennis. Maar helaas is er geen API vanuit het UWV om toegang te krijgen
  tot de data en die gaat voorlopig ook niet gerealiseerd worden."
- Registration or key: none stated for browsing; the vacancy path answered with a redirect to UWV's login server
  (see Seen).
- Cost: free.
- Licence or terms (exact wording, with URL): no terms page was found or read. robots.txt
  (https://www.werk.nl/robots.txt), whole file: "User-agent: * Disallow: /webpublicaties Sitemap:
  https://www.werk.nl/nl/sitemap.xml".
- For a personal job search: job-seeker use allowed in practice (the public service's job site; no terms read);
  automated reading not forbidden by robots.txt and, by UWV's 2020 answer, possible "in principe" by scraping - a
  six-year-old statement, not a licence; private copy not stated.
- How to apply: not examined.
- Volume: not read. On EURES 285,437 vacancies had a workplace in the Netherlands on 2026-11-28 (this study's
  EU-wide file).
- Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 85 bytes; GET /werkzoekenden/vacatures/ -> 302 to
  `https://login.werk.nl:443/oam/server/obrareq.cgi?...` (UWV's access server; not followed); GET of the data
  request page -> 200, text/html, 30,653 bytes.
- Caveats: whether the vacancy search now needs a login, or the redirect only sets a session, was not
  established (following it would have meant a session with the login server). Third parties sell several
  werk.nl scrapers on apify.com; one says it reads "the site's own internal vacancy search API".

### UWV Open Match Data (aggregates; one line)
- https://data.overheid.nl/dataset/uwv-open-match-data : vacancies and anonymised CVs from werk.nl counted per
  occupation and four-digit postcode, CC BY 4.0, weekly ZIP files (per a search summary the files seen date from
  2019-2021 while the record says "Bijgewerkt 28-08-2025"). Counts only; of no use for reading adverts. Not
  requested.

### Werken voor Nederland - central government vacancies
- Publisher: the Rijksoverheid (central government as employer); the site is run for the ministries by the
  government's shared service organisation (named "Uitvoeringsorganisatie Bedrijfsvoering Rijk" in the API
  register entry, per a search summary).
- Documentation: https://www.werkenvoornederland.nl/copyright ; robots.txt.
- Data or endpoint: https://www.werkenvoornederland.nl/vacatures ; sitemap
  https://www.werkenvoornederland.nl/sitemap-vacatures.xml (named in robots.txt, not requested).
- Holds: vacancies of ministries and agencies; the list page says "1500 vacatures". Fields not examined (the
  list is filled by script; no vacancy page was requested).
- Access: web pages and a vacancy sitemap. The JSON API is gone (next block).
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): "Tenzij anders vermeld is op de inhoud van deze website de Creative
  Commons zero verklaring (CC0) van toepassing. Dit houdt in dat hergebruik van de inhoud van deze site is
  toegestaan, tenzij bij een bepaald onderdeel (bijvoorbeeld een document) staat aangegeven dat op dat onderdeel
  een auteursrechtelijke uitzondering van toepassing is. Voor foto's is de CC0 niet van toepassing." and "Bij
  hergebruik van de inhoud van deze website is naamsvermelding niet verplicht." robots.txt, whole file:
  "User-agent: * Disallow: /login Request-rate: 10/1 Visit-time: 0000-2400" and two sitemaps.
- For a personal job search: job-seeker use allowed (reuse of the content is allowed); automated reading allowed
  (robots.txt admits all agents outside `/login`, at a stated rate of 10 requests a second, any hour); private
  copy allowed (CC0).
- How to apply: not examined on a vacancy; the footer points questions on "de sollicitatieprocedure" to the
  site's contact page.
- Volume: about 1,500 vacancies.
- Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 200 bytes; GET /vacatures -> 200, text/html, 604,029
  bytes (the text "1500 vacatures"; no vacancy links and no JSON-LD in the HTML); GET /copyright -> 200, 47,557
  bytes.
- Caveats: central government only; municipalities, provinces and water boards recruit elsewhere (the related
  sites WerkenbijdeOverheid.nl and Mobiliteitsbank.nl were not checked).

### CSO Vacature API and the dataset "Vacatures Overheid" (withdrawn or down)
- Publisher: Uitvoeringsorganisatie Bedrijfsvoering Rijk / "Werkmaatschappij" (per search summaries).
- Documentation: formerly https://developer.overheid.nl/apis/cso-vacature-api and
  https://data.overheid.nl/dataset/vacatures-overheid .
- Data or endpoint: formerly `https://api.cso20.net/v1/JobAPI/` (sandbox `https://sandbox.api.cso20.net/v1/JobAPI/`).
- Holds: per the search summaries of those pages: vacancies of WerkenvoorNederland.nl, WerkenbijdeOverheid.nl
  and Mobiliteitsbank.nl as REST/JSON - counting, retrieving and filtering vacancies - free, open to everyone,
  licence CC0.
- Access: none found working today.
- Registration or key: "authentication unknown" in the register listing (search summary).
- Cost: free.
- Licence or terms (exact wording, with URL): CC0 per the search summary of the dataset page; not confirmed.
- For a personal job search: not applicable while the source is unavailable.
- How to apply: not known.
- Volume: not known. Update cycle: not known.
- Seen on 2026-11-28: GET https://developer.overheid.nl/apis/cso-vacature-api -> 404 ("Pagina niet gevonden"); GET
  https://oss.developer.overheid.nl/apis/cso-vacature-api -> 404; GET
  `https://data.overheid.nl/data/api/3/action/package_show?id=vacatures-overheid` -> 403, "Access denied: User
  not authorized to read package 08c3daa3-9926-4efb-9974-666fdb0bee62"; GET
  https://data.overheid.nl/dataset/vacatures-overheid -> 404; GET https://api.cso20.net/v1/JobAPI/ -> 503 "No
  server is available to handle this request."
- Caveats: search engines still list both pages, so the withdrawal is recent or the pages moved; the new API
  register (apis.developer.overheid.nl) was not searched. Whether the API lives on under another address is not
  known.

### Nationale Vacaturebank and Intermediair (DPG Media)
- Publisher: DPG Media (the two sites share their robots.txt structure).
- Documentation: none read (the terms address tried answered 404).
- Data or endpoint: https://www.nationalevacaturebank.nl ; https://www.intermediair.nl
- Holds: job adverts. Not examined. A third-party scraper listing speaks of "105,000+ listings" on Nationale
  Vacaturebank.
- Access: web only; no reading feed found.
- Registration or key: none to browse. Cost: free to browse.
- Licence or terms (exact wording, with URL): terms not read. robots.txt
  (https://www.nationalevacaturebank.nl/robots.txt), all agents: "Disallow: /vacature/zoeken?*", "Disallow:
  /vacatures/*?page=", "Disallow: /vacature/apply/", "Disallow: /vacature/external-url/", "Disallow:
  /solliciteren/", "Disallow: /archief/"; a separate group "User-agent: ClaudeBot Disallow: /"; ten sitemaps,
  among them `/cdn/sitemaps/vacature.xml`.
- For a personal job search: job-seeker use not stated (terms not read); automated reading - search-result and
  apply URLs are closed to all agents and one AI crawler is shut out by name; vacancy pages are in the sitemaps;
  private copy not stated.
- How to apply: on the site (`/solliciteren/`, `/vacature/apply/`) or through an external link
  (`/vacature/external-url/`); not examined.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 2,818 bytes; GET /gebruiksvoorwaarden -> 404 (a guessed
  address); GET https://www.intermediair.nl/robots.txt -> 200, 3,735 bytes.
- Caveats: the terms were not located.

### Jobbird
- Publisher: Jobbird (the terms cover several "platforms" of the same company).
- Documentation: https://www.jobbird.com/nl/algemene-voorwaarden
- Data or endpoint: https://www.jobbird.com/nl/ ; no reading feed (robots.txt disallows `/*/api`, `/*/export`,
  `/*/xml`).
- Holds: adverts from employers and agencies; "De vacatures worden geanonimiseerd, met uitzondering van
  bedrijfsnaam en logo, op de site geplaatst, dit wil zeggen dat de contactgegevens van de opdrachtgever niet
  beschikbaar zijn bij het doorzoeken van de vacaturedatabank."
- Access: web only. Registration or key: none to browse. Cost: free to browse.
- Licence or terms (exact wording, with URL): Art. 3: "Het is nadrukkelijk verboden om zonder voorafgaande
  schriftelijke toestemming van de platforms verveelvoudiging of (her) publicatie van (een deel van) de website
  of de daarop vermelde informatie over te nemen." robots.txt for all agents also disallows `/nl/vacature?*`,
  `/*/job_contact`, `/*/job_mail`, `/outgoing/*`.
- For a personal job search: job-seeker use allowed in practice (searching and answering vacancies are the
  described use); automated reading not stated as such in the terms (no clause on robots or scripts); private
  copy forbidden as worded (reproduction of any part of the site's information needs written permission).
- How to apply: through Jobbird ("Rechtstreeks solliciteren via de website van Jobbird"); employers may not put
  contact details in an advert ("Het is op de websites niet toegestaan om contactgegevens in de vacature te
  plaatsen").
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, 1,514 bytes; GET of the terms -> 200, text/html, 60,868 bytes.
- Caveats: none beyond the above.

### Werkzoeken.nl and Monsterboard
- Publisher: Werkzoeken.nl; Monster.
- Documentation: Werkzoeken.nl has a page "API documentatie" at https://www.werkzoeken.nl/doc/ (search result;
  not readable - the host blocked this client; what the API is for is unknown).
- Data or endpoint: https://www.werkzoeken.nl ; https://www.monsterboard.nl
- Holds: job adverts. Not examined. Access: not established.
- Registration or key: not known. Cost: free to browse.
- Licence or terms (exact wording, with URL): not read.
- For a personal job search: job-seeker use not stated; automated reading refused in practice by Werkzoeken.nl;
  private copy not stated.
- How to apply: not examined.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET https://www.werkzoeken.nl/robots.txt -> **403**, a Cloudflare page "Sorry, you have
  been blocked" (host not asked again); HEAD https://www.monsterboard.nl/ -> 301 to https://www.monster.com/nl/.
- Caveats: Monster's European companies were reported in liquidation in 2025 (third parties, see the France
  file); what monster.com/nl/ serves was not checked.

### Indeed and LinkedIn in the Netherlands
- Same terms as recorded in this pass's France file (`FR-France.md`): Indeed (terms of 1 April 2026) forbids
  automated systems, "bots", scrapers, "IA agentique", without written permission; LinkedIn (User Agreement
  effective 3 November 2025) forbids software, scripts, robots or crawlers "to scrape or copy the Services".
  Job-seeker use allowed, automated reading forbidden whatever the purpose, private copy forbidden as worded.
  No request was made to nl.indeed.com.

### Official vacancy statistics (one line)
- CBS (Statistics Netherlands) publishes quarterly vacancy tables as open data (several are listed on
  data.overheid.nl, e.g. "Vacatures (openstaande, ontstane en vervulde); overheid en onderwijs"); aggregates only.

## Through the employers

### Business register
- Publisher: KVK (Kamer van Koophandel, the Netherlands Chamber of Commerce), keeper of the Handelsregister - one
  national register.
- Documentation: https://www.kvk.nl/producten-bestellen/kvk-handelsregister-open-data-set/ ;
  https://developers.kvk.nl/documentation/open-dataset-basis-bedrijfsgegevens-api ; paid APIs
  https://www.kvk.nl/producten-bestellen/api/
- Data or endpoint: bulk https://www.kvk.nl/download/kvk-open-dataset-basis-bedrijfsgegevens.zip (not
  downloaded); API `https://opendata.kvk.nl/api/v1/hvds/basisbedrijfsgegevens/kvknummer/{kvknummer}`.
- Holds: **the free data is anonymised and names no company.** KVK: "Ontvang verschillende, anoniem gemaakte,
  bedrijfsgegevens van een BV of NV uit het Handelsregister." and "De HVDS (High Value Data Set) bevat geen
  persoonsgegevens. Dit heeft tot gevolg dat de beschikbare dataset niet alle datavelden bevat die zijn
  omschreven in Uitvoeringsverordening 2023/138. Dit geldt voor de naam van de onderneming en het KVK-nummer. Van
  het vestigingsadres zijn alleen de eerste twee cijfers van de postcode onderdeel van de datasets." Of the eight
  minimum attributes it carries five: registration date ("Datum aanvang"), status ("Actief", "Insolventie"),
  legal form ("Rechtsvorm (BV of NV)"), activity codes ("SBI-activiteiten", "Hoofdactiviteiten"), Member State
  ("Lidstaat"); of the address only "Postcode regio (eerste twee cijfers)". It does not carry the name, the
  registration number or the registered office address. Not supplied either, per the page's FAQ: "Het aantal
  werkzame personen. Het KVK-nummer. Naam van de organisatie. De volledige postcode. [...] Gegevens van
  eenmanszaken." No website, e-mail or telephone.
- Access: bulk CSV (zip) and a keyless API - but the API only answers for a KVK number one already has, and
  returns the same anonymised fields. Named company data is not free: "Om KVK-API's te gebruiken, heb je altijd de
  API 'Zoeken' nodig. Een abonnement kost €6,40 per maand. Voor sommige API's betaal je daarnaast €0,02 per
  bevraging." and "Het maken van selecties of zoekopdrachten op kenmerken zoals SBI-code is niet mogelijk."
  What is free instead: the anonymised dataset; the register's web search on kvk.nl, one company at a time (not
  requested); a test environment of the paid APIs with fictitious data ("Je kunt de API's kosteloos testen").
- Registration or key: none for the open dataset and its API; a paid subscription for the named-data APIs.
- Cost: open dataset free ("Gebruik van de Open Dataset Basis Bedrijfsgegevens is gratis").
- Licence or terms (exact wording, with URL): "De HVDS wordt voor hergebruik beschikbaar gesteld onder de
  voorwaarden van de Creative Commons BY 4.0 licentie (CC BY 4.0)." with the added condition "Het is daarbij niet
  toegestaan om deze HVDS op een zodanige manier te verrijken waardoor de gegevens herleidbaar zijn naar een
  individueel persoon."
- For a personal job search: use allowed; automated reading allowed; private copy allowed - but the data cannot
  serve as a list of employers.
- How to apply: not applicable.
- Volume: BVs and NVs only (no sole traders). Update cycle: "Deze dataset wordt elke werkdag vernieuwd."
- Seen on 2026-11-28: GET of the KVK product page -> 200, text/html, 187,283 bytes; GET of the developer page ->
  200, 82,756 bytes; GET of the API with the documentation's example number 12345678 -> 404, application/json,
  121 bytes: "Op basis van het KVK-nummer 12345678 kan het product niet worden geleverd." (the API answers
  without a key); GET of the paid-API page -> 200, 185,091 bytes.
- Caveats: published as the country's high-value dataset for companies (KVK calls it "HVDS" and cites
  Regulation 2023/138), while by KVK's own statement it lacks attributes the Regulation lists. Enriching it back
  to named companies is restricted by the added licence condition where that would identify a person.

### Applicant-tracking vendors seen in the country

| Vendor | Local or international | Public feed for an employer's board (format, key?) | Documentation URL | Basis for "used here" |
|---|---|---|---|---|
| Recruitee | Dutch (Amsterdam; from memory, not confirmed today) | Keyless JSON per employer: "GET https://{clientname}.recruitee.com/api/offers" (vendor documentation as quoted in a search summary; see `00-EU-wide.md`). A third-party page claims an authentication change is announced for 2027 - not verified | https://docs.recruitee.com/docs/feed (not requested: a host masi's files name) | Not established from a source read today |
| Homerun | Dutch (from memory, not confirmed today) | API: "All API endpoints require Bearer authentication" (key made by the employer). XML feed: the employer generates a link in Settings > Integrations > "Homerun XML" and shares it ("Copy feed link"); the link is not published per company | https://developers.homerun.co/ ; https://help.homerun.co/en/articles/5013627-how-to-generate-an-xml-feed | Not established from a source read today |
| Carerix, OTYS, AFAS, Bullhorn Connexys | Dutch or Dutch-rooted (from memory) | Not checked | - | Named from memory only |
| Teamtailor, Greenhouse, Lever, SmartRecruiters, Workable, Personio, Workday | International | See this study's `00-EU-wide.md`, topic 5 | there | Not established for the Netherlands |

No source was found on which systems Dutch employers use most.

### Links to employers' own pages
- None found in a free source a program may read. werk.nl and the commercial boards were not examined at advert
  level; Nationale Vacaturebank's robots.txt shows that adverts can carry an external link
  (`/vacature/external-url/`) but closes that path to robots.
- Werken voor Nederland's vacancies are the employer's own pages (the government is the employer).

### Employer directories
- Techleap "Finder" (Dutch startups and scale-ups, built with Dealroom): per Techleap's own blog (search
  summary) a free database, with a free account needed to see all results and export in a paid tier. Not
  requested; terms not read.
- No public member list of NLdigital (the ICT trade association) was found by search.

## Not free or not allowed

- KVK: names, numbers and addresses of companies only through paid APIs (subscription €6.40 a month plus €0.02
  per query for some) or one-by-one web search.
- UWV: no API, none planned (2020 statement).
- Indeed, LinkedIn: automated reading forbidden. Jobbird: copying forbidden without written permission.
- Refused a plain client: werkzoeken.nl (403, Cloudflare block).
- Nationale Vacaturebank: search and apply URLs closed in robots.txt; ClaudeBot shut out by name.
- Scrapers of werk.nl, Nationale Vacaturebank, Werkzoeken.nl, Intermediair and StepStone.nl are sold on
  apify.com (search results only).

## Gaps

- **werk.nl**: terms of use, the advert fields, apply paths, the number of live vacancies and whether the search
  needs a login were not established (redirect to the login server not followed; third request not spent).
  UWV's statement on scraping is from 2020.
- **CSO Vacature API**: not confirmed gone for good; only that its register page, its dataset record and its
  published address fail today. The new API register was not searched.
- **Werken voor Nederland**: no vacancy page or sitemap was requested, so fields and apply path are unknown.
  WerkenbijdeOverheid.nl, municipal and provincial job sites (e.g. the regional "werken in" portals) not checked.
- **Nationale Vacaturebank / Intermediair**: terms not located. **Werkzoeken.nl**: nothing read; its "API
  documentatie" page may describe a feed. **StepStone.nl**, Jooble, Adzuna NL, Talent.com: not checked
  (aggregators are in the EU-wide file).
- **UWV Open Match Data**: current coverage not checked.
- **KVK**: the open dataset's zip was not downloaded; the free web search's limits were not read.
- **Applicant-tracking vendors**: no evidence of use in the country was read; Recruitee's documentation was not
  requested; Carerix, OTYS, AFAS, Connexys not examined.
- **Employer directories**: none verified at the publisher.
- CBS table identifiers and licence were not re-read.
