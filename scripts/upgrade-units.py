#!/usr/bin/env python3
"""upgrade-units.py - the upgrade cycle's view of Renovate's units: its open pull requests on infra, platform and ops,
grouped by branch (renovate/<unit> - the same name in each repo).

  list           every unit: "<unit> <kind> <repos> <labels>" a line (kind: patch, minor, major)
  pick           the run's unit and what to do with it, one line - "PAUSED", "NOTHING", or "<action> <unit> <kind>":
                   test    a test environment's unit (renovate/test-<unit>: the copy leaves the test environment out -
                           it is its own proof), merged before its production twin - picked first, and the twin waits
                           while it is open
                   prove   any other unit, patch, minor or major alike (proven, reviewed - compatibility among the
                           passes - then applied in the same run; no notice, no waiting: operator 2026-11-21)
                 STEPS: a unit never goes while a lower step of the same dependency is open - postgres-19.x waits for
                 postgres-18.x, kubernetes-1.37 for kubernetes-1.36, scylladb-2026.3 for scylladb-2026.2 - whatever
                 holds the lower one (a try on record, unlabelled): an upgrade that needs several steps takes
                 them one at a time, the next one rebased by Renovate onto the step before. The same dependency is
                 known by its name AND by the packages in Renovate's table (a family's minors and its major are named
                 apart: scylladb-2026.3 and scylladb-scylla-2027.x move one package) - a major or minor unit waits
                 while another (the patch wave aside) moves one of its packages to a lower version; a test- unit waits
                 for the production unit of a lower step too (the test environment one step ahead at most). To skip a
                 step (not needed, or failing for good) the operator closes its pull requests - Renovate then ignores
                 that version.
                 The order: renovate/wave-patches, then the family minors (istio, gateway-api, kubernetes, cilium, observability,
                 data-operators, argocd, pi-services - the first three one minor at a time, named <family>-<X.Y>, the
                 lowest first), then any other minor (a <name>-<X.Y> one by its version), then majors - the units with
                 a try on record (the runner's .upgrade-cycle/tries) after the ones with none (no blocked state: one
                 that keeps failing never holds the queue - except the higher steps of its own dependency). Left out:
                 a manual- unit (renovate/manual-<unit>: what the copy cannot prove - Woodpecker - applied by hand),
                 a unit any of whose pull
                 requests lacks Renovate's own labels (upgrade-cycle, major, one-way: its kind not known - Forgejo applies
                 only labels a repo has); everything while the
                 dashboard issue carries upgrades-paused (the kill switch) - and no dashboard issue open: not read (exit 1)
  bodies UNIT DIR  each of the unit's pull requests' body written to DIR/<repo>.pr.md (infra.pr.md, ...): Renovate's
                 table and release notes - what the review's compatibility pass reads
  replenish      one unit's pull requests asked of Renovate when nothing open is left to pick - "PAUSED", "OPEN" (a
                 unit to pick is open: nothing asked), "NOTHING" (none waits either), or "APPROVED <unit> <repos>": the
                 dashboards hold every update for approval (dependencyDashboardApproval), and the unit the pick would
                 take first among the ones waiting - the same order, steps and test twins - gets its box ticked on
                 every dashboard that lists it, as the bot; Renovate's next run opens its pull requests. So only the
                 unit being worked on exists as pull requests (operator 2026-11-24: dozens open were noise). The
                 runner runs Renovate itself before and after (task upgrade:run); the body is written whole with the
                 one box changed, and nothing else writes the dashboard while the run holds the copy lock
  held UNIT      what holds the unit now - paused (the dashboard's upgrades-paused, the kill switch: no per-unit hold,
                 no veto since 2026-11-27, the operator's); nothing when nothing does: the runner asks again right
                 before a merge (the kill switch set during the proof and the review was not seen at the pick's time)

A unit is the bot's own pull requests, from branches of the repositories themselves - another account's, or a fork's,
named renovate/<unit> all the same, is no unit.

Env: UPGRADE_FORGEJO_URL (default https://git.pmon.dev/api/v1), UPGRADE_FORGEJO_TOKEN (the renovate-bot's PAT),
     UPGRADE_TRIES (the tries' directory, for the harness). Exit 0 with an answer, 1 when Forgejo's answer was not read (the
     dashboard issue missing among them: pick and held fail closed without the kill switch).
"""
import base64
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
# a step of an upgrade path: <dependency>-<version>[.x] - postgres-18.x, kube-prometheus-stack-93.x (Renovate's major
# lines, separateMultipleMajor), kubernetes-1.37, scylladb-2026.3 (the preset's one-minor-at-a-time families)
STEP = re.compile(r"(?P<base>[a-z0-9][a-z0-9.-]*?)-(?P<ver>\d+(?:\.\d+)*)(?:\.x)?")
# renovate/upgrade-cycle.json's dependencyDashboardTitle - each repo's dashboard (all three extend the preset)
DASHBOARD = "Upgrade cycle - Renovate's dashboard (label upgrades-paused: the cycle stops)"
RENOVATE_LABELS = {"upgrade-cycle", "major", "one-way"}
# the answers pick and replenish share
PAUSED, NOTHING = "PAUSED", "NOTHING"
# the runner's tries, one file a unit (scripts/upgrade-cycle.sh retry): a unit with one on record goes behind the units
# with none - there is no blocked state (operator 2026-11-20), so one that keeps failing never holds the queue
TRIES = os.environ.get("UPGRADE_TRIES",
                       os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".upgrade-cycle", "tries"))


