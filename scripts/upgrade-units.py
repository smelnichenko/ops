#!/usr/bin/env python3
"""upgrade-units.py - the upgrade cycle's view of Renovate's units (docs/plans/120-automated-upgrade-cycle.md, part 2):
its open pull requests on infra, platform and ops, grouped by branch (renovate/<unit> - the same name in each repo).

  list           every unit: "<unit> <kind> <repos> <labels>" a line (kind: patch, minor, major)
  pick           the night's unit and what to do with it, one line - "PAUSED", "NOTHING", or "<action> <unit> <kind>":
                   prove   a patch or minor unit (proven, then applied the same night)
                   notice  a major with no veto notice yet (proven, then its 24 h notice posted - applied a later night)
                   apply   a major whose notice has run out, unvetoed (proven again, then applied)
                 The order: renovate/wave-patches, then the family minors (istio, observability, data-operators, argocd,
                 pi-services), then any other minor, then majors - a waiting major's notice before a new one's. Left out:
                 a unit labelled upgrade-blocked (red after its fix) or veto, a major in its 24 h; everything while the
                 dashboard issue carries upgrades-paused (the kill switch).
  noticed UNIT   when the unit's veto notice was posted (the runner's "UPGRADE NOTICE <iso>" comment), or "NONE"

Env: UPGRADE_FORGEJO_URL (default https://git.pmon.dev/api/v1), UPGRADE_FORGEJO_TOKEN (the renovate-bot's PAT),
     UPGRADE_NOW (an ISO time, for the harness). Exit 0 with an answer, 1 when Forgejo's answer was not read.
"""
import datetime
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

API = os.environ.get("UPGRADE_FORGEJO_URL", "https://git.pmon.dev/api/v1").rstrip("/")
TOKEN = os.environ.get("UPGRADE_FORGEJO_TOKEN", "")
REPOS = ("schnappy/infra", "schnappy/platform", "schnappy/ops")
FAMILIES = ("istio", "observability", "data-operators", "argocd", "pi-services")
VETO_HOURS = 24
NOTICE = re.compile(r"^UPGRADE NOTICE (\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)\b", re.M)
DASHBOARD = "Upgrade cycle - Renovate's dashboard"


class NotRead(Exception):
    pass


def get(path, **params):
    """Every page of a list endpoint (or one object), as Forgejo answers it."""
    out, page = [], 1
    while True:
        q = urllib.parse.urlencode({**params, "page": page, "limit": 50})
        req = urllib.request.Request(f"{API}{path}?{q}")
        if TOKEN:  # not kept across a redirect: the token never reaches another host
            req.add_unredirected_header("Authorization", f"token {TOKEN}")
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                data = json.loads(r.read())
        except (urllib.error.URLError, OSError, ValueError) as e:
            raise NotRead(f"{path}: {e}") from None
        if not isinstance(data, list):
            return data
        out += data
        if len(data) < 50:
            return out
        page += 1


def now():
    v = os.environ.get("UPGRADE_NOW")
    return (datetime.datetime.fromisoformat(v.replace("Z", "+00:00")) if v
            else datetime.datetime.now(datetime.timezone.utc))


def units():
    found = {}
    for repo in REPOS:
        for pr in get(f"/repos/{repo}/pulls", state="open"):
            ref = (pr.get("head") or {}).get("ref") or ""
            if not ref.startswith("renovate/"):
                continue
            name = ref[len("renovate/"):]
            u = found.setdefault(name, {"repos": {}, "labels": set()})
            u["repos"][repo] = pr["number"]
            u["labels"] |= {lb["name"] for lb in pr.get("labels") or []}
    for name, u in found.items():
        u["kind"] = "major" if "major" in u["labels"] else ("patch" if name == "wave-patches" else "minor")
    return found


def noticed(name, u):
    """The earliest runner notice on any of the unit's pull requests."""
    times = []
    for repo, number in u["repos"].items():
        for c in get(f"/repos/{repo}/issues/{number}/comments"):
            m = NOTICE.search(c.get("body") or "")
            if m:
                times.append(datetime.datetime.fromisoformat(m.group(1).replace("Z", "+00:00")))
    return min(times) if times else None


def paused():
    for issue in get("/repos/schnappy/ops/issues", state="open", type="issues"):
        if (issue.get("title") or "").startswith(DASHBOARD):
            return "upgrades-paused" in {lb["name"] for lb in issue.get("labels") or []}
    return False


def order(name, u):
    if name == "wave-patches":
        return (0, name)
    if u["kind"] == "minor":
        return (1, FAMILIES.index(name) if name in FAMILIES else len(FAMILIES), name)
    return (2, name)


def pick():
    if paused():
        return "PAUSED"
    all_units = units()
    open_units = {n: u for n, u in all_units.items() if not ({"upgrade-blocked", "veto"} & u["labels"])}
    for name in sorted((n for n, u in open_units.items() if u["kind"] != "major"), key=lambda n: order(n, open_units[n])):
        return f"prove {name} {open_units[name]['kind']}"
    majors = sorted(n for n, u in open_units.items() if u["kind"] == "major")
    waiting = []
    for name in majors:
        t = noticed(name, open_units[name])
        if t is None:
            continue
        if now() - t >= datetime.timedelta(hours=VETO_HOURS):
            waiting.append((t, name))
    if waiting:
        return f"apply {min(waiting)[1]} major"
    for name in majors:
        if noticed(name, open_units[name]) is None:
            return f"notice {name} major"
    return "NOTHING"


def main(argv):
    try:
        if argv == ["list"]:
            for name, u in sorted(units().items()):
                print(f"{name} {u['kind']} {','.join(sorted(u['repos']))} {','.join(sorted(u['labels'])) or '-'}")
            return 0
        if argv == ["pick"]:
            print(pick())
            return 0
        if len(argv) == 2 and argv[0] == "noticed":
            u = units().get(argv[1])
            if u is None:
                print(f"NO UNIT {argv[1]}")
                return 1
            t = noticed(argv[1], u)
            print(t.strftime("%Y-%m-%dT%H:%M:%SZ") if t else "NONE")
            return 0
    except NotRead as e:
        print(f"NOT READ: Forgejo's answer - {e}")
        return 1
    print("usage: upgrade-units.py list | pick | noticed UNIT")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
