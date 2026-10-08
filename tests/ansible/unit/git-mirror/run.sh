#!/bin/bash
# setup-velero.yml's offsite git mirror on ten (the monitor repo from Forgejo, pushed to the Pis daily), its tasks as
# the playbook holds them: Forgejo read by a token of read:repository alone - never the admin's password, which sat
# in the mirror's origin URL (any local user read it on git-remote-https's argv at each fetch) - kept in a 0600 file
# git's credential helper reads, the origin's URL without credentials (an older mirror's rewritten); the token kept
# while it still reads the repository (a read with no prompt, as the mirror's user), else a new one made, proven, and
# only then the older ones deleted; git's settings written only when they differ. The daily sync, run here with sudo,
# git and logger stubs: a failed fetch or push fails the unit (each was a warning in the journal, the unit green) -
# the push tried even after a failed fetch (the copy it has is still a copy).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/mirror"
cat > "$W/bin/sudo" <<'STUB'
#!/bin/bash
[ "$1" = -u ] && shift 2
exec "$@"
STUB
cat > "$W/bin/git" <<'STUB'
#!/bin/bash
echo "git $*" >> "$W/calls"
case "$*" in
  *" fetch "*) [ -z "${FETCH_FAILS:-}" ] || { echo "fatal: unable to access 'https://git.pmon.dev/x.git/': 502"; exit 128; } ;;
  *" push "*) [ -z "${PUSH_FAILS:-}" ] || { echo "Host key verification failed."; exit 128; } ;;
esac
STUB
printf '#!/bin/bash\necho "logger $*" >> "$W/calls"\ncat >> "$W/calls"\n' > "$W/bin/logger"
chmod +x "$W/bin"/*
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYGM'
import json, os, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render, trust_as_template  # noqa: E402
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
play = next(p for p in yaml.safe_load(open("deploy/ansible/playbooks/setup-velero.yml"))
            if p.get("name") == "Offsite git mirror to the Pis")
tasks = play["tasks"]
pv = {k: trust_as_template(x) if isinstance(x, str) else x for k, x in play["vars"].items()}
v = dict(pv, forgejo_admin_user="admin", forgejo_admin_password="THE-ADMIN-PW", offsite_backup_user="sm",
         keepalived_vip="10.0.0.5")
def text(t):
    for m in ("ansible.builtin.shell", "ansible.builtin.command"):
        a = t.get(m)
        if a is not None:
            return a if isinstance(a, str) else (a.get("cmd") or " ".join(map(str, a.get("argv", []))))
    return ""
check("the admin's password in no command, script or environment",
      [t.get("name") for t in tasks if "password" in text(t) + str(t.get("environment", ""))
       or "THE-ADMIN-PW" in str(render(text(t), **v))], [])
url = str(render("{{ git_mirror_url }}", **v))
# git's settings: each git_config task's name and value, its loop's items expanded
gc = {}
for t in tasks:
    g = t.get("community.general.git_config")
    if g is None:
        continue
    for item in t.get("loop") or [None]:
        name = str(render(str(g["name"]), item=item, **v)) if item else g["name"]
        gc[name] = {"community.general.git_config": dict(g, value=item["value"] if item else g["value"])}
check("the origin's URL set (an older mirror's rewritten), without credentials",
      (str(render(str((gc.get("remote.origin.url") or {}).get("community.general.git_config", {}).get("value")), **v)),
       "@" in url), (url, False))
helper = str(render("{{ _git_mirror_helper }}", **v))
check("git's credential helper: the store, a file of its own",
      (str(render(str((gc.get("credential.helper") or {}).get("community.general.git_config", {}).get("value")), **v)),
       helper.startswith("store --file=/")), (helper, True))
check("the push's ssh set only when it differs (git_config), not changed on every run",
      "core.sshCommand" in gc and not any("core.sshCommand" in text(t) for t in tasks), True)
reads = [t for t in tasks if "ls-remote" in text(t)]
check("the token judged by a read of the repository, with no prompt, as the mirror's user - twice: kept, made",
      [(t.get("become_user") is not None, str((t.get("environment") or {}).get("GIT_TERMINAL_PROMPT")),
        t.get("check_mode")) for t in reads], [(True, "0", False), (True, "0", False)])
post = [t for t in tasks if (t.get("ansible.builtin.uri") or {}).get("method") == "POST"]
check("a new token: read:repository alone, no_log, only when the kept one does not read",
      [(t["ansible.builtin.uri"]["body"]["scopes"], t.get("no_log"),
        condition(t.get("when"), _git_mirror_token_works=True, ansible_check_mode=False),
        condition(t.get("when"), _git_mirror_token_works=False, ansible_check_mode=False)) for t in post],
      [(["read:repository"], True, False, True)])
cred = [t for t in tasks if (t.get("ansible.builtin.copy") or {}).get("dest") == "{{ git_mirror_credentials_file }}"]
check("the token in a file of the mirror's user's alone (0600), no_log",
      [(t["ansible.builtin.copy"].get("mode"), str(render(str(t["ansible.builtin.copy"].get("owner")), **v)),
        t.get("no_log")) for t in cred], [("0600", "sm", True)])
dele = [t for t in tasks if (t.get("ansible.builtin.uri") or {}).get("method") == "DELETE"]
names = [t.get("name") for t in tasks]
check("the older tokens deleted after the new one is proven to read",
      bool(dele) and len(reads) == 2 and names.index(reads[1]["name"]) < names.index(dele[0]["name"]), True)
# the daily sync, as the playbook writes it
sync = next(t for t in tasks if (t.get("ansible.builtin.copy") or {}).get("dest") == "/usr/local/bin/offsite-backup-sync.sh")
script = str(render(sync["ansible.builtin.copy"]["content"], **v)).replace(str(render("{{ git_mirror_local_path }}", **v)),
                                                                            os.path.join(W, "mirror"))
open(os.path.join(W, "sync.sh"), "w").write(script)
def run(**env):
    open(os.path.join(W, "calls"), "w").close()
    r = subprocess.run(["bash", os.path.join(W, "sync.sh")], capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], **env))
    calls = open(os.path.join(W, "calls")).read()
    return r.returncode, " fetch " in calls, " push " in calls, "FAILED" in calls
check("the sync: fetched, pushed, ends 0", run(), (0, True, True, False))
check("a failed fetch: the push still tried, the unit fails, said", run(FETCH_FAILS="1")[0:1] + run(FETCH_FAILS="1")[2:],
      (1, True, True))
check("a failed push: the unit fails, said", run(PUSH_FAILS="1"), (1, True, True, True))
os.rmdir(os.path.join(W, "mirror"))
check("no mirror there: the unit fails", run()[0], 1)
print("git-mirror: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYGM
