#!/bin/bash
# scripts/upgrade-cycle.sh - the upgrade cycle's run - in a throwaway ops directory, every helper and tool stubbed (the
# pick, the labels, the notices, verify, record; task, the agent, ssh, vagrant, git), each call recorded:
#   the gates, before anything: a backup window (the real schedules, Sunday's repair too), an open page (posted again),
#   ops not on main / changed / not origin's, memory short (refused at once - never a wait), an apply recorded today -
#   each refuses, nothing picked; --preflight the gates alone
#   a patch unit: its heads read, proven, reviewed (the agent in clones, a clean environment, settings of its own), the
#   heads after the proof the same, an etcd backup by its task, merged at the proven heads, ops pulled, its production
#   tasks, verified, recorded, reported; red: the agent's one fix (its pushes labelled stop-updating), green; red twice:
#   blocked; a Critical review: blocked; a major's first run: its notice; one-way without a backup path: blocked; the
#   heads moved during the proof, the plan not read, the etcd backup failing, a failed merge: nothing applied; ops not
#   pulled, an ops part with no task, a failed verify: paged; a window at the apply: waited out; the copy destroyed
#   whenever one was built, never when none was; a pick it cannot read: refused.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
REAL=$PWD
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
python3 - "$REAL" "$W" <<'PYCHECK'
import json, os, shutil, subprocess, sys
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
    # the state directory written in whole: the agents run with env -i, no ST of theirs
    open(path, "w").write("#!/bin/bash\nST=" + ST + "\n" + body + "\n")
    os.chmod(path, 0o755)
LOG = 'echo "$(basename "$0") $*" >> "$ST/calls"'
# list: the open units with their labels (default: the picked one, labelled upgrade-cycle alone); pick: the pick
stub(os.path.join(OPS, "scripts/upgrade-units.py"), LOG + '''
case "$1" in
  list) [ ! -e "$ST/list.fail" ] || exit 1
    if [ -e "$ST/list" ]; then cat "$ST/list"; else read -r _ u k < "$ST/pick"; echo "$u $k schnappy/infra upgrade-cycle"; fi ;;
  *) cat "$ST/pick"; exit "$(cat "$ST/pick.rc" 2>/dev/null || echo 0)" ;;
esac''')
# --heads: the next of its answers (one per read; the last stays); --merge --expect FILE: the file kept, its rc
stub(os.path.join(OPS, "scripts/upgrade-label.py"), LOG + '''
case "$2" in
  --heads) [ ! -e "$ST/heads.fail" ] || exit 1
    n=$(cat "$ST/heads.n" 2>/dev/null || echo 0); f="$ST/heads.$n"; [ -e "$f" ] || f="$ST/heads.last"
    [ ! -e "$ST/heads.override" ] || f="$ST/heads.override"
    cat "$f"; [ -e "$ST/heads.$((n + 1))" ] && echo $((n + 1)) > "$ST/heads.n"; exit 0 ;;
  --merge) cp "$4" "$ST/merged.expect"; exit "$(cat "$ST/merge.rc" 2>/dev/null || echo 0)" ;;
esac''')
stub(os.path.join(OPS, "scripts/upgrade-notice.sh"), LOG + '\n[ "$1" != open ] || cat "$ST/open" 2>/dev/null; exit 0')
stub(os.path.join(OPS, "scripts/upgrade-verify.sh"), LOG + '\nexit "$(cat "$ST/verify.rc" 2>/dev/null || echo 0)"')
stub(os.path.join(OPS, "scripts/upgrade-record.sh"), LOG)
# task: the build's and the unit proof's verdicts from files (the proof's a list: one per try), the plan from a file
stub(os.path.join(BIN, "task"), LOG + '''
case "$*" in
  *PLAN=true*) [ ! -e "$ST/plan.fail" ] || exit 1; cat "$ST/plan" ;;
  test:copy:build) exit "$(cat "$ST/build.rc" 2>/dev/null || echo 0)" ;;
  test:copy:unit*) n=$(head -1 "$ST/proofs"); sed -i 1d "$ST/proofs"; exit "${n:-0}" ;;
  "--yes deploy:etcd:backup") exit "$(cat "$ST/etcd.rc" 2>/dev/null || echo 0)" ;;
esac''')
# the agent: its environment's names, its directory and its arguments kept per call
stub(os.path.join(BIN, "claude"), LOG + '''
n=$(ls "$ST"/agent.* 2>/dev/null | wc -l)
{ echo "pwd=$PWD"; env | cut -d= -f1 | sort | tr '\\n' ' '; echo; printf '%s\\n' "$@"; } > "$ST/agent.$n"
case "$*" in *review*) cat "$ST/verdict" ;; *upgrade-fix*) cat "$ST/fix.out" 2>/dev/null; [ ! -e "$ST/fix.heads" ] || cp "$ST/fix.heads" "$ST/heads.override" ;; esac''')
# git: ops on main, clean, origin's - as the state files say; a clone made; a pull's verdict
stub(os.path.join(BIN, "git"), LOG + '''
args="$*"
case "$args" in
  *"rev-parse --abbrev-ref HEAD"*) cat "$ST/branch" 2>/dev/null || echo main ;;
  *"status --porcelain"*) cat "$ST/dirty" 2>/dev/null ;;
  *"fetch -q origin main"*) exit "$(cat "$ST/fetch.rc" 2>/dev/null || echo 0)" ;;
  *"rev-parse HEAD"*) echo 1111111111111111111111111111111111111111 ;;
  *"rev-parse origin/main"*) cat "$ST/origin" 2>/dev/null || echo 1111111111111111111111111111111111111111 ;;
  clone*) mkdir -p "${@: -1}" ;;
  *" pull "*) exit "$(cat "$ST/pull.rc" 2>/dev/null || echo 0)" ;;
esac''')
stub(os.path.join(BIN, "sleep"), LOG)
for t in ("ssh", "vagrant"):
    stub(os.path.join(BIN, t), LOG)
