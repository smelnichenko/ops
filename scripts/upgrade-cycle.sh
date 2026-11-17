#!/usr/bin/env bash
# The upgrade cycle's run - task upgrade's second half, after Renovate (started by hand, run locally): one Renovate
# unit - picked, proven on the Vagrant copy (one fix by the Claude agent when red), reviewed, gated (a major, or a unit
# carrying the agent's fix, waits out a 24 h veto notice), backed up before a one-way change, applied to production,
# verified, recorded, reported (scripts/upgrade-notice.sh: one mail to the single admin address). Nothing in production
# moves before the merge; from the merge on, a run that cannot finish PAGES (a one-way failure: the cycle paused, the
# runner refusing until it is resolved) - half a unit applied is never left unsaid. An applying run waits for the
# cycle's first shadow proof (--shadow, proven and reviewed clean: .upgrade-cycle/shadow-proven).
#
#   0. gates    before anything (and alone with --preflight, which task upgrade runs before Renovate) and again right
#               before the merge: no backup window within the run's span (its start: the proof's time and the
#               apply's, 330 min; before the merge: the apply's own waits, 210); no page open (posted again -
#               Alertmanager forgets them on a restart); no run stopped mid-apply (its journal - one found with no page
#               is paged now; one that ends verified is a record to push, said); ops on main,
#               origin's, clean but for the copy's inventory record; at the start, the local infra and platform mains
#               origin's but for CD's app promotions (the copy mirrors them); production's Alertmanager routing the
#               cycle's notices (its loaded config); production settled and quiet (critical alerts included). The
#               copy's memory (the operator stops the radar) for a unit that builds it - refused, never waited
#   1. pick     scripts/upgrade-units.py pick - NOTHING / PAUSED end the run quietly; a one-way unit whose store has a part
#               with no backup yet (scripts/upgrade-stores.json) blocked at once, the part named; one
#               without Renovate's labels (its kind not known) never applied. A shadow run's pick leaves the test
#               environment's units out (pick --shadow): it merges none, so it would stop at one with nothing proven
#   2. prove    the unit's heads read (and its bases); its branches, in every repo, on main but for CD's promotions
#               (Renovate rebases only on a conflict: a unit behind brought up to date by Forgejo first, its new heads
#               waited for - an empty answer never a head; never read as the unit's defect); then its CI green (a
#               running one waited for an hour - still running: said, no try, the same heads still so a run later a
#               try; a red one a try, none at all a try) and main read again (it moved meanwhile: said, no try), each
#               checkout's branch the head its pull request names (Forgejo's record may lag); task test:copy:build (a copy that does not build ends the run - the unit
#               untouched), task test:copy:unit UNIT=<it>; red: the agent's fix - it commits in clones of the proven
#               commits outside every checkout; the runner fetches its commits into a repository of its own (the
#               agent's hooks and config never run), keeps them only on top of the proven head, inside the unit's own
#               kind of files (infra's clusters/, platform's helm/, ops' Ansible vars and playbooks - never CI,
#               scripts, tasks or an agent's instructions), plain UTF-8 text files alone (no symlink, no submodule, no
#               binary), each line it adds printable ASCII and tab (a NEL or a U+2028 is a line break to YAML and none
#               to git; a no-break space indenting a key, a look-alike letter: another key that reads the same), no
#               merge commit - every repo judged before any is pushed; the fix kept on record (.upgrade-cycle/fixes/<unit>.diff), the unit
#               labelled agent-fixed and stop-updating, then its tree pushed as the bot - one commit of the runner's on
#               the proven head (the agent's own commits - a step in between, its words, its author - never on Forgejo); Forgejo read until it shows them, their
#               CI waited for, proven again; red again, or no fix: blocked (labelled upgrade-blocked only on a verdict
#               - the agent's NO FIX); the heads after the proof the ones proven. A failure with no verdict (CI red, a
#               review or fix that did not finish, Forgejo refusing the update) counts a try for the unit's pull
#               requests (the same name later is another unit): their third in a row blocks it; a notice, a shadow
#               proof or an apply starts the count again
#   3. review   the review of the unit's diff (the agent, headless, --restricted: no instructions from the clones; the
#               reviewers' own agents handed to it, a definition that does not read refusing the review) - VERDICT:
#               CLEAN and every pass named exactly, or blocked (labelled only on a VERDICT: CRITICAL line, any of them -
#               an INCOMPLETE or unfinished review is reviewed again, a try). The copy destroyed then
#   4. gate     patch/minor: on; a major's first run, or any unit carrying the agent's fix (this run's or an earlier
#               one's - its diff on record, under 100 KB, or blocked): labelled stop-updating (a newer release pushed
#               by Renovate would void the notice), its notice mailed (what it changes: each repo's stat, its commits,
#               the review's passes and verdict, the diff of the heads proven - 100 KB in all, the cut said; git
#               failing: no notice; a fix's whole diff), then its UPGRADE NOTICE comment with the heads proven (the
#               clock); a major or fixed unit whose notice ran out unvetoed: on - when its heads are the ones announced,
#               main merged in alone (git judges it: the announced head an ancestor of the head now, and merging the
#               head now into main the very tree merging the announced one makes); a newer release, a fix since, an
#               evil or octopus merge, a rebase, main's work dropped: noticed again
#   5. plan     its production commands read from the proof's plan - a step with none, or a version that is none,
#               refuses the unit, nothing merged
#   6. apply    the gates again; the backups a one-way change needs (an etcd snapshot before Kubernetes, its store's from
#               scripts/upgrade-stores.json) - failing,
#               nothing merged; held (a veto, upgrade-blocked, the kill switch) refused; a journal written (the
#               snapshot's name, the pull requests merged, each command - a closed terminal stops nothing from here
#               on); the unit's pull requests merged by the bot at the proven commits onto the proven bases (CD's app
#               promotions since aside; ops' main where the gate saw it, or nothing merged; a partial or unknown merge
#               - any exit but Forgejo's refusal - pages); ops
#               brought to origin's main (fetch, fast-forward) only when it holds the gate's main and the unit's own
#               merge alone; Argo settled on the merge (infra's and platform's parts) before each production command
#   7. verify   Argo settled on the merge, every pod ready, no critical alert through the hold; red: paged
#   8. record   docs/upgrades/<date>-<unit>.md committed, production's inventory read again; the journal removed
#
# The agents run with a clean environment - never ops/.env (Vault's root token, the admin's password, the API key, which
# would bill instead of the account) and no git credential - and settings of their own (.claude/upgrade-agent/): both
# --restricted (their file tools in their clones alone, no instructions from the clones), their Bash sandboxed (nothing
# in the home directory readable but the clones, .git's hooks and config unwritable, no network - the
# release notes aside - WebFetch); the fix commits only (no checksum script: a pin is Renovate's, a fix that needs one
# is no fix), as an author of its own (Upgrade Fix Agent - never Renovate's e-mail: Renovate takes a branch whose
# commits carry it for unmodified and rebases over them); the review changes nothing. Their clones live outside every checkout. A test environment's unit after
# which anything not placed in the test environment is not settled (a read that failed, a critical alert) pages.
#
# Usage: scripts/upgrade-cycle.sh [--dry|--shadow|--preflight]
#        --dry       every step said, nothing run (the gates read)
#        --shadow    picked, proven, reviewed, the result a comment on the unit's pull requests - nothing applied
#        --preflight the gates (and the copy's memory) alone: exit 0 when a run may start
# Env:   UPGRADE_FORGEJO_TOKEN (the bot's), UPGRADE_AGENT (the agent's command, default claude), UPGRADE_AGENT_TIMEOUT
#        (seconds, 3600), UPGRADE_WORK (the agents' clones, default <ops>/../.upgrade-cycle-work - the agents' settings
#        let them read that one), UPGRADE_HEADS_READS (12) / UPGRADE_HEADS_WAIT (10 s): Forgejo read after a push until
#        it shows it; the harness's: UPGRADE_NOW_HM / UPGRADE_NOW_HM_FILE (HH:MM UTC - the file's lines one a read),
#        UPGRADE_NOW_DOW (1-7), UPGRADE_MEMINFO, UPGRADE_FORGEJO_GIT (the bot's git URL
#        base, default https://git.pmon.dev)
set -uo pipefail
# C's messages and byte order, UTF-8's encoding: what the runner starts includes Ansible (the copy's build, the apply's
# tasks), and Ansible refuses any locale encoding but UTF-8 - LC_ALL=C stopped the first build through the runner
# (2026-11-16, 'Detected None')
export LC_ALL=C.UTF-8
ops=$(cd "$(dirname "$0")/.." && pwd)
cd "$ops" || exit 1
dry=""; shadow=""; preflight=""
case "${1:-}" in
  "") ;;
  --dry) dry=1 ;;
  --shadow) shadow=1 ;;
  --preflight) preflight=1 ;;
  *) echo "REFUSED: upgrade-cycle.sh [--dry|--shadow|--preflight]"; exit 2 ;;
