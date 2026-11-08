import re, sys, urllib.request
from multiprocessing import Pool
UA = "Mozilla/5.0 (compatible; masi-research/1.0)"
MARK = {"teamtailor": r"teamtailor", "teamdash": r"teamdash", "greenhouse": r"greenhouse\.io", "lever": r"lever\.co",
        "workable": r"workable\.com", "recruitee": r"recruitee", "personio": r"personio", "smartrecruiters": r"smartrecruiters",
        "jobvite": r"jobvite", "recrur": r"recrur", "sagehr": r"sage\.hr", "haileyhr": r"haileyhr", "bamboohr": r"bamboohr",
        "workday": r"myworkdayjobs|workday", "successfactors": r"successfactors|sapsf", "icims": r"icims", "eightfold": r"eightfold",
        "phenom": r"phenom", "jobylon": r"jobylon", "homerun": r"homerun\.co", "pinpoint": r"pinpointhq", "breezy": r"breezy\.hr",
        "comeet": r"comeet", "hibob": r"hibob", "ashby": r"ashbyhq", "rippling": r"rippling", "join": r"join\.com", "recman": r"recman",
        "webflow": r"webflow", "wordpress": r"wp-content"}
def one(host):
    try:
        req = urllib.request.Request("https://" + host + "/", headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=12) as r:
            body = r.read(2_000_000).decode("utf-8", "replace"); final = r.geturl(); st = r.status
    except Exception as e:
        return f"{host}\tERR {getattr(e,'code',type(e).__name__)}"
    hits = [v for v, rx in MARK.items() if re.search(rx, body + final, re.I)]
    return f"{host}\t{st}\t{final[:60]}\t{','.join(hits)}"
hosts = sys.argv[1:]
with Pool(4) as p:
    for line in p.imap(one, hosts): print(line)
