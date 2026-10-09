#!/bin/bash
# A wait loop in a playbook's script (for _ in $(seq N) ... sleep) ends at its stated time, not after N tries: each
# try can itself take its client's timeout (Keycloak's "240 s" ran up to 24 minutes - 120 tries of curl's 10 s and the
# sleep). Each such loop also reads a deadline from /proc/uptime (a clock nothing sets back) and stops at it; the time
# its message or comment states is that deadline's. A fixture shows the walk finds a loop without one.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY'
import os, re, sys, tempfile
sys.path.insert(0, "tests/ansible/unit")
from plays import actions, files, load, tasks  # noqa: E402
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


LOOP = re.compile(r"for _ in \$\(seq (?:1 )?(\d+)\); do(.*?)\bdone", re.S)
DEADLINE = re.compile(r"(\w+)=\$\(\( \$\(cut -d\. -f1 /proc/uptime\) \+ (\d+) \)\)")


def scripts(doc):
    for t in tasks(doc):
        for m, v in actions(t):
            if str(m).endswith(("shell", "command")):
                yield t.get("name", "?"), v if isinstance(v, str) else str((v or {}).get("cmd") or "")
            elif str(m).endswith(("copy", "template")) and isinstance(v, dict) \
                    and str(v.get("content") or "").startswith("#!"):  # a script written to run later
                yield t.get("name", "?"), v["content"]


def problems(path):
    out = []
    for name, sc in scripts(load(path)):
        deadlines = {k: int(s) for k, s in DEADLINE.findall(sc)}
        for m in LOOP.finditer(sc):
            body = m[2]
            if "sleep" not in body:
                continue
            used = [k for k in deadlines if re.search(r"/proc/uptime\)\"? -lt \"?\$" + k + r"\b", body)]
            if not used:
                out.append(f"{path}: {name}: a {m[1]}-try wait with no deadline")
                continue
            # the time it states: in the two lines after it (its failure's message), else the nearest before it
            after = "\n".join(sc[m.end():].split("\n")[:3])
            stated = re.findall(r"(\d+) s\b", after) or re.findall(r"(\d+) s\b", sc[max(0, m.start() - 300):m.start()])[-1:]
            if stated and int(stated[0]) != deadlines[used[0]]:
                out.append(f"{path}: {name}: states {stated[0]} s, its deadline {deadlines[used[0]]} s")
    return out


fx = tempfile.mkdtemp()
open(os.path.join(fx, "f.yml"), "w").write("""
- hosts: all
  tasks:
    - name: counted only
      ansible.builtin.shell: |
        for _ in $(seq 30); do up && exit 0; sleep 2; done
        echo "not up 60 s after"
    - name: bounded
      ansible.builtin.shell: |
        end=$(( $(cut -d. -f1 /proc/uptime) + 60 ))
        for _ in $(seq 30); do up && exit 0; [ "$(cut -d. -f1 /proc/uptime)" -lt "$end" ] || break; sleep 2; done
        echo "not up 60 s after"
    - name: bounded, said otherwise
      ansible.builtin.shell: |
        end=$(( $(cut -d. -f1 /proc/uptime) + 90 ))
        for _ in $(seq 30); do up && exit 0; [ "$(cut -d. -f1 /proc/uptime)" -lt "$end" ] || break; sleep 2; done
        echo "not up 60 s after"
""")
check("the walk: a counted wait named, a bounded one passes, one stating another time named",
      [p.split(": ", 1)[1] for p in problems(os.path.join(fx, "f.yml"))],
      ["counted only: a 30-try wait with no deadline", "bounded, said otherwise: states 60 s, its deadline 90 s"])
hits = [p for f in files("deploy/ansible") for p in problems(f)]
for h in hits:
    print("  " + h)
check("every wait loop in deploy/ansible ends at its stated time", len(hits), 0)
print("wait-deadlines: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