esac
# the cycle's state - the open pages, the journal of an apply under way, the run's lock, the first shadow proof:
# gitignored, not .copy's scratch
state=$ops/.upgrade-cycle
work=${UPGRADE_WORK:-$(dirname "$ops")/.upgrade-cycle-work}
forgejo=${UPGRADE_FORGEJO_GIT:-https://git.pmon.dev}
mkdir -p "$ops/.copy" "$state"
log=$ops/.copy/upgrade-cycle-$(date +%Y%m%d-%H%M%S)-$$.log  # each run its own: a verdict is never an earlier run's
say() { echo "$(date '+%F %T') $*" | tee -p -a "$log"; }  # -p: a reader gone (a closed terminal) never costs the log a line
# a step: said, and run unless --dry; its output in the log; nothing it runs reads the run's own input or holds its lock
# (a daemon a step leaves - the copy's host guard - would keep the next run out)
run() {
  say "RUN $*"
  [ -n "$dry" ] && return 0
  "$@" < /dev/null >> "$log" 2>&1 9>&-
}
notice() { run scripts/upgrade-notice.sh "$@" || say "NOTICE NOT SENT: $1 $2 - its post failed (see the log)"; }
unit=""
page() {  # a one-way failure: paged, the cycle paused on Forgejo (durable - the local record is a file)
  notice one-way-failed "$unit" "$1" "$log"
  run scripts/upgrade-label.py --pause "UPGRADE PAUSED $(date -u +%Y-%m-%dT%H:%M:%SZ) - $unit: $1 - the operator's: production checked, then scripts/upgrade-notice.sh resolve $unit, $state/inflight removed (if there), and this label removed" \
    || say "NOT PAUSED: the dashboard's upgrades-paused not set - the runner's own record refuses the next run all the same"
}

# one run at a time, whoever starts it (task upgrade, Renovate's step of it, or by hand)
exec 9>> "$state/lock"
flock -n 9 || { echo "REFUSED: another upgrade run holds $state/lock"; exit 1; }

# an applying run waits for the cycle's first shadow proof (a unit proven and reviewed clean, nothing applied)
if [ -z "$shadow$dry$preflight" ] && [ ! -e "$state/shadow-proven" ]; then
  echo "REFUSED: an applying run waits for the cycle's first shadow proof (task upgrade SHADOW=true: $state/shadow-proven)"
  exit 1
fi

agent=${UPGRADE_AGENT:-claude}
agent_timeout=${UPGRADE_AGENT_TIMEOUT:-3600}
# the agents' environment: none of ops/.env, no git credential or config of the operator's, no repository above their
# clones; their commits the agent's own (never Renovate's identity: a branch it wrote to is one Renovate leaves alone)
clean_env=(env -i "HOME=$HOME" "PATH=$PATH" "LANG=C.UTF-8" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
           GIT_TERMINAL_PROMPT=0 "GIT_CEILING_DIRECTORIES=$work" "GIT_AUTHOR_NAME=Upgrade Fix Agent"
           GIT_AUTHOR_EMAIL=upgrade-fix@pmon.dev "GIT_COMMITTER_NAME=Upgrade Fix Agent" GIT_COMMITTER_EMAIL=upgrade-fix@pmon.dev)
fix_flags=(--restricted --tools "Bash,Read,Edit,Glob,Grep,WebFetch"
           --append-system-prompt-file "$ops/.claude/skills/upgrade-fix/SKILL.md"
           --settings "$ops/.claude/upgrade-agent/fix.json" --strict-mcp-config --permission-mode dontAsk --permission-prompts none)
# the review's reviewers: ops main's own agent definitions, handed over on the command line (--restricted reads no
# settings, skills or instructions from anywhere but its flags)
REVIEWERS="code-architecture-reviewer platform-reliability-reviewer test-quality-reviewer"
REVIEW_PASSES="correctness security architecture reliability tests"
reviewers_json() {
  python3 -I - "$ops/.claude/agents" $REVIEWERS <<'PY'
import json, re, sys
d, out = sys.argv[1], {}
for name in sys.argv[2:]:
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", open(f"{d}/{name}.md", encoding="utf-8").read(), re.S)
    fm = dict(line.split(": ", 1) for line in m.group(1).splitlines() if ": " in line)
    out[name] = {"description": fm["description"], "prompt": m.group(2).strip(),
                 "tools": [t.strip() for t in fm.get("tools", "").split(",") if t.strip()]}
    if not out[name]["description"].strip() or not out[name]["prompt"]:
        sys.exit(f"{name}: no description or no prompt")
print(json.dumps(out))
PY
}
bot_git() {  # git as the bot: its token through a credential helper of the call's own - to Forgejo's host alone, never
             # on a command line
  local host=${forgejo#*://}; host=${host%%/*}
  GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c "credential.helper=!f() { test \"\$1\" = get || exit 0; h=; while IFS== read -r k v && [ -n \"\$k\" ]; do [ \"\$k\" != host ] || h=\$v; done; test \"\$h\" = $host && printf 'username=renovate-bot\\npassword=%s\\n' \"\$UPGRADE_FORGEJO_TOKEN\"; }; f" "$@"
}

now_hm() {  # the time, UTC - the harness's sequence when given (its last line stays)
  if [ -n "${UPGRADE_NOW_HM_FILE:-}" ]; then
    head -n 1 "$UPGRADE_NOW_HM_FILE"
    [ "$(wc -l < "$UPGRADE_NOW_HM_FILE")" -le 1 ] || sed -i 1d "$UPGRADE_NOW_HM_FILE"
  else
    echo "${UPGRADE_NOW_HM:-$(date -u +%H:%M)}"
  fi
}
# the backup windows (UTC) - no merge or apply may meet one:
#   00:50-04:00 every day   the offsite git mirror (04:00 local: 01:00 UTC in summer), CNPG's base backup 01:30, Velero's
#                           daily 02:00, the Pis' backups 02:40, ScyllaDB's backup and Sunday's Velero weekly 03:00
#   04:00-05:00 Sundays     ScyllaDB's repair
#   05:20-05:50 every day   the Pis' restore check 05:30
window_within() {  # a window meeting [now, now + $1 minutes] - "<from>-<to>" said (exit 0), or none (exit 1)
  local span=$1 hm dow t w from to day off d fm tm
  hm=$(now_hm); dow=${UPGRADE_NOW_DOW:-$(date -u +%u)}
  t=$(( 10#${hm%:*} * 60 + 10#${hm#*:} ))
  for off in 0 1440; do  # today's windows and tomorrow's (a span over midnight)
    d=$(( (dow - 1 + off / 1440) % 7 + 1 ))
    for w in "00:50 04:00 any" "04:00 05:00 7" "05:20 05:50 any"; do
      read -r from to day <<< "$w"
      { [ "$day" = any ] || [ "$day" = "$d" ]; } || continue
      fm=$(( off + 10#${from%:*} * 60 + 10#${from#*:} )); tm=$(( off + 10#${to%:*} * 60 + 10#${to#*:} ))
      if [ "$fm" -le $(( t + span )) ] && [ "$tm" -ge "$t" ]; then echo "$from-$to (now $hm, the next $span min)"; return 0; fi
    done
  done
  return 1
}
# the spans no backup window may meet: the apply's (the etcd snapshot up to 15 min, Argo settling up to 30, the
# commands, verify's settle up to 30 and its hour of hold - 210 min), and at the start the proof's before it too (a
# build, the proof and the review: 2 h)
APPLY_SPAN=210; START_SPAN=330

# 0. the gates
# infra's and platform's local mains brought to origin's when only behind it - on main, clean, a fast-forward: the
# runner merges there through Forgejo, so after a unit the next run found them behind and refused (test-curlimages-
# curl-8.x, the first chained run, 2026-11-17); one ahead, dirty or on another branch is left as it is - the check after
# refuses it, said
mains_forward() {
  local r
  [ -n "$dry" ] && { say "RUN git fetch, merge --ff-only (infra, platform: a main only behind origin's brought to it)"; return 0; }
  for r in ../infra ../platform; do
    [ "$(git -C "$r" rev-parse --abbrev-ref HEAD 2> /dev/null)" = main ] && [ -z "$(git -C "$r" status --porcelain 2>&1)" ] || continue
    git -C "$r" fetch -q origin main < /dev/null >> "$log" 2>&1 && git -C "$r" merge -q --ff-only origin/main < /dev/null >> "$log" 2>&1 || true
  done
}
gates() {  # $1: the span (minutes) no backup window may meet; $2: start or merge
  local w open branch head origin am
  if w=$(window_within "$1"); then say "REFUSED: a backup window meets the run ($w UTC) - run when none is that near"; return 1; fi
  open=$(scripts/upgrade-notice.sh open) || { say "REFUSED: the open pages not read"; return 1; }
  if [ -n "$open" ]; then
    run scripts/upgrade-notice.sh repost || say "NOTICE NOT SENT: the open pages' repost failed (see the log)"
    say "REFUSED: a one-way failure's page is open ($(echo $open)) - its fix first, then: scripts/upgrade-notice.sh resolve <unit>"
    return 1
  fi
  if [ -e "$state/inflight" ] && tail -n 1 "$state/inflight" | grep -q ' verified$'; then
    say "REFUSED: the last apply verified, its record not pushed ($state/inflight) - push it (scripts/upgrade-record.sh), then remove the journal"
    return 1
  fi
  if [ -e "$state/inflight" ]; then
    # a run that stopped mid-apply with no page (killed outright, the machine off): paged now - its journal says how far
    unit=$(awk '$1 == "unit" {print $2; exit}' "$state/inflight")
    [[ $unit =~ ^[a-z0-9][a-z0-9.-]*$ ]] || unit=unknown-unit
    say "REFUSED: a run stopped mid-apply - its journal ($state/inflight):"; sed 's/^/  /' "$state/inflight" | tee -a "$log"
    page "a run stopped mid-apply, found by the next run - its journal: $(tr '\n' ';' < "$state/inflight")"
    return 1
  fi
  branch=$(git -C "$ops" rev-parse --abbrev-ref HEAD 2> /dev/null)
  [ "$branch" = main ] || { say "REFUSED: ops is on '$branch', not main - its tasks are what applies"; return 1; }
  # the copy's build reads production's inventory into its record (tracked): that alone may differ
  [ -z "$(git -C "$ops" status --porcelain -- . ':!tests/ansible/copy/prod-inventory.txt' ':!tests/ansible/copy/pi-versions.yml' 2>&1)" ] \
    || { say "REFUSED: ops has changes not on main - its tasks are what applies"; return 1; }
  git -C "$ops" fetch -q origin main >> "$log" 2>&1 || { say "REFUSED: origin's main not read"; return 1; }
  head=$(git -C "$ops" rev-parse HEAD 2> /dev/null); origin=$(git -C "$ops" rev-parse origin/main 2> /dev/null)
  [ -n "$head" ] && [ "$head" = "$origin" ] || { say "REFUSED: ops is not origin's main (${head:0:12} here, ${origin:0:12} there)"; return 1; }
  if [ "$2" = start ]; then  # the copy mirrors the local mains (before the merge the base pin stands for them)
    mains_forward
    scripts/copy-main-current.sh ../infra ../platform >> "$log" 2>&1 \
      || { say "REFUSED: the local infra or platform main is not origin's (the copy mirrors them) - see the log"; return 1; }
  fi
  # the config Alertmanager runs (its API), not the file mounted: a config it refused to load keeps the old one running
  am=$(ssh -o BatchMode=yes -o ConnectTimeout=15 ten "kubectl -n schnappy-infra exec deploy/schnappy-alertmanager -c alertmanager -- amtool config routes test --alertmanager.url=http://localhost:9093 alertname=UpgradeCycle kind=veto unit=probe severity=warning notice=probe" < /dev/null 2>> "$log" | tail -n 1)
  [ "$am" = email-notice ] || { say "REFUSED: production's Alertmanager routes the cycle's notices to '${am:-nothing read}', not email-notice - platform's route not live"; return 1; }
  UPGRADE_VERIFY_SETTLE=0 UPGRADE_VERIFY_HOLD=0 scripts/upgrade-verify.sh < /dev/null >> "$log" 2>&1 \
    || { say "REFUSED: production is not settled and quiet now (see the log) - nothing applied on top of it"; return 1; }
  return 0
}
memory() {  # the copy must fit: the guard's own figure (22.5 GB of VMs + its 2 GB)
  local avail need=$(( 22528 + 2048 + 300 ))
  avail=$(awk '/^MemAvailable:/ {print int($2/1024)}' "${UPGRADE_MEMINFO:-/proc/meminfo}")
  [ "${avail:-0}" -ge "$need" ] || { say "REFUSED: memory - $avail of $need MB free: stop the radar (sudo systemctl stop radar-live) - or a copy left running (vagrant status; vagrant destroy -f) - then run again"; return 1; }
}
if [ -n "$preflight" ]; then
  gates "$START_SPAN" start && memory && { say "PREFLIGHT: a run may start"; exit 0; }
  exit 1
fi
gates "$START_SPAN" start || exit 1
gate_head=$(git -C "$ops" rev-parse HEAD)  # what ops' main may hold at the merge: this, and the unit's own merge

# 1. the pick
picked=$(scripts/upgrade-units.py pick ${shadow:+--shadow}) || { say "NOT READ: Forgejo - the run changes nothing ($picked)"; exit 1; }
say "PICK $picked"
case "$picked" in
  NOTHING|PAUSED) exit 0 ;;
esac
read -r action unit kind <<< "$picked"
[[ $action =~ ^(test|prove|notice|apply)$ && $unit =~ ^[a-z0-9][a-z0-9.-]*$ && $kind =~ ^(patch|minor|major)$ ]] \
  || { say "REFUSED: the pick's answer '$picked'"; exit 1; }
[ "$action" != test ] || [[ $unit == test-* ]] || { say "REFUSED: a test action for '$unit' (no test- unit)"; exit 1; }
heads=$state/heads-$unit-$$
dirs=(); built=""
cleanup() {  # however the run ends: the copy destroyed when it was built (the radar may start), the clones gone
  [ -z "$built" ] || run vagrant destroy -f || say "THE COPY NOT DESTROYED - the radar stays off: vagrant destroy -f by hand"
  [ -n "$dry" ] || { chmod -R u+w "${dirs[@]}" 2> /dev/null; rm -rf "${dirs[@]}" "$heads" "$heads.after" "$heads.expected"; }
  [ -z "${notice_summary:-}" ] || rm -f "$notice_summary"  # mailed by then (the details of a veto go whole)
}
trap cleanup EXIT
tries_key=""
read_heads() {  # the unit's pull requests' heads and bases, "<repo> <number> <head> <base>" a line (into $1); the first
                # read names the pull requests a try is counted for (a later read that fails leaves the file empty)
  [ -n "$dry" ] && { say "RUN scripts/upgrade-label.py $unit --heads"; : > "$1"; return 0; }
  scripts/upgrade-label.py "$unit" --heads > "$1" 2>> "$log" || return 1
  [ -n "$tries_key" ] || tries_key=$(awk '{printf "%s%s#%s", (NR > 1 ? "," : ""), $1, $2}' "$1")
}
# each checkout's branch (fetch_unit's, the proof's own fetch) the head its pull request names: Forgejo's record of a
# pull request may lag its branch - the proof would prove one commit, the review and the merge another
branches_are_heads() {
  local repo head
  [ -z "$dry" ] || return 0
  while read -r repo _ head _ <&3; do
    [ "$(git -C "$(repo_dir "$repo")" rev-parse -q --verify "refs/heads/renovate/$unit" < /dev/null 2>> "$log")" = "$head" ] || return 1
  done 3< "$heads"
}
green() {  # every head's CI success - a running one waited for (an hour: Renovate's run just pushed it), a red one a
           # try (its third blocks), none at all a try (no pipeline started: a webhook lost - it never comes by itself);
           # hours of proof for a merge that refuses either are spent on nothing
  run scripts/upgrade-label.py "$unit" --green 3600
  case $? in
    0) ;;
    4) retry "its CI is red (the update breaking its own checks, or Woodpecker failing) - nothing proven" ;;
    5) retry "no CI on its heads after an hour (no pipeline started for them - a webhook lost?) - nothing proven" ;;
    *) still_running ;;
  esac
}
still_running() {  # its CI still running after an hour (Woodpecker's queue), or not read: no try - but the same heads so
                   # a run later are stuck, a try (the queue run after run behind one unit else)
  local key
  key=$(cut -d' ' -f1-3 "$heads" 2> /dev/null | tr '\n' ' ')
  if [ -n "$key" ] && [ "$(cat "$state/pending/$unit" 2> /dev/null)" = "$key" ]; then
    retry "its CI still not finished on the same heads a run later (stuck in Woodpecker) - nothing proven"
  fi
  [ -n "$dry" ] || { mkdir -p "$state/pending"; printf '%s' "$key" > "$state/pending/$unit"; }
  notice blocked "$unit" "its CI still running after an hour (Woodpecker's queue), or not read - nothing proven, no try counted (the same heads so at the next run count one)" "$log"
  exit 1
}
# its branches on main as it stands but for CD's promotions (the proof refuses them else - never the unit's defect):
# Renovate rebases a branch only on a conflict, so the runner brings the unit it picked onto main itself - Forgejo's
# update (main merged into each pull request behind it), as the bot; what the unit changes stays
repo_dir() { case "$1" in schnappy/ops) echo "$ops" ;; *) echo "$ops/../${1#schnappy/}" ;; esac; }
fetch_unit() {  # the unit's branches into the local checkouts (the proof and the notice's check read them there)
  local repo
  [ -z "$dry" ] || return 0
  for repo in $(cut -d' ' -f1 "$heads"); do
    git -C "$(repo_dir "$repo")" fetch -q origin main "+refs/heads/renovate/$unit:refs/heads/renovate/$unit" < /dev/null >> "$log" 2>&1 || return 1
  done
}
fresh() {
  local repo args=()
  [ -z "$dry" ] || { say "RUN scripts/copy-main-current.sh <the unit's branches>"; return 0; }
  for repo in $(cut -d' ' -f1 "$heads"); do args+=("$(repo_dir "$repo"):renovate/$unit"); done
  scripts/copy-main-current.sh "${args[@]}" < /dev/null >> "$log" 2>&1
}
# Forgejo shows an update of a pull request in a moment of its own: read until each head is its branch's tip
heads_updated() {
  local i repo tip ok
  for i in $(seq "${UPGRADE_HEADS_READS:-12}"); do
    [ "$i" = 1 ] || sleep "${UPGRADE_HEADS_WAIT:-10}"
    read_heads "$heads" || continue
    ok=1
    while read -r repo _ head _ <&3; do
      tip=$(git -C "$(repo_dir "$repo")" ls-remote origin "refs/heads/renovate/$unit" < /dev/null 2>> "$log" | cut -f1)
      [ -n "$tip" ] && [ "$tip" = "$head" ] || ok=""
    done 3< "$heads"
    [ -z "$ok" ] || return 0
  done
  return 1
}
fresh_or_end() {
  fetch_unit || { notice blocked "$unit" "its branches not fetched (git: one checked out in a checkout of the operator's?) - nothing proven, no try counted" "$log"; exit 1; }
  if ! fresh; then
    run scripts/upgrade-label.py "$unit" --update || retry "its branches behind main, Forgejo's update refused (a conflict)"
    heads_updated || { notice blocked "$unit" "its branches updated, Forgejo not showing the new heads yet - nothing proven, no try counted" "$log"; exit 1; }
  fi
  green
  fetch_unit || { notice blocked "$unit" "its branches not fetched after their CI (git) - nothing proven, no try counted" "$log"; exit 1; }
  fresh || { notice blocked "$unit" "main moved again while its CI ran (other work's pushes) - nothing proven, no try counted" "$log"; exit 1; }
  branches_are_heads || { notice blocked "$unit" "its branches' tips not the heads its pull requests name (Forgejo's record behind its git) - nothing proven, no try counted" "$log"; exit 1; }
}

