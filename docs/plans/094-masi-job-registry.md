# 094 — masi: IT job & company registry for Estonia with reviewed CV tuning

## Decision

A new Spring Boot service `schnappy/masi` (`/api/masi`, CNPG database `masi`, Keycloak role
`JOBS`, UI pages in `site/`) that:

1. runs **one dedicated collector agent per source** on its own cron and feeds a deduplicated
   registry of Estonian IT positions, with a **headless browser** as a first-class collector kind;
2. maintains a **registry of Estonian IT companies** with its own discovery sources;
3. for each open position asks Claude for a **tuned CV and cover letter**, hard-checked against a
   versioned CV master so nothing can be fabricated, renders a PDF and parks the package in a
   review queue — **masi never sends anything**; the operator applies by hand and marks the job
   APPLIED or SKIPPED;
4. gives an **overview dashboard, weekly and monthly reports** reproducible from the database;
5. treats **cost monitoring as a feature**: ledger, budgets, metrics, alerts, dashboards.

Source discovery is a separate survey PR that precedes any scraper. LinkedIn, Glassdoor and
Facebook are ToS-forbidden and never polled; a "paste a URL" import covers them.

## Why

Operator, 2026-09-16: *"robot that creates and maintains a registry of IT job offerings in
Estonia, tunes my CV for each new position … essentially, we need a registry of IT companies as
well … overview and stats/reports, like weekly … headless browser is a must have, also plan cost
monitoring."* And on the CV itself: the one-CV-for-fifty-postings model is dead; a title says
nothing, results beat duties, the employer only sees what the CV shows, and a CV must answer
"why does my experience fit *this* job", not "where have I worked".

- No structured CV exists anywhere (only `cv.docx`, LibreOffice variants, a 2022 LinkedIn
  export). A machine-checkable master is the precondition for a fabrication guard, so masi
  introduces it — as an **evidence bank** richer than any single CV.
- The platform already has every piece except the domain: JWT filter, permission AOP, DB-driven
  cron scheduler, SSRF-safe fetcher, Anthropic SDK structured-output idiom, Testcontainers/CI
  scaffolding. Copying `monitor` verbatim for the plumbing keeps review on the new parts.
- Scrapers are the brittle part. One agent per source with its own health, budget and fixture
  keeps a dead board from being a platform incident.
- The admin service maps its `Permission` enum to Keycloak realm roles but only *looks up* roles
  (`KeycloakSyncService`), so a new `JOBS` permission is an admin PR plus a realm-role step, not
  a console click.

Seed inventory, verified 2026-09-16: cv.ee has an unauthenticated JSON search API; cvkeskus.ee
has per-category sitemaps + RSS and no anti-scraping clause; tootukassa.ee has a GraphQL
endpoint + sitemaps (Crawl-delay 10) and an open-data dataset (portal cert expired that day);
ATS JSON feeds verified for Wise (SmartRecruiters), Twilio and Veriff (Greenhouse), Pipedrive
(Lever); TeamDash is the common Estonian ATS with no public feed; MeetFrank returns 403 to plain
fetch. Company discovery: e-Business Register daily open-data dumps with EMTAK codes (CC BY 4.0),
ITL member list (128), Tehnopol portfolio, Startup Estonia/Dealroom (no export).

## Architecture

### Placement and reuse

