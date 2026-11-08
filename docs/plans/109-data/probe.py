"""Read-only measurement: what ATS boards would masi find for companies it knows no job of.

Per company: (1) fingerprint - the homepage and up to two careers pages it links, searched for ATS URLs;
(2) probe - name/domain-derived slugs asked at each vendor's public board API. Parallel by processes.
Usage: python3 -I probe.py companies.tsv out.jsonl
"""
import json
import re
import sys
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import urllib.robotparser
from multiprocessing import Pool

UA = "Mozilla/5.0 (compatible; masi-research/1.0)"
TIMEOUT = 12

ATS = {
    "greenhouse": r"(?:boards|job-boards)(?:\.eu)?\.greenhouse\.io/(?:embed/job_board(?:/js)?\?for=)?([\w-]+)",
    "lever": r"jobs\.(?:eu\.)?lever\.co/([\w.-]+)",
    "ashby": r"jobs\.ashbyhq\.com/([\w.%-]+)",
    "workable": r"(?:apply\.workable\.com/(?!api)([\w-]+)|([\w-]+)\.workable\.com)",
    "recruitee": r"([\w-]+)\.recruitee\.com",
    "teamtailor": r"([\w-]+)\.teamtailor\.com",
    "personio": r"([\w-]+)\.jobs\.personio\.(?:de|com)",
    "smartrecruiters": r"(?:jobs|careers)\.smartrecruiters\.com/([\w-]+)",
    "teamdash": r"([\w-]+)\.teamdash\.com",
    "bamboohr": r"([\w-]+)\.bamboohr\.com",
    "workday": r"([\w-]+)\.(?:wd\d+\.)?myworkdayjobs\.com",
    "breezy": r"([\w-]+)\.breezy\.hr",
    "jobvite": r"jobs\.jobvite\.com/([\w-]+)",
    "join": r"join\.com/companies/([\w-]+)",
    "homerun": r"([\w-]+)\.homerun\.co",
    "pinpoint": r"([\w-]+)\.pinpointhq\.com",
    "softgarden": r"([\w-]+)\.softgarden\.io",
    "jobylon": r"emp\.jobylon\.com/(?:jobs/)?([\w-]+)",
    "cvee": r"cv\.ee/[\w/-]*?(?:employer|tooandja)[\w/-]*?/([\w-]+)",
    "cvkeskus": r"cvkeskus\.ee/([\w-]*?toopakkumised[\w-]*)",
}
IGNORE_SLUG = {"www", "app", "api", "embed", "static", "assets", "cdn", "careers", "jobs", "js", "css"}
CAREERS = re.compile(r"career|karj[aä]{1,2}r|jobs?\b|vacanc|t[oö]{1,2}pakkumis|vabad.t[oö]{1,2}kohad|ametikoh|join.(?:us|the.team)|"
                     r"work.with.us|liitu|tule.t[oö]{1,2}le|we.?re.hiring|open.positions|вакан|карьер", re.I)
HREF = re.compile(r"""<a\b[^>]*?href\s*=\s*["']([^"'#]+)["'][^>]*>(.*?)</a>""", re.I | re.S)
LEGAL = re.compile(r"\b(o[uü]|as|aktsiaselts|osa[uü]hing|mt[uü]|sihtasutus|estonia|eesti|ltd|limited|gmbh|ab|oy|inc|group|filiaal|branch)\b", re.I)


