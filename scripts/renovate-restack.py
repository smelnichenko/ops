#!/usr/bin/env python3
"""renovate-restack.py - a Renovate PR whose branch conflicts with main re-made on main: its own line changes applied
to main's files again and its branch force-pushed as the bot. For the conflict two units make on one dependency (the
app wave's minor merged before the majors PR's major of the same package; two plugin bumps in one plugins block).

Refused - nothing pushed - unless every changed line is a one-for-one replacement, each made on main exactly as many
times as the PR makes it: the old line itself, or (the line moved on main since) the one(s) that are the old line but
for their version(s). Anything more is Renovate's (or a human's) to redo, never guessed here.

Usage: scripts/renovate-restack.py <repo> <pr>
Env:   RENOVATE_TOKEN (the bot's: its PR read, its branch pushed - never on a command line or in a URL);
       RESTACK_FORGEJO_URL (default https://git.pmon.dev/api/v1), RESTACK_GIT_URL (default https://git.pmon.dev),
       RESTACK_OWNER (default schnappy), RESTACK_DIR (default <ops>/.copy/restack - one clone per repo, reused)
Exit:  0 restacked; 1 refused (said why); 2 usage
"""
import json
import os
import re
import subprocess
import sys
import urllib.request
from collections import Counter

OPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = os.environ.get("RESTACK_FORGEJO_URL", "https://git.pmon.dev/api/v1").rstrip("/")
GIT = os.environ.get("RESTACK_GIT_URL", "https://git.pmon.dev").rstrip("/")
OWNER = os.environ.get("RESTACK_OWNER", "schnappy")
WORK = os.environ.get("RESTACK_DIR", os.path.join(OPS, ".copy", "restack"))
BOT = "renovate-bot"
MAIN = "origin/main"
# a version inside an escaped line (re.escape writes its dots as \. and its dashes as \-): 2\.63\.0, 25\.0\.1_8\-jre -
# its numeric parts, then suffixes: a dot suffix starts with a letter, so no two parts can match the same text (linear)
VERSION = re.compile(r"\d+(?:\\\.\d+)+(?:(?:\\-|_)[A-Za-z0-9]+|\\\.[A-Za-z][A-Za-z0-9]*)*")
ANY_VERSION = r"\d[\dA-Za-z._+-]*"


class Refused(Exception):
    pass


def token():
    t = os.environ.get("RENOVATE_TOKEN", "")
    if not t:
        raise Refused("RENOVATE_TOKEN is empty (ops/.env) - nothing read")
    return t


def git(d, *a, env):
    # the bot's credential handed to git by a helper reading the environment - never on a command line or in a URL
    helper = "credential.helper=!f() { test \"$1\" = get && printf 'username=renovate-bot\\npassword=%s\\n' \"$BOT_TOKEN\"; }; f"
    r = subprocess.run(["git", "-C", d, "-c", "credential.helper=", "-c", helper, *a], capture_output=True, text=True, env=env)
    if r.returncode != 0:
        raise Refused(f"git {a[0]} failed: {r.stderr.strip()[-300:]}")
    return r.stdout


def replaced(text, olds, news, name):
    """main's text with the PR's replacements made again (see the module's doc) - Refused when one is not on main the
    times the PR makes it."""
    if len(olds) != len(news) or not olds:
        raise Refused(f"{name} is not a one-for-one line replacement ({len(olds)} removed, {len(news)} added)")
    for (old, new), times in Counter(zip(olds, news)).items():
        for candidate in (re.escape(old), VERSION.sub(lambda _: ANY_VERSION, re.escape(old))):
            pattern = r"(?m)^" + candidate + r"$"
            if len(re.findall(pattern, text)) == times:
                text = re.sub(pattern, lambda _: new, text)
                break
        else:
            raise Refused(f"{name}: the replaced line is not on main the {times} time(s) the PR changes it "
                          f"(its version aside either): {old!r}")
    return text


def restack(repo, number):
    tok = token()
    env = {**os.environ, "GIT_TERMINAL_PROMPT": "0", "BOT_TOKEN": tok}
    req = urllib.request.Request(f"{API}/repos/{OWNER}/{repo}/pulls/{number}")
    req.add_unredirected_header("Authorization", f"token {tok}")  # never across a redirect
    with urllib.request.urlopen(req, timeout=60) as r:
        pr = json.loads(r.read())
    if pr.get("state") != "open" or (pr.get("user") or {}).get("login") != BOT:
        raise Refused(f"{repo}#{number} is not an open Renovate PR")
    if (pr.get("head") or {}).get("repo", {}).get("full_name", f"{OWNER}/{repo}") != f"{OWNER}/{repo}":
        raise Refused(f"{repo}#{number}'s branch is a fork's")
    branch, head = pr["head"]["ref"], pr["head"]["sha"]
    d = os.path.join(WORK, repo)
    if not os.path.isdir(os.path.join(d, ".git")):
        os.makedirs(WORK, exist_ok=True)
        r = subprocess.run(["git", "clone", "-q", f"{GIT}/{OWNER}/{repo}.git", d], capture_output=True, text=True, env=env)
        if r.returncode != 0:
            raise Refused(f"git clone failed: {r.stderr.strip()[-300:]}")
    git(d, "fetch", "-q", "origin", "+main:refs/remotes/origin/main", f"+refs/heads/{branch}:refs/remotes/origin/{branch}", env=env)
    if git(d, "rev-parse", f"origin/{branch}", env=env).strip() != head:
        raise Refused(f"{branch} moved since the PR was read")
    base = git(d, "merge-base", MAIN, f"origin/{branch}", env=env).strip()
    message = git(d, "log", "-1", "--format=%B", f"origin/{branch}", env=env).strip()
    files = git(d, "diff", "--name-only", base, f"origin/{branch}", env=env).split()
    git(d, "checkout", "-q", "-f", "-B", f"restack-{number}", MAIN, env=env)
    for name in files:
        diff = git(d, "diff", "-U0", base, f"origin/{branch}", "--", name, env=env)
        olds = [line[1:] for line in diff.splitlines() if line.startswith("-") and not line.startswith("---")]
        news = [line[1:] for line in diff.splitlines() if line.startswith("+") and not line.startswith("+++")]
        path = os.path.join(d, name)
        if not os.path.isfile(path):
            raise Refused(f"{name} is not on main")
        with open(path) as f:
            text = f.read()
        with open(path, "w") as f:
            f.write(replaced(text, olds, news, name))
        git(d, "add", "--", name, env=env)
    git(d, "-c", "user.name=Renovate Bot", "-c", "user.email=renovate-bot@pmon.dev", "commit", "-q", "-m", message, env=env)
    git(d, "push", "-q", f"--force-with-lease={branch}:{head}", "origin", f"HEAD:refs/heads/{branch}", env=env)
    return branch, git(d, "rev-parse", "--short", "HEAD", env=env).strip(), git(d, "rev-parse", "--short", MAIN, env=env).strip()


def main(argv):
    if len(argv) != 2 or not argv[1].isdigit():
        print("usage: scripts/renovate-restack.py <repo> <pr>", file=sys.stderr)
        return 2
    try:
        branch, new, main_sha = restack(argv[0], int(argv[1]))
    except Refused as e:
        print(f"REFUSED: {e}")
        return 1
    print(f"RESTACKED {argv[0]}#{argv[1]} {branch}: {new} on main {main_sha}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
