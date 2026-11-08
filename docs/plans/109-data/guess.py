"""Slug guessing, measured with its evidence: for each company, name/domain-derived slugs asked at each vendor's
public board, and for every board that answers, the signals a guess would be judged on:
  ee      - postings whose location names Estonia (structured location fields)
  jobs    - postings on the board
  name    - the company's name tokens found in the board's own name/title (0..1)
  domain  - the company's registrable domain appears on the board
Usage: python3 -I guess.py companies.tsv out.jsonl   (tsv: id, name, website, ...)
"""
import json
import re
import sys
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from multiprocessing import Pool

UA = "Mozilla/5.0 (compatible; masi-research/1.0)"
EE = re.compile(r"estonia|eesti|tallinn|tartu|\bee\b|p[aä]rnu|narva", re.I)
LEGAL = {"ou", "as", "aktsiaselts", "osauhing", "mtu", "sihtasutus", "estonia", "eesti", "ltd", "limited", "gmbh", "ab", "oy",
         "inc", "group", "filiaal", "branch", "pank", "bank", "the", "and", "ja", "of", "co", "llc", "sia", "uab", "development",
         "technologies", "technology", "tech", "solutions", "systems", "software", "services", "baltic", "baltics"}
SUFFIXES = ["bank", "group", "tech", "development"]   # the variants the known boards' slugs used (recall test 2026-11-08)


