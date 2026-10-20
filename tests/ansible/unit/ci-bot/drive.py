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
# ten: kubectl answering the two reads the retire play makes from k8s.json (kubectl-stub.py), anything else refused
TEN = os.path.join(W, "ten")
os.mkdir(TEN)
K8S = os.path.join(W, "k8s.json")
with open(os.path.join(TEN, "kubectl"), "w") as f:
    f.write(f'#!/bin/sh\nexec "{sys.executable}" "{H}/kubectl-stub.py" "{K8S}" "{W}/kubectl.log" "$@"\n')
os.chmod(os.path.join(TEN, "kubectl"), 0o755)
PYT = os.path.join(W, "py-ten")
with open(PYT, "w") as f:
    f.write(f'#!/bin/sh\nPATH="{TEN}:{FENCE}:$PATH" exec "{sys.executable}" "$@"\n')
os.chmod(PYT, 0o755)
# pi2: up, but not holding the VIP (its `ip` answers nothing) - the play ends there for it
PI2 = os.path.join(W, "pi2")
os.mkdir(PI2)
with open(os.path.join(PI2, "ip"), "w") as f:
    f.write("#!/bin/sh\nexit 0\n")
os.chmod(os.path.join(PI2, "ip"), 0o755)
PYW2 = os.path.join(W, "py-pi2")
with open(PYW2, "w") as f:
    f.write(f'#!/bin/sh\nPATH="{PI2}:{FENCE}:$PATH" exec "{sys.executable}" "$@"\n')
os.chmod(PYW2, 0o755)
# production's inventory shape (inventory/production.yml): target an ungrouped host, the pis group two Pis
INV = os.path.join(W, "inv.yml")
LOCAL = {"ansible_connection": "local", "ansible_become": False}
yaml.safe_dump({"all": {"hosts": {"target": dict(LOCAL, ansible_python_interpreter=PYT),
                                  "pi1": dict(LOCAL, ansible_python_interpreter=PYW),
                                  "pi2": dict(LOCAL, ansible_python_interpreter=PYW2)},
                        "children": {"pis": {"hosts": {"pi1": None, "pi2": None}}}}}, open(INV, "w"))
assert yaml.safe_load(open(os.path.join(ROOT, "deploy/ansible/inventory/production.yml")))["all"]["hosts"].get(
    "target") is not None, "production's inventory no longer has target as a host - the harness's shape is stale"
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
    return {"seq": 100, "org": ORG, "users": users, "teams": teams, "tokens": tokens, "repos": repos,
            "images": {"masi": ["9f8e7d6", "latest"]}}


VAULT_REST = {"renovate_token": "renovate-xyz", "sonar_token": "sonar-abc", "nexus_url": f"http://{VIP}:8081",
              "custom_extra": "keep-me"}
VAULT_FIXTURE = {"schnappy/woodpecker-ci": {"data": dict(VAULT_REST, infra_repo_token=ADMIN_INFRA,
                                                         clone_token=ADMIN_CLONE), "version": 3}}


PULL_NS = ["woodpecker", "schnappy-production", "schnappy-test", "schnappy-infra"]


def ten(down=False, ready=None, secret=None, pull=None):
    """ten's view: every ExternalSecret's Ready (True unless given, as "<ns>/<name>"), woodpecker-ci-secrets' keys,
    each namespace's forgejo-registry password (a string: woodpecker's); down - kubectl refused."""
    pull = {"woodpecker": pull} if isinstance(pull, str) else (pull or {})
    json.dump({"down": down,
               "ready": {"woodpecker/woodpecker-ci-secrets-es": "True",
                         **{f"{ns}/forgejo-registry-es": "True" for ns in PULL_NS}, **(ready or {})},
               "secret": secret or {}, "pull": {ns: pull.get(ns, "") for ns in PULL_NS}}, open(K8S, "w"))


# what ten is asked (kubectl-stub.py's log: verb, kind, namespace - "*" every one): get alone
READ_ON_TEN = {"get externalsecret -n woodpecker", "get secret -n woodpecker", "get externalsecret -n *",
               "get secret -n *"}


def kubectl_calls():
    p = os.path.join(W, "kubectl.log")
    return open(p).read().splitlines() if os.path.exists(p) else []


def reset(state=None, kv=None):
    forgejo("POST", "/_reset", state or fixture())
    vault("POST", "/_reset", copy.deepcopy(VAULT_FIXTURE if kv is None else kv))
    ten()
    open(os.path.join(W, "kubectl.log"), "w").close()
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
WANT_KINDS = [("infra", ["write:repository"]), ("registry", ["write:package"]), ("clone", ["read:repository"]),
              ("pull", ["read:package"])]
K = len(WANT_KINDS)  # tokens a run mints


def kinds(toks):
    return [(t["name"].split("-")[1], t["scopes"]) for t in toks]


def vault_expect(toks, rest=VAULT_REST):
    by = {t["name"].split("-")[1]: t["sha1"] for t in toks}
    return dict(rest, infra_repo_token=by.get("infra"), registry_token=by.get("registry"),
                clone_token=by.get("clone"), pull_token=by.get("pull"),
                registry_user=BOT)


