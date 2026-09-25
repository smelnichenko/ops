# 097 — masi: company figures — employees, revenue, profit, taxes — as charts

## Decision

The company page shows how the company is doing, as charts: **employees**, **revenue** and **profit** by year from its
annual reports, and **turnover**, **employees** and **taxes paid** by quarter from the Tax and Customs Board. The figures
come from two official open datasets masi reads on a schedule, never from scraping a company's site or a commercial
aggregator. Nothing about a person is read or kept: these are legal persons' filed figures.

Operator, 2026-09-25: *"also would be nice to have number of employees and turnover/etc financial figures as charts"*
(with *"add address to the company with a link to google map"*, masi #61 / site #29).

## Why

- Whether an employer is growing, shrinking or profitable is what the operator asks before applying; today the page
  shows a size band from the register's last three employee counts and nothing else.
- Both sources are official, free and licensed for reuse: no ToS question, no scraping, no key.

## Sources (verified 2026-09-25)

| Source | What | Granularity | Update | Licence | Access |
|---|---|---|---|---|---|
| e-Business Register (RIK) open data, "key indicators" files `4.<year>_aruannete_elemendid_kuni_<date>.zip` | cash, current/non-current assets, assets, current/non-current liabilities, equity, **revenue**, total revenue, **employee expense**, depreciation, **operating profit**, **profit for the period**, **average number of employees**, retained earnings, profit before tax | per company per annual report (2019–2025 files) | monthly | CC BY 4.0 | download from `avaandmed.ariregister.rik.ee` (the host the register dump already comes from) |
| e-Business Register "general information of reports" `1.aruannete_yldandmed_…zip` | report period, submission date, company category, audit | per report | monthly | CC BY 4.0 | same |
| Tax and Customs Board (EMTA) "tasutud maksud, käive ja töötajate arv" | **state taxes**, **labour taxes**, **turnover**, **employees** | per company per quarter (since 2017) | quarterly, 10th of the month after | open data (reuse, commercial too) | CSV per quarter from `emta.ee` — the exact file URLs and column names are confirmed in PR1 before any code |

The register's general data dump (read weekly already) carries only the employee count per annual report; the key
indicators file carries the money.

**Measured 2026-09-25 from real downloads** (scratch `/home/sm/scratch/figures`):
- **EMTA** `tasutud_maksud_kaesolev_aasta_eng.csv` (current + previous year, 62 MB, 442 910 rows) and
  `…_varasemad_aastad_eng.csv` (2022–2024): comma CSV, one row per company per year — `Data date, Registry code, Name,
  Type, County, Activity, Year`, then `State taxes I–IV qtr`, `Labour taxes and payments I–IV qtr`, `Turnover I–IV qtr`,
  `Number of employees I–IV qtr` (a future quarter is empty). Served from `ncfailid.emta.ee` (a Nextcloud share: the
  `/s/<token>/download/…` link answers 303 to `/public.php/dav/files/<token>` on the same host — the token URLs are
  configuration, not code). **Covers every taxpayer**: Nortal AS 2026 Q1 367 employees, turnover 64.9 M; Swedbank AS
  has taxes and employees but **no turnover** (banks report no VAT turnover — a gap, never zero).
- **RIK key indicators** `4.<year>_aruannete_elemendid_kuni_<date>.zip` (2024: 24 MB zip, 319 MB CSV, 3.87 M rows):
  long form `report_id;tabel;elemendi_label;elemendi_nimetus;vaartus` (semicolon, quoted); elements used: `Revenue`,
  `TotalProfitLoss` (operating), `TotalAnnualPeriodProfitLoss` (net), `AverageNumberOfEmployeesInFullTimeEquivalentUnits`,
  `LaborExpense`/`EmployeeExpense` (two report schemes), `Assets`, `Equity`. Joined to companies through
  `1.aruannete_yldandmed_…zip` (255 MB CSV: `report_id, registrikood, aruandeaasta, kas konsolideeritud?, period_start,
  period_end, esitatud_kpv, …`). The 2024 file holds 257 252 reports, 822 consolidated.
- **Coverage of the 97 hiring companies with a code (test, 2026-09-25):** 75 filed a 2024 report; 58 have revenue
  under the report's own id. **Correction (PR2 review):** the "missing" large employers are not missing — a report
  filed with a second id (`taidetud_aruanne_report_id` in the general data; 492 reports in 2024, 75 of the 500 large
  companies, Nortal and Swedbank among them) has its key indicators under that id: Nortal 2024 revenue 62.7 M, 345
  people (its own; the group's 220 M and 1 546 beside them). EMTA still came first: it covers every taxpayer quarterly.

## Architecture

- **Reference tables keyed by registry code**, like `register_company`: `company_figure_year` (registry_code, year —
  the register's label, placed at period_end —, period_end, revenue, operating_profit, profit, labour_expense,
  avg_employees in FTE, assets, equity, submitted) and `company_figure_quarter` (registry_code, year, quarter, turnover, employees, state_taxes, labour_taxes,
  published = the file's `Data date`). Kept for the companies masi has **met** (`findEngaged`: a job, a contact, a note, a
  rating — the same rule the board-members source uses), not every coded row and not the whole country: a company met
  later gets its figures on the next read. Idempotent upserts; a re-read replaces a quarter (corrections happen) unless
  the quarter held came from a later publication.
- **Collectors**: `ariregisteraruanded` (the key-indicator files, monthly, one zip per year streamed like the register
  dump, only rows whose code masi has met) and `emta` (the two quarterly CSVs, older first, on the 12th of January,
  April, July and October; only legal persons' taxpayer types — an unknown type is skipped and named on the run). Each has
  its seeded, disabled-by-default `source` row, a fixture cut from a real file, a byte budget, and the strict allow-list
  (`emta.ee`'s download host added to the chart's `masiService.http.allowedHosts`).
- **API**: `GET /companies/{id}/figures` → `{ years: [...], quarters: [...] }`, empty for a company without a code.
- **Site**: a Figures card on the company page with recharts (already a dependency): employees (annual average and
  quarterly count on one time axis), revenue and profit per year (bars, profit may be negative), quarterly turnover and
  taxes; each series labelled with its source and period; no card without figures. Built with the dataviz skill's rules
  (colour, accessible labels, light and dark), measured in the layout spec at phone width.
- **Money** is euros as the files state it; a missing value is a gap, never zero.

## PRs

1. **platform/infra + masi — EMTA quarterly** (first: it covers the large employers): allow-list `ncfailid.emta.ee`;
   fixture cut from the real file; collector (streamed, only held codes), `company_figure_quarter`; API.
2. **masi — the register's key indicators**: the download page read for the current file names, the general data and
   the latest four years streamed and joined on `report_id` **and** the second id a report is filed with;
   `company_figure_year`; **only the company's own figures, never its group's** (a group's carry `…Consolidated` names);
   a non-profit's own names (total income, surplus, net assets); an IFRS filer's own headcount and revenue from the PDF
   table by label; the liquidation itself is no year, the trading before it is; API `years`. Weekly (the refresh day is
   not published). Allow-list unchanged (same host).
3. **site — the Figures card**: charts, tests, layout spec.

## Verification

Revert checks per mechanism, as for every masi PR: only held codes kept; a re-read replaces; a missing value stays
null; the byte budget; the API empty without a code; the card absent without figures; each chart's series from its
source. Live: after the first reads in test, the figures of a few known employers (e.g. Nortal AS, 10391131) compared by
hand with the register's own page.

## Status

- **PR1 (EMTA quarterly) — MERGED masi #62 (03f90a5), LIVE in test 2026-09-25 18:40 Tallinn (15:40 UTC)**: changeset 044
  ran, `emta` seeded OFF (COMPANIES, `0 40 6 12 1,4,7,10 *`), `company_figure_quarter` empty until the first run;
  platform efbc6c0 put `ncfailid.emta.ee` on the allow-list (in the pod's env). Architecture review + test audit
  findings all fixed (a failed second file or a timeout keeps what was read, an older publication never wins,
  legal-person allow-list, parsed = quarters written); 55 revert checks, all red. The audit ran both real files
  (1.08 M rows) through the collector against an independent oracle: identical.
- **PR3 (site Figures card)** — built ahead of PR2 (the masi tree is lent to 096 PR4b-1): quarterly charts only;
  PR2 adds the annual series to the same card.
- **PR2 (RIK key indicators) — MERGED masi #64 (e061dc4), LIVE in test 2026-09-25 22:07 Tallinn**: changeset 046 ran,
  `ariregisteraruanded` seeded OFF (weekly, Mondays 07:20). Joined on report_id AND the second id; own figures only.
- **PR3b (site: the annual series on the card)** — branch `masi/company-figures-years`: a chart by financial year
  (named by when each year ends), the annual headcount a dashed step held across its year's quarters on the employees
  chart, latest year's revenue and profit; reviewed (web-ui + test audit), fixtures from the real files (HORTICOM
  years to July, ARTISTON an 18-month transition year, 10002603 years only).
- **Follow-up (masi, after monitor-a3's PR #63 frees the tree): send `periodStart`** — `period_start` from the general
  data into `company_figure_year` (changeset 047) and the DTO. The site already holds a year from it when present; until
  then it holds the four quarters before a year's end and never over an earlier year (3 261 companies have short or
  overlapping years touching 2022+, e.g. 10015764). Both files measured: current 62 MB / 442 909 rows
  (2025–2026), previous 93 MB / 642 228 rows (2022–2024), same header, published 10.07.2026.

DRAFT 2026-09-25 — sources verified from real downloads and coverage measured; PR1 starts after masi #61 (the address)
merges (site #29 is merged and live).