H1 = "schnappy/infra 4 " + "a" * 40 + "\nschnappy/ops 7 " + "c" * 40 + "\n"
H2 = "schnappy/infra 4 " + "b" * 40 + "\nschnappy/ops 7 " + "c" * 40 + "\n"
def night(pick, proofs=(0,), plan="test:copy:change INFRA_REF=renovate/x PLATFORM_REF=main\n", verdict="VERDICT: CLEAN", hm="20:00", dow="3", mem=30000, files=None, args=(),
          heads=(H1,), env=None, records=()):
    for f in os.listdir(ST):
        os.remove(os.path.join(ST, f))
    for d in (".copy", "docs"):
        shutil.rmtree(os.path.join(OPS, d), ignore_errors=True)  # each run's logs, records its own
    for r in records:
        os.makedirs(os.path.join(OPS, "docs/upgrades"), exist_ok=True)
        open(os.path.join(OPS, "docs/upgrades", r), "w").write("x\n")
    open(os.path.join(ST, "pick"), "w").write(pick + "\n")
    open(os.path.join(ST, "proofs"), "w").write("".join(f"{p}\n" for p in proofs))
    open(os.path.join(ST, "plan"), "w").write(plan)
    open(os.path.join(ST, "verdict"), "w").write(verdict + "\n")
    open(os.path.join(ST, "meminfo"), "w").write(f"MemAvailable: {mem * 1024} kB\n")
    for i, h in enumerate(heads):
        open(os.path.join(ST, f"heads.{i}"), "w").write(h)
    open(os.path.join(ST, "heads.last"), "w").write(heads[-1])
    for f, v in (files or {}).items():
        open(os.path.join(ST, f), "w").write(v)
    e = {**os.environ, "PATH": BIN + ":" + os.environ["PATH"], "ST": ST, "UPGRADE_NOW_DOW": dow,
         "UPGRADE_MEMINFO": os.path.join(ST, "meminfo"), "UPGRADE_TODAY": "2026-11-20",
         "ANTHROPIC_API_KEY": "sk-the-apps-key", "RENOVATE_TOKEN": "bot-token", "VAULT_ROOT_TOKEN": "root"}
    if isinstance(hm, list):
        open(os.path.join(ST, "hm"), "w").write("".join(f"{x}\n" for x in hm))
        e["UPGRADE_NOW_HM_FILE"] = os.path.join(ST, "hm")
    else:
        e["UPGRADE_NOW_HM"] = hm
    e.update(env or {})
    r = subprocess.run(["bash", os.path.join(OPS, "scripts/upgrade-cycle.sh"), *args], capture_output=True, text=True, env=e,
                       timeout=60)
    calls = open(os.path.join(ST, "calls")).read().splitlines() if os.path.exists(os.path.join(ST, "calls")) else []
    return r.returncode, calls
def has(calls, prefix):
    return [c for c in calls if c.startswith(prefix)]
