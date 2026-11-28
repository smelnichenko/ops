# France (FR) - check of the research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (`curl/8.14.1`), no added headers, no
`-L`, every transfer capped (`--max-filesize 2000000 -m 30`), one request at a time. Web search (run by the
search service, not from this address) only to find page addresses. No account, key or login.
Requests per host: www.data.gouv.fr 10 (one answered 401), static.data.gouv.fr 3, choisirleservicepublic.gouv.fr 3,
www.emploi-territorial.fr 3, candidat.francetravail.fr 2, data.iledefrance.fr 2, data.europa.eu 2,
api.apprentissage.beta.gouv.fr 2, developers.cegid.com 2, developers.flatchr.io 2, and 1 each to francetravail.io,
www.francetravail.fr, data.seinesaintdenis.fr, recherche-entreprises.api.gouv.fr, www.maformation.fr,
www.hellowork.com, fr.indeed.com, www.linkedin.com, www.welcometothejungle.com, www.meteojob.com, www.monster.fr,
frenchtech120.numeum.fr, annuaire-entreprises.data.gouv.fr, www.jobteaser.com, taleez.com,
developers.welcomekit.co, support.beetween.com, www.jobaffinity.fr, jobaffinity.fr, help.jobaffinity.fr,
www.softy.pro, v2.softy.pro, recrutement.softy.pro, www.digitalrecruiters.com, developers.greenhouse.io,
docs.greenhouse.io, raw.githubusercontent.com, developers.smartrecruiters.com, workable.readme.io,
docs.recruitee.com, developer.personio.de, support.teamtailor.com, www.workday.com.
No request to apec.fr or cadremploi.fr (they refused the researcher). No employer's board and no vendor data
endpoint was requested. Redirects were followed only inside the same site and never to a login.

The research file has the section "Through the employers"; it is checked below (claims 41-62).

## Corrections and unverified claims (apply these first)

- CORRECTED (claim 17): emploi-territorial.fr's API is not an open reading interface. Its own description says
  "L'accès à ces ressources nécessite une authentification, contactez le GIP Informatique des CDG pour plus
  d'informations."; the key is an `X-API-Key` "Token d'authentification transmis par le support GIPCDG"; the
  operations are for local authorities' own offers (`/col/listoffres`, `/col/transmetop`), for the Centres de
  Gestion, for sending in a job seeker's request, and statistics. Licence named in the description: "Etalab 2.0".
- CORRECTED (claim 20): the Île-de-France dataset's licence is "Licence Ouverte v2.0 (Etalab)" (the research had
  not read it). Its newest "Date de mise en ligne" is 2026-12-11, a future date, not 2026-11-27. It has 50 fields;
  no link and no salary field, but one contact field for school posts (`vac_lycee_uai_3`, "Mail générique UAI").
- CORRECTED (claim 23): La bonne alternance - the data.gouv.fr record is filed under DINUM, but the API site's own
  terms name the "Éditeur" as the Délégation générale à l'emploi et à la formation professionnelle (DGEFP). The
  terms (v1.0, 31 March 2025) answer what the research left open: "L'inscription est gratuite et ouverte à tous",
  the user is "toute personne physique qui souhaite accéder aux données de l'apprentissage", and the user
  "s'engage à ne pas commercialiser les données reçues et à ne pas les communiquer à des tiers".
- CORRECTED (claim 3): the words "offres partenaires" are on the search page ("Offres partenaires - France
  Travail améliore la transparence du marché du travail en vous proposant plus d'opportunités d'emploi grâce à
  ses partenaires"), not in the terms; the terms only speak of "une API des partenaires de France Travail".
- CORRECTED (claim 48): Taleez does publish a statement about an API: its own site says "Une API publique
  documentée permet également de connecter Taleez à votre écosystème spécifique" and links "Documentation API"
  at https://api.taleez.com/ (not opened: the vendor's API host). No public feed of an employer's board is
  documented on the page read.
- ADDITION (claim 8, confirmed): France Travail's record contradicts itself on private persons - the access table
  says `"role": "private", "condition": "no"`, while the description text still says "L'API s'adresse aux
  particuliers, entreprises & startups et collectivités territoriales". The notice at the top speaks only of
  "Les organismes ayant un besoin d'accès au service".
- ADDITION (claim 14, confirmed): the weekly file holds every offer published since 1 January, expired ones
  included (the first rows end publication on 30/01/2026-03/03/2026); a program has to filter on "Date de fin de
  publication par défaut". Its "Référence" column mixes the portal's own numbers ("2026-2149979") with the
  partner sites' own references ("O033260101000001" for territorial offers, "INRAE-OT-28063", "APHP_2026-19732").
- UNVERIFIED (blocked): everything about APEC (terms, access, "no reading API") - no request made: apec.fr
  refused the researcher with 403.
- UNVERIFIED (blocked): Cadremploi's terms and access - no request made: cadremploi.fr refused the researcher.
- UNVERIFIED: francetravail.io's own notice of the suspension, the API's documentation, field list and the text
  of the "licence de réutilisation des offres" - the portal answers with a script-only shell (`<peio-root>`,
  2,000 bytes). The suspension itself is confirmed from France Travail's record and replies on data.gouv.fr.
- UNVERIFIED: the data.gouv.fr record of the Seine-Saint-Denis copy (created 2026-11-12, archived 2026-11-22 as
  "not-on-remote") - not found by two searches of the portal; the search with `archived=true` answers 401. Only
  the dead source was seen (404).
- UNVERIFIED: JobTeaser's clause on robots - its terms address answers 301 to a PDF on another host
  (d1guu6n8gz71j.cloudfront.net), not followed. A search summary gives a narrower wording than the research: a ban
  on downloading "all or a quantitatively substantial part of the Service by using robots or any other automatic
  extraction process".
- UNVERIFIED: Annuaire des Entreprises - the site answered 302 to itself with a bot-check page ("Loading",
  Incapsula cookies); not asked again.
- UNVERIFIED: "347,200 offers published in 2025" on Choisir le service public; the publisher's statement that it
  will not publish the offers' full content; the "Documentation API CSP" PDF (a search lists it at
  `/wp-content/uploads/2026/08/Documentation-API-CSP.pdf`) - none requested: the three requests to the host and
  the ten to the portal were spent.
