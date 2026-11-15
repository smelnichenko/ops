#!/bin/bash
# scripts/upgrade-cycle.sh - the upgrade cycle's run - in a throwaway ops directory, every helper and tool stubbed (the
# pick, the labels, the notices, verify, record, copy-main-current; task, the agent, ssh, vagrant, git), each call
# recorded:
#   the gates (before anything, and again before the merge): a backup window within the run's span, an open page
#   (posted again), a run stopped mid-apply (its journal), ops not on main / changed (but for the copy's inventory) /
#   not origin's, the local mains stale, production's Alertmanager not routing the notices, production not settled -
#   each refuses; the copy's memory for a unit that builds it (a test unit needs none); one apply a day; --preflight
#   a patch unit: proven, reviewed (CLEAN and its passes), the copy destroyed, its commands mapped, held read again,
#   merged at the proven heads, ops fetched and fast-forwarded, an etcd snapshot right before Kubernetes, verified,
#   recorded, the journal gone; red: the agent's fix (commits only, sandboxed, --restricted) checked and pushed by the
#   runner; a copy that does not build: no agent, no label; a part with no production command: refused before the
#   merge; a partial merge, a failed command, a stop after the merge: paged and paused; --dry runs nothing; one run at
#   a time
set -u
cd "$(dirname "$0")/../../../.." || exit 1
REAL=$PWD
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
python3 - "$REAL" "$W" <<'PYCHECK'
import os, shutil, signal, subprocess, sys, time
REAL, W = sys.argv[1], sys.argv[2]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
OPS = os.path.join(W, "ops"); BIN = os.path.join(W, "bin"); ST = os.path.join(W, "state"); WORK = os.path.join(W, "work")
for d in (os.path.join(OPS, "scripts"), BIN, ST):
    os.makedirs(d, exist_ok=True)
shutil.copy(os.path.join(REAL, "scripts/upgrade-cycle.sh"), os.path.join(OPS, "scripts"))
def stub(path, body):
    # the state and work directories written in whole: the agents run with env -i, no ST of theirs
    open(path, "w").write("#!/bin/bash\nST=" + ST + "\nWORK=" + WORK + "\n" + body + "\n")
    os.chmod(path, 0o755)
