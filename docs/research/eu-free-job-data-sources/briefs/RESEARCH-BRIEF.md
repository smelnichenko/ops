# Research brief: free online job data sources, per EU country

Part of a study that answers: **for every EU member state, which job data sources are available
online for free?** "Job data" here means job vacancies and postings (the adverts themselves, with
title, employer, place, dates, text), and secondarily official vacancy statistics. The state to
describe is the one on the day you check; write that date in every file.

## Purpose of the data

The data is wanted for ONE purpose: one person's own job search and job applications, with a
program doing the reading for that person. Not for redistribution, resale, statistics or model
training. So each source gets ONE verdict, and no further analysis of its terms:

**Usable for own job search: yes / no / unclear**, with the reason in a few words.
- "no" needs the one deciding clause, quoted: a ban on bots or automated queries, or the source is
  paid or for partners only.
- "unclear" when the terms are silent or could not be read.
- Clauses that only restrict redistribution or commercial reuse do not count against a source.

Official vacancy statistics (counts) are of no use for this purpose: skip item 6 below. Archives
of past adverts are a different thing and ARE wanted: see item 8e.

You research the countries named in your task. Another pass covers the EU-wide layer (EURES,
aggregators' APIs, applicant-tracking vendors' public feeds, remote-job feeds, Eurostat, Cedefop),
so mention those only where there is something specific to your country.

## What to find for each country

1. **Public employment service.** Its name (native and English), its vacancy database, and how the
   vacancies can be had: open-data dump, documented API, RSS/XML feed, or web pages only. Number of
   live vacancies if stated.
2. **Government and public-sector job portals** (civil-service vacancies, municipal portals) that
   offer a feed, API or dataset.
3. **Vacancy datasets on the national open data portal** and their entries on data.europa.eu.
4. **The main commercial job boards** (the three to six largest). For each: is there an official
   free feed or API for READING vacancies (not for employers posting them)? What do the terms of
   use and robots.txt say about automated reading and reuse? Quote the clause.
5. **EURES**: whether the country's public employment service sends its vacancies to EURES.
6. **Official vacancy statistics** from the national statistics office or the employment service
   (open data tables), in two or three lines.
7. **What is not free or not allowed**: paid data products, feeds for partners only, terms that
   forbid reuse.
8. **The employer route** (added 2026-11-28, 18:43). The tool this serves already finds jobs in
   Estonia through the companies: it takes a list of companies and reads each employer's own
   careers feed, so the application goes straight to the employer. Find what that route needs in
   the country:
   a. **The official business register**: is basic company data free in bulk or by API (name,
      registration number, status, legal form, address, activity code)? Does it carry a website or
      e-mail address? Licence, key, update cycle, exact URL. Say whether it is published as an EU
      high-value dataset (category "companies and company ownership").
      EU law sets a minimum (Regulation (EU) 2023/138, Annex 5: name, status, registration date,
      registered office address, legal form, registration number, Member State, activity code;
      CC BY 4.0 or looser; API and bulk download; from 9 June 2024 - see
      `evidence/regulation-2023-138-companies.md`). Countries differ in whether and how they meet
      it, so establish the facts for THIS country and do not reason from the rule: which of those
      eight attributes the free data carries, what it carries beyond them (website, e-mail, phone,
      number of employees), and - where the register is not free, not in bulk, or behind an
      approval - say so plainly and name what is free instead (search only, one company per
      request, a partial extract).
   b. **Applicant-tracking systems employers in the country use**, local vendors above all. For
      each: does an employer's board have a documented public feed (JSON, XML, RSS) readable
      without a key, and what do the vendor's terms say? Take this from the vendor's own
      documentation and customer pages only. NEVER request an employer's board or a vendor's data
      endpoint. Give the source of any "widely used here" statement.
   c. **Links from vacancies to employers' own pages**: any free source a program may read that
      carries the employer's own careers or apply URL (for example an open vacancy dataset with an
      external link field). Such links are how employers' boards are discovered.
   d. **Employer directories** with websites (industry associations, startup registers, chambers):
      two or three at most, with their terms.
   e. **Archives of past adverts.** Old adverts show which companies hire in a given skills area,
      so they are wanted, not waste: any free dataset or API of adverts that are no longer live.
      Record the years covered, the size, the licence, and above all the fields - employer name,
      employer registration number, occupation or skills, place, date - since those decide whether
      employers can be picked out by skill. Do not download the files; read their documentation
      and at most one small sample.

