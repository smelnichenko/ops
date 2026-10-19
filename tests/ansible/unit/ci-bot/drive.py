"""The ci-bot harness's cases (run.sh starts it): the REAL setup-ci-bot.yml run by ansible-playbook against a fake
Forgejo and a fake Vault (fakeforgejo.py, fakevault.py - the real community.hashi_vault modules talk to it), a
watch over every process's command line (argvwatch.py), curl & co fenced; then seed-vault-secrets.yml's own two
woodpecker-ci tasks against the same Vault.
argv: <ansible-playbook> <work dir>. Prints PASS/FAIL lines and "ci-bot: ALL-PASS" or "ci-bot: N FAILED".
"""
import atexit
import copy
import json
import os
import re
import secrets
import signal
import subprocess
import sys
import time
import urllib.request

import yaml

AP, W = sys.argv[1], sys.argv[2]
ROOT = os.getcwd()
H = os.path.join(ROOT, "tests/ansible/unit/ci-bot")
PB = os.path.join(ROOT, "deploy/ansible/playbooks/setup-ci-bot.yml")
SEED = os.path.join(ROOT, "deploy/ansible/playbooks/seed-vault-secrets.yml")
BOT, ORG, VIP = "woodpecker-ci", "schnappy", "192.168.11.5"
# an admin password a shell would run (quotes, $( ), backticks, a colon): no shell ever sees it
ADMIN_PW = "adm'\"$(touch " + W + "/ran)`touch " + W + "/ran2`\\:pw"
VAULT_TOKEN = "hvs.TEST" + secrets.token_hex(12)
ADMIN_INFRA, ADMIN_CLONE, READONLY = (secrets.token_hex(20) for _ in range(3))
CANARY = "canary" + secrets.token_hex(8)
fails = 0
procs = []
# the fakes and the watch end with this, however it ends (timeout(1)'s TERM included)
atexit.register(lambda: [p.kill() for p in procs])
signal.signal(signal.SIGTERM, lambda *_: sys.exit(124))


def check(name, got, want):
    global fails
    ok = got == want
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"\n    got  {got}\n    want {want}"))


def start(script, *args):
    portfile = os.path.join(W, os.path.basename(script) + ".port")
    p = subprocess.Popen([sys.executable, os.path.join(H, script), portfile, *args])
    procs.append(p)
    for _ in range(200):
        if os.path.exists(portfile) and open(portfile).read():
            return int(open(portfile).read())
        time.sleep(0.02)
    sys.exit(f"ci-bot: {script} did not start")


def http(port, method, path, body=None):
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", method=method,
                                 data=json.dumps(body).encode() if body is not None else None)
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)


open(os.path.join(W, "root-token"), "w").write(VAULT_TOKEN + "\n")
FP = start("fakeforgejo.py")
VP = start("fakevault.py", os.path.join(W, "root-token"))
forgejo = lambda m, p, b=None: http(FP, m, p, b)  # noqa: E731
vault = lambda m, p, b=None: http(VP, m, p, b)  # noqa: E731

# fenced: what would put a secret on a command line, or reach a real host - each call logged, exit 97
FENCE = os.path.join(W, "fence")
os.mkdir(FENCE)
for tool in ("curl", "wget", "forgejo", "gitea", "vault", "http", "ssh", "kubectl"):
    with open(os.path.join(FENCE, tool), "w") as f:
        f.write(f'#!/bin/sh\necho "{tool} $*" >> "{W}/fence.log"\nexit 97\n')
    os.chmod(os.path.join(FENCE, tool), 0o755)
# the Pi: `ip` saying it holds the VIP (tasks/pi-vip-holder.yml asks), through its own interpreter's PATH
PI = os.path.join(W, "pi")
os.mkdir(PI)
with open(os.path.join(PI, "ip"), "w") as f:
    f.write(f'#!/bin/sh\necho "2: eth0    inet {VIP}/24 scope global secondary eth0"\n')
os.chmod(os.path.join(PI, "ip"), 0o755)
PYW = os.path.join(W, "py-pi1")
with open(PYW, "w") as f:
    f.write(f'#!/bin/sh\nPATH="{PI}:{FENCE}:$PATH" exec "{os.path.dirname(AP)}/python3" "$@"\n')
