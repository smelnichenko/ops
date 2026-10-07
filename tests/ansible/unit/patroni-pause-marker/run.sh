#!/bin/bash
# The three playbooks that pause Patroni around their work (setup-consul, setup-patroni, upgrade-patroni) - their
# pause, resume and not-paused-already tasks as the files hold them, consul (its KV with ModifyIndex and check-and-set)
# and patronictl stubs: each pause puts a marker naming the playbook and the time, check-and-set - one only: a marker
# there already (another run holding the cluster paused, or one cut short) refuses the run before any pause, and
# is left as it is; a pause that fails deletes its own marker; the resume deletes the marker only if it is still its
# own (one put since is left). A pause the next run finds names the run that left it - a Ctrl-C skips Ansible's
# always: - asking whether it still runs; a marker of another shape is not echoed.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/kv"
# consul kv: a key's value in kv/<key>, its ModifyIndex in kv/<key>.idx (a counter in kv/.n)
cat > "$W/bin/consul" <<'STUB'
#!/bin/bash
echo "consul $*" >> "$W/calls"
[ "$1" = kv ] || exit 2
op=$2; shift 2
cas= idx=
while [[ ${1:-} == -* ]]; do
  case "$1" in -cas) cas=1 ;; -modify-index=*) idx=${1#*=} ;; -detailed) det=1 ;; esac; shift
done
k=$W/kv/${1//\//_}
case "$op" in
  put)
    if [ -n "$cas" ] && [ "$idx" = 0 ] && [ -e "$k" ]; then echo "Error! Did not write to $1: CAS failed" >&2; exit 1; fi
    n=$(( $(cat "$W/kv/.n" 2> /dev/null || echo 10) + 1 )); echo $n > "$W/kv/.n"
    printf '%s' "$2" > "$k"; echo $n > "$k.idx" ;;
  get)
    [ -e "$k" ] || { echo "Error! No key exists at: $1" >&2; exit 1; }
    if [ -n "${det:-}" ]; then echo "Key                 $1"; echo "ModifyIndex         $(cat "$k.idx")"
      echo "Value               $(cat "$k")"; else cat "$k"; echo; fi ;;
  delete)
    if [ -n "$cas" ] && { [ ! -e "$k" ] || [ "$(cat "$k.idx")" != "$idx" ]; }; then
      echo "Error! Did not delete key $1: CAS failed" >&2; exit 1
    fi
    rm -f "$k" "$k.idx" ;;
esac
STUB
cat > "$W/bin/patronictl" <<'STUB'
#!/bin/bash
echo "patronictl $*" >> "$W/calls"
case "$*" in
  *"pause --wait"*) [ -z "${PAUSE_FAILS:-}" ] || { echo "Cluster is already paused" >&2; exit 1; }; touch "$W/paused" ;;
  *"resume --wait"*) rm -f "$W/paused" ;;
  *list*) echo "+ Cluster: pg"; [ -e "$W/paused" ] && echo " Maintenance mode: on" ;;