- UNVERIFIED: emploi-territorial.fr's counts by category (31,451 offers) - home page not requested (the three
  requests went to robots.txt and the API documentation).
- UNVERIFIED: how an offer in the weekly file is found on the site from its "Référence" - not tried.
- UNVERIFIED: the content and licence of the BPCE dataset and the content of the Tours datasets - only their
  catalogue entries were seen.
- UNVERIFIED: Monster Europe's liquidation and the July 2025 date (third parties); Les Pépites Tech; the scrapers
  on apify.com; the EURES count of 427,029 (belongs to the EU-wide file) - not requested.
- UNVERIFIED, not sourced - drop: **DigitalRecruiters** - its site answers 301 to another site
  (`https://www.cegid.com/fr/produits/cegid-hr/talent-acquisition/`, not followed); no page of its own was read.
  It is now a Cegid product, so the Cegid row covers the vendor.
- UNVERIFIED: that any of the vendors in the table is used by French employers - no source read, apart from
  Talentsoft behind Choisir le service public (confirmed) and each French vendor's own site.

## Claims

| # | Claim | Verdict | Evidence (URL, status, what was seen) | Corrected statement |
|---|---|---|---|---|
| 1 | France Travail's terms page is dated "Date de mise à jour : 19/02/2024"; offers can be read without an account | CONFIRMED | GET https://www.francetravail.fr/informations/informations-legales-et-conditio/conditions-generales-dutilisatio.html -> 200, text/html, 74,673 bytes: "Date de mise à jour : 19/02/2024"; "Le site permet à toute personne, sans qu'il soit nécessaire de créer un espace personnel, de : [...] consulter des offres d'emploi" | - |
| 2 | Terms: offers go to EURES and to "une API des partenaires de France Travail qui adhèrent à la licence de réutilisation des offres (à l'exception des données de contact)"; other content is reusable under the Licence Ouverte | CONFIRMED | Same page, both sentences word for word, with "Ces offres pourront être réutilisées pour tout usage et notamment être rediffusées sur des sites tiers." and "Les autres contenus constituent des informations publiques librement réutilisables sous réserve du respect de la licence ouverte" | - |
| 3 | The terms and the search page both speak of "offres partenaires" | CORRECTED | Terms page: no "offres partenaires"; only "une API des partenaires de France Travail". GET https://candidat.francetravail.fr/offres/recherche -> 301, body 66,556 bytes: "Offres partenaires", "Afficher uniquement les offres France Travail", "Qui sont nos partenaires ?" | The search page speaks of "offres partenaires"; the terms speak only of partners that reuse the offers. |
| 4 | The terms have no clause on robots, scripts or extraction | NOT DISPROVED | Same page searched for robot, automatis, extraction, aspir, scrap, moissonn: one hit, about automated recruitment methods (GDPR art. 22). The bans in the page concern throw-away e-mail addresses, recording advisers, and files of applications | - |
| 5 | robots.txt of candidat.francetravail.fr: "Disallow: *motsCles=*", "/offres/selection", "/offres/emploi:redirection*", "/offres/recherchesenregistrees", "/espacepersonnel/", "/compte/"; four sitemaps under `/rechercheoffre/sitemap/` | CONFIRMED | GET https://candidat.francetravail.fr/robots.txt -> 200, text/plain, 1,321 bytes; all six lines for `User-agent: *`; four `Sitemap:` lines (secteurs-metiers, regions-departements-villes, croisements-metiers-departements, croisements-metiers-villes) | - |
| 6 | `/offres/recherche` answers 301 to `/offres/emploi` with a 66,556-byte body | CONFIRMED | 301, `Location: /offres/emploi`, 66,556 bytes | - |
| 7 | With a "candidat" space one can "consulter et s'abonner à des offres d'emploi, télé-candidater à des offres d'emploi" | CONFIRMED | Terms page, §3.1, word for word | - |
| 8 | France Travail's API Offres d'emploi: "n'est actuellement plus exposée sur www.francetravail.io", after "usages automatisés massifs par certaines solutions d'intelligence artificielle"; `access_type: restricted`, reason "Analyse de sécurité"; private persons "no"; base URL now `https://francetravail.io/contact`; "10 appels / seconde"; record modified 2026-10-20 | CONFIRMED | GET https://www.data.gouv.fr/api/1/dataservices/api-offres-demploi/ -> 200, application/json, 6,724 bytes, organisation "France Travail" (certified): every quoted sentence and value present; `access_audiences`: local authorities "under_condition", companies and associations "under_condition", `"role": "private", "condition": "no"`; `metadata_modified_at` 2026-10-20T13:57:40 | Add: the same record's description still says "L'API s'adresse aux particuliers, entreprises & startups et collectivités territoriales". |
| 9 | France Travail's reply of 2026-10-19: access "est actuellement suspendu pour les nouveaux requérants"; holders keep theirs | CONFIRMED | GET https://www.data.gouv.fr/api/1/discussions/?for=672cf68826b31834a945cefe -> 200, 8,826 bytes, two threads; reply of 2026-10-19T07:15 by a member of France Travail: "L'accès à l'API Offres d'emploi est actuellement suspendu pour les nouveaux requérants, le temps de mener une analyse sur les nouvelles demandes de consommation. Les consommateurs disposant déjà d'un accès le conservent"; a second reply the same day: "Les demandes d'accès à l'API Offres d'emploi sont actuellement en cours d'analyse." | - |
| 10 | francetravail.io serves a script-only page; the API documentation, field list and licence text cannot be read by this client | CONFIRMED | GET https://francetravail.io/produits-partages/catalogue/offres-emploi -> 200, text/html, 2,000 bytes: `<peio-root></peio-root>` and four script tags, `Last-Modified: Wed, 04 Nov 2026` | - |
| 11 | The Seine-Saint-Denis copy of the API's output was archived and its source answers 404 | UNVERIFIED | Source: GET https://data.seinesaintdenis.fr/api/explore/v2.1/catalog/datasets/france-travail-offres-d-emploi -> 404, "The requested dataset france-travail-offres-d-emploi does not exist." The data.gouv.fr record was not found (`?q=france travail offres seine-saint-denis` -> total 0; with `archived=true` -> 401) | The source is gone (seen). The record's dates of creation and archiving were not seen. |
| 12 | Choisir le service public legal notice: the site is for "toute personne [...] qui souhaite rechercher une offre d'emploi et déposer une candidature"; accessible "aux seules fins de lui permettre de consulter les offres d'emploi et déposer sa candidature"; footer "tous les textes de ce site sont sous licence etalab-2.0"; Talentsoft runs the recruitment platform | CONFIRMED | GET https://choisirleservicepublic.gouv.fr/mentions-legales/ -> 200, text/html, 171,784 bytes; all four seen ("Talentsoft (responsable de la plateforme de recrutement)"). No word robot, automatis, extraction or scrap in the page | - |
| 13 | Its robots.txt, whole rule set: "Disallow: /wp-admin/", "Disallow: /wp-content/uploads/pdf-offers/", "Allow: /wp-admin/admin-ajax.php" | CONFIRMED | GET /robots.txt -> 200, text/plain, 173 bytes; those three rules and `Sitemap: https://choisirleservicepublic.gouv.fr/sitemapindex.xml`. GET of that index -> 200, 1,075 bytes: six sitemaps all dated 2023-04-14, none of offers | - |
| 14 | Weekly open file: Licence Ouverte 2.0 (`lov2`), no key, weekly, current file `offres-datagouv-20261122.csv` of 151,904,521 bytes, yearly files of 141-168 MB for 2022-2025, 30 semicolon-separated columns, no URL and no contact column, no salary, territorial offers included, offers since 1 January 2026 | CONFIRMED | GET https://www.data.gouv.fr/api/1/datasets/les-offres-diffusees-sur-choisir-le-service-public/ -> 200, 21,453 bytes: `license` lov2, `frequency` weekly, publisher DGAFP, last file 2026-11-23, sizes 151,904,521 / 163,994,301 (2025) / 168,159,826 (2024) / 167,427,099 (2023) / 141,408,675 (2022). GET of the CSV, bytes 0-11999 -> 206, text/csv, `Content-Range: bytes 0-11999/151904521`: the 30 column names exactly as listed; 24 whole rows, first publication 01/01/2026; rows of "Fonction Publique Territoriale"; no `http` and no `@` in the sample | Add: expired offers stay in the file; "Référence" has two forms (see above). |
| 15 | The offer has to be found on the site by its "Référence" and the application made there | UNVERIFIED | Not tried (no request left for the host). References seen: "2026-2149979" (the portal's own form), "O033260101000001", "INRAE-OT-28063", "APHP_2026-19732", "MINT_BA075PNC-114177" (partners' forms) | - |
| 16 | emploi-territorial.fr robots.txt: SemrushBot shut out; all agents "Disallow: /exportoffres/", "/arretes/normal/*.pdf", "/arretes/annul/*.pdf" | CONFIRMED | GET https://www.emploi-territorial.fr/robots.txt -> 200, text/plain, 138 bytes, exactly that | - |
| 17 | emploi-territorial.fr: "an API is announced but its terms were not read"; what it offers and to whom is unknown | CORRECTED | GET https://www.emploi-territorial.fr/api/ -> 200, text/html, 28,422 bytes ("Documentation API", Swagger page, version 5.3.1.1); GET https://www.emploi-territorial.fr/api/emploi-territorial.yml -> 200, 106,639 bytes: "L'accès à ces ressources nécessite une authentification, contactez le GIP Informatique des CDG pour plus d'informations."; `securitySchemes: tokenHeader: type: apiKey, name: X-API-Key`, "Token d'authentification transmis par le support GIPCDG"; licence "Etalab 2.0"; paths `/referentiels/*`, `/col/*`, `/cdg/*`, `/demandeurs/*`, `/stats/*` | The API needs a token issued on request by the GIP Informatique des CDG and serves employers' and the Centres de Gestion's systems; it is not a public reading interface. |
| 18 | emploi-territorial.fr counts: A+ 198, A 6,915, B 8,201, C 16,137 (31,451), 72 internships | UNVERIFIED | Home page not requested (three requests spent) | - |
| 19 | Île-de-France dataset: keyless Opendatasoft API, 152 offers, fields `vacancy_ref`, `vacancy_title`, `vacancy_activation_date`, `def_missions`, `vac_profil`; no URL field | CONFIRMED | GET https://data.iledefrance.fr/api/explore/v2.1/catalog/datasets/offres-emploi-region-iledefrance -> 200, 15,058 bytes: `records_count` 152, processed 2026-11-28T02:15; GET `.../records?limit=1&order_by=vacancy_activation_date desc` -> 200, 11,220 bytes, `total_count` 152, no key sent, `X-RateLimit-Limit: 10000` | - |
| 20 | Île-de-France dataset: licence not read; newest activation 2026-11-27; no contact field | CORRECTED | Metadata: `license` "Licence Ouverte v2.0 (Etalab)". Newest record: `vacancy_activation_date` 2026-12-11. Field `vac_lycee_uai_3` "Mail générique UAI"; texts of duties and profile in HTML and plain text; `cust_footer` (conditions of the post) | Licence Ouverte 2.0; activation dates run into the future; a generic e-mail field exists for school posts. |
| 21 | data.europa.eu lists "Offres d'emploi de la Région Île-de-France" (2026-11-27), "Offres d'emploi - Tours" (2026-11-27), "Groupe BPCE - Offres emploi publiques" (2026-11-26), "Offres d'emplois en direct" (Agen, 2015); France Travail's statistics entry is `561fc15688ee3836b1628efc` | CONFIRMED | GET `https://data.europa.eu/api/hub/search/search?q=offres d'emploi&filter=dataset&facets={"country":["fr"]}&limit=12` -> 200, 79,202 bytes: Île-de-France (modified 2026-11-27), Tours (2026-11-27), Agen (2015-04-23), "Offres d'emploi diffusées à France Travail" id 561fc15688ee3836b1628efc. Second search `q=BPCE offres emploi` -> 200: "Groupe BPCE - Offres emploi publiques", 2026-11-26, publisher "BPCE - DRH Groupe" | - |
| 22 | La bonne alternance API: `access_type: open_with_account`, free, "de 5 à 20 appels / seconde", licence none in the record, search by ROME or RNCP code, place, diploma level, radius; offers plus companies likely to hire apprentices | CONFIRMED | GET https://www.data.gouv.fr/api/1/dataservices/api-la-bonne-alternance/ -> 200, 20,989 bytes: all values; "Accéder gratuitement et en temps réel"; `license` null. GET https://api.apprentissage.beta.gouv.fr/fr/documentation-technique -> 200, 91,288 bytes: "Se connecter / S'inscrire"; footer "les contenus de ce site sont proposés sous licence etalab-2.0" | - |
| 23 | La bonne alternance: publisher DINUM; whether a job seeker may use it is not stated | CORRECTED | GET https://api.apprentissage.beta.gouv.fr/fr/cgu -> 200, 101,033 bytes ("Dernière mise à jour le : 31 mars 2025 - v1.0"): "« Éditeur » : désigne la Délégation générale à l'emploi et à la formation professionnelle (DGEFP)"; "L'inscription est gratuite et ouverte à tous"; "« Utilisateur » : désigne toute personne physique qui souhaite accéder aux données de l'apprentissage"; "Il s'engage à ne pas commercialiser les données reçues et à ne pas les communiquer à des tiers" | Open to any natural person with a free account; the data may not be sold or passed on. Editor per the terms: DGEFP. |
| 24 | APEC: terms not read; the site refused the client with 403 (DataDome) | UNVERIFIED | No request made (blocked host) | - |
| 25 | HelloWork group terms (read on maformation.fr): automated systems are "utilisateurs non légitimes"; extraction by automated systems "à quelques fins que ce soit, commerciales ou non, est strictement interdite"; download, display and printing allowed "à des fins exclusivement privées et non commerciales"; "le Site" covers hellowork.com and jobijoba.com | CONFIRMED | GET https://www.maformation.fr/cgu.html -> 200, text/html, 93,432 bytes: the three clauses word for word (Art. 1, 8.2, 8.1); "Le « Site » : [...] hellowork.com, blogdumoderateur.com, helloworkplace.fr, maformation.fr, hellowork-group.com, mon-compte-formation.fr, jobijoba.com, holeest.com, hellocv.com, cvcatcher.io" | - |
| 26 | hellowork.com robots.txt: all agents "Disallow: /*?", "/fr-fr/emploi/recherche.html", "/fr-fr/offres/postuler", "/fr-fr/api/", "/fr-fr/rss/", "/fr-fr/page/cgu/"; several hundred named agents shut out | CONFIRMED | GET https://www.hellowork.com/robots.txt -> 200, text/plain, 18,595 bytes: those lines; 554 `User-agent` lines, among them "Python-urllib" and "Wget" | - |
| 27 | Indeed terms "Dernière mise à jour : 1er avril 2026": job seekers may use the site "à des fins personnelles et non commerciales de recherche d'emploi"; forbidden to "Utiliser un système automatisé (bots, agrégateurs (« scrapers »), « spiders », IA ou IA agentique) pour accéder, extraire des données ou soumettre du contenu au Site [...] sans l'autorisation écrite expresse d'Indeed"; automating applications forbidden | CONFIRMED | GET https://fr.indeed.com/legal -> 200, text/html, 665,417 bytes: all three passages word for word (the one request made to Indeed) | - |
| 28 | LinkedIn User Agreement "Effective on November 3, 2025", 8.2: no "software, devices, scripts, robots [...] to scrape or copy the Services"; no "bots or other unauthorized automated methods to access the Services"; no copying of information "without the consent of the content owner" | CONFIRMED | GET https://www.linkedin.com/legal/user-agreement -> 200, text/html, 184,070 bytes: all three word for word (the one request made to LinkedIn) | - |
| 29 | Welcome to the Jungle terms: licence "solely for your own personal use"; forbidden to "Develop, support, or use any software, device, script, robot [...] to web "scrape" or otherwise copy or download our Website, Content or Services" | CONFIRMED | GET https://www.welcometothejungle.com/en/pages/terms -> 200, text/html, 315,527 bytes: both passages word for word (one request) | - |
| 30 | Indeed, LinkedIn and Welcome to the Jungle offer no public reading API or feed | NOT DISPROVED | Not searched on their sites (one request each, spent on the terms). Welcome to the Jungle's recruiting API is token-gated (claim 49) | - |
| 31 | Cadremploi refused the client (403, Cloudflare) | UNVERIFIED | No request made (blocked host) | - |
| 32 | Meteojob robots.txt, all agents: "Disallow: /api/", "Disallow: /*?" with "Allow: /jobs?*", "Disallow: /postuler/postuler-a-des-offres-d-emploi", "Disallow: /company/" | CONFIRMED | GET https://www.meteojob.com/robots.txt -> 200, text/plain, 730 bytes: those lines | - |
| 33 | monster.fr answers 301 to https://www.monster.com/fr/ | CONFIRMED | GET https://www.monster.fr/ -> 301, `location: https://www.monster.com/fr/` (not followed) | - |
| 34 | monster.fr stopped in July 2025 when Monster Europe was liquidated | UNVERIFIED | Third-party reports; not requested | - |
| 35 | JobTeaser forbids "l'utilisation de robots ou de tout autre procédé d'extraction automatique" | UNVERIFIED | GET https://www.jobteaser.com/fr/about/terms-for-members -> 301 to a PDF on d1guu6n8gz71j.cloudfront.net (another host; not followed) | Per a search summary the clause is narrower: a ban on downloading all or a substantial part of the service with robots. |
| 36 | Dares' JOCAS database of scraped adverts: no open access found | NOT DISPROVED | Not requested. A search summary of a public-statistics project page (ssphub.netlify.app) says the data is open to students, researchers and civil servants, and to others on request to Dares for statistical, non-commercial use | - |
| 37 | Official vacancy statistics exist on data.gouv.fr ("Offres d'emploi diffusées à France Travail", licence `fr-lo`) | CONFIRMED | Portal search (`/api/1/datasets/?q=offres d'emploi` -> 200, 24 results): that dataset, publisher France Travail, `license` fr-lo, modified 2024-02-09. No further request: statistics | - |
| 38 | Local open datasets: Île-de-France, Tours, Agen (stale) | CONFIRMED | Same search: "Offres d'emploi - Tours" (Ville de Tours, lov2, daily, modified 2026-11-28), "Offres d'emploi - Tours Métropole Val de Loire" (lov2, daily, 2026-11-28), "Offres d'emploi de la Région Île-de-France" (lov2), "Offres d'emplois en direct" (Agen, 2015, licence not specified) | Tours has two datasets (city and metropolis), both Licence Ouverte 2.0. |
| 39 | 347,200 offers were published on Choisir le service public in 2025; the publisher does not plan to publish full content; a "Documentation API CSP" PDF is about publishing INTO the portal | UNVERIFIED | None requested (budget). A search result lists the PDF at `https://choisirleservicepublic.gouv.fr/wp-content/uploads/2026/08/Documentation-API-CSP.pdf` and summarises it as publication from the Cegid/Talentsoft recruiting module | - |
| 40 | EURES showed 427,029 vacancies with a workplace in France | UNVERIFIED | Not requested; belongs to the EU-wide file's check | - |
| 41 | Sirene: Licence Ouverte 2.0 (`lov2`), monthly stock files (legal units zip 984,970,049 bytes, establishments 2.9 GB, also Parquet), tags `hvd` and `entreprises-et-propriete-dentreprises`, stable URLs to be used for automation | CONFIRMED | GET https://www.data.gouv.fr/api/1/datasets/base-sirene-des-entreprises-et-de-leurs-etablissements-siren-siret/ -> 200, 63,141 bytes: publisher Insee, `license` lov2, `frequency` monthly, files of 1 November 2026 (984,970,049 and 2,892,689,384 bytes; Parquet 717,824,037 and 2,231,588,933), tags `hvd`, `entreprises-et-propriete-dentreprises`; "Pour toute procédure d'automatisation, il faut utiliser les URL stables." | - |
| 42 | Sirene bulk files carry no website, e-mail or telephone | CONFIRMED | Insee's own variable lists: GET `.../stockunitelegale-311-dessin-de-fichier.csv` -> 200, 3,165 bytes (35 variables) and `.../stocketablissement-311-dessin-de-fichier.csv` -> 200, 4,875 bytes (54 variables): no variable named web, url, mail, courriel, telephone or site | - |
| 43 | Keyless search API `https://recherche-entreprises.api.gouv.fr/search?q=<text>&per_page=1`: name, status, creation date, seat address with coordinates, legal form, SIREN/SIRET, NAF code and NAF 2025 code, employee bracket with year, size class, establishments, directors; no website, e-mail or telephone; `q=doctolib` gives 1 of 8 results in 10,572 bytes; updated 2026-11-28 | CONFIRMED | GET of that address with `q=doctolib` -> 200, application/json, 10,572 bytes, no key sent: `total_results` 8; `nom_complet`, `etat_administratif`, `date_creation`, `siege.adresse`, `siege.coordonnees`, `nature_juridique`, `siren`, `siege.siret`, `activite_principale` 62.01Z, `activite_principale_naf25`, `tranche_effectif_salarie` 42 (2024), `categorie_entreprise` ETI, `nombre_etablissements` 9, `dirigeants`, `date_mise_a_jour` 2026-11-28T10:35:25; no web, mail or phone key | - |
| 44 | Insee's own Sirene API needs a free key (not checked) | CONFIRMED | Dataset record's description: "Pour accéder à l'API Sirene, vous devez d'abord créer un compte sur le portail" (portail-api.insee.fr). The portal itself not requested; "free" not seen | An account on Insee's API portal is needed; cost not seen. |
| 45 | Persons who opposed diffusion are partly masked (`statut_diffusion`) | CONFIRMED | Variable `statutDiffusionUniteLegale` in the list; API record `statut_diffusion` "O"; record description: representatives' data "ne sont pas diffusées par l'Insee en Open Data" | - |
| 46 | Cegid Talentsoft: "Job Board API allows job boards vendors to integrate with Talentsoft" (partners); no keyless feed | CONFIRMED | GET https://developers.cegid.com/docreference/BusinessUnits/Recruiting-developer-portal/jobboard/_index.html -> 200, 5,558 bytes: that sentence. GET `.../JobadService/documentation.html` -> 200, 11,248 bytes: the career-site API needs "a client_id and a client_secret" and a token | - |
| 47 | Flatchr: JSON API only with the employer's key ("Authorization: Bearer API_KEY", generated in the workspace); career pages at `careers.flatchr.io/company/{SLUG}` for iframes; no keyless feed documented | CONFIRMED | GET https://developers.flatchr.io/en/docs/getting_started/ -> 200, 24,596 bytes: "Your API_KEY must be generated in your Flatchr workspace", "Authorization: Bearer API_KEY". GET https://developers.flatchr.io/en/site-carriere/ -> 200, 43,152 bytes: iframe `https://careers.flatchr.io/company/{SLUG}?iframe=true`; "If you want to retrieve your listings in JSON format, you can do so via the API" | - |
| 48 | Taleez: no public documentation located | CORRECTED | GET https://taleez.com/ -> 200, 357,310 bytes: "Une API publique documentée permet également de connecter Taleez à votre écosystème spécifique"; link "Documentation API" -> https://api.taleez.com/ (not opened) | Taleez advertises a documented API; whether it needs a key, and whether a board can be read without one, is not on the page read. |
| 49 | Welcome Kit (Welcome to the Jungle) API is token-gated (per third parties; vendor docs not read) | CONFIRMED | GET https://developers.welcomekit.co/ -> 200, 394,329 bytes ("Welcome to the Jungle Solutions API"): "In order to use the following endpoints, you will have to request an authentication token" | Now confirmed from the vendor's own documentation. |
| 50 | Beetween is a French recruiting-software vendor (public feed: not checked) | CONFIRMED | GET https://support.beetween.com/en/knowledge/documentation-api -> 200, 268,275 bytes: a push connector - "the API is created on the jobboard and will be called by Beetween"; an "XML feed" page for job boards exists in the same help centre (not read). No keyless feed of an employer's board documented on the page read | Vendor sourced; documents delivery to job boards, not a public feed. |
| 51 | JobAffinity is a French recruiting-software vendor (public feed: not checked) | CONFIRMED | www.jobaffinity.fr -> 301 -> jobaffinity.fr -> 303 to a login (`/user/`, not followed). GET https://help.jobaffinity.fr/en/articles/11561675-automatic-posting-on-your-wordpress-site -> 200, 92,891 bytes ("Job Affinity Help Center"): the product pushes offers into the employer's WordPress site over XML-RPC. No public feed documented on the page read | Vendor sourced; no public feed documented. |
| 52 | Softy is a French recruiting-software vendor (public feed: not checked) | CONFIRMED | www.softy.pro -> 307 -> v2.softy.pro -> 307 to a login (not followed). GET https://recrutement.softy.pro/ -> 200, 418,323 bytes ("Logiciel de recrutement Softy"): career site and multiposting to "plus de 100 jobboards"; no word API, feed, flux, XML or RSS on the page | Vendor sourced; no public feed documented. |
| 53 | DigitalRecruiters is a French recruiting-software vendor (public feed: not checked) | UNVERIFIED | GET https://www.digitalrecruiters.com/ -> 301 to https://www.cegid.com/fr/produits/cegid-hr/talent-acquisition/ (another site; not followed) | not sourced - drop (the Cegid row covers it). |
| 54 | Teamtailor has a keyless public feed per employer board (EU-wide file) | CONFIRMED | GET https://support.teamtailor.com/en/articles/11171756-rss-feed-how-to-guide -> 200, 101,810 bytes: "Go to the main jobs page of your careers site and add ".rss""; "all of the data is publicly available"; "the RSS feed will show the first 100 jobs" | - |
| 55 | Greenhouse has a keyless Job Board API | CONFIRMED | developers.greenhouse.io/job-board.html -> 301 -> GET https://docs.greenhouse.io/job-board.html -> 200, 142,149 bytes: "Only the application submission endpoint (POST ...) requires Basic Auth."; "Requests may be rate limited for security and traffic reasons." | - |
| 56 | Lever has a keyless Postings API | CONFIRMED | GET https://raw.githubusercontent.com/lever/postings-api/master/README.md -> 200, 25,813 bytes: "all job postings in the `published` state are publicly viewable. These jobs may be scraped by third parties."; an API key only "To use the POST API"; EU base `https://api.eu.lever.co/v0/postings/` | - |
| 57 | SmartRecruiters has a public Posting API | CONFIRMED | GET https://developers.smartrecruiters.com/docs/posting-api -> 200, 234,241 bytes: "Posting API allows for access to a job posting that was previously made public"; also "The Public Posting API supports both API Key and OAuth 2.0 Client Credentials authentication [...] anyone with a valid API key or OAuth token can access all internal postings" | The page documents the API; it does not say in so many words that public postings need no key. |
| 58 | Workable has keyless public account endpoints | CONFIRMED | GET https://workable.readme.io/reference/jobs-1 -> 200, 287,991 bytes: under "Public Endpoints", `GET https://www.workable.com/api/accounts/{subdomain}` "Returns a collection of the public jobs for an account" | - |
| 59 | Recruitee has a keyless Careers Site API | CONFIRMED | GET https://docs.recruitee.com/reference/offers -> 200, 197,897 bytes: `GET https://{yourcompany}.recruitee.com/api/offers/` "Returns a collection of published company jobs."; the Careers Site API menu also has an "Authentication" page (not read) | The endpoint is documented; that it needs no key is not stated on the page read. |
| 60 | Personio has a keyless XML feed | CONFIRMED | GET https://developer.personio.de/docs/retrieving-open-job-positions -> 200, 175,942 bytes: "Current open job postings can be retrieved in XML format under myaccount.jobs.personio.de/xml"; no word token or authentication on the page | - |
| 61 | Workday: no vendor documentation of a public feed (EU-wide file) | NOT DISPROVED | GET https://www.workday.com/en-us/products/talent-management/talent-acquisition.html -> 200, 728,527 bytes: a product page; no mention of an API, feed, RSS or XML | - |
| 62 | French Tech directory by Numeum: members of Next 40, French Tech 120, French Tech 2030 with website ("Voir le site"), 30 companies on the first page, 140,572 bytes | CONFIRMED | GET https://frenchtech120.numeum.fr/annuaire/ -> 200, text/html, 140,572 bytes: "L'annuaire French Tech 120 par Numeum"; programme years 2020-2026; "Voir le site" 30 times. Terms not read | - |
| 63 | Annuaire des Entreprises is the State's company search built on Sirene; no website field confirmed | UNVERIFIED | GET https://annuaire-entreprises.data.gouv.fr/ -> 302 to itself with Incapsula cookies and a "Loading" page; not asked again | - |
| 64 | No open, keyless source gives links to employers' own pages | NOT DISPROVED | The weekly file and the Île-de-France dataset have no link column (seen). emploi-territorial.fr's API has a field `url_of_cand` ("Lien pour candidater sur l'offre") but needs a token | - |
| 65 | No market-share figure for applicant-tracking systems in France was found | NOT DISPROVED | Not searched further | - |

