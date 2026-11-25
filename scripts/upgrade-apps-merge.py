#!/usr/bin/env python3
"""upgrade-apps-merge.py - the app repos' Renovate PRs driven to merged (the operator's decisions of 2026-11-20 and
2026-11-23: no PR left open for the operator, nothing left behind): round after round until none is pending.

Each round, every app repo, each open PR of the bot's (from the repo's own branch):
  green (its ci/ contexts - never Forgejo's combined state) and mergeable  merged at the head read (head_commit_id)
  green, not mergeable          brought onto main by Forgejo's update (CI runs again); a conflict (409) re-made on main
                                by scripts/renovate-restack.py, or reported CONFLICT
  red                           reported RED - fixed on its branch by hand (this never merges one)
  pending or no CI yet          waited for
Held, never merged:
  - while the upgrade run (scripts/upgrade-cycle.sh) is past its copy proof and its own merge has not landed: an app
    merge makes CD push infra's main, and that push landing with the run's merge lost a proven unit (2026-11-19, 409
    "cannot lock ref") - read from the run's own log (.copy/upgrade-cycle-*.log: no END yet, its review started, no
    MERGED after it)
  - masi: one merge per MASI_GAP seconds - its deploys cut long runs, a burst of them made sources stale (2026-11-09)
The run ends when nothing is pending (red and conflicted ones listed: mine to fix) - or after one round with --once.

Usage: scripts/upgrade-apps-merge.py [--once] [--every SECONDS]   (default 180)
Env:   RENOVATE_TOKEN (the bot's - it merges as the bot); UPGRADE_FORGEJO_URL (default https://git.pmon.dev/api/v1);
       APPS_MERGE_REPOS (space-separated, default the 13 app repos); APPS_MERGE_RUN_LOGS (glob, default
       <ops>/.copy/upgrade-cycle-*.log); MASI_GAP (default 1800); APPS_MERGE_RESTACK (the restack, for the harness)
Exit:  0 nothing pending; 1 Forgejo not read; 2 usage
"""
import glob
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

OPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = os.environ.get("UPGRADE_FORGEJO_URL", "https://git.pmon.dev/api/v1").rstrip("/")
OWNER = "schnappy"
BOT = "renovate-bot"
REPOS = os.environ.get("APPS_MERGE_REPOS", "admin ansible-lint chat chess ci-tools hyperfoil masi monitor radar "
                                           "radio-scheduler site sonar-scanner target-scorer").split()
RUN_LOGS = os.environ.get("APPS_MERGE_RUN_LOGS", os.path.join(OPS, ".copy", "upgrade-cycle-*.log"))
SPACED = {"masi": int(os.environ.get("MASI_GAP", "1800"))}
RESTACK = os.environ.get("APPS_MERGE_RESTACK", os.path.join(OPS, "scripts", "renovate-restack.py"))


def say(msg):
    print(time.strftime("%H:%M:%S"), msg, flush=True)


def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json"})
    req.add_unredirected_header("Authorization", "token " + os.environ["RENOVATE_TOKEN"])  # never across a redirect
    with urllib.request.urlopen(req, timeout=60) as r:
        raw = r.read()
        return json.loads(raw) if raw else None


def ci_state(repo, sha):
    """green, red, pending or none - the ci/ contexts' latest statuses alone"""
    latest = {}
    for s in call("GET", f"/repos/{OWNER}/{repo}/commits/{sha}/statuses?limit=50") or []:  # newest first
        latest.setdefault(s["context"], s["status"])
    states = [v for c, v in latest.items() if c.startswith("ci/")]
    if not states:
        return "none"
    if any(v in ("failure", "error") for v in states):
        return "red"
    return "green" if all(v == "success" for v in states) else "pending"


def run_holds():
    """The upgrade run between its review and its merge: its log (the newest) with no END line, its review started and
    no MERGED line after it."""
    logs = sorted(glob.glob(RUN_LOGS), key=os.path.getmtime)
    if not logs:
        return False
    with open(logs[-1], errors="replace") as f:
        text = f.read()
    if re.search(r"^\S+ \S+ END rc=\d+$", text, re.M):
        return False
    review = text.rfind("RUN claude -p")
    return review >= 0 and not re.search(r"^MERGED ", text[review:], re.M)


def open_prs(repo):
    prs = call("GET", f"/repos/{OWNER}/{repo}/pulls?state=open&limit=50") or []
    return sorted((p for p in prs if (p.get("user") or {}).get("login") == BOT
                   and ((p.get("head") or {}).get("repo") or {}).get("full_name") == f"{OWNER}/{repo}"),
                  key=lambda p: p["number"])


def unstick(repo, number, tag):
    """A green PR Forgejo cannot merge: main merged into it (CI again), or on a conflict re-made on main - True while it
    is pending again; False when it is reported (a conflict the restack refuses: to fix on its branch)."""
    try:
        call("POST", f"/repos/{OWNER}/{repo}/pulls/{number}/update?style=merge")
        say(f"UPDATED onto main (CI again) {tag}")
        return True
    except urllib.error.HTTPError as e:
        if e.code != 409:
            say(f"UPDATE REFUSED (HTTP {e.code}) {tag}")
            return False
    r = subprocess.run([sys.executable, "-I", RESTACK, repo, str(number)],
                       capture_output=True, text=True)
    last = ((r.stdout + r.stderr).strip().splitlines() or ["no output"])[-1]
    say(f"RESTACKED {tag}" if r.returncode == 0 else f"CONFLICT ({last}) {tag}")
    return r.returncode == 0


def handle(repo, p, last_merge):
    """One PR: True while it is still pending (waited for, updated, held), False when merged or reported."""
    pr = call("GET", f"/repos/{OWNER}/{repo}/pulls/{p['number']}")
    sha, tag = pr["head"]["sha"], f"{repo}#{p['number']} {pr['title'][:70]}"
    state = ci_state(repo, sha)
    if state == "red":
        say(f"RED {tag}")
        return False
    if state != "green":
        return True
    if not pr.get("mergeable"):
        return unstick(repo, p["number"], tag)
    if repo in SPACED and time.time() - last_merge.get(repo, 0) < SPACED[repo]:
        return True
    if run_holds():
        say(f"held - the upgrade run is between its review and its merge: {tag}")
        return True
    try:
        call("POST", f"/repos/{OWNER}/{repo}/pulls/{p['number']}/merge",
             {"Do": "merge", "head_commit_id": sha, "delete_branch_after_merge": True})
    except urllib.error.HTTPError as e:
        say(f"MERGE REFUSED (HTTP {e.code}) {tag}")
        return True
    say(f"MERGED {tag}")
    last_merge[repo] = time.time()
    return False


def one_round(last_merge):
    pending = 0
    for repo in REPOS:
        for p in open_prs(repo):
            pending += handle(repo, p, last_merge)
    return pending


def main(argv):
    once = "--once" in argv
    every = int(argv[argv.index("--every") + 1]) if "--every" in argv else 180
    if not os.environ.get("RENOVATE_TOKEN"):
        print("REFUSED: RENOVATE_TOKEN is empty (ops/.env)", file=sys.stderr)
        return 2
    last_merge = {}
    while True:
        try:
            left = one_round(last_merge)
        except OSError as e:  # urllib's URLError is one
            say(f"Forgejo not read: {e}")
            if once:
                return 1
            left = -1
        if left == 0:
            say("DONE - nothing pending (RED and CONFLICT ones above are to fix on their branches)")
            return 0
        say(f"round done: {left} pending" if left > 0 else "round lost - again")
        if once:
            return 0
        time.sleep(every)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
