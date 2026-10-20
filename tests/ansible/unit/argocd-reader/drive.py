"""The argocd-reader harness's cases (run.sh starts it): the REAL setup-argocd-reader.yml run by ansible-playbook against
the ci-bot harness's fake Forgejo and fake Vault (the real community.hashi_vault modules talk to it), ten's kubectl a
stub reading a state file, an infra checkout of fixtures the repositories are derived from, every process's command
line watched for secrets, curl & co fenced; then scripts/argocd-repos.py alone, and seed-vault-secrets.yml's own
argocd/forgejo-readonly tasks.
argv: <ansible-playbook> <work dir>. Prints PASS/FAIL lines and "argocd-reader: ALL-PASS" or "argocd-reader: N FAILED".
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
H = os.path.join(ROOT, "tests/ansible/unit/argocd-reader")
FAKES = os.path.join(ROOT, "tests/ansible/unit/ci-bot")
PB = os.path.join(ROOT, "deploy/ansible/playbooks/setup-argocd-reader.yml")
SEED = os.path.join(ROOT, "deploy/ansible/playbooks/seed-vault-secrets.yml")
REPOS = os.path.join(ROOT, "scripts/argocd-repos.py")
BOT, ORG, VIP, PATH_V = "argocd-reader", "schnappy", "192.168.11.5", "argocd/forgejo-readonly"
ADMIN_PW = "adm'\"$(touch " + W + "/ran)`touch " + W + "/ran2`\\:pw"
VAULT_TOKEN = "hvs.TEST" + secrets.token_hex(12)
READONLY, ADMIN_ARGO, ADMIN_PI, PUSH = (secrets.token_hex(20) for _ in range(4))
CANARY = "canary" + secrets.token_hex(8)
fails = 0
procs = []
atexit.register(lambda: [p.kill() for p in procs])
signal.signal(signal.SIGTERM, lambda *_: sys.exit(124))


def check(name, got, want):
    global fails
    ok = got == want
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"\n    got  {got}\n    want {want}"))


def start(script, *args):
    portfile = os.path.join(W, os.path.basename(script) + ".port")
    p = subprocess.Popen([sys.executable, script, portfile, *args])
    procs.append(p)
    for _ in range(200):
        if os.path.exists(portfile) and open(portfile).read():
            return int(open(portfile).read())
        time.sleep(0.02)
    sys.exit(f"argocd-reader: {script} did not start")


def http(port, method, path, body=None):
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", method=method,
                                 data=json.dumps(body).encode() if body is not None else None)
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)


open(os.path.join(W, "root-token"), "w").write(VAULT_TOKEN + "\n")
FP = start(os.path.join(FAKES, "fakeforgejo.py"))
VP = start(os.path.join(FAKES, "fakevault.py"), os.path.join(W, "root-token"))
forgejo = lambda m, p, b=None: http(FP, m, p, b)  # noqa: E731
vault = lambda m, p, b=None: http(VP, m, p, b)  # noqa: E731

FENCE = os.path.join(W, "fence")
os.mkdir(FENCE)
for tool in ("curl", "wget", "forgejo", "gitea", "vault", "http", "ssh", "kubectl", "argocd"):
    with open(os.path.join(FENCE, tool), "w") as f:
        f.write(f'#!/bin/sh\necho "{tool} $*" >> "{W}/fence.log"\nexit 97\n')
    os.chmod(os.path.join(FENCE, tool), 0o755)


def wrapper(name, path_dir):
    p = os.path.join(W, "py-" + name)
    with open(p, "w") as f:
        f.write(f'#!/bin/sh\nPATH="{path_dir}:{FENCE}:$PATH" exec "{sys.executable}" "$@"\n')
    os.chmod(p, 0o755)
    return p


# pi1 holds the VIP, pi2 does not (its `ip` answers nothing); ten's kubectl is the stub
for name, line in (("pi1", f'echo "2: eth0    inet {VIP}/24 scope global secondary eth0"'), ("pi2", "exit 0")):
    os.mkdir(os.path.join(W, name))
    with open(os.path.join(W, name, "ip"), "w") as f:
        f.write(f"#!/bin/sh\n{line}\n")
    os.chmod(os.path.join(W, name, "ip"), 0o755)
TEN = os.path.join(W, "ten")
os.mkdir(TEN)
K8S = os.path.join(W, "k8s.json")
with open(os.path.join(TEN, "kubectl"), "w") as f:
    f.write(f'#!/bin/sh\nexec "{sys.executable}" "{H}/kubectl-stub.py" "{K8S}" "{W}/kubectl.log" "$@"\n')
os.chmod(os.path.join(TEN, "kubectl"), 0o755)
# production's inventory shape: target an ungrouped host, the pis group two Pis
INV = os.path.join(W, "inv.yml")
LOCAL = {"ansible_connection": "local", "ansible_become": False}
yaml.safe_dump({"all": {"hosts": {"target": dict(LOCAL, ansible_python_interpreter=wrapper("ten", TEN)),
                                  "pi1": dict(LOCAL, ansible_python_interpreter=wrapper("pi1", os.path.join(W, "pi1"))),
                                  "pi2": dict(LOCAL, ansible_python_interpreter=wrapper("pi2", os.path.join(W, "pi2")))},
                        "children": {"pis": {"hosts": {"pi1": None, "pi2": None}}}}}, open(INV, "w"))

# an infra checkout: what Argo CD reads - two Applications on the host (infra, platform), one on a chart repository,
# an ApplicationSet whose matrix lists two repositories for its pull-request generator, a file that is no manifest
INFRA = os.path.join(W, "infra")


def infra_fixture(root, extra=None):
    apps = os.path.join(root, "clusters", "production", "argocd", "apps")
    os.makedirs(apps, exist_ok=True)
    app = lambda n, url: {"apiVersion": "argoproj.io/v1alpha1", "kind": "Application", "metadata": {"name": n},  # noqa
                          "spec": {"source": {"repoURL": url, "path": "."}}}
    docs = {"infra.yaml": [app("root", "https://git.pmon.dev/schnappy/infra.git")],
            "multi.yaml": [{"apiVersion": "argoproj.io/v1alpha1", "kind": "Application", "metadata": {"name": "m"},
                            "spec": {"sources": [{"repoURL": "https://git.pmon.dev/schnappy/platform.git"},
                                                 {"repoURL": "https://charts.jetstack.io", "chart": "x"}]}}],
            "prs.yaml": [{"apiVersion": "argoproj.io/v1alpha1", "kind": "ApplicationSet", "metadata": {"name": "prs"},
                          "spec": {"generators": [{"matrix": {"generators": [
                              {"list": {"elements": [{"repo": "monitor"}, {"repo": "chat"}]}},
                              {"pullRequest": {"gitea": {"owner": ORG, "repo": "{{ .repo }}",
                                                         "api": "https://git.pmon.dev"}}}]}}],
                                   "template": {"spec": {"source": {
                                       "repoURL": "https://git.pmon.dev/schnappy/platform.git"}}}}}]}
    docs.update(extra or {})
    for n, d in docs.items():
        yaml.safe_dump_all(d, open(os.path.join(apps, n), "w"))
    open(os.path.join(apps, "values.yaml"), "w").write("a: {{ not yaml\n")


infra_fixture(INFRA)
VARS = os.path.join(W, "vars.yml")


def write_vars(infra=INFRA):
    yaml.safe_dump({"keepalived_vip": VIP, "forgejo_admin_user": "forgejo_admin", "forgejo_admin_password": ADMIN_PW,
                    "forgejo_api": f"http://127.0.0.1:{FP}/api/v1", "vault_addr": f"http://127.0.0.1:{VP}",
                    "vault_ca_cert": os.path.join(W, "no-ca.pem"),
                    "vault_root_token_file": os.path.join(W, "root-token"), "reader_infra_dir": infra},
                   open(VARS, "w"))


write_vars()
FIXED = os.path.join(W, "fixed-secrets")
open(FIXED, "w").write("\n".join([ADMIN_PW, VAULT_TOKEN, READONLY, ADMIN_ARGO, ADMIN_PI, PUSH, CANARY]) + "\n")
WATCH_OUT = os.path.join(W, "watch.json")
watch = subprocess.Popen([sys.executable, os.path.join(FAKES, "argvwatch.py"), str(FP), FIXED, WATCH_OUT])
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


def flat(out):
    return " ".join(out.split())


def tail(out):
    return "\n".join(x for x in out.splitlines() if "REFUSED" in x or "fatal" in x or "msg" in x)[-600:]


def tok(i, user, name, sha1, scopes):
    return str(i), {"id": i, "user": user, "name": name, "sha1": sha1, "token_last_eight": sha1[-8:], "scopes": scopes}


def fixture():
    users = {
        "forgejo_admin": {"id": 1, "login": "forgejo_admin", "email": "admin@pmon.dev", "password": ADMIN_PW,
                          "is_admin": True, "prohibit_login": False, "active": True, "must_change_password": False},
        "sm": {"id": 2, "login": "sm", "email": "sm@x", "password": "sm-pw", "is_admin": False,
               "prohibit_login": False, "active": True, "must_change_password": False},
    }
    every = {u: "owner" for u in ("repo.code", "repo.packages", "repo.issues", "repo.pulls")}
    teams = {"1": {"id": 1, "name": "Owners", "description": "", "permission": "owner", "units_map": every,
                   "includes_all_repositories": True, "can_create_org_repo": True, "members": ["sm"], "repos": []}}
    tokens = dict([tok(10, "forgejo_admin", "argocd-20260405T154834", ADMIN_ARGO, ["read:repository"]),
                   tok(11, "forgejo_admin", "readonly", READONLY, ["read:repository"]),
                   tok(12, "forgejo_admin", "pi-repo", ADMIN_PI, ["read:repository"]),
                   tok(13, "forgejo_admin", "woodpecker-push", PUSH, ["write:repository"])])
    repos = {r: {"private": True} for r in ("infra", "platform", "monitor", "chat", "admin", "masi")}
    repos["handbook"] = {"private": False}
    return {"seq": 100, "org": ORG, "users": users, "teams": teams, "tokens": tokens, "repos": repos}


VAULT_FIXTURE = {PATH_V: {"data": {"token": READONLY, "kept": "keep-me"}, "version": 2}}


def ten(down=False, ready=None, readonly=READONLY, creds=None):
    """ten's view: argocd's ExternalSecrets (forgejo-readonly-token Ready; the repo-creds ones only when given), the
    readonly token, each repo-creds Secret's username and password (the admin's, before the switch)."""
    creds = creds or {"forgejo-repo-creds": ("forgejo_admin", ADMIN_ARGO), "forgejo-pi-repo": ("forgejo_admin", ADMIN_PI)}
    secrets_ = {"forgejo-readonly-token": {"token": readonly}}
    secrets_.update({n: {"username": u, "password": p} for n, (u, p) in creds.items()})
    json.dump({"down": down, "ready": dict({"forgejo-readonly-token": "True", "vault-cleanup-token": "True"},
                                           **(ready or {})), "secrets": secrets_}, open(K8S, "w"))


def kubectl_calls():
    p = os.path.join(W, "kubectl.log")
    return open(p).read().splitlines() if os.path.exists(p) else []


def reset(state=None, kv=None):
    forgejo("POST", "/_reset", state or fixture())
    vault("POST", "/_reset", copy.deepcopy(VAULT_FIXTURE if kv is None else kv))
    ten()
    open(os.path.join(W, "kubectl.log"), "w").close()


def fstate():
    return forgejo("GET", "/_state")


def kv():
    return vault("GET", "/_state")


def dv(state):
    e = state["kv"].get(PATH_V, {})
    return {"data": e.get("data"), "version": e.get("version")}


def bot_tokens(s):
    return sorted((t for t in s["state"]["tokens"].values() if t["user"] == BOT), key=lambda t: t["id"])


def admin_names(s):
    return sorted(t["name"] for t in s["state"]["tokens"].values() if t["user"] == "forgejo_admin")


def scope_view(s):
    st = s["state"]
    u = st["users"].get(BOT, {})
    teams = {t["name"]: (t["permission"], t["units_map"], t["includes_all_repositories"], t["can_create_org_repo"],
                         sorted(t["repos"]), sorted(t["members"])) for t in st["teams"].values()
             if t["name"].startswith("argocd")}
    return ({k: u.get(k) for k in ("is_admin", "must_change_password", "prohibit_login", "active")}, teams)


def mints(s):
    return [e["path"] for e in s["log"] if e["method"] == "POST" and e["path"].endswith("/tokens")]


def stamp(hours_ago):
    return time.strftime("%Y%m%dT%H%M%S", time.gmtime(time.time() - hours_ago * 3600))


WANT_SCOPE = ({"is_admin": False, "must_change_password": False, "prohibit_login": False, "active": True},
              {"argocd-read": ("read", {"repo.code": "read"}, False, False, ["infra", "platform"], [BOT]),
               "argocd-pulls": ("read", {"repo.pulls": "read"}, False, False, ["chat", "monitor"], [BOT])})
ADMIN_ALL = ["argocd-20260405T154834", "pi-repo", "readonly", "woodpecker-push"]
le = lambda x: x[-8:]  # noqa: E731
# a run that minted none reaches the checks as a failure, never as an IndexError
MISSING = {"id": -1, "sha1": "none", "name": "none", "scopes": [], "token_last_eight": "none"}

# ── the repositories, derived ───────────────────────────────────────────────────────────────────────────────────
r = subprocess.run([sys.executable, REPOS, INFRA, "git.pmon.dev", ORG], capture_output=True, text=True)
check("argocd-repos: the cloned repositories (an Application's source and sources; an ApplicationSet's template), the PR "
      "generator's (its matrix list resolving '{{ .repo }}'); a chart repository and a file that is no manifest left out",
      (r.returncode, json.loads(r.stdout)["code"] if r.returncode == 0 else r.stderr,
       json.loads(r.stdout)["pulls"] if r.returncode == 0 else None), (0, ["infra", "platform"], ["chat", "monitor"]))
for label, extra, said in (
        ("a repoURL on the host but another org's", {"o.yaml": [{"apiVersion": "argoproj.io/v1alpha1",
                                                                  "kind": "Application", "metadata": {"name": "o"},
                                                                  "spec": {"source": {"repoURL":
                                                                           "https://git.pmon.dev/other/x.git"}}}]},
         "not a repository of schnappy"),
        ("a pull-request generator whose templated repo nothing resolves",
         {"u.yaml": [{"apiVersion": "argoproj.io/v1alpha1", "kind": "ApplicationSet", "metadata": {"name": "u"},
                      "spec": {"generators": [{"pullRequest": {"gitea": {"owner": ORG, "repo": "{{ .nope }}",
                                                                         "api": "https://git.pmon.dev"}}}],
                               "template": {"spec": {}}}}]}, "not resolved")):
    d = os.path.join(W, "infra-" + label[:6].replace(" ", "_"))
    infra_fixture(d, extra)
    r = subprocess.run([sys.executable, REPOS, d, "git.pmon.dev", ORG], capture_output=True, text=True)
    check(f"argocd-repos: {label} - refused, said", (r.returncode != 0, said in r.stderr), (True, True))

# ── first run, from production's state today ─────────────────────────────────────────────────────────────────────
reset()
rc, out = run()
s, v = fstate(), kv()
toks = bot_tokens(s) or [MISSING]
check("first run: passes", (rc, tail(out) if rc else ""), (0, ""))
check("first run: the reader no admin; argocd-read code READ on infra and platform (what Applications clone), "
      "argocd-pulls pull requests READ on chat and monitor (the PR generator's) - derived from infra's manifests, "
      "nothing else, each holding the reader alone", scope_view(s), WANT_SCOPE)
check("first run: one token on the reader, read:repository alone, named argocd-reader-<UTC time>, minted as the reader",
      ([(t["scopes"], bool(re.match(r"^argocd-reader-\d{8}T\d{6}$", t["name"]))) for t in toks],
       sorted({str(e["auth"]) for e in s["log"] if e["method"] == "POST" and e["path"].endswith("/tokens")})),
      ([(["read:repository"], True)], [str(["basic", BOT])]))
check("first run: proven - infra's and platform's branches read, chat's and monitor's pull requests listed, with the "
      "token", sorted((e["path"].split("/")[-2], e["path"].split("/")[-1]) for e in s["log"]
                      if e["auth"] and e["auth"][0] == "token" and e["path"].endswith(("/branches", "/pulls"))),
      [("chat", "pulls"), ("infra", "branches"), ("monitor", "pulls"), ("platform", "branches")])
check("first run: Vault argocd/forgejo-readonly holds the token and username (its other property kept), what ten "
      "held recorded for retire "
      "(retire_last_eight: the readonly token's, both repo-creds passwords'), one write with the version read (cas 2), "
      "the run says v2 -> v3",
      (dv(v), [w["cas"] for w in v["writes"]], "argocd/forgejo-readonly v2 -> v3" in flat(out)),
      ({"data": {"token": toks[0]["sha1"] if toks else None, "username": BOT, "kept": "keep-me",
                 "retire_last_eight": ",".join(sorted([le(READONLY), le(ADMIN_ARGO), le(ADMIN_PI)]))},
        "version": 3}, [2], True))
check("first run: the admin's tokens untouched; ten read only (get alone)",
      (admin_names(s), sorted(set(kubectl_calls()))),
      (ADMIN_ALL, ["get externalsecret -n argocd", "get secret -n argocd"]))
first_ids = {t["name"]: t["id"] for t in s["state"]["teams"].values()}

time.sleep(1.1)
rc, out = run()
s2, v2 = fstate(), kv()
toks2 = bot_tokens(s2) or [MISSING]
check("rerun: the account and teams as they were (same teams); the run-1 token kept (Vault held it), a new one in "
      "Vault; retire_last_eight kept",
      (rc, scope_view(s2), {t["name"]: t["id"] for t in s2["state"]["teams"].values()}, [t["id"] for t in toks2],
       (dv(v2)["data"] or {}).get("token") == toks2[-1]["sha1"], (dv(v2)["data"] or {}).get("retire_last_eight")),
      (0, WANT_SCOPE, first_ids, [toks[0]["id"], toks2[-1]["id"]], True, (dv(v)["data"] or {}).get("retire_last_eight")))

# hours later: run 1's token (over 3 h, not in Vault) deleted - unless ten holds it; ten unread or not Ready: none
st = copy.deepcopy(s2["state"])
for t in st["tokens"].values():
    if t["user"] == BOT:
        t["name"] = re.sub(r"\d{8}T\d{6}$", stamp(4), t["name"])
st["seq"] += 1
young = {"id": st["seq"], "user": BOT, "name": "argocd-reader-" + stamp(2.98), "sha1": secrets.token_hex(20),
         "scopes": ["read:repository"]}
young["token_last_eight"] = young["sha1"][-8:]
st["tokens"][str(young["id"])] = young
for label, k8s, want_left, said in (
        ("ten not holding it (one under 3 h kept)", {}, [toks2[-1]["id"], young["id"]],
         "reader tokens deleted: argocd-reader-"),
        ("ten's forgejo-repo-creds still holding it", {"creds": {"forgejo-repo-creds": (BOT, toks[0]["sha1"]),
                                                                 "forgejo-pi-repo": (BOT, toks[0]["sha1"])}},
         [toks[0]["id"], toks2[-1]["id"], young["id"]], "reader tokens deleted: none"),
        ("ten not read", {"down": True}, [toks[0]["id"], toks2[-1]["id"], young["id"]],
         "reader tokens deleted none - ten not read"),
        ("forgejo-repo-creds-es not Ready", {"ready": {"forgejo-repo-creds-es": "False"}},
         [toks[0]["id"], toks2[-1]["id"], young["id"]], "reader tokens deleted none - argocd not synced (not Ready)")):
    reset(copy.deepcopy(st), {PATH_V: dv(v2)})
    ten(**k8s)
    rc, out = run()
    check(f"a run over 3 h later, {label}: the run passes; {len(want_left)} older token(s) left, said",
          (rc, [t["id"] for t in bot_tokens(fstate())][:len(want_left)], said in flat(out)), (0, want_left, True))

st2 = copy.deepcopy(s2["state"])
st2["users"][BOT]["is_admin"] = True
reset(st2, {PATH_V: dv(v2)})
rc, out = run()
check("drift: a reader made admin by hand is made a user again, the run passes", (rc, scope_view(fstate())),
      (0, WANT_SCOPE))

# ── refused, nothing minted, Vault not written ───────────────────────────────────────────────────────────────────
for label, edit, said in (
        ("a team of that name with someone else in it (sm in argocd-read)",
         lambda st: next(t for t in st["teams"].values() if t["name"] == "argocd-read")["members"].append("sm"),
         "REFUSED: team schnappy/argocd-read holds sm"),
        ("the reader put in Owners by hand (push and admin everywhere)",
         lambda st: st["teams"]["1"]["members"].append(BOT), "REFUSED: argocd-reader pushes to"),
        ("the reader put in a team writing infra's code (push, no admin)",
         lambda st: st["teams"].update({"7": {"id": 7, "name": "writers", "description": "", "permission": "write",
                                              "units_map": {"repo.code": "write"}, "includes_all_repositories": False,
                                              "can_create_org_repo": False, "members": [BOT], "repos": ["infra"]}}),
         "REFUSED: argocd-reader pushes to schnappy/infra, administers nothing"),
        ("the reader switched off (inactive)", lambda st: st["users"][BOT].update(active=False),
         "REFUSED: argocd-reader is switched off"),
        ("the reader made admin, Forgejo not making it a user again", None, "REFUSED: argocd-reader is argocd-reader, admin True")):
    st2 = copy.deepcopy(s2["state"])
    if edit:
        edit(st2)
    else:
        st2["users"][BOT]["is_admin"] = True
    reset(st2, {PATH_V: dv(v2)})
    if not edit:
        forgejo("POST", "/_fail", {"method": "PATCH", "path": "/admin/users/argocd-reader$", "ignore": ["admin"]})
    rc, out = run()
    check(f"refused: {label} - said; no token minted, Vault not written",
          (rc != 0, said in flat(out), mints(fstate()), kv()["writes"]), (True, True, [], []))
write_vars(os.path.join(W, "infra-a_repo"))
reset(copy.deepcopy(s2["state"]), {PATH_V: dv(v2)})
rc, out = run()
check("refused: infra names a repository of another org on the host - the derivation fails the run, nothing minted",
      (rc != 0, "not a repository of schnappy" in flat(out), mints(fstate())), (True, True, []))
write_vars()

# ── a failure after the mint ─────────────────────────────────────────────────────────────────────────────────────
V2 = dv(v2)
for label, fault, gone, said in (
        ("Forgejo makes the token with more scope than asked", ("forgejo", {"method": "POST",
                                                                            "path": "/users/argocd-reader/tokens$",
                                                                            "scopes": ["all"]}),
         True, "this run's new token deleted again"),
        ("a PR repository's pull requests not listed", ("forgejo", {"method": "GET", "path": "/pulls$", "status": 403}),
         True, "this run's new token deleted again"),
        ("the Vault write refused (someone wrote between the read and the write)",
         ("vault", {"method": "GET", "path": "forgejo-readonly", "bump": True}), False, "the Vault write itself failed"),
        ("the read-back failing, Vault then holding the token", ("vault", {"method": "GET", "path": "forgejo-readonly",
                                                                          "status": 503, "nth": 2}),
         False, "Vault holds this run's token")):
    reset(copy.deepcopy(s2["state"]), {PATH_V: dict(V2)})
    (vault if fault[0] == "vault" else forgejo)("POST", "/_fail", fault[1])
    rc, out = run()
    n = len(bot_tokens(fstate()))
    check(f"failure: {label} - fails, said; this run's token {'deleted again' if gone else 'kept'}",
          (rc != 0, said in flat(out), n), (True, True, len(toks2) + (0 if gone else 1)))

# ── Vault sealed, missing; no preview ────────────────────────────────────────────────────────────────────────────
reset()
vault("POST", "/_fail", {"method": "GET", "path": "forgejo-readonly", "status": 503, "error": "Vault is sealed"})
rc, out = run()
check("Vault sealed: fails before a token is minted, nothing written", (rc != 0, mints(fstate()), kv()["writes"]),
      (True, [], []))
reset(kv={})
rc, out = run()
check("Vault path missing (a first install): written create-only (cas 0)",
      (rc, [w["cas"] for w in kv()["writes"]], dv(kv())["data"]["username"] if dv(kv())["data"] else None),
      (0, [0], BOT))
reset()
rc, out = run("--check")
check("--check: refused, nothing changed", (rc != 0, "no check mode" in out, BOT in fstate()["state"]["users"],
                                            kv()["writes"]), (True, True, False, []))

# ── retiring the admin's Argo CD tokens ──────────────────────────────────────────────────────────────────────────
ENVR = {"FORGEJO_READONLY_TOKEN": READONLY}
SYNCED_ES = {"forgejo-repo-creds-es": "True", "forgejo-pi-repo-es": "True"}


def synced(token):
    return {"ready": SYNCED_ES, "readonly": token,
            "creds": {"forgejo-repo-creds": (BOT, token), "forgejo-pi-repo": (BOT, token)}}


reset()
rc, out = run("--tags", "retire")
check("retire before the reader is in Vault (.env empty): refused, said, nothing deleted",
      (rc != 0, "run task deploy:argocd-reader first" in flat(out), admin_names(fstate())), (True, True, ADMIN_ALL))
rc, out = run()
st, vv = fstate(), kv()
reader_token = (dv(vv)["data"] or {}).get("token", "none")
for label, k8s, said in (
        ("ten still on the admin (the repo-creds not switched)", {"ready": SYNCED_ES},
         "does not hand Argo CD the reader with Vault's token"),
        ("infra's repo-creds ExternalSecrets missing", dict(synced(reader_token), ready={}),
         "not all Ready (not: forgejo-repo-creds-es, forgejo-pi-repo-es)"),
        ("forgejo-pi-repo still the admin's", dict(synced(reader_token), creds={
            "forgejo-repo-creds": (BOT, reader_token), "forgejo-pi-repo": ("forgejo_admin", ADMIN_PI)}),
         "does not hand Argo CD the reader with Vault's token")):
    ten(**k8s)
    rc, out = run("--tags", "retire", env=ENVR)
    check(f"retire with {label}: refused, said, nothing deleted", (rc != 0, said in flat(out), admin_names(fstate())),
          (True, True, ADMIN_ALL))
ten(**synced(reader_token))
rc, out = run("--tags", "retire", "--limit", "pis", env=ENVR)
check("retire with ten left out (--limit pis): refused, nothing deleted",
      (rc != 0, "REFUSED: the cluster not read on ten" in flat(out), admin_names(fstate())), (True, True, ADMIN_ALL))
e = copy.deepcopy(vv["kv"][PATH_V])
e["data"]["token"] = READONLY
reset(copy.deepcopy(st["state"]), {PATH_V: e})
ten(**synced(READONLY))
rc, out = run("--tags", "retire", env=ENVR)
check("retire while Vault still hands Argo CD the token .env names: refused, said, nothing deleted",
      (rc != 0, "still holds the token .env names" in flat(out), admin_names(fstate())), (True, True, ADMIN_ALL))
st3 = copy.deepcopy(st["state"])
st3["tokens"]["99"] = {"id": 99, "user": "forgejo_admin", "name": "argocd-20260101T000000", "sha1": "x" * 32 +
                       le(reader_token), "token_last_eight": le(reader_token), "scopes": ["read:repository"]}
reset(st3, {PATH_V: vv["kv"][PATH_V]})
ten(**synced(reader_token))
rc, out = run("--tags", "retire", env=ENVR)
check("retire whose target is one Vault and ten still hold (a token of the admin's with the same last eight): "
      "refused, nothing deleted",
      (rc != 0, "REFUSED: a token of the admin's Vault or ten still holds" in flat(out), len(admin_names(fstate()))),
      (True, True, 5))
reset(copy.deepcopy(st["state"]), {PATH_V: vv["kv"][PATH_V]})
ten(**synced(reader_token))
open(os.path.join(W, "kubectl.log"), "w").close()
rc, out = run("--tags", "retire")
s7 = fstate()
check("retire, ten synced (.env empty): the admin's Argo CD tokens deleted - the repo-creds' (recorded in Vault), the "
      "readonly one (Vault's history), argocd-* (setup-argocd's) - its others kept; the reader's tokens and Vault "
      "untouched; ten read only",
      (rc, admin_names(s7), [t["id"] for t in bot_tokens(s7)], kv()["writes"], sorted(set(kubectl_calls()))),
      (0, ["woodpecker-push"], [t["id"] for t in bot_tokens(st)], [],
       ["get externalsecret -n argocd", "get secret -n argocd"]))
rc, out = run("--tags", "retire")
check("retire again: nothing left - passes", (rc, admin_names(fstate())), (0, ["woodpecker-push"]))
hist = {"data": {"token": reader_token, "username": BOT, "retire_last_eight": ",".join(sorted([le(ADMIN_ARGO),
                                                                                              le(ADMIN_PI)]))},
        "version": 5, "history": {"4": {"token": READONLY}}}
hist["history"]["5"] = hist["data"]
reset(copy.deepcopy(st["state"]), {PATH_V: hist})
ten(**synced(reader_token))
rc, out = run("--tags", "retire")
check("retire with .env empty and the readonly token in Vault's history alone (not recorded): found there - deleted",
      (rc, admin_names(fstate())), (0, ["woodpecker-push"]))
st4 = copy.deepcopy(st["state"])
st4["tokens"] = {k: t for k, t in st4["tokens"].items() if not t["name"].startswith("argocd-2")}
reset(st4, {PATH_V: {"data": {"token": reader_token, "username": BOT}, "version": 1}})
ten(**synced(reader_token))
rc, out = run("--tags", "retire")
check("retire with nothing named anywhere (.env empty, no history, nothing recorded, no argocd* token): refused",
      (rc != 0, "nothing to retire" in out, admin_names(fstate())), (True, True, ["pi-repo", "readonly",
                                                                              "woodpecker-push"]))

# ── seed-vault-secrets.yml's argocd/forgejo-readonly: Vault's kept, .env only for a first install ────────────────
seed = yaml.safe_load(open(SEED))[0]
flat_tasks = []


def walk(ts):
    for t in ts or []:
        flat_tasks.append(t)
        for k in ("block", "rescue", "always"):
            walk(t.get(k))


walk(seed["tasks"])
pick = [t for t in flat_tasks if t.get("name") in ("Read argocd/forgejo-readonly (its token is setup-argocd-reader's)",
                                                   "Seed argocd/forgejo-readonly token")]
required = next(t for t in flat_tasks if "Validate required env-sourced" in (t.get("name") or ""))["loop"]
check("seed: its argocd/forgejo-readonly read and write found; .env's FORGEJO_READONLY_TOKEN no longer required",
      (len(pick), "FORGEJO_READONLY_TOKEN" in required), (2, False))
SEED_PLAY = os.path.join(W, "seed.yml")
yaml.safe_dump([{"name": "seed's argocd/forgejo-readonly", "hosts": "localhost", "connection": "local",
                 "gather_facts": False, "vars": {"vault_addr": f"http://127.0.0.1:{VP}", "vault_token_value": VAULT_TOKEN},
                 "tasks": pick}], open(SEED_PLAY, "w"), sort_keys=False)


def seed_run(kvs, env):
    vault("POST", "/_reset", kvs)
    r = subprocess.run([AP, "-i", "localhost,", SEED_PLAY], capture_output=True, text=True, cwd=W, env=dict(ENV, **env))
    return r.returncode, kv()


BOTV = {"token": "reader-token-0000", "username": BOT, "retire_last_eight": "aaaaaaaa"}
rc, after = seed_run({PATH_V: {"data": dict(BOTV), "version": 4}}, ENVR)
check("seed: Vault's token, username and record kept over .env's old admin token, written with the version read",
      (rc, dv(after), [w["cas"] for w in after["writes"]]), (0, {"data": BOTV, "version": 5}, [4]))
rc, after = seed_run({}, {"FORGEJO_READONLY_TOKEN": "vagrant-not-a-token"})
check("seed: a first install takes the token from .env (the Vagrant copy's placeholder)",
      (rc, dv(after)["data"], [w["cas"] for w in after["writes"]]), (0, {"token": "vagrant-not-a-token"}, [0]))
vault("POST", "/_reset", {PATH_V: {"data": dict(BOTV), "version": 4}})
vault("POST", "/_fail", {"method": "GET", "path": "forgejo-readonly", "status": 503, "error": "Vault is sealed"})
r = subprocess.run([AP, "-i", "localhost,", SEED_PLAY], capture_output=True, text=True, cwd=W, env=dict(ENV, **ENVR))
check("seed: a sealed Vault fails the seed - nothing written over the reader's token",
      (r.returncode != 0, kv()["writes"], dv(kv())["data"]), (True, [], BOTV))

# ── setup-argocd no longer mints on the admin ────────────────────────────────────────────────────────────────────
SA = yaml.safe_load(open(os.path.join(ROOT, "deploy/ansible/playbooks/setup-argocd.yml")))
sa_text = yaml.safe_dump(SA)
creds = [t for p in SA for t in (p.get("tasks") or []) if "forgejo-repo-creds" in yaml.safe_dump(t)]
check("setup-argocd: no token minted or listed on Forgejo, no admin credential in Argo CD's repo-creds (its url alone)",
      ("/tokens" in sa_text, [sorted((t.get("kubernetes.core.k8s") or {}).get("definition", {}).get("stringData", {}))
                              for t in creds]), (False, [["type", "url"]]))

# ── no secret on a command line; no command but ten's reads and the derivation ───────────────────────────────────
canary = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(1.5)", CANARY])
canary.wait()
watch.send_signal(signal.SIGTERM)
watch.wait(timeout=30)
w = json.load(open(WATCH_OUT))
fence = open(os.path.join(W, "fence.log")).read().splitlines() if os.path.exists(os.path.join(W, "fence.log")) else []
check("the watch bites: a process with a known secret on its command line is seen",
      any(h["secret"] == 6 for h in w["hits"]), True)
check(f"no secret on any command line over every run ({w['scans']} scans of /proc); nothing fenced run; the admin "
      "password's $( ) and backticks never run",
      ([h for h in w["hits"] if h["secret"] != 6], fence, w["scans"] > 50,
       os.path.exists(os.path.join(W, "ran")) or os.path.exists(os.path.join(W, "ran2"))), ([], [], True, False))
ALLOWED = {"The ExternalSecrets of argocd - their Ready", "What argocd's Secrets hold - their last eight characters",
           "The repositories Argo CD reads, from infra's manifests"}
cmds = []
for play in yaml.safe_load(open(PB)):
    stack = list(play.get("tasks") or [])
    while stack:
        x = stack.pop()
        stack += (x.get("block") or []) + (x.get("rescue") or [])
        for k, val in x.items():
            if "." in k and k.split(".")[-1] in ("shell", "command", "raw", "script", "expect"):
                text = " ".join(val["argv"]) if isinstance(val, dict) and "argv" in val else \
                    (val.get("cmd", "") if isinstance(val, dict) else str(val))
                text = re.sub(r"\{\{.*?\}\}", "X", text)
                verbs = [m[1] for m in re.findall(r"\bkubectl((?:\s+(?:--kubeconfig|-n)\s+\S+)*)\s+(\S+)", text)]
                ok = x.get("name") in ALLOWED and set(verbs) <= {"get"} and \
                    not re.search(r"(^|[\s|;(])(curl|wget|vault|forgejo|ssh)(\s|$)", text)
                cmds.append((play.get("hosts"), x.get("name"), ok))
check("no play runs a command of its own but ten's two reads (kubectl get alone) and the derivation",
      ([c for c in cmds if not c[2]], sorted({c[1] for c in cmds}) == sorted(ALLOWED)), ([], True))

for p in procs:
    p.terminate()
print("argocd-reader: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
