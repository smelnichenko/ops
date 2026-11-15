#!/usr/bin/env python3
"""upgrade-label.py - the upgrade cycle's hands on a Renovate unit's pull requests (renovate/<unit> in infra, platform
and ops), as the renovate-bot (docs/plans/120-automated-upgrade-cycle.md):

  UNIT LABEL          the label on each of the unit's pull requests (made in the repo where missing)
  UNIT --comment TEXT the comment on each (the veto notice: "UPGRADE NOTICE <iso> ...")
  UNIT --heads        each pull request's head, "<repo> <number> <sha>" a line - what the runner proves
  UNIT --merge --expect FILE
                      each merged - infra, platform, then ops - only when every one's head is green (its CI's status
                      success), mergeable and still the commit FILE (--heads' lines) says was proven - the same pull
                      requests, none moved since - each merged at that commit (Forgejo refuses a head that moved): one
                      not, and none is merged (a unit goes in whole or not at all)
Only the bot's own pull requests, from a branch of the repository itself, are a unit's: another account's, or one from a
fork, named renovate/<unit> all the same, is never labelled, commented on or merged.

Env: UPGRADE_FORGEJO_URL (default https://git.pmon.dev/api/v1), UPGRADE_FORGEJO_TOKEN (the bot's PAT).
Exit 0 done, 1 refused or Forgejo's answer not read.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request

API = os.environ.get("UPGRADE_FORGEJO_URL", "https://git.pmon.dev/api/v1").rstrip("/")
TOKEN = os.environ.get("UPGRADE_FORGEJO_TOKEN", "")
REPOS = ("schnappy/infra", "schnappy/platform", "schnappy/ops")
BOT = "renovate-bot"


class Refused(Exception):
    pass


def call(method, path, body=None):
    req = urllib.request.Request(f"{API}{path}", method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json"})
    req.add_unredirected_header("Authorization", f"token {TOKEN}")  # not kept across a redirect
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return json.loads(raw) if raw.strip() else None
    except urllib.error.HTTPError as e:
        raise Refused(f"{method} {path}: {e.code} {e.read()[:200]!r}") from None
    except (OSError, ValueError) as e:  # URLError is an OSError
        raise Refused(f"{method} {path}: {e}") from None


def ours(repo, pr):
    """The bot's own pull request, from a branch of the repository itself."""
    head_repo = ((pr.get("head") or {}).get("repo") or {}).get("full_name")
    return (pr.get("user") or {}).get("login") == BOT and head_repo == repo


def prs(unit):
    found = []
    for repo in REPOS:
        for pr in call("GET", f"/repos/{repo}/pulls?state=open&limit=50") or []:
            if (pr.get("head") or {}).get("ref") == f"renovate/{unit}" and ours(repo, pr):
                found.append((repo, pr))
    if not found:
        raise Refused(f"no open pull request for renovate/{unit}")
    return found


def label(unit, name):
    for repo, pr in prs(unit):
        have = {lb["name"]: lb["id"] for lb in call("GET", f"/repos/{repo}/labels?limit=50") or []}
        if name not in have:
            have[name] = call("POST", f"/repos/{repo}/labels", {"name": name, "color": "#d93f0b"})["id"]
        call("POST", f"/repos/{repo}/issues/{pr['number']}/labels", {"labels": [have[name]]})
        print(f"LABELLED {repo}#{pr['number']} {name}")


def comment(unit, text):
    for repo, pr in prs(unit):
        call("POST", f"/repos/{repo}/issues/{pr['number']}/comments", {"body": text})
        print(f"COMMENTED {repo}#{pr['number']}")


def heads(unit):
    for repo, pr in prs(unit):
        print(f"{repo} {pr['number']} {pr['head']['sha']}")


def read_expected(path):
    """--heads' lines: {repo: (number, sha)} - a line that is not one refused."""
    expected = {}
    try:
        lines = open(path).read().split("\n")
    except OSError as e:
        raise Refused(f"the proven heads not read ({path}: {e})") from None
    for line in filter(None, (x.strip() for x in lines)):
        parts = line.split()
        if len(parts) != 3 or parts[0] not in REPOS or not parts[1].isdigit() or not re.fullmatch(r"[0-9a-f]{40}", parts[2]):
            raise Refused(f"the proven heads' line {line!r} is none")
        expected[parts[0]] = (int(parts[1]), parts[2])
    if not expected:
        raise Refused(f"no proven head in {path}")
    return expected


def merge(unit, expected):
    found = prs(unit)
    if {repo: pr["number"] for repo, pr in found} != {repo: n for repo, (n, _) in expected.items()}:
        raise Refused(f"the unit's pull requests are not the ones proven ({sorted(r for r, _ in found)} against "
                      f"{sorted(expected)}) - nothing merged")
    for repo, pr in found:  # every one green, mergeable and the proven commit first: a unit goes in whole or not at all
        sha = pr["head"]["sha"]
        if sha != expected[repo][1]:
            raise Refused(f"{repo}#{pr['number']} moved since its proof ({expected[repo][1][:12]} proven, {sha[:12]} now) "
                          f"- nothing merged")
        state = (call("GET", f"/repos/{repo}/commits/{sha}/status") or {}).get("state")
        if state != "success":
            raise Refused(f"{repo}#{pr['number']} not green (its CI: {state or 'none'}) - nothing merged")
        if pr.get("mergeable") is False:
            raise Refused(f"{repo}#{pr['number']} not mergeable - nothing merged")
    for repo, pr in sorted(found, key=lambda x: REPOS.index(x[0])):
        call("POST", f"/repos/{repo}/pulls/{pr['number']}/merge",
             {"Do": "merge", "delete_branch_after_merge": True, "head_commit_id": expected[repo][1]})
        print(f"MERGED {repo}#{pr['number']}")


def main(argv):
    if len(argv) < 2 or not re.fullmatch(r"[a-z0-9][a-z0-9.-]*", argv[0]):
        print("usage: upgrade-label.py UNIT LABEL | UNIT --comment TEXT | UNIT --heads | UNIT --merge --expect FILE")
        return 2
    unit = argv[0]
    try:
        if argv[1:] == ["--heads"]:
            heads(unit)
        elif len(argv) == 4 and argv[1:3] == ["--merge", "--expect"]:
            merge(unit, read_expected(argv[3]))
        elif argv[1] == "--comment" and len(argv) == 3 and argv[2]:
            comment(unit, argv[2])
        elif len(argv) == 2 and re.fullmatch(r"[a-z0-9][a-z0-9-]*", argv[1]):
            label(unit, argv[1])
        else:
            print("usage: upgrade-label.py UNIT LABEL | UNIT --comment TEXT | UNIT --heads | UNIT --merge --expect FILE")
            return 2
    except Refused as e:
        print(f"REFUSED: {e}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