def words(c, n):
    return " ".join(c.split(" ")[:n]).strip()
def norm(c):  # a call as the order checks read it: its first three words (record's two: then its log's path)
    return words(c, 2 if c.startswith("upgrade-record.sh") else 3)
def picked(calls):
    return bool(has(calls, "upgrade-units.py pick"))
def flag(args, name):  # the value after a flag, or None (never a crash: the flag missing is a finding)
    return args[args.index(name) + 1] if name in args else None
def agents():
    out = []
    for f in sorted(x for x in os.listdir(ST) if x.startswith("agent.")):
        lines = open(os.path.join(ST, f)).read().split("\n")
        out.append({"pwd": lines[0][4:], "env": lines[1].split(), "args": [x for x in lines[2:] if x]})
    return out
# ── the gates ─────────────────────────────────────────────────────────────────────────────────────────────────────────
for hm, dow, why in (("03:00", "3", "Velero, the Pis' and ScyllaDB's backups"), ("00:55", "3", "the mirror's summer hour"),
                     ("01:35", "3", "CNPG's base backup"), ("05:30", "3", "the Pis' restore check"),
                     ("04:30", "7", "Sunday's ScyllaDB repair")):
    rc, calls = night("prove wave-patches patch", hm=hm, dow=dow)
    check(f"a backup window ({hm}, day {dow}: {why}): refused at once, nothing asked", (rc, calls), (1, []))
rc, calls = night("prove wave-patches patch", hm="04:30", dow="3")
check("04:30 on a weekday: no window - on", (rc, picked(calls)), (0, True))
rc, calls = night("prove wave-patches patch", files={"open": "scylla-2026.3\n"})
check("an open page: posted again (Alertmanager forgets on a restart), refused, nothing picked",
      (rc, has(calls, "upgrade-notice.sh"), picked(calls)),
      (1, ["upgrade-notice.sh open", "upgrade-notice.sh repost"], False))
for files, why in (({"branch": "feat/x\n"}, "on another branch"), ({"dirty": " M Taskfile.yml\n"}, "with changes"),
                   ({"origin": "2" * 40 + "\n"}, "behind or ahead of origin"), ({"fetch.rc": "1"}, "origin not read")):
    rc, calls = night("prove wave-patches patch", files=files)
    check(f"ops {why}: refused - its tasks are what applies - nothing picked", (rc, picked(calls)), (1, False))
rc, calls = night("prove wave-patches patch", mem=20000)
check("memory short (the radar running): refused at once - no notice, no wait, nothing picked",
      (rc, picked(calls), has(calls, "upgrade-notice.sh blocked"), has(calls, "sleep")), (1, False, [], []))
rc, calls = night("prove wave-patches patch", records=("2026-11-20-istio.md",))
check("a production apply recorded today: refused (one a day), nothing picked", (rc, picked(calls)), (1, False))
rc, calls = night("prove wave-patches patch", records=("2026-11-19-istio.md",))
check("one recorded yesterday: on", (rc, picked(calls)), (0, True))
rc, calls = night("prove wave-patches patch", args=("--preflight",))
check("--preflight, the gates passing: exit 0, nothing picked or built", (rc, picked(calls), has(calls, "task")), (0, False, []))
rc, calls = night("prove wave-patches patch", args=("--preflight",), mem=20000)
check("--preflight, a gate refusing: exit 1", rc, 1)
for p in ("NOTHING", "PAUSED"):
    rc, calls = night(p)
    check(f"{p}: the pick alone, nothing built or destroyed", (rc, has(calls, "task"), has(calls, "vagrant")), (0, [], []))
# ── a unit, proven and applied ────────────────────────────────────────────────────────────────────────────────────────
PLAN = ("test:copy:change INFRA_REF=renovate/wave-patches PLATFORM_REF=main\n"
        "test:copy:playbook PLAYBOOK=upgrade-kubeadm.yml ARGS='-e k8s_upgrade_to=1.36.7' RESTARTS_EXPECTED=true\n"
        "test:copy:playbook PLAYBOOK=upgrade-forgejo.yml ARGS='-e @/x/forgejo.yml'\n")