LOG = 'echo "$(basename "$0") $*" >> "$ST/calls"'
stub(os.path.join(OPS, "scripts/upgrade-units.py"), LOG + '''
case "$1" in
  list) [ ! -e "$ST/list.fail" ] || exit 1
    if [ -e "$ST/list" ]; then cat "$ST/list"; else read -r _ u k < "$ST/pick"; echo "$u $k schnappy/infra upgrade-cycle"; fi ;;
  held) [ ! -e "$ST/held.fail" ] || exit 1; cat "$ST/held" 2>/dev/null; exit 0 ;;
  *) cat "$ST/pick"; exit "$(cat "$ST/pick.rc" 2>/dev/null || echo 0)" ;;
esac''')
stub(os.path.join(OPS, "scripts/upgrade-label.py"), LOG + '''
case "$2" in
  --heads) [ ! -e "$ST/heads.fail" ] || exit 1
    n=$(cat "$ST/heads.n" 2>/dev/null || echo 0); f="$ST/heads.$n"; [ -e "$f" ] || f="$ST/heads.last"
    [ ! -e "$ST/heads.override" ] || f="$ST/heads.override"
    cat "$f"; [ -e "$ST/heads.$((n + 1))" ] && echo $((n + 1)) > "$ST/heads.n"; exit 0 ;;
  --merge) cp "$4" "$ST/merged.expect"; exit "$(cat "$ST/merge.rc" 2>/dev/null || echo 0)" ;;
esac''')
stub(os.path.join(OPS, "scripts/upgrade-notice.sh"), LOG + '''
[ "$1" != open ] || { cat "$ST/open" 2>/dev/null; exit 0; }
exit "$(cat "$ST/notice.$1.rc" 2>/dev/null || echo 0)"''')
# verify: the health look (settle 0, hold 0) and the verify after an apply apart
stub(os.path.join(OPS, "scripts/upgrade-verify.sh"), LOG + '''
if [ "${UPGRADE_VERIFY_HOLD:-}" = 0 ]; then exit "$(cat "$ST/health.rc" 2>/dev/null || echo 0)"; fi
echo "upgrade-verify.sh AFTER" >> "$ST/calls"
exit "$(cat "$ST/verify.rc" 2>/dev/null || echo 0)"''')
stub(os.path.join(OPS, "scripts/upgrade-record.sh"), LOG + '\nexit "$(cat "$ST/record.rc" 2>/dev/null || echo 0)"')
stub(os.path.join(OPS, "scripts/copy-main-current.sh"), LOG + '\nexit "$(cat "$ST/mains.rc" 2>/dev/null || echo 0)"')
# task: the build's and the unit proof's verdicts from files (the proof's a list: one per try), the plan, the
# production commands' (one may wait to be stopped)
stub(os.path.join(BIN, "task"), LOG + '''
case "$*" in
  *PLAN=true*) [ ! -e "$ST/plan.fail" ] || { cat "$ST/plan"; exit 1; }; cat "$ST/plan" ;;
  test:copy:build) exit "$(cat "$ST/build.rc" 2>/dev/null || echo 0)" ;;
  test:copy:unit*) n=$(head -1 "$ST/proofs"); sed -i 1d "$ST/proofs"; exit "${n:-0}" ;;
  "--yes "*) [ ! -e "$ST/slow" ] || { touch "$ST/slow.started"; for _ in $(seq 50); do sleep 0.1; done; }
    c="${2//:/_}"; exit "$(cat "$ST/task.$c.rc" 2>/dev/null || echo 0)" ;;
esac''')
# the agent: its environment's names, its directory and its arguments kept per call; the fix "commits" (fix.heads)
stub(os.path.join(BIN, "claude"), LOG + '''
n=$(ls "$ST"/agent.* 2>/dev/null | wc -l)
{ echo "pwd=$PWD"; env | cut -d= -f1 | sort | tr '\\n' ' '; echo; printf '%s\\n' "$@"; } > "$ST/agent.$n"
case "$*" in
  *review*) cat "$ST/verdict"; exit "$(cat "$ST/review.rc" 2>/dev/null || echo 0)" ;;
  *upgrade-fix*) [ -e "$PWD/proof.log" ] && touch "$ST/fix.saw-log"; [ ! -e "$ST/fix.heads" ] || touch "$ST/fixed" ;;
esac''')
# git: ops on main, clean, origin's - as the state files say; a clone made (its repo's proven head, or the fix's);
# the fix's checks and its push
stub(os.path.join(BIN, "git"), LOG + '''
args="$*"
dir=""; [ "$1" != -C ] || dir=$2
case "$args" in
  *" clone "*) mkdir -p "${@: -1}" ;;
  *"rev-parse --abbrev-ref HEAD"*) cat "$ST/branch" 2>/dev/null || echo main ;;
  *"status --porcelain"*) cat "$ST/dirty" 2>/dev/null ;;
  *"fetch -q origin main"*) exit "$(cat "$ST/fetch.rc" 2>/dev/null || echo 0)" ;;
  *"rev-parse origin/main"*) cat "$ST/origin" 2>/dev/null || echo 1111111111111111111111111111111111111111 ;;
  *"rev-parse HEAD"*)
    case "$dir" in
      "$WORK"/*/infra) if [ -e "$ST/fixed" ]; then echo bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; else echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; fi ;;
      "$WORK"/*/ops) echo cccccccccccccccccccccccccccccccccccccccc ;;
      *) echo 1111111111111111111111111111111111111111 ;;
    esac ;;
  *"symbolic-ref --short HEAD"*) cat "$ST/onbranch" 2>/dev/null || { read -r _ u _ < "$ST/pick"; echo "renovate/$u"; } ;;
  *"merge-base --is-ancestor"*) exit "$(cat "$ST/ancestor.rc" 2>/dev/null || echo 0)" ;;
  *" push "*) [ ! -e "$ST/fix.heads" ] || cp "$ST/fix.heads" "$ST/heads.override"; exit "$(cat "$ST/push.rc" 2>/dev/null || echo 0)" ;;
  *"merge -q --ff-only origin/main"*) exit "$(cat "$ST/ff.rc" 2>/dev/null || echo 0)" ;;
esac''')
# ssh: production's Alertmanager routing the cycle's notices (the probe), else nothing
stub(os.path.join(BIN, "ssh"), LOG + '''
case "$*" in *"amtool config routes test"*) cat "$ST/am" 2>/dev/null || echo email-notice ;; esac''')
stub(os.path.join(BIN, "vagrant"), LOG)
H1 = "schnappy/infra 4 " + "a" * 40 + " " + "e" * 40 + "\nschnappy/ops 7 " + "c" * 40 + " " + "e" * 40 + "\n"
H2 = "schnappy/infra 4 " + "b" * 40 + " " + "e" * 40 + "\nschnappy/ops 7 " + "c" * 40 + " " + "e" * 40 + "\n"
CLEAN = "PASSES: code-review, security, architecture, test-quality\nVERDICT: CLEAN"
def setup(pick, proofs=(0,), plan="test:copy:change INFRA_REF=renovate/x PLATFORM_REF=main\n", verdict=CLEAN, mem=30000,
          files=None, heads=(H1,), records=(), inflight=False):
    for f in os.listdir(ST):
        os.remove(os.path.join(ST, f))
    for d in (".copy", "docs", ".upgrade-cycle"):
        shutil.rmtree(os.path.join(OPS, d), ignore_errors=True)  # each run's logs, records, state its own
    shutil.rmtree(WORK, ignore_errors=True)
    for r in records:
        os.makedirs(os.path.join(OPS, "docs/upgrades"), exist_ok=True)
        open(os.path.join(OPS, "docs/upgrades", r), "w").write("x\n")
    if inflight:
        os.makedirs(os.path.join(OPS, ".upgrade-cycle"), exist_ok=True)
        open(os.path.join(OPS, ".upgrade-cycle/inflight"), "w").write("unit wave-patches\n")
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
def environ(hm, dow, env=None):
    e = {**os.environ, "PATH": BIN + ":" + os.environ["PATH"], "ST": ST, "UPGRADE_NOW_DOW": dow, "UPGRADE_WORK": WORK,
         "UPGRADE_MEMINFO": os.path.join(ST, "meminfo"), "UPGRADE_TODAY": "2026-11-20",
         "ANTHROPIC_API_KEY": "sk-the-apps-key", "RENOVATE_TOKEN": "bot-token", "VAULT_ROOT_TOKEN": "root",
         "UPGRADE_FORGEJO_TOKEN": "bot-token"}
    if isinstance(hm, list):
        open(os.path.join(ST, "hm"), "w").write("".join(f"{x}\n" for x in hm))
        e["UPGRADE_NOW_HM_FILE"] = os.path.join(ST, "hm")
    else:
        e["UPGRADE_NOW_HM"] = hm
    e.update(env or {})
    return e
