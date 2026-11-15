#!/usr/bin/env python3
"""upgrade-units.py - the upgrade cycle's view of Renovate's units: its open pull requests on infra, platform and ops,
grouped by branch (renovate/<unit> - the same name in each repo).

  list           every unit: "<unit> <kind> <repos> <labels>" a line (kind: patch, minor, major)
  pick           the run's unit and what to do with it, one line - "PAUSED", "NOTHING", or "<action> <unit> <kind>":
                   test    a test environment's unit (renovate/test-<unit>: the copy leaves the test environment out -
                           it is its own proof), merged before its production twin - picked first, and the twin waits
                           while it is open
                   prove   a patch or minor unit (proven, then applied in the same run)
                   notice  a major with no veto notice yet (proven, then its 24 h notice posted - applied a later run)
                   apply   a major whose notice has run out, unvetoed (proven again, then applied)
                 A unit carrying the agent's fix (labelled agent-fixed by the runner) waits for its notice as a major
                 does, whatever its kind: what an agent wrote reaches production only after the operator was mailed it
                 and 24 h passed unvetoed.
                 The order: renovate/wave-patches, then the family minors (istio, kubernetes, cilium, observability,
                 data-operators, argocd, pi-services - the first three one minor at a time, named <family>-<X.Y>, the
                 lowest first), then any other minor (a <name>-<X.Y> one by its version), then majors - a waiting
                 major's notice before a new one's. Left out:
                 a unit labelled upgrade-blocked (red after its fix) or veto, a major in its 24 h; everything while the
                 dashboard issue carries upgrades-paused (the kill switch) - and no dashboard issue open: not read (exit 1)
  noticed UNIT   when the unit's veto notice was posted (the runner's latest "UPGRADE NOTICE <iso>" comment: a fix
                 noticed again starts its 24 h again), or "NONE"
  held UNIT      what holds the unit now, one a line - upgrade-blocked, veto (on any of its pull requests), paused (the
                 dashboard's upgrades-paused); nothing when nothing does: the runner asks again right before a merge
                 (a veto or the kill switch set during the proof and the review was not seen at the pick's time)

A unit is the bot's own pull requests, from branches of the repositories themselves - another account's, or a fork's,
named renovate/<unit> all the same, is no unit; a notice is the bot's own comment (anyone's backdated one skipped the
24 h veto).

Env: UPGRADE_FORGEJO_URL (default https://git.pmon.dev/api/v1), UPGRADE_FORGEJO_TOKEN (the renovate-bot's PAT),
     UPGRADE_NOW (an ISO time, for the harness). Exit 0 with an answer, 1 when Forgejo's answer was not read (the
     dashboard issue missing among them: pick and held fail closed without the kill switch).
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
BOT = "renovate-bot"
FAMILIES = ("istio", "kubernetes", "cilium", "observability", "data-operators", "argocd", "pi-services")
# a unit moved one minor at a time is named for its minor (renovate/upgrade-cycle.json: istio-1.32, scylladb-2026.3)
VERSIONED = re.compile(r"(?P<base>[a-z0-9][a-z0-9.-]*?)-(?P<major>\d+)\.(?P<minor>\d+)")
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
        except (OSError, ValueError) as e:  # URLError is an OSError
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


def ours(repo, pr):
    """The bot's own pull request, from a branch of the repository itself."""
    head_repo = ((pr.get("head") or {}).get("repo") or {}).get("full_name")
    return (pr.get("user") or {}).get("login") == BOT and head_repo == repo


def units():
    found = {}
    for repo in REPOS:
        for pr in get(f"/repos/{repo}/pulls", state="open"):
            ref = (pr.get("head") or {}).get("ref") or ""
            if not ref.startswith("renovate/") or not ours(repo, pr):
                continue
            name = ref[len("renovate/"):]
            u = found.setdefault(name, {"repos": {}, "labels": set()})
            u["repos"][repo] = pr["number"]
            u["labels"] |= {lb["name"] for lb in pr.get("labels") or []}
    for name, u in found.items():
        if "major" in u["labels"]:
            u["kind"] = "major"
        elif twin(name) == "wave-patches":
            u["kind"] = "patch"
        else:
            u["kind"] = "minor"
    return found


