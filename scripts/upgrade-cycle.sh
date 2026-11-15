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
#               apply's; before the merge: the apply's); no page open (posted again - Alertmanager forgets them on a
#               restart); no run stopped mid-apply (its journal - one found with no page is paged now); ops on main,
#               origin's, clean but for the copy's inventory record; at the start, the local infra and platform mains
#               origin's but for CD's app promotions (the copy mirrors them); production's Alertmanager routing the
#               cycle's notices (its loaded config); production settled and quiet (critical alerts included). The
#               copy's memory (the operator stops the radar) for a unit that builds it - refused, never waited
#   1. pick     scripts/upgrade-units.py pick - NOTHING / PAUSED end the run quietly; a one-way unit blocked at once
#   2. prove    the unit's heads read (and its bases), its CI green (else nothing proven); task test:copy:build (a copy
#               that does not build ends the run - the unit untouched), task test:copy:unit UNIT=<it>; red: the
#               agent's fix - it commits in clones of the proven commits outside every checkout; the runner fetches
#               its commits into a repository of its own (the agent's hooks and config never run), keeps them only on
#               top of the proven head and inside the unit's own kind of files (infra's clusters/, platform's helm/,
#               ops' Ansible vars and playbooks - never CI, scripts, tasks or an agent's instructions), pushes them
#               as the bot (labelled stop-updating, agent-fixed), waits until Forgejo shows them, proves again; red
#               again, or no fix: blocked (labelled upgrade-blocked only on a verdict - the agent's NO FIX); the
#               heads after the proof the ones proven
#   3. review   the review of the unit's diff (the agent, headless, --restricted: no instructions from the clones; the
#               reviewers' own agents handed to it) - VERDICT: CLEAN and every pass named, or blocked (labelled only
#               on VERDICT: CRITICAL - a review that did not finish is reviewed again). The copy destroyed then
#   4. gate     patch/minor: on; a major's first run, or any unit the agent fixed in this run: its notice mailed (the
#               fix's diff in it), then its UPGRADE NOTICE comment (the clock), the run ends; a major or fixed unit
#               whose notice ran out unvetoed: on
#   5. plan     its production commands read from the proof's plan - a step with none, or a version that is none,
#               refuses the unit, nothing merged; a one-way change with no backup path blocked
#   6. apply    the gates again; the backup a one-way change needs (an etcd snapshot before Kubernetes) - failing,
#               nothing merged; held (a veto, upgrade-blocked, the kill switch) refused; a journal written (a closed
#               terminal stops nothing from here on); the unit's pull requests merged by the bot at the proven
#               commits onto the proven bases (CD's app promotions since aside; a partial or unknown merge pages); ops
#               brought to origin's main (fetch, fast-forward); Argo settled on the merge (infra's and platform's
#               parts) before each production command
#   7. verify   Argo settled on the merge, every pod ready, no critical alert through the hold; red: paged
#   8. record   docs/upgrades/<date>-<unit>.md committed, production's inventory read again; the journal removed
#
# The agents run with a clean environment - never ops/.env (Vault's root token, the admin's password, the API key, which
# would bill instead of the account) and no git credential - and settings of their own (.claude/upgrade-agent/): both
# --restricted (their file tools in their clones alone, no instructions from the clones), their Bash sandboxed (nothing
# in the home directory readable but the clones, .git's hooks and config unwritable, no network but the checksum
# script's vendors - the review none); the fix commits only (its checksum script the runner's copy, outside what it may
# edit); the review changes nothing. Their clones live outside every checkout.
#
# Usage: scripts/upgrade-cycle.sh [--dry|--shadow|--preflight]
#        --dry       every step said, nothing run (the gates read)
#        --shadow    picked, proven, reviewed, the result a comment on the unit's pull requests - nothing applied
#        --preflight the gates (and the copy's memory) alone: exit 0 when a run may start
# Env:   UPGRADE_FORGEJO_TOKEN (the bot's), UPGRADE_AGENT (the agent's command, default claude), UPGRADE_AGENT_TIMEOUT
#        (seconds, 3600), UPGRADE_WORK (the agents' clones, default <ops>/../.upgrade-cycle-work - the agents' settings
#        let them read that one), UPGRADE_HEADS_READS (12) / UPGRADE_HEADS_WAIT (10 s): Forgejo read after a push until
#        it shows it; the harness's: UPGRADE_NOW_HM / UPGRADE_NOW_HM_FILE (HH:MM UTC - the file's lines one a read),
#        UPGRADE_NOW_DOW (1-7), UPGRADE_TODAY (YYYY-MM-DD UTC), UPGRADE_MEMINFO, UPGRADE_FORGEJO_GIT (the bot's git URL
#        base, default https://git.pmon.dev)
set -uo pipefail
export LC_ALL=C
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
say() { echo "$(date '+%F %T') $*" | tee -a "$log"; }
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
# clones; their commits the bot's
clean_env=(env -i "HOME=$HOME" "PATH=$PATH" "LANG=C.UTF-8" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
           GIT_TERMINAL_PROMPT=0 "GIT_CEILING_DIRECTORIES=$work" "GIT_AUTHOR_NAME=Renovate Bot"
           GIT_AUTHOR_EMAIL=renovate-bot@pmon.dev "GIT_COMMITTER_NAME=Renovate Bot" GIT_COMMITTER_EMAIL=renovate-bot@pmon.dev)
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
print(json.dumps(out))
PY
}
bot_git() {  # git as the bot: its token through a credential helper of the call's own - to Forgejo's host alone, never
             # on a command line
  local host=${forgejo#*://}; host=${host%%/*}
  git -c credential.helper= -c "credential.helper=!f() { test \"\$1\" = get || exit 0; h=; while IFS== read -r k v && [ -n \"\$k\" ]; do [ \"\$k\" != host ] || h=\$v; done; test \"\$h\" = $host && printf 'username=renovate-bot\\npassword=%s\\n' \"\$UPGRADE_FORGEJO_TOKEN\"; }; f" "$@"
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
# the spans no backup window may meet: the apply's (the merge, Argo settling, the commands, verify's settle and its
# hour of hold - 150 min), and at the start the proof's before it too (a build, the proof and the review: 2 h)
APPLY_SPAN=150; START_SPAN=270

# 0. the gates
gates() {  # $1: the span (minutes) no backup window may meet; $2: start or merge
  local w open branch head origin am
  if w=$(window_within "$1"); then say "REFUSED: a backup window meets the run ($w UTC) - run when none is that near"; return 1; fi
  open=$(scripts/upgrade-notice.sh open) || { say "REFUSED: the open pages not read"; return 1; }
  if [ -n "$open" ]; then
    run scripts/upgrade-notice.sh repost || say "NOTICE NOT SENT: the open pages' repost failed (see the log)"
    say "REFUSED: a one-way failure's page is open ($(echo $open)) - its fix first, then: scripts/upgrade-notice.sh resolve <unit>"
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
today_applied() {  # one production apply a day
  local rec
  for rec in docs/upgrades/"${UPGRADE_TODAY:-$(date -u +%F)}"-*.md; do
    [ -e "$rec" ] && { say "REFUSED: a production apply today already ($rec) - one a day"; return 0; }
  done
  return 1
}
if [ -n "$preflight" ]; then
  gates "$START_SPAN" start && memory && ! today_applied && { say "PREFLIGHT: a run may start"; exit 0; }
  exit 1
fi
gates "$START_SPAN" start || exit 1
today_applied && exit 1

# 1. the pick
picked=$(scripts/upgrade-units.py pick) || { say "NOT READ: Forgejo - the run changes nothing ($picked)"; exit 1; }
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
  [ -n "$dry" ] || rm -rf "${dirs[@]}" "$heads" "$heads.after" "$heads.expected"
}
trap cleanup EXIT
read_heads() {  # the unit's pull requests' heads and bases, "<repo> <number> <head> <base>" a line (into $1)
  [ -n "$dry" ] && { say "RUN scripts/upgrade-label.py $unit --heads"; : > "$1"; return 0; }
  scripts/upgrade-label.py "$unit" --heads > "$1" 2>> "$log"
}
green() {  # every head's CI success - hours of proof for a merge that refuses a red one are spent on nothing
  run scripts/upgrade-label.py "$unit" --green \
    || { notice blocked "$unit" "its CI is not green (or not read) - nothing proven, the next run looks again" "$log"; exit 1; }
}

# one-way with no backup path: Renovate's label (renovate/upgrade-cycle.json's rules) - the names a second net, failing
# closed; the labels not read, nothing is applied
stop_if_one_way() {
  local labels
  labels=$(scripts/upgrade-units.py list) || { notice blocked "$unit" "its labels not read from Forgejo - nothing applied" "$log"; exit 1; }
  labels=$(awk -v u="$unit" '$1 == u {print $4}' <<< "$labels")
  [ -n "$labels" ] || { notice blocked "$unit" "not in the open units any more - nothing applied" "$log"; exit 1; }
  if [[ ,$labels, == *,one-way,* ]] || grep -qE '(postgres|postgresql|scylla|scylladb|kafka|clickhouse|strimzi|grafana|consul|vault)-[0-9]+\.(x|[0-9]+)$' <<< "$unit"; then
    run scripts/upgrade-label.py "$unit" upgrade-blocked || say "NOT LABELLED upgrade-blocked - the next run blocks it again"
    notice blocked "$unit" "a one-way change with no backup path in the cycle yet - left for the operator" "$log"
    exit 1
  fi
}
held_now() {  # a veto, upgrade-blocked or the kill switch set since the pick: refused, nothing merged
  local held
  held=$(scripts/upgrade-units.py held "$unit") || { notice blocked "$unit" "whether it is held not read - nothing merged" "$log"; exit 1; }
  [ -z "$held" ] || { notice blocked "$unit" "held since its pick ($(echo $held)) - nothing merged" "$log"; exit 1; }
}
# the apply's journal: what a run that stops mid-apply leaves for the next one (and the operator) - how far it got
journal() { [ -n "$dry" ] || echo "$(date -u +%FT%TZ) $*" >> "$state/inflight"; }
start_journal() {
  # from here a closed terminal stops nothing: the merge and the commands finish, or page (an interrupt or a kill does)
  trap '' HUP
  [ -n "$dry" ] || printf 'unit %s\nlog %s\nheads %s\nstarted %s\n' "$unit" "$log" "$(tr '\n' ';' < "$heads")" "$(date -u +%FT%TZ)" > "$state/inflight"
}
merged=""
merge() {  # the unit merged at the proven heads onto the proven bases - nothing in: blocked; part in, or not known: paged
  merged=1  # from the call on a stop pages: it may have gone in
  journal "merge asked"
  run scripts/upgrade-label.py "$unit" --merge --expect "$heads"
  case $? in
    0) journal "merged" ;;
    3) page "partly merged, or not known whether - half the unit may apply (see the log: what went in)"; exit 1 ;;
    *) merged=""; [ -n "$dry" ] || rm -f "$state/inflight"
       notice blocked "$unit" "its merge refused - nothing merged" "$log"; exit 1 ;;
  esac
  # ops to origin's main (a pull follows the operator's pull.rebase): the record commits on it, the commands run from it
  run git -C "$ops" fetch -q origin main && run git -C "$ops" merge -q --ff-only origin/main \
    || { page "merged, ops not brought to origin's main - what follows the merge not run"; exit 1; }
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