def calls_now():
    p = os.path.join(ST, "calls")
    return open(p).read().splitlines() if os.path.exists(p) else []
def night(pick, hm="20:00", dow="3", args=(), **kw):
    setup(pick, **kw)
    r = subprocess.run(["bash", os.path.join(OPS, "scripts/upgrade-cycle.sh"), *args], capture_output=True, text=True,
                       env=environ(hm, dow), timeout=120)
    return r.returncode, calls_now()
def has(calls, prefix):
    return [c for c in calls if c.startswith(prefix)]
def words(c, n):
    return " ".join(c.split(" ")[:n]).strip()
def picked(calls):
    return bool(has(calls, "upgrade-units.py pick"))
def notices(calls):
    return [words(c, 3) for c in has(calls, "upgrade-notice.sh") if not c.startswith(("upgrade-notice.sh open", "upgrade-notice.sh repost"))]
def merged(calls, unit):
    return bool(has(calls, f"upgrade-label.py {unit} --merge"))
def paused(calls):
    return bool(has(calls, "upgrade-label.py --pause"))
def pushes(calls):
    return [c.split()[-1] for c in calls if c.startswith("git ") and " push " in c]
def flag(args, name):  # the value after a flag, or None (never a crash: the flag missing is a finding)
    return args[args.index(name) + 1] if name in args else None
def agents():
    out = []
    for f in sorted(x for x in os.listdir(ST) if x.startswith("agent.")):
        lines = open(os.path.join(ST, f)).read().split("\n")
        out.append({"pwd": lines[0][4:], "env": lines[1].split(), "args": [x for x in lines[2:] if x]})
    return out
def inflight():
    return os.path.exists(os.path.join(OPS, ".upgrade-cycle/inflight"))
# ── the gates ─────────────────────────────────────────────────────────────────────────────────────────────────────────
for hm, dow, why in (("03:00", "3", "in Velero's, the Pis' and ScyllaDB's"), ("00:55", "3", "the mirror's summer hour"),
                     ("01:35", "3", "CNPG's base backup"), ("05:30", "3", "the Pis' restore check"),
                     ("04:30", "7", "Sunday's ScyllaDB repair"), ("21:30", "3", "00:50 within the run's 4 h"),
                     ("04:30", "3", "the restore check within the run's 4 h")):
    rc, calls = night("prove wave-patches patch", hm=hm, dow=dow)
    check(f"a backup window ({hm}, day {dow}: {why}): refused at once, nothing asked", (rc, calls), (1, []))
rc, calls = night("prove wave-patches patch", hm="20:30", dow="3")
check("20:30: the next window 4 h 20 min away - on", (rc, picked(calls)), (0, True))
rc, calls = night("prove wave-patches patch", hm="06:00", dow="3")
check("06:00: the day's windows behind it - on", (rc, picked(calls)), (0, True))
rc, calls = night("prove wave-patches patch", hm="22:00", dow="6")
check("22:00 Saturday: Sunday's 00:50 within the span (over midnight) - refused", (rc, picked(calls)), (1, False))
rc, calls = night("prove wave-patches patch", files={"open": "scylla-2026.3\n"})
check("an open page: posted again (Alertmanager forgets on a restart), refused, nothing picked",
      (rc, has(calls, "upgrade-notice.sh"), picked(calls)), (1, ["upgrade-notice.sh open", "upgrade-notice.sh repost"], False))