def twin(name):
    """The production unit a test environment's unit goes before (test-observability -> observability); itself else."""
    return name[len("test-"):] if name.startswith("test-") else name


def noticed(_name, u):
    """The latest runner notice on any of the unit's pull requests - a unit noticed again (its agent's fix, after its
    first notice) waits its 24 h from then: what was noticed first is not what applies."""
    times = []
    for repo, number in u["repos"].items():
        for c in get(f"/repos/{repo}/issues/{number}/comments"):
            if (c.get("user") or {}).get("login") != BOT:
                continue
            m = NOTICE.search(c.get("body") or "")
            if m:
                times.append(datetime.datetime.fromisoformat(m.group(1).replace("Z", "+00:00")))
    return max(times) if times else None


def paused():
    """The kill switch: the dashboard issue's upgrades-paused. No dashboard is not "not paused" - the switch is gone (the
    issue closed, renamed, Renovate's config changed), so nothing is read: the pick and held fail closed."""
    for issue in get("/repos/schnappy/ops/issues", state="open", type="issues"):
        if (issue.get("title") or "").startswith(DASHBOARD):
            return "upgrades-paused" in {lb["name"] for lb in issue.get("labels") or []}
    raise NotRead(f"no open issue titled {DASHBOARD!r} in schnappy/ops - the kill switch not read")


def family(name):
    """(the unit's family or name, its minor as numbers - () for a unit not named for one): istio-1.32 -> ("istio",
    (1, 32)); observability -> ("observability", ())."""
    m = VERSIONED.fullmatch(name)
    return (m["base"], (int(m["major"]), int(m["minor"]))) if m else (name, ())


def order(name, u):
    name = twin(name)
    if name == "wave-patches":
        return (0, 0, name, (), name)
    if u["kind"] == "minor":
        base, version = family(name)
        return (1, FAMILIES.index(base) if base in FAMILIES else len(FAMILIES), base, version, name)
    return (2, 0, name, (), name)


def waits_notice(u):
    """A major, or a unit with the agent's fix in it: applied only after a 24 h notice."""
    return u["kind"] == "major" or "agent-fixed" in u["labels"]


def pick():
    if paused():
        return "PAUSED"
    all_units = units()
    open_units = {n: u for n, u in all_units.items() if not ({"upgrade-blocked", "veto"} & u["labels"])}
    tests = sorted((n for n in open_units if n.startswith("test-")), key=lambda n: order(n, open_units[n]))
    if tests:
        return f"test {tests[0]} {open_units[tests[0]]['kind']}"
    # a production unit waits while its test environment's is open - blocked or vetoed too (its twin goes first)
    open_units = {n: u for n, u in open_units.items() if f"test-{n}" not in all_units}
    for name in sorted((n for n, u in open_units.items() if not waits_notice(u)), key=lambda n: order(n, open_units[n])):
        return f"prove {name} {open_units[name]['kind']}"
    majors = sorted(n for n, u in open_units.items() if waits_notice(u))
    waiting = []
    for name in majors:
        t = noticed(name, open_units[name])
        if t is None:
            continue
        if now() - t >= datetime.timedelta(hours=VETO_HOURS):
            waiting.append((t, name))
    if waiting:
        name = min(waiting)[1]
        return f"apply {name} {open_units[name]['kind']}"
    for name in majors:
        if noticed(name, open_units[name]) is None:
            return f"notice {name} {open_units[name]['kind']}"
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
        if len(argv) == 2 and argv[0] == "held":
            u = units().get(argv[1])
            if u is None:
                print(f"NO UNIT {argv[1]}")
                return 1
            for reason in sorted({"upgrade-blocked", "veto"} & u["labels"]):
                print(reason)
            if paused():
                print("paused")
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
    print("usage: upgrade-units.py list | pick | noticed UNIT | held UNIT")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
