#!/bin/bash
# setup-velero.yml's offsite git mirror on ten: every repository of the Forgejo organisation production's GitOps
# repository lives in, pushed daily to a repository of its own on the Pis' backup volume - a backup that KEEPS what it
# held. Forgejo read with a token of read:repository, read:organization and read:user alone, minted BY the mirror's own
# non-admin reader (git-mirror, made anew at each new token - never adopted: Forgejo's sign-up is open; a team of the
# organisation's gives it code read on every repository; never the admin's token - operator 2026-10-20: no admin account
# in any automation - nor its password, which sat in the old origin URL); the token proven from a file of its own before
# the sync's is replaced; every run reads back that it reaches every repository the organisation has (the admin's
# count) and pushes to none. The push key is the mirror's own, authorized on both Pis for the gate alone, from ten alone
# - the gate (the key's forced command) the only thing it runs there: check, init, refs, git-receive-pack, last-success,
# keep-unmarked, each checked and bounded.
#
# The daily sync runs here for real: real git against a local stand-in for Forgejo (bare repositories under $W/forgejo,
# its API from a curl stub reading them), an ssh stub that runs the rendered gate as sshd would (the asked command in
# SSH_ORIGINAL_COMMAND, its standard input passed on - git-receive-pack reads it), a counting mountpoint stub. It must:
# mirror every repository, each backup's HEAD its default branch; keep a branch deleted upstream, a tag, the commit a
# force-push replaced (its reflog); refuse a repository Forgejo serves empty while its backup holds refs; mirror an empty
# one; never write a repository it did not make; write nothing once the volume is lost; name each failure; write
# last-success and its Prometheus result after a clean run alone; send the token on curl's config and git's credential
# helper only, on every call.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'chmod -R u+rwX "$W" 2> /dev/null; rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/mirror" "$W/pi" "$W/textfile" "$W/forgejo/schnappy"
# curl: argv and the -K config recorded. The organisation's repositories: each bare repository under $W/forgejo/schnappy
# (its default branch its HEAD's), FORCE_LIST=<names> lists those instead (a listed one Forgejo lacks); 50 a page.
# PROBE_CODE: the probe's code (-w); USER_CODE, PROBE_LOGIN, PROBE_ADMIN: the user API's answer; FAIL_API: refused;
# PUSH_ON / ADMIN_ON=<repo>: its permissions; NO_PERMS: none given; PAGES=<n>: n full pages of fillers;
# BRANCH_<repo>=<branch>: the default branch the API says
cat > "$W/bin/curl" <<'STUB'
#!/usr/bin/env python3
import json, os, re, subprocess, sys
W = os.environ["W"]
a = sys.argv[1:]
conf = open(a[a.index("-K") + 1]).read() if "-K" in a else ""
open(os.path.join(W, "curl-calls"), "a").write(json.dumps({"argv": a, "config": conf}) + "\n")
if os.environ.get("FAIL_API"):
    sys.exit(22)
url = a[-1]
out = a[a.index("-o") + 1] if "-o" in a else None
def answer(body, code="200"):
    if out and out != "/dev/null":
        open(out, "w").write(body)
    elif not out:
        sys.stdout.write(body)
    if "-w" in a:
        sys.stdout.write(code)
if url.endswith("/user"):
    answer(json.dumps({"login": os.environ.get("PROBE_LOGIN", "git-mirror"), "is_admin": os.environ.get("PROBE_ADMIN") == "1"}),
           os.environ.get("USER_CODE", "200"))
    sys.exit(0)
if "-w" in a:  # the probe's own listing call: its code alone
    answer("[]", os.environ.get("PROBE_CODE", "200"))
    sys.exit(0)
page = int(re.search(r"page=(\d+)", url).group(1))
org = os.path.join(W, "forgejo", "schnappy")
if os.environ.get("PAGES"):
    names = [f"r{page}x{i}" for i in range(50)] if page <= int(os.environ["PAGES"]) else []
else:
    if os.environ.get("FORCE_LIST") is not None:
        names = os.environ["FORCE_LIST"].split()
    else:
        names = sorted(d[:-4] for d in os.listdir(org) if d.endswith(".git"))
    names = names[(page - 1) * 50: page * 50]
def default(n):
    forced = os.environ.get("BRANCH_" + re.sub(r"\W", "_", n))
    if forced:
        return forced
    p = os.path.join(org, n + ".git")
    head = subprocess.run(["git", "-C", p, "symbolic-ref", "--short", "HEAD"], capture_output=True, text=True).stdout.strip() \
        if os.path.isdir(p) else ""
    return head or "main"
repos = []
for n in names:
    r = {"name": n, "default_branch": default(n)}
    if not os.environ.get("NO_PERMS"):
        r["permissions"] = {"pull": True, "push": n == os.environ.get("PUSH_ON"), "admin": n == os.environ.get("ADMIN_ON")}
    repos.append(r)
answer(json.dumps(repos))
STUB
# ssh: as sshd runs the mirror key's forced command - the asked command in SSH_ORIGINAL_COMMAND, the gate run with the
# standard input passed on (git-receive-pack reads it). Recorded: its options, host, command. REFUSE_HOST=<host>: refused
cat > "$W/bin/ssh" <<'STUB'
#!/bin/bash
opts=() host="" cmd=()
while [ $# -gt 0 ]; do
  case "$1" in
    -o|-i|-p|-l) opts+=("$1" "$2"); shift 2 ;;
    -*) opts+=("$1"); shift ;;
    *) if [ -z "$host" ]; then host=$1; else cmd+=("$1"); fi; shift ;;
  esac