rc, calls = night("prove wave-patches patch", inflight=True)
check("a run stopped mid-apply (its journal): refused, nothing picked", (rc, picked(calls)), (1, False))
for files, why in (({"branch": "feat/x\n"}, "ops on another branch"), ({"dirty": " M Taskfile.yml\n"}, "ops with changes"),
                   ({"origin": "2" * 40 + "\n"}, "ops behind or ahead of origin"), ({"fetch.rc": "1"}, "origin not read"),
                   ({"mains.rc": "1"}, "the local infra or platform main stale"),
                   ({"am": "email\n"}, "production's Alertmanager routing notices elsewhere (platform's route not live)"),
                   ({"health.rc": "1"}, "production not settled and quiet")):
    rc, calls = night("prove wave-patches patch", files=files)
    check(f"{why}: refused, nothing picked", (rc, picked(calls)), (1, False))
rc, calls = night("prove wave-patches patch")
check("ops checked clean but for the copy's inventory record (the build rewrites it)",
      [c for c in calls if "status --porcelain" in c][0].split(" -- ")[-1],
      ". :!tests/ansible/copy/prod-inventory.txt :!tests/ansible/copy/pi-versions.yml")
rc, calls = night("prove wave-patches patch", mem=20000)
check("memory short (the radar running), a unit that builds the copy: refused at once - no wait, no build",
      (rc, has(calls, "task"), has(calls, "sleep")), (1, [], []))
rc, calls = night("test test-observability minor", mem=20000)
check("memory short, a test unit (no copy): on", (rc, merged(calls, "test-observability")), (0, True))
rc, calls = night("prove wave-patches patch", records=("2026-11-20-istio.md",))
check("a production apply recorded today: refused (one a day), nothing picked", (rc, picked(calls)), (1, False))
rc, calls = night("prove wave-patches patch", records=("2026-11-19-istio.md",))
check("one recorded yesterday: on", (rc, picked(calls)), (0, True))
rc, calls = night("prove wave-patches patch", args=("--preflight",))
check("--preflight, the gates passing: exit 0, nothing picked or built", (rc, picked(calls), has(calls, "task")), (0, False, []))
for files, mem, why in (({}, 20000, "memory"), ({"am": "email\n"}, 30000, "Alertmanager")):
    rc, calls = night("prove wave-patches patch", args=("--preflight",), mem=mem, files=files)
    check(f"--preflight, a gate refusing ({why}): exit 1", rc, 1)
for p in ("NOTHING", "PAUSED"):
    rc, calls = night(p)
    check(f"{p}: the pick alone, nothing built or destroyed", (rc, has(calls, "task"), has(calls, "vagrant")), (0, [], []))
# ── a unit, proven and applied ────────────────────────────────────────────────────────────────────────────────────────
PLAN = ("test:copy:change INFRA_REF=renovate/wave-patches PLATFORM_REF=main\n"
        "test:copy:playbook PLAYBOOK=upgrade-kubeadm.yml ARGS='-e k8s_upgrade_to=1.36.7' RESTARTS_EXPECTED=true\n"
        "test:copy:playbook PLAYBOOK=upgrade-forgejo.yml ARGS='-e @/x/forgejo.yml'\n")
rc, calls = night("prove wave-patches patch", plan=PLAN)
KEY = ("task ", "upgrade-label.py", "upgrade-record.sh", "vagrant", "claude", "upgrade-notice.sh applied", "upgrade-verify.sh AFTER")
seq = [words(c, 2 if c.startswith("upgrade-record.sh") else 3) for c in calls if c.startswith(KEY)
       or c.startswith("git -C " + OPS + " merge")]
check("a patch unit: heads, built, proven, heads again, reviewed, the copy destroyed, the plan, held, merged, ops "
      "fast-forwarded, the etcd snapshot, Kubernetes, Forgejo, verified, the inventory read, recorded, reported, the "
      "copy's destroy again on the way out - in that order",
      (rc, seq),
      (0, ["upgrade-label.py wave-patches --heads", "task test:copy:build", "task test:copy:unit UNIT=wave-patches",
           "upgrade-label.py wave-patches --heads", "claude -p upgrade-cycle", "vagrant destroy -f",
           "task test:copy:unit UNIT=wave-patches", "upgrade-label.py wave-patches --merge", "git -C " + OPS,
           "task --yes deploy:etcd:backup", "task --yes deploy:kubeadm:upgrade", "task --yes deploy:forgejo:upgrade",
           "upgrade-verify.sh AFTER", "task test:copy:inventory", "upgrade-record.sh wave-patches",
           "upgrade-notice.sh applied wave-patches", "vagrant destroy -f"]))
