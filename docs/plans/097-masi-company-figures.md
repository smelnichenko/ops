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
indicators file carries the money. The exact column names of both files are read from a real download in PR1 and
recorded here; the fixtures are cut from those downloads.

## Architecture

- **Reference tables keyed by registry code**, like `register_company`: `company_figure_year` (registry_code, year,
  period_end, revenue, total_revenue, operating_profit, profit, employee_expense, avg_employees, assets, equity, source
  file date) and `company_figure_quarter` (registry_code, year, quarter, turnover, employees, state_taxes, labour_taxes).
  Kept for the registry codes masi holds (companies with a code) — not the whole country: a company placed later gets its
  figures on the next read. Idempotent upserts; a re-read replaces a row (corrections happen).
- **Collectors**: `ariregisteraruanded` (the key-indicator files, monthly, one zip per year streamed like the register
  dump, only rows whose code masi holds) and `emtamaksud` (the quarterly CSV, the latest quarters, same filter). Each has
  its seeded, disabled-by-default `source` row, a fixture cut from a real file, a byte budget, and the strict allow-list
  (`emta.ee`'s download host added to the chart's `masiService.http.allowedHosts`).
- **API**: `GET /companies/{id}/figures` → `{ years: [...], quarters: [...] }`, empty for a company without a code.
- **Site**: a Figures card on the company page with recharts (already a dependency): employees (annual average and
  quarterly count on one time axis), revenue and profit per year (bars, profit may be negative), quarterly turnover and
  taxes; each series labelled with its source and period; no card without figures. Built with the dataviz skill's rules
  (colour, accessible labels, light and dark), measured in the layout spec at phone width.
- **Money** is euros as the files state it; a missing value is a gap, never zero.

## PRs

1. **masi — the register's key indicators**: confirm the file layout from a real download; fixture; collector,
   `company_figure_year`, API. Allow-list unchanged (same host).
2. **platform/infra + masi — EMTA quarterly**: allow-list the download host; fixture; collector,
   `company_figure_quarter`; API.
3. **site — the Figures card**: charts, tests, layout spec.

## Verification

Revert checks per mechanism, as for every masi PR: only held codes kept; a re-read replaces; a missing value stays
null; the byte budget; the API empty without a code; the card absent without figures; each chart's series from its
source. Live: after the first reads in test, the figures of a few known employers (e.g. Nortal AS, 10391131) compared by
hand with the register's own page.

## Status

DRAFT 2026-09-25 — sources verified; PR1 starts after masi #61 and site #29 (the address) merge.