rc, calls = night("prove wave-patches patch", plan=PLAN)
seq = [norm(c) for c in calls if not c.startswith(("upgrade-units.py", "git -C", "upgrade-notice.sh open"))]
check("a patch unit: heads, proven, heads again, cloned, reviewed, the plan, the etcd backup, merged, ops pulled, its "
      "production tasks, verified, the inventory read, recorded, reported, the copy destroyed - in that order",
      (rc, seq),
      (0, ["upgrade-label.py wave-patches --heads", "task test:copy:build", "task test:copy:unit UNIT=wave-patches",
           "upgrade-label.py wave-patches --heads", "git clone -q", "git clone -q", "claude -p upgrade-cycle",
           "task test:copy:unit UNIT=wave-patches", "task --yes deploy:etcd:backup", "upgrade-label.py wave-patches --merge",
           "task --yes deploy:kubeadm:upgrade", "task --yes deploy:forgejo:upgrade", "upgrade-verify.sh",
           "task test:copy:inventory", "upgrade-record.sh wave-patches", "upgrade-notice.sh applied wave-patches",
           "vagrant destroy -f"]))
check("  merged at the heads proven (the file the proof read), ops pulled from origin",
      (open(os.path.join(ST, "merged.expect")).read(), len(has(calls, "git -C " + OPS + " pull -q --ff-only origin main"))),
      (H1, 1))
check("  each repo of the unit cloned on its branch, the review's", [c.split()[4:6] for c in has(calls, "git clone")],
      [["renovate/wave-patches", "https://git.pmon.dev/schnappy/infra.git"],
       ["renovate/wave-patches", "https://git.pmon.dev/schnappy/ops.git"]])
check("  Kubernetes to the proven version", has(calls, "task --yes deploy:kubeadm:upgrade"),
      ["task --yes deploy:kubeadm:upgrade -- -e k8s_upgrade_to=1.36.7"])
a = agents()
check("  the review agent: in its clones, none of the task's environment (no API key, no bot token, no Vault token), "
      "settings of its own (the operator's skipped), anything else denied - never asked",
      (len(a), a[0]["pwd"].startswith(os.path.join(OPS, ".copy/upgrade-fix/wave-patches-review-")),
       sorted(set(a[0]["env"]) - {"PWD", "SHLVL", "_", "OLDPWD"}),
       [x for x in a[0]["args"][1:] if x.startswith("--")], flag(a[0]["args"], "--settings"),
       flag(a[0]["args"], "--setting-sources"), flag(a[0]["args"], "--permission-mode")),
      (1, True, ["HOME", "LANG", "PATH", "VAGRANT_CWD"],
       ["--setting-sources", "--settings", "--strict-mcp-config", "--permission-mode", "--permission-prompts"],
       os.path.join(OPS, ".claude/upgrade-agent/review.json"), "project,local", "dontAsk"))
check("  the applied notice says the radar may start", "the radar may start" in " ".join(has(calls, "upgrade-notice.sh applied")), True)
rc, calls = night("prove istio minor", proofs=(1, 0), plan="test:copy:change INFRA_REF=renovate/istio PLATFORM_REF=renovate/istio\n",
                  files={"fix.heads": H2})
a = agents()
check("red, the agent's one fix (in clones of the unit, the proof's log beside them, a clean environment, the fix's own "
      "settings), its pushes labelled stop-updating, proven again: merged at the fixed heads",
      (rc, len(has(calls, "task test:copy:build")), a[0]["pwd"].startswith(os.path.join(OPS, ".copy/upgrade-fix/istio-")),
       os.path.exists(os.path.join(a[0]["pwd"], "proof.log")), "ANTHROPIC_API_KEY" in a[0]["env"],
       flag(a[0]["args"], "--settings"), has(calls, "upgrade-label.py istio stop-updating"),
       open(os.path.join(ST, "merged.expect")).read()),
      (0, 2, True, True, False, os.path.join(OPS, ".claude/upgrade-agent/fix.json"), ["upgrade-label.py istio stop-updating"], H2))
rc, calls = night("prove istio minor", proofs=(1, 0), plan="test:copy:change INFRA_REF=renovate/istio PLATFORM_REF=renovate/istio\n")
check("a fix that pushed nothing: no stop-updating label", (rc, has(calls, "upgrade-label.py istio stop-updating")), (0, []))
rc, calls = night("prove istio minor", proofs=(1, 1))
check("red after its fix: labelled upgrade-blocked, reported, nothing merged, the copy destroyed",
      (rc, [words(c, 3) for c in has(calls, "upgrade-label.py") if "--heads" not in c],
       [words(c, 3) for c in has(calls, "upgrade-notice.sh") if "open" not in c], has(calls, "vagrant")),
      (1, ["upgrade-label.py istio upgrade-blocked"], ["upgrade-notice.sh blocked istio"], ["vagrant destroy -f"]))
