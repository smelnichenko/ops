#!/bin/bash
# tests/ansible/upgrade/metrics-check.yml's every-target-up check as the playbook holds it (rendered by Ansible's
# templar), kubectl a stub recording Prometheus' query: the window it reads `up` over starts where the check's first
# look less 2 minutes was, fixed before the retries - each retry reads from that start, so a target that flapped is
# not waited out (each retry read the 2 minutes before its own time: a flap aged out after 2 minutes of retries).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/bash
case "$*" in
  *targets*) echo '{"data": {"activeTargets": [{"scrapePool": "p", "scrapeUrl": "u", "health": "up", "lastError": "",
                "labels": {"job": "j"}}]}}' ;;
  *query*) echo "${@: -1}" >> "$W/queries"; echo '{"data": {"result": []}}' ;;
esac
STUB
chmod +x "$W/bin/kubectl"
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY'
import os, re, subprocess, sys, time, urllib.parse
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render  # noqa: E402
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
tasks = yaml.safe_load(open("tests/ansible/upgrade/metrics-check.yml"))[0]["tasks"]
names = [t.get("name", "") for t in tasks]
up = next(i for i, n in enumerate(names) if n.startswith("Every scrape target is up"))
start = next((i for i, t in enumerate(tasks) if "_metrics_from" in str(t.get("ansible.builtin.set_fact", ""))
              or t.get("register") == "_metrics_from"), None)
check("the window's start fixed once, before the retried check", start is not None and start < up
      and not tasks[start].get("retries"), True)
t = tasks[up]
cmd = t["ansible.builtin.shell"] if isinstance(t["ansible.builtin.shell"], str) else t["ansible.builtin.shell"]["cmd"]
for late in (0, 300):  # the first look, and a retry 5 minutes later
    first = int(time.time()) - late
    script = render(cmd, kubeconfig="k", proxy="/p", allowed_down=[], _metrics_from={"stdout": str(first - 120)})
    open(os.path.join(W, "queries"), "w").close()
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W))
    q = urllib.parse.unquote(open(os.path.join(W, "queries")).read())
    m = re.search(r"up\[(\d+)s\]", q)
    got = int(m[1]) if m else q.strip()
    check(f"{'a retry 5 minutes after the first look' if late else 'the first look'}: `up` read from 2 minutes before "
          f"the first look ({120 + late} s)", (r.returncode, isinstance(got, int) and abs(got - 120 - late) <= 2),
          (0, True))
print("metrics-window: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