class NotRead(Exception):
    pass


# a box the dashboard holds for approval (Renovate's markdown: "- [ ] <!-- approve-branch=renovate/<unit> -->...")
APPROVE = re.compile(r"^(?P<pre>[ \t]*- )\[ \](?P<post> <!-- approve-branch=renovate/(?P<unit>[a-z0-9][a-z0-9.-]*) -->)",
                     re.M)


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


def patch(path, payload):
    """One PATCH as the bot, its answer read - or NotRead."""
    req = urllib.request.Request(f"{API}{path}", data=json.dumps(payload).encode(), method="PATCH",
                                 headers={"Content-Type": "application/json"})
    if TOKEN:  # not kept across a redirect: the token never reaches another host
        req.add_unredirected_header("Authorization", f"token {TOKEN}")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read() or b"null")
    except (OSError, ValueError) as e:
        raise NotRead(f"{path}: {e}") from None


def ours(repo, pr):
    """The bot's own pull request, from a branch of the repository itself."""
    head_repo = ((pr.get("head") or {}).get("repo") or {}).get("full_name")
    return (pr.get("user") or {}).get("login") == BOT and head_repo == repo


def add_pr(found, repo, pr):
    """the bot's pull request on renovate/<unit>, into its unit"""
    ref = (pr.get("head") or {}).get("ref") or ""
    if not ref.startswith("renovate/") or not ours(repo, pr):
        return
    u = found.setdefault(ref[len("renovate/"):], {"repos": {}, "labels": set(), "unlabelled": False, "bodies": {}})
    u["repos"][repo] = pr["number"]
    u["bodies"][repo] = pr.get("body") or ""
    names = {lb["name"] for lb in pr.get("labels") or []} | renovate_labels(pr)
    u["labels"] |= names
    # Renovate's own labels on every pull request of it (the preset: upgrade-cycle, major, one-way - Forgejo applies
    # only labels the repo has): without them its kind, its one-way mark are not known
    u["unlabelled"] |= not names & RENOVATE_LABELS


def kind_of(name, u):
    if "major" in u["labels"]:
        return "major"
    return "patch" if twin(name) == "wave-patches" else "minor"


def units():
    found = {}
    for repo in REPOS:
        for pr in get(f"/repos/{repo}/pulls", state="open"):
            add_pr(found, repo, pr)
    for name, u in found.items():
        u["kind"] = kind_of(name, u)
    return found


def renovate_labels(pr):
    """The labels Renovate gave the pull request, as its own record in the body says (<!--renovate-debug:...-->) -
    Forgejo drops a label the repo did not have when the pull request was made, and Renovate, recording it as set,
    never adds it again: its record is what it decided."""
    # Renovate appends its own record at the body's end: the last one is its (a copy in the release notes above it is not)
    found = re.findall(r"<!--renovate-debug:([A-Za-z0-9+/=]+)-->", pr.get("body") or "")
    if not found:
        return set()
    try:
        record = json.loads(base64.b64decode(found[-1], validate=True))
    except ValueError:  # not base64, not JSON (binascii.Error is a ValueError)
        return set()
    labels = record.get("labels") if isinstance(record, dict) else None
    return {x for x in labels if isinstance(x, str)} if isinstance(labels, list) else set()


def twin(name):
    """The production unit a test environment's unit goes before (test-observability -> observability); itself else."""
    return name[len("test-"):] if name.startswith("test-") else name


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


def step(name):
    """(the dependency, its version as numbers) for a unit that is a step of an upgrade path - test- units their own
    path; None for a unit that is none (observability, wave-patches)."""
    m = STEP.fullmatch(name)
    return (m["base"], tuple(int(x) for x in m["ver"].split("."))) if m else None


def numbers(version):
    return tuple(int(x) for x in re.findall(r"\d+", version))


def package(cell):
    """a table row's package, one name wherever it is written (docker.io/scylladb/scylla is scylladb/scylla)"""
    name = re.match(r"\[?([^\]]+)", cell).group(1).strip()
    return re.sub(r"^(docker\.io/)?(library/)?", "", name)


