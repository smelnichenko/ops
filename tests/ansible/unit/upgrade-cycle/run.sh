#!/bin/bash
# scripts/upgrade-cycle.sh - the upgrade cycle's run - in a throwaway ops directory, every helper and tool stubbed (the
# pick, the labels, the notices, verify, record, copy-main-current; task, the agent, ssh, vagrant, git), each call
# recorded:
#   the gates (before anything, and again before the merge): an open page (posted again), a run stopped
#   mid-apply (its journal - paged now), ops not on main / changed (but for the copy's inventory) / not origin's, the
#   local mains stale (at the start alone), production's Alertmanager not routing the notices (its loaded config),
#   production not settled - each refuses; the copy's memory for a unit
#   that builds it; one apply a day; --preflight
#   a patch unit: its CI green, proven, reviewed (CLEAN and every pass, --restricted, the reviewers handed over), the
#   copy halted (its snapshot kept), its commands mapped (a version that is none refused), the etcd snapshot BEFORE the merge, held read
#   again, merged at the proven heads, ops fetched and fast-forwarded (always), Argo settled on the merge's commits
#   before the commands, verified on them, recorded, the journal gone
#   red: the agent's fix (commits only, sandboxed, --restricted, the checksum script the runner's) fetched into a
#   repository of the runner's, kept inside the unit's own files, pushed to Forgejo's URL as the bot, labelled
#   stop-updating and agent-fixed, read until Forgejo shows it, proven again, reviewed - then applied in that run (no
#   notice: operator 2026-11-21), a major or one-way unit too; the review handed Renovate's pull request bodies and the
#   repos the unit does not touch, its compatibility pass required; no fix: blocked (labelled on the agent's NO FIX
#   alone), no rebuild
#   a refused merge: the journal gone; a partial one, a failed command, a stop after (or during) the merge: paged and
#   paused; a stop before it: nothing; a closed terminal after the journal: nothing stops; --dry runs and writes
#   nothing; one run at a time; no step holds the run's lock
set -u
cd "$(dirname "$0")/../../../.." || exit 1
REAL=$PWD
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
python3 - "$REAL" "$W" <<'PYCHECK'
import json, os, re, shutil, signal, subprocess, sys, time
REAL, W = sys.argv[1], sys.argv[2]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
OPS = os.path.join(W, "ops"); BIN = os.path.join(W, "bin"); ST = os.path.join(W, "state"); WORK = os.path.join(W, "work")
for d in (os.path.join(OPS, "scripts"), BIN, ST, os.path.join(OPS, ".claude/agents")):
    os.makedirs(d, exist_ok=True)
for f in ("upgrade-cycle.sh", "upgrade-stores.py", "upgrade-stores.json", "upgrade-fix-judge.py"):  # the runner, what one-way stores need, the fix's judge
    shutil.copy(os.path.join(REAL, "scripts", f), os.path.join(OPS, "scripts"))
for name in ("code-architecture-reviewer", "platform-reliability-reviewer", "test-quality-reviewer"):
    shutil.copy(os.path.join(REAL, ".claude/agents", name + ".md"), os.path.join(OPS, ".claude/agents"))
# what the fix agent is handed as the runner's own: ops main's checksum script and keys
open(os.path.join(OPS, "scripts/renovate-checksums.py"), "w").write("# the runner's copy\n")
os.makedirs(os.path.join(OPS, "renovate/keys"), exist_ok=True)
open(os.path.join(OPS, "renovate/keys/keys.json"), "w").write("{}\n")
def stub(path, body):
    # the state and work directories written in whole: the agents run with env -i, no ST of theirs
    open(path, "w").write("#!/bin/bash\nST=" + ST + "\nWORK=" + WORK + "\n" + body + "\n")
    os.chmod(path, 0o755)
