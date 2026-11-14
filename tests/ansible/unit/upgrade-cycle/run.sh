#!/bin/bash
# scripts/upgrade-cycle.sh - the upgrade cycle's night - in a throwaway ops directory, every helper and tool stubbed
# (the pick, the labels, the notices, verify, record; task, the agent, ssh, vagrant, git), each call recorded: a backup
# window ends the night at once; NOTHING/PAUSED touch nothing; memory short: one notice to stop the radar, no build; a
# patch unit proven, reviewed, merged, its ops parts' production tasks (Kubernetes after an etcd snapshot, Forgejo),
# verified, recorded, reported; red: the agent's one fix, then green; red twice: blocked, reported; a Critical review:
# blocked; a major's first night: its notice, nothing merged; a one-way unit without a backup path: blocked, never
# applied; a failed merge: no production task; an ops part with no task, or a failed verify: paged as one-way; the
# copy destroyed whenever one was built, never when none was; a pick it cannot read: refused.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
REAL=$PWD
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
python3 - "$REAL" "$W" <<'PYCHECK'
import os, shutil, subprocess, sys
REAL, W = sys.argv[1], sys.argv[2]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
OPS = os.path.join(W, "ops"); BIN = os.path.join(W, "bin"); ST = os.path.join(W, "state")
for d in (os.path.join(OPS, "scripts"), BIN, ST):
    os.makedirs(d, exist_ok=True)
shutil.copy(os.path.join(REAL, "scripts/upgrade-cycle.sh"), os.path.join(OPS, "scripts"))
def stub(path, body):
    open(path, "w").write("#!/bin/bash\n" + body + "\n")
    os.chmod(path, 0o755)
LOG = 'echo "$(basename "$0") $*" >> "$ST/calls"'
stub(os.path.join(OPS, "scripts/upgrade-units.py"), LOG + '\ncat "$ST/pick"; exit "$(cat "$ST/pick.rc" 2>/dev/null || echo 0)"')
stub(os.path.join(OPS, "scripts/upgrade-label.py"), LOG + '\n[ "$2" != --merge ] || exit "$(cat "$ST/merge.rc" 2>/dev/null || echo 0)"')
stub(os.path.join(OPS, "scripts/upgrade-notice.sh"), LOG)
stub(os.path.join(OPS, "scripts/upgrade-verify.sh"), LOG + '\nexit "$(cat "$ST/verify.rc" 2>/dev/null || echo 0)"')
stub(os.path.join(OPS, "scripts/upgrade-record.sh"), LOG)
# task: the build's and the unit proof's verdicts from files (the proof's a list: one per try), the plan from a file
stub(os.path.join(BIN, "task"), LOG + '''
case "$*" in
  *PLAN=true*) cat "$ST/plan" ;;
  test:copy:build) exit "$(cat "$ST/build.rc" 2>/dev/null || echo 0)" ;;
  test:copy:unit*) n=$(head -1 "$ST/proofs"); sed -i 1d "$ST/proofs"; exit "${n:-0}" ;;
esac''')
stub(os.path.join(BIN, "claude"), LOG + '\ncase "$*" in *review*) cat "$ST/verdict" ;; *upgrade-fix*) cat "$ST/fix.out" 2>/dev/null ;; esac')
for t in ("ssh", "vagrant", "git"):
    stub(os.path.join(BIN, t), LOG)
def night(pick, proofs=(0,), plan="", verdict="VERDICT: CLEAN", hm="20:00", mem=30000, files=None, args=()):
    for f in os.listdir(ST):
        os.remove(os.path.join(ST, f))
    shutil.rmtree(os.path.join(OPS, ".copy"), ignore_errors=True)  # each night's logs its own
    open(os.path.join(ST, "pick"), "w").write(pick + "\n")
    open(os.path.join(ST, "proofs"), "w").write("".join(f"{p}\n" for p in proofs))
    open(os.path.join(ST, "plan"), "w").write(plan)
    open(os.path.join(ST, "verdict"), "w").write(verdict + "\n")
    open(os.path.join(ST, "meminfo"), "w").write(f"MemAvailable: {mem * 1024} kB\n")
    for f, v in (files or {}).items():
        open(os.path.join(ST, f), "w").write(v)
    env = {**os.environ, "PATH": BIN + ":" + os.environ["PATH"], "ST": ST, "UPGRADE_NOW_HM": hm,
           "UPGRADE_MEMINFO": os.path.join(ST, "meminfo"), "UPGRADE_DEADLINE": "00:00"}
    r = subprocess.run(["bash", os.path.join(OPS, "scripts/upgrade-cycle.sh"), *args], capture_output=True, text=True, env=env,
                       timeout=60)
    calls = open(os.path.join(ST, "calls")).read().splitlines() if os.path.exists(os.path.join(ST, "calls")) else []
    return r.returncode, calls
