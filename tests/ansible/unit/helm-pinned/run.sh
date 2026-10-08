#!/bin/bash
# setup-kubeadm's Helm: a pinned release - ten's own (v3.20.0: its binary's sha256 read on ten 2026-10-08, equal to that
# release's) - downloaded bounded, its sha256 checked before anything is installed, on amd64 alone; never a script from
# a branch piped to bash (get-helm-3 on main: the copy's kubeadm VM, made at each full run, got whatever it installed).
# Its script run with curl, uname and install stubbed: a tarball whose sum differs installs nothing and fails.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYHELM'
import hashlib, io, os, subprocess, sys, tarfile
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render  # noqa: E402
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
t = next(t for p in yaml.safe_load(open("deploy/ansible/playbooks/setup-kubeadm.yml")) for t in p.get("tasks") or []
         if t.get("name") == "Install Helm")
sh = t["ansible.builtin.shell"]
cmd = sh if isinstance(sh, str) else sh["cmd"]
v = t.get("vars") or {}
check("a release pinned (ten's own), its sha256 given; no script piped to bash; installed once",
      (v.get("helm_version"), len(str(v.get("helm_sha256", ""))), "| bash" in cmd or "get-helm" in cmd,
       (t.get("args") or {}).get("creates") or (sh.get("creates") if isinstance(sh, dict) else None)),
      ("v3.20.0", 64, False, "/usr/local/bin/helm"))
# a tarball as the release has it (linux-amd64/helm)
buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode="w:gz") as tf:
    data = b"#!/bin/sh\necho helm\n"
    ti = tarfile.TarInfo("linux-amd64/helm"); ti.size = len(data); ti.mode = 0o755
    tf.addfile(ti, io.BytesIO(data))
open(os.path.join(W, "release.tgz"), "wb").write(buf.getvalue())
good = hashlib.sha256(buf.getvalue()).hexdigest()
os.makedirs(os.path.join(W, "bin"), exist_ok=True)
for name, body in (("curl", '#!/bin/bash\necho "curl $*" >> "$W/calls"\nwhile [ $# -gt 0 ]; do [ "$1" = -o ] && cp "$W/release.tgz" "$2"; shift; done\n'),
                   ("uname", '#!/bin/bash\necho "${ARCH:-x86_64}"\n'),
                   ("install", '#!/bin/bash\necho "install $*" >> "$W/calls"\n')):
    open(os.path.join(W, "bin", name), "w").write(body)
    os.chmod(os.path.join(W, "bin", name), 0o755)
def run(sha, arch="x86_64"):
    open(os.path.join(W, "calls"), "w").close()
    script = render(cmd, **{**v, "helm_sha256": sha})
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W, ARCH=arch))
    calls = open(os.path.join(W, "calls")).read().splitlines()
    return r.returncode, [c.split()[0] for c in calls], next((c for c in calls if c.startswith("curl")), "")
rc, calls, curl = run(good)
check("its sum right: downloaded (bounded, the pinned release), installed 0755 as /usr/local/bin/helm",
      (rc, calls, "--max-time" in curl, "get.helm.sh/helm-v3.20.0-linux-amd64.tar.gz" in curl),
      (0, ["curl", "install"], True, True))
check("its sum wrong: nothing installed, fails", run("0" * 64)[:2], (1, ["curl"]))
check("another architecture: refused before the download", run(good, "aarch64")[:2], (1, []))
print("helm-pinned: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYHELM
