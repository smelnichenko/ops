#!/bin/bash
# The Vagrant copy's tasks (Taskfile.yml test:copy:*) as go-task holds them: each one's commands in order, with the
# flags that make it mean something - a change's settle on the pushed commits (expect_mirror) with the apps the build
# recorded or recorded anew (APPS_CHANGED), the copy's deciding settle values (COPY_SETTLE); an ops playbook behind the
# Vagrant guard in the same run, both isolations put back after it; the copy's refs recorded where it changes; the
# inventory after a change judged as a change's. And scripts/copy-refs.sh, what test:copy:check run on its own reads:
# the refs, and whether the copy carries a change.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY_COPY_TASKS'
import atexit, os, re, shutil, subprocess, sys, tempfile
import yaml
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


T = yaml.safe_load(open("Taskfile.yml"))["tasks"]


def cmds(name):
    out = []
    for c in T[name].get("cmds") or []:
        if isinstance(c, dict) and "task" in c:
            out.append(("task", c["task"], c.get("vars") or {}))
        else:
            out.append(("cmd", " ".join(str(c.get("cmd", c) if isinstance(c, dict) else c).split()), {}))
    return out


def index(seq, pattern):
    """The first command matching the regex, by position (-1: none)."""
    return next((i for i, (_, c, _) in enumerate(seq) if re.search(pattern, c)), -1)


def ordered(seq, *patterns):
    at = [index(seq, p) for p in patterns]
    return all(i >= 0 for i in at) and at == sorted(at) and len(set(at)) == len(at)


SETTLE = r"copy/argo-settled\.yml"
argo, change, check_, playbook = cmds("test:copy:argo"), cmds("test:copy:change"), cmds("test:copy:check"), \
    cmds("test:copy:playbook")
# test:copy:argo: main checked first, mirrored as main, the refs recorded, the build's settle
check("test:copy:argo: main checked, mirrored, recorded as main main, then the build's settle (apps recorded)",
      (ordered(argo, r"copy-main-current\.sh \.\./infra \.\./platform$", r"--infra-ref main --platform-ref main",
               r"copy-refs\.sh set main main$", SETTLE),
       argo[index(argo, SETTLE)][1].endswith(
           "-e expect_mirror=true -e record_apps=true -e restart_stage=build-$(date +%Y%m%d%H%M%S) {{.COPY_SETTLE}}")),
      (True, True))
# test:copy:change
s = change[index(change, SETTLE)][1]
check("test:copy:change: the refs checked against origin/main, the inventory before, the mirror, the refs recorded, "
      "the settle, then every check",
      ordered(change, r"copy-main-current\.sh \.\./infra:\{\{\.INFRA_REF\}\} \.\./platform:\{\{\.PLATFORM_REF\}\}$",
              r"vagrant-inventory\.sh && cp \.copy/vagrant-inventory\.txt \.copy/vagrant-inventory-before-change\.txt",
              r"--infra-ref \{\{\.INFRA_REF\}\} --platform-ref \{\{\.PLATFORM_REF\}\}",
              r"copy-refs\.sh set '\{\{\.INFRA_REF\}\}' '\{\{\.PLATFORM_REF\}\}'", SETTLE, r"^test:copy:check$"), True)
check("  its settle: on the pushed commits, the apps by APPS_CHANGED, its own stage, the deciding values",
      [f in s for f in ("-e expect_mirror=true",
                        '{{if eq .APPS_CHANGED "true"}}-e record_apps=true{{else}}-e expect_apps=true{{end}}',
                        "-e restart_stage=change-$(date +%Y%m%d%H%M%S)", "{{.COPY_SETTLE}}")], [True] * 4)
check("  every check after it, as a change's, on its refs and its pools",
      change[-1][2], {"INFRA_REF": "{{.INFRA_REF}}", "PLATFORM_REF": "{{.PLATFORM_REF}}", "CHANGE": "yes",
                      "SCRAPE_POOLS_GONE": "{{.SCRAPE_POOLS_GONE}}"})
# test:copy:playbook
p = playbook[index(playbook, SETTLE)][1]
check("test:copy:playbook: the inventory before, the guard and the playbook in ONE run, the Pis' and the cluster's "
      "isolation put back, the refs marked, the settle, every check",
      ordered(playbook, r"vagrant-inventory-before-change",
              r"vagrant-only-play\.yml playbooks/\{\{\.PLAYBOOK\}\} \{\{\.ARGS\}\}$", r"tests/ansible/isolate-pis\.yml$",
              r"copy/isolate-cluster\.yml$", r"copy-refs\.sh playbook '\{\{\.PLAYBOOK\}\}'$", SETTLE,
              r"^test:copy:check$"), True)
