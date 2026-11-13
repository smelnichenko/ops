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
check("test:copy:argo: main checked, mirrored, recorded as main main, the build's settle (apps recorded), the inventory "
      "judged against production's, then kept as the baseline a change is judged from",
      (ordered(argo, r"copy-main-current\.sh \.\./infra \.\./platform$", r"--infra-ref main --platform-ref main",
               r"copy-refs\.sh set main main$", SETTLE, r"^scripts/inventory-diff\.sh tests/ansible/copy/prod-inventory\.txt "
               r"\.copy/vagrant-inventory\.txt", r"^cp \.copy/vagrant-inventory\.txt \.copy/vagrant-inventory-build\.txt$"),
       argo[index(argo, SETTLE)][1].endswith(
           "-e expect_mirror=true -e record_apps=true -e restart_stage=build-$(date +%Y%m%d%H%M%S) {{.COPY_SETTLE}}")),
      (True, True))
build = cmds("test:copy:build")
check("test:copy:build: main checked, then the record of what the copy ran cleared, then production read",
      ordered(build, r"^scripts/copy-main-current\.sh \.\./infra \.\./platform$", r"^scripts/copy-refs\.sh reset$",
              r"^test:copy:inventory$"), True)
# test:copy:change
s = change[index(change, SETTLE)][1]
check("test:copy:change: the refs checked against origin/main, recorded, the mirror, the settle, the "
      "inventory as the change left it (before any check), then every check",
      ordered(change, r"copy-main-current\.sh \.\./infra:\{\{\.INFRA_REF\}\} \.\./platform:\{\{\.PLATFORM_REF\}\}$",
              r"copy-refs\.sh set '\{\{\.INFRA_REF\}\}' '\{\{\.PLATFORM_REF\}\}'",
              r"--infra-ref \{\{\.INFRA_REF\}\} --platform-ref \{\{\.PLATFORM_REF\}\}", SETTLE, r"^scripts/vagrant-inventory\.sh && cp \.copy/vagrant-inventory\.txt \.copy/vagrant-inventory-after-change\.txt$",
              r"^test:copy:check$"), True)
check("  its settle: on the pushed commits, the apps by APPS_CHANGED, its own stage, the deciding values",
      [f in s for f in ("-e expect_mirror=true",
                        '{{if eq .APPS_CHANGED "true"}}-e record_apps=true{{else}}-e expect_apps=true{{end}}',
                        "-e restart_stage=change-$(date +%Y%m%d%H%M%S)", "{{.COPY_SETTLE}}")], [True] * 4)
check("  every check after it, as a change's, on its refs and its pools",
      change[-1][2], {"INFRA_REF": "{{.INFRA_REF}}", "PLATFORM_REF": "{{.PLATFORM_REF}}", "CHANGE": "yes",
                      "SCRAPE_POOLS_GONE": "{{.SCRAPE_POOLS_GONE}}"})
# test:copy:playbook
p = playbook[index(playbook, SETTLE)][1]
check("test:copy:playbook: the refs marked first, the guard and the playbook in ONE run (production's environment left "
      "out), the Pis' and the cluster's isolation put back, the settle, the inventory as it left the copy, every check",
      ordered(playbook, r"copy-refs\.sh playbook '\{\{\.PLAYBOOK\}\}'$",
              r"^env -i HOME=\"\$HOME\" PATH=\"\$PATH\" bash -c 'cd deploy/ansible && .*vagrant-only-play\.yml "
              r"playbooks/\{\{\.PLAYBOOK\}\} \{\{\.ARGS\}\}'$", r"tests/ansible/isolate-pis\.yml$",
              r"copy/isolate-cluster\.yml$", SETTLE,
              r"^scripts/vagrant-inventory\.sh && cp \.copy/vagrant-inventory\.txt \.copy/vagrant-inventory-after-change\.txt$", r"^test:copy:check$"), True)
check("  its settle: the recorded apps, its own stage, the deciding values; the check after it a change's",
      ([f in p for f in ("-e expect_apps=true", "-e restart_stage=playbook-$(date +%Y%m%d%H%M%S)",
                         "-e restarts_expected={{.RESTARTS_EXPECTED}}", "{{.COPY_SETTLE}}")],
       playbook[-1][2].get("CHANGE"), T["test:copy:playbook"].get("requires", {}).get("vars")),
      ([True] * 4, "yes", ["PLAYBOOK"]))
