#!/usr/bin/env python3
"""upgrade-label.py - the upgrade cycle's hands on a Renovate unit's pull requests (renovate/<unit> in infra, platform
and ops), as the renovate-bot:

  UNIT LABEL          the label on each of the unit's pull requests (made in the repo where missing)
  UNIT --comment TEXT the comment on each (the veto notice: "UPGRADE NOTICE <iso> ...")
  UNIT --heads        each pull request's head and its base branch's commit, "<repo> <number> <head> <base>" a line -
                      what the runner proves
  UNIT --green [SECONDS]
                      each head's CI status, "<repo>#<number> <state>" a line; exit 0 every one success, 4 one red
                      (failure, error: the unit breaks its own checks), 1 else - a running one waited for up to SECONDS
                      (default 0) (a red or running CI is hours of proof for a merge that is refused)
  UNIT --update       each pull request whose base moved past it: main merged into its branch (Forgejo's update, as the
                      bot) - a unit Renovate no longer rebases (stop-updating) brought onto main for its proof
  UNIT --diff-hash    a hash of what the unit changes (each pull request's changed lines and files, no context or
                      positions): its notice holds for this - a rebase onto a newer main keeps it, a newer release not
  UNIT --merge --expect FILE
                      each merged - infra, platform, then ops - only when every one's head is green (its CI's status
                      success), mergeable and still the commit FILE (--heads' lines) says was proven, its base branch
                      not moved since (a merge onto a newer main is a tree nobody proved) but by CD's app promotions
                      alone (scripts/cd-promotions.json: its author, its files, none the unit touches - infra's main
                      moves many times a day by those) - the same pull requests - each merged at that commit (Forgejo
                      refuses a head that moved): one not, and none is merged. A merge whose answer is lost is read
                      again until it shows (a refusal Forgejo answered: once); not known, or one failing after another
                      went in: PARTIAL, exit 3 - what went in said (half a unit may apply)
  --pause TEXT        the cycle paused: ops' dashboard issue labelled upgrades-paused (the pick's kill switch; the
                      issue made, under Renovate's own title, where none is open), TEXT its comment - a one-way
                      failure's durable mark (the runner's own record is a local file)
Only the bot's own pull requests, from a branch of the repository itself, are a unit's: another account's, or one from a
fork, named renovate/<unit> all the same, is never labelled, commented on or merged.

Env: UPGRADE_FORGEJO_URL (default https://git.pmon.dev/api/v1), UPGRADE_FORGEJO_TOKEN (the bot's PAT),
     UPGRADE_MERGE_READS (12) and UPGRADE_MERGE_WAIT (10 s): a lost merge answer read again that often, that far apart.
Exit 0 done, 1 refused or Forgejo's answer not read (nothing merged), 3 a merge partly done or not known, 4 red CI.
"""
import http.client
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

API = os.environ.get("UPGRADE_FORGEJO_URL", "https://git.pmon.dev/api/v1").rstrip("/")
TOKEN = os.environ.get("UPGRADE_FORGEJO_TOKEN", "")
REPOS = ("schnappy/infra", "schnappy/platform", "schnappy/ops")
BOT = "renovate-bot"
DASHBOARD = "Upgrade cycle - Renovate's dashboard"
# renovate/upgrade-cycle.json's dependencyDashboardTitle: the issue made under it is the one Renovate keeps
DASHBOARD_TITLE = "Upgrade cycle - Renovate's dashboard (label upgrades-paused: the cycle stops)"
CD_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cd-promotions.json")


class Refused(Exception):
    """Forgejo's no - definite when Forgejo itself answered it (an HTTP status), else its answer was not had."""

    def __init__(self, msg, definite=False):
        super().__init__(msg)
        self.definite = definite


class Partial(Exception):
    """Some of a unit's pull requests merged, then one did not."""


