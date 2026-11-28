#!/bin/bash
# deploy/ansible/playbooks/restore-check-age-now.yml (task check:production:restore-check-age): a Job from the
# restore-check-age CronJob, waited for - against a stub kubectl playing the Job. Succeeded: its verdict said, the Job
# removed; failed (backoffLimit 0): failed at once, its logs said, the Job kept for them - never waited out to the bound;
# neither within the bound: not done, said; a status read failing once: read again. Each kubectl in kube-system.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/bash
echo "kubectl $*" >> "$W/calls"
case " $* " in
  *" create job --from=cronjob/restore-check-age "*) ;;
  *" get job/"*) n=$(cat "$W/reads" 2>/dev/null || echo 0); echo $((n + 1)) > "$W/reads"
    [ "$n" != 0 ] || [ -z "${READ_FAILS_ONCE:-}" ] || { echo "connection refused" >&2; exit 1; }
    cat "$W/state" ;;
  *" logs "*) printf 'pi1: restored 3 h ago\npi2: restored 26 h ago\nRESTORE CHECK AGE OK\n' ;;
  *" delete job "*) [ -z "${DELETE_FAILS:-}" ] || exit 1; touch "$W/deleted" ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
STUB
chmod +x "$W/bin/kubectl"
W=$W exec "$PY" - <<'PY_AGE'
import os, subprocess, sys, time
import yaml
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f"\n    got:  {got!r}\n    want: {want!r}"))
play = yaml.safe_load(open("deploy/ansible/playbooks/restore-check-age-now.yml"))[0]
task = play["tasks"][0]
cmd = task["ansible.builtin.shell"]["cmd"]
def run(state, wait="30", **env):
    for f in ("calls", "reads", "deleted"):
        if os.path.exists(os.path.join(W, f)):
            os.remove(os.path.join(W, f))
    open(os.path.join(W, "state"), "w").write(state)
    c = cmd.replace("{{ kubectl }}", play["vars"]["kubectl"].replace("kubectl --kubeconfig {{ kubeconfig }}", W + "/bin/kubectl")) \
           .replace("{{ age_wait_s }}", wait)
    t0 = time.monotonic()
    r = subprocess.run(["bash", "-c", c], capture_output=True, text=True, env={**os.environ, "W": W, **env}, timeout=120)
    calls = open(os.path.join(W, "calls")).read().splitlines() if os.path.exists(os.path.join(W, "calls")) else []
    return r.returncode, r.stdout, calls, os.path.exists(os.path.join(W, "deleted")), time.monotonic() - t0
rc, out, calls, deleted, _ = run("1/")
check("succeeded: its verdict said (its log's last lines), the Job removed, every call in kube-system",
      (rc, out.strip().splitlines()[-1], deleted, all(" -n kube-system " in c for c in calls)), (0, "RESTORE CHECK AGE OK", True, True))
rc, out, calls, deleted, took = run("/1")
check("failed: failed at once (not waited out to the bound), its logs and the failure said, the Job kept",
      (rc, took < 5, "age check restore-check-age-now-" in out and out.strip().endswith("failed"), deleted), (1, True, True, False))
rc, out, calls, deleted, took = run("/", wait="1")
check("neither within the bound: not done, said, the Job kept", (rc, out.strip().endswith("not done in 1 s"), deleted), (1, True, False))
rc, out, calls, deleted, _ = run("1/", READ_FAILS_ONCE="1")
check("a status read failing once: read again - succeeded", (rc, deleted), (0, True))
rc, out, calls, deleted, _ = run("1/", DELETE_FAILS="1")
check("succeeded but its delete failing: still a pass (the check passed), the Job said left", (rc, "its delete failed" in out), (0, True))
check("the Job made from the CronJob restore-check-age", any(" create job --from=cronjob/restore-check-age restore-check-age-now-" in c for c in calls), True)
check("the bound past the Job's own deadline (activeDeadlineSeconds 300); a preview runs nothing",
      (int(play["vars"]["age_wait_s"]) > 300, task.get("when")), (True, "not ansible_check_mode"))
print("restore-check-age-now: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_AGE
