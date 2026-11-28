# Austria (AT) - explicitly prohibited sources

Status: first pass - not yet independently checked
Date: 2026-11-28

| Hosts | Source | What is forbidden | Clause (quoted) | Clause read at | Kind |
|---|---|---|---|---|---|
| jobs.ams.at | AMS - "alle jobs" | automated mechanisms of any kind; only one's own manual search is allowed | "Sie dürfen "alle jobs" ausschließlich zur eigenen, manuellen Suche nach Stellenangeboten verwenden. Keinesfalls dürfen automatisierte Mechanismen verwendet werden, beispielsweise um Daten der gelisteten Stellenangebote für Ihre eigenen Zwecke zu verwenden." | https://www.ams.at/arbeitsuchende/arbeitslos-was-tun/jobsuche-online-und-mobil/ams-jobsuche-hilfe | terms |
| karriere.at, www.karriere.at | karriere.at | every form of automated evaluation ("automatisierte Auswertung") of the platform; its information only for the personal job search and private use | "Du darfst die Informationen auf unserer Website bloß für deine persönliche Jobsuche und den privaten Gebrauch verwenden. Sämtliche Formen der automatisierten Auswertung unserer Plattform sind verboten." | https://www.karriere.at/nutzungsbedingungen | terms |
| willhaben.at, www.willhaben.at | willhaben (jobs section) | copying, editing, distributing, publishing or otherwise using the displayed content without the rights holders' prior consent, copying by robot or crawler technology or other automatic mechanisms included; in robots.txt: spiders, search robots or other automatic methods to access the site, unless willhaben has given access | "Die auf willhaben angezeigten Inhalte dürfen ohne vorherige Zustimmung der Rechteinhaber weder kopiert, bearbeitet, verbreitet, veröffentlicht oder öffentlich zur Verfügung gestellt werden (Online-Veröffentlichung) noch in sonstiger Weise genutzt werden. Dies gilt auch für ein Kopieren durch "Robot/Crawler" Suchmaschinentechnologien oder durch sonstige automatische Mechanismen"; robots.txt (https://www.willhaben.at/robots.txt), opening comment: "# It is expressively forbidden to use spiders, search robots or other automatic methods to access willhaben.at. Only if willhaben.at has given such access is allowed." | https://www.willhaben.at/iad/nutzungsbedingungen | terms |

Notes for the reader of this file (not rows):
- AMS: the clause is in the help page of "alle jobs" on www.ams.at and covers that service, which runs on
  jobs.ams.at; the row lists that host only. Its robots.txt closes every path below the entry page to unnamed
  agents and admits one named agent, so the row rests on the terms.
- karriere.at: the terms and robots.txt disagree (robots.txt closes nothing but two named agents); the terms are
  the stricter text.
- willhaben: Kind is "terms"; the robots.txt sentence is a written ban in a comment, while its Disallow lines
  close some paths only.
- Indeed and LinkedIn are the same in every country and go in the EU-wide file.
- Left out on purpose: StepStone.at (4.3.4 forbids scraping "für einen anderen Zweck" than the individual job
  search, not every program; robots.txt closes result lists and query addresses); Jobbörse der Republik
  Österreich (terms not read; robots.txt closes three paths); the Firmenbuch interface (token by approved
  application: unavailable, not prohibited); WKO Firmen A-Z (its own terms were not found - the terms reached
  belong to another service of the chambers; robots.txt closes filter parameters and named robots only; not a
  job source).
