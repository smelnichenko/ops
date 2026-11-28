# Research brief: free online job data sources, per EU country

Part of a study that answers: **for every EU member state, which job data sources are available
online for free?** "Job data" here means job vacancies and postings (the adverts themselves, with
title, employer, place, dates, text), and secondarily official vacancy statistics. The state to
describe is the one on the day you check; write that date in every file.

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
- Volume:
- Update cycle:
- Seen on <date>: <what you requested and what came back>
- Caveats:

(one block per source: employment service first, then public-sector portals, open-data datasets,
commercial boards, statistics)

## Not free or not allowed

## Gaps
```

Your final message: one line per country (the file written, the best free source, and its access
and terms in a few words), then anything that was refused, blocked or contradictory.