os.chmod(PYW, 0o755)
if not os.access(os.path.join(os.path.dirname(AP), "python3"), os.X_OK):
    with open(PYW, "w") as f:
        f.write(f'#!/bin/sh\nPATH="{PI}:{FENCE}:$PATH" exec python3 "$@"\n')
INV = os.path.join(W, "inv.yml")
yaml.safe_dump({"all": {"children": {"pis": {"hosts": {"pi1": {
    "ansible_connection": "local", "ansible_python_interpreter": PYW, "ansible_become": False}}}}}}, open(INV, "w"))
# the play's settings on a file (a value on ansible-playbook's command line is on its argv)
VARS = os.path.join(W, "vars.yml")
yaml.safe_dump({"keepalived_vip": VIP, "forgejo_admin_user": "forgejo_admin", "forgejo_admin_password": ADMIN_PW,
                "forgejo_api": f"http://127.0.0.1:{FP}/api/v1", "vault_addr": f"http://127.0.0.1:{VP}",
                "vault_ca_cert": os.path.join(W, "no-ca.pem"), "vault_root_token_file": os.path.join(W, "root-token")},
               open(VARS, "w"))
FIXED = os.path.join(W, "fixed-secrets")
open(FIXED, "w").write("\n".join([ADMIN_PW, VAULT_TOKEN, ADMIN_INFRA, ADMIN_CLONE, READONLY, CANARY]) + "\n")
WATCH_OUT = os.path.join(W, "watch.json")
watch = subprocess.Popen([sys.executable, os.path.join(H, "argvwatch.py"), str(FP), FIXED, WATCH_OUT])
procs.append(watch)
COLL = ":".join([os.path.join(ROOT, "deploy/ansible/collections"), os.path.expanduser("~/.ansible/collections"),
                 "/usr/share/ansible/collections"])
ENV = {k: v for k, v in os.environ.items() if not k.startswith(("ANSIBLE_", "WOODPECKER_", "FORGEJO_"))}
ENV.update(PATH=FENCE + ":" + os.environ["PATH"], ANSIBLE_NOCOLOR="1", ANSIBLE_PIPELINING="1",
           ANSIBLE_COLLECTIONS_PATH=COLL, ANSIBLE_HOST_KEY_CHECKING="0", ANSIBLE_RETRY_FILES_ENABLED="0",
           ANSIBLE_LOCAL_TEMP=os.path.join(W, "ansible-local"), ANSIBLE_REMOTE_TEMP=os.path.join(W, "ansible-remote"))


def run(*args, env=None, play=PB):
    r = subprocess.run([AP, "-i", INV, play, "-e", "@" + VARS, *args], capture_output=True, text=True, cwd=W,
                       env=dict(ENV, **(env or {})))
    return r.returncode, r.stdout + r.stderr


def tail(out):
    return "\n".join(x for x in out.splitlines() if "REFUSED" in x or "fatal" in x or "msg" in x)[-600:]


def fixture():
    users = {
        "forgejo_admin": {"id": 1, "login": "forgejo_admin", "email": "admin@pmon.dev", "password": ADMIN_PW,
                          "is_admin": True, "prohibit_login": False, "active": True, "must_change_password": False},
        "sm": {"id": 2, "login": "sm", "email": "sm@x", "password": "sm-pw", "is_admin": False,
               "prohibit_login": False, "active": True, "must_change_password": False},
    }
    every = {u: "owner" for u in ("repo.code", "repo.packages", "repo.issues", "repo.pulls")}
    teams = {
        "1": {"id": 1, "name": "Owners", "description": "", "permission": "owner", "units_map": every,
              "includes_all_repositories": True, "can_create_org_repo": True, "members": ["sm"], "repos": []},
        "4": {"id": 4, "name": "schnappy-team", "description": "", "permission": "read",
              "units_map": {u: "read" for u in every}, "includes_all_repositories": True,
              "can_create_org_repo": False, "members": ["sm"], "repos": []},
    }
    tok = lambda i, name, sha1, scopes: (str(i), {"id": i, "user": "forgejo_admin", "name": name, "sha1": sha1,  # noqa
                                                  "token_last_eight": sha1[-8:], "scopes": scopes})
    tokens = dict([tok(10, "woodpecker-infra", ADMIN_INFRA, ["read:repository", "write:repository"]),
                   tok(11, "woodpecker-clone", ADMIN_CLONE, ["read:repository"]),
                   tok(12, "argocd-readonly", READONLY, ["read:repository"])])
    repos = {r: {"private": True} for r in ("infra", "admin", "chat", "chess", "masi", "monitor", "platform", "site")}
    repos["handbook"] = {"private": False}
    return {"seq": 100, "org": ORG, "users": users, "teams": teams, "tokens": tokens, "repos": repos}