def dv(state):
    """Vault's woodpecker-ci entry, its data and version (its history aside)."""
    e = state["kv"].get("schnappy/woodpecker-ci", {})
    return {"data": e.get("data"), "version": e.get("version")}


def stamp(hours_ago):
    return time.strftime("%Y%m%dT%H%M%S", time.gmtime(time.time() - hours_ago * 3600))


def mints(s):
    return [e["path"] for e in s["log"] if e["method"] == "POST" and e["path"].endswith("/tokens")]


def flat(out):
    return " ".join(out.split())


# ── setup-ci-bot.yml: first run, from production's state today ───────────────────────────────────────────────────
reset()
rc, out = run()
s, v = fstate(), kv()
toks = bot_tokens(s)
check("first run: passes", (rc, tail(out) if rc else ""), (0, ""))
check("first run: the bot is no admin (no must-change, may log in) - its teams' scope exactly: ci code+packages write "
      "on infra alone, ci-clone code read on admin chat chess masi, no repository made, each holding the bot alone",
      scope_view(s), WANT_SCOPE)
check("first run: four tokens on the bot, each its scope alone (infra write:repository, registry write:package, "
      "clone read:repository, pull read:package), named ci-<use>-<UTC time>",
      (kinds(toks), all(re.match(r"^ci-(infra|registry|clone|pull)-\d{8}T\d{6}$", t["name"]) for t in toks)),
      (WANT_KINDS, True))
check("first run: minted as the bot (basic auth), never as the admin",
      sorted({str(e["auth"]) for e in s["log"] if e["method"] == "POST" and e["path"].endswith("/tokens")}),
      [str(["basic", BOT])])
check("first run: Vault holds the bot's tokens and name, every other property kept as it was, one write with the "
      "version read (cas 3); the run says the versions (v3 -> v4) - v3 is what a rollback goes back to",
      (dv(v), [w["cas"] for w in v["writes"]], "woodpecker-ci v3 -> v4" in flat(out)),
      ({"data": vault_expect(toks), "version": 4}, [3], True))
check("first run: the registry token proven on the registry itself - a bearer from /v2/token, an upload to "
      "schnappy/masi started and cancelled, none left open",
      ([(e["method"], re.sub(r"[0-9a-f]{16}$", "<uuid>", e["path"])) for e in s["log"] if e["path"].startswith("/v2/")],
       s["state"].get("uploads")),
      ([("GET", "/v2/token"), ("POST", "/v2/schnappy/masi/blobs/uploads/"),
        ("DELETE", "/v2/schnappy/masi/blobs/uploads/<uuid>"),
        ("GET", "/v2/token"), ("POST", "/v2/schnappy/masi/blobs/uploads/"), ("GET", "/v2/schnappy/masi/tags/list"),
        ("GET", "/v2/schnappy/masi/manifests/9f8e7d6")], []))
check("first run: the pull token proven pull-only - a bearer from /v2/token, its push (an upload) refused, a manifest of "
      "schnappy/masi read",
      [(e["method"], e["path"].split("/")[-1] or e["path"].split("/")[-2], str(e["auth"])) for e in s["log"]
       if e["path"].startswith("/v2/") and e["auth"] and e["auth"][0] == "token"][-4:],
      [("GET", "token", str(["token", BOT])), ("POST", "uploads", str(["token", BOT])),
       ("GET", "list", str(["token", BOT])), ("GET", "9f8e7d6", str(["token", BOT]))])
check("first run: the admin's tokens untouched (retired only on --tags retire)",
      sorted(t["name"] for t in s["state"]["tokens"].values() if t["user"] == "forgejo_admin"),
      ["argocd-readonly", "woodpecker-clone", "woodpecker-infra"])
check("first run: what the bot can do, as Forgejo computes it from its teams: push on infra alone, admin nowhere",
      bot_rights(s["state"]), (["infra"], []))
first_ids = {t["name"]: t["id"] for t in s["state"]["teams"].values()}

# ── reruns: the same account and teams; new tokens; none deleted that the cluster may still hold ─────────────────
time.sleep(1.1)  # a new second: the next run's token names
rc, out = run()
s2, v2 = fstate(), kv()
toks2 = bot_tokens(s2)
check("rerun: passes, the account and the teams as they were (same teams, not made again)",
      (rc, scope_view(s2), {t["name"]: t["id"] for t in s2["state"]["teams"].values()}), (0, WANT_SCOPE, first_ids))
check("rerun: the run-1 tokens kept, three new ones, Vault on the new ones, every other property still kept",
      ([t["id"] for t in toks2[:K]], kinds(toks2[K:]), dv(v2)["data"]),
      ([t["id"] for t in toks], WANT_KINDS, vault_expect(toks2[K:])))
