# 096 — masi: company enrichment — every hiring company's website, register entry, careers page and ATS

## Decision

masi finds, for each company that is **hiring now**, the website it certainly has, its register entry (which
ties a board's "LHV" to the register's AS LHV Pank), its careers page and the ATS it posts through. First
**without fetching anything** — the register already publishes most companies' website and e-mail, and a
company's own contacts already write from its domain — then, for what is left, by reading **the company's own
public pages** with a **second, separate fetcher** that may GET any public host, used by enrichment and nothing
else; the collectors keep the strict allow-list (masi #17).

- **Deterministic, no LLM.** Nothing a page says is sent to a model or anywhere else. The `ENRICH` share stays
  unused until coverage is measured and shows a model would add something a rule cannot.
- **Evidence, never a name alone, and never a merge.** A domain is taken when two independent things tie it to
  the company (below); a registry code is adopted only by PR3d's own safe path (a code masi does not hold, never
  rejected by the operator, under the ingest lock). Enrichment never merges two companies: a code another company
  already holds is offered to the operator, who has the existing register-match action.
- **Fill empty fields only**, with conditional updates: register, collector, partner and operator values are
  never overwritten, and a long visit never saves over what changed meanwhile.

Operator, 2026-09-25, choosing between Claude's web search, register data only, and an open fetcher:
*"Open allow-list for enrichment."* And, on the first draft's count of companies "without a website":
*"companies don't lack websites, you just did not find them."* On posting-analysis batching the operator asked
what re-analysis is for; there is almost none (a posting is analysed once; again only when a closed job is
reposted with new text), and batching would save about 0.60 USD a week in test at the price of hours of delay —
not planned.

## Why

- Test, 2026-09-25: 143 companies hiring now, **115 with no website recorded** — they all have one; masi never
  looked. **99 of the 115 are board stubs with no registry code** (LHV, Tervisekassa, Starship, Bolt, Bigbank,
  Cleveron…). The company rows keep the register's WWW only for the EMTAK 62/63 companies the register import
  discovers; the country-wide index (`register_company`, PR3d) keeps WWW for every company but is looked up by
  code or name only, and a board name ("LHV") matches no register name strongly. The import drops the register's
  EMAIL entirely (`AriregisterCollector`, "mostly personal") — yet its **domain**, when it is not free mail, is
  the company's own. The index is still empty in test: the register read last ran 2026-09-22, before PR3d; it
  runs weekly (Sunday 20:00 UTC) and on "Run now".
- 64 of the 99 stubs have a contact whose e-mail domain is visibly the company's (bigbank.ee, cleveron.com,
  elenger.com, esto.eu, ergo.ee): matched against the register's WWW/e-mail domains, most of them are placed
  without a single fetch. 5 have a URL in a posting; the rest (Bolt, Bondora, Coolbet, Delfi, Admirals) have no
  hint in masi at all and need the open fetcher.
- A careers page on the company's own site becomes an `ats:<slug>` source row through the existing
  `CompanyService.attachAts` (created disabled): the company's own feed becomes a collector. Plan 095's
  agency-recruiter signal (a contact's domain against the employer's) needs the employer's domain first.

## Architecture

### Domains (shared)

- `dedupe/Domains`: the **registrable domain** of a host by the public-suffix list (httpclient5's
  `PublicSuffixMatcherLoader.getDefault()`; Estonia has public second levels — `pri.ee`, `com.ee`, `med.ee`,
  `fie.ee`), its **label** (the part left of the suffix), and `FreeMail` — the inbox's list moved here, one call
  site each for the inbox, the register import and enrichment.
- `domain_norm` is an identity key (`CompanyService.find` routes a listing without a code by it, the inbox files
  mail by it): enrichment never writes a domain another company already holds — that is `UNCONFIRMED` with the
  holder named, for the operator.

### Step 1 — the register's own domains (no fetch)

Changeset 042 adds `register_company.website_domain` and `email_domain` (registrable domains, e-mail only when
not free mail; indexed); the register import fills both for every indexed company (the EMAIL value itself is
still never stored). A stub is placed when:

