#!/bin/bash
# setup-velero.yml's offsite git mirror on ten, as the playbook holds it: every repository of the Forgejo organisation
# production's GitOps repository lives in (setup-argocd's argocd_root_repo) - it mirrored forgejo_admin/monitor, a
# repository production does not have, and its daily job had failed since July unnoticed. Forgejo read with a token of
# read:repository and read:organization alone (never the admin's password, which sat in the old origin URL), written
# on ten from stdin into a 0600 file a credential helper of its own reads - one that answers git's "get" alone: git's
# store helper erases what it holds on any 401 (a blip), and every sync after failed; the token kept while it reads the organisation's
# repositories - a 401/403 (or none) makes a new one, a network failure proves nothing and fails the play, minting
# none; a new one that does not read deleted again; the older ones deleted once it reads. The sync runs as the mirror's
# user and is proven at deploy. The daily sync, run here with curl, git, ssh and logger stubs: the organisation's
# repositories listed page by page, each cloned bare when new, its origin set bare, fetched, its bare repository made
# on the Pi when new, pushed whole; a failure named, the rest still going, the unit failed; last-success written on
# the Pi only after a clean run; the token on no command line.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/mirror"
# curl: argv and the -K config recorded; the API's repository list from $W/pages/<n> (none: empty); FAIL_API: fails
cat > "$W/bin/curl" <<'STUB'
#!/usr/bin/env python3
import json, os, re, sys
W = os.environ["W"]
a = sys.argv[1:]
conf = open(a[a.index("-K") + 1]).read() if "-K" in a else ""
open(os.path.join(W, "curl-calls"), "a").write(json.dumps({"argv": a, "config": conf}) + "\n")
if os.environ.get("FAIL_API"):
    sys.exit(22)
url = a[-1]
if "-w" in a:  # the probe: its HTTP code
    print(os.environ.get("PROBE_CODE", "200"), end="")
    sys.exit(0)