VAULT_REST = {"renovate_token": "renovate-xyz", "sonar_token": "sonar-abc", "nexus_url": f"http://{VIP}:8081",
              "custom_extra": "keep-me"}
VAULT_FIXTURE = {"schnappy/woodpecker-ci": {"data": dict(VAULT_REST, infra_repo_token=ADMIN_INFRA,
                                                         clone_token=ADMIN_CLONE), "version": 3}}


def reset(state=None, kv=None):
    forgejo("POST", "/_reset", state or fixture())
    vault("POST", "/_reset", copy.deepcopy(VAULT_FIXTURE if kv is None else kv))
    for f in ("ran", "ran2"):
        if os.path.exists(os.path.join(W, f)):
            os.remove(os.path.join(W, f))


def fstate():
    return forgejo("GET", "/_state")


def kv():
    return vault("GET", "/_state")


def bot_tokens(s):
    return sorted((t for t in s["state"]["tokens"].values() if t["user"] == BOT), key=lambda t: t["id"])


def scope_view(s):
    """The bot's account and teams as the run should leave them (its password aside)."""
    st = s["state"]
    u = st["users"].get(BOT, {})
    teams = {t["name"]: (t["permission"], t["units_map"], t["includes_all_repositories"], t["can_create_org_repo"],
                         sorted(t["repos"]), sorted(t["members"])) for t in st["teams"].values()
             if t["name"] in ("ci", "ci-clone")}
    return ({k: u.get(k) for k in ("is_admin", "must_change_password", "prohibit_login", "active")}, teams)


def bot_rights(st):
    """The repositories the bot pushes to and administers, from every team it is in (as Forgejo computes them)."""
    push, admin = set(), set()
    for r in st["repos"]:
        for t in st["teams"].values():
            if BOT in t["members"] and (t["includes_all_repositories"] or r in t["repos"]):
                m = "owner" if t["permission"] in ("owner", "admin") else t["units_map"].get("repo.code", "none")
                if m in ("write", "admin", "owner"):
                    push.add(r)
                if m in ("admin", "owner"):
                    admin.add(r)
    return sorted(push), sorted(admin)


WANT_SCOPE = ({"is_admin": False, "must_change_password": False, "prohibit_login": False, "active": True},
              {"ci": ("write", {"repo.code": "write", "repo.packages": "write"}, False, False, ["infra"], [BOT]),
               "ci-clone": ("read", {"repo.code": "read"}, False, False, ["admin", "chat", "chess", "masi"], [BOT])})
WANT_KINDS = [("infra", ["write:repository"]), ("registry", ["write:package"]), ("clone", ["read:repository"])]


def kinds(toks):
    return [(t["name"].split("-")[1], t["scopes"]) for t in toks]


def vault_expect(toks, rest=VAULT_REST):
    by = {t["name"].split("-")[1]: t["sha1"] for t in toks}
    return dict(rest, infra_repo_token=by["infra"], registry_token=by["registry"], clone_token=by["clone"],
                registry_user=BOT)


# ── setup-ci-bot.yml: first run, from production's state today ───────────────────────────────────────────────────
reset()
rc, out = run()
s, v = fstate(), kv()
toks = bot_tokens(s)
check("first run: passes", (rc, tail(out) if rc else ""), (0, ""))
check("first run: the bot is no admin (no must-change, may log in) - its teams' scope exactly: ci code+packages write "
      "on infra alone, ci-clone code read on admin chat chess masi, no repository made, each holding the bot alone",
      scope_view(s), WANT_SCOPE)
