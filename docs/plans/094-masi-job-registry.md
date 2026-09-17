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
Company detail shows open/closed listings history and hiring velocity. Blacklisted companies
never get packages.

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
byte-stable; `POST /reports/generate` (202) backfills. The dashboard endpoint returns open jobs,
new/closed this week, companies hiring now, packages awaiting review, applied/skipped, per-source
health and last run, LLM cost today/month, CV completeness. Weekly-report delivery as a
notification is a later PR.

### API (`/api/masi/…`, all `@RequirePermission(JOBS)`, package and CV reads scoped by `user_uuid`)

| Endpoint | Purpose |
|---|---|
| `GET /jobs` (status, source, company, q, remote, since, packageStatus, paging, sort), `GET /jobs/{id}`, `PATCH /jobs/{id}`, `POST /jobs/manual` | registry |
| `POST /jobs/{id}/packages` (202), `GET /packages?status`, `GET /packages/{id}`, `GET /packages/{id}/artifacts/{kind}`, `POST /packages/{id}/review` {REVIEWED/APPLIED/SKIPPED, notes, response}, `POST /packages/{id}/regenerate` (202), `POST /packages/retune` {cvVersion} (202, explicit backlog re-tune with a cost estimate) | review queue; transitions validated (APPLIED from NEW → 409, regenerate on APPLIED → 409) |
| `GET /companies` (q, hiring, status, paging), `GET /companies/{id}`, `PATCH /companies/{id}`, `POST /companies` | company registry |
| `GET /sources`, `PATCH /sources/{id}` {cron, enabled, configJson}, `POST /sources/{id}/run` (202; 409 while running), `GET /sources/{id}/runs` | sources admin |
| `GET /cv`, `GET /cv/versions`, `POST /cv/versions`, `POST /cv/versions/{v}/activate`, `POST /cv/validate`, `GET /cv/versions/{v}/preview.pdf`, `GET /cv/completeness` | CV master |
| `GET /dashboard`, `GET /stats?from&to`, `GET /reports?kind`, `GET /reports/{id}`, `POST /reports/generate` (202) | overview and reports |

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
   - 2d `platform` mesh: service accounts `masi`, `masi-browser`; authorization policies
     (postgres/kafka principals, `$httpCallers` admin += masi, the dedicated masi-browser ALLOW
     policy); destination rules; `-masi-route` `PathPrefix /api/masi` in **both**
     `httproutes.yaml` and `httproutes-external.yaml` (longest-prefix match beats the `/api`
     catch-all regardless of order — chess proves it — so the failure mode is forgetting one
     file; a `helm template | yq` artifact test in platform CI asserts the route in both);
     `kafka-users.yaml` `schnappy-masi` entry (consume `user.events`, group `masi-user`) so
     enabling SCRAM later does not cut masi off.
   - 2e `infra`: `masiService:` blocks with `tag: "<sha>"  # masi` in test (enabled,
     `tuning.auto=false`, daily budget 1 USD — the test namespace would otherwise spend real
     money from day one) and production (disabled until PR9); masi's `cd.yaml` sed pattern
     anchored `# masi$` and `deploy:promote`'s grep likewise, because the copied patterns are
     prefix matches and `# masi-browser` would be rewritten to a git hash on every push;
     sonarqube `setup.projects` += `schnappy-masi`. No `schnappy-pr-envs.yaml` entry: the
     preview ApplicationSet runs the repo's image in the monitor slot with monitor's config, so
     a masi preview would be non-functional; PR envs for masi need the preview arc (own image
     override + `/api/masi` preview route + a CI preview image step), tracked separately.
   - 2f `ops`+`monitor`: Taskfile `SERVICES` += masi at both occurrences; `depcheck.yaml` loop
     += masi; `ops/CLAUDE.md` services, permissions (three lists), DB, registered-repos tables.
   - 2g `admin`+`ops`+`platform`+`site`: `Permission` += `JOBS`, changeset adding `JOBS` to the
     Admins group; a `setup-keycloak-roles.yml` task using `community.general.keycloak_role`
     creates `JOBS` idempotently, adds it to the `Admins` composite and to the `k6-smoke`
     service account, and **fails the play when a listed role is absent afterwards** (the SA
     role assignment silently drops unknown roles today — the recorded VIEW incident); `JOBS`
     added to the realm ConfigMap JSON in `schnappy-auth` (roles, Admins composite, seed user)
     so a fresh import matches, to the Vagrant auth task, and to `Admin.tsx` `ALL_PERMISSIONS`.
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
   `TestHttpServer` `/fixtures/**`, cv.ee / cvkeskus / tootukassa / ATS collectors with fixture
   tests, Jobs and Sources controllers. Invariant: a tick over fixtures produces the expected job
   rows; disabling a source cancels its future within 60 s; an overlapping "Run now" is skipped.
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
7. **PR6 — company registry** (`masi`): `CompanyService` + `CompanyMatcher`, stubs from
   listings, `ariregister/` streamed dump import, `itl/`, `tehnopol/`, ATS rows auto-created,
   Companies controller. Invariant: one employer across boards resolves to one company; the
   register import is idempotent.
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
10. **PR9 — UI** (`site`+`infra`): Dashboard (with cost tile), Jobs, JobDetail, Companies,
    CompanyDetail, Sources with vitest tests; then production `masiService.enabled: true` via
    `task promote:prod`. Invariant: a vitest render at `/masi/jobs` with `JOBS` shows the page
    and without it redirects; the nav link is absent without `JOBS`; the JobDetail PDF link
    carries the artifact URL and responds `application/pdf` in the test namespace.
11. **PR10 — stats, reports and cost dashboards** (`masi`+`site`+`platform`): changeset 009,
    `StatsService`, `ReportService`, `ReportScheduler`, Dashboard/Stats/Reports controllers,
    `MasiReports.tsx`, cost section in the monthly report, Grafana panels. Invariant: every
    number on the Reports page is reproducible from `first_seen_at`/`closed_at`/`applied_at`
    and `llm_call`, and stats for a closed period are identical when recomputed after more ticks.
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
- **PII**: the CV lives only in the DB and its backups; fixtures are scrubbed; the gateway logs
  token counts only; the sample CV is fictitious; recruiter contact persons are never stored
  as fields, enriched or displayed — a name or email inside `description_raw` stays there.
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

DRAFT 2026-09-16 — approved by the operator in session; review findings of ops PR #40 folded in;
PR1 not started.