# every stub says whether it was handed the run's lock (fd 9): no step may hold it
LOG = 'echo "$(basename "$0") $*" >> "$ST/calls"; [ ! -e /proc/$$/fd/9 ] || echo "$(basename "$0") $*" >> "$ST/fd9"'
stub(os.path.join(OPS, "scripts/upgrade-units.py"), LOG + '''
case "$1" in
  list) [ ! -e "$ST/list.fail" ] || exit 1
    n=$(( $(cat "$ST/list.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$ST/list.n"  # list.later: from the second read on
    if [ "$n" -gt 1 ] && [ -e "$ST/list.later" ]; then cat "$ST/list.later"
    elif [ -e "$ST/list" ]; then cat "$ST/list"; else read -r _ u k < "$ST/pick"; echo "$u $k schnappy/infra upgrade-cycle"; fi ;;
  held) [ ! -e "$ST/held.fail" ] || exit 1; cat "$ST/held" 2>/dev/null; exit 0 ;;
  bodies) [ ! -e "$ST/bodies.rc" ] || exit "$(cat "$ST/bodies.rc")"; echo "| x | 1 -> 2 |" > "$3/infra.pr.md"; echo "$3/infra.pr.md" ;;
  moves) [ ! -e "$ST/moves.rc" ] || exit "$(cat "$ST/moves.rc")"; cat "$ST/moves" 2> /dev/null || echo "x 1 2" ;;
  *) cat "$ST/pick"; exit "$(cat "$ST/pick.rc" 2>/dev/null || echo 0)" ;;
esac''')
stub(os.path.join(OPS, "scripts/upgrade-label.py"), LOG + '''
case "$2" in
  --heads) [ ! -e "$ST/heads.fail" ] || exit 1
    n=$(cat "$ST/heads.n" 2>/dev/null || echo 0); f="$ST/heads.$n"; [ -e "$f" ] || f="$ST/heads.last"
    [ ! -e "$ST/heads.override" ] || f="$ST/heads.override"
    cat "$f"; [ -e "$ST/heads.$((n + 1))" ] && echo $((n + 1)) > "$ST/heads.n"; exit 0 ;;
  --green) exit "$(cat "$ST/green.rc" 2>/dev/null || echo 0)" ;;
  --update) exit "$(cat "$ST/update.rc" 2>/dev/null || echo 0)" ;;
  --merge) cp "$4" "$ST/merged.expect"; echo "MERGED schnappy/infra#4"
    [ ! -e "$ST/slowmerge" ] || { touch "$ST/slowmerge.started"; for _ in $(seq 50); do sleep 0.1; done; }
    exit "$(cat "$ST/merge.rc" 2>/dev/null || echo 0)" ;;
esac
[ "$1" != "${TWIN_FAIL:-none}" ] || exit 1
[ "$2" != "${LABEL_FAIL:-none}" ] || exit 1
exit "$(cat "$ST/label.rc" 2>/dev/null || echo 0)"''')
stub(os.path.join(OPS, "scripts/upgrade-notice.sh"), LOG + '''
[ "$1" != open ] || { cat "$ST/open" 2>/dev/null; exit 0; }
[ "$#" -lt 4 ] || [ ! -f "$4" ] || cp "$4" "$ST/notice.$1.details"
exit "$(cat "$ST/notice.$1.rc" 2>/dev/null || echo 0)"''')
# verify: the health look (settle 0, hold 0), Argo settling on the merge (hold 0, its commits given) and the verify
# after an apply apart - the commits it was given said
stub(os.path.join(OPS, "scripts/upgrade-verify.sh"), LOG + '''
if [ "${UPGRADE_VERIFY_HOLD:-}" = 0 ] && [ "${UPGRADE_VERIFY_SETTLE:-}" = 0 ]; then exit "$(cat "$ST/health.rc" 2>/dev/null || echo 0)"; fi
if [ "${UPGRADE_VERIFY_HOLD:-}" = 0 ]; then echo "upgrade-verify.sh ARGO ${UPGRADE_VERIFY_REVISIONS:-}" >> "$ST/calls"; exit "$(cat "$ST/argo.rc" 2>/dev/null || echo 0)"; fi
echo "upgrade-verify.sh AFTER ${UPGRADE_VERIFY_REVISIONS:-}" >> "$ST/calls"
[ ! -e "$ST/slowverify" ] || { echo "verify under way"; touch "$ST/slowverify.started"; for _ in $(seq 50); do sleep 0.1; done; }
rc=$(cat "$ST/verify.rc" 2>/dev/null || echo 0); [ "$rc" = 0 ] || cat "$ST/verify.out" 2>/dev/null
exit "$rc"''')
stub(os.path.join(OPS, "scripts/upgrade-record.sh"), LOG + '\nexit "$(cat "$ST/record.rc" 2>/dev/null || echo 0)"')
# the objects a moved chart stopped shipping, deleted on production after the merge (its verdict from a file)
stub(os.path.join(OPS, "scripts/upgrade-leftovers.py"), LOG + '\nexit "$(cat "$ST/leftovers.rc" 2>/dev/null || echo 0)"')
# the copy's snapshot: used (the copy halted after a run), forget (the proof after a fix on a base built fresh)
stub(os.path.join(OPS, "scripts/copy-snapshot.sh"), LOG + '\nexit "$(cat "$ST/snap.rc" 2>/dev/null || echo 0)"')
# the local mains (the start's gate) apart from the unit's branches (fresh: a list, one verdict a call)
stub(os.path.join(OPS, "scripts/copy-main-current.sh"), LOG + '''
case "$*" in
  *:renovate/*) n=$(head -1 "$ST/stale" 2>/dev/null); [ -z "$n" ] || sed -i 1d "$ST/stale"; exit "${n:-0}" ;;
  *) exit "$(cat "$ST/mains.rc" 2>/dev/null || echo 0)" ;;
esac''')
# task: the build's and the unit proof's verdicts from files (the proof's a list: one per try), the plan, the
# production commands' (one may wait to be stopped)
stub(os.path.join(BIN, "task"), LOG + '''
case "$*" in
  *PLAN=true*) [ ! -e "$ST/plan.fail" ] || { cat "$ST/plan"; exit 1; }; cat "$ST/plan" ;;
  test:copy:ready)  # the locale's encoding as Ansible reads it at its start (it refuses any but UTF-8)
    python3 -c 'import locale; locale.setlocale(locale.LC_ALL, ""); print(locale.getlocale()[1])' > "$ST/build.locale" 2>&1
    exit "$(cat "$ST/build.rc" 2>/dev/null || echo 0)" ;;
  test:copy:unit*) [ ! -e "$ST/slowproof" ] || { touch "$ST/slowproof.started"; for _ in $(seq 50); do sleep 0.1; done; }
    n=$(head -1 "$ST/proofs"); sed -i 1d "$ST/proofs"; exit "${n:-0}" ;;
  "--yes deploy:etcd:backup"*) [ ! -e "$ST/slow" ] || { touch "$ST/slow.started"; for _ in $(seq 30); do sleep 0.1; done; }
    echo "etcd-backup OK: etcd-20261120-120000.db uploaded; current backups:"
    exit "$(cat "$ST/task.deploy_etcd_backup.rc" 2>/dev/null || echo 0)" ;;
  "--yes "*) [ ! -e "$ST/slow" ] || { touch "$ST/slow.started"; for _ in $(seq 30); do sleep 0.1; done; }
    case "$2" in *" "*) echo "task: no task named '$2' (one word with its arguments in it)" >&2; exit 97 ;; esac
    c="${2//:/_}"; exit "$(cat "$ST/task.$c.rc" 2>/dev/null || echo 0)" ;;
esac''')
# the agent: its environment's names, its directory and its arguments kept per call; the fix "commits" (fix.heads) or
# says NO FIX (nofix); it notes whether the runner's checksum script was beside it
stub(os.path.join(BIN, "claude"), LOG + '''
n=$(ls "$ST"/agent.* 2>/dev/null | wc -l)
{ echo "pwd=$PWD"; env | cut -d= -f1 | sort | tr '\\n' ' '; echo; printf '%s\\n' "$@"; } > "$ST/agent.$n"
echo "${GIT_AUTHOR_NAME:-} <${GIT_AUTHOR_EMAIL:-}> ${GIT_COMMITTER_NAME:-} <${GIT_COMMITTER_EMAIL:-}>" > "$ST/author.$n"
case "$*" in
  *"upgrade-cycle review"*) { ls; cat ./*.commits ./*.diff; } > "$ST/review.saw" 2>&1  # what lies beside its clones
    cat ./prod-inventory.txt > "$ST/review.saw-inventory" 2>&1
    n=$(( $(cat "$ST/review.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$ST/review.n"
    if [ -e "$ST/verdict.$n" ]; then cat "$ST/verdict.$n"; else cat "$ST/verdict"; fi
    exit "$(cat "$ST/review.rc" 2>/dev/null || echo 0)" ;;
  *"upgrade-cycle fix"*) [ -e "$PWD/proof.log" ] && touch "$ST/fix.saw-log"
    [ -e "$PWD/review.txt" ] && touch "$ST/fix.saw-review"
    [ ! -e "$PWD/.trusted" ] || touch "$ST/fix.saw-trusted"
    [ ! -e "$ST/fix.heads" ] || touch "$ST/fixed"
    [ ! -e "$ST/nofix" ] || echo "NO FIX: the new version drops a flag the chart needs"
    exit "$(cat "$ST/fix.rc" 2>/dev/null || echo 0)" ;;
esac''')
# git: ops on main, clean, origin's - as the state files say; a clone made; the runner's own repository for the fix
# (made, fetched into, its tip the fix's or the proven head, its files changed); the push; the merge's commits
stub(os.path.join(BIN, "git"), LOG + '''
args="$*"
dir=""; prev=""; for a in "$@"; do [ "$prev" != -C ] || { dir=$a; break; }; prev=$a; done  # -C wherever it stands
case "$args" in
  *" clone "*) cat > /dev/null; case "${@: -1}" in */context/*) [ ! -e "$ST/ctxclone.rc" ] || exit 1 ;; esac; mkdir -p "${@: -1}" ;;
  "init -q --bare "*) cat > /dev/null; mkdir -p "${@: -1}" ;;
  *"fetch -q --no-tags"*) cat > /dev/null; exit "$(cat "$ST/fetchfix.rc" 2>/dev/null || echo 0)" ;;
  *"rev-parse refs/fix"*)
    case "$dir" in
      */infra) if [ -e "$ST/fixed" ]; then echo bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; else echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; fi ;;
      */ops) if [ -e "$ST/fixed.ops" ]; then echo dddddddddddddddddddddddddddddddddddddddd; else echo cccccccccccccccccccccccccccccccccccccccc; fi ;;
    esac ;;
  *" diff "*"--raw"*) [ ! -e "$ST/rawdiff.rc" ] || exit "$(cat "$ST/rawdiff.rc")"
    case "$dir" in  # each file a plain one (100644) unless the case gives raw lines of its own
      */ops) sfx=.ops; def=deploy/ansible/vars/vault.yml ;;
      *) sfx=""; def=clusters/production/istio/values.yaml ;;
    esac
    if [ -e "$ST/fix.raw$sfx" ]; then cat "$ST/fix.raw$sfx"
    else { cat "$ST/fix.files$sfx" 2>/dev/null || echo "$def"; } | while IFS= read -r f; do printf ':100644 100644 1111111 2222222 M\t%s\n' "$f"; done; fi ;;
  *" diff "*"--name-only"*) case "$dir" in
      */ops) cat "$ST/fix.files.ops" 2>/dev/null || echo deploy/ansible/vars/vault.yml ;;
      *) cat "$ST/fix.files" 2>/dev/null || echo clusters/production/istio/values.yaml ;;
    esac ;;
  *"rev-parse --abbrev-ref HEAD"*) f="$ST/branch.$(basename "$dir")"; [ -e "$f" ] || f="$ST/branch"  # one repo's own, or every one's
    cat "$f" 2>/dev/null || echo main ;;
  *"status --porcelain"*) cat "$ST/dirty" 2>/dev/null ;;
  *"fetch -q origin main +refs/heads/renovate/"*)
    if [ -s "$ST/fetchunit.seq" ]; then rc=$(head -1 "$ST/fetchunit.seq"); sed -i 1d "$ST/fetchunit.seq"; exit "$rc"; fi  # one a call
    f="$ST/fetchunit.$(basename "$dir").rc"; [ -e "$f" ] || f="$ST/fetchunit.rc"
    exit "$(cat "$f" 2>/dev/null || echo 0)" ;;
  *"fetch -q origin main"*) exit "$(cat "$ST/fetch.rc" 2>/dev/null || echo 0)" ;;
  *"ls-remote origin refs/heads/renovate/"*)  # a branch's tip: the head Forgejo shows unless the case says otherwise
    r=$(basename "$dir"); f="$ST/tip.$r"; if [ -e "$f" ]; then cat "$f"; else n=$(cat "$ST/heads.n" 2>/dev/null || echo 0)
      h="$ST/heads.$n"; [ -e "$h" ] || h="$ST/heads.last"; [ ! -e "$ST/heads.override" ] || h="$ST/heads.override"
      awk -v r="schnappy/$r" '$1 == r {print $3}' "$h"; fi ;;
  *"rev-parse -q --verify refs/heads/renovate/"*)  # a checkout's branch: the head Forgejo shows unless the case says not
    r=$(basename "$dir"); f="$ST/branchtip.$r"
    if [ -s "$f.seq" ]; then head -1 "$f.seq"; [ "$(wc -l < "$f.seq")" -le 1 ] || sed -i 1d "$f.seq"  # one line a read
    elif [ -e "$f" ]; then cat "$f"; else n=$(cat "$ST/heads.n" 2>/dev/null || echo 0)
      h="$ST/heads.$n"; [ -e "$h" ] || h="$ST/heads.last"; [ ! -e "$ST/heads.override" ] || h="$ST/heads.override"
      awk -v r="schnappy/$r" '$1 == r {print $3}' "$h"; fi ;;
  *"cat-file blob"*) case "${*: -1}" in  # the proven head's file as it was; the fix's as the case gives it
      aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:*|cccccccccccccccccccccccccccccccccccccccc:*) echo "v: 1.0.0" ;;
      *) cat "$ST/blob" 2>/dev/null || echo "v: 1.0.1" ;; esac ;;
  *" diff --text --no-ext-diff --no-textconv --no-color origin/main...HEAD"*)  # the review's diff of a clone
    [ ! -e "$ST/revdiff.$(basename "$dir").rc" ] || exit "$(cat "$ST/revdiff.$(basename "$dir").rc")"
    echo "the diff of $(basename "$dir")" ;;
  *" diff --text"*) cat "$ST/blob" 2>/dev/null || echo "+v: 2 the fix's line"; exit 0 ;;  # the fix's diff (blob: its file)
  *" log --no-color --format=%h %an <%ae> %s origin/main..HEAD"*)  # the review's commits of a clone
    [ ! -e "$ST/revlog.$(basename "$dir").rc" ] || exit "$(cat "$ST/revlog.$(basename "$dir").rc")"
    echo "the commits of $(basename "$dir")" ;;
  *"diff --stat --no-ext-diff --no-textconv --no-color --no-renames origin/main..."*) [ ! -e "$ST/summary.fail" ] || exit 128; echo " clusters/production/x.yaml | 2 +-" ;;
  *"log --format=%h %s origin/main.."*) printf 'abc1234 bump x to 2 \033[2J\n' ;;  # a subject with a terminal escape
  *"log --format=%h %s "*..*) echo "bbbbbbb the agent's own subject" ;;  # the fix's commits in the runner's repository
  *" diff --stat --no-ext-diff --no-textconv --no-color --no-renames "*) echo " clusters/production/fixed.yaml | 2 +-" ;;
  *" commit-tree "*) case "$dir" in  # the runner's commit of the fix's tree: the agent's tip for the case's purposes
      */ops) echo dddddddddddddddddddddddddddddddddddddddd ;; *) echo bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ;; esac ;;
  *"rev-list origin/main --not"*)  # ops' main beyond the gate and the unit's ops head: the unit's merge alone
    if [ -e "$ST/opsextra" ]; then cat "$ST/opsextra"
    else n=0; seen=""; for a in "$@"; do [ -z "$seen" ] || n=$((n + 1)); [ "$a" != --not ] || seen=1; done
      [ "$n" -lt 2 ] || echo mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm; fi ;;
  *"rev-parse "*"^1") echo 1111111111111111111111111111111111111111 ;;
  *"rev-parse "*"^2") cat "$ST/opsparent2" 2>/dev/null || echo cccccccccccccccccccccccccccccccccccccccc ;;
  *"rev-parse origin/main"*) if [ -s "$ST/origin.seq" ]; then head -1 "$ST/origin.seq"; [ "$(wc -l < "$ST/origin.seq")" -le 1 ] || sed -i 1d "$ST/origin.seq"
    else cat "$ST/origin" 2>/dev/null || echo 1111111111111111111111111111111111111111; fi ;;
  *"rev-parse HEAD"*) echo 1111111111111111111111111111111111111111 ;;
  *"ls-remote origin refs/heads/main"*) [ ! -e "$ST/lsremote.fail" ] || exit 1
    printf 'ffffffffffffffffffffffffffffffffffffffff\\trefs/heads/main\\n' ;;
  *"merge-base --is-ancestor"*) exit "$(cat "$ST/ancestor.rc" 2>/dev/null || echo 0)" ;;
  *" push "*) r=$(basename "$dir"); [ ! -e "$ST/push.$r.rc" ] || exit "$(cat "$ST/push.$r.rc")"
    [ ! -e "$ST/fix.heads" ] || [ -e "$ST/fix.unseen" ] || cp "$ST/fix.heads" "$ST/heads.override"
    exit "$(cat "$ST/push.rc" 2>/dev/null || echo 0)" ;;
  *"merge -q --ff-only origin/main"*) exit "$(cat "$ST/ff.rc" 2>/dev/null || echo 0)" ;;
esac''')
# ssh: production's Alertmanager routing the cycle's notices (the probe), else nothing
stub(os.path.join(BIN, "ssh"), LOG + '''
case "$*" in *"amtool config routes test"*) cat "$ST/am" 2>/dev/null || echo email-notice ;; esac''')
stub(os.path.join(BIN, "vagrant"), LOG + '\nexit "$(cat "$ST/vagrant.rc" 2>/dev/null || echo 0)"')
H1 = "schnappy/infra 4 " + "a" * 40 + " " + "e" * 40 + "\nschnappy/ops 7 " + "c" * 40 + " " + "e" * 40 + "\n"
H2 = "schnappy/infra 4 " + "b" * 40 + " " + "e" * 40 + "\nschnappy/ops 7 " + "c" * 40 + " " + "e" * 40 + "\n"
H3 = "schnappy/infra 4 " + "b" * 40 + " " + "e" * 40 + "\nschnappy/ops 7 " + "d" * 40 + " " + "e" * 40 + "\n"
H1_UPDATED = "schnappy/infra 4 " + "5" * 40 + " " + "e" * 40 + "\nschnappy/ops 7 " + "c" * 40 + " " + "e" * 40 + "\n"
H1_BASE_MOVED = "schnappy/infra 4 " + "a" * 40 + " " + "9" * 40 + "\nschnappy/ops 7 " + "c" * 40 + " " + "e" * 40 + "\n"
CLEAN = "PASSES: correctness, security, architecture, reliability, tests, compatibility\nVERDICT: CLEAN"
def setup(pick, proofs=(0,), plan="test:copy:change INFRA_REF=renovate/x PLATFORM_REF=main\n", verdict=CLEAN, mem=30000,
          files=None, heads=(H1,), records=(), inflight=False, tries=0, journal=None, pending=None, verdicts=()):
    for f in os.listdir(ST):
        os.remove(os.path.join(ST, f))
    for d in (".copy", "docs", ".upgrade-cycle"):
        shutil.rmtree(os.path.join(OPS, d), ignore_errors=True)  # each run's logs, records, state its own
    shutil.rmtree(WORK, ignore_errors=True)
    for r in records:
        os.makedirs(os.path.join(OPS, "docs/upgrades"), exist_ok=True)
        open(os.path.join(OPS, "docs/upgrades", r), "w").write("x\n")
    os.makedirs(os.path.join(OPS, ".upgrade-cycle"), exist_ok=True)
    os.makedirs(os.path.join(OPS, "tests/ansible/copy"), exist_ok=True)  # production's inventory as test:copy:ready read it
    open(os.path.join(OPS, "tests/ansible/copy/prod-inventory.txt"), "w").write("image istio/proxyv2 1.31.4 read-this-run\n")
    open(os.path.join(OPS, "tests/ansible/copy/pi-versions.yml"), "w").write("vault: 1.21.1\n")
    if inflight:
        open(os.path.join(OPS, ".upgrade-cycle/inflight"), "w").write(journal or "unit wave-patches\nlog x\nmerged\n")
    if tries:  # earlier runs' tries for the unit
        os.makedirs(os.path.join(OPS, ".upgrade-cycle/tries"), exist_ok=True)
        key = ",".join(f"{l.split()[0]}#{l.split()[1]}" for l in heads[0].splitlines())
        open(os.path.join(OPS, ".upgrade-cycle/tries", pick.split()[1]), "w").write(f"{key} 2026-11-19T12:00:00Z a try\n" * tries)
    if pending is not None:  # an earlier run's CI still running, on these heads ("same": the ones this run reads)
        os.makedirs(os.path.join(OPS, ".upgrade-cycle/pending"), exist_ok=True)
        key = "".join(" ".join(l.split()[:3]) + " " for l in heads[0].splitlines()) if pending == "same" else pending
        open(os.path.join(OPS, ".upgrade-cycle/pending", pick.split()[1]), "w").write(key)
    open(os.path.join(ST, "pick"), "w").write(pick + "\n")
    open(os.path.join(ST, "proofs"), "w").write("".join(f"{p}\n" for p in proofs))
    open(os.path.join(ST, "plan"), "w").write(plan)
    open(os.path.join(ST, "verdict"), "w").write(verdict + "\n")
    for i, v in enumerate(verdicts, 1):  # one a review, in turn (the review after a fix reads the next)
        open(os.path.join(ST, f"verdict.{i}"), "w").write(v + "\n")
    open(os.path.join(ST, "meminfo"), "w").write(f"MemAvailable: {mem * 1024} kB\n")
    for i, h in enumerate(heads):
        open(os.path.join(ST, f"heads.{i}"), "w").write(h)
    open(os.path.join(ST, "heads.last"), "w").write(heads[-1])
    for f, v in (files or {}).items():
        open(os.path.join(ST, f), "w").write(v)
def environ(env=None):
    e = {**os.environ, "PATH": BIN + ":" + os.environ["PATH"], "ST": ST, "UPGRADE_WORK": WORK,
         "UPGRADE_MEMINFO": os.path.join(ST, "meminfo"), "UPGRADE_HEADS_WAIT": "0",
         "UPGRADE_HEADS_READS": "3", "ANTHROPIC_API_KEY": "sk-the-apps-key", "RENOVATE_TOKEN": "bot-token",
         "VAULT_ROOT_TOKEN": "root", "UPGRADE_FORGEJO_TOKEN": "bot-token"}
    e.update(env or {})
    return e
def calls_now():
    p = os.path.join(ST, "calls")
    return open(p).read().splitlines() if os.path.exists(p) else []
def night(pick, args=(), env=None, **kw):
    setup(pick, **kw)
    r = subprocess.run(["bash", os.path.join(OPS, "scripts/upgrade-cycle.sh"), *args], capture_output=True, text=True,
                       env=environ(env), timeout=120)
    night.out = r.stdout
    return r.returncode, calls_now()
def has(calls, prefix):
    return [c for c in calls if c.startswith(prefix)]
def words(c, n):
    return " ".join(c.split(" ")[:n]).strip()
def picked(calls):
    return bool(has(calls, "upgrade-units.py pick"))
def run_log():  # the run's own log - every line it said, the terminal gone or not (each case's .copy its own)
    d = os.path.join(OPS, ".copy")
    logs = sorted(f for f in os.listdir(d) if f.startswith("upgrade-cycle-")) if os.path.isdir(d) else []
    return open(os.path.join(d, logs[-1]), errors="replace").read() if logs else ""
def notices(calls):
    """What the run said of its unit - stopped, applied (a NOTICED, retired 2026-11-21, still caught) - and the pages
    it recorded (its calls)."""
    said = [f"{m.group(1).lower()} {m.group(2)}" for m in re.finditer(r"^\S+ \S+ (STOPPED|APPLIED|NOTICED) ([a-z0-9.-]+):", run_log(), re.M)]
    return said + [f"page {c.split()[2]}" for c in has(calls, "upgrade-notice.sh page")]
def stopped_lines():
    return [l for l in run_log().splitlines() if re.match(r"\S+ \S+ STOPPED ", l)]
def merged(calls, unit):
    return bool(has(calls, f"upgrade-label.py {unit} --merge"))
def paused(calls):
    return bool(has(calls, "upgrade-label.py --pause"))