## For a personal job search and applications

| Source | Usable for own job search | Why (the deciding clause if "no") |
|---|---|---|
| France Travail - offer pages (candidat.francetravail.fr) | unclear | Terms silent on programs; robots.txt closes keyword-search URLs (`*motsCles=*`) and account pages only |
| France Travail - API Offres d'emploi | no | Partners only, and closed: "L'accès à l'API Offres d'emploi est actuellement suspendu pour les nouveaux requérants"; private persons: "no" in the publisher's record |
| Choisir le service public - site | unclear | Terms silent on programs; robots.txt closes only the PDF copies and the admin area |
| Choisir le service public - weekly file | yes | Licence Ouverte 2.0, no key; summary fields only, no link, expired offers included |
| Choisir le service public - yearly files 2022-2025 (past adverts) | yes | Licence Ouverte 2.0; four files of 141-168 MB, same 30 columns: employer's organisation by name ("Organisme de rattachement", "Employeur"), no registration number; occupation ("Métier") and "Compétences attendues" |
| emploi-territorial.fr - site | unclear | Terms not read; robots.txt closes `/exportoffres/` |
| emploi-territorial.fr - API | no | By token on request: "L'accès à ces ressources nécessite une authentification, contactez le GIP Informatique des CDG" |
| Région Île-de-France dataset | yes | Licence Ouverte 2.0, keyless API; one employer, 152 offers, full text, no link |
| Tours datasets (city, metropolis) | yes | Licence Ouverte 2.0 on the portal's records; data not requested; one employer each |
| Groupe BPCE dataset | unclear | Licence not read |
| La bonne alternance API | yes | Free account "ouverte à tous", user "toute personne physique"; apprenticeship offers only; no resale or passing on. Not tested (no account made) |
| APEC | unclear | Terms could not be read (blocked host) |
| HelloWork (and JobiJoba) | no | "l'utilisation de systèmes automatisés ou de logiciels pour extraire des données du Site [...] à quelques fins que ce soit, commerciales ou non, est strictement interdite" |
| Indeed | no | Forbidden: "Utiliser un système automatisé (bots, agrégateurs (« scrapers »), « spiders », IA ou IA agentique) pour accéder, extraire des données" |
| LinkedIn | no | "Use bots or other unauthorized automated methods to access the Services" |
| Welcome to the Jungle | no | "use any software, device, script, robot [...] to web "scrape" or otherwise copy or download our Website, Content or Services" |
| Cadremploi | unclear | Terms could not be read (blocked host) |
| Meteojob | unclear | Terms not read; robots.txt closes `/api/` and query URLs except `/jobs?` |
| JobTeaser | unclear | Terms not read (redirect to another host) |
| Monster France | unclear | Site gone: 301 to monster.com/fr/; terms there not read |
| Dares JOCAS (past adverts scraped from about fifteen sites) | unclear | Access by status or on request, per a third-party page; licence, years, size and fields not read in its own documentation |
| Sirene (bulk files and recherche-entreprises API) | yes | Licence Ouverte 2.0, no key; every company with address, activity and size bracket; no website |
| French Tech directory (Numeum) | unclear | Terms not read; lists company websites |
| Annuaire des Entreprises | unclear | Not read (bot check) |
| Employers' boards on Teamtailor, Greenhouse, Lever, Workable, Personio | unclear | Vendors document keyless reading (Lever: "may be scraped by third parties"; Teamtailor: "publicly available"); no licence stated; use in France not established |
| Employers' boards on Cegid Talentsoft, Flatchr, Welcome Kit | no | Key or token of the employer or a partner needed (e.g. Flatchr: "Authorization: Bearer API_KEY") |