| Item | Decision |
|---|---|
| Repo | `schnappy/masi`, package `io.schnappy.masi`, `sonar.projectKey schnappy-masi`, image `git.pmon.dev/schnappy/masi:$GIT_HASH` |
| Copied from `monitor` (package rename only) | `SecurityConfig`, `CacheConfig`, `KafkaConfig`, `SchedulerConfig`, `GatewayAuthFilter`, `security/*` (`GatewayUser`, `Permission`, `RequirePermission`, `PermissionInterceptor`, `UserProvisioner`), `UserProvisionerAdapter`, `UserEventConsumer`, `User` entity, `UrlValidator`/`CronValidator`/`RegexValidator`, `GlobalExceptionHandler`, `HealthController`, `Dockerfile`, `.woodpecker/*` (sed anchor `# masi`), `renovate.json`, `spotbugs-exclude.xml`, test scaffolding (`TestcontainersConfiguration`, `CiTestConfiguration`, `TestHttpServer`, `TestJwt`, `TestAuthHelper`), `ArchitectureTest` |
| `build.gradle` | monitor's minus the unused jOOQ block, the dead `helm*`/`deploy*` tasks, mail/svix/minio; plus `anthropic-java` (current), `jsoup`, `rome`, `openhtmltopdf-pdfbox`, `spring-boot-starter-thymeleaf`, `json-schema-validator`, `com.microsoft.playwright:playwright` |
| Scheduler | monitor's `MonitorScheduler` pattern: DB polled every 60 s, `ConcurrentHashMap<key, ScheduledFuture>`, cron-change detection, `CronTrigger` |
| LLM | monitor's structured-output idiom (`outputConfig(Pojo.class)` on the beta messages client) behind one `AnthropicGateway` adding retry/backoff, budgets, ledger, prompt caching |
| Permission | new realm role **`JOBS`**; `METRICS`/`PLAY` sit in the default Users group and would expose the CV and the Anthropic spend to every registrant |
| Artifacts | PDFs in Postgres `bytea`; `STORAGE_*` is not wired in the chart, volumes are small, CNPG backups cover it |
| CV master | in the DB via the UI, not a repo file: PII must not ride through CI/Kaniko/depcheck clones; versioned per row; survives redeploys |
| PDF | openhtmltopdf from Thymeleaf XHTML templates; one OFL font on the classpath (the JRE image has no fonts, `readOnlyRootFilesystem`); PDFBox scratch in the `/tmp` emptyDir |
| Browser | Chromium in its own `masi-browser` Deployment (browserless image); masi connects with Playwright over the network; the masi image never contains a browser |
| Models | `claude-opus-5` for tuning and cover letter (adaptive thinking default, effort HIGH); `claude-haiku-4-5` for extraction and classification; prompt caching on the rules block and the CV block |

Properties (`masi.*`, env in parentheses): `enabled` (MASI_ENABLED); `http.{connect-timeout,
read-timeout,user-agent,max-body-bytes}` with UA `masi/1.0 (+https://pmon.dev; job registry;
<contact>)`; `ai.{enabled,api-key,tuning-model,extract-model,daily-budget-usd,monthly-budget-usd,
max-retries}` (AI_ENABLED, ANTHROPIC_API_KEY, AI_MODEL, AI_EXTRACT_MODEL, AI_DAILY_BUDGET_USD,
AI_MONTHLY_BUDGET_USD); `ai.pricing.<model>.{input,output,cacheRead,cacheWrite}`;
`ai.purpose-share.<purpose>`; `tuning.auto`; `lifecycle.close-after-misses` (3);
`browser.{enabled,endpoint,nav-timeout,max-parallel,user-agent}` (MASI_BROWSER_ENDPOINT);
`reports.weekly-cron` (`0 0 6 * * MON`, Europe/Tallinn).

### Package layout `io.schnappy.masi`

```
config/ filter/ security/ event/ validation/(+CvSchemaValidator)   copied plumbing
entity/      User, Source, SourceRun, Company, CompanyAlias, Job, JobListing, CvVersion,
             ApplicationPackage, PackageArtifact, LlmCall, Report (+ enums)
repository/  one Spring Data repository per entity
collector/   Collector (SPI), CollectorKind, CollectContext, CollectResult, RawListing, RawCompany,
             CollectorRegistry, CollectorRunner, fetch/HttpFetcher, html/HtmlText,
             browser/{BrowserClient, BrowserCollector},
             support/{JsoupListCollector, RssCollector, SitemapCollector, JsonApiCollector,
                      LlmExtractCollector, AtsCollector},
             cvee/ cvkeskus/ tootukassa/ ats/ meetfrank/ bolt/ ariregister/ itl/ tehnopol/ manual/
             (one sub-package per source; package name == source.key)
dedupe/      Fingerprint, Normalizer, ListingMatcher, CompanyMatcher
registry/    RegistryService, CompanyService, RegistryQuery
ai/          AnthropicGateway (the only class importing com.anthropic.*), LlmLedgerService, Pricing
cv/          CvMasterService (versions, validation, completeness), CvModel
tuning/      TuningService, TuningPrompt, TunedCvOutput, ClaimsChecker, ClaimsReport, CvLint
render/      PdfRenderer, CvTemplateModel
reports/     StatsService, ReportService, ReportScheduler
scheduler/   SourceScheduler, TuningScheduler
controller/  Jobs, Packages, Companies, Sources, Cv, Dashboard, Reports
```

ArchUnit rules on top of monitor's: per-source packages depend only on `..collector..`,
`..dedupe..`, `..dto..`, `..validation..`; `..tuning..` and `..render..` never depend on
`..collector..`; every `@Component` under `..collector.(*)..` implements `Collector` and lives in
the sub-package equal to its `sourceKey()`; only `..ai..` imports `com.anthropic..`.

### Data model (Liquibase, `author="masi"`)

Jobs, listings and companies are never deleted: closed rows are the history the reports aggregate.

