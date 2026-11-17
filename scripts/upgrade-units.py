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
                 --shadow (a shadow run's): the test environment's units left out - a shadow merges none, so a test
                 unit there is only a comment (no copy, no proof) and every shadow run would stop at it; the production
                 units in their order, a twin still waiting while its test unit is open.
                 A unit carrying the agent's fix (labelled agent-fixed by the runner) waits for its notice as a major
                 does, whatever its kind: what an agent wrote reaches production only after the operator was mailed it
                 and 24 h passed unvetoed.
                 The order: renovate/wave-patches, then the family minors (istio, gateway-api, kubernetes, cilium, observability,
                 data-operators, argocd, pi-services - the first three one minor at a time, named <family>-<X.Y>, the
                 lowest first), then any other minor (a <name>-<X.Y> one by its version), then majors - a waiting
                 major's notice before a new one's. Left out:
                 a manual- unit (renovate/manual-<unit>: what the copy cannot prove - Woodpecker - applied by hand),
                 a unit labelled upgrade-blocked (red after its fix) or veto, a major in its 24 h, a unit any of whose pull
                 requests lacks Renovate's own labels (upgrade-cycle, major, one-way: its kind not known - Forgejo applies
                 only labels a repo has); everything while the
                 dashboard issue carries upgrades-paused (the kill switch) - and no dashboard issue open: not read (exit 1)
  noticed UNIT   when the unit's veto notice was posted and the heads it announced (the runner's latest "UPGRADE
                 NOTICE <iso> heads=<repo>@<sha>,..." comment: a fix noticed again starts its 24 h again), "<iso>
                 <heads>", or "NONE" - the runner applies only those heads, main merged into them aside (git judges it);
                 anything else is noticed again
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
import base64
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
# gateway-api after istio (the operator, 2026-11-16): the control plane first, then the Gateway API it is proven with
FAMILIES = ("istio", "gateway-api", "kubernetes", "cilium", "observability", "data-operators", "argocd", "pi-services")
# a unit moved one minor at a time is named for its minor (renovate/upgrade-cycle.json: istio-1.32, scylladb-2026.3)
VERSIONED = re.compile(r"(?P<base>[a-z0-9][a-z0-9.-]*?)-(?P<major>\d+)\.(?P<minor>\d+)")
VETO_HOURS = 24
# the runner's comment starts with it - a line inside another comment of the bot's (Renovate posts as the same account,
# release notes quoted) is no notice
NOTICE = re.compile(r"UPGRADE NOTICE (\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)(?: heads=(\S+))?")
# renovate/upgrade-cycle.json's dependencyDashboardTitle - each repo's dashboard (all three extend the preset)
DASHBOARD = "Upgrade cycle - Renovate's dashboard (label upgrades-paused: the cycle stops)"
RENOVATE_LABELS = {"upgrade-cycle", "major", "one-way"}


class NotRead(Exception):
    pass


def get(path, paged=True, **params):
    """Every page of a list endpoint (or one object), as Forgejo answers it - one read of an endpoint that takes no
    pages (an issue's comments: every one at once, its page 2 the same list again - a loop with no end)."""
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
        if not isinstance(data, list) or not paged:
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
            u = found.setdefault(name, {"repos": {}, "labels": set(), "unlabelled": False})
            u["repos"][repo] = pr["number"]
            names = {lb["name"] for lb in pr.get("labels") or []} | renovate_labels(pr)
            u["labels"] |= names
            # Renovate's own labels on every pull request of it (the preset: upgrade-cycle, major, one-way - Forgejo
            # applies only labels the repo has): without them its kind, its one-way mark are not known
            u["unlabelled"] |= not names & RENOVATE_LABELS
    for name, u in found.items():
        if "major" in u["labels"]:
            u["kind"] = "major"
        elif twin(name) == "wave-patches":
            u["kind"] = "patch"
        else:
            u["kind"] = "minor"
    return found


def renovate_labels(pr):
    """The labels Renovate gave the pull request, as its own record in the body says (<!--renovate-debug:...-->) -
    Forgejo drops a label the repo did not have when the pull request was made, and Renovate, recording it as set,
    never adds it again: its record is what it decided."""
    m = re.search(r"<!--renovate-debug:([A-Za-z0-9+/=]+)-->", pr.get("body") or "")
    if not m:
        return set()
    try:
        record = json.loads(base64.b64decode(m.group(1), validate=True))
    except ValueError:  # not base64, not JSON (binascii.Error is a ValueError)
        return set()
    labels = record.get("labels") if isinstance(record, dict) else None
    return {x for x in labels if isinstance(x, str)} if isinstance(labels, list) else set()


def twin(name):
    """The production unit a test environment's unit goes before (test-observability -> observability); itself else."""
    return name[len("test-"):] if name.startswith("test-") else name


def noticed(_name, u):
    """The latest runner notice on any of the unit's pull requests, (its time, the heads it announced) - a unit noticed
    again (its agent's fix, after its first notice) waits its 24 h from then: what was noticed first is not what
    applies."""
    found = []
    for repo, number in u["repos"].items():
        for c in get(f"/repos/{repo}/issues/{number}/comments", paged=False):
            if (c.get("user") or {}).get("login") != BOT:
                continue
            m = NOTICE.match(c.get("body") or "")
            if m:
                found.append((datetime.datetime.fromisoformat(m.group(1).replace("Z", "+00:00")), m.group(2) or ""))
    return max(found) if found else None


def paused():
    """The kill switch: upgrades-paused on any of the three repos' dashboards (Renovate's issue: its title, the bot's).
    No dashboard in ops is not "not paused" - the switch is gone (the issue closed, renamed, Renovate's config changed),
    so nothing is read: the pick and held fail closed."""
    ops_seen = False
    for repo in REPOS:
        for issue in get(f"/repos/{repo}/issues", state="open", type="issues"):
            if issue.get("title") == DASHBOARD and (issue.get("user") or {}).get("login") == BOT:
                ops_seen |= repo == "schnappy/ops"
                if "upgrades-paused" in {lb["name"] for lb in issue.get("labels") or []}:
                    return True
    if not ops_seen:
        raise NotRead(f"no open issue titled {DASHBOARD!r} by {BOT} in schnappy/ops - the kill switch not read")
    return False


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
    """A major, a one-way change (ScyllaDB's release lines are minors by number), or a unit with the agent's fix in it:
    applied only after a 24 h notice."""
    return u["kind"] == "major" or bool({"agent-fixed", "one-way"} & set(u["labels"]))


def pick(shadow=False):
    if paused():
        return "PAUSED"
    all_units = units()
    # unlabelled (Renovate's labels not on it): never picked - a major unlabelled read as a minor, applied with no notice
    # a manual- unit (renovate/manual-woodpecker, the preset's): what the copy cannot prove - applied by hand, never picked
    open_units = {n: u for n, u in all_units.items() if not ({"upgrade-blocked", "veto"} & u["labels"]) and not u["unlabelled"]
                  and not n.startswith("manual-")}
    tests = sorted((n for n in open_units if n.startswith("test-")), key=lambda n: order(n, open_units[n]))
    if tests and not shadow:
        return f"test {tests[0]} {open_units[tests[0]]['kind']}"
    # a production unit waits while its test environment's is open - blocked or vetoed too (its twin goes first); a test
    # unit itself is never a production one (a shadow's pick reaches here with them open)
    open_units = {n: u for n, u in open_units.items() if f"test-{n}" not in all_units and not n.startswith("test-")}
    for name in sorted((n for n, u in open_units.items() if not waits_notice(u)), key=lambda n: order(n, open_units[n])):
        return f"prove {name} {open_units[name]['kind']}"
    return pick_noticed(open_units, sorted(n for n, u in open_units.items() if waits_notice(u)))


def pick_noticed(open_units, majors):
    """A major (or a unit carrying the agent's fix) whose notice ran out - the earliest noticed first; else one with no
    notice yet. Whether it applies what was noticed is the runner's to judge (the notice's heads, by git)."""
    notices = {name: noticed(name, open_units[name]) for name in majors}
    waiting = sorted((n[0], name) for name, n in notices.items() if n and now() - n[0] >= datetime.timedelta(hours=VETO_HOURS))
    if waiting:
        name = waiting[0][1]
        return f"apply {name} {open_units[name]['kind']}"
    for name in majors:
        if notices[name] is None:
            return f"notice {name} {open_units[name]['kind']}"
    return "NOTHING"


def show_list():
    for name, u in sorted(units().items()):
        print(f"{name} {u['kind']} {','.join(sorted(u['repos']))} {','.join(sorted(u['labels'])) or '-'}"
              + (" UNLABELLED" if u["unlabelled"] else ""))
    return 0


def show_pick(shadow=False):
    print(pick(shadow))
    return 0


def show_held(name):
    u = units().get(name)
    if u is None:
        print(f"NO UNIT {name}")
        return 1
    for reason in sorted({"upgrade-blocked", "veto"} & u["labels"]):
        print(reason)
    if paused():
        print("paused")
    return 0


def show_noticed(name):  # its time and the heads it announced
    u = units().get(name)
    if u is None:
        print(f"NO UNIT {name}")
        return 1
    n = noticed(name, u)
    if not n:
        print("NONE")
        return 0
    when, heads = n
    print(when.strftime("%Y-%m-%dT%H:%M:%SZ") + (f" {heads}" if heads else ""))
    return 0


def main(argv):
    commands = {("list",): show_list, ("pick",): show_pick, ("pick", "--shadow"): lambda: show_pick(shadow=True)}
    unit_commands = {"held": show_held, "noticed": show_noticed}
    try:
        if tuple(argv) in commands:
            return commands[tuple(argv)]()
        if len(argv) == 2 and argv[0] in unit_commands:
            return unit_commands[argv[0]](argv[1])
    except NotRead as e:
        print(f"NOT READ: Forgejo's answer - {e}")
        return 1
    print("usage: upgrade-units.py list | pick [--shadow] | noticed UNIT | held UNIT")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