# a one-way change: Renovate's label (renovate/upgrade-cycle.json's rules) or its name a store's (the second net) - what
# its store needs before production, from scripts/upgrade-stores.json (scripts/upgrade-stores.py): the backups, run before
# the merge (one_way_backups, into the apply's pre-commands), or a part with none yet - blocked before anything is built,
# the notice naming each (a vague "no backup path" told the operator nothing, 2026-11-17). A test environment's unit needs
# none (its data is no store to keep - the test environment is where a one-way change runs first). The labels or the
# table not read: nothing applied
unit_labels=""
one_way_backups=() one_way_taken=() one_way_minutes=0
stop_if_one_way() {
  local labels line need judged=$unit
  labels=$(scripts/upgrade-units.py list) || { notice blocked "$unit" "its labels not read from Forgejo - nothing applied" "$log"; exit 1; }
  line=$(awk -v u="$unit" '$1 == u' <<< "$labels")
  [ -n "$line" ] || { notice blocked "$unit" "not in the open units any more - nothing applied" "$log"; exit 1; }
  [[ $line != *" UNLABELLED" ]] || { notice blocked "$unit" "Renovate's labels not on it (its kind, its one-way mark not known) - nothing applied" "$log"; exit 1; }
  labels=$(awk '{print $4}' <<< "$line")
  unit_labels=$labels
  # a test environment's unit takes no backup, but runs only when its production twin could (one merged ahead of a twin
  # blocked for good left the test environment ahead of production - proving nothing after)
  [ "$action" != test ] || judged=${unit#test-}
  need=$(python3 -I scripts/upgrade-stores.py "$judged" "$labels" 2>> "$log") \
    || { notice blocked "$unit" "what its one-way change needs not read (scripts/upgrade-stores.py, see the log) - nothing applied" "$log"; exit 1; }
  case "$need" in
    none) return 0 ;;
    store\ *)
      [ "$action" != test ] || { say "ONE-WAY $unit: its production twin's store can take it - no backup in the test environment"; return 0; }
      mapfile -t one_way_backups < <(sed -n 's/^backup //p' <<< "$need")
      mapfile -t one_way_taken < <(sed -n 's/^taken-by //p' <<< "$need")
      one_way_minutes=$(awk 'NR == 1 {print $3}' <<< "$need")
      [ "$(( ${#one_way_backups[@]} + ${#one_way_taken[@]} ))" -gt 0 ] && [[ $one_way_minutes =~ ^[0-9]+$ ]] \
        || { notice blocked "$unit" "a one-way change, its store's backups not read - nothing applied" "$log"; exit 1; }
      say "ONE-WAY $unit: ${need%%$'\n'*} - backed up before the merge: $(printf '%s; ' "${one_way_backups[@]}" "${one_way_taken[@]/#/its command }")"
      return 0 ;;
  esac
  run scripts/upgrade-label.py "$unit" upgrade-blocked || say "NOT LABELLED upgrade-blocked - the next run blocks it again"
  notice blocked "$unit" "a one-way change its store cannot take yet$([ "$judged" = "$unit" ] || echo " (its production twin $judged's)") - $(awk '{sub(/^(missing|unknown) /, ""); printf "%s%s", (NR > 1 ? "; " : ""), $0}' <<< "$need") (scripts/upgrade-stores.json; once there, upgrade-blocked off its pull requests) - nothing applied" "$log"
  exit 1
}
held_now() {  # a veto, upgrade-blocked or the kill switch set since the pick: refused, nothing merged
  local held
  held=$(scripts/upgrade-units.py held "$unit") || { notice blocked "$unit" "whether it is held not read - nothing merged" "$log"; exit 1; }
  [ -z "$held" ] || { notice blocked "$unit" "held since its pick ($(echo $held)) - nothing merged" "$log"; exit 1; }
}
# a failure with no verdict (a red CI, a review or fix that did not finish, Forgejo refusing its update): counted for
# the unit's pull requests (the same name later is another unit) - its third in a row blocks it (labelled, said),
# never the head of the queue run after run; a run that gets it further (noticed, shadow-proven, applied, the test
# environment's merged) starts the count again
retry() {
  local n key=${tries_key:-none}
  [ -n "$dry" ] || { mkdir -p "$state/tries"; echo "$key $(date -u +%FT%TZ) $1" >> "$state/tries/$unit"; }
  n=$(awk -v k="$key" '$1 == k' "$state/tries/$unit" 2> /dev/null | wc -l)
  if [ "${n:-0}" -ge 3 ]; then
    run scripts/upgrade-label.py "$unit" upgrade-blocked || say "NOT LABELLED upgrade-blocked - the next run tries it again"
    notice blocked "$unit" "$1 - its third try in a row: blocked (upgrade-blocked) for the operator" "${2:-$log}"
  else
    notice blocked "$unit" "$1 - the next run tries again (${n:-1} of 3)" "${2:-$log}"
  fi
  exit 1
}
progress() { [ -n "$dry" ] || rm -f "$state/tries/$unit" "$state/pending/$unit"; }
# the apply's journal: what a run that stops mid-apply leaves for the next one (and the operator) - how far it got
journal() { [ -n "$dry" ] || echo "$(date -u +%FT%TZ) $*" >> "$state/inflight"; }
start_journal() {
  # from here a closed terminal stops nothing: the merge and the commands finish, or page (an interrupt or a kill does)
  trap '' HUP
  [ -n "$dry" ] || printf 'unit %s\nlog %s\nheads %s\nsnapshot %s\nstarted %s\n' "$unit" "$log" "$(tr '\n' ';' < "$heads")" \
    "$(grep -o 'etcd-backup OK: [^ ]*' "$log" 2> /dev/null | tail -n 1 | cut -d' ' -f3)" "$(date -u +%FT%TZ)" > "$state/inflight"
}
merged=""
merge() {  # the unit merged at the proven heads onto the proven bases - nothing in: blocked; part in, or not known: paged
  if [ -z "$dry" ] && ! { git -C "$ops" fetch -q origin main < /dev/null >> "$log" 2>&1 && [ "$(git -C "$ops" rev-parse origin/main)" = "$gate_head" ]; }; then
    rm -f "$state/inflight"
    notice blocked "$unit" "ops' main moved since the gate (or not read) - nothing merged, the next run proves it again" "$log"; exit 1
  fi
  merged=1  # from the call on a stop pages: it may have gone in
  journal "merge asked"
  run scripts/upgrade-label.py "$unit" --merge --expect "$heads"
  case $? in
    0) journal "merged: $(grep '^MERGED ' "$log" 2> /dev/null | cut -d' ' -f2 | tr '\n' ' ')" ;;
    1) merged=""; [ -n "$dry" ] || rm -f "$state/inflight"
       notice blocked "$unit" "its merge refused - nothing merged" "$log"; exit 1 ;;
    *) page "partly merged, or not known whether (the merge ended $?) - half the unit may apply (see the log: what went in)"; exit 1 ;;
  esac
  # ops to origin's main (a pull follows the operator's pull.rebase): the record commits on it, the commands run from it -
  # origin's main the gate's plus the unit's own merge alone (anything else pushed since would run unreviewed)
  run git -C "$ops" fetch -q origin main || { page "merged, origin's ops main not read - what follows the merge not run"; exit 1; }
  if [ -z "$dry" ]; then
    local opshead extra
    opshead=$(awk '$1 == "schnappy/ops" {print $3}' "$heads")
    extra=$(git -C "$ops" rev-list origin/main --not "$gate_head" ${opshead:+"$opshead"} 2>> "$log")
    if [ -n "$opshead" ]; then
      [ "$(wc -l <<< "$extra")" = 1 ] && [ "$(git -C "$ops" rev-parse "$extra^1" 2>> "$log")" = "$gate_head" ] \
        && [ "$(git -C "$ops" rev-parse "$extra^2" 2>> "$log")" = "$opshead" ] \
        || { page "merged, ops' main holds more than the unit's merge ($(echo $extra | cut -c1-80)) - what follows not run"; exit 1; }
    elif [ -n "$extra" ]; then
      page "merged, ops' main moved since the gate ($(echo $extra | cut -c1-80)) - what follows not run"; exit 1
    fi
  fi
  run git -C "$ops" merge -q --ff-only origin/main || { page "merged, ops not brought to origin's main - what follows the merge not run"; exit 1; }
}
# a run stopped during or after its merge (an interrupt, a kill): paged, never silent
on_signal() {
  [ -z "$merged" ] || page "the run was stopped during or after its merge - what follows it may not have run"
  exit 1
}
trap on_signal HUP INT TERM
# the merge's commits on infra's and platform's main, for the unit's parts there: what Argo must have synced
revisions() {
  local repo revs="" sha
  [ -z "$dry" ] || { say "RUN git ls-remote origin refs/heads/main (infra, platform: the merge's commits)"; return 0; }
  for repo in infra platform; do
    grep -q "^schnappy/$repo " "$heads" 2> /dev/null || continue
    sha=$(git -C "$ops/../$repo" ls-remote origin refs/heads/main 2>> "$log" | cut -f1)
    [[ $sha =~ ^[0-9a-f]{40}$ ]] || { say "the merge's commit on $repo's main not read"; return 1; }
    revs+="$repo=$sha "
  done
  echo "${revs% }"
}

