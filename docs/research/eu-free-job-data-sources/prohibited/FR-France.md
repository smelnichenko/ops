# France (FR) - explicitly prohibited sources

Status: checked
Date: 2026-11-28

| Hosts | Source | What is forbidden | Clause (quoted) | Clause read at | Kind |
|---|---|---|---|---|---|
| hellowork.com, jobijoba.com, maformation.fr, blogdumoderateur.com, helloworkplace.fr, hellowork-group.com, mon-compte-formation.fr, holeest.com, hellocv.com, cvcatcher.io | HelloWork group (HelloWork, JobiJoba, MaFormation and the group's other sites) | automated systems or software that extract data from the site, for any purpose, without a written licence | "Art. 8.2 [...] l'utilisation de systèmes automatisés ou de logiciels pour extraire des données du Site, en particulier le Contenu et la CVthèque (« capture de données d'écran » / « screen scraping / web scraping» notamment), à quelques fins que ce soit, commerciales ou non, est strictement interdite, à moins que HELLOWORK n'ait conclu une convention de licence écrite" | https://www.maformation.fr/cgu.html | terms |
| welcometothejungle.com, www.welcometothejungle.com | Welcome to the Jungle | software, scripts or robots that scrape, copy or download the website, its content or services | "Develop, support, or use any software, device, script, robot, or any other means or process (including but not limited to spiders, browser plug-ins and add-ons, or any other technology) to web “scrape” or otherwise copy or download our Website, Content or Services" | https://www.welcometothejungle.com/en/pages/terms | terms |
| candidat.francetravail.fr | France Travail - offer search on francetravail.fr | for every agent: crawling search addresses that carry a keyword (`motsCles=`), saved searches (`/offres/recherchesenregistrees`), selections (`/offres/selection`) and offer redirections (`/offres/emploi:redirection`); offer pages and searches without a keyword are not closed | "User-agent: *", "Disallow: *motsCles=*", "Disallow: /offres/recherchesenregistrees", "Disallow: /offres/selection", "Disallow: /offres/emploi:redirection*" | https://candidat.francetravail.fr/robots.txt | robots.txt-partial |
| meteojob.com, www.meteojob.com | Meteojob (CleverConnect) | for every agent: crawling the list `/offres-emploi/les-offres-d-emploi-pres-de-chez-vous`, `/api/`, `/company/`, the apply page and every address with a query string other than the search `/jobs?`, which is allowed by name | "User-Agent: *", "Disallow: /offres-emploi/les-offres-d-emploi-pres-de-chez-vous", "Disallow: /postuler/postuler-a-des-offres-d-emploi", "Disallow: /api/", "Disallow: /*?", "Allow: /jobs?*", "Disallow: /company/" | https://www.meteojob.com/robots.txt | robots.txt-partial |

Notes for the reader of this file (not rows):
- The HelloWork hosts are the ten the terms name as "le Site" (Art. 1), "ainsi que tous leurs sous-domaines". The
  terms were read on maformation.fr; hellowork.com's own copy sits under `/fr-fr/page/cgu/`, which its robots.txt
  disallows, and was not requested. The same article lists former names (regionsjob.com, cadreo.com,
  parisjob.com and others); they are not in the row. hellowork.com's robots.txt, for every agent, also closes
  `/*?`, `/fr-fr/emploi/recherche.html` and `/fr-fr/offres/postuler`; further down it has `/fr-fr/api/` and
  `/fr-fr/rss/`.
- The France Travail and Meteojob rows are narrow: they rest on robots.txt alone. France Travail's terms have no
  clause on robots; Meteojob's terms were not read.
- Rules that name only particular crawlers, not rows: hellowork.com's robots.txt shuts out several hundred named
  agents ("Python-urllib" and "Wget" among them) with "Disallow: /"; emploi-territorial.fr shuts out "SemrushBot";
  Meteojob shuts out "grapeshot".
- Every-agent robots.txt rules that close something other than search, list or advert pages, not rows:
  choisirleservicepublic.gouv.fr closes the PDF copies of offers ("Disallow: /wp-content/uploads/pdf-offers/")
  and the admin area; emploi-territorial.fr closes "/exportoffres/" and PDF files under "/arretes/".
- Left out on purpose: France Travail's API (closed to new users: unavailable, not prohibited); APEC and
  Cadremploi (technical refusals, no clause read); JobTeaser (its terms were not read).
- Indeed and LinkedIn are the same in every country and go in the EU-wide file.