# test:copy:check
c0 = check_[index(check_, SETTLE)][1]
check("test:copy:check: the lock, then settled (pushed commits, recorded apps, its own stage), the parallel checks with the "
      "pools, the inventory last",
      ([f in c0 for f in ("-e expect_mirror=true", "-e expect_apps=true", "-e restart_stage=check-$(date +%Y%m%d%H%M%S)")],
       ordered(check_, r"^scripts/copy-lock\.sh$", SETTLE, r"^COPY_SCRAPE_POOLS_GONE='\{\{\.SCRAPE_POOLS_GONE\}\}' scripts/copy-checks\.sh "
                               r"'\{\{\.INFRA_REF\}\}' '\{\{\.PLATFORM_REF\}\}'$", r"vagrant-inventory\.sh$",
               r"copy-change-inventory\.sh tests/ansible/copy/prod-inventory\.txt \.copy/vagrant-inventory-build\.txt "
               r"\\? \.copy/vagrant-inventory-after-change\.txt \.copy/vagrant-inventory\.txt \{\{\.ALLOWED_MISSING\}\}")),
      ([True] * 3, True))
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


G = os.path.join(W, "git")
for r in ("infra", "platform"):
    d = os.path.join(G, r)
    subprocess.run(["git", "init", "-q", "-b", "main", d], check=True)
    for b in ("main", "fix/a", "fix/b"):
        subprocess.run(["git", "-C", d, "checkout", "-q", "-B", b], check=True)
        subprocess.run(["git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty",
                        "-m", b], check=True)
env.update(COPY_INFRA_DIR=os.path.join(G, "infra"), COPY_PLATFORM_DIR=os.path.join(G, "platform"))
sha = lambda r, b: subprocess.run(["git", "-C", os.path.join(G, r), "rev-parse", b], capture_output=True, text=True).stdout.strip()
check("copy-refs: no file - main's, no change", state(), ("main", "main", "no"))
refs("set", "main", "main")
check("  a build (main main): main's commits, no change", state(), (sha("infra", "main"), sha("platform", "main"), "no"))
refs("set", "fix/a", "main")
check("  a change of infra: its commit, a change", state(), (sha("infra", "fix/a"), sha("platform", "main"), "yes"))
was = sha("infra", "fix/a")
subprocess.run(["git", "-C", os.path.join(G, "infra"), "checkout", "-q", "fix/a"], check=True)
subprocess.run(["git", "-C", os.path.join(G, "infra"), "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q",
                "--allow-empty", "-m", "moved"], check=True)
check("  the branch moved since: the commit the copy runs, not its new tip",
      (refs("infra") == was, sha("infra", "fix/a") != was), (True, True))
check("  a ref not there: refused, the record unchanged", (refs("set", "nosuch", "main"), refs("change")), ("rc=1", "yes"))
refs("set", "main", "fix/b")
check("  a change of platform: its commit, a change", state(), (sha("infra", "main"), sha("platform", "fix/b"), "yes"))
refs("playbook", "upgrade-kubeadm.yml")
check("  a playbook on top: the commits kept, a change", (state()[1:], open(f).read().split()[2:]),
      ((sha("platform", "fix/b"), "yes"), ["playbook:upgrade-kubeadm.yml"]))
refs("set", "main", "main")
check("  main mirrored after a playbook: still a change (the playbook stays applied)", refs("change"), "yes")
refs("reset")
check("  a build from nothing (reset): main's, no change", state(), ("main", "main", "no"))
refs("playbook", "x.yml")
check("  a playbook on a copy with no record: main's refs, a change", state(), ("main", "main", "yes"))
for text, want in (("", ("main", "main")), ("fix/a@abc", ("abc", "main"))):
    open(f, "w").write(text + "\n")
    check(f"  a record {text!r}: what is missing read as main", state()[:2], want)
check("  usage refused (exit 2), the record unchanged", (refs("set", "a"), refs("playbook"), refs("bogus"), refs(),
      open(f).read().strip()), ("rc=2", "rc=2", "rc=2", "rc=2", "fix/a@abc"))
# every copy task whole - each command, in order, and its vars - against expected.json beside this file: a seed dropped,
# an env -i lost (production's .env into the copy), a default moved, an argument left off passes every check above that
# reads one line. A Taskfile change to these tasks changes expected.json in the same commit (its diff is the review)
import json as _json
expected = _json.load(open("tests/ansible/unit/copy-tasks/expected.json"))
whole = lambda n: [(" ".join(str(c.get("cmd", c) if isinstance(c, dict) else c).split()) if not (isinstance(c, dict) and "task" in c)
                    else {"task": c["task"], "vars": c.get("vars") or {}}) for c in T[n].get("cmds") or []]
for n in sorted(k for k in expected if k != "COPY_SETTLE"):
    check(f"{n}: every command in order, and its vars, as expected.json", (whole(n), T[n].get("vars") or {}),
          (expected[n]["cmds"], expected[n]["vars"]))
check("COPY_SETTLE: the deciding settle's values, as expected.json",
      yaml.safe_load(open("Taskfile.yml"))["vars"]["COPY_SETTLE"], expected["COPY_SETTLE"])
print("copy-tasks: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_COPY_TASKS