page = int(re.search(r"page=(\d+)", url).group(1))
p = os.path.join(W, "pages", str(page))
names = open(p).read().split() if os.path.exists(p) else []
print(json.dumps([{"name": n} for n in names]))
STUB
# git: its argv and environment's prompt recorded; clone makes the bare directory; FETCH_FAILS=<repo>: its fetch fails
cat > "$W/bin/git" <<'STUB'
#!/bin/bash
echo "git $* PROMPT=${GIT_TERMINAL_PROMPT:-unset} SSH=${GIT_SSH_COMMAND:-}" >> "$W/git-calls"
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  [ "${args[$i]}" = clone ] && { dest=${args[$((${#args[@]} - 1))]}; mkdir -p "$dest"; touch "$dest/HEAD"; exit 0; }
done
case "$*" in *" fetch "*) [ -n "${FETCH_FAILS:-}" ] && [[ $* == *"/$FETCH_FAILS.git"* ]] && exit 128 ;; esac
exit 0
STUB
# ssh: its argv recorded; INIT_FAILS=<repo>: the Pi's repository for it not made (a full disk, a permission)
cat > "$W/bin/ssh" <<'STUB'
#!/bin/bash
echo "ssh $*" >> "$W/ssh-calls"
[ -n "${INIT_FAILS:-}" ] && [[ $* == *"/$INIT_FAILS.git/HEAD || git init"* ]] && { echo "fatal: cannot mkdir" >&2; exit 128; }
exit 0
STUB
printf '#!/bin/bash\ncat > /dev/null\n' > "$W/bin/logger"
chmod +x "$W/bin"/*
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYGM2'
import json, os, re, shutil, subprocess, sys
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
pv = {k: trust_as_template(x) if isinstance(x, str) else x for k, x in play["vars"].items()}
v = dict(pv, forgejo_admin_user="admin", forgejo_admin_password="THE-ADMIN-PW", offsite_backup_user="sm",
         keepalived_vip="10.0.0.5")
R = lambda t: str(render(str(t), **v))  # noqa: E731
# the organisation: production's GitOps repository's (setup-argocd)
argocd = yaml.safe_load(open("deploy/ansible/playbooks/setup-argocd.yml"))[0]["vars"]
check("every repository of the organisation production's GitOps repository is in", R("{{ git_mirror_org }}"),
      argocd["argocd_root_repo"].split("/")[0])
text = yaml.safe_dump(play)
check("no one repository named, none of the admin's", ("forgejo_admin/" in text, "/monitor" in text), (False, False))
# the token
post = [t for t in tasks if (t.get("ansible.builtin.uri") or {}).get("method") == "POST"]
check("a new token: the organisation's repositories read, nothing more; no_log; only when the kept one does not read",
      [(t["ansible.builtin.uri"]["body"]["scopes"], t.get("no_log"),
        condition(t.get("when"), git_mirror_enabled=True, _git_mirror_token_works=True, ansible_check_mode=False),
        condition(t.get("when"), git_mirror_enabled=True, _git_mirror_token_works=False, ansible_check_mode=False))
       for t in post], [(["read:repository", "read:organization"], True, False, True)])
probe = next(t for t in tasks if t.get("name") == "The mirror's token reads the organisation's repositories")
judge = lambda out: condition(probe["failed_when"], _git_mirror_read={"stdout": out})  # noqa: E731
check("the probe: 200 kept, 401/403/none replaced; no answer or a 5xx fails the play (no token minted on it)",
      [judge(x) for x in ("HTTP 200", "HTTP 401", "HTTP 403", "NO TOKEN", "HTTP 000", "HTTP 502")],
      [False, False, False, False, True, True])
# the probe's script itself: the token from the file, on curl's config
script = R(play["vars"]["_git_mirror_probe"])
creds = os.path.join(W, "creds")
open(creds, "w").write("0123456789abcdef0123456789abcdef01234567")
def probe_run(code, have=True):
    os.path.exists(os.path.join(W, "curl-calls")) and os.remove(os.path.join(W, "curl-calls"))
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True, env=dict(
        os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W, PROBE_CODE=code,
        TOKEN_FILE=creds if have else os.path.join(W, "none"), API="https://git.pmon.dev/api/v1/orgs/x/repos"))
    calls = [json.loads(x) for x in open(os.path.join(W, "curl-calls"))] if os.path.exists(os.path.join(W, "curl-calls")) else []
    return r.stdout.strip(), [("0123456789abcdef" in " ".join(c["argv"]), "token 0123456789abcdef" in c["config"]) for c in calls]
check("the probe's script: HTTP 200 / 401 said, the token on curl's config only; no file, NO TOKEN",
      [probe_run("200"), probe_run("401"), probe_run("200", have=False)],
      [("HTTP 200", [(False, True)]), ("HTTP 401", [(False, True)]), ("NO TOKEN", [])])
block = next(t for t in play["tasks"] if t.get("name") == "The new token in place, proven")
resc = block.get("rescue") or []
check("a new token that does not read: deleted again (its id), the play failed",
      [(t.get("ansible.builtin.uri") or {}).get("method") for t in resc] + [("ansible.builtin.fail" in t) for t in resc],
      ["DELETE", None, False, True])
write = next(t for t in block["block"] if "helper reads it" in t.get("name", ""))
check("the token written on ten from stdin (no copy content: a temp file on the controller), 0600, no_log",
      ("ansible.builtin.copy" in write, "/dev/stdin" in str(write), '"0600"' in json.dumps(write) or "0600" in str(write),
       write.get("no_log")), (False, True, True, True))
names = [t.get("name") for t in tasks]
dele = [t for t in tasks if (t.get("ansible.builtin.uri") or {}).get("method") == "DELETE" and "older" in t.get("name", "")]
check("the older tokens deleted after the new one is proven to read",
      bool(dele) and names.index("The new token reads the organisation's repositories") < names.index(dele[0]["name"]), True)
# which tokens go: the mirror's own alone - the admin's others (Argo CD's, Woodpecker's) never
admin_tokens = [{"id": 1, "name": "git-mirror-20261001T000000"}, {"id": 2, "name": "argocd-root"},
                {"id": 3, "name": "woodpecker-infra"}, {"id": 4, "name": "git-mirror-20261002T000000"},
                {"id": 5, "name": "my-git-mirror-x"}]
check("the older tokens: the mirror's own (git-mirror-*) alone - Argo CD's, Woodpecker's, a name merely holding it kept",
      [x["id"] for x in render(dele[0]["loop"], _git_mirror_tokens={"json": admin_tokens})] if dele else None, [1, 4])
check("the older tokens: none read (the kept token reads) - none deleted",
      list(render(dele[0]["loop"], _git_mirror_tokens={"skipped": True})) if dele else None, [])
# whether the kept token reads: an HTTP 200 alone - a refusal, no token, a skipped read (the mirror off) is none
works = next((t for t in tasks if t.get("name") == "Whether the kept token reads"), None)
fact = (works or {}).get("ansible.builtin.set_fact", {}).get("_git_mirror_token_works")
check("the kept token reads on HTTP 200 alone (401, 403, NO TOKEN, a skipped read: a new one)",
      [str(render(fact, _git_mirror_read=r)) for r in ({"stdout": "HTTP 200"}, {"stdout": "HTTP 401"},
                                                        {"stdout": "HTTP 403"}, {"stdout": "NO TOKEN"}, {"skipped": True})]
      if fact else None, ["True", "False", "False", "False", "False"])
# the new token's proof: anything but HTTP 200 fails it - the rescue deletes it, the older ones stay
proof = next((t for t in block["block"] if t.get("name") == "The new token reads the organisation's repositories"), None)
check("the new token proven by HTTP 200 alone (401, 403, 000, 502 fail the block)",
      [condition(proof["failed_when"], _git_mirror_new_read={"stdout": x})
       for x in ("HTTP 200", "HTTP 401", "HTTP 403", "HTTP 000", "HTTP 502")] if proof else None,
      [False, True, True, True, True])
svc = next(t for t in tasks if (t.get("ansible.builtin.copy") or {}).get("dest") == "/etc/systemd/system/offsite-backup.service")
now = next((t for t in tasks if (t.get("ansible.builtin.systemd") or {}).get("name") == "offsite-backup.service"), None)
check("the sync as the mirror's user; run once at deploy, a failure failing the play (not in a preview)",
      ("User=sm" in R(svc["ansible.builtin.copy"]["content"]), now is not None and now["ansible.builtin.systemd"]["state"],
       now is not None and [condition(now.get("when"), git_mirror_enabled=True, offsite_backup_enabled=True,
                                      ansible_check_mode=c) for c in (False, True)]),
      (True, "started", [True, False]))
# the daily sync, as the playbook writes it
sync = next(t for t in tasks if (t.get("ansible.builtin.copy") or {}).get("dest") == "/usr/local/bin/offsite-backup-sync.sh")
body = R(sync["ansible.builtin.copy"]["content"]).replace(R("{{ git_mirror_token_file }}"), creds) \
    .replace(R("{{ git_mirror_dir }}"), os.path.join(W, "mirror"))
open(os.path.join(W, "sync.sh"), "w").write(body)
def run(pages, existing=(), **env):
    for f in ("git-calls", "ssh-calls", "curl-calls"):
        os.path.exists(os.path.join(W, f)) and os.remove(os.path.join(W, f))
    shutil.rmtree(os.path.join(W, "mirror")); os.makedirs(os.path.join(W, "mirror"))
    shutil.rmtree(os.path.join(W, "pages"), ignore_errors=True); os.makedirs(os.path.join(W, "pages"))
    for i, names_ in enumerate(pages, 1):
        open(os.path.join(W, "pages", str(i)), "w").write(" ".join(names_))
    for e in existing:
        os.makedirs(os.path.join(W, "mirror", e + ".git")); open(os.path.join(W, "mirror", e + ".git", "HEAD"), "w").close()
    r = subprocess.run(["bash", os.path.join(W, "sync.sh")], capture_output=True, text=True, timeout=60,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W, **env))
    rd = lambda f: open(os.path.join(W, f)).read().splitlines() if os.path.exists(os.path.join(W, f)) else []  # noqa: E731
    return r.returncode, r.stdout, rd("git-calls"), rd("ssh-calls"), rd("curl-calls")
org = R("{{ git_mirror_org }}")
rc, out, g, sh, cu = run([["ops", "infra"]], existing=["ops"])
push = [l for l in g if " push " in l]
check("two repositories (one new): the new cloned, both origins set bare, fetched, their Pi repositories made when new, "
      "pushed whole; last-success written; 0",
      (rc, sum(" clone " in l and f"/{org}/infra.git" in l for l in g), sum(" clone " in l for l in g),
       sorted(re.search(r"set-url origin (\S+)", l).group(1) for l in g if "set-url origin" in l),
       sum(" fetch " in l for l in g), sum("git init -q --bare" in l for l in sh),
       sorted(re.search(r"(\S+)$", l.split(" PROMPT=")[0]).group(1).rsplit("/", 1)[1] for l in push),
       sum("last-success" in l for l in sh)),
      (0, 1, 1, [f"https://git.pmon.dev/{org}/infra.git", f"https://git.pmon.dev/{org}/ops.git"], 2, 2,
       ["infra.git", "ops.git"], 1))
check("its git: no prompt (none to answer), the Pi's host keys checked, the credential helper reset before its own",
      (all("PROMPT=0" in l for l in g), all("StrictHostKeyChecking=yes" in l and "UserKnownHostsFile=" in l for l in push),
       all(" -c credential.helper= -c credential.helper=!" in l for l in g if " fetch " in l or " clone " in l)),
      (True, True, True))
# the helper as git runs it (its action an argument): "get" answers the token; "erase" and "store" (git's after a 401,
# a success) leave the file as it is - no store helper anywhere
fetch_line = next((l for l in g if " fetch " in l), "")
helper = re.search(r"credential\.helper=(!f\(\) \{.*?\}; f)(?= )", fetch_line)  # as git is given it
def helper_run(action):
    r = subprocess.run(["sh", "-c", helper.group(1)[1:] + " " + action], input="protocol=https\nhost=git.pmon.dev\n\n",
                       capture_output=True, text=True)
    return r.stdout, open(creds).read()
check("its credential helper: get answers the token; erase and store leave it be; git's store helper used nowhere",
      (helper is not None and helper_run("get"), helper is not None and helper_run("erase")[1],
       helper is not None and helper_run("store")[1], "store --file" in body or "store --file" in text),
      ((f"username=admin\npassword=0123456789abcdef0123456789abcdef01234567\n",
        "0123456789abcdef0123456789abcdef01234567"), "0123456789abcdef0123456789abcdef01234567",
       "0123456789abcdef0123456789abcdef01234567", False))
check("the token on no command line (curl's config, git's credential helper)",
      any("0123456789abcdef" in l for l in g + sh) or any("0123456789abcdef" in json.loads(c)["argv"].__str__() for c in cu),
      False)
rc, out, g, sh, cu = run([[f"r{i}" for i in range(50)], ["r50"]])
check("51 repositories over two pages: every one mirrored", (rc, sum(" push " in l for l in g)), (0, 51))
rc, out, g, sh, cu = run([], FAIL_API="1")
check("the organisation's repositories not listed: fails, nothing done, no last-success",
      (rc, len(g), sum("last-success" in l for l in sh)), (1, 0, 0))
rc, out, g, sh, cu = run([])
check("none listed: fails (an empty organisation is no clean run)", (rc, sum("last-success" in l for l in sh)), (1, 0))
rc, out, g, sh, cu = run([["ops", "infra", "site"]], FETCH_FAILS="infra")
check("one repository's fetch failing: the others pushed, it named, the unit failed, no last-success",
      (rc, sum(" push " in l for l in g), "infra(fetch)" in out, sum("last-success" in l for l in sh)), (1, 3, True, 0))
rc, out, g, sh, cu = run([["ops", "infra", "site"]], INIT_FAILS="infra")
check("one repository's repository on the Pi not made: it named, not pushed; the others pushed; the unit failed, no "
      "last-success", (rc, "infra(its repository on the Pi)" in out, re.findall(r" push -q --mirror \S+/([\w.-]+\.git) ",
                                                                             "\n".join(g)),
                       sum("last-success" in l for l in sh)), (1, True, ["ops.git", "site.git"], 0))
rc, out, g, sh, cu = run([["ops", "bad$(name)"]])
check("a name that is no plain name: named, never used; the unit failed",
      (rc, "(its name)" in out, any("bad$(name)" in l for l in g + sh)), (1, True, False))
print("git-mirror: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYGM2