check("  merged at the heads proven - head and base each - ops brought by fetch and fast-forward (never a pull); held "
      "read again before the merge",
      (open(os.path.join(ST, "merged.expect")).read(), len(has(calls, "git -C " + OPS + " merge -q --ff-only origin/main")),
       has(calls, "git -C " + OPS + " pull"), len(has(calls, "upgrade-units.py held"))), (H1, 1, [], 1))
check("  the gates read again before the merge (Alertmanager probed twice, production's health looked at twice)",
      (len([c for c in calls if "amtool config routes test" in c]), len(has(calls, "copy-main-current.sh"))), (2, 2))
check("  the review's clones as the bot (its token by a helper of the call's own), each at its proven head, outside "
      "every checkout, gone after",
      ([c.split()[-2] for c in calls if c.startswith("git -c credential.helper=") and " clone " in c],
       [c.split()[-1] for c in calls if c.startswith("git -C " + WORK) and "checkout -q -B" in c],
       os.listdir(WORK) if os.path.exists(WORK) else []),
      (["https://git.pmon.dev/schnappy/infra.git", "https://git.pmon.dev/schnappy/ops.git"], ["a" * 40, "c" * 40], []))
check("  Kubernetes to the proven version, its etcd snapshot right before it",
      has(calls, "task --yes")[:2],
      ["task --yes deploy:etcd:backup", "task --yes deploy:kubeadm:upgrade -- -e k8s_upgrade_to=1.36.7"])
check("  the journal of the apply gone with its record", inflight(), False)
a = agents()
check("  the review agent: in its clones, none of the task's environment (no API key, no bot token, no Vault token), no "
      "git config or credential, the bot as author, settings of its own (the operator's skipped), anything else denied",
      (len(a), a[0]["pwd"].startswith(os.path.join(WORK, "wave-patches-review-")),
       sorted(set(a[0]["env"]) - {"PWD", "SHLVL", "_", "OLDPWD"}),
       flag(a[0]["args"], "--settings"), flag(a[0]["args"], "--setting-sources"), flag(a[0]["args"], "--permission-mode"),
       flag(a[0]["args"], "--permission-prompts")),
      (1, True, ["GIT_AUTHOR_EMAIL", "GIT_AUTHOR_NAME", "GIT_CEILING_DIRECTORIES", "GIT_COMMITTER_EMAIL", "GIT_COMMITTER_NAME",
                 "GIT_CONFIG_GLOBAL", "GIT_CONFIG_NOSYSTEM", "GIT_TERMINAL_PROMPT", "HOME", "LANG", "PATH"],
       os.path.join(OPS, ".claude/upgrade-agent/review.json"), "project,local", "dontAsk", "none"))
rc, calls = night("prove istio minor", proofs=(1, 0), plan="test:copy:change INFRA_REF=renovate/istio PLATFORM_REF=renovate/istio\n",
                  files={"fix.heads": H2})
a = agents()
check("red, the agent's fix: --restricted (its file tools in its clones), the skill's text, the fix's settings, in "
      "clones of the proven commits beside the proof's log - its commit checked (on the branch, on top of the proven "
      "head) and pushed by the runner as the bot, labelled stop-updating, proven again, merged at the fixed heads",
      (rc, "--restricted" in a[0]["args"], flag(a[0]["args"], "--append-system-prompt-file"), flag(a[0]["args"], "--settings"),
       flag(a[0]["args"], "--permission-mode"), a[0]["pwd"].startswith(os.path.join(WORK, "istio-fix-")),
       os.path.exists(os.path.join(ST, "fix.saw-log")), pushes(calls), has(calls, "upgrade-label.py istio stop-updating"),
       open(os.path.join(ST, "merged.expect")).read()),
      (0, True, os.path.join(OPS, ".claude/skills/upgrade-fix/SKILL.md"), os.path.join(OPS, ".claude/upgrade-agent/fix.json"),
       "dontAsk", True, True, ["HEAD:refs/heads/renovate/istio"], ["upgrade-label.py istio stop-updating"], H2))
check("  the push as the bot (its token through the call's own credential helper)",
      [c.startswith("git -c credential.helper= -c credential.helper=!f()") for c in calls if c.startswith("git") and " push " in c],
      [True])
rc, calls = night("prove istio minor", proofs=(1, 0), plan="test:copy:change INFRA_REF=renovate/istio PLATFORM_REF=renovate/istio\n")
check("a fix that committed nothing: nothing pushed, no stop-updating label",
      (rc, pushes(calls), has(calls, "upgrade-label.py istio stop-updating")), (0, [], []))
for files, why in (({"fix.heads": H2, "onbranch": "main\n"}, "left the unit's branch (a move to main)"),
                   ({"fix.heads": H2, "ancestor.rc": "1"}, "rewrote the proven commit"),
                   ({"fix.heads": H2, "push.rc": "1"}, "the push of which was refused")):
    rc, calls = night("prove istio minor", proofs=(1, 0), files=files)
    check(f"a fix that {why}: blocked, proven no more, nothing merged",
          (rc, merged(calls, "istio"), notices(calls), len(has(calls, "task test:copy:build"))),
          (1, False, ["upgrade-notice.sh blocked istio"], 1))