def pushes(calls):
    return [c.split()[-2:] for c in calls if c.startswith("git ") and " push " in c]
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
def stopped(sig, flag_file, pick="prove wave-patches patch", **kw):
    """the run started, the signal sent once flag_file shows the step under way - its exit and calls"""
    setup(pick, **kw)
    # the run's signals at their defaults, whoever started the harness: an ignored SIGINT (a shell's `&` job starts so)
    # survives the exec, and the Ctrl-C case passed or failed on how it was launched, not on the runner
    def defaults():
        for s_ in (signal.SIGINT, signal.SIGQUIT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(s_, signal.SIG_DFL)
    p = subprocess.Popen(["bash", os.path.join(OPS, "scripts/upgrade-cycle.sh")], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, env=environ(), preexec_fn=defaults)
    for _ in range(400):
        if os.path.exists(os.path.join(ST, flag_file)):
            break
        time.sleep(0.05)
    p.send_signal(sig)
    p.wait(timeout=60)
    return p.returncode, calls_now()
# ── the gates ─────────────────────────────────────────────────────────────────────────────────────────────────────────
rc, calls = night("prove wave-patches patch", files={"open": "scylla-2026.3\n"})
check("an open page: refused, nothing picked - nothing posted (no mail since 2026-11-20)",
      (rc, has(calls, "upgrade-notice.sh"), picked(calls)), (1, ["upgrade-notice.sh open"], False))
rc, calls = night("prove wave-patches patch", inflight=True)
check("a run stopped mid-apply with no page (its journal): paged now - its unit, the journal in it - paused, refused, "
      "nothing picked", (rc, notices(calls), paused(calls), picked(calls), "merged" in night.out),
      (1, ["page wave-patches"], True, False, True))
for files, why in (({"branch": "feat/x\n"}, "ops on another branch"), ({"dirty": " M Taskfile.yml\n"}, "ops with changes"),
                   ({"origin": "2" * 40 + "\n"}, "ops behind or ahead of origin"), ({"fetch.rc": "1"}, "origin not read"),
                   ({"mains.rc": "1"}, "the local infra or platform main stale"),
                   ({"health.rc": "1"}, "production not settled and quiet")):
    rc, calls = night("prove wave-patches patch", files=files)
    check(f"{why}: refused, nothing picked", (rc, picked(calls)), (1, False))
rc, calls = night("prove wave-patches patch")
check("ops checked clean but for the copy's inventory record (the build rewrites it)",
      [c for c in calls if "status --porcelain" in c][0].split(" -- ")[-1],
      ". :!tests/ansible/copy/prod-inventory.txt :!tests/ansible/copy/pi-versions.yml")
check("Alertmanager never read or posted to (the cycle mails nothing since 2026-11-20)",
      [c for c in calls if "amtool" in c or "alertmanager" in c.lower()], [])
rc, calls = night("prove wave-patches patch", mem=20000)
check("memory short (the radar running), a unit that builds the copy: refused at once - no wait, no build",
      (rc, has(calls, "task"), has(calls, "sleep")), (1, [], []))
rc, calls = night("test test-observability minor", mem=20000)
check("memory short, a test unit (no copy): on", (rc, merged(calls, "test-observability")), (0, True))
# units back to back (operator 2026-11-17: back to back): an apply recorded today stops no run - a
# production unit's or a test environment's (one a day, counting the test unit's record, refused every later run)
for rec in ("2026-11-20-istio.md", "2026-11-20-test-observability.md"):
    rc, calls = night("prove wave-patches patch", records=(rec,))
    check(f"an apply recorded today ({rec}): on - units back to back", (rc, picked(calls)), (0, True))
rc, calls = night("prove wave-patches patch", args=("--preflight",))
check("--preflight, the gates passing: exit 0, nothing picked or built", (rc, picked(calls), has(calls, "task")), (0, False, []))
check("  infra's and platform's local mains brought to origin's (a fast-forward) before the check that they are current - the "
      "runner's own merges there left them behind, the next run refused (2026-11-17)",
      [c for c in calls if c.startswith(("git -C ../infra", "git -C ../platform", "copy-main-current.sh"))],
      ["git -C ../infra rev-parse --abbrev-ref HEAD", "git -C ../infra status --porcelain", "git -C ../infra fetch -q origin main",
       "git -C ../infra merge -q --ff-only origin/main", "git -C ../platform rev-parse --abbrev-ref HEAD",
       "git -C ../platform status --porcelain", "git -C ../platform fetch -q origin main",
       "git -C ../platform merge -q --ff-only origin/main", "copy-main-current.sh ../infra ../platform"])
rc, calls = night("prove wave-patches patch", args=("--preflight",), files={"branch.infra": "feature\n"})
check("  infra's checkout on another branch: left as it is (nothing fetched or merged there - the check after judges it), "
      "platform's still brought forward",
      [c for c in calls if c.startswith(("git -C ../infra f", "git -C ../infra m", "git -C ../platform f", "git -C ../platform m"))],
      ["git -C ../platform fetch -q origin main", "git -C ../platform merge -q --ff-only origin/main"])
for files, mem, why in (({}, 20000, "memory"),):
    rc, calls = night("prove wave-patches patch", args=("--preflight",), mem=mem, files=files)
    check(f"--preflight, a gate refusing ({why}): exit 1", rc, 1)
for p in ("NOTHING", "PAUSED"):
    rc, calls = night(p)
    check(f"{p}: the pick alone, nothing readied or halted", (rc, has(calls, "task"), has(calls, "vagrant")), (0, [], []))
# ── a unit, proven and applied ────────────────────────────────────────────────────────────────────────────────────────
PLAN = ("test:copy:change INFRA_REF=renovate/wave-patches PLATFORM_REF=main\n"
        "test:copy:playbook PLAYBOOK=upgrade-kubeadm.yml ARGS='-e k8s_upgrade_to=1.36.7' RESTARTS_EXPECTED=true\n"
        "test:copy:playbook PLAYBOOK=upgrade-forgejo.yml ARGS='-e @/x/forgejo.yml'\n")
REVS = "infra=" + "f" * 40
rc, calls = night("prove wave-patches patch", plan=PLAN)
check("the copy built in a UTF-8 locale - Ansible refuses any other (the first build through the runner, 2026-11-16: "
      "LC_ALL=C, 'Detected None')", open(os.path.join(ST, "build.locale")).read().strip().lower().replace("-", ""), "utf8")
KEY = ("task ", "upgrade-label.py", "upgrade-record.sh", "vagrant", "claude", "upgrade-verify.sh ARGO",
       "upgrade-verify.sh AFTER", "upgrade-units.py held", "copy-snapshot.sh")
seq = [words(c, 2 if c.startswith("upgrade-record.sh") else 3) for c in calls if c.startswith(KEY)
       or c.startswith("git -C " + OPS + " merge")]
check("a patch unit: heads, green, its plan read, built, proven, heads again, reviewed, the copy marked used and halted, the plan, the etcd snapshot, "
      "held, merged, ops fast-forwarded, Argo settled on the merge, Kubernetes, Forgejo, verified, the inventory read, "
      "recorded, reported - in that order (the copy gone once)",
      (rc, seq),
      (0, ["upgrade-label.py wave-patches --heads", "upgrade-label.py wave-patches --green",
           "task test:copy:unit UNIT=wave-patches", "task test:copy:ready",
           "task test:copy:unit UNIT=wave-patches", "upgrade-label.py wave-patches --heads", "claude -p upgrade-cycle",
           "copy-snapshot.sh used", "vagrant halt", "task test:copy:unit UNIT=wave-patches", "task --yes deploy:etcd:backup",
           "upgrade-units.py held wave-patches", "upgrade-label.py wave-patches --merge", "git -C " + OPS,
           "upgrade-verify.sh ARGO " + REVS, "task --yes deploy:kubeadm:upgrade", "task --yes deploy:forgejo:upgrade",
           "upgrade-verify.sh AFTER " + REVS, "task test:copy:inventory", "upgrade-record.sh wave-patches"]))
check("  said applied on the terminal - nothing mailed", notices(calls), ["applied wave-patches"])
check("  what its charts stopped shipping cleared on production after the merge, before Argo is waited on - from infra's "
      "proven base to its proven head",
      ([words(c, 3) for c in calls if c.startswith(("upgrade-label.py wave-patches --merge", "upgrade-leftovers.py",
                                                     "upgrade-verify.sh ARGO"))], has(calls, "upgrade-leftovers.py")),
      (["upgrade-label.py wave-patches --merge", "upgrade-leftovers.py --on ten", "upgrade-verify.sh ARGO " + REVS],
       ["upgrade-leftovers.py --on ten --base " + "e" * 40 + " --head " + "a" * 40]))
check("  merged at the heads proven - head and base each - ops brought by fetch and fast-forward (never a pull)",
      (open(os.path.join(ST, "merged.expect")).read(), len(has(calls, "git -C " + OPS + " merge -q --ff-only origin/main")),
       has(calls, "git -C " + OPS + " pull")), (H1, 1, []))
check("  the local mains read at the start alone (the base pin stands for them after); the unit's branches judged on "
      "main before its CI and again after it",
      [c for c in has(calls, "copy-main-current.sh")],
      ["copy-main-current.sh ../infra ../platform"] + [f"copy-main-current.sh {OPS}/../infra:renovate/wave-patches {OPS}:renovate/wave-patches"] * 2)
check("  the review's clones as the bot (its token by a helper of the call's own, to Forgejo's host alone), each at its "
      "proven head, outside every checkout, gone after",
      ([c.split()[-2] for c in calls if c.startswith("git -c credential.helper=") and " clone " in c],
       [c.split()[-1] for c in calls if c.startswith("git -C " + WORK) and "checkout -q -B" in c],
       all('test "$h" = git.pmon.dev' in c for c in calls if c.startswith("git -c credential.helper=")),
       os.listdir(WORK) if os.path.exists(WORK) else []),
      (["https://git.pmon.dev/schnappy/infra.git", "https://git.pmon.dev/schnappy/ops.git", "https://git.pmon.dev/schnappy/platform.git"],
       ["a" * 40, "c" * 40], True, []))
check("  the review's context: each repo the unit does not touch cloned at main, one commit deep, under context/ (production's "
      "inventory and every other pin read there); Renovate's pull request bodies written beside the clones",
      ([" ".join(c.split()[-5:-2]) + " " + c.split()[-1].split("/context/")[-1] for c in calls
        if c.startswith("git -c credential.helper=") and " clone " in c and "/context/" in c],
       [c.split()[:3] + [c.split()[3].startswith(WORK)] for c in has(calls, "upgrade-units.py bodies")]),
      (["-q --depth 1 platform"], [["upgrade-units.py", "bodies", "wave-patches", True]]))
check("  Kubernetes to the proven version", has(calls, "task --yes deploy:kubeadm"),
      ["task --yes deploy:kubeadm:upgrade -- -e k8s_upgrade_to=1.36.7"])
check("  the journal of the apply gone with its record; no step that may leave a process behind (task - the copy's host "
      "guard -, vagrant, the agents) handed the run's lock",
      (inflight(), [c for c in (open(os.path.join(ST, "fd9")).read().splitlines() if os.path.exists(os.path.join(ST, "fd9")) else [])
                    if c.startswith(("task", "vagrant", "claude"))]), (False, []))
a = agents()
check("  the review agent: in its clones, none of the task's environment (no API key, no bot token, no Vault token), no "
      "git config or credential, an author of its own, --restricted (no instructions from the clones), its instructions, "
      "the reviewers handed over, settings of its own, anything else denied",
      (len(a), a[0]["pwd"].startswith(os.path.join(WORK, "wave-patches-review-")),
       sorted(set(a[0]["env"]) - {"PWD", "SHLVL", "_", "OLDPWD"}), "--restricted" in a[0]["args"],
       flag(a[0]["args"], "--append-system-prompt-file"), sorted(json.loads(flag(a[0]["args"], "--agents") or "{}")),
       flag(a[0]["args"], "--settings"), flag(a[0]["args"], "--permission-mode"), flag(a[0]["args"], "--permission-prompts")),
      (1, True, ["GIT_AUTHOR_EMAIL", "GIT_AUTHOR_NAME", "GIT_CEILING_DIRECTORIES", "GIT_COMMITTER_EMAIL", "GIT_COMMITTER_NAME",
                 "GIT_CONFIG_GLOBAL", "GIT_CONFIG_NOSYSTEM", "GIT_TERMINAL_PROMPT", "HOME", "LANG", "PATH"], True,
       os.path.join(OPS, ".claude/upgrade-agent/review.md"),
       ["code-architecture-reviewer", "platform-reliability-reviewer", "test-quality-reviewer"],
       os.path.join(OPS, ".claude/upgrade-agent/review.json"), "dontAsk", "none"))
check("  its commits by an identity of its own - never Renovate's (Renovate takes a branch whose commits carry its own "
      "e-mail for unmodified and rebases over them), never the operator's",
      sorted(open(os.path.join(ST, f)).read().strip() for f in os.listdir(ST) if f.startswith("author.")),
      ["Upgrade Fix Agent <upgrade-fix@pmon.dev> Upgrade Fix Agent <upgrade-fix@pmon.dev>"])
check("  the reviewers as their files define them (their prompt, their tools)",
      {k: (v["prompt"][:30], v["tools"]) for k, v in json.loads(flag(a[0]["args"], "--agents") or "{}").items()}.get("code-architecture-reviewer"),
      ("You are a senior reviewer for ", ["Read", "Grep", "Glob", "Bash"]))
check("  beside each clone, before the review starts: its diff against main and its commits (<repo>.diff, <repo>.commits) "
      "- its reviewers read files, their Bash runs one plain git command a call (2026-11-17: a reviewer's cd-then-diff "
      "refused, platform's and ops' diffs never read) - as text, git's external diff and textconv off",
      (open(os.path.join(ST, "review.saw")).read().splitlines(),
       len([c for c in calls if c.startswith("git -C " + WORK) and "diff --text --no-ext-diff --no-textconv --no-color origin/main...HEAD" in c])),
      (["context", "infra", "infra.commits", "infra.diff", "infra.pr.md", "ops", "ops.commits", "ops.diff", "pi-versions.yml", "prod-inventory.txt", "the commits of infra", "the commits of ops",
        "the diff of infra", "the diff of ops"], 2))
rc, calls = night("prove centrifugo minor")
check("a unit with no production command: ops brought to origin's main all the same (its ops part may be a file no "
      "command reads - the record commits on it), Argo's settle left to the verify",
      (rc, len(has(calls, "git -C " + OPS + " merge -q --ff-only")), has(calls, "upgrade-verify.sh ARGO")), (0, 1, []))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"green.rc": "1"})
check("its CI still running after an hour (Woodpecker's queue): reported, nothing built, nothing labelled, NO try counted",
      (rc, has(calls, "task"), notices(calls), has(calls, "upgrade-label.py wave-patches upgrade-blocked"),
       has(calls, "upgrade-label.py wave-patches --green"), os.path.exists(os.path.join(OPS, ".upgrade-cycle/tries/wave-patches"))),
      (1, [], ["stopped wave-patches"], [], ["upgrade-label.py wave-patches --green 3600"], False))
def tries_now(unit="wave-patches"):
    p = os.path.join(OPS, ".upgrade-cycle/tries", unit)
    return len(open(p).read().splitlines()) if os.path.exists(p) else 0
check("  the heads it was still running on recorded: the next run on the same heads counts one",
      os.path.exists(os.path.join(OPS, ".upgrade-cycle/pending/wave-patches")), True)
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"green.rc": "1"}, pending="same")
check("  still running on the same heads a run later (stuck in Woodpecker): a try counted, nothing built",
      (rc, has(calls, "task"), tries_now(), [c for c in stopped_lines() if "same heads a run later" in c] != []),
      (1, [], 1, True))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"green.rc": "1"}, pending="schnappy/infra 1 " + "f" * 40 + " ")
check("  still running on other heads than a run before (they moved): no try, the new heads recorded",
      (rc, tries_now(), open(os.path.join(OPS, ".upgrade-cycle/pending/wave-patches")).read().startswith("schnappy/infra 4 " + "a" * 40)),
      (1, 0, True))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"green.rc": "5"})