def table_rows(body):
    """{column: cell} of each row of the body's first table (Renovate's own: | Package | Update | Change |, the columns
    found by their headers) - one in the release notes below it is upstream's text, never read"""
    cols, rows = None, 0
    for line in body.splitlines():
        if not line.startswith("|"):
            if rows:
                return
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if "Package" in cells and "Change" in cells:
            cols = {c: i for i, c in enumerate(cells)}
        elif cols and len(cells) >= len(cols) and not set(cells[0]) <= {"-", ":"}:
            rows += 1
            yield {c: cells[i] for c, i in cols.items()}


def table_steps(u):
    """{package: the version it moves to, as numbers} for each major or minor row of the unit's pull requests' tables -
    two rows of one package (a minor and a major): its highest target."""
    found = {}
    for body in u.get("bodies", {}).values():
        for row in table_rows(body):
            values = re.findall(r"`([^`]+)`", row["Change"])
            if row.get("Update", "") in ("major", "minor") and values:
                pkg = package(row["Package"])
                found[pkg] = max(found.get(pkg, ()), numbers(values[-1]))
    return found


def lower_step_open(name, all_units):
    """Another open unit of the same dependency at a lower version - this step waits for it, whatever holds it: by its
    name (postgres-18.x for postgres-19.x; for a test- unit its production one's too), and by the packages it moves."""
    mine = step(name)
    if mine:
        bases = {mine[0]} | ({mine[0][len("test-"):]} if mine[0].startswith("test-") else set())
        if any(o != name and (s := step(o)) and s[0] in bases and s[1] < mine[1] for o in all_units):
            return True
    # a patch row is no step (table_steps reads major and minor rows alone): the wave never holds a step, nor waits for one
    moves = table_steps(all_units.get(name) or {})
    for o, ou in all_units.items():
        if o == name or twin(o) == twin(name):  # its twin: the test unit first, by the twin rule - never a deadlock
            continue
        theirs = table_steps(ou)
        if any(pkg in theirs and theirs[pkg] < v for pkg, v in moves.items()):
            return True
    return False


def tried(name, u):
    """A try on record for this unit's pull requests: a line of .upgrade-cycle/tries/<unit> whose key is them
    ("repo#number,..." in any order) - or a key with no "#" (its pull requests not read, the test environment's merge
    that did not settle): the unit's whatever its pull requests. Another unit of the name before (other pull requests)
    is not this one."""
    if not re.fullmatch(r"[a-z0-9][a-z0-9.-]*", name):
        return False
    try:
        lines = open(os.path.join(TRIES, name), encoding="utf-8").read().split("\n")
    except OSError:
        return False
    mine = {f"{repo}#{n}" for repo, n in u["repos"].items()}
    keys = (line.split(" ", 1)[0] for line in lines)
    return any(k and ("#" not in k or set(k.split(",")) == mine) for k in keys)


def pick():
    if paused():
        return PAUSED
    all_units = units()
    # unlabelled (Renovate's labels not on it): never picked - a major unlabelled read as a minor, applied with no notice
    # a manual- unit (renovate/manual-woodpecker, the preset's): what the copy cannot prove - applied by hand, never picked
    # no per-unit hold: a label (veto, upgrade-blocked) holds nothing - the kill switch stops all, a bad unit is fixed
    open_units = {n: u for n, u in all_units.items() if not u["unlabelled"] and not n.startswith("manual-")}
    # the units with a try on record after the ones with none, each group in its order
    def queue(n):
        return (tried(n, open_units[n]), order(n, open_units[n]))
    # a step waits for the lower steps of its dependency - against every open unit, pickable or not (a failing or
    # unlabelled postgres-18.x never lets postgres-19.x jump it)
    open_units = {n: u for n, u in open_units.items() if not lower_step_open(n, all_units)}
    tests = sorted((n for n in open_units if n.startswith("test-")), key=queue)
    # a production unit waits while its test environment's is open - tried or not (its twin goes first); a test
    # unit itself is never a production one
    prod = sorted((n for n in open_units if f"test-{n}" not in all_units and not n.startswith("test-")), key=queue)
    # tests first - unless the first has a try and a production unit has none (one that keeps failing never holds the
    # queue: no blocked state)
    if tests and not (tried(tests[0], open_units[tests[0]]) and prod and not tried(prod[0], open_units[prod[0]])):
        return f"test {tests[0]} {open_units[tests[0]]['kind']}"
    for name in prod:
        return f"prove {name} {open_units[name]['kind']}"
    return NOTHING


