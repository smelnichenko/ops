# 094 — masi: IT job & company registry for Estonia with reviewed CV tuning

## Decision

A new Spring Boot service `schnappy/masi` (`/api/masi`, CNPG database `masi`, Keycloak role
`JOBS`, UI pages in `site/`) that:

1. runs **one dedicated collector agent per source** on its own cron and feeds a deduplicated
   registry of Estonian IT positions, with a **headless browser** as a first-class collector kind;
2. maintains a **registry of Estonian IT companies** with its own discovery sources, and a
   **registry of contacts** (the recruiters and hiring managers the postings name, per company);
3. for each open position asks Claude for a **tuned CV and cover letter**, hard-checked against a
   versioned CV master so nothing can be fabricated, renders a PDF and parks the package in a
   review queue — **masi never sends anything**; the operator applies by hand and marks the job
   APPLIED or SKIPPED;
4. gives an **overview dashboard, weekly and monthly reports** reproducible from the database;
5. treats **cost monitoring as a feature**: ledger, budgets, metrics, alerts, dashboards.

Source discovery is a separate survey PR that precedes any scraper. LinkedIn, Glassdoor and
Facebook are ToS-forbidden and never polled; a "paste a URL" import covers them.

masi is a **single-operator** service: `JOBS` is granted to one user. The schema still scopes
CV versions and packages by `user_uuid` and every package read is filtered by it, so a second
holder of `JOBS` could never read the first one's CV or letters.

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
  scaffolding. Copying the plumbing keeps review on the new parts.
- Scrapers are the brittle part. One agent per source with its own health, budget and fixture
  keeps a dead board from being a platform incident.
- The admin service maps its `Permission` enum to Keycloak realm roles but only *looks up* roles
  (`KeycloakSyncService.getRoleRepresentation` returns null and drops an unknown role silently),
  and no playbook creates realm roles today, so a new `JOBS` permission needs an admin PR, a
  role-creation task and the realm ConfigMap, not a console click.

Seed inventory, verified 2026-09-16: cv.ee has an unauthenticated JSON search API; cvkeskus.ee
has per-category sitemaps + RSS and no anti-scraping clause; tootukassa.ee has a GraphQL
endpoint + sitemaps (Crawl-delay 10) and an open-data dataset (portal cert expired that day);
ATS JSON feeds verified for Wise (SmartRecruiters), Twilio and Veriff (Greenhouse), Pipedrive
(Lever); TeamDash is the common Estonian ATS with no public feed; MeetFrank returns 403 to plain
fetch. Company discovery: e-Business Register daily open-data dumps with EMTAK codes (CC BY 4.0),
ITL member list (128), Tehnopol portfolio, Startup Estonia/Dealroom (no export).

Library versions on Maven Central, checked 2026-09-16: `com.anthropic:anthropic-java` 2.63.0
(monitor/admin pin 2.15.0), `openhtmltopdf-pdfbox` 1.1.86, `com.microsoft.playwright:playwright`
1.63.0, `com.networknt:json-schema-validator` 3.0.7.

## Architecture

### Placement and reuse