time.sleep(1.1)
rc, out = run()
s3, v3 = fstate(), kv()
toks3 = bot_tokens(s3)
check("a third run within 3 h: run 1's tokens kept too - Vault no longer holds them, but External Secrets may not "
      "have synced since (the cluster's Secret may still hand them to CI); account and teams unchanged",
      (rc, [t["id"] for t in toks3[:2 * K]], kinds(toks3[2 * K:]), len(toks3), scope_view(s3),
       dv(v3)["data"] == vault_expect(toks3[2 * K:])),
      (0, [t["id"] for t in toks2], WANT_KINDS, 3 * K, WANT_SCOPE, True))
# hours later: runs 1 and 2's tokens over 3 h old and not in Vault - deleted; run 3's over 3 h old but in Vault - kept;
# one 2 h 59 min old, not in Vault - kept
st = copy.deepcopy(s3["state"])
for t in st["tokens"].values():
    if t["user"] == BOT:
        t["name"] = re.sub(r"\d{8}T\d{6}$", stamp(4), t["name"])
st["seq"] += 1
young = {"id": st["seq"], "user": BOT, "name": "ci-infra-" + stamp(2.98), "sha1": secrets.token_hex(20),
         "scopes": ["write:repository"]}
young["token_last_eight"] = young["sha1"][-8:]
st["tokens"][str(young["id"])] = young
reset(st, {"schnappy/woodpecker-ci": dv(v3)})
rc, out = run()
s10 = fstate()
aged = {t["id"]: t["name"] for t in st["tokens"].values() if t["user"] == BOT}
check("a run over 3 h later: the tokens over 3 h old Vault does not hold deleted (runs 1 and 2); those Vault held "
      "kept however old (run 3), one under 3 h old kept; three new; the deleted ones named in the run's summary",
      (rc, sorted(t["id"] for t in bot_tokens(s10))[:K + 1], len(bot_tokens(s10)),
       all(aged[i] in flat(out) for i in [t["id"] for t in toks3[:2 * K]]) and "bot tokens deleted:" in flat(out)),
      (0, sorted([t["id"] for t in toks3[2 * K:]] + [young["id"]]), 2 * K + 1, True))
check("  ... ten read for it, read only: the ExternalSecrets' Ready, woodpecker-ci-secrets and every namespace's "
      "pull secret (get alone)",
      sorted(set(kubectl_calls())), sorted(READ_ON_TEN))
by_id = {t["id"]: t for t in toks3}
# held still (External Secrets not synced since): run 1's infra token in woodpecker-ci-secrets, run 2's registry token
# in woodpecker's forgejo-registry, run 1's pull token in schnappy-production's
held_infra, held_reg, held_pull = toks3[0], toks3[K + 1], toks3[3]
reset(copy.deepcopy(st), {"schnappy/woodpecker-ci": dv(v3)})
ten(secret={"infra_repo_token": held_infra["sha1"]},
    pull={"woodpecker": held_reg["sha1"], "schnappy-production": held_pull["sha1"]})
rc, out = run()
check("a run over 3 h later with the cluster still holding three old tokens (run 1's infra token in "
      "woodpecker-ci-secrets, run 2's registry token in woodpecker's forgejo-registry, run 1's pull token in "
      "schnappy-production's): those three kept, the others deleted",
      (rc, sorted(t["id"] for t in bot_tokens(fstate()))[:K + 4], len(bot_tokens(fstate()))),
      (0, sorted([held_infra["id"], held_reg["id"], held_pull["id"], young["id"]] + [t["id"] for t in toks3[2 * K:]]),
       2 * K + 4))
for label, k8s, said in (
        ("ten not read (kubectl refused)", {"down": True}, "ten not read"),
        ("an ExternalSecret not Ready (woodpecker's forgejo-registry-es)",
         {"ready": {"woodpecker/forgejo-registry-es": "False"}}, "woodpecker/forgejo-registry-es"),
        ("an ExternalSecret not Ready (schnappy-production's forgejo-registry-es)",
         {"ready": {"schnappy-production/forgejo-registry-es": "False"}}, "schnappy-production/forgejo-registry-es")):
    reset(copy.deepcopy(st), {"schnappy/woodpecker-ci": dv(v3)})
    ten(**k8s)
    rc, out = run()
    check(f"a run over 3 h later with {label}: no bot token deleted, said - the run passes",
          (rc, len(bot_tokens(fstate())), "deleted none" in flat(out) and said in flat(out)),
          (0, len(toks3) + 1 + K, True))
V3 = dv(v3)["data"]
VAULT6 = {"schnappy/woodpecker-ci": {"data": V3, "version": 6}}

# ── drift fixed or refused ──────────────────────────────────────────────────────────────────────────────────────
st = copy.deepcopy(s3["state"])
st["users"][BOT]["is_admin"] = True
st["users"][BOT]["must_change_password"] = True
ci = next(t for t in st["teams"].values() if t["name"] == "ci")
ci["repos"].append("platform")
ci["includes_all_repositories"] = True
ci["can_create_org_repo"] = True
ci["units_map"]["repo.pulls"] = "write"
reset(st, VAULT6)
rc, out = run()
check("drift: a bot made admin by hand is made a user again; a team given another repository, every repository, "
      "repository creation or another unit is put back to its own scope", (rc, scope_view(fstate())), (0, WANT_SCOPE))

