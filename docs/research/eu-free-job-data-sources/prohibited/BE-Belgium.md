# Belgium (BE) - explicitly prohibited sources

Status: checked
Date: 2026-11-28

| Hosts | Source | What is forbidden | Clause (quoted) | Clause read at | Kind |
|---|---|---|---|---|---|
| stepstone.be, www.stepstone.be | StepStone Belgium | for every agent: crawling the result lists (`/5/resultlistpage`, `/5/offres-emploi-resultat.html`, `/5/resultaten-jobs-werk-zoeken.html`), the search pages (`/5/job-search-simple.html`, `/5/advanced-job-search.html`), the apply address (`/5/jobapply`) and the home address with a query string (`/?*`) | "User-agent: *", "Disallow: /?*", "Disallow: /5/resultlistpage", "Disallow: /5/offres-emploi-resultat.html", "Disallow: /5/resultaten-jobs-werk-zoeken.html", "Disallow: /5/job-search-simple.html", "Disallow: /5/advanced-job-search.html", "Disallow: /5/jobapply" | https://www.stepstone.be/robots.txt | robots.txt |

Notes for the reader of this file (not rows):
- The StepStone row rests on robots.txt alone. The file opens with "Any other use of robots or failure to obey
  the robots exclusion standards [...] is strictly prohibited." and further down also has "Disallow: /*?*",
  "/jobagent/", "/widget/" and "/public-api/v1/job-applications/"; the check did not record which agent group
  those later lines stand under, so they are not in the row. StepStone's terms
  (https://www.stepstone.be/about-us/terms-of-use/) forbid scraping only for other ends - "use scraping or
  similar techniques, to collect content to use it for another purpose, to publish it again or use it in a
  different way than what the Services are intended for" - and say the services "are intended only for the
  individual job search by natural persons": not a row on their own.
- VDAB is not a row: its robots.txt (https://www.vdab.be/robots.txt) has "Disallow: /api/vindeenjob/",
  "Disallow: /vacatures/", "Disallow: /vac/" and "Disallow: /zoeken/", but the check did not record the
  User-agent line they stand under (the research says all agents) and no request to the host was left. Its
  disclaimer is silent on programs. VDAB's vacancy API (subscription, "voor werkgevers") and Le Forem's partner
  APIs are unavailable to a person, not prohibited.
- Rules that name only particular crawlers, not rows: VDAB's robots.txt has a group for Baiduspider.
- Jobat, Références and ADG refused the client (403 or a challenge); no clause was read.
- Indeed and LinkedIn are the same in every country and go in the EU-wide file.
