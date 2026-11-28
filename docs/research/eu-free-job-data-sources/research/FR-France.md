# France (FR) - free online job data sources: research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (`curl/8.14.1`, no added headers, one
capped GET per URL), and web search for finding pages. No account, key or login was used. Requests made, per
host: www.data.gouv.fr 8 (open data portal API), choisirleservicepublic.gouv.fr 3, www.emploi-territorial.fr 3,
developers.flatchr.io 3 (two were redirects), candidat.francetravail.fr 2, and 1 each to francetravail.io,
www.francetravail.fr, static.data.gouv.fr, data.seinesaintdenis.fr, data.iledefrance.fr, data.europa.eu,
recherche-entreprises.api.gouv.fr, www.hellowork.com, www.maformation.fr, www.meteojob.com, www.apec.fr (403),
www.cadremploi.fr (403), www.monster.fr, fr.indeed.com, www.linkedin.com, www.welcometothejungle.com,
developers.cegid.com, frenchtech120.numeum.fr. The three hosts that masi's files name (Indeed, LinkedIn, Welcome
to the Jungle) got one request each, to their terms page.

## Takeaway

France's best source on paper, France Travail's "API Offres d'emploi" (all offers shown on francetravail.fr,
free, OAuth key from the developer portal), is **closed to new users today**: France Travail's own record on
data.gouv.fr says the API "n'est actuellement plus exposée sur www.francetravail.io" after "usages automatisés
massifs par certaines solutions d'intelligence artificielle", and its reply of 19 October 2026 says access "est
actuellement suspendu pour les nouveaux requérants"; the record marks access for private persons "no". What a
program may read for free without any agreement is therefore narrower: the public-service portal's weekly CSV of
every offer on Choisir le service public (Licence Ouverte 2.0, no key, no link or apply field), a few local
open datasets (Île-de-France region, Tours), and the apprenticeship-only API of La bonne alternance (free
account). France Travail's web pages themselves carry no clause against automated reading in their terms and a
robots.txt that only closes keyword-search URLs, but they are web pages, not a feed. Every large commercial board
whose terms could be read forbids automated reading outright (Indeed, HelloWork, LinkedIn, Welcome to the
Jungle); APEC and Cadremploi refused the client (403). For the employer route the company register is fully
open (Sirene, Licence Ouverte 2.0, bulk and keyless API, an EU high-value dataset) but carries no website or
e-mail.

## Sources

### France Travail - job offers on francetravail.fr (public employment service; formerly Pôle emploi)
- Publisher: France Travail (the national public employment service; "Pôle emploi" until 1 January 2024).
- Documentation: terms https://www.francetravail.fr/informations/informations-legales-et-conditio/conditions-generales-dutilisatio.html
  ("Date de mise à jour : 19/02/2024").
- Data or endpoint: https://candidat.francetravail.fr/offres/emploi (search; `/offres/recherche` redirects there).
- Holds: offers placed with France Travail by employers and offers passed on by partner sites for
  redistribution (the terms and the search page both speak of "offres partenaires"). Fields not examined on a
  detail page (none was requested).
- Access: web pages only for the public. The API is the next block.
- Registration or key: none to read offers: "Le site permet à toute personne, sans qu'il soit nécessaire de créer
  un espace personnel, de : [...] consulter des offres d'emploi".
- Cost: free.
- Licence or terms (exact wording, with URL): same terms page. §4.2: "Les offres d'emploi diffusées sur
  francetravail.fr sont transmises au portail Eures de l'Union européenne et sont mises à disposition via une
  API des partenaires de France Travail qui adhèrent à la licence de réutilisation des offres (à l'exception des
  données de contact). Ces offres pourront être réutilisées pour tout usage et notamment être rediffusées sur
  des sites tiers." §7: third parties' content may not be reused without their consent; "Les autres contenus
  constituent des informations publiques librement réutilisables sous réserve du respect de la licence ouverte
  pour la réutilisation d'informations publiques". robots.txt (https://candidat.francetravail.fr/robots.txt),
  for all agents, among others: "Disallow: *motsCles=*", "Disallow: /offres/selection", "Disallow:
  /offres/emploi:redirection*", "Disallow: /offres/recherchesenregistrees", "Disallow: /espacepersonnel/",
  "Disallow: /compte/"; four sitemaps under `/rechercheoffre/sitemap/`.
