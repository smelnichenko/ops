# Luxembourg (LU) - explicitly prohibited sources

Status: checked
Date: 2026-11-28

| Hosts | Source | What is forbidden | Clause (quoted) | Clause read at | Kind |
|---|---|---|---|---|---|
| adem.public.lu | ADEM JobBoard (public employment service) | for every agent: crawling any address that carries a query string - which covers the JobBoard's list, offer and search addresses (`/ctie/jobboard?id=`, `/ctie/jobboard/offer?id=`, `/ctie/jobboard/search?id=`); pages without a query string are not closed | "User-agent: *", "Disallow: /*?*", "Allow: /*?b=*" | https://adem.public.lu/robots.txt | robots.txt-partial |

Notes for the reader of this file (not rows):
- The row rests on two things seen on 2026-11-28: the robots.txt rule quoted, and the JobBoard page's own
  configuration (https://adem.public.lu/fr/jobboard.html), which names its data addresses as
  `/ctie/jobboard?id=...`, `/ctie/jobboard/offer?id=...` and `/ctie/jobboard/search?id=...`. None of those
  addresses was requested. ADEM's legal notice does not forbid personal use: it allows consulting and
  downloading "à titre personnel, pour information et dans un cadre strictement privé".
- Rules that name only particular crawlers, not rows: the same file shuts out trendictionbot, six SemrushBot
  variants and SplitSignalBot with "Disallow: /".
- GovJobs (govjobs.public.lu) has the identical robots.txt and legal notice, but its list of posts was not read,
  so whether the rule covers its vacancy addresses is not known: left out.
- Left out on purpose: Moovijob (technical refusal, no clause read); jobs.lu and Jobfinder.lu (terms not read;
  Jobfinder's robots.txt closes `/backoffice/*` only); LBR's paid extracts (paid, not prohibited).
- Indeed and LinkedIn are the same in every country and go in the EU-wide file.