# a test environment's unit: the copy leaves the test environment out - it is its own proof (the test environment before
# production): no copy, no review; one-way left for the operator, else merged at the heads judged, settled, recorded
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
  if ! UPGRADE_VERIFY_REVISIONS="$revs" run scripts/upgrade-verify.sh; then
    # its production twin waits: the test environment not settled is no proof for it (not held: the cycle paused)
    run scripts/upgrade-label.py "${unit#test-}" upgrade-blocked \
      || { page "merged to the test environment, not settled after it, and its production unit ${unit#test-} not held"; exit 1; }
    [ -n "$dry" ] || rm -f "$state/inflight"  # the test environment's: production untouched, the twin held
    notice blocked "$unit" "merged to the test environment, the cluster not settled after it - its production unit ${unit#test-} held (upgrade-blocked)" "$log"
    exit 1
  fi
  journal "verified"
  run scripts/upgrade-record.sh "$unit" "$log" \
    || { notice blocked "$unit" "applied and verified, not recorded - push the record, then remove $state/inflight" "$log"; exit 1; }
  [ -n "$dry" ] || rm -f "$state/inflight"
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
  while read -r repo n sha _; do
    [ -n "$repo" ] || continue
    bot_git clone -q "$forgejo/$repo.git" "$dir/${repo#*/}" >> "$log" 2>&1 9>&- || return 1
    git -C "$dir/${repo#*/}" checkout -q -B "renovate/$unit" "$sha" >> "$log" 2>&1 || return 1
  done < "$heads"
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
# the agent's commits, checked, pushed by the runner: fetched from its clone into a repository of the runner's own (its
# hooks and config - the agent's - never run), on top of the proven head, inside allowed(), pushed as the bot to
# Forgejo's URL itself; their diff kept for the veto notice
fixed=""
push_fix() {
  local dir=$1 repo n sha clone mirror tip bad
  : > "$fixdiff"
  : > "$heads.expected"
  while read -r repo n sha _; do
    clone=$dir/${repo#*/}; mirror=$dir.push/${repo#*/}
    tip=$sha
    if [ -d "$clone" ]; then
      rm -rf "$mirror"; git init -q --bare "$mirror"
      git -C "$mirror" fetch -q --no-tags "$clone" "+refs/heads/renovate/$unit:refs/fix" >> "$log" 2>&1 \
        || { say "the fix left $repo without its branch renovate/$unit - not pushed"; return 1; }
      tip=$(git -C "$mirror" rev-parse refs/fix)
    fi
    if [ "$tip" != "$sha" ]; then
      git -C "$mirror" merge-base --is-ancestor "$sha" "$tip" || { say "the fix rewrote $repo's proven commit - not pushed"; return 1; }
      # both sides of a rename (a script moved into clusters/ is a script gone from its place)
      bad=$(git -C "$mirror" diff --no-renames --name-only "$sha" "$tip" | while IFS= read -r f; do allowed "$repo" "$f" || echo "$f"; done)
      [ -z "$bad" ] || { say "the fix changed what it may not in $repo: $(echo $bad) - not pushed"; return 1; }
      { echo "=== $repo"; git -C "$mirror" log --format='%h %s' "$sha..$tip"; git -C "$mirror" diff --stat "$sha" "$tip"
        git -C "$mirror" diff "$sha" "$tip"; } >> "$fixdiff"
      run bot_git -C "$mirror" -c core.hooksPath=/dev/null push -q "$forgejo/$repo.git" "$tip:refs/heads/renovate/$unit" \
        || { say "the fix's push to $repo refused"; return 1; }
      fixed=1
    fi
    echo "$repo $n $tip" >> "$heads.expected"
  done < "$heads"
  [ -n "$fixed" ] || return 0
  run scripts/upgrade-label.py "$unit" stop-updating || say "NOT LABELLED stop-updating - Renovate may rewrite the fixed branches"
  run scripts/upgrade-label.py "$unit" agent-fixed || { say "NOT LABELLED agent-fixed - not proven again: its 24 h notice would not hold"; return 1; }
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
read_heads "$heads" || { notice blocked "$unit" "its pull requests not read - nothing proven" "$log"; exit 1; }
green
build
if ! run task test:copy:unit UNIT="$unit"; then
  say "RED: $unit - the agent's fix"
  fixdir=$work/$unit-fix-$$; fixdiff=$ops/.copy/upgrade-fix-$unit-$$.diff; fixout=$ops/.copy/upgrade-fix-$unit-$$.txt
  clones "$fixdir" || { notice blocked "$unit" "red; its branches not cloned for the agent - no fix, the next run proves it again" "$log"; exit 1; }
  dirs+=("$fixdir.push")
  if [ -z "$dry" ]; then
    cp "$log" "$fixdir/proof.log"
    # the checksum script and the vendors' keys the agent runs: ops main's, outside what it may edit
    mkdir -p "$fixdir/.trusted" && cp scripts/renovate-checksums.py "$fixdir/.trusted/" && cp -r renovate/keys "$fixdir/.trusted/keys"
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
      notice blocked "$unit" "red; the agent committed no fix and gave no verdict (see the log) - the next run proves it again" "$log"
    fi
    exit 1
  fi
  heads_pushed || { notice blocked "$unit" "its fix pushed, Forgejo not showing it on its pull requests - the next run proves it" "$log"; exit 1; }
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
cmp -s <(cut -d' ' -f1-3 "$heads") <(cut -d' ' -f1-3 "$heads.after") \
  || { notice blocked "$unit" "its branches moved during its proof - nothing applied (the next run proves them)" "$log"; exit 1; }

# 3. the review - from clones of the proven commits; CLEAN and every pass named, nothing else
review=$ops/.copy/upgrade-review-$unit-$(date +%s)-$$.txt
revdir=$work/$unit-review-$$
say "RUN $agent -p <the review of renovate/$unit>"
if [ -z "$dry" ]; then
  clones "$revdir" || { notice blocked "$unit" "its branches not cloned for the review - nothing applied" "$log"; exit 1; }
  (cd "$revdir" && timeout "$agent_timeout" "${clean_env[@]}" "$agent" -p "upgrade-cycle review: review the unit renovate/$unit - its diff in each repo cloned here (one directory per repo) against origin/main - as the review instructions say. End with two lines: 'PASSES: <the passes that ran, comma-separated>' and 'VERDICT: CLEAN' or 'VERDICT: CRITICAL <what>'. Change nothing." \
     --restricted --tools "Bash,Read,Glob,Grep,Agent,Skill" --agents "$(reviewers_json)" \
     --append-system-prompt-file "$ops/.claude/upgrade-agent/review.md" --settings "$ops/.claude/upgrade-agent/review.json" \
     --strict-mcp-config --permission-mode dontAsk --permission-prompts none) < /dev/null > "$review" 2>&1 9>&-
  rc=$?
  cat "$review" >> "$log"
  verdict=$(grep -E '^VERDICT: ' "$review" | tail -1)
  passes=$(grep -E '^PASSES: .+' "$review" | tail -1)
  missing=""
  for p in $REVIEW_PASSES; do grep -qiw "$p" <<< "${passes#PASSES: }" || missing+=" $p"; done
  if [[ $verdict == "VERDICT: CRITICAL"* ]]; then
    run scripts/upgrade-label.py "$unit" upgrade-blocked || say "NOT LABELLED upgrade-blocked - the next run proves it again"
    notice blocked "$unit" "its review blocks it (${verdict:0:300})" "$review"
    say "BLOCKED $unit"
    exit 1
  fi
  if [ "$rc" -ne 0 ] || [ "$verdict" != "VERDICT: CLEAN" ] || [ -n "$missing" ]; then
    notice blocked "$unit" "its review did not finish (${verdict:-no verdict}; passes missing:${missing:- none}; exit $rc) - reviewed again next run" "$review"
    exit 1
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
  say "SHADOW $unit"
  exit 0
fi

# 4. the gate - a major's first run, or a unit this run fixed: its notice mailed first (the fix's diff in it), its comment
# then starts the 24 h - never a clock the operator was not told of
if [ "$action" = notice ] || [ -n "$fixed" ]; then
  why="major $unit proven and reviewed"; details=$log
  [ -z "$fixed" ] || { why="$kind $unit proven and reviewed WITH THE AGENT'S FIX (its diff below)"; details=$fixdiff; }
  run scripts/upgrade-notice.sh veto "$unit" "$why - applies after 24 h unless vetoed (label veto on its PRs)" "$details" \
    || { say "NOT NOTICED: the veto mail not sent - no clock started, the next run notices it again"; exit 1; }
  run scripts/upgrade-label.py "$unit" --comment "UPGRADE NOTICE $(date -u +%Y-%m-%dT%H:%M:%SZ) - applies after 24 h unless vetoed (label veto)${fixed:+ - with the fix by the agent}" \
    || { say "NOT NOTICED: the comment not posted - the next run notices it again"; exit 1; }
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
    "test:copy:playbook PLAYBOOK=upgrade-vault.yml"*) cmds+=("deploy:vault:upgrade") ;;
    "test:copy:playbook PLAYBOOK=upgrade-forgejo.yml"*) cmds+=("deploy:forgejo:upgrade") ;;
    "test:copy:change"*) continue ;;  # Argo applies infra's and platform's merge
    *) notice blocked "$unit" "a part with no production command: $step - nothing merged" "$log"; exit 1 ;;
  esac
done <<< "$plan"
stop_if_one_way

# 6. the apply - the gates again (hours since the start), the backups a one-way change needs, still free, a journal
gates "$APPLY_SPAN" merge || { notice blocked "$unit" "proven and reviewed, not applied: a gate refused it now (see the log) - the next run proves it again" "$log"; exit 1; }
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
[ -n "$dry" ] || rm -f "$state/inflight"
notice applied "$unit" "$kind $unit applied and verified ($copy_gone)" "$log"
say "APPLIED $unit"
