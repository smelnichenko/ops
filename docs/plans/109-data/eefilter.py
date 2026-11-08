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

READ = {"greenhouse": gh, "greenhouse-eu": gh, "greenhouse-old": gh, "lever": lever,
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