| Changeset | Tables and key columns |
|---|---|
| 001 users | `users` (uuid PK, email, created_at) as monitor |
| 002 sources | `source`: key (unique = collector package), name, kind (`DETERMINISTIC`/`LLM_EXTRACT`/`BROWSER`), scope (`JOBS`/`COMPANIES`/`BOTH`), base_url, cron, enabled, config_json, terms_note, health (`OK`/`DEGRADED`/`FAILING`/`DISABLED_AUTO`), consecutive_failures, last_run_at, last_success_at, last_error. `source_run`: source_id, started/finished_at, status (`OK`/`ERROR`/`TIMEOUT`/`SKIPPED_BUDGET`), fetched, parsed, new_jobs, updated_listings, closed_listings, new_companies, browser_pages, error, llm_cost_usd |
| 003 companies | `company`: name, name_norm (unique), registry_code (unique, nullable), website, domain_norm, careers_url, ats_vendor, ats_feed_url, emtak_code, size_band, hq_city, remote_policy, tech_tags, status (`ACTIVE`/`DORMANT`), origin (`DISCOVERED`/`FROM_LISTING`/`MANUAL`), first_seen_at, last_seen_at, last_enriched_at, user_rating, blacklisted, user_note. `company_alias`: company_id, alias_norm (unique) |
| 004 registry | `job`: fingerprint (unique), company_id, title, title_norm, location, remote, seniority, description_text, tech_tags, requirements_json (posting analysis), salary_min/max, status (`OPEN`/`CLOSED`), first_seen_at, last_seen_at, closed_at, match_score, user_note. `job_listing`: job_id, source_id, external_id, url (unique with source_id), title_raw, company_raw, description_raw, posted_at, expires_at, first_seen_at, last_seen_at, miss_count, closed_at, raw_hash |
| 005 seed sources | one insert per surveyed source, `enabled=false`; later sources get `0NN-seed-source-<key>` |
| 006 cv versions | `cv_version`: user_uuid, version, yaml, schema_version, note, active (partial unique), created_at |
| 007 packages | `application_package`: job_id, cv_version_id, **unique (job_id, cv_version_id)**, status (`NEW`→`PREPARING`→`PREPARED`→`REVIEWED`→`APPLIED`\|`SKIPPED`, `FAILED_GUARD`, `FAILED`), tuned_cv_json, cover_letter, claims_report_json, lint_json, model, cost_usd, error, user_notes, applied_at, response (`NONE`/`REPLIED`/`INTERVIEW`/`OFFER`/`REJECTED`). `package_artifact`: package_id, kind (`CV_PDF`/`LETTER_TXT`), content_type, bytes, sha256, size |
| 008 llm calls | `llm_call`: purpose (`EXTRACT`/`TUNE`/`LETTER`/`SCORE`/`ENRICH`), model, source_id, package_id, input/cache_read/cache_write/output tokens, cost_usd, stop_reason, latency_ms, error, created_at |
| 009 reports | `report`: kind (`WEEKLY`/`MONTHLY`), period_start, period_end (unique with kind), payload_json, generated_at |

### Source layer: one collector agent per source

```
interface Collector { String sourceKey(); CollectorKind kind(); Set<Scope> scopes();
                      CollectResult collect(CollectContext ctx); }
record RawListing(externalId, url, titleRaw, companyRaw, location, descriptionRaw, postedAt, expiresAt, extras)
record RawCompany(name, registryCode, website, careersUrl, atsVendor, atsFeedUrl, emtakCode, extras)
record CollectResult(listings, companies, pagesFetched, warnings, complete)
```

- **Registry.** `CollectorRegistry` maps beans by key and cross-checks `source` rows at startup:
  bean without a row → WARN; row without a bean → `FAILING`, not scheduled. Both are integration
  tests, so forgetting the class or the seed changeset fails CI.
- **Isolation.** `CollectorRunner.run(source)`: MDC `source=<key>`, a `source_run` row, a virtual
  thread with a per-source deadline (default 120 s), `catch Throwable`, ingest in its own
  transaction, then health: success resets failures; ≥3 → `DEGRADED`; ≥10 → `DISABLED_AUTO`
  (UI re-enable resets). Metrics `masi_collect_runs_total{source,status}`,
  `masi_collect_listings{source}`, `masi_collect_duration_seconds{source}`,
  `masi_collect_llm_cost_usd{source}`. A throwing collector never reaches the scheduler thread
  or another source's run.
- **Scheduling.** `SourceScheduler` is monitor's scheduler with `collectorRunner.run(source)` as
  the task body; "Run now" enqueues the same runner.

