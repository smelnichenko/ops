"""Every board Common Crawl listed for a vendor, asked once: how many postings, how many located in Estonia, its name."""
import json, sys
from multiprocessing import Pool
sys.path.insert(0, __import__("os").path.dirname(__file__))
from guess import get, jload, ee_count

def gh(slug, host="boards-api.greenhouse.io"):
    meta = jload(get(f"https://{host}/v1/boards/{slug}")[2]) or {}
    jobs = (jload(get(f"https://{host}/v1/boards/{slug}/jobs")[2]) or {}).get("jobs", [])
    return meta.get("name"), len(jobs), ee_count(jobs, ["location", "offices"])

def lever(slug, host="api.lever.co"):
    d = jload(get(f"https://{host}/v0/postings/{slug}?mode=json")[2])
    d = d if isinstance(d, list) else []
    return None, len(d), ee_count(d, ["categories", "country"])

def tt(slug):
    d = jload(get(f"https://{slug}.teamtailor.com/jobs.json")[2]) or {}
    items = d.get("items", []) if isinstance(d, dict) else []
    return d.get("title") if isinstance(d, dict) else None, len(items), ee_count([{"l": (i.get("_jobposting") or {}).get("jobLocation")} for i in items], ["l"])

def ashby(slug):
    d = jload(get(f"https://api.ashbyhq.com/posting-api/job-board/{slug}")[2]) or {}
    jobs = d.get("jobs", []) if isinstance(d, dict) else []
    return None, len(jobs), ee_count(jobs, ["location", "secondaryLocations", "address"])

def recruitee(slug):
    d = jload(get(f"https://{slug}.recruitee.com/api/offers/")[2]) or {}
    offers = d.get("offers", []) if isinstance(d, dict) else []
    return (offers[0].get("company_name") if offers else None), len(offers), ee_count(offers, ["location", "country", "city", "locations"])

def bamboo(slug):
    d = jload(get(f"https://{slug}.bamboohr.com/careers/list")[2]) or {}
    res = d.get("result", []) if isinstance(d, dict) else []
    return None, len(res), ee_count(res, ["location", "atsLocation"])

def personio(slug, tld="de"):
    import re
    b = get(f"https://{slug}.jobs.personio.{tld}/xml")[2]
    if "<workzag-jobs" not in b:
        return None, 0, 0
    offices = re.findall(r"<office>(.*?)</office>", b, re.S)
    sub = re.search(r"<subcompany>(.*?)</subcompany>", b, re.S)
    from guess import EE
    return (sub.group(1) if sub else None), b.count("<position>"), sum(bool(EE.search(o)) for o in offices)

def workable(slug):
    d = jload(get(f"https://apply.workable.com/api/v1/widget/accounts/{slug}")[2]) or {}
    jobs = d.get("jobs", []) if isinstance(d, dict) else []
    return d.get("name") if isinstance(d, dict) else None, len(jobs), ee_count(jobs, ["country", "city", "locations"])

def smartr(slug):
    d = jload(get(f"https://api.smartrecruiters.com/v1/companies/{slug}/postings?limit=100&country=ee")[2]) or {}
    items = d.get("content", []) if isinstance(d, dict) else []
    nm = next((p.get("company", {}).get("name") for p in items), None)
    return nm, d.get("totalFound", 0) if isinstance(d, dict) else 0, sum(1 for p in items if (p.get("location") or {}).get("country") == "ee")

def breezy(slug):
    d = jload(get(f"https://{slug}.breezy.hr/json")[2])
    d = d if isinstance(d, list) else []
    return None, len(d), ee_count(d, ["location"])

READ = {"ashby": ashby, "recruitee": recruitee, "bamboohr": bamboo, "personio": personio,
        "personio-com": lambda s: personio(s, "com"), "workable": workable, "smartrecruiters": smartr, "breezy": breezy,
"greenhouse": gh, "greenhouse-eu": gh, "greenhouse-old": gh, "lever": lever,
        "levereu": lambda s: lever(s, "api.eu.lever.co"), "teamtailor": tt}

def one(job):
    vendor, slug = job
    try:
        name, n, ee = READ[vendor](slug)
    except Exception as e:  # noqa: BLE001 - a measurement
        return {"vendor": vendor, "slug": slug, "error": type(e).__name__}
    return {"vendor": vendor, "slug": slug, "name": name, "jobs": n, "ee": ee}

if __name__ == "__main__":
    lists = json.load(open(sys.argv[1]))
    done = set()
    try:
        for l in open(sys.argv[2]):
            r = json.loads(l); done.add((r["vendor"], r["slug"]))
    except FileNotFoundError:
        pass
    jobs = [(v, s) for v in sys.argv[3].split(",") for s in lists.get(v, []) if (v, s) not in done]
    print(len(jobs), "boards to ask", flush=True)
    with Pool(6) as pool, open(sys.argv[2], "a") as out:
        for r in pool.imap_unordered(one, jobs, chunksize=4):
            out.write(json.dumps(r, ensure_ascii=False) + "\n"); out.flush()