- For a personal job search: job-seeker use allowed (the site's stated object: services "à destination des
  personnes à la recherche d'un emploi", offers readable without an account); automated reading not stated in
  the terms (no clause on robots, scripts or extraction was found in the page), and robots.txt forbids only
  keyword-search URLs (`*motsCles=*`) and account pages, not offer pages; private copy not stated.
- How to apply: per the terms, with a "candidat" personal space one can "consulter et s'abonner à des offres
  d'emploi, télé-candidater à des offres d'emploi"; whether an offer page also shows the employer's contact or an
  external link was not checked (no offer page requested). Partner offers are shown as coming from partner sites.
- Volume: not read from the site. On the EURES portal 427,029 vacancies had a workplace in France on
  2026-11-28 (this study's EU-wide file, one request to the EURES search back end).
- Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 1,321 bytes; GET /offres/recherche -> 301 to
  /offres/emploi with a 66,556-byte HTML body (the search form; no count in its text); GET of the terms page
  -> 200, text/html, 74,673 bytes.
- Caveats: the third request to the host was not spent; no offer page or result list was read.

### France Travail - API Offres d'emploi (francetravail.io)
- Publisher: France Travail; developer portal francetravail.io ("anciennement dénommé Emploi Store Développeurs").
- Documentation: https://francetravail.io/produits-partages/catalogue/offres-emploi/documentation#/ (a script-only
  page for this client); the publisher's record on the national portal:
  https://www.data.gouv.fr/dataservices/api-offres-demploi (metadata modified 2026-10-20).
- Data or endpoint: not given any more: the record's "base_api_url" is now `https://francetravail.io/contact`.
- Holds: "restitue en temps réel les offres d'emploi actives collectées par France Travail ou que France Travail
  a reçues de ses partenaires à la condition que ceux-ci aient consenti à leur mise à disposition dans l'API";
  search with paged results, offer detail ("intitulé, lieu, entreprise, contrat..."), reference lists.
- Access: API, `access_type: restricted` (reason given: "Analyse de sécurité"). Audiences in the record: local
  authorities and administrations "under_condition", companies and associations "under_condition", private
  persons "no". Rate limit "10 appels / seconde".
- Registration or key: was a free self-service key on the portal; **today new access is suspended**. The
  record: "L'API Offre d'emploi de France Travail n'est actuellement plus exposée sur www.francetravail.io le
  temps d'une analyse des modalités de distribution et de réutilisation du service. Cette démarche fait suite à
  la constatation d'usages automatisés massifs par certaines solutions d'intelligence artificielle ne
  respectant pas les conditions et licences de réutilisation associées à l'API. Les organismes ayant un besoin
  d'accès au service peuvent adresser leur demande via le formulaire de contact". France Travail's reply in the
  record's discussion (2026-10-19): "L'accès à l'API Offres d'emploi est actuellement suspendu pour les nouveaux
  requérants, le temps de mener une analyse sur les nouvelles demandes de consommation. Les consommateurs
  disposant déjà d'un accès le conservent et peuvent continuer à utiliser l'API dans le cadre de leur
  consommation actuelle."
- Cost: free.
- Licence or terms (exact wording, with URL): a "licence de réutilisation des offres" that partners adhere to
  (francetravail.fr terms, quoted above); its text sits on the portal and was not readable (script-only page).
- For a personal job search: job-seeker use not stated (the record describes developers of "solutions
  personnalisées de recherche d'emploi pour un site ou une application"; its audience list gives private
  persons "no"); automated reading is the API's purpose but only for holders of a key, and none is issued to new
  applicants now; private copy not stated (licence text not read).
- How to apply: not confirmed today (the field list is in the documentation that could not be read).
- Volume: not stated in the record.
- Update cycle: real time.
- Seen on 2026-11-28: GET https://www.data.gouv.fr/api/1/dataservices/api-offres-demploi/ -> 200,
  application/json, 6,724 bytes (the text quoted); GET of its discussions -> 200, 8,826 bytes (two threads,
  October 2026); GET https://francetravail.io/data/api/offres-emploi -> 200, text/html, 2,000 bytes (an empty
  application shell, `<peio-root>`).