def get(url, accept=None, limit=2_000_000):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": accept or "text/html,application/json,*/*"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return r.status, r.geturl(), r.read(limit).decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, url, ""
    except Exception as e:  # noqa: BLE001 - a measurement: every failure is recorded, none stops the run
        return None, url, type(e).__name__


def allowed(url, cache):
    p = urllib.parse.urlsplit(url)
    root = f"{p.scheme}://{p.netloc}"
    if root not in cache:
        rp = urllib.robotparser.RobotFileParser()
        status, _, body = get(root + "/robots.txt")
        rp.parse(body.splitlines() if status == 200 else [])
        cache[root] = rp
    return cache[root].can_fetch(UA, url)


def fingerprints(html):
    found = set()
    for vendor, rx in ATS.items():
        for m in re.finditer(rx, html, re.I):
            slug = next((g for g in m.groups() if g), None)
            if slug and slug.lower() not in IGNORE_SLUG:
                found.add((vendor, slug))
    return found


def careers_links(base, html):
    host = urllib.parse.urlsplit(base).netloc.removeprefix("www.")
    out = []
    for href, text in HREF.findall(html):
        text = re.sub(r"<[^>]+>", " ", text)
        if CAREERS.search(href) or CAREERS.search(text):
            u = urllib.parse.urljoin(base, href.strip())
            uh = urllib.parse.urlsplit(u).netloc.removeprefix("www.")
            if u.startswith("http") and (uh == host or uh.endswith("." + host)) and u not in out:
                out.append(u)
    return out[:2]


def slugs(name, website):
    labels = urllib.parse.urlsplit(website).netloc.lower().split(":")[0].split(".")
    label = labels[-3] if len(labels) >= 3 and labels[-2] in {"com", "co"} else labels[-2] if len(labels) >= 2 else labels[0]
    n = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode().lower()
    n = LEGAL.sub(" ", re.sub(r"[^\w\s-]", " ", n))
    words = [w for w in n.split() if w]
    cands = [label, "".join(words), "-".join(words)] + ([words[0]] if words else [])
    return [s for s in dict.fromkeys(cands) if re.fullmatch(r"[a-z0-9][a-z0-9-]{1,60}", s)]


def probe(slug):
    hits = []
    s, _, b = get(f"https://boards-api.greenhouse.io/v1/boards/{slug}")
    if s == 200:
        jobs = get(f"https://boards-api.greenhouse.io/v1/boards/{slug}/jobs")[2]
        hits.append(("greenhouse", json.loads(b).get("name"), _count(jobs, "jobs"), _ee(jobs)))
    s, _, b = get(f"https://api.lever.co/v0/postings/{slug}?mode=json")
    if s == 200 and b.strip().startswith("["):
        hits.append(("lever", slug, len(json.loads(b)), _ee(b)))
    s, _, b = get(f"https://api.ashbyhq.com/posting-api/job-board/{slug}")
    if s == 200:
        hits.append(("ashby", slug, _count(b, "jobs"), _ee(b)))
    s, _, b = get(f"https://{slug}.recruitee.com/api/offers/")
    if s == 200 and b.strip().startswith("{"):
        hits.append(("recruitee", slug, _count(b, "offers"), _ee(b)))
    s, u, b = get(f"https://apply.workable.com/api/v1/widget/accounts/{slug}")
    if s == 200 and b.strip().startswith("{"):
        d = json.loads(b)
        hits.append(("workable", d.get("name"), len(d.get("jobs", [])), _ee(b)))
    s, u, b = get(f"https://{slug}.jobs.personio.de/xml")
    if s == 200 and "<workzag-jobs" in b:
        hits.append(("personio", slug, b.count("<position>"), _ee(b)))
    s, u, b = get(f"https://{slug}.teamtailor.com/jobs")
    if s == 200 and slug in urllib.parse.urlsplit(u).netloc:
        hits.append(("teamtailor", re.search(r"<title>(.*?)</title>", b, re.S | re.I).group(1).strip()[:80] if "<title>" in b.lower() else slug,
                     b.count('href="/jobs/') or None, _ee(b)))
    s, u, b = get(f"https://api.smartrecruiters.com/v1/companies/{slug}/postings?limit=100")
    if s == 200:
        d = json.loads(b) if b.strip().startswith("{") else {}
        if d.get("totalFound"):
            names = {p.get("company", {}).get("name") for p in d.get("content", [])}
            hits.append(("smartrecruiters", ",".join(sorted(n for n in names if n))[:80], d["totalFound"], _ee(b)))
    s, u, b = get(f"https://{slug}.teamdash.com/")
    if s == 200 and "teamdash" in b.lower():
        hits.append(("teamdash", slug, None, _ee(b)))
    return hits


def _count(body, key):
    try:
        return len(json.loads(body).get(key, []))
    except ValueError:
        return None


def _ee(body):
    return len(re.findall(r"estonia|tallinn|tartu|eesti", body, re.I))


def one(row):
    cid, name, website, band, emtak, has_ats = row
    res = {"id": int(cid), "name": name, "website": website, "band": band, "emtak": emtak, "known_ats": has_ats == "t"}
    robots = {}
    pages, fp = [], set()
    if allowed(website, robots):
        s, final, html = get(website)
        res["home"] = s
        if s == 200:
            fp |= fingerprints(html)
            for c in careers_links(final, html):
                if not allowed(c, robots):
                    continue
                cs, cfinal, chtml = get(c)
                pages.append([c, cs])
                if cs == 200:
                    fp |= fingerprints(chtml) | fingerprints(cfinal)
    else:
        res["home"] = "robots"
    res["careers"] = pages
    res["fingerprint"] = sorted(fp)
    res["slugs"] = slugs(name, website)
    res["probe"] = {s: probe(s) for s in res["slugs"]}
    return res


if __name__ == "__main__":
    rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
    with Pool(4) as pool, open(sys.argv[2], "w", encoding="utf-8") as out:
        for r in pool.imap_unordered(one, rows):
            out.write(json.dumps(r, ensure_ascii=False) + "\n")
            out.flush()