| Source shape | Kind | Base |
|---|---|---|
| JSON API, ATS feed, RSS/Atom, sitemap, list page with stable markup | `DETERMINISTIC` — always preferred: free, exact, offline-testable | `JsonApiCollector`, `AtsCollector`, `RssCollector`, `SitemapCollector`, `JsoupListCollector` |
| Bespoke or unstable career pages whose HTML still carries the data | `LLM_EXTRACT` — Haiku; Sonnet only when a fixture shows Haiku missing fields | `LlmExtractCollector`: jsoup visible text (60 k chars) → structured output → deterministic post-validation (every URL must occur in the fetched HTML or resolve under `base_url`) → per-run cost cap |
| JS-rendered lists, "load more", data only in XHR (MeetFrank, Bolt, Töötukassa GraphQL) | `BROWSER` | `BrowserCollector`: navigate in the browser pod, wait for a selector, scroll/click up to `maxPages`, capture rendered HTML **and** XHR responses matching `harvestUrlPattern`, hand off to the jsoup/JSON/LLM parsers |
| Login wall, WAF that blocks the browser too, ToS-forbidden | not collected; `manual/` = "add listing by URL" | — |

**Headless browser.** A `masi-browser` Deployment in the chart runs a browserless/Chromium image
with its own resources (512Mi–1Gi), NetworkPolicy (ingress only from masi on 3000, egress DNS +
internet 80/443) and mesh service account. masi uses Playwright for Java with `connectOverCDP`
(or `connect` against a Playwright server whose version equals the client's) and never downloads
a browser (`PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1`). Guards: every URL passes `UrlValidator` before
navigation and every request is re-validated (`page.onRequest` aborts non-allowed hosts);
downloads, geolocation and camera blocked; per-run navigation timeout and page cap; one context
per run, at most `browser.max-parallel` concurrent runs. The browser pod restarts on its own
liveness probe; masi degrades the *source*, not itself, when the endpoint is unreachable.

**Adding a source** (acceptance list for every collector PR): survey row → class
`collector.<key>.<Name>Collector` → fixture `src/test/resources/fixtures/<key>/…` captured from the
real site and scrubbed, served by `TestHttpServer`, test asserting exact `RawListing`/`RawCompany`
values plus a negative case (broken selector → `complete=false`, `DEGRADED`, sibling source
unaffected) → seed changeset → registry picks the bean up → enable in the UI → check `source_run`
and Grafana.

Source tiers from the seed inventory, to be confirmed by the survey:

| Tier | Source | Access |
|---|---|---|
| T1 | cv.ee | `GET /api/v1/vacancy-search-service/search?categories[]=INFORMATION_TECHNOLOGY` (id, title, salary, remoteWork, employerName, publish/expiration dates) |
| T1 | cvkeskus.ee | per-category sitemap (~600 URLs, lastmod) + RSS for freshness + detail HTML via jsoup |
| T1 | tootukassa.ee | sitemap `/web/joboffers/sitemap.xml` (Crawl-delay 10) + detail HTML; the browser harvests the GraphQL responses once to learn the schema, then a deterministic collector replays it; open data when the portal is reachable |
| T1 | ATS feeds | `AtsCollector` per company row: SmartRecruiters (Wise, `?country=ee`), Greenhouse (Twilio, Veriff), Lever (Pipedrive) |
| T2 browser | MeetFrank (WAF; the survey decides), Bolt careers (13 JS pages), Nortal, Microsoft/Ericsson SPAs, otsintood.ee as a cross-check oracle, TeamDash pages if jsoup fails |
| T2 | Teamtailor (Swedbank `jobs.json`), BambooHR (Ridango), TeamDash (Helmes, Cybernetica, LHV), devjobsscanner |
| never | LinkedIn, Glassdoor, Facebook (ToS), Indeed (no EE site), hh.ee (dead) |
| companies | e-Business Register general-data dump (daily, JSON/Parquet, EMTAK 62/63, active only, streamed weekly), ITL members (HTML), Tehnopol portfolio (HTML), employer names from the boards (stub + enrich), Dealroom manual only |

### Companies

`CompanyService.resolve(rawCompany)` dedupes by registry code, then `name_norm`, then
`domain_norm`, then aliases; a listing naming an unknown company creates a `FROM_LISTING` stub.
Enrichment (`ENRICH`, Haiku, budgeted) finds the careers URL and ATS vendor; a detected ATS gets
its own `source` row so the company's feed becomes its own collector agent. Company detail shows
open/closed listings history and hiring velocity. Blacklisted companies never get packages.

### Dedupe and lifecycle

- `Fingerprint.of(companyRaw, titleRaw)` = SHA-256 of `norm(company)|norm(title)`; `norm` folds
  diacritics, lowercases, strips legal suffixes (`oü`, `as`, `ltd`, `ou`, `llc`, `gmbh`, `inc`),
  gender tags, punctuation. Location excluded (boards disagree); seniority words kept.
- Ingest: upsert `job_listing` by `(source_id, url)`; find or create `job` by fingerprint;
  `last_seen_at = now`, `miss_count = 0`.
- Closing: after each **successful** run of source S, listings of S with `last_seen_at <
  run.started_at` get `miss_count++`; at `close-after-misses` → `closed_at`. Also close on detail
  404/410, a parsed "expired" marker, or `expires_at` passed. A job closes when all its listings
  are closed. Failed or timed-out runs never increment misses.

### CV principles

1. One CV per position, never one universal CV; the summary answers "why does my experience fit
   *this* job".
2. Results, not duties: each bullet says what was done, at what scale, with what outcome. A
   title says nothing; qualify it with the area owned, the problems solved, the stack, the autonomy.
3. Company context per role: domain, type, scale, team, area of responsibility.
4. The posting's vocabulary, but only where the master carries evidence.
5. Positioning first: target roles, value proposition, differentiators live in the master.

Consequences: the **master is an evidence bank** — per role `company{name, domain, type,
size_band, users_or_revenue}`, `team{size, role_in_team}`, `scope`, `autonomy`, `tech[]`,
`achievements[{statement, metric, problem, keywords[]}]`, plus a `positioning` block; it holds
far more achievements than any one CV shows and the tuner picks the 3–5 per role that answer
the posting. `CvMasterService.completeness()` shows per-role gaps in the editor and on the
dashboard until 100 %. `TuningPrompt.RULES` (the cached block) demands results-first bullets with
metrics kept verbatim, a company-context line per role, a 3–4 line fit summary naming the role
and company, the posting's terms where supported, irrelevant roles collapsed to one line, and
never a fact absent from the master. A deterministic **`CvLint`** flags duty verbs without a
metric, roles without context, summaries that do not name the role, unused posting keywords
present in the master, over-long bullets; warnings above a threshold trigger one retry. A
**posting analysis** (`EXTRACT`, Haiku) is stored once per job in `requirements_json`.

### Tuning pipeline

1. `TuningScheduler` (every 5 min) picks `OPEN` jobs without a package for the active CV version
   (when `tuning.auto`), or `POST /jobs/{id}/packages`. Idempotent on `(job_id, cv_version_id)`.
2. `AnthropicGateway.structured(TunedCvOutput.class, TUNE)`: system = rules block with
   `cache_control` (1 h); user block 1 = the stored CV YAML text verbatim with `cache_control`;
   user block 2 = the posting (volatile, after the last breakpoint); `maxTokens 16000`, effort
   HIGH, no thinking parameter. `refusal` → `FAILED` with the category; `max_tokens` → one retry
   with a shorter description.
3. `ClaimsChecker` — deterministic fabrication guard: experience entries match the master by
   (company, title, start, end), none added; skills ⊆ master; education, certifications and
   languages are copied from the master by the renderer, never from the model; each bullet shares
   ≥ 0.5 Jaccard with a master bullet of the same role or uses only that role's tokens; every
   number, year and percentage in CV and letter appears in the master or the posting; the letter
   names the job's company; no salary figures. Violation → one retry with the violations
   appended; second failure → `FAILED_GUARD` with the report in the UI. Clean → `CvLint` →
   `PdfRenderer` → artifacts → `PREPARED`.
4. `AnthropicGateway` is the single choke point: exponential backoff with jitter on 429/529/5xx,
   never on 400 or refusal; budget checks before each call; an `llm_call` row after each call
   with cache tokens and the cost from `Pricing`; logs token counts, never bodies.

### Cost monitoring

- **Ledger**: `llm_call` is the source of truth; `source_run.llm_cost_usd` and
  `application_package.cost_usd` are denormalised sums; `source_run.browser_pages` meters the browser.
- **Budgets**, all enforced in the gateway before a call: daily and monthly USD caps, per-source
  cap per run, per-package cap, per-purpose share (extraction may not starve tuning). Exceeding a
  cap = `SKIPPED_BUDGET` run or a package left `NEW`, never an error loop.
- **Metrics**: `masi_llm_cost_usd_total{purpose,model,source}`, `masi_llm_tokens_total{kind}`,
  `masi_llm_calls_total{purpose,model,stop_reason}`, `masi_llm_budget_used_ratio{period}`,
  `masi_browser_pages_total{source}`; browser pod CPU/memory from kube metrics.
- **Alerts** in the chart's `prometheus-rules.yaml`: daily budget ratio > 0.8, monthly > 0.9,
  cost rate > N USD/h, ledger write failures, browser pod restarts > 3/h, model-id drift
  between response and configuration.
- **Dashboards**: masi dashboard tile (today, month, per purpose, cost per prepared package);
  Grafana panels in schnappy-observability; a cost section in the monthly report.
- **Reconciliation** (later, optional): Anthropic Admin usage report vs ledger, alert on > 10 % drift.

### Reports and overview

`StatsService.period(from, to)` aggregates purely from timestamps: new/closed listings per source
and company, top hiring companies, title/seniority/tech-tag frequencies, salary ranges where
posted, remote share, median listing lifetime, funnel (prepared → reviewed → applied →
responses), source health and runs, LLM spend. `ReportScheduler` writes a `report` snapshot
weekly (Monday 06:00 Europe/Tallinn) and monthly (1st), so past reports stay byte-stable;
`POST /reports/generate` backfills. The dashboard endpoint returns open jobs, new/closed this
week, companies hiring now, packages awaiting review, applied/skipped, per-source health and last
run, LLM cost today/month, CV completeness. Weekly-report delivery as a notification is a later PR.

### API (`/api/masi/…`, all `@RequirePermission(JOBS)`)

| Endpoint | Purpose |
|---|---|
| `GET /jobs` (status, source, company, q, remote, since, packageStatus, paging, sort), `GET /jobs/{id}`, `PATCH /jobs/{id}`, `POST /jobs/manual` | registry |
| `POST /jobs/{id}/packages`, `GET /packages?status`, `GET /packages/{id}`, `GET /packages/{id}/artifacts/{kind}`, `POST /packages/{id}/review` {REVIEWED/APPLIED/SKIPPED, notes, response}, `POST /packages/{id}/regenerate` | review queue; transitions validated (APPLIED from NEW → 409) |
| `GET /companies` (q, hiring, status, paging), `GET /companies/{id}`, `PATCH /companies/{id}`, `POST /companies` | company registry |
| `GET /sources`, `PATCH /sources/{id}` {cron, enabled, configJson}, `POST /sources/{id}/run`, `GET /sources/{id}/runs` | sources admin |
| `GET /cv`, `GET /cv/versions`, `POST /cv/versions`, `POST /cv/versions/{v}/activate`, `POST /cv/validate`, `GET /cv/versions/{v}/preview.pdf`, `GET /cv/completeness` | CV master |
| `GET /dashboard`, `GET /stats?from&to`, `GET /reports?kind`, `GET /reports/{id}`, `POST /reports/generate` | overview and reports |

### site/ pages

`src/pages/Masi{Dashboard,Jobs,JobDetail,Companies,CompanyDetail,Sources,Cv,Reports}.tsx`, each
with a co-located vitest test; API functions in `src/services/api.ts` under `${API_BASE}/masi/…`;
lazy routes under `/masi/*` in `ProtectedRoute permission="JOBS"` and a nav link gated by
`hasPermission('JOBS')`; route list in `site/CLAUDE.md`. The Cv page is a structured editor over
the evidence bank with per-role completeness gaps beside the YAML. The JobDetail package panel
shows listing links per source, the description, claims violations and lint warnings next to the
rendered CV, PDF download, copy-letter, notes, Prepare / Mark reviewed / Mark applied / Skip,
and response recording. Reports use tables and simple charts.

## Migration strategy

One PR at a time, each full-reviewed with the test-quality audit, `./gradlew clean check` green
for Java and `npm run test` green for site.

1. **PR0 — this document** (`ops`). Nothing deployed changes.
2. **PR1 — repo skeleton + CI** (`masi`): copied plumbing, changeset 001, `application.yml`,
   Dockerfile, woodpecker, ArchUnit, context/health/auth/permission/provisioner/consumer tests.
   Invariant: `/api/actuator/health` 200 unauthenticated; `/api/masi/**` 401 without a token,
   403 without `JOBS`; CI green with sidecars. Manual steps recorded in the PR: Forgejo repo
   (SHA-1), `woodpecker-cli repo sync && repo add schnappy/masi`, repo secrets.
3. **PR2 — infra onboarding**, ordered sub-PRs:
   - 2a `ops`: `seed-vault-secrets.yml` += `postgres-masi`; seed test and prod.
   - 2b `platform`+`infra`: `postgres.databases += masi` in `schnappy-data` values (chart, test,
     production) → role, DB, ExternalSecret `schnappy-<env>-postgres-masi`.
   - 2c `platform` chart: `masi-deployment.yaml` + `masi-service.yaml` from `chess-*.yaml` with
     the AI env block, budgets and `MASI_BROWSER_ENDPOINT`; `masi-browser-deployment.yaml` +
     service; `_helpers.tpl`; `values.yaml` `masiService:` incl. `browser:` and `budgets:`;
     `network-policies.yaml` masi policy (chess policy + monitor's internet egress + Keycloak
     VIP + postgres/valkey/kafka/admin + masi-browser:3000) and a masi-browser policy (ingress
     from masi only, egress DNS + internet); masi selector in admin's ingress and site's egress;
     `prometheus-rules.yaml` job regex + cost/browser alerts.
   - 2d `platform` mesh: service accounts `masi`, `masi-browser`; authorization policies
     (postgres/valkey/kafka principals, `$httpCallers` admin += masi, masi-browser callable by
     masi only); destination rules; `-masi-route` `PathPrefix /api/masi` in **both**
     `httproutes.yaml` and `httproutes-external.yaml`.
   - 2e `infra`: `masiService:` blocks with `tag: "<sha>"  # masi` in test (enabled) and
     production (disabled until PR9); `schnappy-pr-envs.yaml` += masi; sonarqube
     `setup.projects` += `schnappy-masi`.
   - 2f `ops`+`monitor`: Taskfile `SERVICES` += masi; `depcheck.yaml` loop += masi; `ops/CLAUDE.md`.
   - 2g `admin`+`ops`: `Permission` += `JOBS`, changeset adding `JOBS` to the Admins group;
     the Keycloak playbook creates the `JOBS` realm role (properly, not a one-off).
   Invariant: masi pod Ready in test, `/api/masi/actuator/health` via the gateway, no Istio
   `shadow_denied`, other services' policies unchanged except the added selectors.
4. **PR3 — source survey** (`ops`, `094-masi-source-survey.md`): every candidate from the seed
   inventory plus the ~40 largest Estonian IT employers' ATS mapping, each with coverage, fetch
   method, structure stability, `robots.txt` verdict, ToS excerpt, rate expectations, chosen
   kind, cron, tier; a company-discovery section (register dump format/size/fields, ITL,
   Tehnopol, Dealroom); the `config_json` shape per kind; the fixture capture procedure. Doc only.
5. **PR4 — registry core + T1 job collectors** (`masi`): changesets 002–005, `HttpFetcher`
   (2 MB cap, manual redirects with SSRF re-validation), `HtmlText`, `Fingerprint`,
   `RegistryService`, `CollectorRegistry`, `CollectorRunner`, `SourceScheduler`, support bases,
   cv.ee / cvkeskus / tootukassa / ATS collectors with fixture tests, Jobs and Sources
   controllers. Invariant: a tick over fixtures produces the expected job rows; disabling a
   source cancels its future within 60 s.
6. **PR5 — headless browser collectors** (`masi`): Playwright client, `BrowserCollector`,
   `browser.*` properties, Testcontainers test against the browserless image serving a JS
   fixture page (rendered list + harvested JSON; RFC1918 navigation aborted; endpoint down →
   source `DEGRADED`, sibling unaffected), env-gated live smoke, MeetFrank / Bolt / Töötukassa
   GraphQL capture. Invariant: a JS-only fixture yields listings; the masi pod never contains a browser.
7. **PR6 — company registry** (`masi`): `CompanyService` + `CompanyMatcher`, stubs from
   listings, `ariregister/` streamed dump import, `itl/`, `tehnopol/`, ATS rows auto-created,
   Companies controller. Invariant: one employer across boards resolves to one company; the
   register import is idempotent.
8. **PR7 — CV master + renderer** (`masi`+`site`): changeset 006, `cv-schema.json`
   (evidence-bank shape), `CvSchemaValidator`, `CvMasterService` with `completeness()`,
   `PdfRenderer` + templates + bundled font, Cv controller, `MasiCv.tsx`, route and nav. A
   fictitious sample CV for tests. Invariant: valid YAML → activatable version + previewable PDF;
   invalid YAML rejected with the schema path.
9. **PR8 — tuning pipeline + cost ledger and budgets** (`masi`): changesets 007–008,
   `AnthropicGateway`, `Pricing`, cost metrics, `TuningPrompt`, `TunedCvOutput`, posting
   analysis, `ClaimsChecker`, `CvLint`, `TuningService`, `TuningScheduler`, Packages
   controller with state-machine negatives. Invariant: no package reaches `PREPARED` without a
   clean claims report; daily LLM cost cannot exceed the budget.
10. **PR9 — UI** (`site`+`infra`): Dashboard (with cost tile), Jobs, JobDetail, Companies,
    CompanyDetail, Sources with vitest tests; then production `masiService.enabled: true` via
    `task promote:prod`. Invariant: a `PREPARED` package is ≤ 2 clicks from the nav link and
    its PDF downloads as `application/pdf`.
11. **PR10 — stats, reports and cost dashboards** (`masi`+`site`+`platform`): changeset 009,
    `StatsService`, `ReportService`, `ReportScheduler`, Dashboard/Stats/Reports controllers,
    `MasiReports.tsx`, cost section in the monthly report, Grafana panels, alert rules proven to
    fire on a synthetic breach in test. Invariant: every number on the Reports page is
    reproducible from `first_seen_at`/`last_seen_at`/`closed_at` and `llm_call`.
12. **PR11 — dedupe hardening + lifecycle** (`masi`): `pg_trgm` near-duplicate hint (never
    auto-merged), detail 404/expired → close, `expires_at`, auto-disable re-enable, manual import
    UX. Invariant: a listing vanishing from one board closes its job only when every other
    listing is gone too.

Later: match scoring (`SCORE`), company enrichment (`ENRICH`), weekly-report notification
(Kafka → chat/email), T2 collectors, Admin-API cost reconciliation.

### Verification

Revert checks that must each turn a test red: fingerprint `norm()` made identity → the
two-sources-one-job test; `catch Throwable` removed from `CollectorRunner` → the sibling-source
test; `miss_count` no longer reset on sight → the close-too-early test; registry-code lookup
skipped → the duplicate-company test; `ClaimsChecker` returning empty → the fabricated-skill
case reaches `PREPARED`; `CvLint` returning empty → the duty-only bullet shows no warning;
`completeness()` returning 100 → the missing-metric test; the unique `(job_id, cv_version_id)`
dropped → the duplicate-package test; the budget query skipped → the budget test; the browser
`onRequest` abort dropped → the RFC1918 navigation test; a browser connect failure propagating →
the sibling-source test; `validateHostAtRequestTime` dropped on redirects → the RFC1918 redirect
test; `@RequirePermission(JOBS)` removed → the 403 tests; the font resource deleted → the
renderer test; the report period boundary shifted by an hour → the weekly-count test.

End-to-end in the test namespace after PR9/PR10: enable cv.ee → one tick → jobs and company
stubs appear → a package auto-prepares → job detail shows "0 violations", the PDF downloads, the
letter copies → Mark applied → the row leaves the queue with `applied_at` set → Reports shows
the funnel. Fabrication proof: activate a CV version with one skill removed, regenerate the same
job; the guard flags any output still naming it. Cache proof: the second tuning call has
`cache_read_tokens > 0`. Cost proof: the dashboard's "LLM cost today" equals `sum(llm_call.cost_usd)`.

## Risks

- **ToS / robots**: the survey gates every source; honest UA; cron ≥ hourly; Töötukassa's
  Crawl-delay honoured; forbidden sources stay disabled with the ToS excerpt in `terms_note`.
- **Anti-bot / WAF**: the browser handles JS rendering, not bot walls; a source that blocks the
  browser too stays disabled with the evidence recorded. Chromium in its own pod bounds memory,
  crashes and SSRF via redirects; the request guard aborts navigation to private hosts.
- **Scraper drift**: fixtures pin today's markup; health metrics, auto-disable and the run
  ledger make drift visible within one tick; an env-gated weekly live smoke per T1 source.
- **LLM cost**: daily/monthly budgets, per-run extraction cap, prompt caching (no dates or run
  ids in the system prompt, the CV sent as stored text verbatim, constant effort), Haiku for
  extraction, one package per job per CV version, `tuning.auto=false` as the off switch.
- **Cost blind spots**: a wrong pricing table makes the ledger wrong; the model-id drift check
  and the optional Admin-API reconciliation catch it; alerts fire on rate, not only on totals.
- **PII**: the CV lives only in the DB; fixtures are scrubbed; the gateway logs token counts
  only; the sample CV is fictitious.
- **Register dump size**: stream the zip, keep only EMTAK 62/63 active rows, run weekly.
- **Route precedence**: `/api/masi` must beat the `/api` catch-all in both HTTPRoute files.
- **`JOBS` role**: admin PR + playbook; site hides the nav link without it, so a missing role is
  visible, not silent.

To verify while implementing: openhtmltopdf version and Java 25 behaviour; the Anthropic Java
SDK builder for `outputConfig(Class)` together with effort on the beta path; the browserless
image and the Playwright protocol match; smoke-test.js per-service structure; Töötukassa
open-data format; cv.ee ToS; TeamDash/Teamtailor/BambooHR feed conventions.

## Status

DRAFT 2026-09-16 — approved by the operator in session; PR1 not started.