for label, edit, said in (
        ("a team of that name with someone else in it (sm in ci)",
         lambda st: next(t for t in st["teams"].values() if t["name"] == "ci")["members"].append("sm"),
         "REFUSED: team schnappy/ci holds sm"),
        ("the bot put in Owners by hand (push and admin everywhere)",
         lambda st: st["teams"]["1"]["members"].append(BOT), "REFUSED: woodpecker-ci pushes to"),
        ("a branch protection on infra (CD's push to main would be refused)",
         lambda st: st["repos"]["infra"].update(protections=[{"branch_name": "main"}]),
         "REFUSED: schnappy/infra has branch protections"),
        ("the bot switched off (inactive) - a kill switch a run must not undo",
         lambda st: st["users"][BOT].update(active=False), "REFUSED: woodpecker-ci is switched off"),
        ("the bot's login prohibited - a kill switch a run must not undo",
         lambda st: st["users"][BOT].update(prohibit_login=True), "REFUSED: woodpecker-ci is switched off")):
    st = copy.deepcopy(s3["state"])
    edit(st)
    reset(st, VAULT6)
    rc, out = run()
    s4, v4 = fstate(), kv()
    check(f"refused: {label} - said; no token minted, Vault not written, ten not read",
          (rc != 0, said in flat(out), mints(s4), v4["writes"], kubectl_calls()), (True, True, [], [], []))
check("  ... and the switched-off bot left as it was (no edit of it)",
      ([e["method"] for e in s4["log"] if e["path"].endswith("/admin/users/" + BOT) and e["method"] != "GET"],
       s4["state"]["users"][BOT]["prohibit_login"]), ([], True))
st = copy.deepcopy(s3["state"])
st["users"][BOT]["active"] = False
reset(st, VAULT6)
rc, out = run("-e", "ci_bot_reactivate=true")
check("the switched-off bot with ci_bot_reactivate=true: switched on again, the run passes",
      (rc, scope_view(fstate())), (0, WANT_SCOPE))

# ── a failure after a mint: the new tokens deleted again, Vault unchanged (or as another writer left it) ───────────
for label, fault, want_vault in (
        ("the second token's mint fails", ("forgejo", {"method": "POST", "path": "/users/woodpecker-ci/tokens$",
                                                        "status": 500, "nth": 2}), {"data": V3, "version": 6}),
        ("Forgejo makes a token with more scope than asked (all)",
         ("forgejo", {"method": "POST", "path": "/users/woodpecker-ci/tokens$", "scopes": ["all"], "nth": 3}),
         {"data": V3, "version": 6}),
        ("the registry refuses the push (the upload)",
         ("forgejo", {"method": "POST", "path": "^/v2/.+/blobs/uploads/$", "status": 401}),
         {"data": V3, "version": 6}),
        ("the pull token can push (the registry starts its upload)",
         ("forgejo", {"method": "POST", "path": "^/v2/.+/blobs/uploads/$", "status": 202, "nth": 2}),
         {"data": V3, "version": 6}),
        ("the pull token reads no manifest",
         ("forgejo", {"method": "GET", "path": "^/v2/.+/manifests/", "status": 404}), {"data": V3, "version": 6}),
):
    reset(copy.deepcopy(s3["state"]), copy.deepcopy(VAULT6))
    (vault if fault[0] == "vault" else forgejo)("POST", "/_fail", fault[1])
    rc, out = run()
    s5, v5 = fstate(), kv()
    check(f"failure: {label} - fails, said; this run's tokens deleted again (the bot's as before), Vault "
          + "unchanged",
          (rc != 0, "this run's new tokens deleted again" in flat(out), [t["id"] for t in bot_tokens(s5)], dv(v5)),
          (True, True, [t["id"] for t in toks3], want_vault))

# ── the Vault write itself failing (its answer may come late - the write may still land): none deleted ──────────
WRITE_FAILED = "the Vault write itself failed"
for label, faults, want_vault in (
        ("someone writes Vault between the read and the write (the version read refuses this write)",
         [{"method": "GET", "path": "woodpecker-ci", "bump": True}], lambda new: {"data": dict(V3, someone="else"),
                                                                                  "version": 7}),
        ("the write applied, its answer lost", [{"method": "POST", "path": "woodpecker-ci", "lose": True}],
         lambda new: {"data": vault_expect(new, rest=VAULT_REST), "version": 7}),
        ("the write refused (500)", [{"method": "POST", "path": "woodpecker-ci", "status": 500}],
         lambda new: {"data": V3, "version": 6})):
    reset(copy.deepcopy(s3["state"]), copy.deepcopy(VAULT6))
    for f in faults:
        vault("POST", "/_fail", f)
    rc, out = run()
    s11, v11 = fstate(), kv()
    new = bot_tokens(s11)[len(toks3):]
    check(f"the Vault write failing - {label}: fails, saying so; none of this run's tokens deleted (left for a later "
          "run past the 3 h)",
          (rc != 0, WRITE_FAILED in flat(out), kinds(new), dv(v11)), (True, True, WANT_KINDS, want_vault(new)))