check("no CI on its heads after an hour (no pipeline started - it never comes by itself): a try counted, nothing built",
      (rc, has(calls, "task"), tries_now(), [c for c in stopped_lines() if "no CI on its heads" in c] != []),
      (1, [], 1, True))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"green.rc": "4"}, tries=2)
check("  the third try for the unit's pull requests (red CI, its heads moved between them): a try like any other - never "
      "labelled, no blocked state (the pick takes the units with none first)",
      (rc, has(calls, "upgrade-label.py wave-patches upgrade-blocked"), tries_now(), notices(calls)), (1, [], 3, ["stopped wave-patches"]))
setup("prove wave-patches patch", plan=PLAN, files={"green.rc": "4"})
os.makedirs(os.path.join(OPS, ".upgrade-cycle/tries"), exist_ok=True)
open(os.path.join(OPS, ".upgrade-cycle/tries/wave-patches"), "w").write("schnappy/infra#1,schnappy/ops#2 2026-11-01T00:00:00Z old\n" * 5)
subprocess.run(["bash", os.path.join(OPS, "scripts/upgrade-cycle.sh")], capture_output=True, text=True, env=environ(), timeout=120)
check("  tries of an earlier unit of the name (other pull requests): not this one's - a first try, not labelled",
      has(calls_now(), "upgrade-label.py wave-patches upgrade-blocked"), [])
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"green.rc": "4"})
check("its CI red (its own checks, or Woodpecker failing - a clone that lost its credentials): a try, nothing built, not "
      "labelled the first time", (rc, has(calls, "task"), has(calls, "upgrade-label.py wave-patches upgrade-blocked"), notices(calls)),
      (1, [], [], ["stopped wave-patches"]))
rc, calls = night("prove wave-patches patch", plan=PLAN, tries=2)
check("a run that gets the unit further (applied) starts its count again", (rc, os.path.exists(os.path.join(OPS, ".upgrade-cycle/tries/wave-patches"))),
      (0, False))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"stale": "1\n0\n"}, heads=(H1, H1_UPDATED))
check("its branches behind main (Renovate rebases on a conflict alone): brought onto main by Forgejo FIRST (a red CI on "
      "a stale head heals with the update's run), its new heads waited for, then green, fetched, judged again - then "
      "built, proven on the new heads",
      (rc, [words(c, 3) for c in has(calls, "upgrade-label.py wave-patches") if c.split()[2] in ("--update", "--green")],
       bool(has(calls, "task test:copy:ready")), open(os.path.join(ST, "merged.expect")).read() if os.path.exists(os.path.join(ST, "merged.expect")) else None),
      (0, ["upgrade-label.py wave-patches --update", "upgrade-label.py wave-patches --green"], True, H1_UPDATED))
check("  every repo of the unit judged on main - ops' branch too", [c for c in has(calls, "copy-main-current.sh") if "renovate/" in c][:1],
      [f"copy-main-current.sh {OPS}/../infra:renovate/wave-patches {OPS}:renovate/wave-patches"])
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"stale": "1\n1\n"})
check("  behind again after its CI (other work's pushes to main): said, nothing built, NO try", (rc, has(calls, "task test:copy:ready"),
      notices(calls), os.path.exists(os.path.join(OPS, ".upgrade-cycle/tries/wave-patches"))), (1, [], ["stopped wave-patches"], False))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"stale": "1\n", "tip.infra": "9" * 40 + "\n"})
check("  updated, Forgejo not showing the new heads yet: said, nothing built, no try", (rc, has(calls, "task test:copy:ready"),
      os.path.exists(os.path.join(OPS, ".upgrade-cycle/tries/wave-patches"))), (1, [], False))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"stale": "1\n", "tip.infra": "\n"})
check("  a tip not read (ls-remote failing): never taken for the new head - nothing built", (rc, has(calls, "task test:copy:ready")), (1, []))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"stale": "1\n", "tip.infra": "\n"},
                  heads=("schnappy/infra 4\nschnappy/ops 7 " + "c" * 40 + " " + "e" * 40 + "\n",))
check("  a tip not read and a head Forgejo did not give (both empty - equal): never an update shown - nothing built",
      (rc, has(calls, "task test:copy:ready")), (1, []))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"stale": "1\n", "update.rc": "1"})
check("  Forgejo's update refused (a conflict): a try", (rc, os.path.exists(os.path.join(OPS, ".upgrade-cycle/tries/wave-patches"))), (1, True))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"fetchunit.seq": "0\n0\n1\n"})
check("  its branches fetched before its CI, not after it (the second fetch failing alone): said, nothing built, no try",
      (rc, has(calls, "task test:copy:ready"), tries_now(),
       [c for c in stopped_lines() if "not fetched after their CI" in c] != []), (1, [], 0, True))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"fetchunit.ops.rc": "1"})
check("  ops' branch fetched too (its checkout's own fetch failing): said, nothing built", (rc, has(calls, "task test:copy:ready")), (1, []))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"fetchunit.rc": "1"})
check("its branches not fetched (git): said, nothing proven - NOT a try (no stale base)", (rc, has(calls, "task test:copy:ready"),
      os.path.exists(os.path.join(OPS, ".upgrade-cycle/tries/wave-patches"))), (1, [], False))
# ── red: the agent's fix ──────────────────────────────────────────────────────────────────────────────────────────────
ISTIO = "test:copy:change INFRA_REF=renovate/istio PLATFORM_REF=renovate/istio\n"
rc, calls = night("prove istio minor", proofs=(1, 0), plan=ISTIO, files={"fix.heads": H2})
a = agents()
check("red, the agent's fix: --restricted, the skill's text, the fix's settings, in clones of the proven commits beside "
      "the proof's log (no checksum script of any kind: a pin is Renovate's), all gone after",
      (rc, "--restricted" in a[0]["args"], flag(a[0]["args"], "--append-system-prompt-file"), flag(a[0]["args"], "--settings"),
       flag(a[0]["args"], "--permission-mode"), a[0]["pwd"].startswith(os.path.join(WORK, "istio-fix-")),
       os.path.exists(os.path.join(ST, "fix.saw-log")), os.path.exists(os.path.join(ST, "fix.saw-trusted")),
       os.listdir(WORK) if os.path.exists(WORK) else []),
      (0, True, os.path.join(OPS, ".claude/skills/upgrade-fix/SKILL.md"), os.path.join(OPS, ".claude/upgrade-agent/fix.json"),
       "dontAsk", True, True, False, []))
check("  its commits fetched into the runner's own repository (never run in the agent's), pushed from there to Forgejo's "
      "URL as the bot (no hooks), labelled stop-updating and agent-fixed, proven again on the heads Forgejo shows; its "
      "files judged with both sides of a rename",
      ([c.startswith("git init -q --bare " + WORK) for c in calls if c.startswith("git init")],
       [c.split()[2].endswith(".push/infra") for c in calls if "fetch -q --no-tags" in c][:1],
       pushes(calls), [("core.hooksPath=/dev/null" in c, c.startswith("git -c credential.helper= -c credential.helper=!f()"))
                       for c in calls if c.startswith("git") and " push " in c],
       [words(c, 3) for c in has(calls, "upgrade-label.py istio") if c.split()[2] in ("stop-updating", "agent-fixed")],
       len(has(calls, "task test:copy:ready")), [("--no-renames" in c) for c in calls if " diff " in c and "--raw" in c]),
      ([True, True], [True], [["https://git.pmon.dev/schnappy/infra.git", "b" * 40 + ":refs/heads/renovate/istio"]],
       [(True, True)], ["upgrade-label.py istio agent-fixed", "upgrade-label.py istio stop-updating"], 2, [True]))
check("  the fix's own CI waited for before its proof (green read again after the push)",
      [words(c, 4) for c in calls if c.startswith(("upgrade-label.py istio --green", "upgrade-label.py istio agent-fixed"))],
      ["upgrade-label.py istio --green 3600", "upgrade-label.py istio agent-fixed", "upgrade-label.py istio --green 3600"])
check("  then, proven again and reviewed: applied in this run (no notice, no comment - operator 2026-11-21), said with "
      "the agent's fix named; its record gone with the apply (its commit merged)",
      (notices(calls), has(calls, "upgrade-label.py istio --comment"), merged(calls, "istio"),
       any("APPLIED istio: minor, with the agent's fix" in l for l in run_log().splitlines()),
       os.path.exists(os.path.join(OPS, ".upgrade-cycle/fixes/istio.diff"))),
      (["applied istio"], [], True, True, False))
for files, why in (({"fix.heads": H2, "fix.files": ".woodpecker/ci.yaml\n"}, "changed CI (outside the unit's own files)"),
                   ({"fix.heads": H2, "fix.files": "clusters/production/CLAUDE.md\n"}, "wrote an agent's instructions"),
                   ({"fix.heads": H2, "fix.files": "clusters/x.yaml\nscripts/copy-unit.sh\n"}, "changed a script beside a value"),
                   ({"fix.heads": H2, "fetchfix.rc": "1"}, "left its branch (nothing to fetch)"),
                   ({"fix.heads": H2, "ancestor.rc": "1"}, "rewrote the proven commit"),
                   ({"fix.heads": H2, "push.rc": "1"}, "the push of which was refused")):
    rc, calls = night("prove istio minor", proofs=(1, 0), files=files)
    check(f"a fix that {why}: not pushed, blocked, proven no more, nothing merged",
          (rc, merged(calls, "istio"), pushes(calls) if "push.rc" not in files else [], notices(calls), len(has(calls, "task test:copy:ready"))),
          (1, False, [], ["stopped istio"], 1))
rc, calls = night("prove istio minor", proofs=(1, 0), files={"fix.heads": H2, "rawdiff.rc": "128"})
check("a fix whose files git does not list (its diff failing): nothing pushed, blocked - never its tree pushed unjudged",
      (rc, pushes(calls), any("the fix's files not read" in l for l in run_log().splitlines())), (1, [], True))
rc, calls = night("prove istio minor", proofs=(1, 0), files={"fix.heads": H2, "fix.raw": ":000000 120000 0000000 3333333 A\tclusters/production/x.yaml\n"})
check("a fix committing a symlink (or a submodule) under the unit's own files: nothing pushed, blocked (the copy reads "
      "the tree unsandboxed)", (rc, pushes(calls), notices(calls)), (1, [], ["stopped istio"]))
for blob, why in (("v: 2\r  extra: evil\n", "a carriage return (a YAML key hidden from the mail and the review)"),
                  ("{{/* \x00 */}}\n", "a NUL (git calls it binary: the mail shows 'Binary files differ')"),
                  ("bell \x07\n", "another control character")):
    rc, calls = night("prove istio minor", proofs=(1, 0), files={"fix.heads": H2, "blob": blob})
    check(f"a fix holding {why}: nothing pushed, blocked", (rc, pushes(calls), notices(calls)), (1, [], ["stopped istio"]))
rc, calls = night("prove istio minor", proofs=(1, 0), files={"fix.heads": H2}, env={"LABEL_FAIL": "stop-updating"})
check("a fix whose stop-updating label does not set (Renovate would rewrite it): nothing pushed, blocked", (rc, pushes(calls), notices(calls)),
      (1, [], ["stopped istio"]))
setup("prove istio minor", proofs=(1, 0), files={"fix.heads": H2, "merge.rc": "1"})  # ends before the apply clears it
os.makedirs(os.path.join(OPS, ".upgrade-cycle/fixes"), exist_ok=True)
open(os.path.join(OPS, ".upgrade-cycle/fixes/istio.diff"), "w").write("=== the agent's fix of renovate/istio, long ago (applied) - files:\nOLD\n")
subprocess.run(["bash", os.path.join(OPS, "scripts/upgrade-cycle.sh")], capture_output=True, text=True, env=environ(), timeout=120)
check("a unit of a name fixed before (its record of an applied instance): this fix's record alone - the old one never mailed",
      "OLD" in open(os.path.join(OPS, ".upgrade-cycle/fixes/istio.diff")).read(), False)
rc, calls = night("prove istio minor", proofs=(1, 0), files={"fix.heads": H2, "blob": "v: 1.0.1\n# " + "y" * 120000 + "\n"})
check("a fix of any size (over the 100 KB a mail once took): applied all the same - nothing is mailed, never labelled",
      (rc, has(calls, "upgrade-label.py istio upgrade-blocked"), notices(calls)), (0, [], ["applied istio"]))
rc, calls = night("prove istio minor", proofs=(1, 0), files={"fix.heads": H2, "fix.raw": ":100644 000000 1111111 0000000 D\tclusters/production/old.yaml\n"})
check("a fix deleting a file of the unit's own: refused, nothing pushed (a NetworkPolicy or a PeerAuthentication gone is no fix)",
      (rc, len(pushes(calls))), (1, 0))
rc, calls = night("prove istio minor", proofs=(1, 0), files={"fix.heads": H2, "merge.rc": "1"})  # ends before the apply clears it
fixrec = os.path.join(OPS, ".upgrade-cycle/fixes/istio.diff")
rec = open(fixrec).read() if os.path.exists(fixrec) else ""
check("  the fix on record (.upgrade-cycle/fixes/<unit>.diff): every repo's files first, then its commits and diff",
      (rec.startswith("=== the agent's fix of renovate/istio, "), rec.split("\n")[1:3],
       rec.find("bbbbbbb the agent's own subject") > rec.find("fixed.yaml | 2 +-") > 0, "+v: 2 the fix's line" in rec),
      (True, ["=== schnappy/infra", " clusters/production/fixed.yaml | 2 +-"], True, True))
rc, calls = night("prove istio minor", proofs=(1, 0), files={"fix.heads": H2}, env={"LABEL_FAIL": "agent-fixed"})
check("a fix whose agent-fixed label does not set (what the agent wrote would carry no mark of it): nothing pushed, "
      "blocked, not proven again",
      (rc, pushes(calls), len(has(calls, "task test:copy:ready")), notices(calls), merged(calls, "istio")),
      (1, [], 1, ["stopped istio"], False))
# ops' merge on main: its second parent the fixed ops head (dddd) - the unit goes on to its apply now
rc, calls = night("prove istio minor", proofs=(1, 0), files={"fix.heads": H3, "fixed.ops": "", "opsparent2": "d" * 40 + "\n"})
labelled_at = min([i for i, c in enumerate(calls) if c.startswith("upgrade-label.py istio agent-fixed")] or [10 ** 6])
pushed_at = [i for i, c in enumerate(calls) if c.startswith("git ") and " push " in c]
check("a fix in two repos (the clone and its list read past every step that reads stdin): both judged, labelled "
      "agent-fixed BEFORE the first push, both pushed, proven again on both heads Forgejo shows",
      (rc, [p[1][:4] for p in pushes(calls)], bool(pushed_at) and labelled_at < min(pushed_at), len(has(calls, "task test:copy:ready")),
       notices(calls)), (0, ["bbbb", "dddd"], True, 2, ["applied istio"]))