- a domain tied to the stub — **a contact of this company writes from it**, or the board gave it as the company's
  website (`domain_norm`) — is the `website_domain` or `email_domain` of register rows (a domain more than 25 rows
  give names none: a host's, a franchise's), and **exactly one** of all those rows fits the stub (a holding that
  lists its subsidiary's site does not stop the subsidiary; two fitting rows — a bank and its group — place
  nothing):
- the fit: `RegisterMatcher`'s strong rule (normalised name or `nameCore` equal, legal
  form consistent), or the register name starts with the stub's name as whole words when the prefix query is not
  truncated (the domain is the second signal, so the weaker name rule is enough here, and only here).

Placement goes through `RegisterMatcher`'s path: code not held by any company, not in the operator's rejected
codes, `adoptRegistryCode` under `IngestLock.tryLocked`, a `RegisterPlacement` written so the operator can undo
it. A held code → the row is recorded as `CODE_HELD` and offered to the operator (`POST /companies/{id}/
register-match`). The register's WWW then fills `website` (when empty and not held by another company).

This step runs after every complete register read and in the enrichment tick; it is what places most of the 64.

### Step 2 — the company's own site (open fetcher)

For a hiring company still without a website or code after step 1. **Candidates**, in order, deduplicated by
registrable domain, at most 4:
1. `company.website`; 2. the index's WWW for the company's code; 3. contact domains (not free mail, not a board,
ATS or known agency, most frequent first); 4. hosts in the company's postings' text and apply URLs that
`AtsDetector` does not recognise and that are no board; 5. **guesses**: the name with legal form and diacritics
stripped, as one label and as its first word — the first word only when it is not on a stop-list of generic
words (eesti, estonia, baltic, nordic, tallinna, tartu, digital, tech, group, solutions, …) — under `.ee`,
`.com`, `.eu`.

**Proof** — a site is taken only on two independent signals:
- `PROVED`: one of its pages prints a registry code near a registry keyword (*registrikood*, *reg. kood*,
  *reg nr*, *registry code*, *company code*; whole 8-digit tokens) **and** the domain is tied to the company —
  its label is the company's name, or it is the index's WWW/e-mail domain for that code, or a contact of the
  company writes from it. For a stub, the code's register row must fit the name as in step 1 — exact rule for a
  guessed domain, never the prefix rule — and exactly one code on the site may fit; adoption as in step 1.
- `MATCHED` (no code on the site, or a foreign company): a contact of the company writes from the domain **and**
  its label equals the company's normalised name (or a non-stop-list first word) **and** its suffix is `.ee`,
  `.com`, `.eu` or the company's own country's. `website` filled, no code adopted.
- `FOREIGN`: a site proved by `MATCHED` whose pages carry no Estonian code (Starship, Riverty, Entain, EY): no
  adoption ever; the register's prefix candidates (Starship Technologies OÜ) are listed for the operator.
- A register aggregator (inforegister.ee, teatmik.ee, e-krediidiinfo.ee, ariregister.rik.ee, rik.ee,
  eestiinfo.ee, …, a denylist in code) is never a candidate: it prints every company's name and code.
- After redirects the **final** registrable domain is the one judged, and it must pass the same rules.
- Anything else: `UNCONFIRMED`, kept with what was looked at, offered on the company page with **Accept**.

**What is taken from a site taken:** the careers page — the first home-page link whose text or path matches the
careers words (`karjäär`, `karjaar`, `tööpakkumised`, `vabad ametikohad`, `töökohad`, `liitu`, `careers`,
`jobs`, `join us`, `вакансии`, `карьера`), same registrable domain or a recognised ATS host; and the ATS — links
of the **careers page only** through `AtsDetector`, attached (`attachAts`) only when they name a **single**
vendor and slug (an agency's page links many clients' boards; `attachAts` names the new row after this company).

### The open fetcher (`enrich/OpenWebFetcher`)

Its own class, not an `HttpFetcher` bean, on Apache HttpClient 5 (managed by the Boot 4 BOM, 5.6.x):
- `PinnedResolver` implements `DnsResolver`: resolves once, refuses the whole answer if any address is
  internal (`UrlValidator.validateResolved`, the one rule), and returns exactly those addresses — the connection
  uses them. The client is built with the default route planner, **no `useSystemProperties()`** (a proxy would
  make the resolver resolve the proxy), `disableRedirectHandling()`, `disableCookieManagement()`,
  `disableContentCompression()` (no `Accept-Encoding: gzip`: the cap counts the bytes read, and no gzip bomb).