For every source record: publisher; exact URL of the documentation and of the data or endpoint;
what it holds (which fields: title, employer, location, salary, description, dates, occupation
code); access (bulk file, API, feed, web only); whether registration or a key is needed and whether
getting one is free and self-service; cost; licence or terms of reuse, with the exact wording and
its URL; volume; update cycle; language; caveats and recent or announced changes.

## How to check, and what not to do

- Open the publisher's own pages. Where an endpoint or file is public, request it once and record
  the HTTP status, content type, size and what came back (for an API: one minimal request, at most
  a handful of records).
- **These hosts are shared with a production system on the same public address. Be gentle:** at
  most three requests to any one job-board or vendor host in total, never two at the same time, no
  paging through results, no loops. An answer of 429, 403, a CAPTCHA or "error 1015" means stop
  using that host at once and record it.
- Do not create accounts, request API keys, accept terms on anyone's behalf, or log in anywhere.
  If a key is needed, describe how one is obtained from the publisher's page and stop there.
- Do not disguise the client: no browser-like User-Agent or other spoofed headers, no bypassing of
  TLS verification. A refusal is a finding; record it.
- Do not request bing.com directly.
- Never download a large file whole: use a HEAD request or a small byte range and cap every
  transfer (`curl --max-filesize 2000000 -m 30`). If you must save a file, use a new empty
  directory under
  `/home/sm/scratch/claude-tmp/claude-1000/-home-sm-src-monitor/5b4e1b67-888b-4b03-a7ad-7a83d164d86a/scratchpad/`
  and delete it when done. Run any Python that reads downloaded data with `python3 -I`; parallelise
  Python with processes only, never threads.
- Do not guess. Anything you could not confirm goes under "Gaps", with the reason. A statement
  taken from a third party (a blog, a wiki, another project's source list) is labelled as such.
- No git commands. Write only the files named below.

## Output: one file per country, written as soon as that country is done

Write `<folder>/research/<CC>-<Name>.md` (the folder and the exact file names are in your task)
with this structure, and write each country's file before starting the next country, so that an
interruption loses at most one country:

```
# <Name> (<CC>) - free online job data sources: research

Checked on <date>. Client: <what you used>.

## Takeaway
Three to six sentences: the best free source, how it is obtained and on what terms, and what is missing.

## Sources

### <source name>
- Publisher:
- Documentation:
- Data or endpoint:
- Holds:
- Access:
- Registration or key:
- Cost:
- Licence or terms (exact wording, with URL):
- Usable for own job search: <yes / no / unclear> - <reason; the deciding clause if "no">
- Volume:
- Update cycle:
- Seen on <date>: <what you requested and what came back>
- Caveats:

(one block per source: employment service first, then public-sector portals, open-data datasets,
commercial boards)

## Through the employers

### Business register
(one block in the same format as a source)

### Applicant-tracking vendors seen in the country

| Vendor | Local or international | Public feed for an employer's board (format, key?) | Documentation URL | Basis for "used here" |
|---|---|---|---|---|

### Links to employers' own pages

### Employer directories

### Archives of past adverts

## Not free or not allowed

## Gaps
```

## Second output: the country's prohibited sources

For each country also write `<folder>/prohibited/<CC>-<Name>.md`, with "Status: first pass - not
yet independently checked", in the format of `briefs/PROHIBITED-BRIEF.md` (read it): one row per
source whose own terms or robots.txt explicitly forbid automated reading or copying, with the
clause you read today quoted. It needs no extra requests. Run `python3 -I exclude_list.py` in the
folder at the end; it must exit 0.

Your final message: one line per country (the file written, the best free source, and its access
and terms in a few words), then anything that was refused, blocked or contradictory.