readies = [i for i, c in enumerate(calls) if c.startswith("task test:copy:ready")]
forgets = [i for i, c in enumerate(calls) if c.startswith("copy-snapshot.sh forget")]
check("  the proof after the fix on a base built fresh: the snapshot forgotten between the two readies, once (never one base twice)",
      (len(forgets), len(readies) == 2 and len(forgets) == 1 and readies[0] < forgets[0] < readies[1]), (1, True))
rc, calls = night("prove istio minor", proofs=(1, 0), files={"fix.heads": H3, "fixed.ops": "", "snap.rc": "1"})
check("  the snapshot not forgotten, or the copy not marked used (its script failing): said, never silent",
      [(m in night.out) for m in ("THE SNAPSHOT NOT FORGOTTEN", "THE COPY NOT MARKED USED")], [True, True])
check("  the copy marked used before its halt, however the run ended",
      [c.split()[1] if c.startswith("copy-snapshot.sh") else c for c in calls if c.startswith(("copy-snapshot.sh used", "vagrant halt"))][-2:],
      ["used", "vagrant halt"])
rc, calls = night("prove istio minor", proofs=(1, 0), files={"fix.heads": H3, "fixed.ops": "", "fix.files.ops": "Taskfile.yml\n"})
check("a fix fine in infra, outside the unit's files in ops: NOTHING pushed (never half a fix, unlabelled), blocked",
      (rc, pushes(calls), has(calls, "upgrade-label.py istio agent-fixed"), notices(calls)), (1, [], [], ["stopped istio"]))
rc, calls = night("prove istio minor", proofs=(1, 0), files={"fix.heads": H3, "fixed.ops": "", "push.ops.rc": "1"})
check("a fix whose second push is refused after the first went in: blocked - the unit labelled agent-fixed already (what "
      "went in is proven and reviewed again before any apply)", (rc, len(pushes(calls)), bool(has(calls, "upgrade-label.py istio agent-fixed")), notices(calls)),
      (1, 2, True, ["stopped istio"]))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"branchtip.infra": "9" * 40 + "\n"})
check("a checkout's branch not the head its pull request names (Forgejo's record behind its git): nothing built, no try",
      (rc, has(calls, "task"), tries_now(), [c for c in stopped_lines() if "tips not the heads" in c] != []),
      (1, [], 0, True))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"branchtip.infra.seq": "a" * 40 + "\n" + "9" * 40 + "\n"})
check("  the branch moved past its pull request's head during the proof (the copy fetched another commit): nothing applied",
      (rc, merged(calls, "wave-patches"), [c for c in stopped_lines() if "moved during its proof" in c] != []),
      (1, False, True))
rc, calls = night("prove istio minor", proofs=(1, 0), files={"fix.heads": ""})
check("a try counted for the pull requests the run's first read named - a later read that came back empty no other key",
      [l.split()[0] for l in open(os.path.join(OPS, ".upgrade-cycle/tries/istio")).read().splitlines()]
      if os.path.exists(os.path.join(OPS, ".upgrade-cycle/tries/istio")) else None, ["schnappy/infra#4,schnappy/ops#7"])
rc, calls = night("prove istio minor", proofs=(1, 0), files={"fix.heads": H2, "fix.unseen": ""})
check("a fix pushed that Forgejo does not show on its pull requests: blocked, not proven on what it shows",
      (rc, len(has(calls, "task test:copy:ready")), notices(calls)), (1, 1, ["stopped istio"]))
rc, calls = night("prove istio minor", proofs=(1, 0), plan=ISTIO, files={"nofix": ""})
check("no fix, the agent's verdict (NO FIX - the new version's defect): a try, its reason said - never labelled, no rebuild",
      (rc, has(calls, "upgrade-label.py istio upgrade-blocked"), notices(calls), len(has(calls, "task test:copy:ready")), tries_now("istio"),
       any("NO FIX: the new version drops a flag" in l for l in stopped_lines())),
      (1, [], ["stopped istio"], 1, 1, True))
rc, calls = night("prove istio minor", proofs=(1, 0), plan=ISTIO, files={"fix.rc": "1"})
check("no fix and no verdict (the agent did not finish): a try, never labelled, no rebuild",
      (rc, has(calls, "upgrade-label.py istio upgrade-blocked"), notices(calls), len(has(calls, "task test:copy:ready")), tries_now("istio")),
      (1, [], ["stopped istio"], 1, 1))
rc, calls = night("prove istio minor", proofs=(1, 1), files={"fix.heads": H2})
check("red after its fix: a try, said, nothing merged, the copy halted - never labelled",
      (rc, has(calls, "upgrade-label.py istio upgrade-blocked"), notices(calls), merged(calls, "istio"), len(has(calls, "vagrant")), tries_now("istio")),
      (1, [], ["stopped istio"], False, 1, 1))
rc, calls = night("prove istio minor", files={"build.rc": "1"})
check("a copy that does not get ready: the run ends - no agent, no label, no notice blaming the unit; the copy halted",
      (rc, has(calls, "claude"), has(calls, "upgrade-label.py istio upgrade-blocked"), notices(calls), len(has(calls, "vagrant"))),
      (1, [], [], [], 1))
rc, calls = night("prove istio minor", heads=(H1, H2))
check("the heads moved during the proof: blocked, nothing reviewed or merged",
      (rc, merged(calls, "istio"), has(calls, "claude"), notices(calls)), (1, False, [], ["stopped istio"]))
rc, calls = night("prove istio minor", heads=(H1, H1_BASE_MOVED))
check("only a base moved during the proof (CD's promotions - the merge judges a base): reviewed and merged",
      (rc, merged(calls, "istio")), (0, True))
rc, calls = night("prove istio minor", files={"vagrant.rc": "1"})
check("the copy not halted after the review: said in the run and the applied notice (the radar stays off)",
      (rc, "THE COPY NOT HALTED" in night.out), (0, True))
# ── the review ────────────────────────────────────────────────────────────────────────────────────────────────────────
# any finding - whatever its severity (operator 2026-11-20: every severity, not criticals alone) - goes to the agent's fix (here it
# commits none: a try); a review that did not finish is a try with no fix; nothing is ever labelled
for verdict, files, label, why in (("VERDICT: CRITICAL a bad thing\nPASSES: x", {}, True, "a CRITICAL: a finding, to the fix agent"),
                                   ("PASSES: a\nVERDICT: CLEAN\nVERDICT: CRITICAL later", {}, True, "a later CRITICAL: a finding, to the fix agent"),
                                   ("VERDICT: CRITICAL first\n" + CLEAN, {}, True, "a CRITICAL then CLEAN (a later line never takes it back): to the fix agent"),
                                   ("FINDING: suggestion infra/x.yaml - a nit\n" + CLEAN, {}, True, "a suggestion beside a CLEAN verdict: a finding, to the fix agent"),
                                   ("FINDING: warning a - b\nPASSES: correctness, security, architecture, reliability, tests, compatibility\nVERDICT: FINDINGS 1", {}, True,
                                    "VERDICT: FINDINGS: to the fix agent"),
                                   ("VERDICT: CLEAN", {}, False, "CLEAN with no passes named: not labelled"),
                                   ("PASSES: correctness, security, architecture, reliability, compatibility\nVERDICT: CLEAN", {}, False,
                                    "CLEAN with a pass missing (tests): not labelled"),
                                   ("PASSES: correctness, security, architecture, reliability, tests\nVERDICT: CLEAN", {}, False,
                                    "CLEAN with the compatibility pass missing: not labelled"),
                                   ("PASSES: x\nnothing more", {}, False, "no verdict (it did not finish): not labelled"),
                                   ("PASSES: correctness, security, architecture, reliability, compatibility\nVERDICT: INCOMPLETE tests", {}, False,
                                    "INCOMPLETE (a pass that did not run): not labelled"),
                                   ("PASSES: correctness, security, architecture, reliability, tests-not-run, compatibility\nVERDICT: CLEAN", {}, False,
                                    "CLEAN, 'tests-not-run' for tests (a name is a name): not labelled"),
                                   ("PASSES: correctness, security, architecture, reliability, tests (skipped), compatibility\nVERDICT: CLEAN", {}, False,
                                    "CLEAN, 'tests (skipped)': not labelled"),
                                   ("PASSES: correctness, security, architecture, reliability, no tests, compatibility\nVERDICT: CLEAN", {}, False,
                                    "CLEAN, 'no tests': not labelled"),
                                   (CLEAN, {"review.rc": "1"}, False, "the review agent failing: not labelled")):
    rc, calls = night("prove istio minor", verdict=verdict, files=files)
    check(f"{why.replace(': not labelled', ': no fix')}, nothing merged, never labelled, a try",
          (rc, merged(calls, "istio"), has(calls, "upgrade-label.py istio upgrade-blocked"), os.path.exists(os.path.join(ST, "fix.saw-review")),
           tries_now("istio")), (1, False, [], label, 1))
# the finding fixed: proven again on a fresh base and reviewed again - CLEAN goes on to the apply in the same run;
# findings left after the fix, or red after it: a try; two fixes at most a run
FIND = ("FINDING: warning clusters/production/istio/values.yaml - a value the new chart renamed\n"
        "PASSES: correctness, security, architecture, reliability, tests, compatibility\nVERDICT: FINDINGS 1")
def reviews(calls):
    return len([c for c in calls if c.startswith("claude") and "upgrade-cycle review" in c])
def proven(calls, unit="istio"):
    return len([c for c in calls if c == f"task test:copy:unit UNIT={unit}"])
rc, calls = night("prove istio minor", proofs=(0, 0), verdicts=(FIND, CLEAN), files={"fix.heads": H2})
check("a review's finding (a warning): the agent's fix handed the review (review.txt), pushed, proven again on a fresh "
      "base, reviewed again CLEAN - then applied in this run (no notice)",
      (rc, os.path.exists(os.path.join(ST, "fix.saw-review")), len(pushes(calls)), len(has(calls, "task test:copy:ready")),
       proven(calls), reviews(calls), notices(calls), merged(calls, "istio")),
      (0, True, 1, 2, 2, 2, ["applied istio"], True))
rc, calls = night("prove istio minor", proofs=(0, 0), verdicts=(FIND, FIND), files={"fix.heads": H2})
check("  findings left after its fix: a try, said - nothing merged, never labelled",
      (rc, merged(calls, "istio"), tries_now("istio"), notices(calls), has(calls, "upgrade-label.py istio upgrade-blocked")),
      (1, False, 1, ["stopped istio"], []))
rc, calls = night("prove istio minor", proofs=(0, 1), verdicts=(FIND,), files={"fix.heads": H2})
check("  red after the fix of its findings: a try, never reviewed again, nothing merged",
      (rc, merged(calls, "istio"), reviews(calls), tries_now("istio"), notices(calls)), (1, False, 1, 1, ["stopped istio"]))
rc, calls = night("prove istio minor", proofs=(1, 0), verdicts=(FIND,), files={"fix.heads": H2}, env={"UPGRADE_FIX_ROUNDS": "1"})
check("  a red proof fixed, then a finding with the run's fixes spent: a try, said, the agent not run again",
      (rc, len([c for c in calls if c.startswith("claude") and "upgrade-cycle fix" in c]), any("fixes spent" in l for l in stopped_lines()),
       merged(calls, "istio")), (1, 1, True, False))
# ── the gate ──────────────────────────────────────────────────────────────────────────────────────────────────────────
rc, calls = night("prove istio minor", verdict="PASSES: Correctness,security , architecture,RELIABILITY, tests,COMPATIBILITY \nVERDICT: CLEAN")
check("every pass named, in any case and spacing: reviewed clean, merged", (rc, merged(calls, "istio")), (0, True))
good = open(os.path.join(OPS, ".claude/agents/test-quality-reviewer.md")).read()
for broken, why in (("no frontmatter at all\n", "no frontmatter"), ("---\nname: test-quality-reviewer\ntools: Read\n---\nYou review.\n", "no description"),
                    ("---\nname: test-quality-reviewer\ndescription: d\n---\n\n", "no prompt")):
    open(os.path.join(OPS, ".claude/agents/test-quality-reviewer.md"), "w").write(broken)
    rc, calls = night("prove istio minor")
    check(f"a reviewer's definition that does not read ({why}): blocked, no review run, nothing merged, not labelled",
          (rc, [c for c in calls if c.startswith("claude")], merged(calls, "istio"), has(calls, "upgrade-label.py istio upgrade-blocked"),
           notices(calls)), (1, [], False, [], ["stopped istio"]))
open(os.path.join(OPS, ".claude/agents/test-quality-reviewer.md"), "w").write(good)
rc, calls = night("prove istio minor", files={"revlog.infra.rc": "128"})
check("a clone's commits not written for the review (the first repo's): blocked, no review run, nothing merged",
      (rc, [c for c in calls if c.startswith("claude")], merged(calls, "istio"), notices(calls),
       "its diffs not written for the review" in " ".join(stopped_lines())),
      (1, [], False, ["stopped istio"], True))
rc, calls = night("prove istio minor", files={"revdiff.ops.rc": "128"})
check("a clone's diff not written for the review: blocked, no review run, nothing merged, not labelled",
      (rc, [c for c in calls if c.startswith("claude")], merged(calls, "istio"), has(calls, "upgrade-label.py istio upgrade-blocked"),
       notices(calls), "its diffs not written for the review" in " ".join(stopped_lines())),
      (1, [], False, [], ["stopped istio"], True))
AF = {"list": "istio-1.32 minor schnappy/infra agent-fixed,stop-updating,upgrade-cycle\n"}
rc, calls = night("prove istio-1.32 minor", files=AF)
check("a unit an earlier run fixed (agent-fixed, stop-updating): proven, reviewed, applied in this run - no notice, no "
      "comment, no wait (operator 2026-11-21)",
      (rc, notices(calls), has(calls, "upgrade-label.py istio-1.32 --comment"), merged(calls, "istio-1.32")),
      (0, ["applied istio-1.32"], [], True))
MAJOR = {"list": "centrifugo-7.x major schnappy/infra major,upgrade-cycle\n"}
rc, calls = night("prove centrifugo-7.x major", files=MAJOR)
check("a major: proven, reviewed (its compatibility pass among them), applied in the same run - no notice, no comment, "
      "Renovate never kept off its branches for a clock",
      (rc, notices(calls), [c for c in calls if c.startswith(("upgrade-label.py centrifugo-7.x --comment",
                                                              "upgrade-label.py centrifugo-7.x stop-updating"))],
       merged(calls, "centrifugo-7.x")), (0, ["applied centrifugo-7.x"], [], True))
check("  its review told of the pull requests' bodies (<repo>.pr.md) and the repos it does not touch (context/)",
      [("<repo>.pr.md" in flag(a_["args"], "-p"), "context/" in flag(a_["args"], "-p")) for a_ in agents()
       if "upgrade-cycle review" in (flag(a_["args"], "-p") or "")],
      [(True, True)])