rc, calls = night("prove istio minor", proofs=(1, 1))
check("red after its fix: labelled upgrade-blocked, reported, nothing merged, the copy destroyed",
      (rc, has(calls, "upgrade-label.py istio upgrade-blocked"), notices(calls), merged(calls, "istio"), len(has(calls, "vagrant"))),
      (1, ["upgrade-label.py istio upgrade-blocked"], ["upgrade-notice.sh blocked istio"], False, 1))
rc, calls = night("prove istio minor", files={"build.rc": "1"})
check("a copy that does not build: the run ends - no agent, no label, no notice blaming the unit",
      (rc, has(calls, "claude"), has(calls, "upgrade-label.py istio upgrade-blocked"), notices(calls)), (1, [], [], []))
rc, calls = night("prove istio minor", heads=(H1, H2))
check("the heads moved during the proof: blocked, nothing reviewed or merged",
      (rc, merged(calls, "istio"), has(calls, "claude"), notices(calls)), (1, False, [], ["upgrade-notice.sh blocked istio"]))
for verdict, files, why in (("VERDICT: CRITICAL a bad thing\nPASSES: x", {}, "a Critical review"),
                            ("VERDICT: CLEAN", {}, "CLEAN with no passes named"),
                            ("PASSES: a\nVERDICT: CLEAN\nVERDICT: CRITICAL later", {}, "a later CRITICAL"),
                            (CLEAN, {"review.rc": "1"}, "the review agent failing")):
    rc, calls = night("prove istio minor", verdict=verdict, files=files)
    check(f"{why}: blocked, nothing merged", (rc, merged(calls, "istio"), has(calls, "upgrade-label.py istio upgrade-blocked")),
          (1, False, ["upgrade-label.py istio upgrade-blocked"]))
rc, calls = night("notice kafka-5.x major", files={"list": "kafka-5.x major schnappy/infra major\n"})
check("a major's first run: proven, reviewed, its notice mailed, then its comment (the clock) - nothing merged",
      (rc, [words(c, 3) for c in calls if c.startswith(("upgrade-notice.sh veto", "upgrade-label.py kafka-5.x --comment"))],
       merged(calls, "kafka-5.x")),
      (1, [], False))
rc, calls = night("notice centrifugo-7.x major")
check("a major's first run: its notice mailed, then its comment (the clock) - nothing merged",
      (rc, [words(c, 3) for c in calls if c.startswith(("upgrade-notice.sh veto", "upgrade-label.py centrifugo-7.x --comment"))],
       merged(calls, "centrifugo-7.x")),
      (0, ["upgrade-notice.sh veto centrifugo-7.x", "upgrade-label.py centrifugo-7.x --comment"], False))
rc, calls = night("notice centrifugo-7.x major", files={"notice.veto.rc": "1"})
check("a veto mail that failed: no comment, no clock started", (rc, has(calls, "upgrade-label.py centrifugo-7.x --comment")), (1, []))
rc, calls = night("apply postgresql-19.x major")
check("a one-way unit with no backup path: blocked before its proof, never merged",
      (rc, has(calls, "task"), has(calls, "upgrade-label.py postgresql-19.x upgrade-blocked")),
      (1, [], ["upgrade-label.py postgresql-19.x upgrade-blocked"]))
for unit in ("kafka-4.x", "clickhouse-26.x", "strimzi-1.x", "consul-2.x", "vault-2.x", "scylladb-2026.3", "postgres-18.x",
             "grafana-grafana-13.x"):
    rc, calls = night(f"prove {unit} minor", files={"list": f"{unit} minor schnappy/infra upgrade-cycle\n"})
    check(f"{unit}, its label missing: the names' net blocks it", (rc, merged(calls, unit)), (1, False))
rc, calls = night("prove data-operators minor", files={"list": "data-operators minor schnappy/infra one-way,upgrade-cycle\n"})
check("a unit labelled one-way: blocked, never merged", (rc, merged(calls, "data-operators")), (1, False))
rc, calls = night("prove centrifugo-6.x minor", files={"list": "centrifugo-6.x minor schnappy/infra not-one-way,upgrade-cycle\n"})
check("a label only containing the word (not-one-way) is not one-way: merged", (rc, merged(calls, "centrifugo-6.x")), (0, True))
rc, calls = night("prove wave-patches patch", files={"list.fail": ""})
check("the labels not read: nothing built or merged (fails closed)", (rc, has(calls, "task"), merged(calls, "wave-patches")),
      (1, [], False))
