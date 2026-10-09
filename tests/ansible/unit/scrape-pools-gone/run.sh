#!/bin/bash
# A scrape pool a step removes on purpose (its scrape-pool-gone line - step 27 stops scraping the API server, whose
# ServiceMonitor kube-prometheus-stack 91.x authenticates with a token Secret that never expires): the metrics check
# excuses exactly the pools the steps up to the one checked removed; any other pool gone or smaller still fails it.
# The comparison as metrics-check.yml holds it, run on a fixture of Prometheus' targets.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY'
import json, os, re, subprocess, sys
import yaml
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


API = "serviceMonitor/schnappy-infra/schnappy-apiserver/0"
inv = lambda *a: subprocess.run(["scripts/upgrade-expected-inventory.py", *a], capture_output=True, text=True)
steps = sorted(f[:-4] for f in os.listdir("tests/ansible/upgrade/steps") if f.endswith(".txt"))
kps = next(s for s in steps if "kube-prometheus-stack" in s)
check(f"{kps} removes the API server's pool (its line)",
      f"scrape-pool-gone {API}" in open(f"tests/ansible/upgrade/steps/{kps}.txt").read(), True)
before_kps = steps[steps.index(kps) - 1]
check("--scrape-pools-gone: none before it, the pool from it on",
      (inv("--scrape-pools-gone", before_kps).stdout.strip(), inv("--scrape-pools-gone", kps).stdout.strip(),
       inv("--scrape-pools-gone", steps[-1]).stdout.strip()), ("", API, API))
# the comparison metrics-check.yml runs, its python taken from the task
play = yaml.safe_load(open("tests/ansible/upgrade/metrics-check.yml"))
task = next(t for p in play for t in p.get("tasks") or [] if "No scrape pool gone" in str(t.get("name")))
cmd = task["ansible.builtin.shell"]["cmd"]
code = re.search(r"python3 -c '\n(.*?)'\s*$", cmd, re.S)
check("the comparison found in metrics-check.yml", code is not None, True)
check("  given the pools gone by the steps up to the one checked", "scrape_pools_gone" in str(task.get("environment")),
      True)
targets = lambda pools: json.dumps({"data": {"activeTargets": [{"scrapePool": p} for p in pools]}})


def compare(before, now, gone=""):
    r = subprocess.run([sys.executable, "-c", code[1] if code else "import sys; sys.exit(9)"], input=targets(now),
                       capture_output=True, text=True, env=dict(os.environ, BEFORE=json.dumps(before), GONE=gone))
    return r.returncode


check("nothing gone: passes", compare({API: 1, "x": 2}, [API, "x", "x"]), 0)
check("the API server's pool gone, the step's line says so: passes", compare({API: 1, "x": 2}, ["x", "x"], API), 0)
check("the same pool gone with no line: fails", compare({API: 1, "x": 2}, ["x", "x"]), 1)
check("another pool gone beside it: fails", compare({API: 1, "x": 2}, ["y"], API), 1)
check("another pool smaller: fails", compare({API: 1, "x": 2}, ["x"], API), 1)
# the step checks hand the metrics check the list; the step task computes it for its step
sc = open("scripts/upgrade-step-checks.sh").read()
check("upgrade-step-checks.sh gives the metrics check the pools gone",
      bool(re.search(r"start metrics play \.\./\.\./tests/ansible/upgrade/metrics-check\.yml .*scrape_pools_gone", sc)),
      True)
step = yaml.safe_load(open("Taskfile.yml"))["tasks"]["test:upgrade:step"]
check("test:upgrade:step computes them for its step",
      "--scrape-pools-gone {{.STEP}}" in str((step.get("vars") or {}).get("SCRAPE_POOLS_GONE")), True)
print("scrape-pools-gone: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