check("  its settle: the recorded apps, its own stage, the deciding values; the check after it a change's",
      ([f in p for f in ("-e expect_apps=true", "-e restart_stage=playbook-$(date +%Y%m%d%H%M%S)", "{{.COPY_SETTLE}}")],
       playbook[-1][2].get("CHANGE"), T["test:copy:playbook"].get("requires", {}).get("vars")),
      ([True] * 3, "yes", ["PLAYBOOK"]))
# test:copy:check
c0 = check_[0][1]
check("test:copy:check: settled first (pushed commits, recorded apps, its own stage), the parallel checks with the "
      "pools, the inventory last",
      ([f in c0 for f in ("-e expect_mirror=true", "-e expect_apps=true", "-e restart_stage=check-$(date +%Y%m%d%H%M%S)")],
       ordered(check_, SETTLE, r"^COPY_SCRAPE_POOLS_GONE='\{\{\.SCRAPE_POOLS_GONE\}\}' scripts/copy-checks\.sh "
                               r"'\{\{\.INFRA_REF\}\}' '\{\{\.PLATFORM_REF\}\}'$", r"vagrant-inventory\.sh$",
               r"copy-change-inventory\.sh .*vagrant-inventory-before-change\.txt")), ([True] * 3, True))
# the serial checks, each exactly its playbook on the copy - none in check mode, none tolerated, in this order
PB = "cd deploy/ansible && venv/bin/ansible-playbook -i inventory/vagrant.yml "
want = [PB + "../../tests/ansible/copy/" + f for f in ("barman-check.yml", "cert-check.yml", "restore-check.yml",
                                                        "backup-check.yml")] + \
    [PB + "playbooks/scylla-backup-check.yml", PB + "../../tests/ansible/copy/sweeper-check.yml"]
got = [c for _, c, _ in check_ if c.startswith(PB) and "argo-settled" not in c]
check("  its serial checks, each its playbook exactly, in order", got, want)
v = T["test:copy:check"]["vars"]
check("  run on its own: the refs and the change from copy-refs.sh, a caller's given ones first",
      (v["COPY_INFRA_REF"], v["COPY_PLATFORM_REF"], v["COPY_CHANGE"], v["INFRA_REF"], v["PLATFORM_REF"], v["CHANGE"]),
      ({"sh": "scripts/copy-refs.sh infra"}, {"sh": "scripts/copy-refs.sh platform"}, {"sh": "scripts/copy-refs.sh change"},
       "{{.INFRA_REF | default .COPY_INFRA_REF}}", "{{.PLATFORM_REF | default .COPY_PLATFORM_REF}}",
       "{{.CHANGE | default .COPY_CHANGE}}"))
last = check_[-1][1]
check("  the inventory: a change's judged by copy-change-inventory.sh, else production's exactly",
      bool(re.search(r'if \[ "\{\{\.CHANGE\}\}" = yes \]; then scripts/copy-change-inventory\.sh .* else '
                     r'scripts/inventory-diff\.sh tests/ansible/copy/prod-inventory\.txt \.copy/vagrant-inventory\.txt', last)),
      True)

# scripts/copy-refs.sh
W = tempfile.mkdtemp()
atexit.register(shutil.rmtree, W, True)
f = os.path.join(W, ".copy", "copy-refs")
env = {**os.environ, "COPY_REFS_FILE": f}


def refs(*a):
    r = subprocess.run(["scripts/copy-refs.sh", *a], capture_output=True, text=True, env=env)
    return r.stdout.strip() if r.returncode == 0 else f"rc={r.returncode}"


def state():
    return tuple(refs(x) for x in ("infra", "platform", "change"))


check("copy-refs: no file - main's, no change", state(), ("main", "main", "no"))
refs("set", "main", "main")
check("  a build (main main): no change", state(), ("main", "main", "no"))
refs("set", "fix/a", "main")
check("  a change of infra: its ref, a change", state(), ("fix/a", "main", "yes"))
refs("set", "main", "fix/b")
check("  a change of platform: its ref, a change", state(), ("main", "fix/b", "yes"))
refs("playbook", "upgrade-kubeadm.yml")
check("  a playbook on top: the refs kept, a change", (state(), open(f).read().strip()),
      (("main", "fix/b", "yes"), "main fix/b playbook:upgrade-kubeadm.yml"))
refs("set", "main", "main")
check("  rebuilt: the playbook mark gone", state(), ("main", "main", "no"))
os.remove(f)
refs("playbook", "x.yml")
check("  a playbook on a copy with no record: main's refs, a change", state(), ("main", "main", "yes"))
check("  usage refused (exit 2)", (refs("set", "a"), refs("bogus"), refs()), ("rc=2", "rc=2", "rc=2"))
print("copy-tasks: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_COPY_TASKS