test_only() {  # $1: verify's output - every line it complains of placed in the test environment
  python3 -I - "$1" <<'PY'
import re, sys
lines = [l for l in open(sys.argv[1]).read().splitlines()
         if l.strip() and not re.match(r"(SETTLED|NOT SETTLED|NOT QUIET)\b", l)]  # verify's own headers
test = [l for l in lines if re.match(r"(app schnappy-test(-[^ ]+)? |pod schnappy-test(-[^/ ]+)?/)", l)]
root = [l for l in lines if l.startswith("app root ")]
sys.exit(0 if lines and test and len(test) + len(root) == len(lines) else 1)
PY
}
# a test environment's unit: the copy leaves the test environment out - it is its own proof (the test environment before
# production): no copy, no review, no backup (its data is no store to keep); merged at the heads judged, settled, recorded
if [ "$action" = test ]; then
  stop_if_one_way
  if [ -n "$shadow" ]; then
    run scripts/upgrade-label.py "$unit" --comment "UPGRADE SHADOW $(date -u +%Y-%m-%dT%H:%M:%SZ) - test: the test environment's unit, merged first in a real run; nothing applied"
    say "SHADOW $unit"
    exit 0
  fi
  read_heads "$heads" || { notice blocked "$unit" "its pull requests not read - nothing merged" "$log"; exit 1; }
  green
  held_now
  start_journal
  merge
  revs=$(revisions) || { page "merged, the merge's commits not read - its verify not run"; exit 1; }
  vout=$ops/.copy/upgrade-verify-$unit-$$.txt
  say "RUN scripts/upgrade-verify.sh (the test environment's merge)"
  if [ -z "$dry" ] && ! UPGRADE_VERIFY_REVISIONS="$revs" scripts/upgrade-verify.sh < /dev/null > "$vout" 2>&1 9>&-; then
    cat "$vout" >> "$log"
    # the test environment's charts can carry what reaches beyond it: anything not placed in it pages - an app of its
    # own (root aside, when it is its children that are not settled), a pod in its namespaces; a critical alert, a read
    # that failed, anything else: production's
    if ! test_only "$vout"; then
      page "merged to the test environment, production not settled after it (see the log)"; exit 1
    fi
    # its production twin waits: the test environment not settled is no proof for it (not held: the cycle paused)
    run scripts/upgrade-label.py "${unit#test-}" upgrade-blocked \
      || { page "merged to the test environment, not settled after it, and its production unit ${unit#test-} not held"; exit 1; }
    rm -f "$state/inflight"  # the test environment's: production untouched, the twin held
    notice blocked "$unit" "merged to the test environment, it not settled after it - its production unit ${unit#test-} held (upgrade-blocked)" "$log"
    exit 1
  fi
  [ ! -e "$vout" ] || cat "$vout" >> "$log"
  journal "verified"
  run scripts/upgrade-record.sh "$unit" "$log" \
    || { notice blocked "$unit" "applied and verified, not recorded - push the record, then remove $state/inflight" "$log"; exit 1; }
  [ -n "$dry" ] || rm -f "$state/inflight"
  progress
  notice applied "$unit" "the test environment's $unit applied and verified (its production unit next)" "$log"
  say "APPLIED $unit"
  exit 0
