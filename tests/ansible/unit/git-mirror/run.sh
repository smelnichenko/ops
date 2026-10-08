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
# PUSH_FAILS=<repo>: the Pi refuses its push (a full disk, a permission). A push runs its --receive-pack command as
# the Pi would (pibin: mountpoint answering MOUNTED, git-receive-pack recording) - none given, it lands unchecked
case "$*" in *" push "*) [ -n "${PUSH_FAILS:-}" ] && [[ $* == *"/$PUSH_FAILS.git"* ]] && exit 1
  rp=""; for a; do case $a in --receive-pack=*) rp=${a#--receive-pack=} ;; esac; done
  dest=${@: -1}; path=${dest#*:}; path=${path//\/mnt\/backups\/git-mirror/$W/pi}
  if [ -n "$rp" ]; then PATH="$W/pibin:$PATH" bash -c "${rp//\/mnt\/backups\/git-mirror/$W/pi} '$path'" || exit 1
  else echo "received-unchecked $path" >> "$W/pi-calls"; fi
  exit 0 ;; esac
# OLD_CONFIG=<repo>: the old mirror's settings in it - an ssh command (no host-key check) and a remote named pi;
# GLOBAL_SSH: one in the user's or the system's git config (every scope but the repository's own)
old=""; [ -n "${OLD_CONFIG:-}" ] && [[ $* == *"/$OLD_CONFIG.git "* ]] && old=1
case "$*" in
  *" config --local --get core.sshCommand"*) [ -n "$old" ] && { echo "ssh -o StrictHostKeyChecking=no"; exit 0; }; exit 1 ;;
  *" config --get core.sshCommand"*) [ -n "$old" ] || [ -n "${GLOBAL_SSH:-}" ] && { echo "ssh -o x"; exit 0; }; exit 1 ;;
  *" config --local --get-regexp ^remote\.pi\."*) [ -n "$old" ] && { echo "remote.pi.url pi:/x"; exit 0; }; exit 1 ;;
  *" remote") echo origin; [ -z "$old" ] || echo pi; exit 0 ;;