# ── the write answered done but not applied: the read-back refuses; Vault read again, holding none - deleted again
reset(copy.deepcopy(s3["state"]), copy.deepcopy(VAULT6))
vault("POST", "/_fail", {"method": "POST", "path": "woodpecker-ci", "drop": True})
rc, out = run()
check("the Vault write answered done but not applied: the read-back refuses; this run's tokens deleted again, Vault "
      "unchanged",
      (rc != 0, "REFUSED at 'Vault holds this run's tokens'" in flat(out)
       and "this run's new tokens deleted again" in flat(out), [t["id"] for t in bot_tokens(fstate())], dv(kv())),
      (True, True, [t["id"] for t in toks3], {"data": V3, "version": 6}))

# ── a failure after the write (its read-back): Vault read again - holding this run's tokens, or unread: none deleted
reset(copy.deepcopy(s3["state"]), copy.deepcopy(VAULT6))
vault("POST", "/_fail", {"method": "GET", "path": "woodpecker-ci", "status": 503, "nth": 2, "error": "Vault is sealed"})
rc, out = run()
s11, v11 = fstate(), kv()
new = bot_tokens(s11)[len(toks3):]
check("the read-back after the write failing, Vault then read again holding this run's tokens: fails, saying so - "
      "none deleted (CI may already get them)",
      (rc != 0, "Vault holds this run's tokens" in flat(out), kinds(new), dv(v11)),
      (True, True, WANT_KINDS, {"data": vault_expect(new, rest=VAULT_REST), "version": 7}))
reset(copy.deepcopy(s3["state"]), copy.deepcopy(VAULT6))
vault("POST", "/_fail", {"method": "GET", "path": "woodpecker-ci", "status": 503, "nth": 2, "error": "Vault is sealed"})
vault("POST", "/_fail", {"method": "GET", "path": "woodpecker-ci", "status": 503, "nth": 3, "error": "Vault is sealed"})
rc, out = run()
check("the read-back failing and Vault unreadable after it: fails, saying so - none deleted (whether Vault holds "
      "them is not known)",
      (rc != 0, "Vault not read after the write" in flat(out), len(bot_tokens(fstate()))),
      (True, True, len(toks3) + K))

# ── Forgejo not applying a team's units (an edit answered 200, the units left as they were): refused on reading back ──
st = copy.deepcopy(s3["state"])
next(t for t in st["teams"].values() if t["name"] == "ci")["units_map"]["repo.pulls"] = "write"
reset(st, copy.deepcopy(VAULT6))
forgejo("POST", "/_fail", {"method": "PATCH", "path": "^/api/v1/teams/[0-9]+$", "ignore": ["units_map"]})
rc, out = run()
s9 = fstate()
check("a team whose units Forgejo leaves wider than asked: refused on reading it back, said - no token minted, Vault "
      "not written",
      (rc != 0, "REFUSED: team schnappy/ci reads back" in flat(out), mints(s9), kv()["writes"]), (True, True, [], []))

# ── Forgejo leaving the bot an admin (its edit not applied): refused before a team or a token is touched ──────────
st = copy.deepcopy(s3["state"])
st["users"][BOT]["is_admin"] = True
reset(st, copy.deepcopy(VAULT6))
forgejo("POST", "/_fail", {"method": "PATCH", "path": "/admin/users/woodpecker-ci$", "ignore": ["admin"]})
rc, out = run()
s8 = fstate()
check("an admin bot Forgejo will not make a user: refused, said - no team changed, no token minted, Vault not written",
      (rc != 0, "REFUSED: woodpecker-ci is woodpecker-ci, admin True" in flat(out),
       [e["method"] + " " + e["path"] for e in s8["log"] if e["method"] != "GET" and "/admin/users" not in e["path"]],
       kv()["writes"]), (True, True, [], []))

# ── Vault: a sealed one refuses, a missing path is a first install ───────────────────────────────────────────────
reset()
vault("POST", "/_fail", {"method": "GET", "path": "woodpecker-ci", "status": 503, "error": "Vault is sealed"})
rc, out = run()
check("Vault sealed: fails before any token is minted (none asked for), nothing written",
      (rc != 0, mints(fstate()), kv()["writes"]), (True, [], []))
reset(kv={})
rc, out = run()
s6, v6 = fstate(), kv()
check("Vault path missing (a first install): the four written create-only (cas 0)",
      (rc, dv(v6)["data"], [w["cas"] for w in v6["writes"]], "woodpecker-ci v0 -> v1" in flat(out)),
      (0, vault_expect(bot_tokens(s6), rest={}), [0], True))

