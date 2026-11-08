"""Every board a vendor hosts, as Common Crawl saw it: slugs per vendor from the CDX index. Sequential, retried."""
import json, re, sys, time, urllib.parse, urllib.request
UA = "masi-research/1.0"
CRAWLS = ["CC-MAIN-2026-43", "CC-MAIN-2026-39", "CC-MAIN-2026-34"]
Q = {"teamtailor": ("*.teamtailor.com", r"^https?://([a-z0-9-]+)\.teamtailor\.com"),
     "lever": ("jobs.lever.co/*", r"^https?://jobs\.lever\.co/([A-Za-z0-9._-]+)"),
     "levereu": ("jobs.eu.lever.co/*", r"^https?://jobs\.eu\.lever\.co/([A-Za-z0-9._-]+)"),
     "greenhouse": ("job-boards.greenhouse.io/*", r"^https?://job-boards\.greenhouse\.io/([a-z0-9-]+)"),
     "greenhouse-eu": ("job-boards.eu.greenhouse.io/*", r"^https?://job-boards\.eu\.greenhouse\.io/([a-z0-9-]+)"),
     "greenhouse-old": ("boards.greenhouse.io/*", r"^https?://boards\.greenhouse\.io/([a-z0-9-]+)"),
     "ashby": ("jobs.ashbyhq.com/*", r"^https?://jobs\.ashbyhq\.com/([A-Za-z0-9._%-]+)"),
     "teamdash": ("*.teamdash.com", r"^https?://([a-z0-9-]+)\.teamdash\.com"),
     "recruitee": ("*.recruitee.com", r"^https?://([a-z0-9-]+)\.recruitee\.com"),
     "bamboohr": ("*.bamboohr.com", r"^https?://([a-z0-9-]+)\.bamboohr\.com"),
     "personio": ("*.jobs.personio.de", r"^https?://([a-z0-9-]+)\.jobs\.personio\.de"),
     "personio-com": ("*.jobs.personio.com", r"^https?://([a-z0-9-]+)\.jobs\.personio\.com"),
     "workable": ("apply.workable.com/*", r"^https?://apply\.workable\.com/([a-z0-9-]+)"),
     "recrur": ("*.recrur.com", r"^https?://([a-z0-9-]+)\.recrur\.com"),
     "smartrecruiters": ("jobs.smartrecruiters.com/*", r"^https?://jobs\.smartrecruiters\.com/([A-Za-z0-9-]+)"),
     "breezy": ("*.breezy.hr", r"^https?://([a-z0-9-]+)\.breezy\.hr"),
     "homerun": ("*.homerun.co", r"^https?://([a-z0-9-]+)\.homerun\.co"),
     "pinpoint": ("*.pinpointhq.com", r"^https?://([a-z0-9-]+)\.pinpointhq\.com"),
     "jobylon": ("emp.jobylon.com/*", r"^https?://emp\.jobylon\.com/(?:jobs/)?([a-z0-9-]+)")}
def get(url, tries=6):
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=120) as r:
                return r.read().decode("utf-8", "replace")
        except Exception as e:
            print("  retry", i, type(e).__name__, getattr(e, "code", ""), url[:90], file=sys.stderr, flush=True)
            time.sleep(10 * (i + 1))
    return None
out = {}
for vendor, (q, rx) in Q.items():
    slugs = set()
    for crawl in CRAWLS:
        base = f"https://index.commoncrawl.org/{crawl}-index?url={urllib.parse.quote(q, safe='*/')}&output=json"
        meta = get(base + "&showNumPages=true")
        if not meta or not meta.strip().startswith("{"):
            print(vendor, crawl, "no index answer", file=sys.stderr); continue
        for page in range(json.loads(meta)["pages"]):
            body = get(base + f"&fl=url&page={page}")
            for line in (body or "").splitlines():
                try: m = re.match(rx, json.loads(line)["url"])
                except ValueError: continue
                if m: slugs.add(m.group(1))
            time.sleep(1)
    slugs -= {"www", "api", "app", "embed", "assets", "static", "careers", "jobs", "cdn", "help", "support", "status", "blog", "go", "info", "auth", "login", "marketplace", "docs", "developers"}
    out[vendor] = sorted(slugs)
    print(vendor, len(slugs), flush=True)
    json.dump(out, open(sys.argv[1], "w"))