rc, calls = night("prove istio minor", heads=(H1, H2))
check("the heads moved during the proof (a push after it was read): blocked, nothing merged, nothing reviewed",
      (rc, has(calls, "upgrade-label.py istio --merge"), has(calls, "claude"), [words(c, 3) for c in has(calls, "upgrade-notice.sh") if "open" not in c]),
      (1, [], [], ["upgrade-notice.sh blocked istio"]))
rc, calls = night("prove istio minor", files={"heads.fail": ""})
check("the heads not read: nothing proven or merged", (rc, has(calls, "task"), has(calls, "upgrade-label.py istio --merge")), (1, [], []))
rc, calls = night("prove istio minor", verdict="VERDICT: CRITICAL a bad thing")
check("a Critical review: blocked, nothing merged", (rc, has(calls, "upgrade-label.py istio --merge"), has(calls, "upgrade-label.py istio upgrade-blocked")),
      (1, [], ["upgrade-label.py istio upgrade-blocked"]))
rc, calls = night("prove istio minor", proofs=(1, 0), verdict="VERDICT: CRITICAL still bad", files={"fix.out": "VERDICT: CLEAN\n"})
check("a CLEAN another step printed into the run's log is not the review's verdict: blocked",
      (rc, has(calls, "upgrade-label.py istio --merge")), (1, []))
rc, calls = night("prove istio minor", verdict="(the agent printed no verdict)")
check("no verdict at all: blocked", (rc, has(calls, "upgrade-label.py istio --merge")), (1, []))
rc, calls = night("notice kafka-5.x major")
check("a major's first run: proven, reviewed, its notice comment and mail - nothing merged",
      (rc, [words(c, 4) for c in has(calls, "upgrade-label.py") if "--heads" not in c],
       [words(c, 3) for c in has(calls, "upgrade-notice.sh") if "open" not in c], has(calls, "upgrade-label.py kafka-5.x --merge")),
      (0, ["upgrade-label.py kafka-5.x --comment UPGRADE"], ["upgrade-notice.sh veto kafka-5.x"], []))
rc, calls = night("apply postgresql-19.x major", plan="test:copy:change INFRA_REF=renovate/postgresql-19.x PLATFORM_REF=main\n")
check("a one-way unit with no backup path: blocked, never merged",
      (rc, has(calls, "upgrade-label.py postgresql-19.x --merge"), has(calls, "upgrade-label.py postgresql-19.x upgrade-blocked")),
      (1, [], ["upgrade-label.py postgresql-19.x upgrade-blocked"]))
rc, calls = night("prove data-operators minor", files={"list": "data-operators minor schnappy/infra one-way,upgrade-cycle\n"})
check("a unit labelled one-way: blocked, never merged, whatever its name",
      (rc, has(calls, "upgrade-label.py data-operators --merge")), (1, []))
for unit, kind in (("scylladb-2026.3", "minor"), ("postgres-18.x", "major"), ("grafana-grafana-13.x", "major")):
    rc, calls = night(f"prove {unit} {kind}", files={"list": f"{unit} {kind} schnappy/infra upgrade-cycle\n"})
    check(f"{unit}, its label missing: the names' net blocks it", (rc, has(calls, f"upgrade-label.py {unit} --merge")), (1, []))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"plan.fail": ""})
check("the unit's plan not read: blocked, no backup, nothing merged (an empty plan merged and paged before)",
      (rc, has(calls, "task --yes"), has(calls, "upgrade-label.py wave-patches --merge"),
       [words(c, 3) for c in has(calls, "upgrade-notice.sh") if "open" not in c]),
      (1, [], [], ["upgrade-notice.sh blocked wave-patches"]))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"etcd.rc": "1"})
check("the etcd backup before Kubernetes failing: blocked, nothing merged, kubeadm never run",
      (rc, has(calls, "upgrade-label.py wave-patches --merge"), has(calls, "task --yes deploy:kubeadm"),
       [words(c, 3) for c in has(calls, "upgrade-notice.sh") if "open" not in c]),
      (1, [], [], ["upgrade-notice.sh blocked wave-patches"]))
rc, calls = night("prove wave-patches patch", plan=PLAN, hm=["20:00", "03:00", "04:10"])
check("a backup window when the apply comes (the proof took its time): waited out, then merged",
      (rc, len(has(calls, "sleep 300")), len(has(calls, "upgrade-label.py wave-patches --merge"))), (0, 1, 1))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"merge.rc": "1"})