## Found beyond the research

- **emploi-territorial.fr API** (claim 17): documented in the open (OpenAPI file at `/api/emploi-territorial.yml`),
  token on request from the GIP Informatique des CDG (support@gipcdg.fr), named licence "Etalab 2.0". Its offer
  model has an apply link (`url_of_cand`) and an application e-mail (`email_dest_cand_of`).
- **La bonne alternance** terms (claim 23): open to any natural person; the API also has a route to send an
  application ("Envoyer une candidature à une opportunité d'emploi en alternance", record description).
- **France Travail's other services** on data.gouv.fr (`/api/1/dataservices/?organization=534fffa3a3a7292c64a78094`
  -> 200, 13 services): only "API Offres d'emploi" changed in October 2026. Marked `access_type: open`: "API La
  Bonne Boite" (companies likely to hire - an employer-route source), "API Marché du travail", "API ROME 4.0",
  "API Référentiel des agences". Their portal pages are on francetravail.io (script-only) and were not read.
- **Sirene has an employer flag**: `caractereEmployeurUniteLegale` / `caractereEmployeurEtablissement` in the bulk
  files and `caractere_employeur` in the API, beside the size bracket - a way to keep only units with staff. The
  API record also returns `finances` (turnover, net result) and collective-agreement flags.
- **Weekly file**: the data.gouv.fr record links the portal's "API tabulaire" (`tabular-api.data.gouv.fr`, open,
  CSV up to 100 MB by default); the current file is 152 MB, so it is probably not served there (not tested).
- **More local datasets** on data.gouv.fr: "Offres d'emploi - Tours Métropole Val de Loire" (a second Tours
  dataset) and "Offres d'emploi Grand Besançon Métropole, Ville de Besançon, CCAS de Besançon" (2020, licence
  not specified, stale).
- **Cegid**: besides the partner Job Board API, a "Job advertising service" API for career sites
  (`/{brandId}/api/jobseeker/v{n}/...`) exists; it needs a client id and secret. DigitalRecruiters' site now
  redirects to Cegid's "Talent Acquisition" product page.
- **Choisir le service public** has a sitemap index, but all six sitemaps date from 2023-04-14 and none lists
  offers.