| Item | Decision |
|---|---|
| Repo | `schnappy/masi`, package `io.schnappy.masi`, `sonar.projectKey schnappy-masi`, image `git.pmon.dev/schnappy/masi:$GIT_HASH`, `server.servlet.context-path: /api/masi` (so probes, `prometheus.io/path` and the gateway all use `/api/masi/actuator/…`; chess's `/api` layout would leave the actuator routed to monitor) |
| Copied from `monitor` (package rename only) | `SecurityConfig`, `SchedulerConfig`, `GatewayAuthFilter`, `RequestLoggingFilter`, `security/*` (`GatewayUser`, `Permission`, `RequirePermission`, `PermissionInterceptor`, `UserProvisioner`), `UserProvisionerAdapter`, `UrlValidator`/`CronValidator`/`RegexValidator`, `GlobalExceptionHandler`, `HealthController`, `Dockerfile`, `.woodpecker/{ci,cd,pitest,renovate}.yaml` (not `depcheck.yaml`, which is monitor's org-wide nightly), `renovate.json`, `spotbugs-exclude.xml`, test scaffolding (`TestcontainersConfiguration`, `CiTestConfiguration`, `TestHttpServer`, `TestJwt`), `ArchitectureTest` |
| Copied from `chess` | `UserEventConsumer` + `KafkaConfig` with **`groupId = "masi-user"`** (monitor's `user-sync` group would split `user.events` partitions with monitor and each user event would reach only one service), the `users` table shape (`uuid`, `email`, `enabled`, `created_at`) and its entity, `TestJwt`-only auth helper (monitor's `TestAuthHelper` needs group tables masi does not have) |
| Not copied | `CacheConfig`/Valkey (nothing in masi caches; drops a dependency, a NetworkPolicy rule and a mesh principal), mail, svix, minio, the unused jOOQ block, the dead `helm*`/`deploy*` Gradle tasks |
| `build.gradle` additions | `anthropic-java` 2.63.0, `jsoup`, `rome`, `openhtmltopdf-pdfbox` + `-slf4j` 1.1.86, `spring-boot-starter-thymeleaf`, `json-schema-validator` 3.0.7, `playwright` 1.63.0 |
| Jackson | Spring-facing JSON (`config_json`, `requirements_json`, `claims_report_json`, `lint_json`, `payload_json`, DTOs) goes through the Boot 4 `tools.jackson` mapper; `json-schema-validator` and the Anthropic SDK's `outputConfig` schema derivation use their own Jackson 2 — never share a mapper between the two trees |
| Scheduler | monitor's `MonitorScheduler` pattern: DB polled every 60 s, `ConcurrentHashMap<key, ScheduledFuture>`, cron-change detection, `new CronTrigger(cron, ZoneId.of("Europe/Tallinn"))` (the container runs UTC); a 5-thread `ThreadPoolTaskScheduler` only *dispatches* — collector and tuning bodies run on virtual threads; per-source `tryLock` so "Run now" and the cron never overlap; `replicas: 1` is a constraint (the map is in-memory) |
| LLM | monitor's structured-output idiom (`outputConfig(Pojo.class)` on the beta messages client) behind one `AnthropicGateway` adding retry/backoff, budgets, ledger, prompt caching |
| Permission | new realm role **`JOBS`**; `METRICS`/`CHAT` sit in the default Users group and would expose the CV and the Anthropic spend to every registrant |
| Artifacts | PDFs in Postgres `bytea` (`byte[]` with `@JdbcTypeCode(SqlTypes.VARBINARY)`, never `@Lob`, which Hibernate maps to Postgres large objects); `STORAGE_*` is not wired in the chart (verified: no `STORAGE_`/`MINIO_`/`S3_` env in any app template), volumes are small, CNPG backups cover it |
| CV master | in the DB via the UI, not a repo file: PII must not ride through CI/Kaniko/depcheck clones; versioned per row; survives redeploys. Accepted consequence: the CV also lives in the CNPG barman backups on the Pi store and in every restore drill. The test namespace only ever holds the fictitious sample CV |
| PDF | openhtmltopdf from Thymeleaf XHTML templates; one OFL font on the classpath (the JRE image has no fonts, `readOnlyRootFilesystem`); PDFBox scratch in the `/tmp` emptyDir |
| Browser | Chromium in its own `masi-browser` Deployment; masi connects with Playwright over the network; the masi image never contains a browser (Playwright Java does unpack its Node driver into `java.io.tmpdir`, i.e. the `/tmp` emptyDir, and runs a Node process inside the pod's memory limit — sized for) |
| Models | `claude-opus-5` for tuning and cover letter (adaptive thinking default, effort HIGH); `claude-haiku-4-5` for extraction and classification; prompt caching on the rules block and the CV block. Env `MASI_AI_TUNING_MODEL` / `MASI_AI_EXTRACT_MODEL`, never the chart-level `AI_MODEL` (which is Haiku in test values) |

Properties (`masi.*`, env in parentheses): `enabled` (MASI_ENABLED); `http.{connect-timeout,
read-timeout,user-agent,max-body-bytes}` with UA `masi/1.0 (+https://pmon.dev; job registry;
<contact>)`; `ai.{enabled,api-key,tuning-model,extract-model,daily-budget-usd,monthly-budget-usd,
max-retries,in-flight}` (AI_ENABLED, ANTHROPIC_API_KEY, MASI_AI_TUNING_MODEL, MASI_AI_EXTRACT_MODEL,
AI_DAILY_BUDGET_USD, AI_MONTHLY_BUDGET_USD); `ai.pricing.<model>.{input,output,cacheRead,cacheWrite}`;
`ai.purpose-share.<purpose>`; `tuning.auto`; `lifecycle.close-after-misses` (3);
`browser.{enabled,endpoint,nav-timeout,run-deadline,max-parallel,user-agent}` (MASI_BROWSER_ENDPOINT);
`reports.weekly-cron` (`0 0 6 * * MON`, Europe/Tallinn); `test.allowed-hosts` (test-only, see Verification).

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
             (one sub-package per source; package name == the source key's package part)
dedupe/      Fingerprint, Normalizer, ListingMatcher, CompanyMatcher
registry/    RegistryService, CompanyService, RegistryQuery
ai/          AnthropicGateway (the only class importing com.anthropic.*), LlmLedgerService, Pricing
cv/          CvMasterService (versions, validation, completeness), CvModel
tuning/      TuningService, TuningPrompt, TunedCvOutput, ClaimsChecker, ClaimsReport, CvLint
render/      PdfRenderer, CvTemplateModel
reports/     StatsService, ReportService, ReportScheduler
scheduler/   SourceScheduler, TuningScheduler, RecoverySweeper
controller/  Jobs, Packages, Companies, Sources, Cv, Dashboard, Reports
```

ArchUnit rules on top of monitor's: source packages `..collector.(*)..` excluding
`support|fetch|html|browser` depend only on `..collector..`, `..dedupe..`, `..dto..`,
`..validation..`; a `@Component` in a source package must implement `Collector` and be the only
public class there; `..tuning..` and `..render..` never depend on `..collector..`; only `..ai..`
imports `com.anthropic..`; every handler method in `..controller..` except health carries
`@RequirePermission`. The runtime half — each bean's `sourceKey()` package part equals its
package name, and the bean set equals the seeded `source.key` set — is a Spring integration
test (`CollectorRegistryTest`), because ArchUnit cannot read a runtime value.

### Data model (Liquibase, `author="masi-service"`)

Jobs, listings and companies are never deleted: closed rows are the history the reports aggregate.
Seed inserts carry `preConditions onFail="MARK_RAN"` on row existence, because rows are editable
and settings persist. `pg_trgm` is a trusted extension on PG 17, so the `masi` owner creates it
from a changeset without a superuser step.

| Changeset | Tables and key columns |
|---|---|
| 001 users | `users` (uuid PK, email, enabled, created_at) as chess |
| 002 sources | `source`: key (unique; `<package>` or `<package>:<instance>` for per-company ATS rows, bean resolved by the package part), name, kind (`DETERMINISTIC`/`LLM_EXTRACT`/`BROWSER`), scope (`JOBS`/`COMPANIES`/`BOTH`), base_url, cron, enabled, config_json, terms_note, health (`OK`/`DEGRADED`/`FAILING`/`DISABLED_AUTO`), consecutive_failures, last_run_at, last_success_at, last_error. `source_run`: source_id, started/finished_at, status (`OK`/`ERROR`/`TIMEOUT`/`SKIPPED_BUDGET`/`SKIPPED_BROWSER`/`INTERRUPTED`), complete, fetched, parsed, new_jobs, updated_listings, closed_listings, new_companies, browser_pages, error, llm_cost_usd |
| 003 companies | `company`: name, name_norm (unique), registry_code (unique, nullable), website, domain_norm, careers_url, ats_vendor, ats_feed_url, emtak_code, size_band, hq_city, remote_policy, tech_tags, status (`ACTIVE`/`DORMANT`), origin (`DISCOVERED`/`FROM_LISTING`/`MANUAL`), first_seen_at, last_seen_at, last_enriched_at, user_rating, blacklisted, user_note. `company_alias`: company_id, alias_norm (unique) |
| 004 registry | `job`: fingerprint (unique), company_id, title, title_norm, location, remote, seniority, description_text, tech_tags, requirements_json, salary_min/max, status (`OPEN`/`CLOSED`), first_seen_at, last_seen_at, closed_at, reopened_count, match_score, user_note. `job_listing`: job_id, source_id, external_id, url (unique with source_id), title_raw, company_raw, description_raw, posted_at, expires_at, first_seen_at, last_seen_at, miss_count, closed_at, raw_hash |
| 005 seed sources | one insert per surveyed source, `enabled=false`; later sources get `0NN-seed-source-<key>` |
| 006 cv versions | `cv_version`: user_uuid, version, yaml, schema_version, note, active (partial unique per user), activated_at, created_at |
| 007 packages | `application_package`: job_id, cv_version_id, **unique (job_id, cv_version_id)**, status (`NEW`→`PREPARING`→`PREPARED`→`REVIEWED`→`APPLIED`\|`SKIPPED`, `FAILED_GUARD`, `FAILED`), preparing_since, attempts, tuned_cv_json, cover_letter, claims_report_json, lint_json, model, cost_usd, error, user_notes, applied_at, response (`NONE`/`REPLIED`/`INTERVIEW`/`OFFER`/`REJECTED`). `package_artifact`: package_id, kind (`CV_PDF`/`LETTER_TXT`), **unique (package_id, kind)** (regenerate overwrites), content_type, bytes, sha256, size |
| 008 llm calls | `llm_call`: purpose (`EXTRACT`/`TUNE`/`LETTER`/`SCORE`/`ENRICH`), model, source_id, package_id, status (`PENDING`/`OK`/`ERROR`/`LOST`), estimated_cost_usd, input/cache_read/cache_write/output tokens, cost_usd, stop_reason, latency_ms, error, created_at |
| 009 reports | `report`: kind (`WEEKLY`/`MONTHLY`), period_start, period_end (unique with kind), payload_json, generated_at |
| 010 contacts | `contact`: company_id (nullable), kind (`PERSON`/`GENERIC`), name, title, email, phone, origin (`FROM_LISTING`/`FROM_REGISTER`/`MANUAL`), source_id, first_listing_id, first_seen_at, last_seen_at, do_not_contact, user_note; unique (company_id, lower(email)) where email is not null, else (company_id, name_norm). Operator decision 2026-09-18: "build requires contacts registry as well as a company registry" — supersedes the earlier rule that recruiter contacts are never stored. Basis: the operator's own job search (GDPR legitimate interest, data the employer published for that purpose); stored minimally, never enriched from third parties, deletable per row, never in fixtures (synthetic replacements). Ships in PR4 (table, capture, API), UI page in PR9, letter addressed to the named contact in PR8. |

Retention: a nightly job nulls `package_artifact.bytes` (keeping sha256 and size) for
`SKIPPED` packages and for packages of jobs closed more than 90 days ago.

### Source layer: one collector agent per source

```
interface Collector { String sourceKey(); CollectorKind kind(); Set<Scope> scopes();
                      CollectResult collect(CollectContext ctx); }
record RawListing(externalId, url, titleRaw, companyRaw, location, descriptionRaw, postedAt, expiresAt, extras)
record RawCompany(name, registryCode, website, careersUrl, atsVendor, atsFeedUrl, emtakCode, extras)
record CollectResult(listings, companies, pagesFetched, warnings, complete)
```

- **Registry.** `CollectorRegistry` maps beans by key and cross-checks `source` rows at startup:
  a row whose package part has no bean → `FAILING`, not scheduled. `CollectorRegistryTest`
  asserts the two sets agree in both directions, so forgetting the class or the seed changeset
  fails CI (a WARN alone fails nothing).
- **Isolation.** `CollectorRunner.run(source)`: per-source `tryLock` (a run in progress means the
  new request is skipped, never queued), MDC `source=<key>`, a `source_run` row, a virtual thread
  with a per-kind deadline (120 s deterministic/LLM, 600 s browser), `catch Throwable`, ingest in
  its own transaction, then health: success resets failures; ≥3 → `DEGRADED`; ≥10 →
  `DISABLED_AUTO` (UI re-enable resets). A browser endpoint that is unreachable yields
  `SKIPPED_BROWSER`, which does **not** count towards `consecutive_failures` — an overnight
  browser-pod outage must not pin every browser source off. What the catch protects is the run
  row (`finished_at`, `ERROR`), the failure counter and the *next* scheduled run of the same
  source; sibling sources are protected by the thread boundary, and both are tested separately.
  Metrics `masi_collect_runs_total{source,status}`, `masi_collect_listings{source}`,
  `masi_collect_duration_seconds{source}`, `masi_collect_llm_cost_usd{source}`, gauges
  `masi_source_health{source,state}`, `masi_source_last_success_seconds{source}`.
- **Recovery.** `RecoverySweeper` on startup and every 10 min: `source_run` rows without
  `finished_at` → `INTERRUPTED`; packages `PREPARING` for more than 15 min → `NEW`
  (`attempts ≥ 3` → `FAILED`); `llm_call` rows `PENDING` for more than 10 min → `LOST`,
  keeping the estimate in the budget.
- **Scheduling.** `SourceScheduler` is monitor's scheduler with `collectorRunner.run(source)` as
  the task body; "Run now" enqueues the same runner and hits the same lock.

| Source shape | Kind | Base |
|---|---|---|
| JSON API, ATS feed, RSS/Atom, sitemap, list page with stable markup | `DETERMINISTIC` — always preferred: free, exact, offline-testable | `JsonApiCollector`, `AtsCollector`, `RssCollector`, `SitemapCollector`, `JsoupListCollector` |
| Bespoke or unstable career pages whose HTML still carries the data | `LLM_EXTRACT` — Haiku; Sonnet only when a fixture shows Haiku missing fields | `LlmExtractCollector`: jsoup visible text (60 k chars) → structured output → deterministic post-validation (every URL must occur in the fetched HTML or resolve under `base_url`; a listing failing it is dropped with a warning) → per-run cost cap |
| JS-rendered lists, "load more", data only in XHR (MeetFrank, Bolt, Töötukassa GraphQL) | `BROWSER` | `BrowserCollector`: navigate in the browser pod, wait for a selector, scroll/click up to `maxPages`, capture rendered HTML **and** XHR responses matching `harvestUrlPattern`, hand off to the jsoup/JSON/LLM parsers |
| Login wall, WAF that blocks the browser too, ToS-forbidden | not collected; `manual/` = "add listing by URL" | — |

**Headless browser.** A `masi-browser` Deployment in the chart runs a browserless/Chromium
image pinned by digest, with `maxSurge: 0`, requests 512Mi / limits 2Gi (150–300 MiB per
context plus Envoy plus the Node driver), an `ephemeral-storage` limit, liveness on its HTTP
health endpoint, and a NetworkPolicy: ingress from the masi selector on 3000 only; egress DNS
plus `ipBlock 0.0.0.0/0 except 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16,
100.64.0.0/10` on 80/443 only — no VIP rule, no 587. **That NetworkPolicy is the SSRF control**:
DNS resolves inside Chromium, so nothing masi validates before navigation proves where the
browser connects. Pod hardening, stated because the copied `securityContext`
(`seccompProfile: RuntimeDefault`, `drop: [ALL]`) forbids Chromium's user-namespace sandbox:
browserless runs `--no-sandbox`, so the pod boundary is the sandbox and the compensating
controls are `automountServiceAccountToken: false`, no secrets mounted, `runAsNonRoot` with the
image's own uid, `readOnlyRootFilesystem` with emptyDirs for `/tmp`, the browserless workspace
and `/dev/shm` (`medium: Memory`, 512Mi; Kubernetes' default 64 MiB crashes renderers),
`--disable-quic` (UDP 443 is dropped by the policy and QUIC probing adds latency), browserless
`TIMEOUT` = the run deadline and `CONCURRENT` = `max-parallel` so the server kills sessions
itself. If the chosen image requires a `TOKEN`, it is seeded at `secret/<env>/masi-browser` via
ESO (no default accounts in values); otherwise access is gated by the NetworkPolicy plus a
dedicated Istio ALLOW policy on component `masi-browser` for principal `<fullname>-masi` on
port 3000 and nothing else (the shared `$httpCallers` template would also admit the gateway and
Hyperfoil). The sidecar stays (STRICT mTLS); the CDP websocket upgrades through Envoy on a
Service port named `http`, and the mesh `DestinationRule` idle timeout (3600 s) exceeds any run.

masi side: Playwright for Java with `connectOverCDP` (or `connect` against a Playwright server
whose version equals the client's), `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1`, one context per run,
at most `browser.max-parallel` (2) runs with the permit released in `finally`. Second-layer
guard: `context.route("**/*", …)` (the observe-only `page.onRequest` cannot abort) re-validates
every request host including redirects, iframes and websockets and aborts private, loopback
(the sidecar's Envoy admin listens on `127.0.0.1:15000`), link-local and non-allow-listed hosts,
recording each abort in the run's warnings; downloads, geolocation and camera blocked; the
deadline watchdog closes the `BrowserContext` and drops the connection rather than interrupting
the thread (a blocking websocket read cannot be interrupted). Gauges `masi_browser_reachable`
(a periodic connect + `about:blank`), `masi_browser_sessions_active`, counter
`masi_browser_pages_total{source}`.

**Adding a source** (acceptance list for every collector PR): survey row → class
`collector.<key>.<Name>Collector` → fixture `src/test/resources/fixtures/<key>/…` captured from the
real site and scrubbed, with a `CAPTURE.md` (exact curl/Playwright command, date, what was
scrubbed) → served by `TestHttpServer`'s `/fixtures/**` context (classpath resources, content-type
from a sidecar `.headers` file — the copied server serves hard-coded strings only) → test
asserting exact `RawListing`/`RawCompany` values plus the negatives (broken selector →
`complete=false`, `DEGRADED`, no miss counting; a sibling source in the same tick still runs) →
seed changeset → `CollectorRegistryTest` agrees → enable in the UI → check `source_run` and
Grafana → the env-gated live smoke for the source asserts ≥ N listings, every URL under
`base_url`, ≥ 1 `posted_at` within 7 days, and the same non-null field set as the fixture test
(a field that goes null live but not in the fixture is drift). otsintood.ee is an Alma Career
sibling of cv.ee, so it is a coverage cross-check, not an independent oracle; cvkeskus.ee
(Ringier) is the independent one.

Source tiers from the seed inventory, to be confirmed by the survey:

| Tier | Source | Access |
|---|---|---|
| T1 | cv.ee | `GET /api/v1/vacancy-search-service/search?categories[]=INFORMATION_TECHNOLOGY` (id, title, salary, remoteWork, employerName, publish/expiration dates) |
| T1 | cvkeskus.ee | per-category sitemap (~600 URLs, lastmod) + RSS for freshness + detail HTML via jsoup |
| T1 | tootukassa.ee | sitemap `/web/joboffers/sitemap.xml` (Crawl-delay 10) + detail HTML; the browser harvests the GraphQL responses once to learn the schema, then a deterministic collector replays it; open data when the portal is reachable |
| T1 | ATS feeds | `AtsCollector` per company row (`ats:<company>`): SmartRecruiters (Wise, `?country=ee`), Greenhouse (Twilio, Veriff), Lever (Pipedrive) |
| T2 browser | MeetFrank (WAF; the survey decides), Bolt careers (13 JS pages), Nortal, Microsoft/Ericsson SPAs, otsintood.ee (Alma Career sibling of cv.ee — coverage check only), TeamDash pages if jsoup fails |
| T2 | Teamtailor (Swedbank `jobs.json`), BambooHR (Ridango), TeamDash (Helmes, Cybernetica, LHV), devjobsscanner |
| never | LinkedIn, Glassdoor, Facebook (ToS), Indeed (no EE site), hh.ee (dead) |
| companies | e-Business Register general-data dump (daily, JSON/Parquet, EMTAK 62/63, active only, streamed weekly), ITL members (HTML), Tehnopol portfolio (HTML), employer names from the boards (stub + enrich), Dealroom manual only |

### Companies

`CompanyService.resolve(rawCompany)` dedupes by registry code, then `name_norm`, then
`domain_norm`, then aliases; a listing naming an unknown company creates a `FROM_LISTING` stub.
Enrichment (`ENRICH`, Haiku, budgeted) finds the careers URL and ATS vendor; a detected ATS gets
its own `source` row `ats:<company>` so the company's feed becomes its own collector agent.
Company detail shows open/closed listings history, hiring velocity and its **contacts**.
`ContactService.record(rawContact, company, listing)` upserts by (company, email) or (company,
name) and stamps `last_seen_at`; sources that publish a contact person feed it: cv.ee
(`contacts{firstName,lastName,email,phone}`), Töötukassa (`avalikKontaktisik`), Teamtailor
(`_jobposting.hiringOrganization`/recruiter block where present), TeamDash job pages (contact
block), the register's `EMAIL` as `GENERIC` (often a personal Gmail — flagged, never mailed
automatically). Blacklisted companies never get packages; `do_not_contact` contacts never appear
in a letter.

### Dedupe and lifecycle

- `Fingerprint.of(companyRaw, titleRaw)` = SHA-256 of `norm(company)|norm(title)`; `norm` folds
  diacritics, lowercases, strips legal suffixes (`oü`, `as`, `ltd`, `ou`, `llc`, `gmbh`, `inc`),
  gender tags, punctuation. Location excluded (boards disagree, and the same posting in Tallinn
  and Tartu is one job for this operator); seniority words kept.
- Ingest: upsert `job_listing` by `(source_id, url)`; find or create `job` by fingerprint;
  `last_seen_at = now`, `miss_count = 0`. A fingerprint hit on a `CLOSED` job **reopens** it
  (`status=OPEN`, `closed_at` cleared, `reopened_count++`; the listings keep their own
  `closed_at` history), and its existing package is regenerated in place if the description hash
  changed.
- Closing: only after a run with `status = OK` **and** `complete = true` do listings of that
  source with `last_seen_at < run.started_at` get `miss_count++`; at `close-after-misses` →
  `closed_at`. A `complete=false`, `ERROR`, `TIMEOUT`, `SKIPPED_*` or `INTERRUPTED` run never
  touches `miss_count` — a broken selector must not close the world. Also close on detail
  404/410, a parsed "expired" marker, or `expires_at` passed. A job closes when all its listings
  are closed.

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
the posting. `CvMasterService.completeness()` scores per-role gaps and an empty `positioning`
block, shown in the editor and on the dashboard until 100 %. `cv-schema.json` has no photo,
birth-date, marital-status or ID-code fields and rejects unknown properties, which is where
the no-personal-data rule is enforced. `TuningPrompt.RULES` (the cached block) demands results-first bullets with
metrics kept verbatim, a company-context line per role, a 3–4 line fit summary naming the role
and company, the posting's terms where supported, irrelevant roles collapsed to one line, and
never a fact absent from the master. A deterministic **`CvLint`** flags duty verbs without a
metric, roles without context, summaries that do not name the role, unused posting keywords
present in the master, over-long bullets, a keyword-density rule against stuffing (a term
repeated more than N times or a skills list longer than the master's top-K for the posting),
an LLM-boilerplate stop-list (spearheaded, leveraged, passionate, results-driven, proven track
record), tense/voice drift; warnings above a threshold trigger one retry. The company-context
line is rendered from master fields, never from model prose. A
**posting analysis** (`EXTRACT`, Haiku) is stored once per job in `requirements_json`.

### Tuning pipeline

1. `TuningScheduler` (`fixedDelay` 5 min, dispatching to virtual threads through a single-permit
   tuning lane) picks `OPEN` jobs without a package for the active CV version **whose
   `first_seen_at` is after `cv_version.activated_at`** (when `tuning.auto`), or
   `POST /jobs/{id}/packages` (returns `202 Accepted` with a status URL; the existing
   `HighRequestLatency` alert would fire on a synchronous Opus call). Activating a new CV version
   never auto-tunes the backlog: re-tuning older open jobs is an explicit "Re-tune N jobs (~$X)"
   action. Idempotent on `(job_id, cv_version_id)`; `regenerate` overwrites the row in place.
2. `AnthropicGateway.structured(TunedCvOutput.class, TUNE)`: system = rules block with
   `cache_control` (1 h); user block 1 = the stored CV YAML text verbatim with `cache_control`;
   user block 2 = the posting (volatile, after the last breakpoint); `maxTokens 16000`, effort
   HIGH, no thinking parameter. `refusal` → `FAILED` with the category; `max_tokens` → one retry
   with a shorter description.
3. `ClaimsChecker` — deterministic fabrication guard: experience entries match the master by
   (company, title, start, end), none added **and none removed** (a collapsed role keeps
   company, title and dates); skills ⊆ master; a selected achievement's master `metric`
   appears verbatim in its bullet; autonomy verbs never outrank the matched master bullet
   (participated < contributed < proposed < owned/led < decided — token overlap is blind to a
   single verb swap, the seniority-inflation failure); output language equals the master's
   language; the posting's title never becomes the current title; skills ⊆ master; education, certifications and
   languages are copied from the master by the renderer, never from the model; each bullet shares
   ≥ 0.5 Jaccard with a master bullet of the same role or uses only that role's tokens; every
   number, year and percentage in the CV appears in the master (posting numbers such as "5 years
   of Kubernetes" are the likeliest fabrication and are allowed only in the letter's description
   of the role, never as the candidate's own); the letter names the job's company; no salary
   figures. Violation → one retry with the violations appended; second failure → `FAILED_GUARD`
   with the report in the UI. Clean → `CvLint` → `PdfRenderer` → artifacts → `PREPARED`.
4. `AnthropicGateway` is the single choke point: exponential backoff with jitter on 429/529/5xx,
   never on 400 or refusal; **reserve-then-settle** budgeting (below); an `llm_call` row before
   and after each call; logs token counts, never bodies (a log-capture test proves it).

### Cost monitoring

- **Ledger and budgets, atomically.** Before a call the gateway inserts the `llm_call` row as
  `PENDING` with `estimated_cost_usd` inside `pg_advisory_xact_lock(hashtext('masi-budget'))`
  and compares `sum(coalesce(cost_usd, estimated_cost_usd))` for the day (UTC), the month, the
  source's run, the package and the purpose share against the caps in the same transaction; a
  cap reached means no HTTP request, a `SKIPPED_BUDGET` run or a package left `NEW`, never an
  error loop. After the response the row is settled with real usage and cost from `Pricing`;
  `ai.in-flight` (2) bounds concurrent calls; a restart mid-call leaves a `PENDING` row that the
  sweeper marks `LOST` while keeping its estimate — spend never escapes the ledger. The
  daily/monthly boundary is UTC and says so on the dashboard.
- **Key isolation.** masi uses its own Vault path `<prefix>/ai-masi` and ExternalSecret
  `<fullname>-ai-masi` (gated on `masiService.ai.existingSecret`), not the shared `<prefix>/ai`
  key that monitor and admin use: a runaway must be revocable without breaking admin's
  registration approval, and the console usage report must be splittable per service. A spend
  limit on that key in the Anthropic console is the backstop outside the process that spends.
- **Metrics**: `masi_llm_cost_usd_total{purpose,model,source}`, `masi_llm_tokens_total{kind}`,
  `masi_llm_calls_total{purpose,model,stop_reason}`, `masi_llm_budget_used_ratio{period}`,
  `masi_llm_ledger_failures_total`, `masi_llm_model_mismatch_total{configured,returned}`,
  `masi_browser_pages_total{source}`, the source-health gauges above. Nothing scrapes cAdvisor
  today (the kubelet ServiceMonitor is disabled), so browser CPU/memory is not claimed; OOM and
  restarts come from the existing `ContainerOOMKilled` / `PodRestartingFrequently` rules.
- **Alerts** in the chart's `prometheus-rules.yaml`, each with a `runbook_url` like every
  existing rule, shipped with PR8 (they belong with the ledger, and production is enabled only
  after them): `MasiBudgetDay` (ratio > 0.8), `MasiBudgetMonth` (> 0.9), `MasiCostRate`
  (> N USD/h), `MasiLedgerFailures`, `MasiModelMismatch`, `MasiSourceDisabledAuto`,
  `MasiSourceStale` (`time() - last_success > 3 × cron interval`), `MasiBrowserUnreachable`,
  `MasiBrowserSaturated` (`sessions_active == max-parallel` for 15 min), each paired with
  `absent()` cover since the ratios are app-computed. Rules render only where `alerts.enabled`
  (production today), so proof is `promtool test rules` unit files in platform CI, not a
  synthetic breach in test.
- **Dashboards**: masi dashboard tile (today, month, per purpose, cost per prepared package);
  Grafana panels in schnappy-observability; a cost section in the monthly report.
- **Reconciliation** (later, optional): Anthropic Admin usage report vs ledger, alert on > 10 % drift.

### Reports and overview

`StatsService.period(from, to)` aggregates only from `first_seen_at`, `closed_at`, `posted_at`,
`applied_at`, `llm_call.created_at` and run timestamps — never from `last_seen_at`, which later
ticks mutate — so a period's stats are the same whenever they are computed. Stats: new/closed
listings per source and company, top hiring companies, title/seniority/tech-tag frequencies,
salary ranges where posted, remote share, median listing lifetime, funnel (prepared → reviewed →
applied → responses), source health and runs, LLM spend. `ReportScheduler` writes a `report`
snapshot weekly (Monday 06:00 Europe/Tallinn) and monthly (1st) so past reports stay
byte-stable; `POST /reports/generate` backfills (201 written, 200 already stored). The dashboard endpoint returns open jobs,
new/closed this week, companies hiring now, packages awaiting review, applied/skipped, per-source
health and last run, LLM cost today/month, CV completeness. Weekly-report delivery as a
notification is a later PR.

### API (`/api/masi/…`, all `@RequirePermission(JOBS)`, package and CV reads scoped by `user_uuid`)

| Endpoint | Purpose |
|---|---|
| `GET /jobs` (status, source, company, q, remote, since, packageStatus, paging, sort), `GET /jobs/{id}`, `PATCH /jobs/{id}`, `POST /jobs/manual` | registry |
| `POST /jobs/{id}/packages` (202), `GET /packages?status`, `GET /packages/{id}`, `GET /packages/{id}/artifacts/{kind}`, `POST /packages/{id}/review` {REVIEWED/APPLIED/SKIPPED, notes, response}, `POST /packages/{id}/regenerate` (202), `POST /packages/retune` {cvVersion} (202, explicit backlog re-tune with a cost estimate) | review queue; transitions validated (APPLIED from NEW → 409, regenerate on APPLIED → 409) |
| `GET /companies` (q, hiring, status, paging), `GET /companies/{id}`, `PATCH /companies/{id}`, `POST /companies` | company registry |
| `GET /contacts` (q, company, paging), `GET /companies/{id}/contacts`, `POST /contacts`, `PATCH /contacts/{id}` {title, email, phone, doNotContact, userNote}, `DELETE /contacts/{id}` | contacts registry (a real delete: personal data) |
| `GET /sources`, `PATCH /sources/{id}` {cron, enabled, configJson}, `POST /sources/{id}/run` (202; 409 while running), `GET /sources/{id}/runs` | sources admin |
| `GET /cv`, `GET /cv/versions`, `POST /cv/versions`, `POST /cv/versions/{v}/activate`, `POST /cv/validate`, `GET /cv/versions/{v}/preview.pdf`, `GET /cv/completeness` | CV master |
| `GET /dashboard`, `GET /stats?from&to`, `GET /reports?kind`, `GET /reports/{id}`, `POST /reports/generate` | overview and reports |

### site/ pages

`src/pages/Masi{Dashboard,Jobs,JobDetail,Companies,CompanyDetail,Sources,Cv,Reports}.tsx`, each
with a co-located vitest test; API functions in `src/services/api.ts` under `${API_BASE}/masi/…`;
lazy routes under `/masi/*` in `ProtectedRoute permission="JOBS"` and a nav link gated by
`hasPermission('JOBS')`; `JOBS` added to `ALL_PERMISSIONS` in `src/pages/Admin.tsx` (else the
Admin UI cannot grant it); route list in `site/CLAUDE.md`. The Cv page is a structured editor
over the evidence bank with per-role completeness gaps beside the YAML. The JobDetail package
panel shows listing links per source, the description, claims violations and lint warnings next
to the rendered CV, PDF download, copy-letter, notes, Prepare / Mark reviewed / Mark applied /
Skip, and response recording. Reports use tables and simple charts.

## Migration strategy

One PR at a time, each full-reviewed with the test-quality audit, `./gradlew clean check` green
for Java and `npm run test` green for site.

1. **PR0 — this document** (`ops`). Nothing deployed changes.
2. **PR1 — repo skeleton + CI** (`masi`): copied plumbing, changeset 001, `application.yml`
   with `context-path: /api/masi`, Dockerfile, woodpecker (ci, cd, pitest, renovate with
   `RENOVATE_REPOSITORIES: schnappy/masi`), ArchUnit incl. the permission-coverage rule,
   context/health/auth/permission/provisioner/consumer tests. Invariant: `/api/masi/actuator/health`
   200 unauthenticated; `/api/masi/jobs` 401 without a token, 403 without `JOBS`; Kafka consumer
   group `masi-user` (service-unique); Woodpecker CI green with its Postgres service container;
   a CI step asserts the image contains no `ms-playwright` or `chrome` path. Manual steps
   recorded in the PR: Forgejo repo (SHA-1), `woodpecker-cli repo sync && repo add schnappy/masi`,
   the `pitest-nightly` and `renovate` crons, the "Registered repos" list in `ops/CLAUDE.md`
   (pipelines read the shared `woodpecker-ci-secrets`; there are no per-repo secrets).
3. **PR2 — infra onboarding**, ordered sub-PRs; each states its rollback:
   - 2a `ops`: `seed-vault-secrets.yml` += `postgres-masi` (generatable) and `ai-masi`
     (`api_key` from `MASI_ANTHROPIC_API_KEY`, one key for prod and test, skipped visibly while
     unset); seed test and prod. Rollback on abandonment: remove both entries, add the paths to
     the "Delete retired vault path" loop for one release, and revoke the key in the Anthropic
     console — a leftover `ai-masi` is a live third-party credential, not harmless.
   - 2b `platform`+`infra`: **convert `cnpg-init-users.yaml` to a Sync hook Job**
     (`argocd.argoproj.io/hook: Sync`, `hook-delete-policy: BeforeHookCreation`, keep
     `sync-wave: 10` — the s3gw-buckets pattern) in the same platform PR, because the plain Job
     carries `sync-options: Delete=true`, which Argo does not know, and adding a database changes
     its immutable `spec.template`: this is the first time `postgres.databases` changes since
     the annotation landed and the apply would fail. Then `postgres.databases += masi` in
     `schnappy-data` values (chart, test, production) → role, DB, ExternalSecret
     `schnappy-<env>-postgres-masi`. Gate: 2a seeded and the ExternalSecret `SecretSynced`
     before merging (else the hook pod sits in `CreateContainerConfigError` until its deadline).
     Confirm in test that the CNPG webhook accepts the `postInitSQL` edit on an initialised
     cluster before prod. Rollback: revert the values commit; role and DB stay by design (the
     data app never prunes); a failed Job is deleted and re-synced — the Job is idempotent.
     **Done 2026-09-17** (platform #31–#33, infra #28 + main d2d10f4), with three corrections
     the plan did not foresee: (1) a hook that keeps the legacy plain Job's name collides with
     it on the first sync — Argo's prune task and hook task share one result key, so
     BeforeHookCreation deletes the old Job and the hook is never created (silently "Synced");
     production therefore deleted the two legacy Jobs before landing the values, test needed a
     second sync; (2) psql does not interpolate `:'var'` inside `-c` — the SQL goes through
     stdin with `ON_ERROR_STOP`; (3) kubelet reduces `$$` in container args to `$`, so the DO
     block is dollar-quoted `$do$` and platform CI extracts the rendered script, applies the
     kubelet rewrite and runs it against a real Postgres. `masi` is in the per-environment infra
     values only (the chart default also feeds `schnappy-infra-data`). `sync-options:
     Delete=true` was merely Argo's default, not an unknown option.
   - 2c `platform` chart: `masi-deployment.yaml` + `masi-service.yaml` from `chess-*.yaml` with
     the `ai-masi` ExternalSecret env block, budgets, `MASI_AI_*` model envs and
     `MASI_BROWSER_ENDPOINT`; `masi-browser-deployment.yaml` + service with the hardening above,
     the browser image pinned by digest and its tag line commented `# browserless` (never
     `# masi…`, see 2e); `_helpers.tpl`; `values.yaml` `masiService:` incl. `browser:`, `ai:`,
     `budgets:`; `external-secrets.yaml` `-ai-masi`; `network-policies.yaml` masi policy (chess
     policy + internet egress on 80/443 only with the extended `except` list + Keycloak VIP +
     postgres/kafka/admin + masi-browser:3000) and the masi-browser policy; masi selector in
     admin's ingress (not site's egress — nginx proxies `/api/` to monitor only, so that would
     be dead config); `prometheus-rules.yaml` `$jobRegex` += masi (keep `masi-browser` out: its
     `/metrics` is JSON). These policy and rule edits render regardless of `masiService.enabled`
     and go live in production on merge, so the PR runs `argocd app diff` for both apps
     environments before merge and proves other services' policies unchanged except the added
     selector. `files/smoke-test.js` gains a `masi` group in `AUTH_GROUPS` with the chart's
     auto-skip when `masiService.enabled` is false. Rollback: revert; apps prune the masi
     Deployment/Service/policies (`prune: true`).
     **2c done 2026-09-17** (platform main ab958bd). Review corrections: (1) NetworkPolicies
     only ADD to the namespace default-deny, which already allows every pod, any :443, the Pi
     VIP, argocd, woodpecker, Tempo and Mimir — the browser's real bound is a
     `CiliumNetworkPolicy` DENY (host, remote-node, kube-apiserver, every pod but kube-dns,
     private/link-local/CGNAT CIDRs; inbound only masi + a scraper), to be probed from inside
     the pod in test before production enablement; (2) browserless without a `TOKEN` hands a
     CDP session to any page it renders over loopback (Envoy admin :15000 is one request away)
     — the token is REQUIRED (`masiService.browser.existingSecret`, Vault `<prefix>/masi-browser`
     property `token`, seeded by ops), the chart refuses to render the browser without it, and
     masi sends it on every connect; (3) `/active` is not a saturation signal (204 while full) —
     probes use `/pressure` via exec with the token, a saturated browser stays in the Service
     and masi must treat a 429 on connect as "retry shortly", never a source failure (PR5
     contract); (4) uid 999, emptyDirs at `/tmp`, `/home/blessuser`, `/dev/shm` (verified with
     docker diff), `TZ=Europe/Tallinn`, DNS egress scoped to kube-dns, `QUEUED=0`.
   - 2d `platform` mesh: service accounts `masi`, `masi-browser`; authorization policies
     (postgres/kafka principals, `$httpCallers` admin += masi, the dedicated masi-browser ALLOW
     policy); destination rules; `-masi-route` `PathPrefix /api/masi` in **both**
     `httproutes.yaml` and `httproutes-external.yaml` (longest-prefix match beats the `/api`
     catch-all regardless of order — chess proves it — so the failure mode is forgetting one
     file; a `helm template | yq` artifact test in platform CI asserts the route in both);
     `kafka-users.yaml` `schnappy-masi` entry (consume `user.events`, group `masi-user`) so
     enabling SCRAM later does not cut masi off.
     **2d done 2026-09-17** (platform main c3df16f, same push as 2c so no Deployment can
     reference a missing service account — a render check asserts it). `masi-browser-http`
     admits exactly masi's principal on 3000; `masi-http` has no in-mesh callers.
   - 2e `infra`: `masiService:` blocks with `tag: "<sha>"  # masi` in test (enabled,
     `tuning.auto=false`, daily budget 1 USD — the test namespace would otherwise spend real
     money from day one) and production (disabled until PR9); masi's `cd.yaml` sed pattern
     anchored `# masi$` and `deploy:promote`'s grep likewise, because the copied patterns are
     prefix matches and `# masi-browser` would be rewritten to a git hash on every push;
     sonarqube `setup.projects` += `schnappy-masi`. No `schnappy-pr-envs.yaml` entry: the
     preview ApplicationSet runs the repo's image in the monitor slot with monitor's config, so
     a masi preview would be non-functional; PR envs for masi need the preview arc (own image
     override + `/api/masi` preview route + a CI preview image step), tracked separately.
     **2e done 2026-09-17** (infra main 30691cc; platform fixes 0984c60, 51b6f33): masi and
     masi-browser run in schnappy-test (image 8b0a5cf, AI off, browser on); production block
     present but disabled. Verified: `/api/masi/actuator/health` 200 and `/api/masi/jobs` 401
     through the test gateway; `user.events` consumed in group `masi-user`; the browser refuses
     loopback requests without the token (401) and serves with it; from INSIDE the browser pod
     Mimir :9009, Tempo :4318, the Vault VIP :8200, Keycloak VIP :443, the API server, argocd,
     an in-namespace pod and 169.254.169.254 all fail while example.com on 80 and 443 and DNS
     work. Two Cilium lessons (Hubble "denylist" both times): the egress deny must exempt
     istiod (`k8s:app=istiod`, sidecar xDS/CA on 15012) and the ingress deny must not include
     the `host` entity (kubelet probes the sidecar's :15021). Both are render-check assertions.
     PR5 contract: a 429 on browser connect means "retry shortly", never a source failure.
   - 2f `ops`+`monitor`: Taskfile `SERVICES` += masi at both occurrences; `depcheck.yaml` loop
     += masi; `ops/CLAUDE.md` services, permissions (three lists), DB, registered-repos tables.
   - 2g `admin`+`ops`+`platform`+`site`: `Permission` += `JOBS`, changeset adding `JOBS` to the
     Admins group; a `setup-keycloak-roles.yml` task using `community.general.keycloak_role`
     creates `JOBS` idempotently, adds it to the `Admins` composite and to the `k6-smoke`
     service account, and **fails the play when a listed role is absent afterwards** (the SA
     role assignment silently drops unknown roles today — the recorded VIEW incident); `JOBS`
     added to the realm ConfigMap JSON in `schnappy-auth` (roles, Admins composite, seed user)
     so a fresh import matches, to the Vagrant auth task, and to `Admin.tsx` `ALL_PERMISSIONS`.
     **2f done 2026-09-17** (ops main 3d57d3f: `promote:prod` SERVICES += masi, CLAUDE.md;
     monitor #10: depcheck loop += masi). **2g done 2026-09-18**: admin #4 (`Permission.JOBS`,
     changeset 010 → Admins group only, `GroupPermissionsMigrationTest` on a real Postgres —
     verified in schnappy-test: Admins = CHAT,EMAIL,JOBS,MANAGE_USERS,METRICS,PLAY; Users =
     CHAT,METRICS), site #7 (`ALL_PERMISSIONS`), platform eb7bfbf (realm import), ops main
     8bb48de (`setup-keycloak-clients.yml` now runs on pi1, creates every app realm role, fills
     the Admins composite, assigns and PROVES k6-smoke's roles incl. JOBS, fails on a missing
     role; run: JOBS created in the live realm). Production admin gets 010 with the next
     `promote:prod`.
   Invariant (k6 smoke, the only thing that sees the route, the policy, the role and the image
   together): unauthenticated `GET /api/masi/jobs` → 401; with the `k6-smoke` token → 200 and a
   body containing masi's seed source keys (a body only masi can produce); Istio
   `istio_requests_total{response_code="403", destination_service=~".*masi.*"}` stays 0.
4. **PR3 — source survey** (`ops`, `094-masi-source-survey.md`): every candidate from the seed
   inventory plus the ~40 largest Estonian IT employers' ATS mapping, each with coverage, fetch
   method, structure stability, `robots.txt` verdict, ToS excerpt, rate expectations, chosen
   kind, cron, tier; a company-discovery section (register dump format/size/fields, ITL,
   Tehnopol, Dealroom); the `config_json` shape per kind; the fixture capture procedure. Doc only.
5. **PR4 — registry core + T1 job collectors** (`masi`): changesets 002–005, `HttpFetcher`
   (2 MB cap, manual redirects re-validated through `UrlValidator` — monitor's fetcher follows
   redirects blindly, so this is new code), `HtmlText`, `Fingerprint`, `RegistryService`,
   `CollectorRegistry`, `CollectorRunner`, `RecoverySweeper`, `SourceScheduler`, support bases,
   `TestHttpServer` `/fixtures/**`, cv.ee / tootukassa / Bolt / ATS (Teamtailor, Greenhouse,
   SmartRecruiters, Lever, Ashby) / TeamDash collectors with fixture tests (cvkeskus held, D1),
   changeset 010 + `ContactService` + Contacts controller, Jobs and Sources controllers. Invariant: a tick over fixtures produces the expected job
   rows; disabling a source cancels its future within 60 s; an overlapping "Run now" is skipped.
   **PR4 done 2026-09-18** (masi #3, #4, #5 merged, main 3b783ea; three review rounds — concurrency,
   architecture, test-quality with 45 revert checks — folded in; 198 tests). Live in
   schnappy-test the same day: cv.ee run OK/complete — 185 parsed, 181 new jobs, 85 companies,
   27 contacts from 40 detail pages; Bolt run OK/complete — 74 Estonian positions, 66 new jobs;
   the two ran concurrently. Deltas from this plan, all recorded in the code: a contacts
   registry (changeset 010) per the operator's decision; ingest is one listing per
   transaction (a bad row is a warning on the run); a retitled posting at the same URL moves
   its listing and closes the orphaned job; paced sources get a deadline floored by their
   pacing budget; the runner's lock is released only after the run and health rows are written;
   `Source` carries `@Version`; `job_listing.detail_fetched_at` (changeset 011) marks which
   listings still need their detail page, so a per-run detail cap spreads over runs instead of
   leaving the rest undetailed for ever (proven live: 40 → 80 → 120 of 185 cv.ee listings
   detailed over three runs, contacts 27 → 81); the per-source run lock is a one-permit
   Semaphore, not a ReentrantLock — run-now begins on the request thread and executes on
   another, and an owner-bound lock leaked on every run-now (masi #5); cvkeskus is not seeded (D1); the LHV row is not seeded
   (its careers block loads a TeamDash feed client-side — the survey's `window.landing` claim
   was wrong); Bolt is deterministic (list pages), no sitemap.
   **PR5 done 2026-09-18** (masi #6): `BrowserClient` (Playwright `connectOverCDP` with the
   token, `Semaphore(maxParallel)`, connect failure or saturation → `BrowserUnavailableException`
   → SKIPPED_BROWSER; `masi_browser_reachable` probed every minute via `/pressure`,
   `masi_browser_sessions_active`, `masi_browser_pages_total{source}`), `BrowserSession` (one
   context per run, `context.route("**/*")` re-validates every request through `UrlValidator`
   and aborts private/loopback/link-local/`*.internal` with the reason in the run's warnings,
   every call bounded by the run deadline, rendered DOM + XHR bodies matching
   `harvestUrlPattern`), `TeamDashLandingCollector` (`teamdashlanding:lhv`, seeded disabled).
   Deltas: the fixture pages reach the local browserless through Testcontainers'
   `exposeHostPorts` sshd forward addressed by IP (the validator refuses every `*.internal`
   name, test flags included, and this host's firewall drops bridge-to-host traffic); CI runs
   browserless as a `services:` sidecar and passes the step's IP as
   `MASI_TEST_ALLOWED_HOSTS`; `masi.browser.endpoint` comes from the environment, not
   `DynamicPropertyRegistry` (the browser tests are plain unit tests, no Spring context);
   MeetFrank is held — its WAF answers the headless browser with a CloudFront error page too —
   and Bolt and Töötukassa turned out deterministic in PR4, so no XHR-harvest source is seeded
   yet (the harvest path is covered by the JS-only fixture test). Review rounds added: the probe
   uses its own HTTP client with the token as a bearer header (the collectors' SSRF fetcher
   refuses the ClusterIP; a URL with the token must never reach a log); a watchdog kills the
   driver after the deadline (Playwright's pump clears the interrupt and its close calls have no
   timeout); Playwright routes never see redirect hops, so hops into refused hosts are observed
   and recorded and the pod policy drops them; the browserless TIMEOUT outlasts the run deadline
   by 60 s (platform 4b354ed); the merge pipeline needed the same browserless service (masi #7).
   Proven live 2026-09-18 in schnappy-test: run-now of `teamdashlanding:lhv` → OK, 1 browser page
   + 7 job pages, 7 new LHV jobs; the guard aborted a Google Tag Manager request the cluster
   resolver sinkholes to an internal address (a warning on the run, not a failure).
6. **PR5 — headless browser collectors** (`masi`): Playwright client, `BrowserCollector`,
   `browser.*` properties, the browserless image as a Woodpecker `services:` sidecar in
   `ci.yaml` (same digest as the chart value, recorded beside both) and as the `!ci`
   Testcontainers singleton locally, exposing `masi.browser.endpoint` through
   `DynamicPropertyRegistry`; the test is never `assumeTrue`-gated; fixture pages are served to
   the container via `Testcontainers.exposeHostPorts` / the CI step's hostname; env-gated live
   smoke against the **deployed** test-namespace `masi-browser` (the only test that sees an
   image/protocol mismatch and the driver-extraction path); MeetFrank / Bolt / Töötukassa GraphQL
   capture. Invariant: a JS-only fixture yields listings and the harvested XHR JSON; the masi
   image contains no browser.
   **PR6 delta (masi #8, 2026-09-18):** three COMPANIES-scope collectors seeded disabled —
   `ariregister` (the `yldandmed.json.zip` streamed through the zip and the JSON array under a
   512 MB byte budget via `HttpFetcher.stream`; registered companies with a current EMTAK 62/63
   activity; name, code, WWW, main code, city, size band from the newest three reports; EMAIL,
   MOB and TEL dropped; `complete` only when the array closed and ≥ `minRows` were kept), `itl`
   and `tehnopol` (jsoup; Tehnopol modal text never read). `CompanyMatcher` did not become a
   class: the matching order lives in `CompanyService.resolve` (code → name → domain → alias;
   a raw with a code never merges into a row with another code). The register is the one
   source that renames a row (old name → alias; a rename onto a code-less board stub merges
   the stub in — jobs, contacts, aliases move; a name another registered company holds gives
   the row a code-suffixed key). `register_seen_at` (changeset 013) drives dormancy: absent
   from two consecutive complete register imports → DORMANT, and only the register revives.
   `AtsDetector` turns an apply/careers URL on greenhouse, lever, smartrecruiters, teamtailor
   or ashby into a disabled `ats:<slug>` source row (a conflict-free native insert) and records
   the vendor for teamdash/workable/bamboohr. Companies API: `q`, `status`, `hiring`, `POST`
   for manual entries (shape-only URL check, DNS at fetch time), `careersUrl` on PATCH. Two
   operator rules landed in the same PR and are enforced from now on: no generic exceptions
   (`CollectException`, `SourceConfigException`, `InvalidUrlException`, `BadRequestException`,
   …) and braces on every `if`/`else`/`for`/`while` body (`CodeStyleTest`).
   **PR6 done 2026-09-18** (masi #8 merged, main 2d2596f, 244 tests; three review rounds and
   the revert-check audit). Proven live in schnappy-test by run-now: `itl` OK (114 new of 128),
   `tehnopol` OK (252 new), `ariregister` OK and complete — the 230 MB dump streamed and parsed
   in about two minutes against the 840 s deadline, 27,583 new companies, registry 458 →
   28,035 rows. Cross-source identity: Nortal AS, an ITL row without a code, gained registry
   code 10391131, EMTAK 62101, size band 250+ and Tallinn from the register by name while
   keeping ITL's website and tags; Pipedrive OÜ 11958539 sits at 250+. No company went
   dormant on the first import, as designed (dormancy needs two consecutive absences).
7. **PR6 — company registry** (`masi`): `CompanyService` + `CompanyMatcher`, stubs from
   listings, `ariregister/` streamed dump import, `itl/`, `tehnopol/`, ATS rows auto-created,
   Companies controller. Invariant: one employer across boards resolves to one company; the
   register import is idempotent.
   **PR7 delta (masi #9, site #8, 2026-09-18):** the changeset is `014` (006–009 were never
   created; a number is immutable once it has run). `json-schema-validator` 3.0.7 is built on
   Jackson 3, so the validator shares the Boot mapper line after all; the openhtmltopdf group is
   `io.github.openhtmltopdf` with packages still `com.openhtmltopdf`. The schema is the
   no-personal-data rule (`additionalProperties: false` on every object, tested on every
   nesting level), with three fields the tuner will need beyond the plan: per-achievement
   `autonomy` (the verb-ladder gate compares bullet for bullet), `person.availability` (the
   letter's one line), `experience[].collapsed` (a one-line role: full completeness share, no
   bullets). Limits: 256 000 characters, `maxItems` on every array, YAML aliases refused by
   the parser itself (Jackson YAML does not expand them), two renders at once with a 30 s queue
   and a 503. The renderer refuses every external resource; a revert check with a real PNG on
   a `file:` URL proves it. Bundled font: Liberation Sans (OFL), bold face asserted embedded;
   PDFBox's font cache is pointed at the tmp emptyDir. Versions are numbered under a per-user
   advisory lock; activation clears the persistence context after the bulk deactivate. Errors
   are JSON pointers (`/person`, `$` for the root). The site page is `/masi/cv` with the
   nav link "Jobs"; the site's `prettier --check .` had been walking the Sonar step's
   `.scannerwork` (green or red depending on which step finished first) — ignored for good.
   The merge pipeline of masi #9 then failed in the scheduler tests: disabling a source by
   load-and-save while a run every second bumps the row version loses the optimistic lock, and
   `PATCH /sources/{id}` had the same race (a 500 for the operator) — masi #10 added
   `SourceAdminService` (three attempts on a fresh copy, then 409).
   **PR7 done 2026-09-18** (masi main 43740ba, 268 tests; site main e72cef6, 378 tests).
   Proven live in schnappy-test with the fictitious sample: `POST /cv/versions` → version 1
   inactive, a `photo` field → 400 with its path, activate → active v1, completeness 100,
   `preview.pdf` → 26 962 bytes of real text (name, context line, bullets) from the bundled
   font; nothing of the CV in the pod log; the served site bundle carries `/masi/cv`.
8. **PR7 — CV master + renderer** (`masi`+`site`): changeset 006, `cv-schema.json`
   (evidence-bank shape), `CvSchemaValidator`, `CvMasterService` with `completeness()`,
   `PdfRenderer` + templates + bundled font, Cv controller, `MasiCv.tsx`, route and nav,
   `Admin.tsx` permission list. A fictitious sample CV for tests. Invariant: valid YAML →
   activatable version + previewable PDF; invalid YAML rejected with the schema path.
9. **PR8 — tuning pipeline + cost ledger, budgets and alerts** (`masi`+`platform`): changesets
   007–008, `AnthropicGateway` with reserve-then-settle, `Pricing`, cost and health metrics,
   `TuningPrompt`, `TunedCvOutput`, posting analysis, `ClaimsChecker`, `CvLint`, `TuningService`,
   `TuningScheduler`, Packages controller with the state machine and user scoping; the
   PrometheusRule entries with runbook URLs and their `promtool` unit files. Invariant: no
   package reaches `PREPARED` without a clean claims report; no HTTP request leaves the gateway
   once a cap is reached; a second `JOBS` user cannot read the first user's packages.
   **PR8a delta (masi #11, platform main aaede0d, 2026-09-18):** the gateway and the ledger
   shipped first, the pipeline second (8b), so the alerts landed with the metrics they read.
   Changeset is `015` (`llm_call`, statuses `PENDING/OK/ERROR/LOST`). `AnthropicGateway` is
   the only class importing `com.anthropic` (ArchUnit): SDK `maxRetries(0)` and
   `logLevel(OFF)` (its body logger bypasses SLF4J, so `ANTHROPIC_LOG=debug` in a pod env would
   otherwise print the CV), retries only on 429/529/5xx with 1 s-doubling jitter capped at 30 s
   after the jitter, a 400 costs nothing, a wire failure or an unreadable 200 keeps the
   estimate (billing unknown), one `deadlineMillis` bounds the permit wait, every attempt and
   every backoff; a call inside a transaction is refused (`LlmTransactionContextException`).
   Reserve-then-settle under `pg_advisory_xact_lock(hashtext('masi-budget'))` in `REQUIRES_NEW`:
   day, month, purpose share (EXTRACT 0.30, ENRICH 0.20), per-run 0.25 USD and per-package
   1.50 USD caps, all against `coalesce(cost, estimate)`; the estimate assumes the full
   `max_tokens` out, so the in-flight semaphore (2) and the ledger together admit exactly one
   call into one remaining slot (forced in the test with a gated fixture). The budget gauges
   `masi_llm_budget_used_ratio{period}` read the ledger on scrape. A PENDING row older than
   every attempt at the full timeout plus the backoffs plus two minutes is marked LOST by the
   sweeper unless this process owns it (`liveCalls()` is process-local: replicas 1); a LOST
   row that then settles becomes OK/ERROR with `masi_llm_ledger_failures_total{what=
   lost_then_settled}`. A missing cache price falls back to the documented multiplier
   (read 0.1×, 1 h write 2×, 5 m write 1.25× input), never to free; an unpriced model refuses
   at startup. Platform: group `{{ $ns }}-masi` with MasiBudgetDay/Month, MasiBudgetGaugeAbsent,
   MasiCostRate, MasiLedgerFailures, MasiModelMismatch, MasiSourceDisabledAuto, MasiSourceStale
   (`time() - masi_source_last_success_timestamp_seconds > on(source,job,namespace)
   (3 * masi_source_interval_seconds)` — the two gauges are 8b's), MasiBrowserUnreachable,
   MasiBrowserSaturated; `promtool test rules` unit files run in platform CI (helm template →
   awk → `build/rules/`, chmod for the `nobody` uid of the prometheus image). Lessons: any
   `assertThat(list).hasSize(n)` over recorded requests prints the CV into the report on
   failure — assert on `.size()`; the SDK's required fields are read lazily and throw its own
   types, so usage/model/stop are read inside one guard; `absent()` alerts carry the equality
   matchers as labels in the unit expectation.
   **PR8a done 2026-09-18** (masi main adf5265, 286 tests; live in schnappy-test: health UP,
   `masi_llm_budget_used_ratio{day,month}` = 0, AI disabled — no key in the test namespace).
   **PR8b delta (masi #12, 2026-09-18):** changeset `016` (`application_package` with a
   `row_version`, `package_artifact`). The state machine is as planned plus `SKIPPED` for a job
   that closed while the package waited (no call) and `FAILED` for the per-package cap (a
   terminal state, not an endless deferral). The claim NEW→PREPARING is one conditional update
   stamped with `preparing_since`; every terminal write re-checks the stamp inside its
   transaction and drops its result when another process took the row (counter
   `masi_tuning_ownership_lost_total`); the interrupt flag is parked around those writes, since
   an interrupted JDBC read on a virtual thread fails at once. Recovery is two conditional bulk
   updates after `preparingLimit()` = 4 × the request timeout + the analysis deadline + 5 min
   (about 47 min at the defaults), not 15 min. The lane is a single fair permit on virtual
   threads, a `SmartLifecycle` that stops first, admits nothing once draining, waits
   `tuning.drain` (25 s; the pod's grace is 60 s) and then interrupts — an interrupted call
   defers the package with its attempt given back. A spent day pauses the lane to the next UTC
   day, a spent month to the next month; a disabled gateway makes the tick a no-op; a spent
   EXTRACT share skips the analysis and tunes anyway. The pipeline: analysis (Haiku, stored on
   the job with a targeted update — `Job` is `@DynamicUpdate` because the ingest writes the same
   row), tune (Opus, rules + stored YAML cached, posting volatile, the named contact as
   addressee unless `do_not_contact`), `ClaimsChecker`, and only then lint, render, the two-page
   gate (a violation like any other), artifacts. One retry with the violations; a clean output
   with more than four actionable lint warnings buys one retry too, and the clean output stands
   if the retry is worse or fails. `ClaimsChecker` beyond the plan: compound metrics part by
   part, the letter's numbers (master or posting, never a posting figure in a first-person
   sentence), the autonomy ladder ranks the highest ownership word anywhere in the bullet
   except words the achievement itself carries, a collapsed role may carry no bullets, dates,
   tech, skills, certification years, availability and language levels count as master
   figures, the letter names the company by its first word and the role by the content words
   of either half of a bilingual title. `GET /packages/retune` is the dry run behind "Re-tune N
   jobs (~$X)"; `POST /packages/retune` takes no body (the active version). The two source
   gauges the platform alert reads: the enabling time stands in for the last success until the
   first one (a run no longer moves `updated_at`), FAILING sources carry none, the interval is
   the shortest gap over the next eight fires. `Json` moved to `io.schnappy.masi.support`.
   Revert table corrections: "shifted date" is not a row (dates are never in the output; the
   renderer copies them), "posting title as current title" is tested as the target line and as
   a role title, and a roman-numeral "I" in a title reads as the first person to the letter's
   numbers gate (one retry, never a false pass).
   **PR8b done 2026-09-18** (masi #12 merged as 6479f9e, 347 tests; deps bumped in #13). Live in
   schnappy-test: changeset 016 applied, health UP, `GET /packages` → 200 `[]`,
   `GET /packages/retune` → 254 open jobs at a 105 USD reservation estimate, a foreign id → 404,
   `POST /jobs/{id}/packages` → 409 "AI is disabled" (no key in the test namespace), no token →
   401; the staleness gauges are absent because every source in test is disabled (by design).
10. **PR9 — UI** (`site`+`infra`): Dashboard (with cost tile), Jobs, JobDetail, Companies,
    CompanyDetail (with contacts), Contacts, Sources with vitest tests; then production `masiService.enabled: true` via
    `task promote:prod`. Invariant: a vitest render at `/masi/jobs` with `JOBS` shows the page
    and without it redirects; the nav link is absent without `JOBS`; the JobDetail PDF link
    carries the artifact URL and responds `application/pdf` in the test namespace.
    **PR9 delta (masi #14, site #9 + #10, 2026-09-18):** the UI needed three backend additions
    (masi #14): `GET /jobs` takes `q` (a literal: `%` and `_` escaped), `company`, `source` (a
    listing's source key), `remote`, `since`, `packageStatus` (NONE for jobs without one) and
    `sort` (`firstSeenAt|lastSeenAt|title|closedAt,asc|desc`); every row and the detail carry the
    caller's NEWEST package on the job, and the filter and the dashboard funnel mean the same
    newest package (a re-tuned job sits in one state); `GET /packages?job=` (with `status`) lists a
    job's packages with their artifacts; `GET /dashboard` is the overview in one call (open/new/
    closed over a rolling 7 × 24 h — not a calendar week, a reopened job is not "closed" —,
    companies hiring, the caller's funnel, LLM spend vs the UTC day/month budgets and the AI
    switch, CV completeness, sources with health, the tuning pause); APPLIED from APPLIED updates
    the notes and the employer's response instead of a 409 (the panel's "Save response"); the
    run-now 409 carries an error message; `TuningScheduler.pause(Instant)`. The site pages live
    under `src/pages/masi/` (MasiCv moved in) behind a shared tab bar; the review queue offers the
    backlog re-tune only behind `GET /packages/retune`'s estimate; the job page polls a queued
    package (10 s, then 60 s, an hour at most) and shows "Prepare package" only when no package
    exists for the active CV version; files open through a download link (no popup); the panel
    hides every transition the backend would refuse. Site #10 makes SonarJS's rule set part of
    `npm run lint` — the gate (0 new issues) had failed three pushes on rules eslint never ran —
    and fixes the sixteen findings in older code, two of them real: message handlers that never
    checked the sender's origin, and two super-linear regexes. Deferred to PR10 by the plan's own
    scope: the cost tile's per-purpose and per-package figures. Production enablement
    (`masiService.enabled: true`) is NOT done: masi in production would run without an Anthropic
    key and with every source disabled; it is the operator's call once the key is seeded.
    **PR9 done 2026-09-18** (masi main facc87b, site main 482037a; site #10 — Sonar's rule set as local lint — merged 2026-09-19, site main 1bc0896 served at test.pmon.dev). Live in schnappy-test: the
    served bundle carries `/masi`, `/masi/jobs|packages|companies|contacts|sources|cv` and the
    lazy page chunks (the dashboard chunk answers 200 with its cost tile); `GET /dashboard` with a
    JOBS token → 254 open jobs, 86 companies hiring, CV v1 at 100 %, 27 sources, AI disabled;
    `GET /jobs?q=java&packageStatus=NONE&sort=title,asc` → 3 rows in title order;
    `since=yesterday` → 400.
11. **PR10 — stats, reports and cost dashboards** (`masi`+`site`+`platform`): changesets 017–018,
    `StatsService`, `ReportService`, `ReportScheduler`, Stats/Reports controllers,
    `MasiReports.tsx`, cost section in the monthly report, Grafana panels. Invariant: every
    number on the Reports page is reproducible from `first_seen_at`/`applied_at`, `lifecycle_event`
    and `llm_call`, and stats for a closed period are identical when recomputed after more ticks.

    **PR10 delta (masi #16, site #12, platform, 2026-09-19):** the plan said "never from
    `last_seen_at`", which was not enough — three existing writers rewrite what a period reads.
    A reopen clears `closed_at` on the job and the listing (so "closed this week" shrank on
    recompute), a regenerate rewrites `application_package.cost_usd` (so the per-package average
    moved), and the nightly sweeper deletes `source_run` rows (so an old window lost its runs).
    Changeset 018 adds an append-only `lifecycle_event` (CLOSED/REOPENED per job and listing,
    written where the close happens) and every close count and listing lifetime is read from it;
    the per-package cost comes from `llm_call.package_id`, and the run retention is the property
    `masi.lifecycle.run-retention` (90 d) that `/stats` is documented against. `source_run.
    llm_cost_usd` had no writer at all, so per-source spend now comes from `llm_call.source_id`;
    `job.seniority` and `job.tech_tags` had no writer either, so `storeRequirements` fills them
    from the posting analysis in the same update. `GET /reports/generate` returns 201 for a
    period it wrote and 200 for one already stored (the plan's 202 predates the synchronous,
    idempotent generator). `ReportScheduler` catches up every period between the newest stored
    report and the last complete one, on startup and on each cron, because a pod that is down at
    Monday 06:00 would otherwise lose that week for good.

    **PR10 done 2026-09-20** (masi #16 main f02ae7c, site #12/#13 main 8889330, platform fe83b34).
    Two review rounds and a test audit with revert checks changed the design more than the plan
    did: a job already CLOSED was being closed a second time when its last listing moved away
    (a double count on an append-only log; the close is now guarded on the job's own state); a
    restart minutes after midnight froze the week before the night's runs — the catch-up now
    waits the six hours the 06:00 crons encode and runs on the scheduler, not on the startup
    thread; changeset 019 seeds `lifecycle_event` from the closes still on the rows and backfills
    `seniority`/`tech_tags`; per-source LLM cost was dropped because nothing attributes a call to
    a source yet (it returns with the first collector that spends). Live in schnappy-test:
    changesets 017–019 EXECUTED, the restart catch-up wrote the weekly report for 7–13 Sep and the
    monthly for August by itself, `GET /stats?from=2026-09-07&to=2026-09-20` → 254 new jobs, 266
    new listings, Bolt 80 / Kühne + Nagel 9 on top, six sources with runs; a second
    `POST /reports/generate` → 200 with the same id, an open period → 400, no token → 401; the
    dashboard carries `monthByPurpose` and `averagePackageCostMonth`; Grafana dashboard uid
    `masi` loaded; `MasiReportsStale` rule rendered with its promtool test. Left open by design:
    masi's Sonar gate (red since 2026-09-18, 273 issues, enforced by nothing) is the next PR.
12. **PR11 — dedupe hardening + lifecycle** (`masi`): `pg_trgm` near-duplicate hint (never
    auto-merged), detail 404/expired → close, `expires_at`, auto-disable re-enable, manual import
    UX, artifact retention job. Invariant: a listing vanishing from one board closes its job
    only when every other listing is gone too.

Later: match scoring (`SCORE`), company enrichment (`ENRICH`), weekly-report notification
(Kafka → chat/email), T2 collectors, Admin-API cost reconciliation, PR preview envs for masi.

### Verification

The test JVM pins `user.timezone=UTC` (the pod's zone; a developer machine on Europe/Tallinn
would hide a `systemDefault()` leak). The copied `allowLoopback` test flag is narrowed: it allows
**loopback and the `masi.test.allowed-hosts` list only**; site-local, link-local and
`169.254.169.254` are refused regardless of the flag — otherwise every SSRF assertion in a
Spring test passes with the guard deleted, because monitor's flag disables the whole validator.

Revert checks that must each turn a named test red:

| Mechanism | Fixture | Revert |
|---|---|---|
| Fingerprint dedupe | source A `Wise Europe OÜ` / `Senior Java Developer (m/f/d)`, source B `wise europe` / `Senior Java Developer` → one job; `Java Developer` at the same company stays a second job | `norm()` made identity |
| Company dedupe | two rows sharing `registry_code` with **different** names → one company | registry-code lookup skipped (the `name_norm` fallback must not mask it) |
| Run row and retry | a throwing collector → run `ERROR` with `finished_at`, `consecutive_failures=1`, and a second `run(source)` executes the collector again | `catch Throwable` removed |
| Sibling isolation | a hanging collector does not delay a sibling's run in the same tick | collector body moved onto the scheduler thread |
| Overlap | a latch holds run A inside `collect()`, run B is requested → B skipped, one `source_run` | per-source `tryLock` removed |
| Cancel on disable | cron `* * * * * *` with a counting fake runner; disable, `refresh()`, await 2 s → count unchanged, `future.isCancelled()` | `future.cancel()` removed |
| Miss counting | seen, missed, missed, seen, missed, missed → still `OPEN` | `miss_count` reset on sight removed |
| Incomplete runs | a `complete=false` run leaves every `miss_count` untouched; a complete run that omits the listing increments | `complete` no longer consulted |
| SSRF on redirect | fixture `/redir` → `Location: http://10.255.255.1/` and → `http://169.254.169.254/latest/meta-data`; fetch throws naming the address, the run ends `ERROR` | `validateHostAtRequestTime` removed from the redirect loop (with the narrowed flag in force) |
| Browser guard | fixture page with `<img src="http://169.254.169.254/…">` and `fetch('http://10.0.0.1/x')` → both aborts in the run's warnings, list still harvested | `context.route` handler removed |
| Browser isolation | endpoint down → source `SKIPPED_BROWSER`, `consecutive_failures` unchanged, sibling deterministic source runs | connect failure counted as failure |
| Registry agreement | seeded keys == bean keys, package part == package name | a seed row added without a bean (and vice versa) |
| Fabrication guard | one row per rule: added employer, removed role, shifted date, skill not in master, bullet Jaccard < 0.5, number absent from master, posting number claimed as the candidate's, master metric dropped from a selected bullet, "led" for "participated" (verb ladder), Estonian output for an English master, posting title as current title, letter not naming the company or the role, letter over 250 words, salary figure, model-supplied certification absent from the PDF text; a rephrased bullet with the same verb rank passes | `ClaimsChecker` returns empty; Jaccard threshold set to 0, the verb list emptied, and the removal check dropped must each go red |
| Quality lint | duty-only bullet flagged; results-first bullet with a metric passes; a term repeated 6× flagged; a stop-list word flagged | `CvLint` returns empty |
| No bodies in logs | one gateway call under a captured appender; the output contains no substring of the master YAML | request body logged |
| Master completeness | role without a metric-bearing achievement lowers the score and names the role; an empty `positioning` block lowers it | `completeness()` returns 100 |
| PII fields | a master YAML with `photo` or `birth_date` is rejected by the schema | `additionalProperties` allowed |
| Package idempotency | two concurrent `POST /jobs/{id}/packages` released by a latch → exactly one row | unique `(job_id, cv_version_id)` dropped |
| Budget | ledger seeded to the cap → the fake transport saw zero requests and the outcome is `SKIPPED_BUDGET`; extraction at its share → tuning still permitted; two concurrent calls under one remaining slot → one request | budget transaction skipped |
| Gateway request shape | `AnthropicGatewayTest` points the SDK at `TestHttpServer` via `baseUrl`; the server captures request bodies and replays **recorded** responses from one real call per shape (`end_turn` with cache-creation tokens, second call with cache-read tokens, `refusal`, `max_tokens`, 429 with `retry-after`, 529, 400); asserts exactly two `cache_control` blocks at the rules and CV positions, `output_config` and effort present, no `thinking`, the CV block byte-equal to the stored YAML, 429/529 retried, 400 and refusal not, a ledger row written even when the call fails | any of those |
| Recovery | a `PREPARING` package older than 15 min returns to `NEW`; a run without `finished_at` becomes `INTERRUPTED`; a `PENDING` call becomes `LOST` and still counts | sweeper disabled |
| User scoping | a second `JOBS` user gets 404 on the first user's package and artifact | scope filter removed |
| Permission coverage | ArchUnit: every controller handler except health carries `@RequirePermission` | annotation removed from one method |
| Font bundling / PDF | PDFBox extraction with `setSortByPosition(true)` equals extraction in stream order (both must agree, or the layout is not single-column) and contains the sample name and an Estonian diacritic in order; ≤ 2 pages, gated per package at render time; the OFL font name is among the embedded fonts | font resource deleted; a two-column test template must also go red |
| Tuning quality (judged) | an eval set of N fictitious postings × the sample CV with hand-written expected must-have mappings, plus adversarial `TunedCvOutput` fixtures each carrying exactly one fabrication; precision reported per release | not a revert check — a judge without a labelled set is an opinion |
| Reports | rows at Monday 00:30 and Sunday 23:30 Europe/Tallinn and a week spanning 2026-10-25 (DST) → exact weekly counts; stats at T1 equal stats at T2 after more ticks | period boundary shifted by an hour; a stat computed from `last_seen_at` |
| Review flow | `POST /packages` → tick → `PREPARED` with artifacts → `REVIEWED` → `APPLIED` (`applied_at`, gone from the `PREPARED` list) → regenerate 409; blacklisted company → no package; `tuning.auto=false` → nothing created; new CV version → only jobs first seen after activation | any transition guard removed |
| Route in both files | `helm template \| yq` finds `-masi-route` with `PathPrefix /api/masi` in both rendered route files | one file's route removed |
| Alert rules | `promtool test rules` unit file per masi alert | expression changed |

End-to-end in the test namespace after PR9/PR10: enable cv.ee → one tick → jobs and company
stubs appear → a package prepares → job detail shows "0 violations", the PDF downloads, the
letter copies → Mark applied → the row leaves the queue with `applied_at` set → Reports shows
the funnel. Cache proof (env-gated live smoke, two assertions): the first tuning call reports
`cache_creation_input_tokens > 0` (the prefix qualifies for the model's minimum cacheable
length) and the second `cache_read_input_tokens > 0`. Cost proof: the dashboard's "LLM cost
today" equals `sum(llm_call.cost_usd)`.

## Risks

- **ToS / robots**: the survey gates every source; honest UA; cron ≥ hourly; Töötukassa's
  Crawl-delay honoured; forbidden sources stay disabled with the ToS excerpt in `terms_note`.
- **Anti-bot / WAF**: the browser handles JS rendering, not bot walls; a source that blocks the
  browser too stays disabled with the evidence recorded. An unsandboxed Chromium renders
  untrusted pages inside the mesh: the pod boundary, the egress policy with the extended
  `except` list, no service-account token and no mounted secrets are the controls.
- **Scraper drift**: fixtures pin today's markup; health metrics, auto-disable, `MasiSourceStale`
  and the run ledger make drift visible within one tick; the live smoke per T1 source catches
  fields that go null.
- **LLM cost**: reserve-then-settle budgets, key isolation with a console spend limit,
  per-run extraction cap, prompt caching (no dates or run ids in the system prompt, the CV sent
  as stored text verbatim, constant effort), Haiku for extraction, one package per job per CV
  version, no backlog auto-tune on CV activation, `tuning.auto=false` as the off switch.
- **Cost blind spots**: a wrong pricing table makes the ledger wrong; the model-id mismatch
  counter and the optional Admin-API reconciliation catch it; alerts fire on rate, not only totals.
- **PII**: the CV lives only in the DB and its backups; fixtures are scrubbed (contact persons
  replaced by synthetic ones); the gateway logs token counts only; the sample CV is fictitious.
  Recruiter contacts ARE stored (operator decision 2026-09-18) — only what the posting or the
  public register publishes, no enrichment, per-row delete, `do_not_contact` honoured by every
  letter, and the register's e-mails flagged `GENERIC` because most are personal addresses.
- **Register dump size**: stream the zip, keep only EMTAK 62/63 active rows, run weekly.
- **Single replica**: the scheduler map and the per-source locks are in-memory; `replicas: 1`
  and `maxSurge: 0` are constraints until a DB lease replaces them.
- **`JOBS` role**: admin PR + role task that fails loudly + realm ConfigMap; the site hides the
  nav link without it, so a missing role is visible, not silent.

To verify while implementing: openhtmltopdf 1.1.86 on Java 25; the Anthropic Java SDK 2.63.0
builder for `outputConfig(Class)` together with effort on the beta path (2.15.0 has
`BetaOutputConfig.Effort`, `BetaThinkingConfigAdaptive`, `BetaCacheControlEphemeral` on the
structured path); the browserless image digest, its `TOKEN` requirement and the Playwright
protocol match; whether the CNPG webhook accepts a `postInitSQL` edit; Töötukassa open-data
format; cv.ee ToS; TeamDash/Teamtailor/BambooHR feed conventions.

## Status

IN PROGRESS — approved 2026-09-16; PR0, PR1 (masi #1), PR2a (ops #43) and PR2b (platform #31–#33,
infra #28/main d2d10f4), PR2c + PR2d (platform main ab958bd, c3df16f; production PostSync
green with the masi smoke group skipped) and PR2e (infra main 30691cc, verified in test incl.
the browser's SSRF bound from inside the pod) done on 2026-09-17; PR2f and PR2g done 2026-09-18
(JOBS role live, Admins group carries it in test); PR3 source survey and PR4 registry core DONE
2026-09-18 (247 open jobs in schnappy-test after the first cv.ee + Bolt runs); PR3 survey
(`094-masi-source-survey.md`: five operator decisions D1–D5, twelve seed corrections — notably
Töötukassa and Bolt are deterministic, cvkeskus.ee is held on its 10 000 €/request clause —
config shapes, fixture procedure, three verbatim survey reports); PR5–PR7 and PR8a (gateway,
ledger, alerts), PR8b (tuning pipeline, masi #12) and PR9 (masi #14 + site #9/#10, the UI) done
2026-09-18 and proven live in schnappy-test; production stays disabled until the Anthropic key
is seeded; next PR10 (stats, reports, cost dashboards).
Process since 2026-09-17: platform, infra and ops changes go straight to main (no PRs); the app
repos keep PRs with PR-only CI.