check("first run: three tokens on the bot, each its scope alone (infra write:repository, registry write:package, "
      "clone read:repository), named ci-<use>-<UTC time>",
      (kinds(toks), all(re.match(r"^ci-(infra|registry|clone)-\d{8}T\d{6}$", t["name"]) for t in toks)),
      (WANT_KINDS, True))
check("first run: minted as the bot (basic auth), never as the admin",
      sorted({str(e["auth"]) for e in s["log"] if e["method"] == "POST" and e["path"].endswith("/tokens")}),
      [str(["basic", BOT])])
check("first run: Vault holds the bot's tokens and name, every other property kept as it was, one write with the "
      "version read (cas 3)",
      (v["kv"]["schnappy/woodpecker-ci"]["data"], v["kv"]["schnappy/woodpecker-ci"]["version"],
       [w["cas"] for w in v["writes"]]), (vault_expect(toks), 4, [3]))
check("first run: the admin's tokens untouched (retired only on --tags retire)",
      sorted(t["name"] for t in s["state"]["tokens"].values() if t["user"] == "forgejo_admin"),
      ["argocd-readonly", "woodpecker-clone", "woodpecker-infra"])
check("first run: what the bot can do, as Forgejo computes it from its teams: push on infra alone, admin nowhere",
      bot_rights(s["state"]), (["infra"], []))
first_ids = {t["name"]: t["id"] for t in s["state"]["teams"].values()}

# ── a rerun: the same account and teams; new tokens, the ones Vault held kept, older ones deleted ────────────────
time.sleep(1.1)  # a new second: the next run's token names
rc, out = run()
s2, v2 = fstate(), kv()
toks2 = bot_tokens(s2)
check("rerun: passes, the account and the teams as they were (same teams, not made again)",
      (rc, scope_view(s2), {t["name"]: t["id"] for t in s2["state"]["teams"].values()}), (0, WANT_SCOPE, first_ids))
check("rerun: the run-1 tokens kept (Vault held them - the cluster's Secret may still), three new ones, Vault on the "
      "new ones, every other property still kept",
      ([t["id"] for t in toks2[:3]], kinds(toks2[3:]), v2["kv"]["schnappy/woodpecker-ci"]["data"]),
      ([t["id"] for t in toks], WANT_KINDS, vault_expect(toks2[3:])))
time.sleep(1.1)
rc, out = run()
s3, v3 = fstate(), kv()
toks3 = bot_tokens(s3)
check("third run: steady - run 1's tokens deleted, run 2's kept, three new; account and teams unchanged",
      (rc, [t["id"] for t in toks3[:3]], kinds(toks3[3:]), len(toks3), scope_view(s3),
       v3["kv"]["schnappy/woodpecker-ci"]["data"] == vault_expect(toks3[3:])),
      (0, [t["id"] for t in toks2[3:]], WANT_KINDS, 6, WANT_SCOPE, True))

# ── drift fixed or refused ──────────────────────────────────────────────────────────────────────────────────────
st = s3["state"]
st["users"][BOT]["is_admin"] = True
st["users"][BOT]["must_change_password"] = True
ci = next(t for t in st["teams"].values() if t["name"] == "ci")
ci["repos"].append("platform")
ci["includes_all_repositories"] = True
ci["can_create_org_repo"] = True
ci["units_map"]["repo.pulls"] = "write"
reset(st, {"schnappy/woodpecker-ci": {"data": v3["kv"]["schnappy/woodpecker-ci"]["data"], "version": 6}})
rc, out = run()
check("drift: a bot made admin by hand is made a user again; a team given another repository, every repository, "
      "repository creation or another unit is put back to its own scope", (rc, scope_view(fstate())), (0, WANT_SCOPE))

for label, edit, said in (
        ("a team of that name with someone else in it (sm in ci)",
         lambda st: next(t for t in st["teams"].values() if t["name"] == "ci")["members"].append("sm"),
         "REFUSED: team schnappy/ci holds sm"),
        ("the bot put in Owners by hand (push and admin everywhere)",
         lambda st: st["teams"]["1"]["members"].append(BOT), "REFUSED: woodpecker-ci pushes to")):
    st = copy.deepcopy(s3["state"])
    edit(st)
    reset(st, {"schnappy/woodpecker-ci": {"data": v3["kv"]["schnappy/woodpecker-ci"]["data"], "version": 6}})
    rc, out = run()
    s4, v4 = fstate(), kv()
    check(f"refused: {label} - said; no token minted, Vault not written",
          (rc != 0, said in out, len(bot_tokens(s4)), v4["writes"]), (True, True, 6, []))