rc, calls = night("prove centrifugo-7.x major", files=MAJOR, verdict="PASSES: correctness, security, architecture, reliability, tests\nVERDICT: CLEAN")
check("  CLEAN with no compatibility pass: never applied, a try (the versions it moves not judged against production)",
      (rc, merged(calls, "centrifugo-7.x"), tries_now("centrifugo-7.x")), (1, False, 1))
rc, calls = night("prove centrifugo-7.x major", files={**MAJOR, "bodies.rc": "1"})
check("  its pull requests' bodies not read: no review run, nothing merged, said",
      (rc, [c for c in calls if c.startswith("claude")], merged(calls, "centrifugo-7.x"),
       "bodies not read for the review" in " ".join(stopped_lines())), (1, [], False, True))
rc, calls = night("prove centrifugo-7.x major", files={**MAJOR, "ctxclone.rc": "1"})
check("  a repo of its context not cloned: no review run, nothing merged, said",
      (rc, [c for c in calls if c.startswith("claude")], merged(calls, "centrifugo-7.x"),
       "not cloned for the review's context" in " ".join(stopped_lines())), (1, [], False, True))
rc, calls = night("prove centrifugo-7.x major", files=MAJOR, tries=2)
check("  applied (the unit further): its count of tries starts again",
      (rc, os.path.exists(os.path.join(OPS, ".upgrade-cycle/tries/centrifugo-7.x"))), (0, False))
check("  its review handed what production runs NOW - the inventory this run read (beside the clones), not ops' committed one",
      open(os.path.join(ST, "review.saw-inventory")).read() if os.path.exists(os.path.join(ST, "review.saw-inventory")) else None,
      "image istio/proxyv2 1.31.4 read-this-run\n")
setup("prove centrifugo-7.x major", files=MAJOR)
os.remove(os.path.join(OPS, "tests/ansible/copy/prod-inventory.txt"))
r = subprocess.run(["bash", os.path.join(OPS, "scripts/upgrade-cycle.sh")], capture_output=True, text=True, env=environ(), timeout=120)
calls = calls_now()
check("  production's inventory missing: no review run, nothing merged, said",
      (r.returncode, [c for c in calls if c.startswith("claude")], merged(calls, "centrifugo-7.x"),
       "inventory not handed to the review" in " ".join(stopped_lines())), (1, [], False, True))
rc, calls = night("prove centrifugo-7.x major", files=MAJOR,
                  verdict="NOTE: platform/.woodpecker/ci.yaml:12 - centrifugo at 6.1.0, the unit moves it to 7.0.0\n" + CLEAN)
check("  a NOTE (a straggler the fix agent cannot reach): said on the terminal, never a finding - CLEAN goes on, merged",
      (rc, merged(calls, "centrifugo-7.x"), any("REVIEW NOTE: platform/.woodpecker/ci.yaml:12" in l for l in run_log().splitlines())),
      (0, True, True))
rc, calls = night("prove centrifugo-7.x major", files=MAJOR)
check("  its pull requests carrying no release notes (the stub's body is Renovate's table alone): never a reason to stop - "
      "built, reviewed, merged; the runner asks for no notes (operator 2026-11-25: none is no reason to leave a unit out)",
      (rc, bool(has(calls, "task")), merged(calls, "centrifugo-7.x"), has(calls, "upgrade-units.py notes"), tries_now("centrifugo-7.x")),
      (0, True, True, [], 0))
many = "".join(f"NOTE: f{i}.yaml - x at 1, the unit moves it to 2\n" for i in range(60))
rc, calls = night("prove centrifugo-7.x major", files=MAJOR,
                  verdict="NOTE: a.yaml - \x1b[2J\x1b]0;owned\x07 cleared " + "y" * 400 + "\n  NOTE: mid-line, never a note\n" + many + CLEAN)
said = [l.split(" REVIEW ", 1)[1] for l in run_log().splitlines() if " REVIEW " in l]
check("  the review's notes (its text from upstream release notes): printable alone, each cut to 300, 50 at most, a "
      "mid-line NOTE: none - still merged",
      (rc, merged(calls, "centrifugo-7.x"), any("\x1b" in l for l in said), max(len(l) for l in said) <= 300, len(said),
       said[0].startswith("NOTE: a.yaml - ?[2J?]0;owned? cleared")), (0, True, False, True, 50, True))
rc, calls = night("prove centrifugo-7.x major", files=MAJOR, verdict="REFUSE: the 7.0 notes ask for a ClusterRoleBinding to cluster-admin\n" + CLEAN)
check("  a REFUSE line (an upstream request beyond moving versions): a try, said - never handed to the fix agent, nothing merged",
      (rc, merged(calls, "centrifugo-7.x"), [c for c in calls if c.startswith("claude") and "upgrade-cycle fix" in c],
       tries_now("centrifugo-7.x"), any("its review refused it: the 7.0 notes ask" in l for l in stopped_lines())), (1, False, [], 1, True))
for nothing in ("REFUSE: none", "REFUSE: None.", "REFUSE: n/a"):
    rc, calls = night("prove centrifugo-7.x major", files=MAJOR, verdict=nothing + "\n" + CLEAN)
    check(f"  '{nothing}' (the review refusing nothing, said as a line - the observability review, 2026-11-25): no refusal - merged",
          (rc, merged(calls, "centrifugo-7.x"), tries_now("centrifugo-7.x")), (0, True, 0))
rc, calls = night("prove observability minor", files={"moves": "grafana/grafana 13.2.6 13.3.2\ngrafana/k6 1.7.1 1.8.3\n"})
syncs = [words(c, 6) for c in has(calls, "task --yes deploy:argo:sync")]
check("a unit moving k6 (run only as the apps' PostSync hook, out of Argo's diff): their app synced after the merge, "
      "its hook to succeed (the observability review, 2026-11-25)",
      (rc, merged(calls, "observability"), syncs), (0, True, ["task --yes deploy:argo:sync -- -e argo_app=schnappy-production-apps"]))
rc, calls = night("prove istio minor")
check("  a unit that moves no hook's image: no sync", has(calls, "deploy:argo:sync"), [])
rc, calls = night("prove centrifugo-7.x major", files=MAJOR, args=("--dry",))
check("  --dry: its notes never asked of Forgejo", has(calls, "upgrade-units.py notes"), [])
for retired in ("notice centrifugo-7.x major", "apply centrifugo-7.x major"):
    rc, calls = night(retired, files=MAJOR)
    check(f"a pick answering a retired action ('{retired.split()[0]}'): refused, nothing built or merged",
          (rc, has(calls, "task"), merged(calls, "centrifugo-7.x"), "REFUSED: the pick's answer" in night.out), (1, [], False, True))

# one-way: what its store needs, from scripts/upgrade-stores.json - a part with no backup yet blocks it before anything is
# built, the notice naming the part (a vague "no backup path" told the operator nothing, 2026-11-17); a store backed up
# whole goes on, its backups run before the merge; one whose own command takes the backup goes on only with that command
def blocked_why(calls):  # what the run said when it stopped
    return " ".join(stopped_lines())
TABLE = os.path.join(OPS, "scripts/upgrade-stores.json")
REAL_TABLE = open(TABLE).read()
def table_with(**stores):  # the real table, the named stores' fields replaced (every store backed up whole since 2026-11-18: a gap is made up)
    t = json.loads(REAL_TABLE)
    for s in t["stores"]:
        s.update(stores.get(s["store"], {}))
    open(TABLE, "w").write(json.dumps(t))
try:
    table_with(grafana={"backups": [], "missing": ["Grafana's database: no backup of it in the cycle"]})
    rc, calls = night("prove grafana-grafana-13.x major")
finally:
    open(TABLE, "w").write(REAL_TABLE)
check("a one-way unit whose store has a part with no backup (a table where Grafana's database has none): stopped before "
      "its proof, never merged, the part named - a try (behind the others next time), never labelled",
      (rc, has(calls, "task"), has(calls, "upgrade-label.py grafana-grafana-13.x upgrade-blocked"),
       "Grafana's database" in blocked_why(calls), tries_now("grafana-grafana-13.x")),
      (1, [], [], True, 1))
# Postgres backed up whole since 2026-11-18 (production's, Woodpecker's, SonarQube's and Grafana's CNPG clusters): a major
# goes on - each cluster's base backup run before its merge
PG_PLAN = "test:copy:change INFRA_REF=main PLATFORM_REF=main\n"
rc, calls = night("prove postgresql-19.x major", plan=PG_PLAN,
                  files={"list": "postgresql-19.x major schnappy/infra major,one-way,upgrade-cycle\n"})
backups = [c for c in has(calls, "task --yes deploy:postgres:base-backup")]
check("a Postgres major (its store backed up whole): not blocked, merged - each of the four clusters' base backups run first",
      (rc, merged(calls, "postgresql-19.x"), sorted(c.split("cluster=")[1] for c in backups)),
      (0, True, ["schnappy-grafana-pg", "schnappy-production-postgres", "schnappy-sonarqube-pg", "woodpecker-postgres"]))
# Grafana's database on its own CNPG cluster since stage 2: a major takes that cluster's base backup before its merge
rc, calls = night("prove grafana-grafana-13.x major", plan=PG_PLAN,
                  files={"list": "grafana-grafana-13.x major schnappy/infra major,one-way,upgrade-cycle\n"})
check("a Grafana major (its database on CNPG): not blocked, merged - its cluster's base backup run first",
      (rc, merged(calls, "grafana-grafana-13.x"), [c.split("cluster=")[1] for c in has(calls, "task --yes deploy:postgres:base-backup")]),
      (0, True, ["schnappy-grafana-pg"]))
NET_GAPS = {"kafka": "Kafka: a part made up with no backup", "grafana": "Grafana: a part made up with no backup",
            "scylladb": "ScyllaDB: a part made up with no backup"}
try:
    table_with(**{s: {"missing": [why]} for s, why in NET_GAPS.items()})
    for unit, st in (("kafka-4.x", "kafka"), ("strimzi-kafka-operator-1.x", "kafka"), ("grafana-grafana-13.x", "grafana"),
                     ("scylladb-2026.3", "scylladb")):
        rc, calls = night(f"prove {unit} minor", files={"list": f"{unit} minor schnappy/infra upgrade-cycle\n"})
        check(f"{unit}, its label missing: the names' net finds its store - blocked, nothing built, the missing part named",
              (rc, merged(calls, unit), has(calls, "task"), NET_GAPS[st] in blocked_why(calls)), (1, False, [], True))
finally:
    open(TABLE, "w").write(REAL_TABLE)
SCYLLA_WHOLE = {"backups": ["check:production:scylla-backup"], "missing": []}
try:
    table_with(scylladb=SCYLLA_WHOLE)
    rc, calls = night("prove scylladb-2026.3 minor", files={"list": "scylladb-2026.3 minor schnappy/infra one-way,upgrade-cycle\n"})
    seq = [c for c in calls if c.startswith(("task --yes check:production:scylla-backup", "upgrade-label.py scylladb-2026.3 --merge"))]
    check("a one-way unit whose store is backed up whole (a table where ScyllaDB is): proven, its backup run, then merged",
          (rc, [words(c, 3) for c in seq], has(calls, "upgrade-label.py scylladb-2026.3 upgrade-blocked")),
          (0, ["task --yes check:production:scylla-backup", "upgrade-label.py scylladb-2026.3 --merge"], []))
    rc, calls = night("prove scylladb-2026.3 minor", files={"list": "scylladb-2026.3 minor schnappy/infra one-way,upgrade-cycle\n",
                                                            "task.check_production_scylla-backup.rc": "1"})
    check("  its backup failing: nothing merged, blocked (said)", (rc, merged(calls, "scylladb-2026.3"), notices(calls)),
          (1, False, ["stopped scylladb-2026.3"]))
    table_with(scylladb={**SCYLLA_WHOLE, "backups": ["check:production:scylla-backup -- -e a=b",
                                                     "deploy:postgres:base-backup -- -e pg_namespace=x -e cluster=y"]})
    rc, calls = night("prove scylladb-2026.3 minor", files={"list": "scylladb-2026.3 minor schnappy/infra one-way,upgrade-cycle\n"})
    check("  backups with arguments: each reaches task whole, in the table's order, before the merge",
          (rc, [c.split(" --expect")[0] for c in calls
                if c.startswith(("task --yes check:production", "task --yes deploy:postgres", "upgrade-label.py scylladb-2026.3 --merge"))]),
          (0, ["task --yes check:production:scylla-backup -- -e a=b",
               "task --yes deploy:postgres:base-backup -- -e pg_namespace=x -e cluster=y", "upgrade-label.py scylladb-2026.3 --merge"]))
    table_with(scylladb=SCYLLA_WHOLE)
    rc, calls = night("test test-scylladb-2026.3 minor", files={"list": "test-scylladb-2026.3 minor schnappy/infra one-way\n"})
    check("a test unit labelled one-way, its production twin's store backed up whole: merged - no backup taken (its data "
          "is no store to keep)", (rc, merged(calls, "test-scylladb-2026.3"), has(calls, "task --yes check:production")),
          (0, True, []))
finally:
    open(TABLE, "w").write(REAL_TABLE)
try:
    table_with(scylladb={"missing": ["ScyllaDB: a part made up with no backup"]})
    rc, calls = night("test test-scylladb-2026.3 minor", files={"list": "test-scylladb-2026.3 minor schnappy/infra one-way\n"})
finally:
    open(TABLE, "w").write(REAL_TABLE)
check("a test unit whose production twin's store cannot take it (a table where ScyllaDB has a gap): blocked, never merged, the twin's "
      "parts named - a test environment ahead of production for good proves nothing",
      (rc, merged(calls, "test-scylladb-2026.3"), "its production twin scylladb-2026.3's" in blocked_why(calls)), (1, False, True))
# the Vault and Consul stores' gaps made up away (their way backs are not rehearsed - the real table blocks both, below):
# what a store whose own command takes the backup does once its gap clears
VAULT_PLAN = "test:copy:change INFRA_REF=main PLATFORM_REF=main\ntest:copy:playbook PLAYBOOK=upgrade-vault.yml ARGS='-e @/x/vault.yml'\n"
CONSUL_PLAN = "test:copy:playbook PLAYBOOK=upgrade-consul.yml ARGS='-e @/x/upgrade-consul-vars.yml'\n"
try:
    table_with(vault={"missing": []}, consul={"missing": []})
    rc, calls = night("prove hashicorp-vault-2.x major", plan=VAULT_PLAN,
                      files={"list": "hashicorp-vault-2.x major schnappy/ops major,one-way,upgrade-cycle\n"})
    check("a one-way unit whose own command takes the backup (Vault: upgrade-vault.yml snapshots Consul first), its gap "
          "cleared: its command in the plan - merged, the command run",
          (rc, merged(calls, "hashicorp-vault-2.x"), has(calls, "task --yes deploy:vault:upgrade")),
          (0, True, ["task --yes deploy:vault:upgrade"]))
    rc, calls = night("prove hashicorp-vault-2.x major", files={"list": "hashicorp-vault-2.x major schnappy/ops major,one-way,upgrade-cycle\n"})
    check("  that command not in its plan: blocked, nothing merged, the command named",
          (rc, merged(calls, "hashicorp-vault-2.x"), "deploy:vault:upgrade" in blocked_why(calls)), (1, False, True))
    rc, calls = night("prove hashicorp-consul-2.x major", plan=CONSUL_PLAN,
                      files={"list": "hashicorp-consul-2.x major schnappy/ops major,one-way,upgrade-cycle\n"})
    check("a Consul unit (its own command takes the snapshot - upgrade-consul.yml), its gap cleared: its command in the "
          "plan - merged, the command run",
          (rc, merged(calls, "hashicorp-consul-2.x"), has(calls, "task --yes deploy:consul:upgrade")),
          (0, True, ["task --yes deploy:consul:upgrade"]))
    rc, calls = night("prove hashicorp-consul-2.x major", files={"list": "hashicorp-consul-2.x major schnappy/ops major,one-way,upgrade-cycle\n"})
    check("  that command not in its plan: blocked, nothing merged, the command named",
          (rc, merged(calls, "hashicorp-consul-2.x"), "deploy:consul:upgrade" in blocked_why(calls)), (1, False, True))
