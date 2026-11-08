# Plan 112 — masi lists: every column sortable, the same way everywhere

**Status:** asked for 2026-11-08 by the operator: "essentially, all fields should be sortable" and "use same best
practice for sorting everywhere".

## Why

- **Most columns do not sort.** Only a few do: People (name, address, seen), Companies (name, registry code, seen) and
  Jobs (title, first seen, match). The rest of masi's lists do not sort at all.
- **The server treats a sort three ways.**
  - Jobs answers an unknown column with a 400.
  - Companies and People silently fall back to their default order, so a wrong request looks right.
  - No list breaks ties, so a sort on a column many rows share can repeat or skip rows from one page to the next.
- **The headers differ from page to page** in style and in how they are marked.

## The practice, the same on every list

1. **Every column that shows a value sorts.** A column of buttons (Actions) does not.
2. **The sort lives in the URL** (`?sort=column,asc|desc`). It survives a reload and a shared link, and a new sort starts
   again at page 1.
3. **A paged list is sorted by the server, over all its rows.** Sorting one page in the browser would show a false order.
   A list the page loads whole (Packages, Sources, a source's newest runs, Reports) sorts in the browser.
4. **One header component.**
   - A button inside `<th aria-sort="ascending|descending|none">`, so screen readers announce the order.
   - ▲ or ▼ marks the sorted column; the label reads the same as the other headers.
   - Tab, then Enter or Space, works it from a keyboard.
5. **First press ascending, second descending:** A→Z, oldest first, smallest first.
6. **Empty values last, in both directions.** A missing date or score is not "earliest" or "latest".
7. **Ties broken by id**, in the same direction, so pages never repeat or skip a row.
8. **masi: one parser for every endpoint.** Each endpoint lists its API column names and maps each to a column or an
   expression. An unknown column or direction is a 400, never a silent default.

## Columns

A computed column sorts by what its cell shows.

| List (paged?) | Columns: what each sorts by |
|---|---|
| People (paged) | Name; Address; Companies: the first company name, A→Z; Seen; Contact?: ok to contact before do not contact; the Companies cell lists them A→Z |
| Companies (paged) | Name; Registry code; City; ATS: vendor name; Status; Seen |
| Jobs (paged) | Title; Company: its name; Sources: how many; Location; First seen; Match (as now: unscored last); Package: its state |
| Listings (paged) | Job: its title; Company: its name; On the board: the posting's title; Source: its name; First seen; Closed |
| Bookings (paged) | When; Booking: its title; Job: its title; Company: its name; Outcome |
| Source runs (the 20 newest, whole) | Started; Status; Parsed; New jobs; Closed; Companies; Error: those with one first. Sorted in the browser: the table is a source's newest runs, and the page's progress poll reads them newest first |
| Packages (whole) | Job; Company; State; Cost; Updated |
| Sources (whole) | Source; Kind; Cron: the next run (masi adds `nextRunAt`, the cron in the scheduler's zone); Requests/day: no cap last; Health: best to worst; Last success (Actions: no) |
| Reports (whole) | Kind; Period; Generated |

## Steps

1. **masi PR:** the shared parser, every paged endpoint's columns, a 400 on an unknown column, ties by id, empty last.
   - Tests for each endpoint: each column orders as it should, an empty value comes last both ways, the tie-break holds
     across pages, and an unknown column gets a 400.
2. **site PR:** the shared `SortableHeader` on every masi list, with browser sorting for the lists loaded whole.
   - Unit tests with user-event (press, press again, keyboard).
   - Layout harness: the header keeps the steady widths.
   - A rendered sample goes to the operator before shipping.