fi

memory || exit 1
stop_if_one_way

# clones of the unit's proven commits - the agents' working directory, outside every checkout (a commit there never
# lands in the operator's tree)
clones() {  # into $1, one per repo of the unit (from $heads), each on renovate/<unit> at its proven head
  local dir=$1 repo n sha
  dirs+=("$dir")
  [ -n "$dry" ] && { say "RUN clones of renovate/$unit into $dir"; return 0; }
  rm -rf "$dir"; mkdir -p "$dir"
  while read -r repo n sha _ <&3; do
    [ -n "$repo" ] || continue
    bot_git clone -q "$forgejo/$repo.git" "$dir/${repo#*/}" < /dev/null >> "$log" 2>&1 9>&- || return 1
    git -C "$dir/${repo#*/}" checkout -q -B "renovate/$unit" "$sha" < /dev/null >> "$log" 2>&1 || return 1
  done 3< "$heads"
}
# beside each clone in $1: <repo>.diff and <repo>.commits, the unit's diff and commits against main - the review's
# reviewers read them with Read alone (their Bash is plain read-only git, one command a call: a reviewer's `cd <path>`
# then `git diff`, or a loop over `git -C`, is refused - the first unattended review, 2026-11-17, had its reviewers read
# platform's and ops' files at HEAD instead of the diff); --text: a file git takes for binary shown whole, never "Binary
# files differ" (a NUL or a stray encoding hiding a key from the review)
diffs() {
  local dir=$1 repo r
  while read -r repo _ <&3; do
    [ -n "$repo" ] || continue
    r=$dir/${repo#*/}
    git -C "$r" diff --text --no-ext-diff --no-textconv --no-color origin/main...HEAD > "$r.diff" 2>> "$log" < /dev/null || return 1
    git -C "$r" log --no-color --format='%h %an <%ae> %s' origin/main..HEAD > "$r.commits" 2>> "$log" < /dev/null || return 1
  done 3< "$heads"
}
# what the agent may change in each repo: the unit's own kind of files - never CI, scripts, tasks, the trust files or an
# agent's instructions (each would run, or steer a later run, unproven)
allowed() {  # allowed <repo> <path>
  case "$2" in
    */CLAUDE.md|CLAUDE.md|*/AGENTS.md|AGENTS.md|.claude/*|*/.claude/*|.woodpecker/*|.gitattributes|*/.gitattributes|.gitmodules|renovate.json) return 1 ;;
  esac
  case "$1:$2" in
    schnappy/infra:clusters/*|schnappy/platform:helm/*) return 0 ;;
    schnappy/ops:deploy/ansible/vars/*.yml|schnappy/ops:deploy/ansible/playbooks/*.yml) return 0 ;;
  esac
  return 1
}
# a file of the agent's: UTF-8 text (a binary showed as "Binary files differ"), each line it adds printable ASCII and
# tab alone - a carriage return, a NEL or a U+2028 is a line break to YAML and none to git (a key hidden from the mail
# and the review), a no-break space indenting a key made it another key that read the same, a zero-width or bidi
# character, a look-alike letter the same; a line it keeps stays as it was
plain_fix() {  # plain_fix <repository> <proven> <tip> <path>
  python3 -I - "$@" <<'PY'
import collections, subprocess, sys
repo, proven, tip, path = sys.argv[1:]
def blob(rev):
    r = subprocess.run(["git", "-C", repo, "cat-file", "blob", f"{rev}:{path}"], capture_output=True, stdin=subprocess.DEVNULL)
    return r.stdout if r.returncode == 0 else None
new = blob(tip)
try:
    text = new.decode("utf-8")
except (AttributeError, UnicodeDecodeError):  # not there, or not UTF-8
    sys.exit(1)
kept = collections.Counter((blob(proven) or b"").decode("utf-8", "replace").split("\n"))
for line in text.split("\n"):
    if kept[line] > 0:
        kept[line] -= 1
    elif any(c != "\t" and not " " <= c <= "~" for c in line):
        sys.exit(1)
PY
}
# the agent's commits, checked, pushed by the runner: fetched from its clone into a repository of the runner's own (its
# hooks and config - the agent's - never run), on top of the proven head, inside allowed(), their tree pushed as one
# commit of the runner's on the proven head - every repo judged before
# any is pushed (half a fix pushed, unlabelled, was a fix a later run would apply with no notice); the unit labelled
# agent-fixed (and stop-updating) before the first push; pushed as the bot to Forgejo's URL itself; their diff kept
# for the veto notice. The heads file read on a descriptor of its own: nothing in the loop reads it away
fixed=""
push_fix() {
  local dir=$1 repo n sha clone mirror tip bad
  local -a push=()
  : > "$fixdiff"; : > "$fixdiff.stat"
  : > "$heads.expected"
  while read -r repo n sha _ <&3; do
    clone=$dir/${repo#*/}; mirror=$dir.push/${repo#*/}
    tip=$sha
    [ -d "$clone" ] || { say "the agent's clone of $repo is gone - not pushed"; return 1; }
    rm -rf "$mirror"; git init -q --bare "$mirror" < /dev/null
    git -C "$mirror" -c fetch.fsckObjects=true fetch -q --no-tags "$clone" "+refs/heads/renovate/$unit:refs/fix" < /dev/null >> "$log" 2>&1 \
      || { say "the fix left $repo without its branch renovate/$unit - not pushed"; return 1; }
    tip=$(git -C "$mirror" rev-parse refs/fix < /dev/null)
    if [ "$tip" != "$sha" ]; then
      git -C "$mirror" merge-base --is-ancestor "$sha" "$tip" < /dev/null || { say "the fix rewrote $repo's proven commit - not pushed"; return 1; }
      [ -z "$(git -C "$mirror" rev-list --merges "$sha..$tip" < /dev/null)" ] || { say "the fix holds a merge commit in $repo - nothing pushed"; return 1; }
      # each file: both sides of a rename (a script moved into clusters/ is a script gone from its place), a plain file
      # or a deletion alone (a symlink is followed by whatever reads the tree unsandboxed; a submodule is another repo)
      bad=$(git -C "$mirror" diff --raw --no-renames "$sha" "$tip" < /dev/null | while IFS=$'\t' read -r meta f; do
              mode=$(cut -d' ' -f2 <<< "$meta")
              { [[ $mode =~ ^(100644|100755|000000)$ ]] && allowed "$repo" "$f" \
                && { [ "$mode" = 000000 ] || plain_fix "$mirror" "$sha" "$tip" "$f" < /dev/null; }; } || echo "$f"
            done)
      [ -z "$bad" ] || { say "the fix changed what it may not in $repo: $(echo $bad) - nothing pushed"; return 1; }
      { echo "=== $repo"; git -C "$mirror" diff --stat --no-ext-diff --no-textconv --no-color --no-renames "$sha" "$tip"; } < /dev/null >> "$fixdiff.stat"
      { echo "=== $repo"; git -C "$mirror" log --format='%h %s' "$sha..$tip" | LC_ALL=C tr -c '[:print:]\n' '?' | cut -c1-200
        git -C "$mirror" diff --text --no-ext-diff --no-textconv --no-color --no-renames "$sha" "$tip"; } < /dev/null >> "$fixdiff"
      # pushed as one commit of the runner's on the proven head - its tree the one judged: the agent's own commits (a
      # step in between with files it may not touch, its words - a closing keyword on the dashboard -, an author
      # it chose) never reach Forgejo
      tip=$(env GIT_AUTHOR_NAME="Upgrade Fix Agent" GIT_AUTHOR_EMAIL=upgrade-fix@pmon.dev GIT_COMMITTER_NAME="Upgrade Fix Agent" \
              GIT_COMMITTER_EMAIL=upgrade-fix@pmon.dev git -C "$mirror" commit-tree "$tip^{tree}" -p "$sha" \
              -m "upgrade-fix: renovate/$unit - the agent's fix, judged and committed by the upgrade runner" < /dev/null) \
        || { say "the fix's commit not made in $repo - nothing pushed"; return 1; }
      push+=("$repo $tip")
    fi
    echo "$repo $n $tip" >> "$heads.expected"
  done 3< "$heads"
  [ "${#push[@]}" -gt 0 ] || return 0
  # the fix on record before anything is pushed: its notice (this run's or a later one's) mails it whole - every repo's
  # stat first, then each commit and diff (appended: a second fix noticed with the first)
  if [ -z "$dry" ]; then
    mkdir -p "$state/fixes"
    # a unit of this name fixed before (applied, closed) is not this one: its record starts again
    [[ ,$unit_labels, == *,agent-fixed,* ]] || : > "$state/fixes/$unit.diff"
    { echo "=== the agent's fix of renovate/$unit, $(date -u +%FT%TZ) - files:"; cat "$fixdiff.stat"; cat "$fixdiff"; } >> "$state/fixes/$unit.diff"
  fi
  run scripts/upgrade-label.py "$unit" agent-fixed || { say "NOT LABELLED agent-fixed - nothing pushed: its 24 h notice would not hold"; return 1; }
  run scripts/upgrade-label.py "$unit" stop-updating || { say "NOT LABELLED stop-updating - nothing pushed: Renovate would rewrite the fixed branches"; return 1; }
  unit_labels+=",stop-updating"
  fixed=1  # labelled: from here a push that went in waits for its notice, whatever follows
  for p in "${push[@]}"; do
    read -r repo tip <<< "$p"
    run bot_git -C "$dir.push/${repo#*/}" -c core.hooksPath=/dev/null push -q "$forgejo/$repo.git" "$tip:refs/heads/renovate/$unit" \
      || { say "the fix's push to $repo refused (the unit labelled agent-fixed: what went in waits for its notice)"; return 1; }
  done
}
# Forgejo shows a push to a pull request in a moment of its own: read until the heads are the ones pushed
heads_pushed() {
  local i
  [ -n "$dry" ] && { say "RUN scripts/upgrade-label.py $unit --heads (until it shows the fix)"; return 0; }
  for i in $(seq "${UPGRADE_HEADS_READS:-12}"); do
    [ "$i" = 1 ] || sleep "${UPGRADE_HEADS_WAIT:-10}"
    read_heads "$heads" || continue
    cmp -s <(cut -d' ' -f1-3 "$heads") "$heads.expected" && return 0
  done
  return 1
}