def has(calls, prefix):
    return [c for c in calls if c.startswith(prefix)]
rc, calls = night("prove wave-patches patch", hm="03:00")
check("a backup window: the night ends at once, nothing asked", (rc, calls), (0, []))
rc, calls = night("prove wave-patches patch", hm="05:30")
check("the restore check's window too", (rc, calls), (0, []))
for p in ("NOTHING", "PAUSED"):
    rc, calls = night(p)
    check(f"{p}: the pick alone, nothing built or destroyed", (rc, calls), (0, ["upgrade-units.py pick"]))
rc, calls = night("prove wave-patches patch", mem=20000)
check("memory short: one notice to stop the radar, no build, no copy destroyed",
      (rc, [c.split(" ")[0] + " " + c.split(" ")[1] for c in calls[1:]], "stop the radar" in " ".join(calls), has(calls, "task")),
      (0, ["upgrade-notice.sh blocked"], True, []))
PLAN = ("test:copy:change INFRA_REF=renovate/wave-patches PLATFORM_REF=main\n"
        "test:copy:playbook PLAYBOOK=upgrade-kubeadm.yml ARGS='-e k8s_upgrade_to=1.36.7' RESTARTS_EXPECTED=true\n"
        "test:copy:playbook PLAYBOOK=upgrade-forgejo.yml ARGS='-e @/x/forgejo.yml'\n")
rc, calls = night("prove wave-patches patch", plan=PLAN)
def words(c, n):
    return " ".join(c.split(" ")[:n])
seq = [c for c in calls if not c.startswith("upgrade-units.py")]
check("a patch unit: proven, reviewed, an etcd snapshot, merged, ops pulled, its production tasks, verified, the "
      "inventory read, recorded, reported, the copy destroyed - in that order",
      (rc, [words(c, 2) for c in seq]),
      (0, ["task test:copy:build", "task test:copy:unit", "claude -p", "task test:copy:unit", "ssh ten",
           "upgrade-label.py wave-patches", "git -C", "task --yes", "task --yes", "upgrade-verify.sh ", "task test:copy:inventory",
           "upgrade-record.sh wave-patches", "upgrade-notice.sh applied", "vagrant destroy"]))
check("  the snapshot is etcd's, the merge the unit's, the tasks Kubernetes' then Forgejo's",
      ("cronjob/etcd-backup" in seq[4], seq[5], [words(c, 3) for c in has(calls, "task --yes")]),
      (True, "upgrade-label.py wave-patches --merge", ["task --yes deploy:kubeadm:upgrade", "task --yes deploy:forgejo:upgrade"]))
check("  Kubernetes to the proven version", has(calls, "task --yes deploy:kubeadm:upgrade"),
      ["task --yes deploy:kubeadm:upgrade -- -e k8s_upgrade_to=1.36.7"])
check("  the agent asked once: the review, not a fix", [c.split(" ")[2] for c in has(calls, "claude")], ["upgrade-cycle"])
check("  the applied notice says the radar may start", "the radar may start" in " ".join(has(calls, "upgrade-notice.sh applied")), True)
rc, calls = night("prove istio minor", proofs=(1, 0), plan="test:copy:change INFRA_REF=renovate/istio PLATFORM_REF=renovate/istio\n")
check("red, then the agent's one fix, then green: on to the apply",
      (rc, len(has(calls, "task test:copy:build")), "upgrade-fix skill" in " ".join(has(calls, "claude")),
       len(has(calls, "upgrade-label.py istio --merge"))), (0, 2, True, 1))