def get(url, limit=3_000_000):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json,text/html,*/*"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, r.geturl(), r.read(limit).decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, url, ""
    except Exception as e:  # noqa: BLE001 - a measurement
        return None, url, type(e).__name__


def tokens(text):
    t = unicodedata.normalize("NFKD", re.sub(r"\(.*?\)", " ", text)).encode("ascii", "ignore").decode().lower()
    return [w for w in re.sub(r"[^a-z0-9]+", " ", t).split() if w]


def core(name):
    return [w for w in tokens(name) if w not in LEGAL]


def domain_of(website):
    if not website:
        return None
    h = urllib.parse.urlsplit(website if "//" in website else "https://" + website).netloc.lower().split(":")[0]
    labels = h.removeprefix("www.").split(".")
    if len(labels) >= 3 and labels[-2] in {"com", "co"}:
        return ".".join(labels[-3:])
    return ".".join(labels[-2:]) if len(labels) >= 2 else None


def slugs(name, website, aliases=()):
    out = []
    d = domain_of(website)
    if d:
        out.append(d.split(".")[0])
    for n in (name, *aliases):
        w = core(n) or tokens(n)
        if not w:
            continue
        out += ["".join(w), "-".join(w), w[0], "".join(w[:2])]
    w0 = (core(name) or tokens(name) or [""])[0]
    out += [w0 + s for s in SUFFIXES] + ["ee" + w0]
    return [s for s in dict.fromkeys(out) if re.fullmatch(r"[a-z0-9][a-z0-9-]{1,60}", s)]


def name_score(company, board_name):
    c = set(core(company)) or set(tokens(company))
    b = set(tokens(board_name or ""))
    return round(len(c & b) / len(c), 2) if c and b else 0.0


def ee_count(items, keys):
    n = 0
    for it in items:
        loc = json.dumps([it.get(k) for k in keys], ensure_ascii=False)
        n += bool(EE.search(loc))
    return n


def jload(body):
    try:
        return json.loads(body)
    except ValueError:
        return None


def boards(slug):
    """Every vendor's answer for one slug: (vendor, board_name, jobs, ee, body-for-domain-check)."""
    found = []
    s, _, b = get(f"https://boards-api.greenhouse.io/v1/boards/{slug}")
    if s == 200 and (meta := jload(b)):
        jobs = (jload(get(f"https://boards-api.greenhouse.io/v1/boards/{slug}/jobs")[2]) or {}).get("jobs", [])
        found.append(("greenhouse", meta.get("name"), len(jobs), ee_count(jobs, ["location", "offices"]), b + json.dumps(jobs)))
    for host in ("api.lever.co", "api.eu.lever.co"):
        s, _, b = get(f"https://{host}/v0/postings/{slug}?mode=json")
        if s == 200 and isinstance(d := jload(b), list):
            found.append(("lever" + ("-eu" if ".eu." in host else ""), None, len(d), ee_count(d, ["categories", "country", "workplaceType"]), b))
    s, _, b = get(f"https://api.ashbyhq.com/posting-api/job-board/{slug}")
    if s == 200 and isinstance(d := jload(b), dict):
        jobs = d.get("jobs", [])
        found.append(("ashby", None, len(jobs), ee_count(jobs, ["location", "secondaryLocations", "address"]), b))
    s, _, b = get(f"https://{slug}.recruitee.com/api/offers/")
    if s == 200 and isinstance(d := jload(b), dict):
        offers = d.get("offers", [])
        nm = offers[0].get("company_name") if offers else None
        found.append(("recruitee", nm, len(offers), ee_count(offers, ["location", "country", "city", "locations"]), b))
    s, _, b = get(f"https://apply.workable.com/api/v1/widget/accounts/{slug}")
    if s == 200 and isinstance(d := jload(b), dict) and d.get("jobs"):
        jobs = d["jobs"]
        found.append(("workable", d.get("name"), len(jobs), ee_count(jobs, ["country", "city", "locations"]), b))
    for tld in ("de", "com"):
        s, _, b = get(f"https://{slug}.jobs.personio.{tld}/xml")
        if s == 200 and "<workzag-jobs" in b:
            offices = re.findall(r"<office>(.*?)</office>", b, re.S)
            sub = re.search(r"<subcompany>(.*?)</subcompany>", b, re.S)
            found.append(("personio", sub.group(1) if sub else None, b.count("<position>"), sum(bool(EE.search(o)) for o in offices), b))
            break
    s, u, b = get(f"https://{slug}.teamtailor.com/jobs.json")
    if s == 200 and isinstance(d := jload(b), dict) and slug in urllib.parse.urlsplit(u).netloc:
        items = d.get("items", [])
        home = get(f"https://{slug}.teamtailor.com/")[2]
        places = [{"loc": (i.get("_jobposting") or {}).get("jobLocation")} for i in items]   # schema.org Place(s)
        found.append(("teamtailor", d.get("title"), len(items), ee_count(places, ["loc"]), b + home))
    s, _, b = get(f"https://api.smartrecruiters.com/v1/companies/{slug}/postings?limit=100")
    if s == 200 and isinstance(d := jload(b), dict) and d.get("totalFound"):
        items = d.get("content", [])
        nm = next((p.get("company", {}).get("name") for p in items), None)
        found.append(("smartrecruiters", nm, d["totalFound"], sum(1 for p in items if (p.get("location") or {}).get("country") == "ee"), b))
    s, u, b = get(f"https://{slug}.teamdash.com/")
    if s == 200 and slug in urllib.parse.urlsplit(u).netloc and "teamdash" in b.lower():
        title = re.search(r"<title>(.*?)</title>", b, re.S | re.I)
        found.append(("teamdash", title.group(1).strip() if title else None, b.count("/p/job/") or None, 1, b))
    s, u, b = get(f"https://{slug}.bamboohr.com/careers/list")
    if s == 200 and isinstance(d := jload(b), dict) and slug in urllib.parse.urlsplit(u).netloc:
        res = d.get("result", [])
        found.append(("bamboohr", None, len(res), ee_count(res, ["location", "atsLocation"]), b + get(f"https://{slug}.bamboohr.com/careers")[2]))
    s, u, b = get(f"https://{slug}.recrur.com/public")
    if s == 200 and slug in urllib.parse.urlsplit(u).netloc:
        title = re.search(r"<title>(.*?)</title>", b, re.S | re.I)
        found.append(("recrur", title.group(1).strip() if title else None, None, 1, b))
    s, u, b = get(f"https://{slug}.breezy.hr/json")
    if s == 200 and isinstance(d := jload(b), list):
        found.append(("breezy", None, len(d), ee_count(d, ["location"]), b))
    return found


def one(row):
    cid, name, website = row[0], row[1], row[2]
    aliases = [a for a in (row[3].split("|") if len(row) > 3 and row[3] else []) if a]
    dom = domain_of(website)
    res = {"id": int(cid), "name": name, "website": website, "slugs": slugs(name, website, aliases), "hits": []}
    for s in res["slugs"]:
        for vendor, bname, jobs, ee, body in boards(s):
            res["hits"].append({"slug": s, "vendor": vendor, "board": bname, "jobs": jobs, "ee": ee,
                                "name": name_score(name, bname or ""), "slugname": name_score(name, s.replace("-", " ")),
                                "domain": bool(dom and dom in body.lower())})
    return res


if __name__ == "__main__":
    rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
    with Pool(int(sys.argv[3]) if len(sys.argv) > 3 else 4) as pool, open(sys.argv[2], "w", encoding="utf-8") as out:
        for r in pool.imap_unordered(one, rows):
            out.write(json.dumps(r, ensure_ascii=False) + "\n")
            out.flush()
