# Finland (FI) - explicitly prohibited sources

Status: checked
Date: 2026-11-28

| Hosts | Source | What is forbidden | Clause (quoted) | Clause read at | Kind |
|---|---|---|---|---|---|
| duunitori.fi | Duunitori | storing, archiving, scraping or otherwise systematically copying the service's content or a substantial part of it, except as far as technically necessary for authorised use (binds every user, job seekers included) | "Käyttäjä ei saa tallentaa, arkistoida, skrapata tai muutoin järjestelmällisesti kopioida Palvelun sisältöä tai olennaista osaa siitä, paitsi siltä osin kuin se on teknisesti välttämätöntä Palvelun valtuutettua käyttöä varten." | https://duunitori.fi/compliance/kayttoehdot | terms |
| jobly.fi, www.jobly.fi | Jobly.fi (Alma Media's marketplace terms) | manual or automated software, machines, algorithms, search robots or other technical aids (robot, spider, scraper, offline reader) for retrieving information or making copies from the service, without the provider's prior express written consent | "Käyttäjällä ei ole oikeutta ilman Palveluntarjoajan etukäteen antamaa nimenomaista kirjallista suostumusta käyttää manuaalisia tai automatisoituja ohjelmistoja, koneita, algoritmejä, hakurobotteja tai muunlaisia teknisiä apuvälineitä (mm. ”robot-”, ”spider”, ”scraper-” ja ”offline reader-” ohjelmistot) tiedonhakuun tai kappaleiden valmistamiseksi Palvelusta" | https://www.almamedia.fi/markkinapaikkaehdot/#jobly | terms |

Notes for the reader of this file (not rows):
- Duunitori's terms were read through a fetch tool that relays text in fragments; the check confirmed the
  sentence as relayed. Its robots.txt says "User-agent: *", "Disallow: /" but lets some twenty named agents in,
  so it is not a ban for every agent and the row rests on the terms.
- Duunitori's terms are group terms: they name JobbSafari AB (Sweden) and Jobbland AS (Norway) as the contracting
  party by the user's country, but no host. jobbsafari.se is not in the row: whether it publishes these terms
  was not checked (the Sweden check rates it unclear).
- Jobly's terms allow one copy for personal use; the ban is on robots and scrapers. The marketplace terms were
  read in their Jobly.fi section; other sites they may cover are not named in the files.
- Left out on purpose: Job Market Finland's retrieval interface (credentials by application; no forwarding and
  no keeping of removed postings: unavailable, and limits on passing on) and its website (no clause; robots.txt,
  archive copy, closes `/api/` only); Valtiolle.fi and Kuntarekry (no terms of use; robots.txt allows all);
  Oikotie Työpaikat (the host only redirects).
