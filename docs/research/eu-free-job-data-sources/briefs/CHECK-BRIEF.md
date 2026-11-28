# Check brief: independent re-check of the research, claim by claim

You are an independent fact-checker for a study of free online job data sources (job vacancies and
postings) in the EU. A researcher wrote one file per country in `research/`. Your job is to check
those files against the live sources, not to trust them. Assume each claim may be wrong until you
have seen the evidence yourself.

## What to do, per country (or per topic for the EU-wide file)

1. Read the research file fully. List every checkable claim: each source URL, endpoint, feed or
   file; access (bulk, API, feed, web only); registration or key requirement; cost; licence or
   terms wording; fields; volume; update cycle; dates of changes; and every negative statement
   ("no API", "no open dataset", "terms forbid reuse").
2. Re-request each URL and endpoint yourself, once, and record the status, content type and what
   came back.
3. Re-read licence, terms, cost and registration claims on the PUBLISHER'S OWN page. Quote the
   wording you saw, with its URL.
4. Try to disprove the negative claims: search the national open data portal and data.europa.eu
   for vacancy datasets, and look for a developer or API page on the publisher's site.
5. Where the research marks something as a gap, try once by a different legitimate route.

## Rules

- **The hosts are shared with a production system on the same public address. Be gentle:** at most
  three requests to any one job-board or vendor host in total, never two at the same time, no
  paging, no loops. A 429, 403, CAPTCHA or "error 1015" means stop using that host at once and mark
  the claim UNVERIFIED.
- Do not create accounts, request API keys, accept terms, or log in. Do not disguise the client:
  no spoofed headers, no bypassing of TLS verification. If the session's permission system declines
  a request, record it as UNVERIFIED and move on; do not look for a way around it.
- Do not request bing.com directly.
- Cap every transfer (`curl --max-filesize 2000000 -m 30`); some servers ignore Range. Save files
  only in a new empty directory under
  `/home/sm/scratch/claude-tmp/claude-1000/-home-sm-src-monitor/5b4e1b67-888b-4b03-a7ad-7a83d164d86a/scratchpad/`
  and delete it when done. `python3 -I` for any Python that reads downloaded data; processes, never
  threads.
- Do NOT edit anything in `research/`. No git commands.
- CONFIRMED means you saw it today; say what you saw. Never mark something CONFIRMED because the
  research says so or because it is plausible. A negative claim you failed to disprove is
  NOT DISPROVED, not CONFIRMED.

## Output: one file per country, written as soon as that country is done

Write `<folder>/check/<CC>-<Name>.md` (same file name as the research file) with:

```
# <Name> (<CC>) - check of the research

Checked on <date>. Client: <what you used>.

## Corrections and unverified claims (apply these first)
- one line per CORRECTED or WRONG claim, with the right value
- one line per UNVERIFIED claim, with the reason

## Claims

| # | Claim | Verdict | Evidence (URL, status, what was seen) | Corrected statement |
|---|---|---|---|---|

## Found beyond the research
- sources or facts the research missed, each with its evidence
```

Verdicts: CONFIRMED / CORRECTED / WRONG / UNVERIFIED / NOT DISPROVED. Put the verdict word first
in its cell. Write each country's file before starting the next, so an interruption loses at most
one country.

Your final message: counts per verdict per country, each CORRECTED or WRONG item in one line with
the right value, and each UNVERIFIED item with the reason.
