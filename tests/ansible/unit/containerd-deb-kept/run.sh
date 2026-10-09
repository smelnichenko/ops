#!/bin/bash
# upgrade-containerd.yml keeps the running containerd's package before it replaces it: the abort reinstalls it (apt's
# cache may be cleaned by then, the mirror moved on) - the version dpkg says is installed, downloaded into the backup
# directory once (a re-run keeps it), before the download and install of the new runtime, not in a preview.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml, jinja2' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/keep"
cat > "$W/bin/dpkg-query" <<'STUB'
#!/bin/bash
printf 'containerd 1.7.24~ds1-6+deb13u1 installed\ncontainerd.io  not-installed\n'
STUB
cat > "$W/bin/apt-get" <<'STUB'
#!/bin/bash
echo "apt-get $*" >> "$W/calls"
[ "$1" = download ] && touch "containerd_1.7.24~ds1-6+deb13u1_amd64.deb"
STUB
chmod +x "$W/bin/dpkg-query" "$W/bin/apt-get"
W=$W "$PY" - <<'PY_DEBKEPT'
import os, subprocess, sys, yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
play = yaml.safe_load(open("deploy/ansible/playbooks/upgrade-containerd.yml"))[0]
def walk(ts):
    for t in ts or []:
        yield t
        for k in ("block", "rescue", "always"):
            yield from walk(t.get(k))
tasks = list(walk(play["tasks"]))
names = [str(t.get("name", "")) for t in tasks]
keep = next((i for i, n in enumerate(names) if n.startswith("The running containerd's package kept")), None)
check("the task exists", keep is not None, True)
if keep is not None:
    at = lambda prefix: next(i for i, n in enumerate(names) if n.startswith(prefix))
    check("after the preview ends, before the download and the install",
          (at("End the preview here") < keep < at("Download containerd.io") < at("Install containerd.io")), True)
    cmd = render(tasks[keep]["ansible.builtin.shell"]["cmd"], upgrade_backup_dir=os.path.join(W, "keep"))
    env = dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"])
    r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, env=env)
    calls = open(os.path.join(W, "calls")).read().splitlines() if os.path.exists(os.path.join(W, "calls")) else []
    check("the installed version downloaded into the backup directory",
          (r.returncode, calls, os.listdir(os.path.join(W, "keep"))),
          (0, ["apt-get download containerd=1.7.24~ds1-6+deb13u1"], ["containerd_1.7.24~ds1-6+deb13u1_amd64.deb"]))
    r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, env=env)
    calls = open(os.path.join(W, "calls")).read().splitlines()
    check("a re-run keeps it, downloads nothing", (r.returncode, len(calls), "kept already" in r.stdout), (0, 1, True))
print("containerd-deb-kept: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_DEBKEPT
