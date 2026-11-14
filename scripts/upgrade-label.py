#!/usr/bin/env python3
"""upgrade-label.py - the upgrade cycle's hands on a Renovate unit's pull requests (renovate/<unit> in infra, platform
and ops), as the renovate-bot (docs/plans/120-automated-upgrade-cycle.md):

  UNIT LABEL          the label on each of the unit's pull requests (made in the repo where missing)
  UNIT --comment TEXT the comment on each (the veto notice: "UPGRADE NOTICE <iso> ...")
  UNIT --merge        each merged - infra, platform, then ops - only when every one's head is green (its CI's status
                      success) and mergeable: one not, and none is merged (a unit goes in whole or not at all)

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


class Refused(Exception):
    pass


def call(method, path, body=None):
    req = urllib.request.Request(f"{API}{path}", method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": f"token {TOKEN}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return json.loads(raw) if raw.strip() else None
    except urllib.error.HTTPError as e:
        raise Refused(f"{method} {path}: {e.code} {e.read()[:200]!r}") from None
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise Refused(f"{method} {path}: {e}") from None


def prs(unit):
    found = []
    for repo in REPOS:
        for pr in call("GET", f"/repos/{repo}/pulls?state=open&limit=50") or []:
            if (pr.get("head") or {}).get("ref") == f"renovate/{unit}":
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


def merge(unit):
    found = prs(unit)
    for repo, pr in found:  # every one green and mergeable first: a unit goes in whole or not at all
        sha = pr["head"]["sha"]
        state = (call("GET", f"/repos/{repo}/commits/{sha}/status") or {}).get("state")
        if state != "success":
            raise Refused(f"{repo}#{pr['number']} not green (its CI: {state or 'none'}) - nothing merged")
        if pr.get("mergeable") is False:
            raise Refused(f"{repo}#{pr['number']} not mergeable - nothing merged")
    for repo, pr in sorted(found, key=lambda x: REPOS.index(x[0])):
        call("POST", f"/repos/{repo}/pulls/{pr['number']}/merge", {"Do": "merge", "delete_branch_after_merge": True})
        print(f"MERGED {repo}#{pr['number']}")


def main(argv):
    if len(argv) < 2 or not re.fullmatch(r"[a-z0-9][a-z0-9.-]*", argv[0]):
        print("usage: upgrade-label.py UNIT LABEL | UNIT --comment TEXT | UNIT --merge")
        return 2
    unit = argv[0]
    try:
        if argv[1:] == ["--merge"]:
            merge(unit)
        elif argv[1] == "--comment" and len(argv) == 3 and argv[2]:
            comment(unit, argv[2])
        elif len(argv) == 2 and re.fullmatch(r"[a-z0-9][a-z0-9-]*", argv[1]):
            label(unit, argv[1])
        else:
            print("usage: upgrade-label.py UNIT LABEL | UNIT --comment TEXT | UNIT --merge")
            return 2
    except Refused as e:
        print(f"REFUSED: {e}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