esac
exit 0
STUB
# ssh: its argv recorded; INIT_FAILS=<repo>: the Pi's repository for it not made (a full disk, a permission)
cat > "$W/bin/ssh" <<'STUB'
#!/bin/bash
echo "ssh $*" >> "$W/ssh-calls"
[ -n "${INIT_FAILS:-}" ] && [[ $* == *"/$INIT_FAILS.git/HEAD"* ]] && { echo "fatal: cannot mkdir" >&2; exit 128; }
# LAST_FAILS: the last-success write refused on the Pi
[ -n "${LAST_FAILS:-}" ] && [[ $* == *"last-success"* ]] && { echo "Permission denied" >&2; exit 1; }
# the remote command run as the Pi would: the volume at $W/pi, mounted unless MOUNTED=no
cmd=${@: -1}
PATH="$W/pibin:$PATH" bash -c "${cmd//\/mnt\/backups\/git-mirror/$W/pi}"
STUB
mkdir -p "$W/pibin"
printf '#!/bin/bash\n[ "${MOUNTED:-yes}" = yes ]\n' > "$W/pibin/mountpoint"
printf '#!/bin/bash\necho "pi-git $*" >> "$W/pi-calls"\n' > "$W/pibin/git"
printf '#!/bin/bash\necho "received $*" >> "$W/pi-calls"\n' > "$W/pibin/git-receive-pack"
chmod +x "$W/pibin"/*
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
# read page by page (Forgejo pages its answers: 30 a page by default, 50 at most) - an older mirror token on a later
# page was never deleted
pages = {"results": [{"json": admin_tokens[:3]}, {"json": admin_tokens[3:]}, {"json": []}]}
check("the older tokens: the mirror's own (git-mirror-*) alone, from every page - Argo CD's, Woodpecker's, a name "
      "merely holding it kept", [x["id"] for x in render(dele[0]["loop"], _git_mirror_tokens=pages)] if dele else None,
      [1, 4])
# a token gone already (deleted meanwhile - a run cut short after its delete, by hand) is what the delete wants: 404
# fails no play whose new token is in place by then - the new token's own, on its failure, too
# - Argo CD's token rotation (setup-argocd) as this one
from plays import actions, files, load, tasks as all_tasks  # noqa: E402
deletes = [(f, t.get("name"), v.get("status_code")) for f in files("deploy/ansible") for t in all_tasks(load(f))
           for m, v in actions(t) if str(m).split(".")[-1] == "uri" and isinstance(v, dict)
           and str(v.get("method", "")).upper() == "DELETE" and "/tokens/" in str(v.get("url"))]
check("every Forgejo token delete (the mirror's, Argo CD's) takes 404 (gone already) as done",
      ([x[1] for x in deletes if 404 not in (x[2] if isinstance(x[2], list) else [x[2]])], len(deletes) >= 3), ([], True))
check("the older tokens: none read (the kept token reads) - none deleted",
      list(render(dele[0]["loop"], _git_mirror_tokens={"results": [{"skipped": True}] * 3})) if dele else None, [])
listing = next((t for t in tasks if (t.get("ansible.builtin.uri") or {}).get("method") == "GET"
                and "/tokens" in str(t["ansible.builtin.uri"].get("url"))), None)
check("the admin's tokens read a page at a time (limit and page in the URL, a loop over the pages)",
      listing is not None and "limit=50" in str(listing["ansible.builtin.uri"]["url"])
      and "page={{ item }}" in str(listing["ansible.builtin.uri"]["url"]) and "loop" in listing, True)
full = next((t for t in tasks if "ansible.builtin.assert" in t and "_git_mirror_tokens" in str(t)), None)
check("the last page read not full - more tokens than read refused, never some left unread",
      [condition(full["ansible.builtin.assert"]["that"], _git_mirror_tokens=r) for r in (
          pages, {"results": [{"json": [{"id": i, "name": "x"} for i in range(50)]}] * 10})] if full else None,
      [True, False])
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
# the Pi-side root the sync writes as the mirror's user: the backup-git-mirror volume's root (root:root 0755 on
# production, read 2026-10-08: every repository's init and last-success refused) made the mirror user's, on each Pi
# where it is mounted - a bare mount point refused (the Pi's own disk); before the deploy-time sync
root = next((t for t in tasks if "mountpoint -q" in str(t.get("ansible.builtin.shell", ""))
             and "chown" in str(t.get("ansible.builtin.shell", ""))), None)
check("the Pi-side root made the mirror user's, on each Pi, before the sync runs",
      (root is not None and root.get("delegate_to") == "{{ item }}" and "groups['pis']" in str(root.get("loop")),
       root is not None and names.index(root["name"]) < names.index("The mirror synced now")), (True, True))
if root:
    sh_ = root["ansible.builtin.shell"]
    rscript = R(sh_ if isinstance(sh_, str) else sh_["cmd"])
    def root_run(mounted, stat):
        open(os.path.join(W, "root-calls"), "w").close()
        for b, body in (("mountpoint", f'#!/bin/bash\n[ "{mounted}" = yes ]\n'), ("stat", f'#!/bin/bash\necho "{stat}"\n'),
                        ("chown", '#!/bin/bash\necho "chown $*" >> "$W/root-calls"\n'),
                        ("chmod", '#!/bin/bash\necho "chmod $*" >> "$W/root-calls"\n')):
            open(os.path.join(W, "rbin", b), "w").write(body)
            os.chmod(os.path.join(W, "rbin", b), 0o755)
        r = subprocess.run(["bash", "-c", rscript], capture_output=True, text=True, env=dict(
            os.environ, PATH=os.path.join(W, "rbin") + ":" + os.environ["PATH"], W=W))
        return r.returncode, r.stdout.strip().split("\n")[-1][:40], open(os.path.join(W, "root-calls")).read().split("\n")[:2]
    os.makedirs(os.path.join(W, "rbin"), exist_ok=True)
    got = [root_run("no", "root:root 755"), root_run("yes", "root:root 755"), root_run("yes", "sm:sm 750")]
    check("the root: not mounted - refused, nothing changed; root's - made the mirror user's 0750, said; already - nothing",
          [(g[0], g[0] != 0 or "changed" in g[1], [c.split()[0] for c in g[2] if c]) for g in got],
          [(1, True, []), (0, True, ["chown", "chmod"]), (0, False, [])])
    check("its changed: only where it changed",
          [condition(root.get("changed_when", True), **{root.get("register", "_r"): {"stdout": o}})
           for o in ("changed from root:root 755", "")], [True, False])
# the mirror's volume on the Pis touched by no other playbook's task (setup-gluster mounts it) but where it is checked
# mounted and bounded: setup-vault-pi made its root and monitor.git through the mount, unbounded, with no check - a
# hung client held the play, an unmounted Pi got them on its own disk; the sync makes each repository itself
from plays import files as _files, load as _load, plays as _plays  # noqa: E402
def _walk(ts):
    for t in ts or []:
        if isinstance(t, dict):
            yield t
            for k in ("block", "rescue", "always"):
                yield from _walk(t.get(k))
on_pi = lambda play, t: bool(re.search(r"\bpi", str(t.get("delegate_to", play.get("hosts")))))  # noqa: E731
touch = [(f, t.get("name")) for f in _files("deploy/ansible") if not f.endswith("setup-gluster.yml")
         for play in _plays(_load(f)) for k in ("pre_tasks", "tasks", "post_tasks", "handlers")
         for t in _walk(play.get(k)) if on_pi(play, t) and ("/mnt/backups/git-mirror" in str(t) or "git_mirror_pi_dir" in str(t))
         and not ("mountpoint -q" in str(t) and (t.get("timeout") or "timeout " in str(t)))]
check("the mirror's volume touched by no task but one that checks it mounted, bounded", touch, [])
# the daily sync, as the playbook writes it
sync = next(t for t in tasks if (t.get("ansible.builtin.copy") or {}).get("dest") == "/usr/local/bin/offsite-backup-sync.sh")
body = R(sync["ansible.builtin.copy"]["content"]).replace(R("{{ git_mirror_token_file }}"), creds) \
    .replace(R("{{ git_mirror_dir }}"), os.path.join(W, "mirror"))
open(os.path.join(W, "sync.sh"), "w").write(body)
def run(pages, existing=(), **env):
    for f in ("git-calls", "ssh-calls", "curl-calls"):
        os.path.exists(os.path.join(W, f)) and os.remove(os.path.join(W, f))
    shutil.rmtree(os.path.join(W, "mirror")); os.makedirs(os.path.join(W, "mirror"))
    shutil.rmtree(os.path.join(W, "pi"), ignore_errors=True); os.makedirs(os.path.join(W, "pi"))
    os.path.exists(os.path.join(W, "pi-calls")) and os.remove(os.path.join(W, "pi-calls"))
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
# its own helper for Forgejo's URL alone (git's credential.<url>.helper) and no redirect followed: a redirect off the
# host (a misconfigured proxy) asked the helper for the new host, and it answered any with the token
check("its git: no prompt (none to answer), the Pi's host keys checked, the credential helper reset before its own - "
      "Forgejo's URL's alone; no redirect followed",
      (all("PROMPT=0" in l for l in g), all("StrictHostKeyChecking=yes" in l and "UserKnownHostsFile=" in l for l in push),
       all(" -c credential.helper= -c credential.https://git.pmon.dev.helper=!" in l for l in g
           if " fetch " in l or " clone " in l),
       all(" -c http.followRedirects=false " in l for l in g if " fetch " in l or " clone " in l)),
      (True, True, True, True))
# the old mirror's own settings (monitor.git on ten: core.sshCommand with no host-key check, a remote holding the Pi)
# gone from the repository that holds them, the others left as they are
rc, out, g, sh, cu = run([["ops", "infra"]], existing=["ops", "infra"], OLD_CONFIG="ops")
check("the old mirror's ssh setting and its pi remote removed where they are, nowhere else; the run 0",
      (rc, [l.split(" PROMPT=")[0].split("/mirror/")[1] for l in g if "--unset-all core.sshCommand" in l or "remote remove pi" in l]),
      (0, ["ops.git config --unset-all core.sshCommand", "ops.git remote remove pi"]))
# the helper as git runs it (its action an argument): "get" answers the token; "erase" and "store" (git's after a 401,
# a success) leave the file as it is - no store helper anywhere
fetch_line = next((l for l in g if " fetch " in l), "")
# as git is given it: its key (credential.helper, or a URL's credential.<url>.helper) and the helper
helper = re.search(r"(credential\.\S*?helper)=(!f\(\) \{.*?\}; f)(?= )", fetch_line)
def helper_run(action):
    r = subprocess.run(["sh", "-c", helper.group(2)[1:] + " " + action], input="protocol=https\nhost=git.pmon.dev\n\n",
                       capture_output=True, text=True)
    return r.stdout, open(creds).read()
check("its credential helper: get answers the token; erase and store leave it be; git's store helper used nowhere",
      (helper is not None and helper_run("get"), helper is not None and helper_run("erase")[1],
       helper is not None and helper_run("store")[1], "store --file" in body or "store --file" in text),
      ((f"username=admin\npassword=0123456789abcdef0123456789abcdef01234567\n",
        "0123456789abcdef0123456789abcdef01234567"), "0123456789abcdef0123456789abcdef01234567",
       "0123456789abcdef0123456789abcdef01234567", False))
# git itself asked as a fetch asks - for Forgejo's host, and for another (where a redirect went): only Forgejo's answered
def fill(host):
    r = subprocess.run(["git", "-c", "credential.helper=", "-c",
                        f"{helper.group(1)}={helper.group(2)}" if helper else "x.y=", "credential", "fill"],
                       input=f"protocol=https\nhost={host}\n\n", capture_output=True, text=True,
                       env=dict(os.environ, GIT_TERMINAL_PROMPT="0"))
    return "password=0123456789abcdef0123456789abcdef01234567" in r.stdout
check("git asks its helper: Forgejo's host given the token, another host (a redirect's) nothing",
      (fill("git.pmon.dev"), fill("other.example.org")), (True, False))
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
      "last-success", (rc, "infra(its repository on the Pi)" in out, re.findall(r" push .*/([\w.-]+\.git) PROMPT=",
                                                                             "\n".join(g)),
                       sum("last-success" in l for l in sh)), (1, True, ["ops.git", "site.git"], 0))