# ── no preview ───────────────────────────────────────────────────────────────────────────────────────────────────
reset()
rc, out = run("--check")
check("--check: refused, nothing changed", (rc != 0, "no check mode" in out, BOT in fstate()["state"]["users"],
                                            kv()["writes"]), (True, True, False, []))
check("  ... ten not read either", kubectl_calls(), [])

# ── retiring the admin's CI tokens ──────────────────────────────────────────────────────────────────────────────
RETIRE_ENV = {"WOODPECKER_INFRA_REPO_TOKEN": ADMIN_INFRA, "WOODPECKER_CLONE_TOKEN": " " + ADMIN_CLONE + " "}
ALL_ADMIN = ["argocd-readonly", "woodpecker-clone", "woodpecker-infra"]
admin_names = lambda s: sorted(t["name"] for t in s["state"]["tokens"].values() if t["user"] == "forgejo_admin")  # noqa


def cluster(ready="True", synced=True):
    """ten's view for retire: woodpecker-ci-secrets-es's Ready, the Secret as External Secrets last wrote it (Vault's
    now, or the admin's - not synced since)."""
    data = dv(kv())["data"] or {}
    secret = ({k: data.get(k, "") for k in ("infra_repo_token", "registry_token", "clone_token")} if synced
              else {"infra_repo_token": ADMIN_INFRA, "clone_token": ADMIN_CLONE})
    ten(ready={"woodpecker/woodpecker-ci-secrets-es": ready}, secret=secret)


reset()
cluster()
rc, out = run("--tags", "retire", env=RETIRE_ENV)
check("retire before the bot's tokens are in Vault: refused, nothing deleted - ten not read after the refusal "
      "(two Pis: pi2 ending its play is no failure)",
      (rc != 0, "REFUSED" in out, admin_names(fstate()), kubectl_calls()), (True, True, ALL_ADMIN, []))
rc, out = run()
st, vv = fstate(), kv()
for label, ready, synced, said in (
        ("the ExternalSecret not Ready", "False", True, "REFUSED: ExternalSecret woodpecker/woodpecker-ci-secrets-es"),
        ("the cluster's Secret not synced since (still the admin's tokens)", "True", False,
         "REFUSED: the cluster's woodpecker-ci-secrets does not hand CI what Vault holds")):
    cluster(ready, synced)
    rc, out = run("--tags", "retire", env=RETIRE_ENV)
    check(f"retire with {label}: refused, said, nothing deleted",
          (rc != 0, said in flat(out), admin_names(fstate())), (True, True, ALL_ADMIN))
cluster()
open(os.path.join(W, "kubectl.log"), "w").close()
rc, out = run("--tags", "retire", env=RETIRE_ENV)
s7 = fstate()
check("retire after setup, the cluster synced: the admin's two CI tokens deleted, its others kept; the bot's tokens, "
      "the account and Vault untouched",
      (rc, admin_names(s7), [t["id"] for t in bot_tokens(s7)], kv() == vv, scope_view(s7)),
      (0, ["argocd-readonly"], [t["id"] for t in bot_tokens(st)], True, WANT_SCOPE))
check("retire read the cluster read-only: the ExternalSecrets and the Secrets, get alone",
      sorted(set(open(os.path.join(W, "kubectl.log")).read().splitlines())), sorted(READ_ON_TEN))
rc, out = run("--tags", "retire", env=RETIRE_ENV)
check("retire again: nothing left to delete - passes", (rc, admin_names(fstate())), (0, ["argocd-readonly"]))
reset(copy.deepcopy(st["state"]), {"schnappy/woodpecker-ci": vv["kv"]["schnappy/woodpecker-ci"]})
cluster()
rc, out = run("--tags", "retire", env={"WOODPECKER_INFRA_REPO_TOKEN": ADMIN_INFRA})
check("retire with .env naming the infra token alone: the clone token found in Vault's history (v3) - both deleted",
      (rc, admin_names(fstate())), (0, ["argocd-readonly"]))
reset(copy.deepcopy(st["state"]), {"schnappy/woodpecker-ci": vv["kv"]["schnappy/woodpecker-ci"]})
cluster()
rc, out = run("--tags", "retire")
check("retire with nothing in .env: both found in Vault's history - deleted", (rc, admin_names(fstate())),
      (0, ["argocd-readonly"]))
e = copy.deepcopy(vv["kv"]["schnappy/woodpecker-ci"])
e["data"]["clone_token"] = ADMIN_CLONE
reset(copy.deepcopy(st["state"]), {"schnappy/woodpecker-ci": e})
cluster()
open(os.path.join(W, "kubectl.log"), "w").close()
rc, out = run("--tags", "retire", env=RETIRE_ENV)
check("retire while Vault still hands CI one of the admin's tokens .env names: refused at once (Vault's read - ten not "
      "even read), said, nothing deleted",
      (rc != 0, "still holds a token of the admin .env names" in flat(out), admin_names(fstate()),
       open(os.path.join(W, "kubectl.log")).read()), (True, True, ALL_ADMIN, ""))