# ── a failure after a mint: the new tokens deleted again, Vault unchanged ────────────────────────────────────────
for label, fault in (
        ("Vault's version moved on between the read and the write (cas refused)",
         ("vault", {"method": "POST", "path": "woodpecker-ci", "status": 400,
                    "error": "check-and-set parameter did not match the current version"})),
        ("the second token's mint fails", ("forgejo", {"method": "POST", "path": "/users/woodpecker-ci/tokens$",
                                                        "status": 500, "nth": 2})),
        ("the registry token's proof fails", ("forgejo", {"method": "GET", "path": "^/api/v1/packages/", "status": 404})),
):
    reset(copy.deepcopy(s3["state"]), {"schnappy/woodpecker-ci": {"data": v3["kv"]["schnappy/woodpecker-ci"]["data"],
                                                                   "version": 6}})
    (vault if fault[0] == "vault" else forgejo)("POST", "/_fail", fault[1])
    rc, out = run()
    s5, v5 = fstate(), kv()
    check(f"failure: {label} - fails, said; this run's tokens deleted again (the bot's as before), Vault unchanged",
          (rc != 0, "this run's new tokens deleted again" in out, [t["id"] for t in bot_tokens(s5)],
           v5["kv"]["schnappy/woodpecker-ci"]),
          (True, True, [t["id"] for t in toks3], {"data": v3["kv"]["schnappy/woodpecker-ci"]["data"], "version": 6}))

# ── Vault: a sealed one refuses, a missing path is a first install ───────────────────────────────────────────────
reset()
vault("POST", "/_fail", {"method": "GET", "path": "woodpecker-ci", "status": 503, "error": "Vault is sealed"})
rc, out = run()
check("Vault sealed: fails before any token is minted, nothing written",
      (rc != 0, bot_tokens(fstate()), kv()["writes"]), (True, [], []))
reset(kv={})
rc, out = run()
s6, v6 = fstate(), kv()
check("Vault path missing (a first install): the four written create-only (cas 0)",
      (rc, v6["kv"].get("schnappy/woodpecker-ci", {}).get("data"), [w["cas"] for w in v6["writes"]]),
      (0, vault_expect(bot_tokens(s6), rest={}), [0]))

# ── no preview ───────────────────────────────────────────────────────────────────────────────────────────────────
reset()
rc, out = run("--check")
check("--check: refused, nothing changed", (rc != 0, "no check mode" in out, BOT in fstate()["state"]["users"],
                                            kv()["writes"]), (True, True, False, []))

# ── retiring the admin's CI tokens ──────────────────────────────────────────────────────────────────────────────
RETIRE_ENV = {"WOODPECKER_INFRA_REPO_TOKEN": ADMIN_INFRA, "WOODPECKER_CLONE_TOKEN": " " + ADMIN_CLONE + " "}
admin_names = lambda s: sorted(t["name"] for t in s["state"]["tokens"].values() if t["user"] == "forgejo_admin")  # noqa
reset()
rc, out = run("--tags", "retire", env=RETIRE_ENV)
check("retire before the bot's tokens are in Vault: refused, nothing deleted",
      (rc != 0, "REFUSED" in out, admin_names(fstate())), (True, True, ["argocd-readonly", "woodpecker-clone",
                                                                       "woodpecker-infra"]))
rc, out = run()
st, vv = fstate(), kv()
rc, out = run("--tags", "retire", env=RETIRE_ENV)
s7 = fstate()
check("retire after setup: the admin's two CI tokens (as .env names them, whatever their names) deleted, its "
      "others kept; the bot's tokens, the account and Vault untouched",
      (rc, admin_names(s7), [t["id"] for t in bot_tokens(s7)], kv() == vv, scope_view(s7)),
      (0, ["argocd-readonly"], [t["id"] for t in bot_tokens(st)], True, WANT_SCOPE))