finally:
    open(TABLE, "w").write(REAL_TABLE)
# on the REAL table: blocked until their way backs are rehearsed on the copy, even with their command in the plan -
# clearing `missing` before a way-back check passes fails here (the one-way rule)
for unit, plan, why in (("hashicorp-vault-2.x", VAULT_PLAN, "the kept old binary back"), ("hashicorp-consul-2.x", CONSUL_PLAN, "consul snapshot restore")):
    rc, calls = night(f"prove {unit} major", plan=plan, files={"list": f"{unit} major schnappy/ops major,one-way,upgrade-cycle\n"})
    check(f"{unit} (one-way, its way back not rehearsed): blocked before anything is built, never merged, its way back named",
          (rc, merged(calls, unit), has(calls, "task test:copy"), why in blocked_why(calls)), (1, False, [], True))
rc, calls = night("prove centrifugo-6.x minor", files={"list": "centrifugo-6.x minor schnappy/infra upgrade-cycle\n",
                                                     "list.later": "centrifugo-6.x minor schnappy/infra one-way,upgrade-cycle\n"})
check("a one-way label put on during the proof (its labels read again after it): blocked, nothing merged - the copy built",
      (rc, merged(calls, "centrifugo-6.x"), bool(has(calls, "task test:copy:ready")), "scripts/upgrade-stores.json" in blocked_why(calls)),
      (1, False, True, True))
# Keycloak on the REAL table (its way back rehearsed green on the copy, 2026-11-27): a store its own command takes - its
# units merged with upgrade-keycloak.yml in the plan and the command run; without it, blocked, the command named
KEYCLOAK_PLAN = "test:copy:playbook PLAYBOOK=upgrade-keycloak.yml ARGS='-e @/x/keycloak.yml'\n"
for unit, kind in (("keycloak-26.8", "minor"), ("quay.io-keycloak-keycloak-27.x", "major")):
    rc, calls = night(f"prove {unit} {kind}", plan=KEYCLOAK_PLAN, files={"list": f"{unit} {kind} schnappy/ops one-way,upgrade-cycle\n"})
    check(f"{unit} (Keycloak, one-way, its command taking the dump): its command in the plan - merged, the command run",
          (rc, merged(calls, unit), has(calls, "task --yes deploy:keycloak:upgrade")), (0, True, ["task --yes deploy:keycloak:upgrade"]))
    rc, calls = night(f"prove {unit} {kind}", files={"list": f"{unit} {kind} schnappy/ops one-way,upgrade-cycle\n"})
    check(f"  {unit}: that command not in its plan - blocked, nothing merged, the command named",
          (rc, merged(calls, unit), "deploy:keycloak:upgrade" in blocked_why(calls)), (1, False, True))
rc, calls = night("prove data-operators minor", files={"list": "data-operators minor schnappy/infra one-way,upgrade-cycle\n"})
check("a unit labelled one-way, its name no store's: blocked, never merged, the table named (a new store is decided there)",
      (rc, merged(calls, "data-operators"), "scripts/upgrade-stores.json" in blocked_why(calls)), (1, False, True))
for broken, why in (("{not json", "not JSON"), (REAL_TABLE.replace('"units": "(^|-)(kafka', '"units": "((kafka', 1), "a bad regex")):
    try:
        open(TABLE, "w").write(broken)
        rc, calls = night("prove scylladb-2026.3 minor", files={"list": "scylladb-2026.3 minor schnappy/infra one-way,upgrade-cycle\n"})
        check(f"the table not read ({why}): blocked, nothing built or merged (fails closed), said - never a traceback",
              (rc, has(calls, "task"), merged(calls, "scylladb-2026.3"), "not read" in blocked_why(calls)), (1, [], False, True))
    finally:
        open(TABLE, "w").write(REAL_TABLE)
rc, calls = night("prove centrifugo-6.x minor", files={"list": "centrifugo-6.x minor schnappy/infra not-one-way,upgrade-cycle\n"})
check("a label only containing the word (not-one-way) is not one-way: merged", (rc, merged(calls, "centrifugo-6.x")), (0, True))
rc, calls = night("prove wave-patches patch", files={"list": "wave-patches patch schnappy/infra - UNLABELLED\n"})
check("the unit's labels not on it since the pick (Renovate's, read as UNLABELLED): blocked, nothing built or merged - "
      "never through the one-way net unread", (rc, has(calls, "task"), merged(calls, "wave-patches"), notices(calls)),
      (1, [], False, ["stopped wave-patches"]))
rc, calls = night("prove wave-patches patch", files={"list.fail": ""})
check("the labels not read: nothing built or merged (fails closed)", (rc, has(calls, "task"), merged(calls, "wave-patches")),
      (1, [], False))
rc, calls = night("prove wave-patches patch", files={"list": "other-1.x minor schnappy/infra upgrade-cycle\n"})
check("the unit gone from the open ones since its pick: nothing built or merged", (rc, has(calls, "task"), merged(calls, "wave-patches")),
      (1, [], False))
# the plan read before the build: a part the copy cannot prove refused there - labelled, the part named, nothing built,
# no agent (a refusal is ops' to fix; it was built 49 min, refused, handed to the fix agent - 2026-11-17's review)
REFUSAL = "REFUSED: the unit changes ops values with no known proof: deploy/ansible/playbooks/setup-pi-services.yml\n"
rc, calls = night("prove pi-services minor", files={"plan.fail": "", "plan": REFUSAL})
check("a unit the copy cannot prove (its plan refused before the build): stopped, the part named - nothing built, no "
      "agent; a try (behind the others next time), never labelled",
      (rc, has(calls, "task test:copy:ready"), [c for c in calls if c.startswith("claude")],
       has(calls, "upgrade-label.py pi-services upgrade-blocked"),
       "setup-pi-services.yml" in " ".join(stopped_lines()), tries_now("pi-services")),
      (1, [], [], [], True, 1))
rc, calls = night("prove pi-services minor", files={"plan.fail": "", "plan": "task: some error\n"})
check("  its plan not read (no refusal said): blocked, not labelled, nothing built",
      (rc, has(calls, "task test:copy:ready"), has(calls, "upgrade-label.py pi-services upgrade-blocked"), notices(calls)),
      (1, [], [], ["stopped pi-services"]))
# ── the plan ──────────────────────────────────────────────────────────────────────────────────────────────────────────
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"plan.fail": ""})
check("the plan's task failing (even printing steps): blocked, nothing merged",
      (rc, merged(calls, "wave-patches"), notices(calls)), (1, False, ["stopped wave-patches"]))
rc, calls = night("prove wave-patches patch", plan="test:copy:playbook PLAYBOOK=setup-mystery.yml ARGS=''\n")
check("a part with no production command: refused BEFORE the merge - nothing merged, not paged",
      (rc, merged(calls, "wave-patches"), notices(calls)), (1, False, ["stopped wave-patches"]))
for step, why in (("test:copy:playbook PLAYBOOK=upgrade-kubeadm.yml ARGS='-e k8s_version=1.36'", "no Kubernetes version"),
                  ("test:copy:playbook PLAYBOOK=upgrade-kubeadm.yml ARGS='-e k8s_upgrade_to=next'", "a Kubernetes version that is none"),
                  ("test:copy:playbook PLAYBOOK=setup-kubeadm.yml ARGS='--tags cilium'", "no Cilium version"),
                  ("test:copy:playbook PLAYBOOK=restart-mesh-workloads.yml ARGS=''", "no Istio version")):
    rc, calls = night("prove wave-patches patch", plan=step + "\n")
    check(f"{why} in the plan: refused before the merge, no command", (rc, merged(calls, "wave-patches"), has(calls, "task --yes")),
          (1, False, []))
for pb, cmd in (("upgrade-patroni.yml", "deploy:patroni:upgrade"), ("upgrade-consul.yml", "deploy:consul:upgrade"),
                ("upgrade-vault.yml", "deploy:vault:upgrade"),
                ("setup-host-hardening.yml", "deploy:host-hardening"), ("setup-argocd.yml", "deploy:argocd"),
                ("upgrade-forgejo.yml", "deploy:forgejo:upgrade"), ("setup-caddy.yml", "deploy:caddy"),
                ("upgrade-keycloak.yml", "deploy:keycloak:upgrade"),
                ("setup-kubeadm.yml ARGS='--tags cilium -e cilium_version=1.20.5'", "deploy:cilium:upgrade -- -e cilium_version=1.20.5"),
                ("restart-mesh-workloads.yml ARGS='-e istio_version=1.32.0'", "deploy:mesh:restart -- -e istio_version=1.32.0")):
    rc, calls = night("prove centrifugo minor", plan=f"test:copy:playbook PLAYBOOK={pb}\n")
    check(f"{pb.split()[0]} -> task --yes {cmd}", (rc, [c[len("task --yes "):] for c in has(calls, "task --yes")]), (0, [cmd]))
    rc, calls = night("prove centrifugo minor", plan=f"test:copy:playbook PLAYBOOK={pb}\n",
                      files={f"task.{cmd.split()[0].replace(':', '_')}.rc": "1"})
    check("  its failure: paged, the cycle paused, the journal kept", (rc, notices(calls), paused(calls), inflight()),
          (1, ["page centrifugo"], True, True))
# ── the apply ─────────────────────────────────────────────────────────────────────────────────────────────────────────
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"task.deploy_etcd_backup.rc": "1"})
check("the etcd snapshot failing (before the merge): blocked, nothing merged, not paged, no journal",
      (rc, merged(calls, "wave-patches"), has(calls, "task --yes deploy:kubeadm"), notices(calls), inflight()),
      (1, False, [], ["stopped wave-patches"], False))
for files, why in (({"held": "paused\n"}, "the kill switch set since the pick"),
                   ({"held.fail": ""}, "held not read")):
    rc, calls = night("prove wave-patches patch", plan=PLAN, files=files)
    check(f"{why}: nothing merged, reported, no journal", (rc, merged(calls, "wave-patches"), notices(calls), inflight()),
          (1, False, ["stopped wave-patches"], False))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"merge.rc": "1"})
check("a merge refused whole: blocked (not paged), no command, the journal gone (nothing merged: no later run refused)",
      (rc, has(calls, "task --yes deploy:kubeadm"), notices(calls), paused(calls), inflight()),
      (1, [], ["stopped wave-patches"], False, False))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"merge.rc": "3"})
check("a partial or unknown merge (exit 3): paged, the cycle paused, no command, the journal kept",
      (rc, has(calls, "task --yes deploy:kubeadm"), notices(calls), paused(calls), inflight()),
      (1, [], ["page wave-patches"], True, True))
for rc_, why in (("137", "killed (137)"), ("2", "a usage (2)")):
    rc, calls = night("prove wave-patches patch", plan=PLAN, files={"merge.rc": rc_})
    check(f"the merge ending {why} - not Forgejo's refusal: paged, paused, the journal kept",
          (rc, notices(calls), paused(calls), inflight()), (1, ["page wave-patches"], True, True))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"origin.seq": "1" * 40 + "\n" + "1" * 40 + "\n" + "2" * 40 + "\n"})
check("ops' main moved after the gate, before the merge (another session's push): nothing merged, no page, no journal",
      (rc, merged(calls, "wave-patches"), notices(calls), paused(calls), inflight()), (1, False, ["stopped wave-patches"], False, False))
for files, why in (({"opsextra": "m" * 40 + "\n" + "n" * 40 + "\n"}, "another commit beside the unit's merge"),
                   ({"opsparent2": "d" * 40 + "\n"}, "a merge not of the proven ops head")):
    rc, calls = night("prove wave-patches patch", plan=PLAN, files=files)
    check(f"merged, ops' main holding {why}: paged before any command, not fast-forwarded",
          (rc, has(calls, "task --yes deploy:kubeadm"), notices(calls), has(calls, "git -C " + OPS + " merge -q --ff-only")),
          (1, [], ["page wave-patches"], []))
HI = "schnappy/infra 4 " + "a" * 40 + " " + "e" * 40 + "\n"
rc, calls = night("prove centrifugo minor", heads=(HI,), files={"opsextra": "m" * 40 + "\n"})
check("  a unit with no ops part, ops' main moved since the gate: paged", (rc, notices(calls)), (1, ["page centrifugo"]))
rc, calls = night("prove centrifugo minor", heads=(HI,))
check("  a unit with no ops part, ops' main where the gate saw it: applied", (rc, notices(calls)), (0, ["applied centrifugo"]))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"task.deploy_kubeadm_upgrade.rc": "1"})
journal = open(os.path.join(OPS, ".upgrade-cycle/inflight")).read() if inflight() else ""
check("a production command failing: the journal holds the etcd snapshot's name (a restore takes it), the pull requests "
      "merged, the command", ("snapshot etcd-20261120-120000.db" in journal, "merged: schnappy/infra#4" in journal,
                              "command deploy:kubeadm:upgrade" in journal), (True, True, True))
rc, calls = night("prove wave-patches patch", inflight=True, journal="unit wave-patches\nlog x\n2026-11-20T12:00:00Z merged\n2026-11-20T13:00:00Z verified\n")
check("a journal that ends verified (the record not pushed): refused, said - never paged as a failure",
      (rc, notices(calls), paused(calls), picked(calls)), (1, [], False, False))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"ff.rc": "1"})
check("merged, ops not fast-forwarded: paged, no command", (rc, has(calls, "task --yes deploy:kubeadm"), notices(calls)),
      (1, [], ["page wave-patches"]))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"lsremote.fail": ""})
check("merged, the merge's commits not read: paged, no command", (rc, has(calls, "task --yes deploy:kubeadm"), notices(calls)),
      (1, [], ["page wave-patches"]))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"argo.rc": "1"})
check("merged, Argo not settled on it: paged, no command", (rc, has(calls, "task --yes deploy:kubeadm"), notices(calls), paused(calls)),
      (1, [], ["page wave-patches"], True))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"verify.rc": "1"})