# 2. the proof, one fix - the copy destroyed when the run ends, however it ends (the radar may start again)
build() { built=1; run task test:copy:build || { say "COPY NOT BUILT - the unit untouched (see the log); run again"; exit 1; }; }
# the unit's plan read before the copy is built: a part the proof cannot take (an ops value copy-unit.sh has no proof for -
# Keycloak's, Consul's) refused now - labelled upgrade-blocked, the parts named, nothing built and no agent: the refusal is
# ops' to fix, never the unit's (it was built 49 min, refused, and handed to the fix agent as red - 2026-11-17's review)
preplan() {
  local out
  [ -z "$dry" ] || { say "RUN task test:copy:unit UNIT=$unit PLAN=true (before the build)"; return 0; }
  out=$(task test:copy:unit UNIT="$unit" PLAN=true 2>&1 < /dev/null 9>&-) && { printf '%s\n' "$out" >> "$log"; return 0; }
  printf '%s\n' "$out" >> "$log"
  if grep -q '^REFUSED:' <<< "$out"; then
    run scripts/upgrade-label.py "$unit" upgrade-blocked || say "NOT LABELLED upgrade-blocked - the next run blocks it again"
    notice blocked "$unit" "the copy cannot prove it - $(grep -m1 '^REFUSED:' <<< "$out" | cut -c10-400) (scripts/copy-unit.sh's proof paths; once there, upgrade-blocked off its pull requests) - nothing built" "$log"
    exit 1
  fi
  notice blocked "$unit" "its plan not read before the build (see the log) - nothing built, no try counted" "$log"
  exit 1
}
read_heads "$heads" || { notice blocked "$unit" "its pull requests not read - nothing proven" "$log"; exit 1; }
fresh_or_end
preplan
build
if ! run task test:copy:unit UNIT="$unit"; then
  say "RED: $unit - handed to the fix agent"
  fixdir=$work/$unit-fix-$$; fixdiff=$ops/.copy/upgrade-fix-$unit-$$.diff; fixout=$ops/.copy/upgrade-fix-$unit-$$.txt
  clones "$fixdir" || { notice blocked "$unit" "red; its branches not cloned for the agent - no fix, the next run proves it again" "$log"; exit 1; }
  dirs+=("$fixdir.push")
  if [ -z "$dry" ]; then
    cp "$log" "$fixdir/proof.log"
    (cd "$fixdir" && timeout "$agent_timeout" "${clean_env[@]}" "$agent" -p "upgrade-cycle fix: the unit renovate/$unit failed its proof on the Vagrant copy (its log: proof.log here). Follow the upgrade-fix instructions: the unit's branches are cloned here (one directory per repo); diagnose from the log, commit one fix in each repo it needs. Do not push - the runner does." "${fix_flags[@]}") < /dev/null > "$fixout" 2>&1 9>&-
    rc=$?
    cat "$fixout" >> "$log"
    [ "$rc" = 0 ] || say "the fix agent ended $rc - its commits, if any, are checked all the same"
  else
    say "RUN $agent -p <the fix of renovate/$unit>"
  fi
  if [ -n "$dry" ]; then say "RUN the agent's commits checked and pushed"
  else push_fix "$fixdir" || { notice blocked "$unit" "its fix not pushed (see the log) - left for the operator" "$log"; exit 1; }; fi
  if [ -z "$fixed" ] && [ -z "$dry" ]; then
    # no commit: a verdict (the agent's NO FIX - the new version's defect) holds the unit; an agent that did not
    # finish (a limit, a timeout) does not - the next run proves it again
    if grep -q '^NO FIX: ' "$fixout"; then
      run scripts/upgrade-label.py "$unit" upgrade-blocked || say "NOT LABELLED upgrade-blocked - the next run proves it again"
      notice blocked "$unit" "red, no fix: $(grep -m1 '^NO FIX: ' "$fixout" | cut -c1-300)" "$log"
    else
      retry "red; the agent committed no fix and gave no verdict (see the log)"
    fi
    exit 1
  fi
  heads_pushed || retry "its fix pushed, Forgejo not showing it on its pull requests"
  green  # the fix's own CI
  build
  if ! run task test:copy:unit UNIT="$unit"; then
    run scripts/upgrade-label.py "$unit" upgrade-blocked || say "NOT LABELLED upgrade-blocked - the next run proves it again"
    notice blocked "$unit" "red after its fix - left for the operator" "$log"
    say "BLOCKED $unit"
    exit 1
  fi