done
printf '%s\n' "$(printf '%s ' "${opts[@]}")| $host | ${cmd[*]}" >> "$W/ssh-calls"
[ "${REFUSE_HOST:-}" != "${host#*@}" ] || { echo "Permission denied (publickey)." >&2; exit 255; }
SSH_ORIGINAL_COMMAND="${cmd[*]}" exec bash "$W/gate.sh"
STUB
# mountpoint: the volume mounted unless MOUNTED=no; MOUNT_LOST_AFTER=<n>: lost from its (n+1)th check on
cat > "$W/bin/mountpoint" <<'STUB'
#!/bin/bash
n=$(( $(cat "$W/mount-checks" 2> /dev/null || echo 0) + 1 )); echo "$n" > "$W/mount-checks"
[ "${MOUNTED:-yes}" = yes ] || exit 1
[ -z "${MOUNT_LOST_AFTER:-}" ] || [ "$n" -le "$MOUNT_LOST_AFTER" ]
STUB
printf '#!/bin/bash\ncat >> "$W/logged"\n' > "$W/bin/logger"
chmod +x "$W/bin"/*
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYGM'
import base64, getpass, json, os, shutil, subprocess, sys, time
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render, trust_as_template  # noqa: E402
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
def walk(ts):
    for t in ts or []:
        yield t
        for k in ("block", "rescue", "always"):
            yield from walk(t.get(k))
play = next(p for p in yaml.safe_load(open("deploy/ansible/playbooks/setup-velero.yml"))
            if p.get("name") == "Offsite git mirror to the Pis")
tasks = list(walk(play["tasks"]))
names = [t.get("name") for t in tasks]
by_name = {t.get("name"): t for t in tasks}
pv = {k: trust_as_template(x) if isinstance(x, str) else x for k, x in play["vars"].items()}
v = dict(pv, forgejo_admin_user="admin", forgejo_admin_password="THE-ADMIN-PW", offsite_backup_user="sm",
         keepalived_vip="10.0.0.5", ansible_host="192.168.11.2", inventory_hostname="target")
R = lambda t, **kw: str(render(str(t), **dict(v, **kw)))  # noqa: E731
text = yaml.safe_dump(play)
TOKEN = "0123456789abcdef0123456789abcdef01234567"

# ── what it mirrors, from where ─────────────────────────────────────────
argocd = yaml.safe_load(open("deploy/ansible/playbooks/setup-argocd.yml"))[0]["vars"]
check("every repository of the organisation production's GitOps repository is in", R("{{ git_mirror_org }}"),
      argocd["argocd_root_repo"].split("/")[0])
check("no one repository named, none of the admin's", ("forgejo_admin/" in text, "/monitor.git" in text), (False, False))
check("Forgejo as the environment serves it: production's https://git.pmon.dev (forgejo_root_url unset), the copy's own "
      "(its VIP, http) - never git.pmon.dev there", (R("{{ git_mirror_base }}"),
      R("{{ git_mirror_base }}", forgejo_root_url="http://192.168.56.50:3000/")),
      ("https://git.pmon.dev", "http://192.168.56.50:3000"))

# ── the reader: made anew at each new token, no admin, its team ──────────
NOT_WORKS = dict(git_mirror_enabled=True, _git_mirror_token_works=False, ansible_check_mode=False)
check("the reader is git-mirror, never the admin (asserted before anything is made)",
      (R("{{ git_mirror_user }}"),
       condition(by_name["The admin's credentials, and a reader that is not the admin"]["ansible.builtin.assert"]["that"],
                 **dict(v, git_mirror_user="admin"))), ("git-mirror", False))
dele = by_name["The reader of before deleted - its tokens, keys and grants with it (never adopted)"]
made = by_name["The reader made"]
check("an account of that name deleted first (purge: its tokens, keys, grants) - only where Forgejo has one, never in "
      "a preview; then made anew, every new token",
      ([condition(dele["when"], **dict(NOT_WORKS, _git_mirror_account={"status": st}, ansible_check_mode=cm))
        for st, cm in ((200, False), (404, False), (200, True))], "purge=true" in dele["ansible.builtin.uri"]["url"],
       dele["ansible.builtin.uri"]["method"], names.index(dele["name"]) < names.index(made["name"]),
       condition(made["when"], **NOT_WORKS),
       condition(made["when"], **dict(NOT_WORKS, _git_mirror_token_works=True))),
      ([True, False, False], True, "DELETE", True, True, False))
check("  made private, no admin in its body, the password no_log",
      ("admin" not in made["ansible.builtin.uri"]["body"], made["ansible.builtin.uri"]["body"]["visibility"],
       made.get("no_log")), (True, "private", True))
noadm = by_name["The reader is no admin"]["ansible.builtin.assert"]["that"]
check("the reader as it sees itself: its own login, no admin - else refused",
      [condition(noadm, git_mirror_user="git-mirror", _git_mirror_self={"json": j}) for j in (
          {"login": "git-mirror", "is_admin": False}, {"login": "git-mirror", "is_admin": True},
          {"login": "forgejo_admin", "is_admin": True})], [True, False, False])
team = by_name["The reader's team made, where missing"]["ansible.builtin.uri"]["body"]
check("its team: code read on every repository of the organisation (new ones too), nothing more - no other unit, no "
      "repository made", (team["permission"], team["units_map"], team["includes_all_repositories"],
                          team["can_create_org_repo"]), ("read", {"repo.code": "read"}, True, False))
check("  the team's scope written back each run (the same body)",
      by_name["The reader's team's scope - code read on every repository, nothing more"]["ansible.builtin.uri"]["body"], team)
alone = by_name["The reader's team holds no one else"]["ansible.builtin.assert"]["that"]
check("the team holds the reader alone - anyone else in it refused, nothing changed",
      [condition(alone, git_mirror_user="git-mirror", _git_mirror_members={"json": j})
       for j in ([], [{"login": "git-mirror"}], [{"login": "git-mirror"}, {"login": "sm"}])], [True, True, False])
cap = by_name["Every team read (one page, not full)"]["ansible.builtin.assert"]["that"]
check("the teams read on one page: 49 pass, 50 refused (not all read)",
      [condition(cap, _git_mirror_teams={"json": [{}] * n}) for n in (49, 50)], [True, False])
atok = by_name["The admin's mirror tokens of before revoked"]
admin_tokens = [{"id": 1, "name": "git-mirror-20261001T000000"}, {"id": 2, "name": "argocd-root"},
                {"id": 3, "name": "woodpecker-infra"}, {"id": 4, "name": "git-mirror-20261002T000000"},
                {"id": 5, "name": "my-git-mirror-x"}]
pages = {"results": [{"json": admin_tokens[:3]}, {"json": admin_tokens[3:]}, {"json": []}]}
check("the admin's mirror tokens of before (git-mirror-*) revoked, from every page - Argo CD's, Woodpecker's, a name "
      "merely holding it kept; 404 (gone already) is done",
      ([x["id"] for x in render(atok["loop"], _git_mirror_admin_tokens=pages)],
       atok["ansible.builtin.uri"]["method"], 404 in atok["ansible.builtin.uri"]["status_code"], atok.get("no_log")),
      ([1, 4], "DELETE", True, True))
afull = by_name["Every one of the admin's tokens read (the last page not full)"]["ansible.builtin.assert"]["that"]
check("  the admin's tokens read to a page not full - more refused",
      [condition(afull, _git_mirror_admin_tokens=r) for r in (pages, {"results": [{"json": [{"id": 0, "name": "x"}] * 50}] * 10})],
      [True, False])

# ── the token: minted by the reader, proven from its own file, then put in place ──
post = [t for t in tasks if (t.get("ansible.builtin.uri") or {}).get("method") == "POST"
        and str(t["ansible.builtin.uri"]["url"]).endswith("/tokens")]
check("a new token: the organisation's repositories read (and whose it is), nothing more; minted BY the reader (its "
      "own basic auth), no_log; only when the kept one does not read",
      [(t["ansible.builtin.uri"]["body"]["scopes"], t["ansible.builtin.uri"]["user"], t.get("no_log"),
        condition(t.get("when"), **dict(NOT_WORKS, _git_mirror_token_works=True)), condition(t.get("when"), **NOT_WORKS))
       for t in post], [(["read:repository", "read:organization", "read:user"], "{{ git_mirror_user }}", True, False, True)])
check("no admin's token minted anywhere (every token minted under the reader's name)",
      [t["ansible.builtin.uri"]["url"] for t in post], ["{{ _git_mirror_forgejo }}/users/{{ git_mirror_user }}/tokens"])
block = by_name["The new token in place, proven"]
put_new, prove, move = block["block"]
check("the new token written beside the sync's (from stdin, 0600, no_log), proven from that file, and only then moved "
      "over the sync's", ([t.get("name") for t in block["block"]], "/dev/stdin" in str(put_new), "0600" in str(put_new),
                          str(put_new["ansible.builtin.command"]["argv"][-1]), put_new.get("no_log"),
                          prove["environment"]["TOKEN_FILE"], move["ansible.builtin.command"]["argv"]),
      (["The new token beside the sync's", "The new token reads the organisation's repositories - and is the reader's, no admin's",
        "The new token where the sync's credential helper reads it"], True, True, "{{ git_mirror_token_file }}.new", True,
       "{{ git_mirror_token_file }}.new", ["mv", "-f", "{{ git_mirror_token_file }}.new", "{{ git_mirror_token_file }}"]))
resc = block["rescue"]
check("a new token that does not read: deleted again (its id), its file removed, the play failed - the sync's as it was",
      ([(t.get("ansible.builtin.uri") or {}).get("method") for t in resc],
       ((resc[1].get("ansible.builtin.file") or {}).get("path"), (resc[1].get("ansible.builtin.file") or {}).get("state")),
       "ansible.builtin.fail" in resc[2]), (["DELETE", None, None], ("{{ git_mirror_token_file }}.new", "absent"), True))
check("the new token proven by HTTP 200 as the reader, no admin, alone",
      [condition(prove["failed_when"], _git_mirror_new_read={"stdout": x}, git_mirror_user="git-mirror")
       for x in ("HTTP 200 git-mirror false", "HTTP 200 git-mirror true", "HTTP 200 forgejo_admin true", "HTTP 200 UNSCOPED",
                 "HTTP 401", "USER API HTTP 502")], [False, True, True, True, True, True])
probe = by_name["The mirror's token reads the organisation's repositories"]
judge = lambda out: condition(probe["failed_when"], _git_mirror_read={"stdout": out})  # noqa: E731
check("the probe: a 200 with its owner, UNSCOPED, 401/403, none judged; the user API down, a 5xx, no answer fail the play "
      "(no token minted on a blip)",
      [judge(x) for x in ("HTTP 200 git-mirror false", "HTTP 200 forgejo_admin true", "HTTP 200 UNSCOPED", "HTTP 401",
                          "HTTP 403", "NO TOKEN", "HTTP 000", "HTTP 502", "USER API HTTP 500", "USER API NOT READ", "HTTP 200")],
      [False, False, False, False, False, False, True, True, True, True, True])
works = by_name["Whether the kept token reads"]["ansible.builtin.set_fact"]["_git_mirror_token_works"]
check("the kept token: HTTP 200 as the reader, no admin, alone",
      [str(render(works, _git_mirror_read=r, git_mirror_user="git-mirror")) for r in (
          {"stdout": "HTTP 200 git-mirror false"}, {"stdout": "HTTP 200 forgejo_admin true"},
          {"stdout": "HTTP 200 git-mirror true"}, {"stdout": "HTTP 200 UNSCOPED"}, {"stdout": "HTTP 401"},
          {"stdout": "NO TOKEN"}, {"skipped": True})], ["True", "False", "False", "False", "False", "False", "False"])
creds = os.path.join(W, "token")
open(creds, "w").write(TOKEN)
def env_with(**e):
    return dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W, **e)
def calls():
    p = os.path.join(W, "curl-calls")
    out = [json.loads(x) for x in open(p)] if os.path.exists(p) else []
    os.path.exists(p) and os.remove(p)
    return out
script = R(play["vars"]["_git_mirror_probe"])
def probe_run(have=True, **e):
    calls()
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True, env=env_with(
        TOKEN_FILE=creds if have else os.path.join(W, "none"), API="https://git.pmon.dev/api/v1/orgs/x/repos",
        USER_API="https://git.pmon.dev/api/v1/user", **e))
    cs = calls()
    return r.stdout.strip(), len(cs), all(f"token {TOKEN}" in c["config"] and TOKEN not in " ".join(c["argv"]) for c in cs)
check("the probe's script: its owner said; UNSCOPED on the user API's 401/403; its code on anything else; NO TOKEN - "
      "the token on curl's config on every call, never its command line",
      [probe_run(), probe_run(PROBE_LOGIN="forgejo_admin", PROBE_ADMIN="1"), probe_run(USER_CODE="403"),
       probe_run(USER_CODE="500"), probe_run(PROBE_CODE="401"), probe_run(have=False)],
      [("HTTP 200 git-mirror false", 2, True), ("HTTP 200 forgejo_admin true", 2, True), ("HTTP 200 UNSCOPED", 2, True),
       ("USER API HTTP 500", 2, True), ("HTTP 401", 1, True), ("NO TOKEN", 0, True)])
check("  its user API answer kept in a file beside the token, removed after", [f for f in os.listdir(W) if f.startswith(".probe.")], [])

# ── what it reaches: every repository, none pushed to - and every one the organisation has ──
reach_script = R(play["vars"]["_git_mirror_reach"])
def reach_run(**e):
    calls()
    r = subprocess.run(["bash", "-c", reach_script], capture_output=True, text=True, env=env_with(
        TOKEN_FILE=creds, API="https://git.pmon.dev/api/v1/orgs/x/repos", **e))
    cs = calls()
    return r.stdout.strip(), bool(cs) and all(f"token {TOKEN}" in c["config"] for c in cs)
check("what it reaches: every repository read, none pushed to or administered - else named; permissions missing, the "
      "listing failing, over 20 pages: NOT READ; the token on every call",
      [reach_run(FORCE_LIST="ops infra site"), reach_run(FORCE_LIST="ops infra", PUSH_ON="infra"),
       reach_run(FORCE_LIST="ops infra", ADMIN_ON="ops"), reach_run(FORCE_LIST="ops", NO_PERMS="1"),
       reach_run(FORCE_LIST="ops", FAIL_API="1")[0], reach_run(PAGES="25")],
      [("PUSHES NONE 3", True), ("PUSHES infra", True), ("PUSHES ops", True), ("NOT READ", True), "NOT READ",
       ("NOT READ", True)])
rtask = by_name["What the mirror's token reaches - read, never pushed to"]
check("  the play fails unless it reaches some and pushes to none; run in a preview where the kept token reads",
      ([condition(rtask["failed_when"], _git_mirror_reach_read={"stdout": o})
        for o in ("PUSHES NONE 3", "PUSHES NONE 0", "PUSHES infra", "NOT READ")], rtask.get("check_mode"),
       [condition(rtask["when"], git_mirror_enabled=True, ansible_check_mode=cm, _git_mirror_token_works=w)
        for cm, w in ((False, False), (True, True), (True, False))]),
      ([False, True, True, True], False, [True, True, False]))
every = by_name["The mirror reads every repository the organisation has"]
org_pages = lambda *ns: {"results": [{"json": [{}] * n} for n in ns]}  # noqa: E731
check("it reads every repository the organisation has (the admin's count): 20 of 20 pass; 3 of 20 (a lost grant: the "
      "public ones alone) refused; a last page not empty (not all listed) refused",
      [condition(every["ansible.builtin.assert"]["that"], _git_mirror_reach_read={"stdout": out}, _git_mirror_org_pages=pg,
                 _org_count=str(sum(len(x["json"]) for x in pg["results"])))
       for out, pg in (("PUSHES NONE 20", org_pages(20, 0)), ("PUSHES NONE 3", org_pages(20, 0)),
                       ("PUSHES NONE 50", org_pages(*([50] * 20))))], [True, False, False])

# ── the gate, the key, the Pis ───────────────────────────────────────────
gtask = by_name["The mirror's gate on each Pi"]
check("the gate on every Pi, root's 0755, the play's own script",
      (gtask["delegate_to"], gtask["loop"], gtask["ansible.builtin.copy"]["owner"], gtask["ansible.builtin.copy"]["mode"],
       gtask["ansible.builtin.copy"]["content"]), ("{{ item }}", "{{ groups['pis'] }}", "root", "0755", "{{ _git_mirror_gate_script }}"))
mk = by_name["The mirror's push key, made where it has none"]["ansible.builtin.command"]
pub = by_name["The mirror's push key's public half - derived from the key (a passphrase on it fails here)"]
key = by_name["The mirror's push key authorized on each Pi - for the gate alone, from ten alone"]
ak = key["ansible.posix.authorized_key"]
check("its push key: the mirror's own (in its directory, not its user's login key), made where none, no passphrase; its "
      "public half derived from it (no .pub to miss), a passphrase failing it",
      (R("{{ _git_mirror_key }}"), mk["creates"], mk["argv"][mk["argv"].index("-N") + 1],
       pub["ansible.builtin.command"]["argv"]), ("/var/lib/git-mirror/id_ed25519", "{{ _git_mirror_key }}", "",
                                                  ["ssh-keygen", "-y", "-P", "", "-f", "{{ _git_mirror_key }}"]))
check("authorized on every Pi for the mirror user: its gate as forced command, restrict, from ten alone; its other keys kept",
      (key["delegate_to"], key["loop"], ak["user"], R(ak["key_options"]), ak["exclusive"],
       R(ak["key"], _git_mirror_pubkey={"stdout": "ssh-ed25519 AAAAKEY old-comment"})),
      ("{{ item }}", "{{ groups['pis'] }}", "{{ _git_mirror_owner }}",
       'restrict,from="192.168.11.2",command="/usr/local/bin/git-mirror-gate"', False, "ssh-ed25519 AAAAKEY offsite-git-mirror@target"))
kh = R(by_name["The VIP's known hosts - both Pis' keys"]["ansible.builtin.copy"]["content"], _pi_host_keys={"results": [
    {"content": base64.b64encode(b"ssh-ed25519 AAAApi1 root@pi1").decode()},
    {"content": base64.b64encode(b"ssh-ed25519 AAAApi2 root@pi2").decode()}]})
check("both Pis' host keys known under the alias the sync checks (one line each)", kh.splitlines(),
      ["pi-vip ssh-ed25519 AAAApi1", "pi-vip ssh-ed25519 AAAApi2"])
pchk = by_name["The push accepted on each Pi - its gate, the volume mounted and writable"]
argv = list(render(pchk["ansible.builtin.command"]["argv"], **dict(v, item="pi2", hostvars={"pi2": {"ansible_host": "192.168.11.6"}})))
check("the push proven through each Pi's own address at deploy (not only the VIP's holder), as the sync connects - its "
      "key, the alias, host keys checked; anything but OK fails the play",
      (pchk["loop"], argv[0], argv[-2:], argv[argv.index("-i") + 1] if "-i" in argv else None, "HostKeyAlias=pi-vip" in argv,
       "StrictHostKeyChecking=yes" in argv, "BatchMode=yes" in argv,
       [condition(pchk["failed_when"], _git_mirror_pi_check={"rc": rc, "stdout": o}) for rc, o in ((0, "OK"), (0, ""), (3, "OK"))]),
      ("{{ groups['pis'] }}", "ssh", ["sm@192.168.11.6", "check"], "/var/lib/git-mirror/id_ed25519", True, True, True,
       [False, True, True]))
kept = by_name["A repository on the volume the mirror did not make, kept aside"]
check("a repository the mirror did not make kept aside at deploy, through the VIP's holder, before the sync",
      (list(render(kept["ansible.builtin.command"]["argv"], **v))[-2:],
       names.index(kept["name"]) < names.index("The mirror synced now")), (["sm@10.0.0.5", "keep-unmarked"], True))
td = by_name["The node_exporter textfile directory"]["ansible.builtin.file"]
mf = by_name["The mirror's metrics file, the mirror user's"]["ansible.builtin.file"]
check("the textfile directory root's 0755 (as setup-host-hardening's); the metrics file the mirror user's 0644 - its "
      "owner and mode put right every run, its content and times never touched",
      (R(td["path"]), td["state"], td["owner"], td["mode"], R(mf["path"]), mf["state"], mf["owner"], mf["mode"],
       mf["modification_time"], mf["access_time"]),
      ("/var/lib/node_exporter/textfile", "directory", "root", "0755", "/var/lib/node_exporter/textfile/offsite_git_mirror.prom",
       "touch", "{{ _git_mirror_owner }}", "0644", "preserve", "preserve"))
host_td = next(t for t in yaml.safe_load(open("deploy/ansible/playbooks/setup-host-hardening.yml"))[0]["tasks"]
               if (t.get("ansible.builtin.file") or {}).get("path") == "{{ node_exporter_textfile_dir }}")["ansible.builtin.file"]
check("  setup-host-hardening's directory the same (root, 0755): neither undoes the other",
      (host_td["owner"], host_td["group"], host_td["mode"]), (td["owner"], td["group"], td["mode"]))
unit_t = by_name["Create offsite backup systemd service"]
script_t = by_name["Write offsite backup sync script"]
timer_t = by_name["Enable and start offsite backup timer"]
unit = R(unit_t["ansible.builtin.copy"]["content"])
check("the unit written before the script (a stop between them left the old unit, no User=, to run the new script as "
      "root); as the mirror's user; a failed night tried again (45 min, 3 in 6 h)",
      (names.index(unit_t["name"]) < names.index(script_t["name"]), "User=sm" in unit, "Restart=on-failure" in unit,
       "RestartSec=45min" in unit, "StartLimitBurst=3" in unit, "StartLimitIntervalSec=6h" in unit), (True,) * 6)
check("the script root's 0755 (its user cannot rewrite it); the timer enabled and started",
      (script_t["ansible.builtin.copy"]["owner"], script_t["ansible.builtin.copy"]["group"], script_t["ansible.builtin.copy"]["mode"],
       timer_t["ansible.builtin.systemd"]["enabled"], timer_t["ansible.builtin.systemd"]["state"]), ("root", "root", "0755", True, "started"))
now_t = by_name["The mirror synced now"]
res_t = by_name["Its result is this run's, every repository of the organisation counted"]
check("run at deploy with systemctl start (joins a run going - the module skipped it while activating), not in a "
      "preview; its result this run's and every repository counted - else the play fails",
      (now_t["ansible.builtin.command"]["argv"], condition(now_t["when"], git_mirror_enabled=True, offsite_backup_enabled=True,
                                                           ansible_check_mode=True),
       [condition(res_t["ansible.builtin.assert"]["that"], _git_mirror_started={"stdout": "1000"}, _ts=ts, _count=c,
                  _git_mirror_reach_read={"stdout": "PUSHES NONE 20"}) for ts, c in (("1005", "20"), ("999", "20"), ("1005", "3"))]),
      (["systemctl", "start", "offsite-backup.service"], False, [True, False, False]))
pw = [t.get("name") for t in tasks if "_git_mirror_password" in json.dumps({k: x for k, x in t.items() if k != "name"})
      and "ansible.builtin.set_fact" not in t and "block" not in t and not t.get("no_log")]
check("every task carrying the reader's password is no_log", pw, [])

# ── the gate itself ──────────────────────────────────────────────────────
pi = os.path.join(W, "pi")
gate = R(play["vars"]["_git_mirror_gate_script"], git_mirror_pi_dir=pi)
open(os.path.join(W, "gate.sh"), "w").write(gate)
def gate_run(cmd, **e):
    r = subprocess.run(["bash", os.path.join(W, "gate.sh")], capture_output=True, text=True, input="",
                       env=env_with(SSH_ORIGINAL_COMMAND=cmd, **e))
    return r.returncode, r.stdout.strip()
def git(*a, cwd=None, check_=True):
    return subprocess.run(["git", *a], cwd=cwd, capture_output=True, text=True, check=check_,
                          env=dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1")).stdout.strip()
def cfg(repo, key):
    return git("-C", repo, "config", "--get", key, check_=False)
def reset_pi():
    shutil.rmtree(pi); os.makedirs(pi)
reset_pi()
rc_init = gate_run("init ops main")
r_ops = os.path.join(pi, "ops.git")
check("gate init: a bare repository made, marked as the mirror's, kept as a backup (every update logged and never expired, "
      "no gc, no deletion), HEAD its branch",
      (rc_init[0], cfg(r_ops, "mirror.made-by"), cfg(r_ops, "core.logAllRefUpdates"), cfg(r_ops, "gc.reflogExpire"),
       cfg(r_ops, "gc.reflogExpireUnreachable"), cfg(r_ops, "gc.pruneExpire"), cfg(r_ops, "gc.auto"), cfg(r_ops, "receive.autogc"),
       cfg(r_ops, "receive.denyDeletes"), git("-C", r_ops, "symbolic-ref", "HEAD")),
      (0, "offsite-git-mirror", "always", "never", "never", "never", "0", "false", "true", "refs/heads/main"))
git("init", "-q", "--bare", os.path.join(pi, "theirs.git"))
check("gate: a repository it did not make is never written - init and receive-pack refuse it (5)",
      (gate_run("init theirs main")[0], gate_run(f"git-receive-pack '{pi}/theirs.git'")[0], cfg(os.path.join(pi, "theirs.git"), "gc.auto")),
      (5, 5, ""))
check("gate refuses what is not its own: a bad name, a bad branch, a path outside its volume, another verb, extra or "
      "missing arguments, a command smuggled after a verb (2)",
      [gate_run(c)[0] for c in ("init ../x main", "init -x main", "init x a..b", "init x a;b", "git-receive-pack '/etc/x.git'",
                                f"git-receive-pack '{pi}/../x.git'", "rm -rf /", "check now", "init x", "", "check; id",
                                "last-success yesterday", "refs a b")],
      [2] * 13)
check("gate: every verb refuses on an unmounted volume (3), nothing made",
      ([gate_run(c, MOUNTED="no")[0] for c in ("check", "init new main", "refs ops", f"git-receive-pack '{pi}/ops.git'",
                                               "last-success 20261115T040000Z", "keep-unmarked")], os.path.exists(os.path.join(pi, "new.git"))),
      ([3] * 6, False))
check("gate check and refs: OK; a repository's ref count (0 for none)",
      (gate_run("check"), gate_run("refs ops"), gate_run("refs none")), ((0, "OK"), (0, "0"), (0, "0")))
os.chmod(pi, 0o555)
unwritable = gate_run("check")[0]
os.chmod(pi, 0o755)
check("gate check: an unwritable volume refused (3)", unwritable, 3 if os.geteuid() != 0 else unwritable)
check("gate last-success: written whole", (gate_run("last-success 20261115T040000Z")[0],
                                           open(os.path.join(pi, "last-success")).read()), (0, "20261115T040000Z\n"))
kept_out = gate_run("keep-unmarked")
check("gate keep-unmarked: a repository it did not make kept aside under its name (never pushed over), its own left",
      (kept_out[0], kept_out[1].startswith("kept theirs.git as theirs.pre-mirror-"), os.path.isdir(r_ops),
       os.path.exists(os.path.join(pi, "theirs.git")), gate_run("keep-unmarked")[1]),
      (0, True, True, False, ""))
check("gate: each step bounded (timeout around git, mountpoint, receive-pack and the last-success write)",
      ("timeout --kill-after=10 120 git" in gate, "timeout 60 mountpoint" in gate, "exec timeout --kill-after=30 1800 git-receive-pack" in gate,
       "timeout 60 sh -c" in gate), (True, True, True, True))

# ── the sync, for real ───────────────────────────────────────────────────
named = subprocess.run(["id", "-un"], capture_output=True, text=True)
if named.returncode != 0:
    # the sync refuses any user but the mirror's, by name (id -un): a uid with no name (a container run with --user, not
    # CI's root) cannot be it - its part not run here, said (never a pass)
    print(f"SKIPPED the sync's real runs: uid {os.getuid()} has no name here ({named.stderr.strip()})")
    print("git-mirror: " + ("ALL-PASS (the sync's real runs skipped)" if not fails else f"{fails} FAILED"))
    sys.exit(1 if fails else 0)
me = named.stdout.strip()
forgejo = os.path.join(W, "forgejo", "schnappy")
prom = os.path.join(W, "textfile", "offsite_git_mirror.prom")
sync = by_name["Write offsite backup sync script"]
SV = dict(offsite_backup_user=me, git_mirror_dir=os.path.join(W, "mirror"), git_mirror_token_file=creds,
          git_mirror_pi_dir=pi, node_exporter_textfile_dir=os.path.join(W, "textfile"),
          forgejo_root_url="file://" + os.path.join(W, "forgejo") + "/")
body = R(sync["ansible.builtin.copy"]["content"], **SV)
open(os.path.join(W, "sync.sh"), "w").write(body)
def commit(work, msg):
    git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", msg, cwd=work)
def upstream(name, branches=("main",), tags=(), default="main"):
    """A bare repository in the stand-in Forgejo, its branches each one commit apart, HEAD its default."""
    bare = os.path.join(forgejo, name + ".git")
    shutil.rmtree(bare, ignore_errors=True)
    git("init", "-q", "--bare", "-b", default, bare)
    work = os.path.join(W, "work-" + name)
    shutil.rmtree(work, ignore_errors=True)
    git("init", "-q", "-b", default, work)
    for br in branches:
        git("checkout", "-q", "-B", br, cwd=work)
        commit(work, f"{name} {br} {time.time()}")
        git("push", "-q", bare, br, cwd=work)
    for t in tags:
        git("-c", "user.name=t", "-c", "user.email=t@t", "tag", "-a", "-m", t, t, cwd=work)
        git("push", "-q", bare, t, cwd=work)
    return bare, work
def refs(repo):
    out = git("-C", repo, "for-each-ref", "--format=%(refname) %(objectname)", check_=False)
    return dict(l.split(" ", 1) for l in out.splitlines() if l)
def run(**e):
    for f in ("ssh-calls", "logged", "mount-checks", "curl-calls"):
        os.path.exists(os.path.join(W, f)) and os.remove(os.path.join(W, f))
    r = subprocess.run(["bash", os.path.join(W, "sync.sh")], capture_output=True, text=True, timeout=120, env=env_with(**e))
    return r.returncode, r.stdout
def last():
    p = os.path.join(pi, "last-success")
    return open(p).read() if os.path.exists(p) else ""
reset_pi()
ops_bare, ops_work = upstream("ops", branches=("main", "dev"), tags=("v1",))
infra_bare, _ = upstream("infra", default="trunk", branches=("trunk",))
rc, out = run()
ops_pi, infra_pi = os.path.join(pi, "ops.git"), os.path.join(pi, "infra.git")
check("a first run: every repository mirrored - each backup Forgejo's refs exactly, its HEAD Forgejo's default branch, "
      "marked as the mirror's; last-success written; 0",
      (rc, refs(ops_pi) == refs(ops_bare), refs(infra_pi) == refs(infra_bare), git("-C", ops_pi, "symbolic-ref", "HEAD", check_=False),
       git("-C", infra_pi, "symbolic-ref", "HEAD", check_=False), cfg(ops_pi, "mirror.made-by"), bool(last())),
      (0, True, True, "refs/heads/main", "refs/heads/trunk", "offsite-git-mirror", True))
cl = os.path.join(W, "restore")
shutil.rmtree(cl, ignore_errors=True)
git("clone", "-q", infra_pi, cl, check_=False)
check("it restores: a plain clone of a backup checks out Forgejo's default branch's commit",
      git("-C", cl, "rev-parse", "HEAD", check_=False), refs(infra_bare).get("refs/heads/trunk"))
plines = open(prom).read().splitlines() if os.path.exists(prom) else []
metrics = [l for l in plines if l and not l.startswith("#")]
check("its result for Prometheus: its time now, every repository counted, one sample each, the HELP and TYPE lines",
      (len(metrics), metrics[1:2], bool(metrics) and abs(int(metrics[0].split()[1]) - time.time()) < 120,
       sum(l.startswith("# TYPE ") for l in plines)), (2, ["offsite_git_mirror_repositories 2"], True, 2))
cs = calls()
sc = open(os.path.join(W, "ssh-calls")).read().splitlines() if os.path.exists(os.path.join(W, "ssh-calls")) else []
check("the token on curl's config on every API call, on no command line, never to the Pi",
      (bool(cs), all(f"token {TOKEN}" in c["config"] for c in cs), any(TOKEN in " ".join(c["argv"]) for c in cs),
       any(TOKEN in l for l in sc)), (True, True, False, False))
key_path = os.path.join(W, "mirror", "id_ed25519")
check("every ssh with the mirror's key alone, the Pi's host keys checked under its alias, no prompt; to the VIP; each "
      "command a gate verb", (bool(sc) and all(f"-i {key_path} " in l and "IdentitiesOnly=yes" in l and "StrictHostKeyChecking=yes" in l
                                              and "HostKeyAlias=pi-vip" in l and "BatchMode=yes" in l for l in sc),
                              {l.split(" | ")[1] for l in sc}, sorted({l.split(" | ")[2].split()[0] for l in sc})),
      (True, {f"{me}@10.0.0.5"}, ["git-receive-pack", "init", "last-success"]))
# Forgejo changes: a branch deleted, a branch force-pushed, a tag added - the backup keeps what it held
old_main = refs(ops_bare)["refs/heads/main"]
git("push", "-q", ops_bare, ":dev", cwd=ops_work)
git("checkout", "-q", "main", cwd=ops_work)
git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--amend", "--allow-empty", "-m", "rewritten", cwd=ops_work)
git("push", "-q", "--force", ops_bare, "main", cwd=ops_work)
git("-c", "user.name=t", "-c", "user.email=t@t", "tag", "-a", "-m", "v2", "v2", cwd=ops_work)
git("push", "-q", ops_bare, "v2", cwd=ops_work)
dev_before = refs(ops_pi).get("refs/heads/dev")
rc, out = run()
pr = refs(ops_pi)
check("Forgejo deleted a branch, force-pushed another, added a tag: the backup keeps the deleted branch at its commit, "
      "takes the new main and tag - and its reflog keeps the commit main had (nothing Forgejo rewrites is lost); 0",
      (rc, pr.get("refs/heads/dev") == dev_before and dev_before is not None,
       pr.get("refs/heads/main") == refs(ops_bare)["refs/heads/main"], "refs/tags/v2" in pr,
       old_main in git("-C", ops_pi, "reflog", "show", "--format=%H", "refs/heads/main", check_=False).split()),
      (0, True, True, True, True))
# Forgejo serves a repository empty (deleted and made again, a restore gone wrong): named, its backup kept
infra_refs = refs(infra_pi)
lsc = last(); prom_before = open(prom).read()
shutil.rmtree(infra_bare); git("init", "-q", "--bare", "-b", "trunk", infra_bare)
rc, out = run()
check("Forgejo serves a repository empty while its backup holds refs: named, its backup kept as it was, the others done; "
      "the unit failed, last-success and the Prometheus result left as the last good run's",
      (rc, "infra(emptied in Forgejo - its backup of" in out, refs(infra_pi) == infra_refs, last() == lsc,
       open(prom).read() == prom_before), (1, True, True, True, True))
# an empty repository in Forgejo and in its backup: mirrored as it is
upstream("infra", default="trunk", branches=("trunk",))
shutil.rmtree(infra_pi)
shutil.rmtree(os.path.join(W, "mirror", "infra.git"), ignore_errors=True)
git("init", "-q", "--bare", "-b", "main", os.path.join(forgejo, "fresh.git"))
rc, out = run()
check("an empty repository (no commit yet): its backup made, HEAD set, counted - no push; the run 0",
      (rc, os.path.isdir(os.path.join(pi, "fresh.git")), git("-C", os.path.join(pi, "fresh.git"), "symbolic-ref", "HEAD", check_=False),
       [l for l in open(prom).read().splitlines() if l.startswith("offsite_git_mirror_repositories")]),
      (0, True, "refs/heads/main", ["offsite_git_mirror_repositories 3"]))
check("  two good runs: still one sample of each metric", len([l for l in open(prom).read().splitlines() if l and not l.startswith("#")]), 2)
# a repository on the volume the mirror did not make (the old mirror's monitor.git): never pushed over
upstream("monitor")
git("init", "-q", "--bare", os.path.join(pi, "monitor.git"))
before = sorted(os.listdir(os.path.join(pi, "monitor.git")))
rc, out = run()
check("a repository on the volume it did not make: never written (the gate refuses it), named; the others done; failed",
      (rc, "monitor(its repository on the Pi)" in out, sorted(os.listdir(os.path.join(pi, "monitor.git"))) == before,
       refs(os.path.join(pi, "monitor.git"))), (1, True, True, {}))
gate_run("keep-unmarked")
rc, out = run()
check("  kept aside (keep-unmarked, the play's at deploy): the mirror makes its own, the old one beside it; 0",
      (rc, cfg(os.path.join(pi, "monitor.git"), "mirror.made-by"), any(x.startswith("monitor.pre-mirror-") for x in os.listdir(pi))),
      (0, "offsite-git-mirror", True))
# the volume lost mid-run: nothing written after it, the unit failed, no last-success - at its first check, halfway, at
# its last (a clean run's own count)
shutil.rmtree(os.path.join(pi, "fresh.git"), ignore_errors=True)
run()
total = int(open(os.path.join(W, "mount-checks")).read())
for lost in (1, total // 2, total - 1):
    lsc = last()
    shutil.rmtree(os.path.join(pi, "fresh.git"), ignore_errors=True)
    rc, out = run(MOUNT_LOST_AFTER=str(lost))
    checks = int(open(os.path.join(W, "mount-checks")).read())
    check(f"the volume lost after {lost} mount checks: the unit fails, no last-success, the checks after it all refused",
          (rc, last() == lsc, checks > lost), (1, True, True))
shutil.rmtree(os.path.join(pi, "fresh.git"), ignore_errors=True)
rc, out = run(MOUNTED="no")
check("the volume not mounted: every repository named, nothing written, failed",
      (rc, "(its repository on the Pi)" in out, os.path.exists(os.path.join(pi, "fresh.git"))), (1, True, False))
rc, out = run()
check("  mounted again: done; 0", rc, 0)
# failures named, the stale copy never pushed, the rest still done
git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "newer", cwd=ops_work)
git("push", "-q", ops_bare, "main", cwd=ops_work)
before_ops = refs(ops_pi)
os.chmod(ops_bare, 0o000)
rc, out = run()
os.chmod(ops_bare, 0o755)
ops_calls = [l for l in (open(os.path.join(W, "ssh-calls")).read().splitlines() if os.path.exists(os.path.join(W, "ssh-calls")) else [])
             if l.split(" | ")[2].split()[1:2] == ["ops"] or "/ops.git" in l]
check("a fetch failing: named, its stale copy NOT pushed - nothing sent to the Pi for it (the backup as it was), the "
      "others done; failed", (rc, "ops(fetch)" in out, refs(ops_pi) == before_ops, ops_calls) if os.geteuid() != 0
      else (1, True, True, []), (1, True, True, []))
rc, out = run(FORCE_LIST="ops infra ghost")
check("a listed repository that does not clone: named, the others done; failed", (rc, "ghost(clone)" in out), (1, True))
rc, out = run(FORCE_LIST="ops bad$(name)")
check("a name that is no plain name: named, never used; failed",
      (rc, "(its name)" in out, "bad$(name)" in (open(os.path.join(W, "ssh-calls")).read() if os.path.exists(os.path.join(W, "ssh-calls")) else "")),
      (1, True, False))
rc, out = run(FORCE_LIST="ops", BRANCH_ops="x;rm")
check("a default branch that is no plain name: named, never used; failed", (rc, "ops(its default branch)" in out), (1, True))
rc, out = run(FAIL_API="1")
check("the organisation's repositories not listed: fails, nothing done", (rc, "not listed" in out,
      os.path.exists(os.path.join(W, "ssh-calls"))), (1, True, False))
rc, out = run(FORCE_LIST="")
check("none listed: fails (an empty organisation is no clean run)", (rc, "no repository listed" in out), (1, True))
rc, out = run(PAGES="25")
check("more pages than it reads: fails, said - never a mirror of part of the organisation", (rc, "not all listed" in out), (1, True))
open(creds, "w").write("")
rc, out = run()
open(creds, "w").write(TOKEN)
check("no token: fails, said", (rc, "no token" in out), (1, True))
os.chmod(prom, 0o444); os.chmod(os.path.join(W, "textfile"), 0o555)
rc, out = run()
os.chmod(os.path.join(W, "textfile"), 0o755); os.chmod(prom, 0o644)
check("its result not written for Prometheus: the unit fails, said",
      (rc, "not written for Prometheus" in out) if os.geteuid() != 0 else (1, True), (1, True))
rc, out = run(REFUSE_HOST="10.0.0.5")
check("the Pi refusing its key: every repository named, failed", (rc, "(its repository on the Pi)" in out), (1, True))
home = os.path.join(W, "home"); os.makedirs(home, exist_ok=True)
open(os.path.join(home, ".gitconfig"), "w").write('[url "file:///nowhere/"]\n\tinsteadOf = file://\n')
rc, out = run(HOME=home)
check("the mirror user's ~/.gitconfig never applies to the mirror's git (a URL rewrite there changes nothing)", rc, 0)
other = R(sync["ansible.builtin.copy"]["content"], **dict(SV, offsite_backup_user="someone-else"))
r = subprocess.run(["bash", "-c", other], capture_output=True, text=True, env=env_with())
check("run as anyone but the mirror's user (sudo by hand, the old unit as root): refused before anything",
      (r.returncode, "REFUSED: run as someone-else" in r.stdout), (1, True))
# its credential helper, as git runs it, for production's base and the copy's (http, a port)
def fill(base, host):
    b = R(sync["ansible.builtin.copy"]["content"], **dict(SV, forgejo_root_url=base + "/"))
    lines = b.splitlines()
    i = next(n for n, l in enumerate(lines) if l.strip().startswith("helper=("))
    helper_def = lines[i] + "\n" + lines[i + 1]
    snip = (f"mirror_user=git-mirror; tokenf={creds}\nforgejo_helper=\"credential.{base}.helper\"\n{helper_def}\n"
            f"printf 'protocol={base.split(':')[0]}\\nhost={host}\\n\\n' | git \"${{helper[@]}}\" credential fill")
    r = subprocess.run(["bash", "-c", snip], capture_output=True, text=True,
                       env=dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1"))
    return f"password={TOKEN}" in r.stdout
check("its credential helper answers Forgejo's host alone - production's https, the copy's http with a port; another "
      "host (a redirect's) nothing", (fill("https://git.pmon.dev", "git.pmon.dev"), fill("https://git.pmon.dev", "other.example.org"),
                                       fill("http://192.168.56.50:3000", "192.168.56.50:3000"),
                                       fill("http://192.168.56.50:3000", "other.example.org")), (True, False, True, False))
check("its credential helper never stores or erases (git's store helper used nowhere)",
      ("store --file" in body, '[ \\"\\$1\\" = get ] || return 0' in body), (False, True))
check("its fetch and clone: no redirect followed, a stalled transfer ended after 10 minutes (a large repository's pack "
      "prepared first)", ("http.followRedirects=false" in body, "http.lowSpeedTime=600" in body), (True, True))
check("its push: every ref forced, none deleted (no --mirror), bounded",
      ("push --force --porcelain" in body and "'refs/*:refs/*'" in body and "push -q --mirror" not in body,
       "timeout --kill-after=30 1800 git -C" in body), (True, True))
print("git-mirror: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYGM
