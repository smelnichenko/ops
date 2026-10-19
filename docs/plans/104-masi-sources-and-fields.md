# Plan 104 — masi: the review's sources, and the fields they need

**Status:** approved 2026-10-19. The operator reviewed "masi data collection & relocation review"
(https://claude.ai/artifact/L3qNC2DSPrHLaeW3NTzcwX) and said "do it" and "everything approved!". Treated as an
academic project; see the memory note on that.

Masi gets one PR at a time. Each PR follows the usual routine: a failing test first, revert checks, the clean check, a
PR, CI, merge, a smoke test on test, a promote, and a check in production. Production is the main environment and test
is smoke only.

## Why

masi collects for Estonia only. The operator may move abroad (Indonesia was first named, but nothing is fixed) and may
work B2B through the OÜ. The review found ten legally clean sources worth adding. It also found four gaps in the data
model that block searching from abroad.

## PRs, in order

1. **Any public host.** `masi.http.allowed-hosts: *`, both in the fetcher and in the browser guard. The SSRF check and
   the network policy stay as the defence. The chart sets `*` in production. Every new source then needs no host
   entry.
2. **Fields.**
   - Salary currency and pay period. MeetFrank already mixes yearly with monthly figures, and Personio assumes EUR.
   - Employment type (permanent, contract, freelance), taken from the ATS fields masi already receives and drops:
     Lever `commitment`, Ashby `employmentType`, SmartRecruiters `typeOfEmployment`, Workable `employment_type`,
     Töötukassa full/part-time.
   - Country and remote scope (country list, timezone limits).
   - A filter on the jobs page for each of these.
3. **MeetFrank honesty.** Compare against the API's `totalCount`, so that a short answer is an incomplete run and
   never closes listings.
4. **B2B contracts.** Verama's public JSON (remote %, rate, deadline), and freelancermap (sitemap + JobPosting).
5. **Tenders.** TED API v3 for IT CPV codes (72, 48) in EE/LV/LT/FI/SE, with award notices kept as a list of prime
   contractors. Also riigihanked RSS plus the monthly eForms XML. Tenders are a new kind (not a job); the jobs page
   shows them apart.
6. **Remote boards.**
   - Himalayas API (free key; its terms name a "personal agent"; every Apply uses its `applicationLink`).
   - HN "Who is hiring" via Algolia, extracted per comment by the cheap model. Its ATS links feed the existing
     auto-detection.
   - We Work Remotely RSS only (its terms forbid scraping the HTML).
7. **Baltic and Nordic boards.**
   - cv.lv and cvonline.lt as configuration on `CvEeCollector`. Read their terms first and record them.
   - Sweden's JobTech (CC0, `remote=true`).
   - Germany's BA Jobsuche.
   - EURES (crawl-delay 10, credit ELA).
8. **Company signals.** The RTK grant-recipient xlsx, joined by registry code. The Estonian startup funding sheet. The
   ERR/aritehnoloogia/ArcticStartup feeds as company mentions. Recruiter and investor names are never kept.
9. **Indonesia.** Source rows on ATS types masi already reads:
   - Grab (SmartRecruiters);
   - GoToGroup (Lever, the case exact);
   - dkatalislabs, xendit, straitsx (Greenhouse);
   - ajaib, amartha (Workable).

   Plus a Kalibrr JSON collector, and new Breezy HR and Mekari Talenta collectors.
10. **Research-only sources at stated risk** (approved): Duunitori, cvbankas, JustJoin.it, The Hub, No Fluff Jobs,
    Landing.jobs, Remotive. Each records its terms and robots facts in `docs/sources.md`.

11. **People: a profile link and the operator's own photo** (operator 2026-10-19, "do both", after being advised
    against collecting faces automatically). No automatic photo collection: LinkedIn sits behind a login, a Gravatar
    lookup by e-mail would be enrichment, and a team-page face matched to a name is guesswork. Systematically scraping
    faces also very likely falls outside GDPR's household exemption.
    - `person.profile_url`: http(s) only. The operator sets it on the person's page (their public team page or
      profile). The site shows it as a link (`rel="noopener noreferrer"`); masi never fetches it.
    - The operator's photo: uploaded on the person's page; JPEG/PNG/WebP checked by content, at most 2 MB. Re-encoded
      on the server so EXIF and GPS are dropped, and stored with the owner's user id (a `person_photo` row). Served
      only to the owner with `Cache-Control: private`, and never sent anywhere else (no mail, report or partner API).
      Removed when the operator removes it, and when the person is erased (the erase already writes a suppression row).
    - masi backend first, then the site's person page.

## Out regardless

Each of these needs the operator to name it explicitly:
- cvkeskus: €10,000 per automated request.
- LinkedIn, Wellfound, Upwork, Crunchbase: login walls.
- Malt, Dealroom, teatmik, jobs.ee: bot challenges or captchas.

Getting past a login or a challenge removes both copyright exceptions (AutÕS §19¹ and §19²).

## Rules for every new source

- Record what its robots.txt and terms say in `docs/sources.md` (the new-source checklist).
- Store no recruiter, investor or bidder names; only what the posting published, as today.
- Ship disabled, run once in production by hand, then enable.
- A source that is a new *kind* (tenders, company signals) gets its own page section, not mixed into jobs.