fi
# what was proven is what is merged: the heads after the proof the ones read before it
read_heads "$heads.after" || { notice blocked "$unit" "its pull requests not read after its proof - nothing applied" "$log"; exit 1; }
if ! { cmp -s <(cut -d' ' -f1-3 "$heads") <(cut -d' ' -f1-3 "$heads.after") && branches_are_heads; }; then
  notice blocked "$unit" "its branches moved during its proof - nothing applied (the next run proves them)" "$log"; exit 1
fi

# 3. the review - from clones of the proven commits; CLEAN and every pass named, nothing else
review=$ops/.copy/upgrade-review-$unit-$(date +%s)-$$.txt
revdir=$work/$unit-review-$$
say "RUN $agent -p <the review of renovate/$unit>"
if [ -z "$dry" ]; then
  reviewers=$(reviewers_json 2>> "$log") || { notice blocked "$unit" "the reviewers' definitions not read - not reviewed, nothing applied" "$log"; exit 1; }
  clones "$revdir" || { notice blocked "$unit" "its branches not cloned for the review - nothing applied" "$log"; exit 1; }
  diffs "$revdir" || { notice blocked "$unit" "its diffs not written for the review - nothing applied" "$log"; exit 1; }
  (cd "$revdir" && timeout "$agent_timeout" "${clean_env[@]}" "$agent" -p "upgrade-cycle review: review the unit renovate/$unit - its diff in each repo cloned here (one directory per repo, its diff against origin/main in <repo>.diff and its commits in <repo>.commits beside it) - as the review instructions say. End with two lines: 'PASSES: <the passes that ran, comma-separated>' and 'VERDICT: CLEAN' or 'VERDICT: CRITICAL <what>'. Change nothing." \
     --restricted --tools "Bash,Read,Glob,Grep,Agent,Skill" --agents "$reviewers" \
     --append-system-prompt-file "$ops/.claude/upgrade-agent/review.md" --settings "$ops/.claude/upgrade-agent/review.json" \
     --strict-mcp-config --permission-mode dontAsk --permission-prompts none) < /dev/null > "$review" 2>&1 9>&-
  rc=$?
  cat "$review" >> "$log"
  verdict=$(grep -E '^VERDICT: ' "$review" | tail -1)
  passes=$(grep -E '^PASSES: .+' "$review" | tail -1)
  missing=""
  for p in $REVIEW_PASSES; do tr ',' '\n' <<< "${passes#PASSES: }" | sed 's/^ *//; s/ *$//' | grep -qxi "$p" || missing+=" $p"; done
  if grep -q '^VERDICT: CRITICAL' "$review"; then  # any CRITICAL line - a later CLEAN never takes it back
    verdict=$(grep -m1 '^VERDICT: CRITICAL' "$review")
    run scripts/upgrade-label.py "$unit" upgrade-blocked || say "NOT LABELLED upgrade-blocked - the next run proves it again"
    notice blocked "$unit" "its review blocks it (${verdict:0:300})" "$review"
    say "BLOCKED $unit"
    exit 1
  fi
  if [ "$rc" -ne 0 ] || [ "$verdict" != "VERDICT: CLEAN" ] || [ -n "$missing" ]; then
    retry "its review did not finish (${verdict:-no verdict}; passes missing:${missing:- none}; exit $rc)" "$review"
  fi
fi
# proven and reviewed: the copy goes now - the radar may start, the apply needs none of it
copy_gone="the copy is gone: the radar may start"
if run vagrant destroy -f; then built=""; else copy_gone="THE COPY NOT DESTROYED - the radar stays off"; say "$copy_gone"; fi

# shadow: proven and reviewed is where the run ends - the result on the pull requests, nothing applied; the cycle's
# first such proof lets applying runs start
if [ -n "$shadow" ]; then
  run scripts/upgrade-label.py "$unit" --comment "UPGRADE SHADOW $(date -u +%Y-%m-%dT%H:%M:%SZ) - $action: proven on the Vagrant copy and reviewed clean${fixed:+ (with the fix by the agent)}; nothing applied"
  [ -n "$dry" ] || [ -e "$state/shadow-proven" ] || printf 'unit %s\nlog %s\nat %s\n' "$unit" "$log" "$(date -u +%FT%TZ)" > "$state/shadow-proven"
  progress
  say "SHADOW $unit"
  exit 0
fi