- **https only**: an `http://` candidate or redirect is rewritten to `https://`; port 443 only. On port 80 the
  Istio sidecar is an HTTP proxy that routes by Host and may add trace and peer-metadata headers to an outside
  request; on 443 it passes TCP through. A test asserts the exact outgoing header set against the local server.
- IP-literal hosts (dotted, decimal, hex, IPv6) are refused; redirects by hand, at most 3, every hop through the
  resolver, to 443 only.
- `text/html` only; 1 MB cap applied while reading; connect 5 s, per-read 10 s, and a **total deadline** of 15 s
  per request (a slow-drip server cannot hold a tick).
- Parsed with jsoup (charset from the headers or `<meta>`, `<base href>` honoured).
- `robots.txt` per host, fetched once per visit (64 KB cap; `Disallow` for `masi` or `*`; 404 = allowed,
  5xx/timeout = not allowed), including for a host reached by redirect.
- **One hard cap of 10 requests per company per visit**, every hop and every robots fetch counted; 2 s between
  requests to a host, the wait interruptible. A guess that does not resolve costs no request.
- Honest UA (the collectors' `masi/1.0 (+https://pmon.dev; job registry)`), GET only, no query of masi's making.
- `ArchitectureTest`: only `..enrich..` uses `OpenWebFetcher`; only `..enrich..` (and the shared `Domains`)
  depend on `org.apache.hc..`; `..collector..` never depends on `..enrich..`.
- The masi NetworkPolicy already refuses private, link-local and CGNAT ranges on egress; loopback is the
  resolver's to refuse.

### The collectors' rebinding gap

`UrlValidator.validate` resolves a name through a 5-minute cache and the JDK client resolves it again to
connect; the allow-list makes it unexploitable only as long as every listed host's DNS is trustworthy. Fixed,
not documented: `HttpFetcher` moves onto the same `PinnedResolver` (its own PR, with the rebinding test).

### Scheduling and recording

`EnrichmentScheduler` (fixed delay `masi.enrich.tick`, 10 min; `masi.enrich.per-tick` 5; off unless
`masi.enrich.enabled`, on in test) takes hiring, not-blacklisted companies not visited, or visited more than
30 days ago, or `FETCH_FAILED` more than a day ago (at most 5 attempts), or visited before the latest complete
register read (`register_index_read`) while still without a code — most open jobs first. The house lane pattern
of `AnalysisScheduler`: one tick at a time on a virtual thread, drained on shutdown; **only a finished visit is
stamped** (`last_enriched_at`) — a visit cut by shutdown stamps nothing. Fetching happens outside any
transaction; the result is applied with conditional updates (`… where website is null`) so a blacklist, a note
or a collector fill made during the visit survives.

`company_enrichment` (changeset 043): `company_id`, `run_at`, `outcome` (`PLACED_BY_REGISTER`, `PROVED`,
`MATCHED`, `FOREIGN`, `CODE_HELD`, `INDEX_NOT_READY`, `UNCONFIRMED`, `NO_CANDIDATE`, `ROBOTS_DENIED`,
`FETCH_FAILED`), `candidate_url`, `evidence`, `adopted_code`, `careers_url`, `ats_vendor`, `requests`, `error`.
`CompanyService.merge()` repoints it like the other company tables; rows older than 180 days are deleted by the
enrichment tick itself. Metrics `masi_enrich_companies_total{outcome}`, `masi_enrich_requests_total{result}`.

### Operator actions

`CompanyPatch` gains `website` (the "Accept", with the fetcher PR that produces candidates to accept): `validateSyntax`, `domain_norm` set, refused (409, named) when
another company holds the domain. The company page shows the latest enrichment row with its evidence, the
unconfirmed candidate with Accept, a held code with the register-match action, and a foreign company's prefix
candidates.

## PRs

1. **masi — the register's domains**: `Domains` + `FreeMail`, changeset 042 (`website_domain`,
   `email_domain`), the import fills them; merged, then the register read is run once in test ("Run now") so the
   index fills now rather than on Sunday.