def call(method, path, body=None):
    req = urllib.request.Request(f"{API}{path}", method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json"})
    req.add_unredirected_header("Authorization", f"token {TOKEN}")  # not kept across a redirect
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return json.loads(raw) if raw.strip() else None
    except urllib.error.HTTPError as e:
        # a 4xx is Forgejo's own no; a 5xx is a gateway or Forgejo failing - the request may have gone through
        raise Refused(f"{method} {path}: {e.code} {e.read()[:200]!r}", definite=400 <= e.code < 500) from None
    except (OSError, ValueError, http.client.HTTPException) as e:  # URLError is an OSError; a cut body HTTPException
        raise Refused(f"{method} {path}: {e}") from None


def every(path):
    """Every page of a list endpoint (one page of 50 hid an older pull request: half a unit seen, half merged)."""
    out, page = [], 1
    sep = "&" if "?" in path else "?"
    while True:
        data = call("GET", f"{path}{sep}limit=50&page={page}") or []
        out += data
        if len(data) < 50:
            return out
        page += 1


def ours(repo, pr):
    """The bot's own pull request, from a branch of the repository itself."""
    head_repo = ((pr.get("head") or {}).get("repo") or {}).get("full_name")
    return (pr.get("user") or {}).get("login") == BOT and head_repo == repo


def prs(unit):
    found = []
    for repo in REPOS:
        for pr in every(f"/repos/{repo}/pulls?state=open"):
            if (pr.get("head") or {}).get("ref") == f"renovate/{unit}" and ours(repo, pr):
                found.append((repo, pr))
    if not found:
        raise Refused(f"no open pull request for renovate/{unit}")
    return found


def label(unit, name):
    for repo, pr in prs(unit):
        have = {lb["name"]: lb["id"] for lb in every(f"/repos/{repo}/labels")}
        if name not in have:
            have[name] = call("POST", f"/repos/{repo}/labels", {"name": name, "color": "#d93f0b"})["id"]
        call("POST", f"/repos/{repo}/issues/{pr['number']}/labels", {"labels": [have[name]]})
        print(f"LABELLED {repo}#{pr['number']} {name}")


def comment(unit, text):
    for repo, pr in prs(unit):
        call("POST", f"/repos/{repo}/issues/{pr['number']}/comments", {"body": text})
        print(f"COMMENTED {repo}#{pr['number']}")


def base_of(repo, pr):
    """The commit the pull request's base branch is at now."""
    ref = (pr.get("base") or {}).get("ref") or "main"
    return ((call("GET", f"/repos/{repo}/branches/{ref}") or {}).get("commit") or {}).get("id") or ""


def heads(unit):
    for repo, pr in prs(unit):
        print(f"{repo} {pr['number']} {pr['head']['sha']} {base_of(repo, pr)}")


def state(repo, sha):
    return (call("GET", f"/repos/{repo}/commits/{sha}/status") or {}).get("state")


class Red(Exception):
    """A head's CI finished red: the unit breaks its own checks."""


def green(unit, wait=0):
    """Every head's CI success - a running one waited for (up to wait seconds), a red one at once."""
    deadline = time.monotonic() + wait
    while True:
        states = [(f"{repo}#{pr['number']}", state(repo, pr["head"]["sha"]) or "none") for repo, pr in prs(unit)]
        red = [n for n, st in states if st in ("failure", "error")]
        if red:
            print("\n".join(f"{n} {st}" for n, st in states))
            raise Red(f"red: {', '.join(red)}")
        if all(st == "success" for _, st in states):
            print("\n".join(f"{n} {st}" for n, st in states))
            return
        if time.monotonic() >= deadline:
            print("\n".join(f"{n} {st}" for n, st in states))
            raise Refused(f"not green yet: {', '.join(n for n, st in states if st != 'success')}")
        time.sleep(float(os.environ.get("UPGRADE_GREEN_POLL", "60")))


def diff_hash(unit):
    print(unit_diff_hash(unit))


def update(unit):
    """Each pull request whose base moved past it brought up to date - main merged into its branch, by Forgejo, as the
    bot (a unit Renovate no longer rebases: stop-updating, the agent's fix on it). What it changes stays (its diff)."""
    for repo, pr in prs(unit):
        ref = (pr.get("base") or {}).get("ref") or "main"
        behind = (call("GET", f"/repos/{repo}/compare/{pr['head']['sha']}...{ref}") or {}).get("total_commits")
        if behind:
            call("POST", f"/repos/{repo}/pulls/{pr['number']}/update?style=merge")
            print(f"UPDATED {repo}#{pr['number']} ({behind} commit(s) of {ref} merged in)")


def unit_diff_hash(unit):
    """What the unit changes, independent of where its bases stand: each pull request's diff, its changed lines and
    file names alone (no context, no hunk positions), hashed - a notice holds for this, and for nothing else."""
    import hashlib
    h = hashlib.sha256()
    for repo, pr in sorted(prs(unit), key=lambda x: REPOS.index(x[0])):
        req = urllib.request.Request(f"{API}/repos/{repo}/pulls/{pr['number']}.diff")
        req.add_unredirected_header("Authorization", f"token {TOKEN}")
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                text = r.read().decode("utf-8", "replace")
        except (OSError, http.client.HTTPException) as e:
            raise Refused(f"{repo}#{pr['number']}'s diff: {e}") from None
        h.update(repo.encode() + b"\n")
        for line in text.splitlines():
            if line.startswith(("+++ ", "--- ")) or (line[:1] in "+-" and line[:1]):
                h.update(line.encode() + b"\n")
    return h.hexdigest()


def cd_only(repo, pr, proven_base, base):
    """The base branch moved since the proof by CD's app promotions alone (each commit its author's, its files CD's):
    the merged tree is the proven one plus app image tags production gets anyway - a unit that changes another line of
    CD's file merges beside them (Forgejo's mergeable, already required, says whether the two meet)."""
    try:
        with open(CD_FILE, encoding="utf-8") as f:
            cd = json.load(f)
    except (OSError, ValueError):
        return False
    paths = set((cd.get("paths") or {}).get(repo.split("/")[1], []))
    if not paths or (call("GET", f"/repos/{repo}/compare/{base}...{proven_base}") or {}).get("total_commits") != 0:
        return False  # no CD here, or the proven base no longer on the branch
    moved = call("GET", f"/repos/{repo}/compare/{proven_base}...{base}") or {}
    commits = moved.get("commits") or []
    if not commits or len(commits) != moved.get("total_commits"):
        return False  # a list cut short is no proof of what is in it
    for c in commits:
        files = {f.get("filename") for f in c.get("files") or []}
        if ((c.get("commit") or {}).get("author") or {}).get("email") != cd.get("author") or not files or files - paths:
            return False
    return True


def went_in(repo, number, definite, head="", base_ref="main"):
    """A merge whose POST failed: merged after all (True: the pull request says so, or its head is on the base branch
    already - a failure after the merge commit), not (False: Forgejo answered no, a 4xx, and both say so), or not
    known (None: its answer lost, or a 5xx, and it not merged after waiting, or not read)."""
    reads = 1 if definite else max(1, int(os.environ.get("UPGRADE_MERGE_READS", "12")))
    for i in range(reads):
        if i:
            time.sleep(float(os.environ.get("UPGRADE_MERGE_WAIT", "10")))
        try:
            if (call("GET", f"/repos/{repo}/pulls/{number}") or {}).get("merged"):
                return True
            # a 4xx refused it before anything moved; after a 5xx or no answer, its head on the base is a merge too
            if not definite and head and (call("GET", f"/repos/{repo}/compare/{base_ref}...{head}") or {}).get("total_commits") == 0:
                return True
        except Refused:
            continue
        else:
            if definite:
                return False
    return None


def read_expected(path):
    """--heads' lines: {repo: (number, sha)} - a line that is not one refused."""
    expected = {}
    try:
        lines = open(path).read().split("\n")
    except OSError as e:
        raise Refused(f"the proven heads not read ({path}: {e})") from None
    for line in filter(None, (x.strip() for x in lines)):
        parts = line.split()
        if (len(parts) != 4 or parts[0] not in REPOS or not parts[1].isdigit()
                or not all(re.fullmatch(r"[0-9a-f]{40}", x) for x in parts[2:])):
            raise Refused(f"the proven heads' line {line!r} is none")
        expected[parts[0]] = (int(parts[1]), parts[2], parts[3])
    if not expected:
        raise Refused(f"no proven head in {path}")
    return expected


def merge(unit, expected):
    found = prs(unit)
    if {repo: pr["number"] for repo, pr in found} != {repo: n for repo, (n, _, _) in expected.items()}:
        raise Refused(f"the unit's pull requests are not the ones proven ({sorted(r for r, _ in found)} against "
                      f"{sorted(expected)}) - nothing merged")
    for repo, pr in found:  # every one green, mergeable and the proven commit first: a unit goes in whole or not at all
        sha = pr["head"]["sha"]
        if sha != expected[repo][1]:
            raise Refused(f"{repo}#{pr['number']} moved since its proof ({expected[repo][1][:12]} proven, {sha[:12]} now) "
                          f"- nothing merged")
        st = state(repo, sha)
        if st != "success":
            raise Refused(f"{repo}#{pr['number']} not green (its CI: {st or 'none'}) - nothing merged")
        if pr.get("mergeable") is False:
            raise Refused(f"{repo}#{pr['number']} not mergeable - nothing merged")
        base = base_of(repo, pr)
        if base != expected[repo][2]:
            if not cd_only(repo, pr, expected[repo][2], base):
                raise Refused(f"{repo}'s {(pr.get('base') or {}).get('ref') or 'main'} moved since the proof "
                              f"({expected[repo][2][:12]} proven, {base[:12]} now) - nothing merged")
            print(f"BASE {repo}: moved since the proof by CD's app promotions alone ({expected[repo][2][:12]} -> {base[:12]})")
    merged = []
    try:
        for repo, pr in sorted(found, key=lambda x: REPOS.index(x[0])):
            try:
                call("POST", f"/repos/{repo}/pulls/{pr['number']}/merge",
                     {"Do": "merge", "delete_branch_after_merge": True, "head_commit_id": expected[repo][1]})
            except Refused as e:
                # its answer lost (a timeout, Forgejo restarting) is no proof it did not merge: read it again
                went = went_in(repo, pr["number"], e.definite, expected[repo][1], (pr.get("base") or {}).get("ref") or "main")
                if went:
                    merged.append(f"{repo}#{pr['number']}")
                    print(f"MERGED {repo}#{pr['number']} (its answer lost: {e})")
                    continue
                if merged or went is None:
                    raise Partial(f"merged {', '.join(merged) or 'nothing known'}; {repo}#{pr['number']} not"
                                  f"{' known' if went is None else ''}: {e}") from None
                raise
            merged.append(f"{repo}#{pr['number']}")
            print(f"MERGED {repo}#{pr['number']}")
    except (Partial, Refused):
        raise
    except Exception as e:  # anything else once a merge was asked for: what went in is not known - never "nothing"
        raise Partial(f"merged {', '.join(merged) or 'nothing known'}; then {e!r}") from None


def pause(text):
    have = {lb["name"]: lb["id"] for lb in every("/repos/schnappy/ops/labels")}
    if "upgrades-paused" not in have:
        have["upgrades-paused"] = call("POST", "/repos/schnappy/ops/labels",
                                       {"name": "upgrades-paused", "color": "#b60205"})["id"]
    for issue in every("/repos/schnappy/ops/issues?state=open&type=issues"):
        # the dashboard upgrade-units.py reads: Renovate's title exactly, the bot's issue - a label on another is unread
        if issue.get("title") == DASHBOARD_TITLE and (issue.get("user") or {}).get("login") == BOT:
            number = issue["number"]
            call("POST", f"/repos/schnappy/ops/issues/{number}/labels", {"labels": [have["upgrades-paused"]]})
            break
    else:  # none open (closed, renamed): made under Renovate's title - the kill switch never missing when it is pulled
        number = call("POST", "/repos/schnappy/ops/issues",
                      {"title": DASHBOARD_TITLE, "body": text, "labels": [have["upgrades-paused"]]})["number"]
        print(f"MADE schnappy/ops#{number} (no dashboard issue was open)")
    call("POST", f"/repos/schnappy/ops/issues/{number}/comments", {"body": text})
    print(f"PAUSED schnappy/ops#{number}")


USAGE = ("usage: upgrade-label.py UNIT LABEL | UNIT --comment TEXT | UNIT --heads | UNIT --green [SECONDS] | UNIT --diff-hash | "
         "UNIT --update | UNIT --merge --expect FILE | --pause TEXT")


def main(argv):
    if len(argv) == 2 and argv[0] == "--pause" and argv[1]:
        try:
            pause(argv[1])
        except Refused as e:
            print(f"REFUSED: {e}")
            return 1
        return 0
    if len(argv) < 2 or not re.fullmatch(r"[a-z0-9][a-z0-9.-]*", argv[0]):
        print(USAGE)
        return 2
    unit = argv[0]
    try:
        if argv[1:] == ["--heads"]:
            heads(unit)
        elif argv[1:2] == ["--green"] and len(argv) <= 3 and all(x.isdigit() for x in argv[2:]):
            green(unit, int(argv[2]) if len(argv) == 3 else 0)
        elif argv[1:] == ["--diff-hash"]:
            diff_hash(unit)
        elif argv[1:] == ["--update"]:
            update(unit)
        elif len(argv) == 4 and argv[1:3] == ["--merge", "--expect"]:
            merge(unit, read_expected(argv[3]))
        elif argv[1] == "--comment" and len(argv) == 3 and argv[2]:
            comment(unit, argv[2])
        elif len(argv) == 2 and re.fullmatch(r"[a-z0-9][a-z0-9-]*", argv[1]):
            label(unit, argv[1])
        else:
            print(USAGE)
            return 2
    except Partial as e:
        print(f"PARTIAL: {e}")
        return 3
    except Red as e:
        print(f"RED: {e}")
        return 4
    except Refused as e:
        print(f"REFUSED: {e}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