reset(copy.deepcopy(st["state"]), {"schnappy/woodpecker-ci": e})
cluster()
rc, out = run("--tags", "retire", env={"WOODPECKER_INFRA_REPO_TOKEN": ADMIN_INFRA})
check("retire while Vault hands CI an admin token .env does not name (found in the history): refused, nothing deleted",
      (rc != 0, "still holds a token of the admin (woodpecker-clone)" in flat(out), admin_names(fstate())),
      (True, True, ALL_ADMIN))
reset(copy.deepcopy(st["state"]), {"schnappy/woodpecker-ci": vv["kv"]["schnappy/woodpecker-ci"]})
cluster()
rc, out = run("--tags", "retire", "--limit", "pis", env=RETIRE_ENV)
check("retire with ten left out (--limit pis - the cluster not read): refused, nothing deleted",
      (rc != 0, "REFUSED: the cluster not read on ten" in flat(out), admin_names(fstate())), (True, True, ALL_ADMIN))
reset(kv={"schnappy/woodpecker-ci": {"data": dict(VAULT_REST), "version": 1}})
cluster()
rc, out = run("--tags", "retire", env=RETIRE_ENV)
check("retire while Vault holds none of the bot's (setup-ci-bot never ran): refused, said, nothing deleted",
      (rc != 0, "run task deploy:ci-bot first" in flat(out), len(admin_names(fstate()))), (True, True, 3))
reset(copy.deepcopy(st["state"]), {"schnappy/woodpecker-ci": {"data": dv(vv)["data"], "version": 1}})
cluster()
rc, out = run("--tags", "retire")
check("retire with nothing in .env nor in Vault's history: refused, nothing deleted",
      (rc != 0, "nothing to retire" in out, admin_names(fstate())), (True, True, ALL_ADMIN))

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
        "registry_token": "bot-registry-0000", "pull_token": "bot-pull-0000"}
SEED_ENV = {"SONARQUBE_TOKEN": "sonar-new", "NVD_API_KEY": "nvd", "PROMETHEUS_AUTH_TOKEN": "prom",
            "RENOVATE_TOKEN": "renovate-new"}
SEED_OUT = {"sonar_token": "sonar-new", "sonar_host_url": "https://sonar.pmon.dev", "nexus_url": f"http://{VIP}:8081",
            "nexus_npm_registry": f"http://{VIP}:8081/repository/npm-public/", "nvd_api_key": "nvd",
            "prometheus_auth_token": "prom", "renovate_token": "renovate-new", "renovate_github_token": ""}
OLD_ENV = {"WOODPECKER_INFRA_REPO_TOKEN": ADMIN_INFRA, "WOODPECKER_CLONE_TOKEN": ADMIN_CLONE,
           "WOODPECKER_REGISTRY_USER": "forgejo_admin", "WOODPECKER_REGISTRY_TOKEN": ADMIN_PW,
           "WOODPECKER_PULL_TOKEN": "an-old-pull-token"}



def wci(state):
    """Vault's woodpecker-ci data in a fake Vault state, None where the path is missing."""
    return state["kv"].get("schnappy/woodpecker-ci", {}).get("data")

def seed_run(kvs, env):
    vault("POST", "/_reset", kvs)
    r = subprocess.run([AP, "-i", "localhost,", SEED_PLAY], capture_output=True, text=True, cwd=W,
                       env=dict(ENV, **env))
    return r.returncode, kv(), r.stdout + r.stderr


rc, after, out = seed_run({"schnappy/woodpecker-ci": {"data": dict(BOTV, custom_extra="keep-me", sonar_token="old"),
                                                      "version": 7}}, dict(SEED_ENV, **OLD_ENV))
check("seed: Vault's CI bot four kept over .env's old admin values; .env's other properties written; one it does not "
      "know kept; written with the version read (cas 7)",
      (rc, wci(after), [w["cas"] for w in after["writes"]]),
      (0, dict(SEED_OUT, custom_extra="keep-me", **BOTV), [7]))
rc, after, out = seed_run({}, dict(SEED_ENV, **{k: "vagrant-" + k for k in OLD_ENV}))
check("seed: a first install (the path missing) takes the CI bot's five from .env where set (the Vagrant copy's "
      "placeholders)",
      (rc, wci(after), [w["cas"] for w in after["writes"]]),
      (0, dict(SEED_OUT, infra_repo_token="vagrant-WOODPECKER_INFRA_REPO_TOKEN",
               clone_token="vagrant-WOODPECKER_CLONE_TOKEN", registry_user="vagrant-WOODPECKER_REGISTRY_USER",
               pull_token="vagrant-WOODPECKER_PULL_TOKEN",
               registry_token="vagrant-WOODPECKER_REGISTRY_TOKEN"), [0]))
rc, after, out = seed_run({}, SEED_ENV)
check("seed: a first install without them in .env leaves them missing (for setup-ci-bot) - never an empty value",
      (rc, wci(after)), (0, SEED_OUT))
rc, after, out = seed_run({"schnappy/woodpecker-ci": {"data": dict(BOTV), "version": 2}}, SEED_ENV)
check("seed: Vault's four kept when .env has none of them", (rc, wci(after)),
      (0, dict(SEED_OUT, **BOTV)))