rc, calls = night("prove istio minor", proofs=(1, 1))
check("red after its fix: labelled upgrade-blocked, reported, nothing merged, the copy destroyed",
      (rc, has(calls, "upgrade-label.py"), [words(c, 3) for c in has(calls, "upgrade-notice.sh")], has(calls, "vagrant")),
      (1, ["upgrade-label.py istio upgrade-blocked"], ["upgrade-notice.sh blocked istio"], ["vagrant destroy -f"]))
rc, calls = night("prove istio minor", verdict="VERDICT: CRITICAL a bad thing")
check("a Critical review: blocked, nothing merged", (rc, has(calls, "upgrade-label.py")), (1, ["upgrade-label.py istio upgrade-blocked"]))
rc, calls = night("prove istio minor", proofs=(1, 0), verdict="VERDICT: CRITICAL still bad", files={"fix.out": "VERDICT: CLEAN\n"})
check("a CLEAN another step printed into the night's log is not the review's verdict: blocked",
      (rc, has(calls, "upgrade-label.py")), (1, ["upgrade-label.py istio upgrade-blocked"]))
rc, calls = night("prove istio minor", verdict="(the agent printed no verdict)")
check("no verdict at all: blocked", (rc, has(calls, "upgrade-label.py")), (1, ["upgrade-label.py istio upgrade-blocked"]))
rc, calls = night("notice kafka-5.x major")
check("a major's first night: proven, reviewed, its notice comment and mail - nothing merged",
      (rc, [words(c, 4) for c in has(calls, "upgrade-label.py")], [words(c, 3) for c in has(calls, "upgrade-notice.sh")],
       has(calls, "upgrade-label.py kafka-5.x --merge")),
      (0, ["upgrade-label.py kafka-5.x --comment UPGRADE"], ["upgrade-notice.sh veto kafka-5.x"], []))
rc, calls = night("apply postgresql-19.x major", plan="test:copy:change INFRA_REF=renovate/postgresql-19.x PLATFORM_REF=main\n")
check("a one-way unit with no backup path: blocked, never merged",
      (rc, has(calls, "upgrade-label.py")), (1, ["upgrade-label.py postgresql-19.x upgrade-blocked"]))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"merge.rc": "1"})
check("a failed merge: no production task, reported", (rc, has(calls, "task --yes"), [words(c, 3) for c in has(calls, "upgrade-notice.sh")]),
      (1, [], ["upgrade-notice.sh blocked wave-patches"]))
rc, calls = night("prove wave-patches patch", plan="test:copy:playbook PLAYBOOK=setup-mystery.yml ARGS=''\n")
check("an ops part with no production task: paged as one-way", (rc, [words(c, 3) for c in has(calls, "upgrade-notice.sh")]),
      (1, ["upgrade-notice.sh one-way-failed wave-patches"]))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"verify.rc": "1"})
check("verify red: paged as one-way, not recorded as applied",
      (rc, [words(c, 3) for c in has(calls, "upgrade-notice.sh")], has(calls, "upgrade-record")),
      (1, ["upgrade-notice.sh one-way-failed wave-patches"], []))
rc, calls = night("prove wave-patches patch", plan=PLAN, args=("--shadow",))
check("--shadow: proven and reviewed, the result a comment - no notice, no merge, no production task, the copy destroyed",
      (rc, [words(c, 3) for c in has(calls, "upgrade-label.py")], has(calls, "upgrade-notice"), has(calls, "task --yes"),
       has(calls, "vagrant")),
      (0, ["upgrade-label.py wave-patches --comment"], [], [], ["vagrant destroy -f"]))
rc, calls = night("notice kafka-5.x major", args=("--shadow",))
check("--shadow on a major: no veto notice either", (rc, has(calls, "upgrade-notice")), (0, []))
r = subprocess.run(["bash", os.path.join(OPS, "scripts/upgrade-cycle.sh"), "--apply-all"], capture_output=True, text=True)
check("an option it does not take: refused", r.returncode, 2)
rc, calls = night("prove Bad/Unit patch")
check("a pick it cannot read: refused, nothing built", (rc, has(calls, "task")), (1, []))
rc, calls = night("", files={"pick.rc": "1"})
check("Forgejo not read: the night changes nothing", (rc, has(calls, "task")), (1, []))
print("upgrade-cycle: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