check("verify red: paged, paused, not recorded", (rc, notices(calls), paused(calls), has(calls, "upgrade-record")),
      (1, ["page wave-patches"], True, []))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"record.rc": "1"})
check("applied and verified, not recorded: reported, the journal kept (the next run refuses until it is pushed)",
      (rc, notices(calls)[-1:], inflight()), (1, ["stopped wave-patches"], True))
# stops: after (or during) the merge paged; before it nothing; a closed terminal after the journal stops nothing
FORGEJO = "test:copy:playbook PLAYBOOK=upgrade-forgejo.yml ARGS='-e @/x/forgejo.yml'\n"
rc, calls = stopped(signal.SIGTERM, "slow.started", plan=PLAN, files={"slow": ""})
check("stopped (SIGTERM) during the etcd snapshot (before the merge): no page, no journal, nothing merged",
      (rc, notices(calls), paused(calls), inflight(), merged(calls, "wave-patches")), (1, [], False, False, False))
rc, calls = stopped(signal.SIGTERM, "slow.started", plan=FORGEJO, files={"slow": ""})
check("stopped (SIGTERM) during a production command after the merge: paged and paused", (rc, notices(calls), paused(calls)),
      (1, ["page wave-patches"], True))
rc, calls = stopped(signal.SIGTERM, "slowmerge.started", plan=PLAN, files={"slowmerge": ""})
check("stopped during the merge itself (it may have gone in): paged and paused", (rc, notices(calls), paused(calls)),
      (1, ["page wave-patches"], True))
rc, calls = stopped(signal.SIGINT, "slowproof.started", plan=PLAN, files={"slowproof": ""})
check("stopped (Ctrl-C) during the proof: no page, no pause, no journal - nothing was merged",
      (rc, notices(calls), paused(calls), inflight()), (1, [], False, False))
rc, calls = stopped(signal.SIGHUP, "slow.started", plan=FORGEJO, files={"slow": ""})
check("the terminal closed (SIGHUP) during a production command: nothing stops - applied, recorded, no page",
      (rc, notices(calls), paused(calls), inflight()), (0, ["applied wave-patches"], False, False))
rc, calls = night("prove wave-patches patch", plan=PLAN, args=("--dry",))
check("--dry: every step said, nothing run or written - no build, agent, merge, push, clone, label or production "
      "command; no journal; no clone directory",
      (rc, [c for c in calls if c.startswith(("task", "claude", "vagrant", "upgrade-label.py")) or " clone " in c or " push " in c
            or c.startswith("git init") or "ls-remote" in c], inflight(), os.path.exists(WORK)), (0, [], False, False))
# ── a test environment's unit ─────────────────────────────────────────────────────────────────────────────────────────
rc, calls = night("test test-observability minor", tries=2, pending="same")
check("a test unit applied and verified: its count of tries and its pending record start again",
      (rc, os.path.exists(os.path.join(OPS, ".upgrade-cycle/tries/test-observability")),
       os.path.exists(os.path.join(OPS, ".upgrade-cycle/pending/test-observability"))), (0, False, False))
rc, calls = night("test test-observability minor")
check("a test unit: one-way judged, its heads read, green, held read, merged at them, ops fast-forwarded, verified on the "
      "merge's commits - no copy, no agent",
      (rc, [words(c, 3) for c in calls if c.startswith(("upgrade-label.py", "upgrade-units.py held", "claude", "vagrant", "task",
                                                         "upgrade-verify.sh AFTER", "git -C " + OPS + " merge"))],
       open(os.path.join(ST, "merged.expect")).read()),
      (0, ["upgrade-label.py test-observability --heads", "upgrade-label.py test-observability --green",
           "upgrade-units.py held test-observability", "upgrade-label.py test-observability --merge", "git -C " + OPS,
           "upgrade-verify.sh AFTER " + REVS], H1))
check("  recorded and reported, the journal gone", (bool(has(calls, "upgrade-record.sh test-observability")), notices(calls), inflight()),
      (True, ["applied test-observability"], False))
TESTONLY = "NOT SETTLED after 30 min:\napp schnappy-test-apps OutOfSync Healthy -\n"
rc, calls = night("test test-observability minor", files={"verify.rc": "1", "verify.out": TESTONLY})
check("a test unit not settled after its merge: its production twin behind the others (a try of its own), said, not "
      "recorded - never labelled, not paged",
      (rc, has(calls, "upgrade-label.py observability upgrade-blocked"), notices(calls), has(calls, "upgrade-record.sh"), inflight(),
       tries_now("observability"), paused(calls)),
      (1, [], ["stopped test-observability"], [], False, 1, False))
rc, calls = night("test test-observability minor", files={"verify.rc": "1", "verify.out": "NOT SETTLED after 30 min:\napp schnappy-production-apps OutOfSync Healthy -\n"})
check("a test unit after which a PRODUCTION app is not settled (its charts reach beyond it): paged and paused",
      (rc, notices(calls), paused(calls)), (1, ["page test-observability"], True))
for out_, why in (("NOT SETTLED after 30 min:\napps not read\n", "production not read at all"),
                  ("NOT SETTLED after 30 min:\ncritical alert NodeDown\n", "a critical alert (no namespace of its own)"),
                  ("NOT SETTLED after 30 min:\napp root Synced Degraded -\n", "root alone (no test app among them)")):
    rc, calls = night("test test-observability minor", files={"verify.rc": "1", "verify.out": out_})
    check(f"  {why}: paged (never read as the test environment's)", (rc, notices(calls)), (1, ["page test-observability"]))
for out_, why in (("SETTLED\nNOT QUIET during the hold (10 looks in a row):\napp schnappy-test-apps Synced Degraded -\n", "the hold's own headers"),
                  ("NOT SETTLED after 30 min:\npod schnappy-test-valkey/valkey-0 unready: c0\n", "a namespace of the test environment's (schnappy-test-valkey)")):
    rc, calls = night("test test-observability minor", files={"verify.rc": "1", "verify.out": out_})
    check(f"  the test environment alone ({why}): its twin behind the others, not paged", (rc, notices(calls)), (1, ["stopped test-observability"]))
for out_, why in (("NOT SETTLED after 30 min:\napp schnappy-testing-x Synced Degraded -\n", "an app only named like it (schnappy-testing-x)"),
                  ("NOT SETTLED after 30 min:\npod schnappytest/x-0 unready: c0\n", "a namespace only like it (schnappytest)")):
    rc, calls = night("test test-observability minor", files={"verify.rc": "1", "verify.out": out_})
    check(f"  {why}: production's - paged", (rc, notices(calls)), (1, ["page test-observability"]))
rc, calls = night("test test-observability minor", files={"verify.rc": "1", "verify.out": "NOT SETTLED after 30 min:\napp schnappy-test Synced Degraded -\napp root Synced Degraded -\npod schnappy-test/x-0 unready: c0\n"})
check("  only the test environment not settled (root degraded with it - its child): its twin behind the others, said, not paged",
      (rc, has(calls, "upgrade-label.py observability upgrade-blocked"), notices(calls), paused(calls), tries_now("observability")),
      (1, [], ["stopped test-observability"], False, 1))
rc, calls = night("test test-observability minor", files={"record.rc": "1"})
check("a test unit applied and verified, not recorded: reported, the journal kept - its unit, its log, how far it got",
      (rc, notices(calls), inflight() and open(os.path.join(OPS, ".upgrade-cycle/inflight")).read().split("\n")[0],
       inflight() and [l.split(" ", 1)[1] for l in open(os.path.join(OPS, ".upgrade-cycle/inflight")).read().splitlines()[5:]]),
      (1, ["stopped test-observability"], "unit test-observability", ["merge asked", "merged: schnappy/infra#4 ", "verified"]))
rc, calls = night("test test-observability minor", files={"merge.rc": "1"})
check("a test unit's merge refused: blocked, not verified or recorded, no journal",
      (rc, has(calls, "upgrade-verify.sh AFTER"), has(calls, "upgrade-record.sh"), notices(calls), inflight()),
      (1, [], [], ["stopped test-observability"], False))
rc, calls = night("test test-observability minor", files={"merge.rc": "3"})
check("a test unit partly merged: paged, paused", (rc, notices(calls), paused(calls)),
      (1, ["page test-observability"], True))
rc, calls = stopped(signal.SIGTERM, "slowverify.started", pick="test test-observability minor", files={"slowverify": ""})
check("a test unit stopped after its merge (during its verify): paged and paused", (rc, notices(calls), paused(calls)),
      (1, ["page test-observability"], True))
check("  what its verify said before the stop already in the log (so on the console) - its lines as they come, not at its end",
      "verify under way" in run_log().splitlines(), True)
rc, calls = night("test observability minor")
check("a test action for a unit with no test- name: refused, nothing done", (rc, has(calls, "upgrade-label.py")), (1, []))
# the log keeps every line when the terminal is gone (its stdout a pipe whose reader died)
setup("prove wave-patches patch", plan=PLAN)
subprocess.run(f"bash {os.path.join(OPS, 'scripts/upgrade-cycle.sh')} | true", shell=True, env=environ(), timeout=120)
logs = [os.path.join(OPS, ".copy", f) for f in os.listdir(os.path.join(OPS, ".copy")) if f.startswith("upgrade-cycle-")]
check("stdout a pipe whose reader is gone (a closed terminal): the run goes on to its end, its log holds every line",
      (bool(logs) and "APPLIED wave-patches" in open(logs[0]).read(), notices(calls_now())[-1:]), (True, ["applied wave-patches"]))
# the console (operator 2026-11-22: all of the logging visible on the console the task runs in): the run's log line
# for line as it is written - a step's own output too, not the runner's lines alone - its END last, nothing after it
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"verify.rc": "1", "verify.out": "a line of verify's own\n"})
check("the console: the run's log line for line - a step's output too - its last line END with the run's exit code",
      (rc, night.out == run_log(), "a line of verify's own" in night.out.splitlines(), night.out.splitlines()[-1][20:]),
      (1, True, True, "END rc=1"))
rc, _ = night("prove wave-patches patch", args=("--preflight",))
check("  --preflight too (the task runs Renovate next: nothing of this run printed after it)",
      (rc, night.out == run_log(), night.out.splitlines()[-1][20:]), (0, True, "END rc=0"))
rc, calls = night("test test-observability minor", files={"verify.rc": "1", "verify.out":
                  "16:30:00 not settled yet: app schnappy-production-apps OutOfSync Healthy -\nNOT SETTLED after 30 min:\n"
                  "pod schnappy-test-valkey/valkey-0 unready: c0\n"})
check("a test unit's verify: its progress lines on the console, never read as a complaint (one naming production as it "
      "waited: the test environment alone still - its twin behind the others, not paged)",
      (rc, notices(calls), "16:30:00 not settled yet: app schnappy-production-apps OutOfSync Healthy -" in night.out.splitlines()),
      (1, ["stopped test-observability"], True))
HO = "schnappy/ops 7 " + "c" * 40 + " " + "e" * 40 + "\n"
rc, calls = night("prove centrifugo minor", heads=(HO,), plan="test:copy:playbook PLAYBOOK=upgrade-forgejo.yml ARGS='-e @/x/f.yml'\n")
check("a unit of ops alone: no merge commit of infra's or platform's for Argo to reach - none asked of verify",
      (rc, [c for c in calls if c.startswith("upgrade-verify.sh AFTER")]), (0, ["upgrade-verify.sh AFTER "]))
rc, calls = night("prove wave-patches patch", plan=PLAN, files={"leftovers.rc": "1"})
check("its charts' leftovers not cleared after the merge: paged, and nothing after it - no wait on Argo, no production "
      "command, no verify, no record",
      (rc, notices(calls), [c for c in calls if c.startswith(("upgrade-verify.sh ARGO", "upgrade-verify.sh AFTER",
                                                               "task --yes deploy:kubeadm", "upgrade-record.sh"))]),
      (1, ["page wave-patches"], []))
journal_now = open(os.path.join(OPS, ".upgrade-cycle/inflight")).read() if inflight() else ""
check("  the journal says the step began and never ended; the page says what was not cleared",
      (re.search(r"Z leftovers$", journal_now, re.M) is not None, "leftovers done" in journal_now,
       any("what its charts stopped shipping not cleared" in c for c in has(calls, "upgrade-notice.sh page"))),
      (True, False, True))
H_BADBASE = "schnappy/infra 4 " + "a" * 40 + " main\nschnappy/ops 7 " + "c" * 40 + " " + "e" * 40 + "\n"
rc, calls = night("prove wave-patches patch", plan=PLAN, heads=(H_BADBASE,))
check("infra's base in the heads no commit (a branch name): paged after the merge, no leftovers asked about, nothing after",
      (merged(calls, "wave-patches"), notices(calls), has(calls, "upgrade-leftovers.py"),
       [c for c in calls if c.startswith(("upgrade-verify.sh AFTER", "task --yes deploy:kubeadm"))],
       any("infra's proven base and head not read" in c for c in has(calls, "upgrade-notice.sh page"))),
      (True, ["page wave-patches"], [], [], True))
rc, calls = night("prove centrifugo minor", heads=(HO,), plan="test:copy:playbook PLAYBOOK=upgrade-forgejo.yml ARGS='-e @/x/f.yml'\n")
check("a unit of ops alone: no chart of infra's moved - no leftovers asked about", has(calls, "upgrade-leftovers.py"), [])
# ── refusals, the lock ──────────────────────────────────────────────────────────────────────────────────────
rc, calls = night("prove wave-patches patch", plan=PLAN)
check("the run's pick the plain one (the test environment's units first)", has(calls, "upgrade-units.py pick"),
      ["upgrade-units.py pick"])
# no shadow mode (operator 2026-11-15; its flag gone 2026-11-20): --shadow is an option like any other it does not take
rc, calls = night("prove wave-patches patch", plan=PLAN, args=("--shadow",))
check("--shadow: refused, nothing read, nothing built", (rc, calls), (2, []))
r = subprocess.run(["bash", os.path.join(OPS, "scripts/upgrade-cycle.sh"), "--apply-all"], capture_output=True, text=True)
check("an option it does not take: refused", r.returncode, 2)
for pick in ("prove Bad/Unit patch", "prove istio huge", "explode istio minor"):
    rc, calls = night(pick)
    check(f"a pick it cannot read ({pick}): refused, nothing built", (rc, has(calls, "task")), (1, []))
rc, calls = night("", files={"pick.rc": "1"})
check("Forgejo not read: the run changes nothing", (rc, has(calls, "task")), (1, []))
setup("prove wave-patches patch", plan=PLAN)
holder = subprocess.Popen(["flock", os.path.join(OPS, ".upgrade-cycle/lock"), "sleep", "5"])
time.sleep(0.3)
r = subprocess.run(["bash", os.path.join(OPS, "scripts/upgrade-cycle.sh")], capture_output=True, text=True, env=environ())
holder.kill()
holder.wait()
check("a second run while one holds the lock: refused, nothing read", (r.returncode, "another upgrade run" in r.stdout, calls_now()),
      (1, True, []))
print("upgrade-cycle: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