# a major's notice: what it changes, bounded - each repo's files and commits, the diff itself (its first 80 KB), the
# review's verdict (the run's log is hundreds of KB: a mail carries what the operator reads)
summary() {  # summary <file>: what the unit changes, for its notice's mail - each repo's files and commits (the heads
             # read: the ones proven), the review's passes and verdict, the diff; 100 KB in all (upgrade-notice.sh refuses
             # more: a unit never noticed), the cut said in the mail; git failing: no summary (no notice on what is not known)
  local out=$1 repo head dir ok=1 size limit=102400
  [ -z "$dry" ] || { : > "$out"; return 0; }
  { echo "=== renovate/$unit: what it changes"
    while read -r repo _ head _ <&3; do
      dir=$(repo_dir "$repo")
      echo "=== $repo"; git -C "$dir" diff --stat --no-ext-diff --no-textconv --no-color --no-renames "origin/main...$head" < /dev/null 2>> "$log" || ok=""
      git -C "$dir" log --format='%h %s' "origin/main..$head" < /dev/null 2>> "$log" | LC_ALL=C tr -c '[:print:]\n' '?' | cut -c1-200
      [ "${PIPESTATUS[0]}" = 0 ] || ok=""
    done 3< "$heads"
    echo "=== the review: $(grep -E '^(PASSES|VERDICT): ' "$review" 2> /dev/null | tr '\n' ' ')"
    echo "=== the diff"
    while read -r repo _ head _ <&3; do
      git -C "$(repo_dir "$repo")" diff --text --no-ext-diff --no-textconv --no-color --no-renames "origin/main...$head" < /dev/null 2>> "$log" || ok=""
    done 3< "$heads"
  } > "$out.whole"
  [ -n "$ok" ] || { rm -f "$out.whole"; return 1; }
  size=$(wc -c < "$out.whole")
  if [ "$size" -le "$limit" ]; then
    mv "$out.whole" "$out"
  else
    { head -c $((limit - 200)) "$out.whole"
      printf '\n[cut: %s of %s bytes shown - the whole: git diff origin/main...<head> in each repo above]\n' $((limit - 200)) "$size"
    } > "$out"
    rm -f "$out.whole"
  fi
}
# a major (or a unit carrying the agent's fix) applies only what its notice announced: the heads on its comment, each
# an ancestor of the head proven now, and merging the head now into main makes the very tree merging the announced one
# makes - main merged in since (Forgejo's update) changes nothing of it; a newer release, a fix since, a rebase, an evil
# or octopus merge (git judges only two parents of a merge - one that took an old main as its second dropped main's
# work), main's work dropped: noticed again
notice_holds() {
  local line announced repo sha cur dir tree_now tree_announced pair
  [ -z "$dry" ] || return 0
  line=$(scripts/upgrade-units.py noticed "$unit" 2>> "$log") || return 1
  announced=$(awk '{print $2}' <<< "$line")
  [ -n "$announced" ] || return 1
  [ "$(tr ',' '\n' <<< "$announced" | cut -d@ -f1 | sort | tr '\n' ' ')" = "$(cut -d' ' -f1 "$heads" | sort | tr '\n' ' ')" ] || return 1
  for pair in ${announced//,/ }; do
    repo=${pair%@*}; sha=${pair#*@}
    [[ $sha =~ ^[0-9a-f]{40}$ ]] || return 1
    cur=$(awk -v r="$repo" '$1 == r {print $3}' "$heads"); dir=$(repo_dir "$repo")
    git -C "$dir" merge-base --is-ancestor "$sha" "$cur" 2>> "$log" || return 1
    # each merge clean (a conflict prints more than a tree and exits 1) and the same tree
    tree_now=$(git -C "$dir" merge-tree --write-tree origin/main "$cur" 2>> "$log") || return 1
    tree_announced=$(git -C "$dir" merge-tree --write-tree origin/main "$sha" 2>> "$log") || return 1
    [ "$tree_now" = "$tree_announced" ] || return 1
  done
}

# 4. the gate - a major's first run, a unit this run fixed, or one whose notice no longer holds: its notice mailed first
# (the fix's diff in it), its comment then starts the 24 h - never a clock the operator was not told of
again=""
[ "$action" != apply ] || notice_holds || { again=1; say "its notice does not hold for the heads proven now (a newer release, a fix since) - noticed again"; }
if [ "$action" = notice ] || [ -n "$fixed" ] || [ -n "$again" ]; then
  why="major $unit proven and reviewed"; notice_summary=$ops/.copy/upgrade-notice-$unit-$$.txt; details=$notice_summary
  summary "$details" || { notice blocked "$unit" "its summary not made (git failing - see the log) - not noticed, no try counted" "$log"; exit 1; }
  if [ -n "$fixed" ] || [[ ,$unit_labels, == *,agent-fixed,* ]]; then
    # the agent's fix, whichever run pushed it: its whole diff on record, or no notice (no clock without its evidence)
    details=$state/fixes/$unit.diff
    [ -s "$details" ] || { notice blocked "$unit" "carries the agent's fix, its diff not on record ($details) - not noticed, left for the operator" "$log"; exit 1; }
    why="$kind $unit proven and reviewed WITH THE AGENT'S FIX (its diff below)"; fixed=1
  fi
  if [ -n "$fixed" ] && [ "$(wc -c < "$details")" -gt 102400 ]; then  # a fix too large to mail whole is no fix to notice: the operator's
    run scripts/upgrade-label.py "$unit" upgrade-blocked || say "NOT LABELLED upgrade-blocked - the next run tries again"
    notice blocked "$unit" "its fix's diff ($(wc -c < "$details") bytes) is over a mail's 100 KB - not noticed, labelled upgrade-blocked" "$log"
    exit 1
  fi
  # what the notice announces: the heads proven now - a later run applies these (main merged in aside), or notices again;
  # Renovate kept off its branches from here (a newer release it pushed would void the notice, the loop never ending)
  announce=$(awk '{printf "%s%s@%s", (NR > 1 ? "," : ""), $1, $3}' "$heads")
  [[ ,$unit_labels, == *,stop-updating,* ]] || run scripts/upgrade-label.py "$unit" stop-updating \
    || { say "NOT NOTICED: stop-updating not set - Renovate would void the notice; the next run notices it again"; exit 1; }
  run scripts/upgrade-notice.sh veto "$unit" "$why - applies after 24 h unless vetoed (label veto on its PRs)" "$details" \
    || { say "NOT NOTICED: the veto mail not sent - no clock started, the next run notices it again"; exit 1; }
  run scripts/upgrade-label.py "$unit" --comment "UPGRADE NOTICE $(date -u +%Y-%m-%dT%H:%M:%SZ) heads=$announce - applies after 24 h unless vetoed (label veto)${fixed:+ - with the fix by the agent}" \
    || { say "NOT NOTICED: the comment not posted - the next run notices it again"; exit 1; }
  progress
  say "NOTICED $unit"
  exit 0
fi

# 5. the plan: its production commands, every one known and its version one - or the unit refused, nothing merged
if [ -n "$dry" ]; then
  say "RUN task test:copy:unit UNIT=$unit PLAN=true"; plan=""
else
  plan=$(task test:copy:unit UNIT="$unit" PLAN=true 2>> "$log" 9>&- | grep -E '^test:copy:') \
    || { notice blocked "$unit" "its plan not read - nothing applied" "$log"; exit 1; }
fi
pre=(); cmds=()
version_of() {  # the value of $1= in the step, a version or nothing
  local v
  v=$(sed -n "s/.*$1=\([^ ']*\).*/\1/p" <<< "$2")
  [[ $v =~ ^[0-9][0-9A-Za-z.+~-]*$ ]] && echo "$v"
}
while IFS= read -r step; do
  [ -n "$step" ] || continue
  case "$step" in
    "test:copy:playbook PLAYBOOK=upgrade-kubeadm.yml"*)
      v=$(version_of k8s_upgrade_to "$step") || { notice blocked "$unit" "no Kubernetes version in its plan ($step) - nothing merged" "$log"; exit 1; }
      pre+=("deploy:etcd:backup"); cmds+=("deploy:kubeadm:upgrade -- -e k8s_upgrade_to=$v") ;;
    "test:copy:playbook PLAYBOOK=setup-kubeadm.yml"*)
      v=$(version_of cilium_version "$step") || { notice blocked "$unit" "no Cilium version in its plan ($step) - nothing merged" "$log"; exit 1; }
      cmds+=("deploy:cilium:upgrade -- -e cilium_version=$v") ;;
    "test:copy:playbook PLAYBOOK=setup-argocd.yml"*) cmds+=("deploy:argocd") ;;
    "test:copy:playbook PLAYBOOK=setup-host-hardening.yml"*) cmds+=("deploy:host-hardening") ;;
    "test:copy:playbook PLAYBOOK=upgrade-patroni.yml"*) cmds+=("deploy:patroni:upgrade") ;;
    "test:copy:playbook PLAYBOOK=upgrade-consul.yml"*) cmds+=("deploy:consul:upgrade") ;;
    "test:copy:playbook PLAYBOOK=upgrade-vault.yml"*) cmds+=("deploy:vault:upgrade") ;;
    "test:copy:playbook PLAYBOOK=upgrade-forgejo.yml"*) cmds+=("deploy:forgejo:upgrade") ;;
    "test:copy:playbook PLAYBOOK=setup-caddy.yml"*) cmds+=("deploy:caddy") ;;  # it installs the version pinned
    "test:copy:change"*) continue ;;  # Argo applies infra's and platform's merge
    *) notice blocked "$unit" "a part with no production command: $step - nothing merged" "$log"; exit 1 ;;
  esac
done <<< "$plan"
stop_if_one_way
pre+=("${one_way_backups[@]}")  # a one-way store's backups, after the plan's own (an etcd snapshot) - each before the merge, the order theirs alone
for c in "${one_way_taken[@]}"; do  # a store whose backup its own command takes: that command in the plan, or nothing
  printf '%s\n' "${cmds[@]}" | grep -qx -- "$c" \
    || { notice blocked "$unit" "a one-way change whose backup its command takes ($c) - not in its plan; nothing merged" "$log"; exit 1; }
done
APPLY_SPAN=$((APPLY_SPAN + one_way_minutes))  # the backups' bound: the apply's window holds them too

# 6. the apply - the gates again (hours since the start), the backups a one-way change needs, still free, a journal
gates "$APPLY_SPAN" merge || { notice blocked "$unit" "proven and reviewed, not applied: a gate refused it now (see the log) - the next run proves it again" "$log"; exit 1; }
gate_head=$(git -C "$ops" rev-parse HEAD)
for c in "${pre[@]}"; do
  read -ra words <<< "$c"
  run task --yes "${words[@]}" || { notice blocked "$unit" "its backup before the change failed (task $c) - nothing merged" "$log"; exit 1; }
done
held_now
start_journal
merge
revs=$(revisions) || { page "merged, the merge's commits not read - its production commands not run"; exit 1; }
journal "revisions $revs"
if [ -n "$revs" ] && [ "${#cmds[@]}" -gt 0 ]; then
  # Argo applies infra's and platform's part first, as on the copy - a command (kubeadm restarting the API server)
  # in the middle of its sync fails the sync
  UPGRADE_VERIFY_REVISIONS="$revs" UPGRADE_VERIFY_HOLD=0 run scripts/upgrade-verify.sh \
    || { page "merged, Argo not settled on it - its production commands not run"; exit 1; }
fi
for c in "${cmds[@]}"; do
  read -ra words <<< "$c"
  journal "command $c"
  run task --yes "${words[@]}" || { page "its production command failed: task $c"; exit 1; }
  journal "command done $c"
done

# 7. verify
if ! UPGRADE_VERIFY_REVISIONS="$revs" run scripts/upgrade-verify.sh; then
  page "applied, production not settled after it - see the log"
  exit 1
fi
journal "verified"

# 8. record
run task test:copy:inventory || say "the inventory not read after it - the record says so"
run scripts/upgrade-record.sh "$unit" "$log" \
  || { notice blocked "$unit" "applied and verified, not recorded - push the record, then remove $state/inflight" "$log"; exit 1; }
[ -n "$dry" ] || rm -f "$state/inflight" "$state/tries/$unit" "$state/fixes/$unit.diff"
notice applied "$unit" "$kind $unit applied and verified ($copy_gone)" "$log"
say "APPLIED $unit"