rc, out = run("--tags", "retire", env=RETIRE_ENV)
check("retire again: nothing left to delete - passes", (rc, admin_names(fstate())), (0, ["argocd-readonly"]))
reset(copy.deepcopy(st["state"]), {"schnappy/woodpecker-ci": dict(vv["kv"]["schnappy/woodpecker-ci"])})
data = vault("GET", "/_state")["kv"]["schnappy/woodpecker-ci"]
data["data"]["clone_token"] = ADMIN_CLONE
vault("POST", "/_reset", {"schnappy/woodpecker-ci": data})
rc, out = run("--tags", "retire", env=RETIRE_ENV)
check("retire while Vault still hands CI one of the admin's tokens: refused, nothing deleted",
      (rc != 0, "still holds a token of the admin" in out, admin_names(fstate())),
      (True, True, ["argocd-readonly", "woodpecker-clone", "woodpecker-infra"]))
reset()
rc, out = run("--tags", "retire")
check("retire with no admin token named in .env: refused, nothing deleted",
      (rc != 0, "nothing to retire" in out, len(admin_names(fstate()))), (True, True, 3))

# ── seed-vault-secrets.yml's woodpecker-ci: Vault's CI bot properties kept, .env's old tokens never over them ────
seed = yaml.safe_load(open(SEED))[0]
flat = []


def walk(ts):
    for t in ts or []:
        flat.append(t)
        for k in ("block", "rescue", "always"):
            walk(t.get(k))


walk(seed["tasks"])
pick = [t for t in flat if t.get("name") in ("Read the woodpecker-ci secret (its CI bot properties are setup-ci-bot's)",
                                             "Seed woodpecker-ci secrets")]
required = next(t for t in flat if "Validate required env-sourced" in (t.get("name") or ""))["loop"]
check("seed: its woodpecker-ci read and write found; .env's admin tokens no longer required",
      (len(pick), [x for x in ("WOODPECKER_INFRA_REPO_TOKEN", "WOODPECKER_CLONE_TOKEN") if x in required]), (2, []))
SEED_PLAY = os.path.join(W, "seed.yml")
yaml.safe_dump([{"name": "seed-vault-secrets' woodpecker-ci tasks", "hosts": "localhost", "connection": "local",
                 "gather_facts": False,
                 "vars": {"vault_prefix": "schnappy", "vault_addr": f"http://127.0.0.1:{VP}",
                          "vault_token_value": VAULT_TOKEN, "keepalived_vip": VIP},
                 "tasks": pick}], open(SEED_PLAY, "w"), sort_keys=False)
BOTV = {"infra_repo_token": "bot-infra-0000", "clone_token": "bot-clone-0000", "registry_user": BOT,
        "registry_token": "bot-registry-0000"}
SEED_ENV = {"SONARQUBE_TOKEN": "sonar-new", "NVD_API_KEY": "nvd", "PROMETHEUS_AUTH_TOKEN": "prom",
            "RENOVATE_TOKEN": "renovate-new"}
SEED_OUT = {"sonar_token": "sonar-new", "sonar_host_url": "https://sonar.pmon.dev", "nexus_url": f"http://{VIP}:8081",
            "nexus_npm_registry": f"http://{VIP}:8081/repository/npm-public/", "nvd_api_key": "nvd",
            "prometheus_auth_token": "prom", "renovate_token": "renovate-new", "renovate_github_token": ""}
OLD_ENV = {"WOODPECKER_INFRA_REPO_TOKEN": ADMIN_INFRA, "WOODPECKER_CLONE_TOKEN": ADMIN_CLONE,
           "WOODPECKER_REGISTRY_USER": "forgejo_admin", "WOODPECKER_REGISTRY_TOKEN": ADMIN_PW}


def seed_run(kvs, env):
    vault("POST", "/_reset", kvs)
    r = subprocess.run([AP, "-i", "localhost,", SEED_PLAY], capture_output=True, text=True, cwd=W,
                       env=dict(ENV, **env))
    return r.returncode, kv(), r.stdout + r.stderr


rc, after, out = seed_run({"schnappy/woodpecker-ci": {"data": dict(BOTV, custom_extra="keep-me", sonar_token="old"),
                                                      "version": 7}}, dict(SEED_ENV, **OLD_ENV))