def failed_at(out):
    """The task the run failed at: the last TASK header before its first fatal line."""
    lines = out.splitlines()
    first = next((i for i, x in enumerate(lines) if x.startswith(("fatal:", "failed:"))), len(lines))
    return next((x for x in reversed(lines[:first]) if x.startswith("TASK [")), "")


vault("POST", "/_reset", {"schnappy/woodpecker-ci": {"data": dict(BOTV), "version": 2}})
vault("POST", "/_fail", {"method": "GET", "path": "woodpecker-ci", "status": 503, "error": "Vault is sealed"})
r = subprocess.run([AP, "-i", "localhost,", SEED_PLAY], capture_output=True, text=True, cwd=W,
                   env=dict(ENV, **SEED_ENV, **OLD_ENV))
check("seed: a sealed Vault fails the seed at its read - nothing written over the bot's tokens",
      (r.returncode != 0, "Read the woodpecker-ci secret" in failed_at(r.stdout), kv()["writes"],
       kv()["kv"]["schnappy/woodpecker-ci"]["data"]), (True, True, [], BOTV))
vault("POST", "/_reset", {"schnappy/woodpecker-ci": {"data": dict(BOTV), "version": 2}})
vault("POST", "/_fail", {"method": "GET", "path": "woodpecker-ci", "bump": True})
r = subprocess.run([AP, "-i", "localhost,", SEED_PLAY], capture_output=True, text=True, cwd=W,
                   env=dict(ENV, **SEED_ENV, **OLD_ENV))
check("seed: someone writes Vault between its read and its write - the version read refuses it, theirs kept",
      (r.returncode != 0, dv(kv())), (True, {"data": dict(BOTV, someone="else"), "version": 3}))

# ── a new environment's pull secret: the CI bot's pull-only token, never the admin ─────────────────────────────────
CE = os.path.join(ROOT, "deploy/ansible/playbooks/create-environment.yml")
blocks = [t["ansible.builtin.blockinfile"]["block"] for t in yaml.safe_load(open(CE))[0]["tasks"]
          if t.get("name") == "Add forgejo-registry secret"]
es = yaml.safe_load(blocks[0].replace("{{ env_ns }}", "schnappy-pr-1").replace("{{ '{{' }}", "{{")
                    .replace("{{ '}}' }}", "}}")) if len(blocks) == 1 else {}
check("create-environment: a new environment's forgejo-registry-es takes woodpecker-ci's registry_user and pull_token "
      "(read:package), nothing of the admin's",
      (len(blocks), [(d["secretKey"], d["remoteRef"]["key"], d["remoteRef"]["property"]) for d in es["spec"]["data"]]
       if es else None, "admin" in (blocks[0] if blocks else "admin")),
      (1, [("registry_user", "secret/data/schnappy/woodpecker-ci", "registry_user"),
           ("registry_token", "secret/data/schnappy/woodpecker-ci", "pull_token")], False))

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
CMD = ("shell", "command", "raw", "script", "expect")
# the reads on ten, by task: what each runs is kubectl, every kubectl a get
READS_ON_TEN = {"An ExternalSecret's Ready", "Every pull secret's ExternalSecret's Ready",
                "The cluster's tokens - their last eight characters"}
cmds = []
for play in pl:
    stack = list(play.get("tasks") or []) + list(play.get("pre_tasks") or []) + list(play.get("post_tasks") or [])
    while stack:
        x = stack.pop()
        stack += (x.get("block") or []) + (x.get("rescue") or []) + (x.get("always") or [])
        for k, v in x.items():
            if "." in k and k.split(".")[-1] in CMD:
                text = " ".join(v["argv"]) if isinstance(v, dict) and "argv" in v else \
                    (v.get("cmd", "") if isinstance(v, dict) else str(v))
                text = re.sub(r"\{\{.*?\}\}", "X", text)  # a template one word
                verbs = [m[1] for m in re.findall(r"\bkubectl((?:\s+(?:--kubeconfig|-n)\s+\S+)*)\s+(\S+)", text)]
                cmds.append((play.get("hosts"), x.get("name"), x.get("name") in READS_ON_TEN and
                             play.get("hosts") == "target" and bool(verbs) and set(verbs) == {"get"}
                             and not re.search(r"(^|[\s|;(])(curl|wget|vault|forgejo|ssh)(\s|$)", text)))
cfg = open(os.path.join(ROOT, "deploy/ansible/ansible.cfg")).read()
check("no play runs a command of its own (Forgejo and Vault in-process, uri and hashi_vault) but ten's reads - "
      "kubectl get alone; production's modules get their arguments on stdin (pipelining = True)",
      ([c for c in cmds if not c[2]], sorted({c[1] for c in cmds}) == sorted(READS_ON_TEN),
       "\npipelining = True\n" in cfg), ([], True, True))

for p in procs:
    p.terminate()
print("ci-bot: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