esac
exit 0
STUB
chmod +x "$W/bin"/*
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import os, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render  # noqa: E402
W = os.environ["W"]
KEY = os.path.join(W, "kv", "ansible_patroni-paused-by")
fails = 0
def check(name, ok, detail=""):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f"\n  {detail}"))
def tasks(items):
    for t in items or []:
        yield t
        for k in ("block", "rescue", "always"):
            yield from tasks(t.get(k))
def text(t):
    for m in ("ansible.builtin.command", "ansible.builtin.shell"):
        a = t.get(m)
        if a is not None:
            return a if isinstance(a, str) else a.get("cmd", "")
    return ""
def state(paused=False, marker=None, idx=None):
    for f in os.listdir(os.path.join(W, "kv")):
        os.remove(os.path.join(W, "kv", f))
    open(os.path.join(W, "calls"), "w").close()
    if paused:
        open(os.path.join(W, "paused"), "w").close()
    elif os.path.exists(os.path.join(W, "paused")):
        os.remove(os.path.join(W, "paused"))
    if marker is not None:
        open(KEY, "w").write(marker)
        open(KEY + ".idx", "w").write(f"{idx or 7}\n")
def sh(cmd, env=None, **st):
    state(**st)
    r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], **(env or {})))
    calls = open(os.path.join(W, "calls")).read().splitlines()
    return r, calls, open(KEY).read() if os.path.exists(KEY) else None
v = dict(patronictl="patronictl")
for book in ("setup-consul", "setup-patroni", "upgrade-patroni"):
    every = [t for play in yaml.safe_load(open(f"deploy/ansible/playbooks/{book}.yml")) for t in tasks(play.get("tasks"))]
    pause = [t for t in every if "pause --wait" in text(t) and "resume --wait" not in text(t)]
    resume = [t for t in every if "resume --wait" in text(t)]
    checks = [t for t in every if "Maintenance mode" in text(t) and "REFUSED" in text(t)]
    check(f"{book}: one pause, one resume, one not-paused check", (len(pause), len(resume), len(checks)) == (1, 1, 1),
          (len(pause), len(resume), len(checks)))
    if not (pause and resume and checks):
        continue
    p, rs, ck = (render(text(x[0]), **v) for x in (pause, resume, checks))
    reg = pause[0].get("register")
    r, calls, kv = sh(p)
    first = [c.split()[0] + " " + c.split()[1] for c in calls]
    check(f"{book}: the pause puts its marker (check-and-set), then pauses; its index kept",
          r.returncode == 0 and kv is not None and kv.startswith(book + " ") and "MARKER 11" in r.stdout
          and any("put -cas -modify-index=0" in c for c in calls) and first.index("patronictl pause") > 0,
          (r.returncode, r.stdout, r.stderr, calls, kv))
    r, calls, kv = sh(p, marker="setup-consul 2026-10-08T01:00:00Z")
    check(f"{book}: a marker there already: refused before any pause, the marker left as it was",
          r.returncode != 0 and "REFUSED" in r.stdout + r.stderr and not any("pause" in c for c in calls if c.startswith("patronictl"))
          and kv == "setup-consul 2026-10-08T01:00:00Z", (r.returncode, r.stdout, r.stderr, calls, kv))
    r, calls, kv = sh(p, env={"PAUSE_FAILS": "1"})
    check(f"{book}: its pause failing: its own marker deleted again", r.returncode != 0 and kv is None,
          (r.returncode, r.stdout, r.stderr, kv))
    pout = "MARKER 7"
    renv = {n: str(render(str(x), **{reg: {"stdout": pout}})) for n, x in (resume[0].get("environment") or {}).items()}
    r, calls, kv = sh(rs, env=renv, paused=True, marker=f"{book} 2026-10-08T01:00:00Z", idx=7)
    check(f"{book}: the resume resumes, then deletes its own marker",
          r.returncode == 0 and kv is None and not os.path.exists(os.path.join(W, "paused"))
          and [c.split()[1] for c in calls][:2] == ["resume", "kv"], (r.returncode, r.stdout, r.stderr, calls, kv))
    r, calls, kv = sh(rs, env=renv, paused=True, marker="setup-patroni 2026-10-08T02:00:00Z", idx=9)
    check(f"{book}: a marker put since (not its own): left as it is, said so", r.returncode == 0
          and kv == "setup-patroni 2026-10-08T02:00:00Z" and "left" in r.stdout, (r.returncode, r.stdout, r.stderr, kv))
    r, calls, kv = sh(ck, paused=True, marker="upgrade-patroni 2026-10-07T23:00:00Z")
    check(f"{book}: paused, a marker: refused, naming the run, asking whether it still runs", r.returncode == 1
          and "upgrade-patroni 2026-10-07T23:00:00Z" in r.stdout and "no longer running" in r.stdout, (r.returncode, r.stdout))
    r, calls, kv = sh(ck, paused=True, marker="$(reboot) run patronictl remove")
    check(f"{book}: paused, a marker of another shape: refused, not echoed", r.returncode == 1
          and "reboot" not in r.stdout and "another shape" in r.stdout, (r.returncode, r.stdout))
    r, calls, kv = sh(ck, paused=True)
    check(f"{book}: paused, no marker (someone's maintenance): refused, no run named", r.returncode == 1
          and "REFUSED" in r.stdout and "no longer running" not in r.stdout, (r.returncode, r.stdout))
    r, calls, kv = sh(ck)
    check(f"{book}: not paused: passes", r.returncode == 0, (r.returncode, r.stdout))
print("patroni-pause-marker: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