def dashboards():
    """Each repo's dashboard issue (Renovate's: its title, the bot's), {repo: issue}."""
    found = {}
    for repo in REPOS:
        for issue in get(f"/repos/{repo}/issues", state="open", type="issues"):
            if issue.get("title") == DASHBOARD and (issue.get("user") or {}).get("login") == BOT:
                found[repo] = issue
    return found


def pending_kind(name):
    """A waiting unit's kind before its pull requests carry Renovate's labels, by its name: the waves, a major line
    (hashicorp-vault-2.x), a minor else - for the order alone; the pick reads the labels once its pull requests open."""
    name = twin(name)
    if name == "wave-patches":
        return "patch"
    return "major" if name == "wave-majors" or re.fullmatch(r".*-\d+\.x", name) else "minor"


def replenish():
    if paused():
        return PAUSED
    if pick() != NOTHING:
        return "OPEN"
    boards = dashboards()
    waiting = {}
    for repo, issue in boards.items():
        for m in APPROVE.finditer(issue.get("body") or ""):
            waiting.setdefault(m["unit"], []).append(repo)
    # a manual- unit is applied by hand, never asked for here; a step waits for a lower one waiting or open
    shaped = {n: {"repos": dict.fromkeys(rs, 0), "labels": set(), "unlabelled": False, "bodies": {},
                  "kind": pending_kind(n)} for n, rs in waiting.items() if not n.startswith("manual-")}
    known = {**units(), **shaped}
    ready = {n: u for n, u in shaped.items() if not lower_step_open(n, known)}
    tests = sorted((n for n in ready if n.startswith("test-")), key=lambda n: order(n, ready[n]))
    prod = sorted((n for n in ready if not n.startswith("test-") and f"test-{n}" not in known),
                  key=lambda n: order(n, ready[n]))
    chosen = (tests or prod or [None])[0]
    if chosen is None:
        return NOTHING
    for repo in waiting[chosen]:
        issue = boards[repo]
        body = issue.get("body") or ""
        box = next(m for m in APPROVE.finditer(body) if m["unit"] == chosen)
        body = body[:box.start()] + box["pre"] + "[x]" + box["post"] + body[box.end():]
        patch(f"/repos/{repo}/issues/{issue['number']}", {"body": body})
    return f"APPROVED {chosen} {','.join(r.split('/')[1] for r in waiting[chosen])}"


def show_replenish():
    print(replenish())
    return 0


def show_list():
    for name, u in sorted(units().items()):
        print(f"{name} {u['kind']} {','.join(sorted(u['repos']))} {','.join(sorted(u['labels'])) or '-'}"
              + (" UNLABELLED" if u["unlabelled"] else ""))
    return 0


def show_pick():
    print(pick())
    return 0


def show_held(name):
    u = units().get(name)
    if u is None:
        print(f"NO UNIT {name}")
        return 1
    if paused():
        print("paused")
    return 0


def show_bodies(name, out_dir):
    """Each of the unit's pull requests' body to <out_dir>/<repo>.pr.md - Renovate's table and release notes."""
    u = units().get(name)
    if u is None:
        print(f"NO UNIT {name}")
        return 1
    for repo, body in sorted(u["bodies"].items()):
        path = os.path.join(out_dir, f"{repo.split('/')[-1]}.pr.md")
        with open(path, "w", encoding="utf-8") as f:
            f.write(body)
        print(path)
    return 0


def show_moves(name):
    """What the unit moves, from its pull requests' tables: '<package> <from> <to>' a line, each once (patch, minor,
    major and digest rows - a digest's from and to its first 7 hex digits) - the copy's inventory after the change must
    show production's lines of it at the new version (scripts/copy-change-inventory.sh)."""
    u = units().get(name)
    if u is None:
        print(f"NO UNIT {name}")
        return 1
    seen = []
    for body in u.get("bodies", {}).values():
        for row in table_rows(body):
            values = re.findall(r"`([^`]+)`", row.get("Change", ""))
            line = f"{package(row['Package'])} {values[0]} {values[-1]}" if len(values) >= 2 else ""
            if row.get("Update", "") in ("major", "minor", "patch", "digest") and line and line not in seen:
                seen.append(line)
    print("\n".join(seen))
    return 0


def main(argv):
    commands = {("list",): show_list, ("pick",): show_pick, ("replenish",): show_replenish}
    try:
        if tuple(argv) in commands:
            return commands[tuple(argv)]()
        if len(argv) == 2 and argv[0] == "held":
            return show_held(argv[1])
        if len(argv) == 3 and argv[0] == "bodies":
            return show_bodies(argv[1], argv[2])
        if len(argv) == 2 and argv[0] == "moves":
            return show_moves(argv[1])
    except NotRead as e:
        print(f"NOT READ: Forgejo's answer - {e}")
        return 1
    print("usage: upgrade-units.py list | pick | replenish | held UNIT | bodies UNIT DIR | moves UNIT")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