check("a failed merge: no production task, reported", (rc, has(calls, "task --yes deploy:kubeadm"),
      [words(c, 3) for c in has(calls, "upgrade-notice.sh") if "open" not in c]), (1, [], ["upgrade-notice.sh blocked wave-patches"]))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"pull.rc": "1"})
check("merged, ops not pulled: paged, no production task (its stale vars never applied)",
      (rc, has(calls, "task --yes deploy:kubeadm"), [words(c, 3) for c in has(calls, "upgrade-notice.sh") if "open" not in c]),
      (1, [], ["upgrade-notice.sh one-way-failed wave-patches"]))
rc, calls = night("prove wave-patches patch", plan="test:copy:playbook PLAYBOOK=setup-mystery.yml ARGS=''\n")
check("an ops part with no production task: paged as one-way",
      (rc, [words(c, 3) for c in has(calls, "upgrade-notice.sh") if "open" not in c]), (1, ["upgrade-notice.sh one-way-failed wave-patches"]))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"verify.rc": "1"})
check("verify red: paged as one-way, not recorded as applied",
      (rc, [words(c, 3) for c in has(calls, "upgrade-notice.sh") if "open" not in c], has(calls, "upgrade-record")),
      (1, ["upgrade-notice.sh one-way-failed wave-patches"], []))
rc, calls = night("prove argocd minor", plan="test:copy:playbook PLAYBOOK=setup-argocd.yml ARGS='-e @vars/vault-vagrant.yml' RESTARTS_EXPECTED=true\n")
check("an Argo CD unit: merged, then production's deploy:argocd (no etcd backup)", (rc, has(calls, "task --yes")), (0, ["task --yes deploy:argocd"]))
# ── a test environment's unit ─────────────────────────────────────────────────────────────────────────────────────────
rc, calls = night("test test-observability minor")
seq = [norm(c) for c in calls if not c.startswith(("upgrade-units.py", "git -C", "upgrade-notice.sh open"))]
check("a test unit: one-way judged, its heads read, merged at them, verified, recorded, reported - no copy, no agent",
      (rc, seq, open(os.path.join(ST, "merged.expect")).read()),
      (0, ["upgrade-label.py test-observability --heads", "upgrade-label.py test-observability --merge", "upgrade-verify.sh",
           "upgrade-record.sh test-observability", "upgrade-notice.sh applied test-observability"], H1))
rc, calls = night("test test-scylladb-2026.3 minor", files={"list": "test-scylladb-2026.3 minor schnappy/infra one-way\n"})
check("a test unit labelled one-way: blocked, never merged", (rc, has(calls, "upgrade-label.py test-scylladb-2026.3 --merge")), (1, []))
rc, calls = night("test test-observability minor", files={"verify.rc": "1"})
check("a test unit not settled after its merge: reported blocked (not paged), not recorded",
      (rc, [words(c, 3) for c in has(calls, "upgrade-notice.sh") if "open" not in c], has(calls, "upgrade-record.sh")),
      (1, ["upgrade-notice.sh blocked test-observability"], []))
rc, calls = night("test observability minor")
check("a test action for a unit with no test- name: refused, nothing done", (rc, has(calls, "upgrade-label.py")), (1, []))
# ── --shadow, refusals ────────────────────────────────────────────────────────────────────────────────────────────────
rc, calls = night("prove wave-patches patch", plan=PLAN, args=("--shadow",))
check("--shadow: proven and reviewed, the result a comment - no notice, no merge, no production task, the copy destroyed",
      (rc, [words(c, 3) for c in has(calls, "upgrade-label.py") if "--heads" not in c],
       [c for c in has(calls, "upgrade-notice.sh") if "open" not in c], has(calls, "task --yes"), has(calls, "vagrant")),
      (0, ["upgrade-label.py wave-patches --comment"], [], [], ["vagrant destroy -f"]))
r = subprocess.run(["bash", os.path.join(OPS, "scripts/upgrade-cycle.sh"), "--apply-all"], capture_output=True, text=True)
check("an option it does not take: refused", r.returncode, 2)
rc, calls = night("prove Bad/Unit patch")
check("a pick it cannot read: refused, nothing built", (rc, has(calls, "task")), (1, []))
rc, calls = night("", files={"pick.rc": "1"})
check("Forgejo not read: the run changes nothing", (rc, has(calls, "task")), (1, []))
print("upgrade-cycle: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