rc, calls = night("prove wave-patches patch", files={"list": "other-1.x minor schnappy/infra upgrade-cycle\n"})
check("the unit gone from the open ones since its pick: nothing built or merged", (rc, has(calls, "task"), merged(calls, "wave-patches")),
      (1, [], False))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"plan.fail": ""})
check("the plan's task failing (even printing steps): blocked, nothing merged",
      (rc, merged(calls, "wave-patches"), notices(calls)), (1, False, ["upgrade-notice.sh blocked wave-patches"]))
rc, calls = night("prove wave-patches patch", plan="test:copy:playbook PLAYBOOK=setup-mystery.yml ARGS=''\n")
check("a part with no production command: refused BEFORE the merge - nothing merged, not paged",
      (rc, merged(calls, "wave-patches"), notices(calls)), (1, False, ["upgrade-notice.sh blocked wave-patches"]))
for pb, cmd in (("upgrade-patroni.yml", "deploy:patroni:upgrade"), ("upgrade-vault.yml", "deploy:vault:upgrade"),
                ("setup-host-hardening.yml", "deploy:host-hardening"), ("setup-argocd.yml", "deploy:argocd"),
                ("upgrade-forgejo.yml", "deploy:forgejo:upgrade"),
                ("setup-kubeadm.yml ARGS='-e cilium_version=1.20.5'", "deploy:cilium:upgrade -- -e cilium_version=1.20.5")):
    rc, calls = night("prove centrifugo minor", plan=f"test:copy:playbook PLAYBOOK={pb}\n")
    check(f"{pb.split()[0]} -> task --yes {cmd}", (rc, [c[len("task --yes "):] for c in has(calls, "task --yes")]), (0, [cmd]))
    rc, calls = night("prove centrifugo minor", plan=f"test:copy:playbook PLAYBOOK={pb}\n",
                      files={f"task.{cmd.split()[0].replace(':', '_')}.rc": "1"})
    check("  its failure: paged, the cycle paused, the journal kept", (rc, notices(calls), paused(calls), inflight()),
          (1, ["upgrade-notice.sh one-way-failed centrifugo"], True, True))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"task.deploy_etcd_backup.rc": "1"})
check("the etcd snapshot failing (after the merge): paged, kubeadm never run",
      (rc, has(calls, "task --yes deploy:kubeadm"), notices(calls)), (1, [], ["upgrade-notice.sh one-way-failed wave-patches"]))
rc, calls = night("prove wave-patches patch", plan=PLAN, hm=["20:00", "23:00"])
check("a backup window near when the apply comes (the proof took its time): proven and reviewed, not applied - "
      "nothing merged, reported", (rc, merged(calls, "wave-patches"), notices(calls)),
      (1, False, ["upgrade-notice.sh blocked wave-patches"]))
for files, why in (({"held": "veto\n"}, "a veto set since the pick"), ({"held": "paused\n"}, "the kill switch set since"),
                   ({"held.fail": ""}, "held not read")):
    rc, calls = night("prove wave-patches patch", plan=PLAN, files=files)
    check(f"{why}: nothing merged, reported", (rc, merged(calls, "wave-patches"), notices(calls)),
          (1, False, ["upgrade-notice.sh blocked wave-patches"]))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"merge.rc": "1"})
check("a merge refused whole: blocked (not paged), no command", (rc, has(calls, "task --yes"), notices(calls), paused(calls)),
      (1, [], ["upgrade-notice.sh blocked wave-patches"], False))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"merge.rc": "3"})
check("a partial merge (exit 3): paged, the cycle paused, no command, the journal kept",
      (rc, has(calls, "task --yes"), notices(calls), paused(calls), inflight()),
      (1, [], ["upgrade-notice.sh one-way-failed wave-patches"], True, True))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"ff.rc": "1"})
check("merged, ops not fast-forwarded: paged, no command", (rc, has(calls, "task --yes"), notices(calls)),
      (1, [], ["upgrade-notice.sh one-way-failed wave-patches"]))
rc, calls = night("prove centrifugo minor")
check("a unit with no ops part: ops not fast-forwarded for it", (rc, has(calls, "git -C " + OPS + " merge")), (0, []))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"verify.rc": "1"})
check("verify red: paged, paused, not recorded", (rc, notices(calls), paused(calls), has(calls, "upgrade-record")),
      (1, ["upgrade-notice.sh one-way-failed wave-patches"], True, []))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"record.rc": "1"})
check("applied and verified, not recorded: reported, the journal kept (the next run refuses until it is pushed)",
      (rc, notices(calls)[-1:], inflight()), (1, ["upgrade-notice.sh blocked wave-patches"], True))