- Caveats: no end date is given for the suspension. A copy of the API's output published as an open dataset by
  the Seine-Saint-Denis department (data.gouv.fr record created 2026-11-12, Licence Ouverte 2.0) was archived on
  2026-11-22 as "not-on-remote", and its source answers 404 today ("The requested dataset
  france-travail-offres-d-emploi does not exist").

### Choisir le service public - the public service's job portal (site)
- Publisher: Direction générale de l'administration et de la fonction publique (DGAFP).
- Documentation: legal notice https://choisirleservicepublic.gouv.fr/mentions-legales/
- Data or endpoint: https://choisirleservicepublic.gouv.fr/nos-offres/
- Holds: vacancies of the three branches of the public service (State, territorial, hospital), placed by public
  employers or passed on by partner sites.
- Access: web pages; the offers as a weekly open file (next block).
- Registration or key: none to read; an account ("votre espace") to apply.
- Cost: free.
- Licence or terms (exact wording, with URL): legal notice: "Le Site est destiné à toute personne [...] qui
  souhaite rechercher une offre d'emploi et déposer une candidature dans la fonction publique." and "Il doit
  être accessible à l'utilisateur aux seules fins de lui permettre de consulter les offres d'emploi et déposer
  sa candidature." Page footer: "Sauf mention contraire, tous les textes de ce site sont sous licence
  etalab-2.0". robots.txt, whole rule set for all agents: "Disallow: /wp-admin/", "Disallow:
  /wp-content/uploads/pdf-offers/", "Allow: /wp-admin/admin-ajax.php".
- For a personal job search: job-seeker use allowed (quoted); automated reading not stated (no clause; robots.txt
  closes only the PDF copies of offers and the admin area); private copy not stated (texts under Licence Ouverte
  2.0 "sauf mention contraire").
- How to apply: on the site, with the candidate account; the recruitment platform behind it is run by Talentsoft
  (named in the legal notice). Whether an offer also names a contact was not checked.
- Volume: 347,200 offers published in 2025 (DGAFP statistics note, from a search summary).
- Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, 173 bytes; GET /mentions-legales/ -> 200, text/html, 171,784 bytes;
  GET /nos-offres/ -> 200 but the transfer was cut at the 2,000,000-byte cap; the part received held no offer
  links (the list is filled by script).
- Caveats: a "Documentation API CSP" PDF exists on the site (2026-08) - by its search summary it is about
  employers' recruiting software publishing offers INTO the portal, not about reading them. Not fetched (three
  requests used).

### "Les offres diffusées sur Choisir le Service Public" - weekly open file
- Publisher: DGAFP.
- Documentation: https://www.data.gouv.fr/datasets/les-offres-diffusees-sur-choisir-le-service-public (two PDFs
  and a reference workbook listed as resources; not fetched).