2. **masi — placement by domain (step 1)**, candidates found this way offered as `DOMAIN`; measured in test after
   a register read: how many of the 99. The site labels `DOMAIN` candidates (site PR with item 5).
3. **masi — the collectors on the pinned resolver** (the rebinding gap).
4. **masi — the open fetcher and step 2**, in three: **4a** the fetcher (#60, merged); **4b-1** the
   `EnrichmentService` — candidates, proof (`PROVED`/`MATCHED`/`FOREIGN`/`UNCONFIRMED`/…), placement through
   `RegisterMatcher`'s guards, careers page, single-vendor ATS through `attachAts`, conditional fills —
   `company_enrichment` (the next free changeset after the figures work's), `CompanyService.merge()` repointing it,
   driven only by tests; **4b-2** the `EnrichmentScheduler` (off by default, hiring companies, the revisit rules,
   stamp only a finished visit, 180-day retention), metrics, `CompanyPatch.website` (Accept) and the company DTO's
   latest enrichment row; **infra** enables it in test.
5. **site** — the company card: evidence, Accept, held code, foreign candidates.
6. **infra** — `masi.enrich.enabled` in test; after a day, coverage by outcome recorded here.

## Verification (each revert check must turn a named test red)

| Mechanism | Test | Revert |
|---|---|---|
| registrable domain | `a.b.pri.ee` → `b.pri.ee`; `www.lhv.ee` → `lhv.ee` | strip `www.` only |
| e-mail domain, free mail | register EMAIL `x@gmail.com` → no `email_domain`; `info@lhv.ee` → `lhv.ee`; the address itself is not stored | free-mail check removed |
| placed by domain | stub "LHV", contact at lhv.ee, index row AS LHV Pank with `lhv.ee` → code adopted, placement written | adoption skipped |
| exactly one row | two index rows share the domain → nothing adopted | "exactly one" dropped |
| held code | the fitting code is held by another company → `CODE_HELD`, no merge, both companies still there | held check removed |
| rejected code | the operator rejected that code for the stub → not adopted again | rejected check removed |
| name must fit | contact domain's row is an agency → nothing adopted | name check removed |
| domain collision | a domain another company holds → `UNCONFIRMED`, website empty | collision check removed |
| resolver refuses internal | an answer with 127.0.0.1 / 10.x / 169.254.x / ::1 → no connection, 0 hits | check removed from the resolver |
| one resolution | a resolver answering public-then-internal is asked once, the connection uses the first answer | the client's own resolution restored |
| redirect re-checked | a redirect to an internal host, to port 8443, to `http://` | redirects followed by the client |
| IP literals | `https://2130706433/`, `https://0x7f000001/`, `https://[::1]/` refused | literal check removed |
| no proxy | `https.proxyHost` set in the test JVM → ignored | `useSystemProperties()` |
| no gzip | the request carries no `Accept-Encoding`; a gzip body is not inflated | compression enabled |
| header set | the outgoing headers are exactly Host, User-Agent, Accept (and Connection) | any extra header |
| no cookies | a `Set-Cookie` is not sent back | cookie management enabled |
| body cap | a 2 MB page is not read past 1 MB | cap removed |
| html only | an `application/pdf` is not read | type check removed |
| total deadline | a server dripping one byte a second is cut at 15 s | deadline removed |
| robots | `Disallow: /` → only robots.txt fetched | robots ignored |
| robots fail closed | robots.txt 503 → nothing fetched | 5xx read as allowed |
| request cap | a site of 20 contact-like links and redirects → at most 10 requests | cap removed |
| proof needs two signals | the code on the page of an aggregator host / of a guessed domain whose label is another name → not `PROVED` | domain tie removed |
| guessed domain, prefix name | `nordic.ee` printing "Nordic Foo OÜ" for stub "Nordic" → nothing adopted | exact rule for guesses dropped |
| two codes | a site printing two codes that both fit → nothing adopted | "exactly one" dropped |
| code near a keyword | `123456789` or a bare 8-digit phone number → no code | keyword proximity removed |
| matched | contact at bigbank.ee, stub Bigbank AS, no code → `MATCHED`; label `otherbank` → `UNCONFIRMED`; `bigbank.xyz` → `UNCONFIRMED` | label / contact / suffix check removed |
| foreign | a matched site with no Estonian code → `FOREIGN`, no adoption | adoption allowed |
| ATS single vendor | a careers page linking one Greenhouse board → attached; linking three boards → none | single-vendor rule removed |
| fill empty only | a register website is never replaced; an operator note written mid-visit survives | overwrite / whole-entity save |
| scope | no open job, blacklisted, visited 3 days ago → not visited; a stub visited before the latest register read → visited | a filter removed |
| shutdown | a visit interrupted mid-fetch stamps nothing | stamp before the visit |
| merge carries rows | a merged stub's enrichment rows move to the survivor | repoint removed |
| off by default | no request without `masi.enrich.enabled` | switch ignored |
| isolation | ArchitectureTest: a collector importing `OpenWebFetcher` / `org.apache.hc` fails | rule removed |
| Accept | PATCH website to a domain held elsewhere → 409 | collision check removed |

## Risks

- **A wrong website or a wrong placement** misroutes listings and mail (`domain_norm` is an identity key) or
  fuses two companies. Two independent signals for every domain, exactly one fitting register row or code,
  never a merge, never a code the operator rejected, never a domain another company holds, the aggregator
  denylist, and every automatic placement undoable through its `RegisterPlacement`.
- **An open fetcher is an SSRF surface.** Pinned resolution, https only, 443 only, no proxy, no cookies, no
  compression, IP literals refused, small caps and a total deadline, the NetworkPolicy behind it, and one package
  allowed to use it.
- **Politeness:** at most 10 requests per company per 30 days, robots honoured (fail closed), 2 s spacing,
  honest UA.
- **Nothing leaves masi** but GET requests with the UA over TLS; page content is read for links and codes and
  dropped — never stored, never sent to a model or a partner.

## Status

IN PROGRESS 2026-09-25 — first draft reviewed (3 critical, 11 warnings, 8 suggestions), all folded in above.
**PR1 (masi #56) merged and live in test 2026-09-25** (masi 8c30cd0, changeset 042): the index keeps
`website_domain`/`email_domain`; its review found malformed hosts (`lhv..ee` → `.ee`), two forms of Estonian-letter
domains, platform sites keyed to the platform, and the register's free-text fields read wrongly — all fixed; 25
revert checks. The columns fill on the next register read (Sunday 20:00 UTC, or "Run now" — the operator's click).
**PR2 (masi #57) merged and live in test 2026-09-25** (masi 7069f65): placement by the employer's domain — the board's
site, else a domain at least half its people write from — to exactly one registered company that is it by name (same
name core, or a registered name beginning with it as whole words, only while the brand is no company of its own and
the name is no common start), employer form, the board's form; never a held or rejected code; no domain another company
holds; platform pages give no website domain. Its review found brand→subsidiary fusion (alias pull), stray contacts,
and a domain written into a second company — all fixed; 31 revert checks. Measured once the register read fills the
index. The site's `DOMAIN` label is a follow-up.
**Operator, 2026-09-25: "never use eesti.ee for emails", "cleanup from eesti.ee" → masi #58** (merged): one rule,
`Normalizer.refusal`, refuses a no-reply mailbox or a resident's state inbox (`@eesti.ee`, read as the registrable
domain) on every path that stores, derives or mails an address — capture, identity, the operator's and the partner's
edits (400), the inbox (no contact), the digest (never mailed), the mail and inbox settings (no start); the startup
repair forgets any stored before. None was stored in test or production.
**Site #28** (merged, live): the register card says how each candidate was found (same name / starts with it / its
people write from its domain / the code you typed) — a typed code had also read "starts with it".
**PR3 (masi #59) merged and live in test 2026-09-25** (masi 3170eb4): the collectors' `HttpFetcher` on HttpClient 5
with `validation/PinnedResolver` — a name resolved once per connection, one internal address refuses the whole answer,
the port judged with the addresses, the connection uses exactly the judged addresses; `UrlValidator.validateShape`
without DNS. Its review found that closing an HttpClient 5 response reads the rest of its body (a page over the cap
would have been downloaded all the same) — responses not read to their end are aborted; the pool is 20 per host / 100,
no connection is reused, no JVM proxy. 24 revert checks. The client is HTTP/1.1 only (the JDK client could negotiate
h2): collector run statuses compared with the day before, 2 h after the deploy. `BrowserSession` still validates with
`UrlValidator.validate` (Chromium resolves again) — its egress policy is the control there; the fetcher PR4 builds on
`PinnedResolver`.
**PR4a (masi #60) merged 2026-09-25** (masi 3e5c0ad): `enrich/OpenWebFetcher` + `Visit` + `RobotsRules`, used by nothing
yet — HTTPS on 443 only (http read over https), no address as the host (a numeric last label included), IDN in ASCII,
GET only, no cookies/compression/proxy/reuse, a deadline per request that also covers a dripping body, responses not
read to their end aborted; a visit: 10 requests (robots and hops counted, an unresolvable name costs none), robots per
host and per hop (a linear wildcard walk — a regex let a hostile pattern pin the thread —, product-token groups,
percent-encoded, BOM; 4xx allows, 429/5xx/unreadable disallows), 2 s per host, HTML only, 1 MB. Its review (3
critical: ReDoS, unknown charset and malformed Location throwing) and audit (18 untested mechanisms) folded in —
partly by a resumed peer session (monitor-40), merged; 33 revert checks. Tests run against an HTTPS fixture server
with a test-only certificate; nothing leaves the test. Next: PR4b — the enrichment service (candidates, proof,
placement, careers page, ATS), `company_enrichment` (044 — 043 goes to the address feature), the scheduler,
`CompanyPatch.website`.
**PR4b-1 (masi #63) parked 2026-09-25 for rework** (the tree went to the figures work meanwhile). Its review found
the proof too loose, and the rules change to:
- a **contact domain is a tie only when it is a placing domain** (the board's own site, else one at least half the
  company's people write from — `RegisterMatcher.placingDomains`, shared); a **posting host is no tie**; a **guessed
  domain is no tie at all** — it can be `PROVED` only when the register itself gives that domain (WWW or e-mail) for
  the code on the site, otherwise at most `UNCONFIRMED` (the operator's Accept): a squatter or an unrelated
  same-named company on the name's domain must not win;
- a stub is placed only when the fitting code is the **only employer-form code the site prints** (a customer list,
  a group footer, a partner page print several), and by name `sameName` or `prefixMayPlace` — **never a brand on its
  subsidiary's code** (PR2's bug, back through the service);
- a company with a code is `PROVED` by a site printing its code only on the same terms (tied, the only employer code);
- the **final registrable domain after redirects** is the one judged, tied and written (firma.ee → firma.com);
- a site whose domain another company holds is not taken at all (no careers page, no ATS under the wrong company);
  `fillWebsite` is one statement (no other company on the domain);
- links: http(s) only (a `mailto:jobs@` is no careers page), careers words matched as words/path segments;
- `placeBySite` re-reads the company under the lock (placed or merged meanwhile is an outcome, not an exception);
  evidence and URLs cut to their columns; ISP mail (elion.ee, estpak.ee, starman.ee) is free mail; ATS and more
  aggregators (eestiinfo.ee, 1182.ee) are platforms; `INDEX_NOT_READY` does not end a visit.

**Measured in test 2026-09-25**, after the register read at 12:43 UTC (the first since PR3d): the index holds 369 127
companies, 20 626 with a website domain and 114 084 with an e-mail domain. The weekly pass then placed **64 employers
by name** (PR3d's rule, first run with a filled index) and **7 by domain** (PR2): Fontes PMP, Ida-Tallinna
Keskhaigla, Inbank, Kühne + Nagel, M-Partner HR, Omniva, Swedbank — each checked by hand, all right. Hiring companies
without a registry code: **47 of 144** (≈ 99 in the morning); without a website: 96 (the register's WWW is often empty,
or the domain is another company's). PR3 (#59) on live collectors, 2 h after its deploy: every source OK but one cv.ee
detail page answering 500 (the board's).