rc, out, g, sh, cu = run([["ops", "infra", "site"]], PUSH_FAILS="infra")
check("one repository's push refused by the Pi: named, the others pushed, the unit failed, no last-success",
      (rc, "infra(push)" in out, sum("last-success" in l for l in sh)), (1, True, 0))
rc, out, g, sh, cu = run([["ops", "infra"]], LAST_FAILS="1")
check("its last-success not written on the Pi: the unit failed, said", (rc, "last-success not written" in out), (1, True))
# what it writes on the Pi only where the volume is mounted: an unmounted mount point is the Pi's own disk (pushes there
# lost with the next mount)
remote = [l for l in sh if "git init" in l or "last-success" in l]
check("every write on the Pi (a repository made, last-success) under the mount's check",
      (bool(remote), all("mountpoint -q " in l for l in remote)), (True, True))
# run as the Pi runs them: mounted - each repository made and received, last-success written; not mounted (a bare
# mount point, the Pi's own disk) - nothing made, nothing received, no last-success, the unit failed, each named
pi_calls = lambda: open(os.path.join(W, "pi-calls")).read().splitlines() if os.path.exists(os.path.join(W, "pi-calls")) else []  # noqa: E731
rc, out, g, sh, cu = run([["ops", "infra"]])
got_m = (rc, sorted(l.split()[0] for l in pi_calls()), os.path.exists(os.path.join(W, "pi", "last-success")))
rc, out, g, sh, cu = run([["ops", "infra"]], MOUNTED="no")
got_u = (rc, pi_calls(), os.path.exists(os.path.join(W, "pi", "last-success")))
check("on the Pi, mounted: each repository made and received, last-success written; not mounted: nothing made or "
      "received, no last-success, the unit failed", (got_m, got_u),
      ((0, ["pi-git", "pi-git", "received", "received"], True), (1, [], False)))
# bounded: its ssh (a dead connection ends), each remote command's mount check, its fetch's speed; the listing's pages
check("its ssh and remote commands bounded, its fetch's low speed bounded",
      ("ConnectTimeout=" in body and "ServerAliveInterval=" in body, all("timeout " in l for l in sh if "mountpoint" in l),
       "http.lowSpeedLimit" in body), (True, True, True))
rc, out, g, sh, cu = run([[f"r{i}"] for i in range(25)])
check("more pages than it reads: fails, said - never a mirror of part of the organisation",
      (rc, "not all listed" in out), (1, True))
# the old mirror's settings read in the repository's own config alone: one in the user's or the system's left (its
# unset of the repository's failed every run, every repository named)
rc, out, g, sh, cu = run([["ops", "infra"]], existing=["ops", "infra"], GLOBAL_SSH="1")
check("an ssh setting in git's user or system config: left, the run 0", (rc, any("--unset-all" in l for l in g)), (0, False))
rc, out, g, sh, cu = run([["ops", "bad$(name)"]])
check("a name that is no plain name: named, never used; the unit failed",
      (rc, "(its name)" in out, any("bad$(name)" in l for l in g + sh)), (1, True, False))
print("git-mirror: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYGM2
