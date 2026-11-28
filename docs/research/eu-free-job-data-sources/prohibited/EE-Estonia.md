# Estonia (EE) - explicitly prohibited sources

Status: checked
Date: 2026-11-28

| Hosts | Source | What is forbidden | Clause (quoted) | Clause read at | Kind |
|---|---|---|---|---|---|
| cvkeskus.ee, www.cvkeskus.ee, cvmarket.lv, www.cvmarket.lv, cvmarket.lt, www.cvmarket.lt | CV Keskus (CVKeskus.ee, CVMarket.lv, CVMarket.lt) | automated queries: use of the site with software or tools that query it without human intervention (binds every user; 10 000 EUR per query) | 2.10 "Kasutajal on keelatud kasutada Veebikeskkonda tarkvara või vahendite abil, mis võimaldavad teha ilma inimese sekkumiseta automaatseid päringuid."; the sites covered, 1.1: "reguleerivad veebikeskkonna www.cvkeskus.ee, www.cvmarket.lv ja www.cvmarket.lt (Veebikeskkond) kasutamist." | https://www.cvkeskus.ee/kasutustingimused | terms |
| cv.ee, www.cv.ee | cv.ee (CV-Online, Alma Career Estonia) | extracts and copies of the database, and its use for any other purpose than applying - terms for the unregistered or unauthenticated job seeker (automated reading is not named there); copying by programs or scripts - employers' terms only | 1.2 "Te ei tohi teha andmebaasist väljavõtteid ega koopiaid ega kasutada seda ühelgi muul eesmärgil."; employers' terms, 3.6: "Klient ei tohi Andmebaasi ja/või Veebisaiti täielikult või osaliselt kopeerida või kahjustada ega selle tööd häirida, sealhulgas mistahes arvutiprogrammide (rakenduste, skriptide, käsurealiidese kaudu tehtavate päringute vms) abil." | https://hr.cv.ee/tingimused | terms |

Notes for the reader of this file (not rows):
- The CV Keskus row covers the Latvian and Lithuanian sister sites, which clause 1.1 names; they have no row in
  the Latvia and Lithuania files.
- cv.ee is a ban on extracts and copies, not on robots by name: no clause of the job-seeker terms names programs,
  scripts or automated queries, and 3.6 binds employer clients only. Its robots.txt (Internet Archive copy of
  2026-03-24) allows every path to unnamed agents and closes the site to named AI crawlers only.
- Left out on purpose: Töötukassa (terms unread - a script shell; robots.txt, archive copy, asks a crawl delay
  and closes list addresses with a query only); fin.ee "Avalikud konkursid" (no terms; robots.txt closes
  administration paths only); cvpro.ee and MeetFrank (terms not found); Glassdoor and Facebook ("terms forbid"
  is known from the production file only, no clause read); Töötukassa's vacancy statistics (CC BY-NC: a limit
  on commercial reuse only).
