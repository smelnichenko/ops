# Ireland (IE) - explicitly prohibited sources

Status: checked
Date: 2026-11-28

| Hosts | Source | What is forbidden | Clause (quoted) | Clause read at | Kind |
|---|---|---|---|---|---|
| rezoomo.com, www.rezoomo.com | Rezoomo (recruiting platform that hosts Irish employers' job pages) | systematic or automated scraping, data mining, extraction or harvesting, by means of or in relation to the services | (section "Data mining") "You must not conduct any systematic or automated data scraping, data mining, data extraction or data harvesting, or other systematic or automated data collection activity, by means of or in relation to the Services." | https://www.rezoomo.com/terms-of-use/ | terms |
| irishjobs.ie, www.irishjobs.ie | IrishJobs.ie (The Stepstone Group) | for every agent: crawling the list `/jobs/permanent`, paged list addresses with a `&page=` parameter, and the apply addresses (`/*/apply`); other lists (`/jobs/contract`, `/jobs/temporary`, `/jobs/part-time`) and paged keyword searches (`/*?q*&page=`) are allowed by name | "User-agent: *", "Disallow: /jobs/permanent", "Disallow: /*&page=", "Disallow: /*/apply?", "Disallow: /*/apply$" (with "Allow: /*?q*&page=") | https://www.irishjobs.ie/robots.txt | robots.txt |
| jobs.ie, www.jobs.ie | Jobs.ie (The Stepstone Group) | for every agent: crawling the list `/jobs/permanent`, paged list addresses with a `&page=` parameter, and the apply addresses (`/*/apply`); other lists and paged keyword searches are allowed by name | "User-agent: *", "Disallow: /jobs/permanent", "Disallow: /*&page=", "Disallow: /*/apply?", "Disallow: /*/apply$" (with "Allow: /*?q*&page=") | https://www.jobs.ie/robots.txt | robots.txt |

Notes for the reader of this file (not rows):
- The two Stepstone rows are narrow: they rest on robots.txt alone and close one list, paging on filtered lists
  and the apply addresses. The sites' terms (read on 2026-11-28 at https://www.irishjobs.ie/recruiters/terms/ and
  https://www.jobs.ie/recruiters/recruitment-news/terms/) have no clause on robots or scraping and allow
  download "for personal non-commercial use". Jobs.ie's robots.txt was compared with IrishJobs.ie's line by
  line: the rules are the same.
- Rules that name only particular crawlers, not rows: both files have separate groups for adidxbot, Twitterbot,
  Applebot, Bingbot, BingPreview, MSNBot and Slurp (with "Allow: /job/" and "Allow: /jobs/"); those groups were
  not transcribed in full by the check.
- Left out on purpose: publicjobs.ie (personal, non-commercial use; no clause on robots; its robots.txt closes
  system directories only); JobsIreland (nothing could be read: every address returns a script shell).
- Indeed and LinkedIn are the same in every country and go in the EU-wide file.