check("seed: Vault's CI bot four kept over .env's old admin values; .env's other properties written; one it does not "
      "know kept; written with the version read (cas 7)",
      (rc, after["kv"]["schnappy/woodpecker-ci"]["data"], [w["cas"] for w in after["writes"]]),
      (0, dict(SEED_OUT, custom_extra="keep-me", **BOTV), [7]))
rc, after, out = seed_run({}, dict(SEED_ENV, **{k: "vagrant-" + k for k in OLD_ENV}))
check("seed: a first install (the path missing) takes the four from .env where set (the Vagrant copy's placeholders)",
      (rc, after["kv"]["schnappy/woodpecker-ci"]["data"], [w["cas"] for w in after["writes"]]),
      (0, dict(SEED_OUT, infra_repo_token="vagrant-WOODPECKER_INFRA_REPO_TOKEN",
               clone_token="vagrant-WOODPECKER_CLONE_TOKEN", registry_user="vagrant-WOODPECKER_REGISTRY_USER",
               registry_token="vagrant-WOODPECKER_REGISTRY_TOKEN"), [0]))
rc, after, out = seed_run({}, SEED_ENV)
check("seed: a first install without them in .env leaves them missing (for setup-ci-bot) - never an empty value",
      (rc, after["kv"]["schnappy/woodpecker-ci"]["data"]), (0, SEED_OUT))
rc, after, out = seed_run({"schnappy/woodpecker-ci": {"data": dict(BOTV), "version": 2}}, SEED_ENV)
check("seed: Vault's four kept when .env has none of them", (rc, after["kv"]["schnappy/woodpecker-ci"]["data"]),
      (0, dict(SEED_OUT, **BOTV)))
vault("POST", "/_reset", {"schnappy/woodpecker-ci": {"data": dict(BOTV), "version": 2}})
vault("POST", "/_fail", {"method": "GET", "path": "woodpecker-ci", "status": 503, "error": "Vault is sealed"})
r = subprocess.run([AP, "-i", "localhost,", SEED_PLAY], capture_output=True, text=True, cwd=W,
                   env=dict(ENV, **SEED_ENV, **OLD_ENV))
check("seed: a sealed Vault read fails the seed - nothing written over the bot's tokens",
      (r.returncode != 0, kv()["writes"], kv()["kv"]["schnappy/woodpecker-ci"]["data"]), (True, [], BOTV))

# ── no secret on a command line ─────────────────────────────────────────────────────────────────────────────────
canary = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(1.5)", CANARY])
canary.wait()
watch.send_signal(signal.SIGTERM)
watch.wait(timeout=30)
w = json.load(open(WATCH_OUT))
fence = open(os.path.join(W, "fence.log")).read().splitlines() if os.path.exists(os.path.join(W, "fence.log")) else []
check("the watch bites: a process with a known secret on its command line is seen",
      any(h["secret"] == 5 for h in w["hits"]), True)
check(f"no secret on any command line over every run ({w['scans']} scans of /proc): the admin's password, Vault's "
      "token, the bot's password, every token issued; no curl/forgejo/vault/ssh/kubectl run; the password's $( ) and "
      "backticks never run",
      ([h for h in w["hits"] if h["secret"] != 5], fence, w["scans"] > 50,
       os.path.exists(os.path.join(W, "ran")) or os.path.exists(os.path.join(W, "ran2"))), ([], [], True, False))
pl = yaml.safe_load(open(PB))
acts = set()
for t in pl[0]["tasks"]:
    stack = [t]
    while stack:
        x = stack.pop()
        stack += (x.get("block") or []) + (x.get("rescue") or [])
        acts |= {k for k in x if "." in k and k.split(".")[0] in ("ansible", "community")}
cfg = open(os.path.join(ROOT, "deploy/ansible/ansible.cfg")).read()
check("the playbook runs no command of its own (Forgejo and Vault in-process, uri and hashi_vault), and production's "
      "modules get their arguments on stdin (pipelining = True)",
      (sorted(a for a in acts if a.split(".")[-1] in ("shell", "command", "raw", "script", "expect")),
       "\npipelining = True\n" in cfg), ([], True))

for p in procs:
    p.terminate()
print("ci-bot: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