# a stop after the merge (the terminal closed): paged, never silent
setup("prove wave-patches patch", plan=PLAN, files={"slow": ""})
p = subprocess.Popen(["bash", os.path.join(OPS, "scripts/upgrade-cycle.sh")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     env=environ("20:00", "3"))
for _ in range(400):
    if os.path.exists(os.path.join(ST, "slow.started")):
        break
    time.sleep(0.05)
p.send_signal(signal.SIGTERM)
p.wait(timeout=60)
calls = calls_now()
check("stopped (SIGTERM) during a production command after the merge: paged and paused",
      (p.returncode, notices(calls), paused(calls)), (1, ["upgrade-notice.sh one-way-failed wave-patches"], True))
rc, calls = night("prove wave-patches patch", plan=PLAN, args=("--dry",))
check("--dry: every step said, nothing run - no build, agent, merge, push or production command",
      (rc, [c for c in calls if c.startswith(("task", "claude", "vagrant")) or " --merge" in c or " push " in c]), (0, []))
# ── a test environment's unit ─────────────────────────────────────────────────────────────────────────────────────────
rc, calls = night("test test-observability minor")
check("a test unit: one-way judged, held read, its heads read, merged at them, verified - no copy, no agent",
      (rc, [words(c, 3) for c in calls if c.startswith(("upgrade-label.py", "upgrade-units.py held", "claude", "vagrant", "task"))],
       open(os.path.join(ST, "merged.expect")).read()),
      (0, ["upgrade-units.py held test-observability", "upgrade-label.py test-observability --heads",
           "upgrade-label.py test-observability --merge"], H1))
check("  recorded and reported", (bool(has(calls, "upgrade-record.sh test-observability")), notices(calls)),
      (True, ["upgrade-notice.sh applied test-observability"]))
rc, calls = night("test test-observability minor", files={"verify.rc": "1"})
check("a test unit not settled after its merge: its production twin held (upgrade-blocked), reported, not recorded",
      (rc, has(calls, "upgrade-label.py observability upgrade-blocked"), notices(calls), has(calls, "upgrade-record.sh")),
      (1, ["upgrade-label.py observability upgrade-blocked"], ["upgrade-notice.sh blocked test-observability"], []))
rc, calls = night("test test-observability minor", files={"merge.rc": "1"})
check("a test unit's merge refused: blocked, not verified or recorded",
      (rc, has(calls, "upgrade-verify.sh AFTER"), has(calls, "upgrade-record.sh"), notices(calls)),
      (1, [], [], ["upgrade-notice.sh blocked test-observability"]))
rc, calls = night("test test-observability minor", files={"merge.rc": "3"})
check("a test unit partly merged: paged, paused", (rc, notices(calls), paused(calls)),
      (1, ["upgrade-notice.sh one-way-failed test-observability"], True))
rc, calls = night("test test-scylladb-2026.3 minor", files={"list": "test-scylladb-2026.3 minor schnappy/infra one-way\n"})
check("a test unit labelled one-way: blocked, never merged", (rc, merged(calls, "test-scylladb-2026.3")), (1, False))
rc, calls = night("test observability minor")
check("a test action for a unit with no test- name: refused, nothing done", (rc, has(calls, "upgrade-label.py")), (1, []))
# ── --shadow, refusals, the lock ──────────────────────────────────────────────────────────────────────────────────────
rc, calls = night("prove wave-patches patch", plan=PLAN, args=("--shadow",))
check("--shadow: proven and reviewed, the result a comment - no notice, no merge, no production command, the copy destroyed",
      (rc, [words(c, 3) for c in has(calls, "upgrade-label.py") if "--heads" not in c], notices(calls), has(calls, "task --yes"),
       bool(has(calls, "vagrant destroy"))), (0, ["upgrade-label.py wave-patches --comment"], [], [], True))
r = subprocess.run(["bash", os.path.join(OPS, "scripts/upgrade-cycle.sh"), "--apply-all"], capture_output=True, text=True)
check("an option it does not take: refused", r.returncode, 2)
for pick in ("prove Bad/Unit patch", "prove istio huge", "explode istio minor"):
    rc, calls = night(pick)
    check(f"a pick it cannot read ({pick}): refused, nothing built", (rc, has(calls, "task")), (1, []))
rc, calls = night("", files={"pick.rc": "1"})
check("Forgejo not read: the run changes nothing", (rc, has(calls, "task")), (1, []))
setup("prove wave-patches patch", plan=PLAN)
os.makedirs(os.path.join(OPS, ".upgrade-cycle"), exist_ok=True)
holder = subprocess.Popen(["flock", os.path.join(OPS, ".upgrade-cycle/lock"), "sleep", "5"])
time.sleep(0.3)
r = subprocess.run(["bash", os.path.join(OPS, "scripts/upgrade-cycle.sh")], capture_output=True, text=True, env=environ("20:00", "3"))
holder.kill()
holder.wait()
check("a second run while one holds the lock: refused, nothing read", (r.returncode, "another upgrade run" in r.stdout, calls_now()),
      (1, True, []))
print("upgrade-cycle: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
