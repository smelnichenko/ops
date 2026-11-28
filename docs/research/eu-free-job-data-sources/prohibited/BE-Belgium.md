# Belgium (BE) - explicitly prohibited sources

Status: checked
Date: 2026-11-28

None found.

Notes for the reader of this file (not rows):
- StepStone Belgium is left out: its terms (https://www.stepstone.be/about-us/terms-of-use/) forbid scraping only
  for other ends - "use scraping or similar techniques, to collect content to use it for another purpose, to
  publish it again or use it in a different way than what the Services are intended for" - and say the services
  "are intended only for the individual job search by natural persons". Its robots.txt closes every address
  with a query string and the result lists, not the site.
- VDAB is left out: its disclaimer is silent on programs; its robots.txt closes `/api/vindeenjob/`, `/vacatures/`
  and `/zoeken/` for every agent, not the vacancy pages. VDAB's vacancy API (subscription, "voor werkgevers") and
  Le Forem's partner APIs are unavailable to a person, not prohibited.
- Jobat, Références and ADG refused the client (403 or a challenge); no clause was read.
- Indeed and LinkedIn are the same in every country and go in the EU-wide file.