- Data or endpoint:
  https://static.data.gouv.fr/resources/les-offres-diffusees-sur-choisir-le-service-public/20261123-070111/offres-datagouv-20261122.csv
  (the file name changes every week; the current one is in the dataset record,
  https://www.data.gouv.fr/api/1/datasets/les-offres-diffusees-sur-choisir-le-service-public/).
- Holds: one line per offer, 30 columns (semicolon-separated): "Organisme de rattachement; Référence; Versant;
  Métier; Statut du poste; Nature de l'emploi; Durée du contrat; Intitulé du poste; Localisation du poste; Lieu
  d'affectation; Niveau d'études; Niveau d'expérience min. requis; Date de vacance de l'emploi; Date de début de
  publication par défaut; Date de fin de publication par défaut; Date de première publication; Spécialisation;
  Télétravail; Management; Employeur; Catégorie; Temps Plein; Durée du poste; Langues; Niveaux; Lieu
  d'affectation (sans géolocalisation); Avis de vacances au JO; Compétences attendues; Documents à transmettre;
  Nature de contrat". Territorial offers are in it too (rows with "Fonction Publique Territoriale"). No salary,
  no description of the duties, **no URL and no contact column**.
- Access: bulk CSV.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): the record's licence is `lov2` = Licence Ouverte / Open Licence
  version 2.0 (https://www.etalab.gouv.fr/licence-ouverte-open-licence).
- For a personal job search: job-seeker use allowed (open licence, any use with attribution); automated reading
  allowed (a file published for download); private copy allowed.
- How to apply: not from the file - it has the offer's "Référence" only; the offer has to be found on the site
  by that reference and the application made there.
- Volume: the current file is 151,904,521 bytes (offers published since 1 January 2026, by its first rows);
  yearly files of 141-168 MB for 2022-2025.
- Update cycle: weekly ("mises à jour à une fréquence hebdomadaire"; last file 2026-11-23).
- Seen on 2026-11-28: dataset record -> 200, application/json, 21,453 bytes; GET of the CSV with a byte range
  0-5999 -> 206, text/csv, 6,000 bytes (header and six rows).
- Caveats: the publisher has said it does not plan to publish the offers' full content there (dataset
  discussion, from a search summary). On data.europa.eu the French portal's records keep their data.gouv.fr
  identifier (seen for "Offres d'emploi diffusées à France Travail",
  https://data.europa.eu/data/datasets/561fc15688ee3836b1628efc); this dataset's EU entry was not requested.

### emploi-territorial.fr - territorial civil service
- Publisher: the Centres de Gestion de la Fonction Publique Territoriale and the CNFPT; "Site développé et
  maintenu par le GIP Informatique des Centres de Gestion".
- Documentation: a footer link "Données accessibles par API" (`/api`); not read (see Seen).
- Data or endpoint: https://www.emploi-territorial.fr/ (search `/rechercher?...`).
- Holds: vacancies of local authorities; the home page counts them by category: A+ 198, A 6,915, B 8,201,
  C 16,137 (31,451 together), and 72 internship or apprenticeship offers.
- Access: web pages; an API is announced but its terms were not read.
- Registration or key: none to search; an account for alerts and CV.
- Cost: free.
- Licence or terms (exact wording, with URL): not read. robots.txt: "User-agent: SemrushBot Disallow: /" and
  for all agents "Disallow: /exportoffres/", "Disallow: /arretes/normal/*.pdf", "Disallow:
  /arretes/annul/*.pdf".
- For a personal job search: job-seeker use allowed in practice (a public job portal; no terms read); automated
  reading not stated (robots.txt closes `/exportoffres/` only); private copy not stated.
- How to apply: not checked (FAQ entry "Comment postuler à une offre d'emploi ?" not read).
- Volume: about 31,400 live offers (above).
- Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, 138 bytes; GET / -> 200, text/html, 139,656 bytes; GET /api -> 301
  to `http://www.emploi-territorial.fr/api/` (not followed: third and last request to the host).
- Caveats: what the API offers, and to whom, is unknown; one web search found no description of it.

### Local and sector open datasets of vacancies (data.gouv.fr, Opendatasoft portals)
- Publisher: each authority; e.g. Région Île-de-France, Tours Métropole Val de Loire; one company (Groupe BPCE).
- Documentation: https://data.iledefrance.fr/explore/dataset/offres-emploi-region-iledefrance/ ; EU entries
  found by one search on data.europa.eu: "Offres d'emploi de la Région Île-de-France" (modified 2026-11-27),
  "Offres d'emploi - Tours" (2026-11-27), "Groupe BPCE - Offres emploi publiques" (2026-11-26), "Offres d'emplois
  en direct" (Agen, 2015, stale).
- Data or endpoint:
  `https://data.iledefrance.fr/api/explore/v2.1/catalog/datasets/offres-emploi-region-iledefrance/records?limit=1`
- Holds (Île-de-France): the region's own vacancies: `vacancy_ref`, `vacancy_title`,
  `vacancy_activation_date`, department, unit, grade and category, `def_missions` (duties, text),
  `vac_profil` (profile). No URL, contact or salary field.
- Access: API (Opendatasoft Explore v2.1) and exports; no key.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): not read for these datasets (the record requested was a data
  record, not the dataset's metadata).
- For a personal job search: job-seeker use not stated; automated reading allowed in practice (a public open-data
  API); private copy not stated (licence not read).
- How to apply: no apply field; the reference has to be taken to the employer's site.
- Volume: 152 offers (Île-de-France, `total_count`).
- Update cycle: daily by the look of the dates (newest activation 2026-11-27).
- Seen on 2026-11-28: the request above -> 200, application/json, 17,885 bytes, one record.
- Caveats: single employers only. The Tours and BPCE datasets were not requested.

### La bonne alternance - apprenticeship offers API
- Publisher: Direction interministérielle du numérique (DINUM), "La bonne alternance".
- Documentation: https://api.apprentissage.beta.gouv.fr/fr/documentation-technique ; record
  https://www.data.gouv.fr/dataservices/api-la-bonne-alternance
- Data or endpoint: https://api.apprentissage.beta.gouv.fr (OpenAPI at `/api/swagger.json?lang=fr`); not requested.
- Holds: "l'ensemble des opportunités d'emploi en alternance" collected by the service and its partner sites,
  plus companies judged likely to hire apprentices; search by ROME or RNCP code, place, diploma level, radius.
- Access: API, `access_type: open_with_account`; "de 5 à 20 appels / seconde".
- Registration or key: a free account on the API site (per the record; not created).
- Cost: free ("Accéder gratuitement et en temps réel").
- Licence or terms (exact wording, with URL): none stated in the record (`license: None`).
- For a personal job search: job-seeker use not stated (the API is described for sites that show the offers);
  automated reading allowed with an account; private copy not stated.
- How to apply: the record says a site can let its users "contacter les recruteurs [...] directement depuis
  votre site" through the API; fields not read.
- Volume: not stated. Update cycle: real time.
- Seen on 2026-11-28: the data.gouv.fr record -> 200, application/json, 20,989 bytes.
- Caveats: apprenticeship and work-study contracts only.

### APEC (Association pour l'emploi des cadres)
- Publisher: Apec.
- Documentation: terms at https://www.apec.fr/infos-legales/infos-cgu.html (address from a search; not readable).
- Data or endpoint: https://www.apec.fr
- Holds: vacancies for managers and graduates ("cadres"). Not examined.
- Access: web only as far as known; no reading API was found by search.
- Registration or key: not applicable. Cost: free to browse.
- Licence or terms (exact wording, with URL): not read - the site refused this client.
- For a personal job search: job-seeker use not stated (terms not read); automated reading refused in practice
  (bot protection answered 403 to robots.txt); private copy not stated.
- How to apply: not checked.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET https://www.apec.fr/robots.txt -> 403, text/html, 767 bytes: "Please enable JS and
  disable any ad blocker", headers `x-datadome: protected`, a captcha-delivery.com script. The host was not
  asked again.
- Caveats: nothing about APEC's terms is confirmed from its own pages.

### HelloWork (formerly RegionsJob)
- Publisher: HELLOWORK (group sites include hellowork.com and jobijoba.com).
- Documentation: the group's terms, read at https://www.maformation.fr/cgu.html, which define "le Site" as
  "hellowork.com, blogdumoderateur.com, helloworkplace.fr, maformation.fr, hellowork-group.com,
  mon-compte-formation.fr, jobijoba.com, [...]". hellowork.com's own copy is under `/fr-fr/page/cgu/`, which its
  robots.txt disallows, so it was not requested.
- Data or endpoint: https://www.hellowork.com/fr-fr/ ; no feed or API for reading offers is offered
  (robots.txt disallows `/rss/` and `/api/`).
- Holds: job, internship and training offers. Not examined.
- Access: web only.
- Registration or key: none to browse. Cost: free to browse.
- Licence or terms (exact wording, with URL): Art. 1: "Les systèmes automatisés ou un logiciel accédant au Site
  sont expressément considérés comme des utilisateurs non légitimes de la base de données disponible sur le
  Site". Art. 8.2: "L'Utilisateur peut uniquement utiliser le Site aux fins d'accéder aux Services, ce
  exclusivement à des fins privées et non commerciales. [...] l'utilisation de systèmes automatisés ou de
  logiciels pour extraire des données du Site, en particulier le Contenu et la CVthèque (« capture de données
  d'écran » / « screen scraping / web scraping» notamment), à quelques fins que ce soit, commerciales ou non,
  est strictement interdite, à moins que HELLOWORK n'ait conclu une convention de licence écrite". Art. 8.1
  allows "[le] téléchargement, [...] l'affichage et [...] l'impression des données de ce site à des fins
  exclusivement privées et non commerciales". robots.txt (https://www.hellowork.com/robots.txt), all agents:
  "Disallow: /*?", "Disallow: /fr-fr/emploi/recherche.html", "Disallow: /fr-fr/offres/postuler", "Disallow:
  /fr-fr/api/", "Disallow: /fr-fr/rss/", "Disallow: /fr-fr/search/"; several hundred named agents (among them
  "Python-urllib", "Wget") get "Disallow: /".
- For a personal job search: job-seeker use allowed (private, non-commercial use of the services); automated
  reading forbidden - a ban on automated systems whatever the purpose ("commerciales ou non"); private copy
  limited (download, display and printing for exclusively private, non-commercial ends).
- How to apply: on the site (`/offres/postuler` pages); not examined.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET https://www.hellowork.com/robots.txt -> 200, text/plain, 18,595 bytes; GET
  https://www.maformation.fr/cgu.html -> 200, text/html, 93,432 bytes (no date on the text).
- Caveats: the terms were read on a sister site of the same publisher; that hellowork.com serves the same text
  is inferred from the text's own list of domains.

### Indeed (France and the other four countries of this pass)
- Publisher: Indeed (the contracting entity depends on the user's country, terms section D.13).
- Documentation: https://fr.indeed.com/legal ("Conditions d'utilisation", "Dernière mise à jour : 1er avril 2026").
- Data or endpoint: https://fr.indeed.com ; no reading API (this study's EU-wide file).
- Holds: adverts posted on Indeed and adverts it collects from employers' sites and feeds. Not examined.
- Access: web only.
- Registration or key: none to browse; an account to apply through Indeed.
- Cost: free for job seekers.
- Licence or terms (exact wording, with URL): job seekers: "En tant que Chercheur d'emploi, vous êtes autorisé à
  utiliser le Site et son contenu à des fins personnelles et non commerciales de recherche d'emploi ou
  d'informations relatives à votre recherche d'emploi." Site rules, forbidden: "Utiliser un système automatisé
  (bots, agrégateurs (« scrapers »), « spiders », IA ou IA agentique) pour accéder, extraire des données ou
  soumettre du contenu au Site, en bloc ou autrement, sans l'autorisation écrite expresse d'Indeed (nous
  accordons sous condition l'autorisation d'indexer le Site uniquement comme indiqué dans notre fichier
  robots.txt). Indexer, agréger, extraire des données, reproduire, dupliquer, copier, vendre, exploiter, échanger
  ou revendre une quelconque partie du Site". Applying: "L'utilisation de technologies d'automatisation,
  d'écriture de scripts ou de bots pour automatiser le processus de candidature sur Indeed en dehors des
  fournisseurs et des outils officiels d'Indeed est interdite."
- For a personal job search: job-seeker use allowed (personal, non-commercial job search); automated reading
  forbidden - a ban on bots, scrapers and "IA agentique" whatever the purpose; private copy forbidden as worded
  ("reproduire, dupliquer, copier [...] une quelconque partie du Site").
- How to apply: through Indeed (Indeed Apply, account) or on the employer's site where the advert sends there;
  automating the application is forbidden.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET https://fr.indeed.com/legal -> 200, text/html, 665,417 bytes. One request to Indeed in
  all; robots.txt was not requested.
- Caveats: one text for all Indeed country sites; it was read in its French version only.

### LinkedIn
- Publisher: LinkedIn (LinkedIn Ireland Unlimited Company for EU members, per the agreement).
- Documentation: https://www.linkedin.com/legal/user-agreement ("Effective on November 3, 2025").
- Data or endpoint: https://www.linkedin.com/jobs/ ; no public reading API for jobs.
- Holds: job adverts. Not examined.
- Access: web, mostly behind a login.
- Registration or key: an account for most use. Cost: free tier.
- Licence or terms (exact wording, with URL): section 8.2, the member agrees not to: "Develop, support or use
  software, devices, scripts, robots or any other means or processes (such as crawlers, browser plugins and
  add-ons or any other technology) to scrape or copy the Services, including profiles and other data from the
  Services"; "Use bots or other unauthorized automated methods to access the Services, add or download contacts,
  send or redirect messages [...]"; "Copy, use, display or distribute any information (including content)
  obtained from the Services, whether directly or through third parties [...], without the consent of the
  content owner".
- For a personal job search: job-seeker use allowed (the service's purpose: "find opportunities"); automated
  reading forbidden whatever the purpose; private copy forbidden as worded ("scrape or copy the Services").
- How to apply: on LinkedIn ("Easy Apply", account) or on the employer's site the advert links to; not examined.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET of the agreement -> 200, text/html, 184,070 bytes. One request to LinkedIn in all.
- Caveats: same agreement in all five countries of this pass.

### Welcome to the Jungle
- Publisher: Welcome to the Jungle (WTTJ).
- Documentation: https://www.welcometothejungle.com/en/pages/terms
- Data or endpoint: https://www.welcometothejungle.com/fr/jobs ; no public reading feed.
- Holds: adverts of client companies with company profiles. Not examined.
- Access: web only. Registration or key: none to browse. Cost: free for candidates.
- Licence or terms (exact wording, with URL): a "limited, revocable, non-exclusive, non-transferable,
  non-sublicensable license to access, view, and use the Platform solely for your own personal use. You cannot
  use any part of the Platform or any WTTJ Content, User Content or Recruiter Content [...] for any other use
  including commercial purposes." Forbidden: "Develop, support, or use any software, device, script, robot, or
  any other means or process (including but not limited to spiders, browser plug-ins and add-ons, or any other
  technology) to web "scrape" or otherwise copy or download our Website, Content or Services, including company
  profiles as well as any other data available on the Website (except that we grant the operators of public
  search engines revocable permission to use spiders [...] but not caches or archives of such materials)".
- For a personal job search: job-seeker use allowed (own personal use); automated reading forbidden whatever the
  purpose; private copy forbidden as worded ("otherwise copy or download").
- How to apply: on the platform or on the employer's own site, depending on the advert; not examined.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET of the terms -> 200, text/html, 315,527 bytes. One request to the host in all.
- Caveats: the company's recruiting software ("Welcome Kit") has an API that third parties describe as
  token-gated; nothing was requested from it.

### Cadremploi (Figaro group) and Meteojob (CleverConnect)
- Publisher: Cadremploi; Meteojob.
- Documentation: none read.
- Data or endpoint: https://www.cadremploi.fr ; https://www.meteojob.com
- Holds: job adverts. Not examined. Access: web only as far as checked.
- Registration or key: none to browse. Cost: free to browse.
- Licence or terms (exact wording, with URL): Cadremploi: not read (refused). Meteojob: terms not read;
  robots.txt (https://www.meteojob.com/robots.txt) for all agents: "Disallow: /api/", "Disallow: /*?" with
  "Allow: /jobs?*", "Disallow: /postuler/postuler-a-des-offres-d-emploi", "Disallow: /company/".
- For a personal job search: job-seeker use not stated (terms not read); automated reading - Cadremploi refused
  the client; Meteojob's robots.txt leaves `/jobs?` pages open and closes `/api/`; private copy not stated.
- How to apply: not checked.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET https://www.cadremploi.fr/robots.txt -> 403, text/html, 4,547 bytes, a Cloudflare page
  "Sorry, you have been blocked" (host not asked again); GET https://www.meteojob.com/robots.txt -> 200, 730 bytes.
- Caveats: Monster France is gone: `https://www.monster.fr/` answers 301 to `https://www.monster.com/fr/`, and
  third parties (Le Monde Informatique, blog-rh.com) report that monster.fr stopped in July 2025 when Monster
  Europe was liquidated.

### Official vacancy statistics (one line)
- France Travail's quarterly counts of offers ("Offres d'emploi diffusées à France Travail", licence `fr-lo`,
  https://www.data.gouv.fr/datasets/offres-demploi-diffusees-a-france-travail) and Dares series on offers
  collected and on vacant jobs are open on data.gouv.fr; aggregates only, of no use for this purpose.

## Through the employers

### Business register
- Publisher: Insee (Sirene register of companies and their establishments); the legal register (Registre national
  des entreprises) is INPI's and was not examined.
- Documentation: https://www.data.gouv.fr/datasets/base-sirene-des-entreprises-et-de-leurs-etablissements-siren-siret ;
  https://www.insee.fr/fr/information/3591226 (not fetched); API https://recherche-entreprises.api.gouv.fr
- Data or endpoint: monthly stock files, e.g.
  https://static.data.gouv.fr/resources/base-sirene-des-entreprises-et-de-leurs-etablissements-siren-siret/20261103-091933/stock-stockunitelegale-csv.zip
  (984,970,049 bytes; also Parquet; establishments file 2.9 GB) - the record says to use the dataset's stable
  URLs for automation; keyless search API `https://recherche-entreprises.api.gouv.fr/search?q=<text>&per_page=1`.
- Holds: SIREN and SIRET numbers, name, legal form (`nature_juridique`), administrative status
  (`etat_administratif`), creation and closing dates, activity code (NAF; the NAF 2025 code is already given),
  head-office address with coordinates, employee bracket, company size class, directors (in the API). **No
  website, e-mail or telephone field** (none in the API record's keys).
- Access: bulk files and API.
- Registration or key: none for the files or the search API (Insee's own Sirene API needs a free key; not checked).
- Cost: free.
- Licence or terms (exact wording, with URL): licence `lov2` (Licence Ouverte 2.0) on the dataset record.
- For a personal job search: use allowed (open licence); automated reading allowed (bulk files and a public
  API); private copy allowed.
- How to apply: not applicable.
- Volume: every registered unit (the file sizes above). Update cycle: monthly stock (1 November 2026 file),
  the API daily ("date_mise_a_jour": 2026-11-28).
- Seen on 2026-11-28: dataset record -> 200, application/json, 63,141 bytes (tags include `hvd`,
  `entreprises-et-propriete-dentreprises`); the search request with `q=doctolib` -> 200, application/json,
  10,572 bytes, 1 of 8 results.
- Caveats: published as an EU high-value dataset (the `hvd` tag and the category tag on the record). Persons who
  opposed diffusion are partly masked (`statut_diffusion`). From 1 January 2027 activity codes move to NAF 2025.

### Applicant-tracking vendors seen in the country

| Vendor | Local or international | Public feed for an employer's board (format, key?) | Documentation URL | Basis for "used here" |
|---|---|---|---|---|
| Cegid Talentsoft | French (Cegid) | None without credentials found: the "Job Board API allows job boards vendors to integrate with Talentsoft" (partners); a front-office API under OAuth scopes | https://developers.cegid.com/docreference/BusinessUnits/Recruiting-developer-portal/jobboard/_index.html | Choisir le service public's legal notice names Talentsoft as the recruitment platform (seen today) |
| Flatchr | French | JSON API only with the employer's key ("Authorization: Bearer API_KEY", generated in the employer's workspace); career pages at `careers.flatchr.io/company/{SLUG}` meant for iframes; no keyless feed documented | https://developers.flatchr.io/en/docs/getting_started/ and /en/site-carriere/ | French vendor; named in French comparisons (Planète Grandes Écoles, third party) |
| Taleez | French | Not found (no public documentation located) | - | Third-party comparison only |
| Welcome Kit (Welcome to the Jungle) | French | Token-gated per third parties (API Evangelist, merge.dev); vendor docs not read | - | Third party |
| JobAffinity, Beetween, Softy, DigitalRecruiters | French | Not checked | - | Named in third-party lists; "used by more than 10,000 recruiters" is JobAffinity's own claim via G2 |
| Teamtailor, Greenhouse, Lever, SmartRecruiters, Workable, Recruitee, Personio, Workday | International | See this study's `00-EU-wide.md`, topic 5 (several have keyless public feeds) | there | Not established for France from any source read today |

No market-share figure for France was found; a search returned editorial comparisons only.

### Links to employers' own pages
- None found in an open, keyless source. The Choisir le service public file and the Île-de-France dataset carry
  no URL field. France Travail's API is said to mark each offer's origin and partner; its field list could not be
  read today, and the API is closed to new users.
- Indirect: the French Tech directory below gives company websites, from which a careers page has to be found.

### Employer directories
- French Tech programmes directory by Numeum - https://frenchtech120.numeum.fr/annuaire/ : members of Next 40,
  French Tech 120, French Tech 2030 and related programmes by year, each with website ("Voir le site"),
  LinkedIn page, city, headcount, founding year. GET -> 200, 140,572 bytes, 30 companies on the first page.
  Terms (`/mentions-legales/`) not read.
- Annuaire des Entreprises - https://annuaire-entreprises.data.gouv.fr (DINUM): the State's company search built
  on Sirene and other open registers (from a search summary; not requested); no website field confirmed.
- Les Pépites Tech (lespepitestech.com), a private startup directory by French Tech hub: seen in search results
  only; terms not read.

## Not free or not allowed

- France Travail API Offres d'emploi: free, but no new access is granted at present; private persons are listed
  as not eligible.
- Indeed, LinkedIn, Welcome to the Jungle, HelloWork (and its JobiJoba aggregator, same terms): automated
  reading forbidden by the terms whatever the purpose.
- APEC (DataDome, 403) and Cadremploi (Cloudflare block, 403): refuse a plain client.
- JobTeaser (student and graduate board): "l'utilisation de robots ou de tout autre procédé d'extraction
  automatique est interdit" (its member terms, from a search summary; not read directly).
- Dares' JOCAS database of scraped online adverts: a research database; no open access found.
- Scrapers of France Travail, HelloWork and Welcome to the Jungle are sold on apify.com (search results only).

## Gaps

- **francetravail.io** serves a script-only page to this client: the API's documentation, field list, the text of
  the "licence de réutilisation des offres", and the portal's own notice of the suspension were not read. The
  suspension is taken from France Travail's record and replies on data.gouv.fr (October 2026); whether it has
  ended since is not known. Statements that the API carried an origin URL or a contact block per offer are from
  memory and were not confirmed.
- France Travail offer pages: fields, apply paths and the number of live offers were not read.
- emploi-territorial.fr's API page, terms and FAQ: not read (third request lost to a redirect).
- APEC and Cadremploi: nothing read (403). Meteojob's terms, JobTeaser, Jooble, Talent.com: not read.
- HelloWork: the terms come from maformation.fr; hellowork.com's own page was not requested because its
  robots.txt disallows it.
- Choisir le service public: the dataset's two documentation PDFs, its data.europa.eu entry, and how the offer
  list is loaded were not read.
- La bonne alternance: API terms and fields not read; no request was made to the API host.
- Licences of the Île-de-France, Tours and BPCE datasets: not read.
- INPI's Registre national des entreprises and Insee's own Sirene API (key conditions): not examined.
- Applicant-tracking vendors: no reliable source for which systems French employers use most; Taleez, Welcome
  Kit, JobAffinity, Beetween documentation not read.
- Indeed's and LinkedIn's robots.txt were not requested (one request each, spent on the terms).
