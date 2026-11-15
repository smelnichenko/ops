#!/usr/bin/env bash
# The upgrade cycle's run - task upgrade's second half, after Renovate (the operator's decisions of 2026-11-15: started
# by hand, run locally, no shadow): one Renovate unit - picked, proven on the Vagrant copy (one fix by the Claude agent
# when red), reviewed, gated (a major waits out its 24 h notice), backed up before a one-way change, applied to
# production, verified, recorded, reported (scripts/upgrade-notice.sh: one mail to the single admin address). Nothing
# in production moves before the merge; from the merge on, a run that cannot finish PAGES (a one-way failure: the
# cycle paused, the runner refusing until it is resolved) - half a unit applied is never left unsaid.
#
#   0. gates    before anything (and alone with --preflight, which task upgrade runs before Renovate) and again right
#               before the merge: no backup window within the run's span; no page open (posted again - Alertmanager
#               forgets them on a restart), no run stopped mid-apply (its journal); ops on main, origin's, clean but
#               for the copy's inventory record; the local infra and platform mains origin's (the copy mirrors them);
#               production's Alertmanager routing the cycle's notices (platform's route live); production settled and
#               quiet. The copy's memory (the operator stops the radar) for a unit that builds it - refused, never waited
#   1. pick     scripts/upgrade-units.py pick - NOTHING / PAUSED end the run quietly; a one-way unit blocked at once
#   2. prove    the unit's heads read (and its bases); task test:copy:build (a copy that does not build ends the run -
#               the unit untouched), task test:copy:unit UNIT=<it>; red: the agent's fix - it commits in clones of
#               the proven commits outside every checkout, the runner checks and pushes - proven again; red again:
#               labelled upgrade-blocked, reported; the heads after the proof the ones proven
#   3. review   the full review of the unit's diff (the agent, headless, from clones of the proven commits) - CLEAN
#               and the passes it ran, or blocked. The copy destroyed then (the radar may start)
#   4. gate     patch/minor: on; a major's first run: its notice mailed, then its UPGRADE NOTICE comment (the clock),
#               the run ends; a major whose notice ran out unvetoed: on
#   5. plan     its production commands read from the proof's plan - a step with none refuses the unit, nothing merged;
#               a one-way change with no backup path blocked; held (a veto, upgrade-blocked, the kill switch) refused
#   6. apply    the gates again, a journal written; the unit's pull requests merged by the bot at the proven commits
#               onto the proven bases (a partial merge pages); ops brought to origin's main (fetch, fast-forward);
#               each production command - an etcd snapshot right before Kubernetes'
#   7. verify   Argo settled, every pod ready, no critical alert; red: paged
#   8. record   docs/upgrades/<date>-<unit>.md committed, production's inventory read again; the journal removed
#
# The agents run with a clean environment - never ops/.env (Vault's root token, the admin's password, the API key, which
# would bill instead of the account) and no git credential - and settings of their own (.claude/upgrade-agent/): the
# fix --restricted (its file tools in its clones alone), its Bash sandboxed (credentials unreadable, no network but the
# checksum script's vendors), committing only; the review read-only. Their clones live outside every checkout.
#
# Usage: scripts/upgrade-cycle.sh [--dry|--shadow|--preflight]
#        --dry       every step said, nothing run (the gates read)
#        --shadow    picked, proven, reviewed, the result a comment on the unit's pull requests - nothing applied
#        --preflight the gates (and the copy's memory) alone: exit 0 when a run may start
# Env:   UPGRADE_FORGEJO_TOKEN (the bot's), UPGRADE_AGENT (the agent's command, default claude), UPGRADE_AGENT_TIMEOUT
#        (seconds, 3600), UPGRADE_WORK (the agents' clones, default <ops>/../.upgrade-cycle-work); the harness's:
#        UPGRADE_NOW_HM / UPGRADE_NOW_HM_FILE (HH:MM UTC - the file's lines one a read), UPGRADE_NOW_DOW (1-7),
#        UPGRADE_TODAY (YYYY-MM-DD UTC), UPGRADE_MEMINFO
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
# the cycle's state - the open pages, the journal of an apply under way, the run's lock: gitignored, not .copy's scratch
state=$ops/.upgrade-cycle
work=${UPGRADE_WORK:-$(dirname "$ops")/.upgrade-cycle-work}
mkdir -p "$ops/.copy" "$state"
log=$ops/.copy/upgrade-cycle-$(date +%Y%m%d-%H%M%S)-$$.log  # each run its own: a verdict is never an earlier run's
say() { echo "$(date '+%F %T') $*" | tee -a "$log"; }
run() {  # a step: said, and run unless --dry; its output in the log; nothing it runs reads the run's own input
  say "RUN $*"
  [ -n "$dry" ] && return 0
  "$@" < /dev/null >> "$log" 2>&1
}
run_in() {  # a step run in a directory of its own (the agents' clones)
  local dir=$1; shift
  say "RUN (in $dir) $*"
  [ -n "$dry" ] && return 0
  (cd "$dir" && "$@") < /dev/null >> "$log" 2>&1
}
notice() { run scripts/upgrade-notice.sh "$@" || say "NOTICE NOT SENT: $1 $2 - its post failed (see the log)"; }
unit=""
page() {  # a one-way failure: paged, the cycle paused on Forgejo (durable - the local record is a file)
  notice one-way-failed "$unit" "$1" "$log"
  run scripts/upgrade-label.py --pause "UPGRADE PAUSED $(date -u +%Y-%m-%dT%H:%M:%SZ) - $unit: $1 - the operator's: production checked, then scripts/upgrade-notice.sh resolve $unit and this label removed" \
    || say "NOT PAUSED: the dashboard's upgrades-paused not set - the runner's own record refuses the next run all the same"
}

# one run at a time, whoever starts it (task upgrade or by hand)
exec 9>> "$state/lock"
flock -n 9 || { echo "REFUSED: another upgrade run holds $state/lock"; exit 1; }

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
review_flags=(--setting-sources project,local --settings "$ops/.claude/upgrade-agent/review.json" --strict-mcp-config
              --permission-mode dontAsk --permission-prompts none)
bot_git() {  # git as the bot: its token through a credential helper of the call's own, never on a command line
  git -c credential.helper= -c "credential.helper=!f() { test \"\$1\" = get && printf 'username=renovate-bot\\npassword=%s\\n' \"\$UPGRADE_FORGEJO_TOKEN\"; }; f" "$@"
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

# 0. the gates
gates() {  # $1: the span (minutes) no backup window may meet
  local w open branch head origin am
  if w=$(window_within "$1"); then say "REFUSED: a backup window meets the run ($w UTC) - run when none is that near"; return 1; fi
  open=$(scripts/upgrade-notice.sh open) || { say "REFUSED: the open pages not read"; return 1; }
  if [ -n "$open" ]; then
    run scripts/upgrade-notice.sh repost || say "NOTICE NOT SENT: the open pages' repost failed (see the log)"
    say "REFUSED: a one-way failure's page is open ($(echo $open)) - its fix first, then: scripts/upgrade-notice.sh resolve <unit>"
    return 1
  fi
  if [ -e "$state/inflight" ]; then
    say "REFUSED: a run stopped mid-apply ($(tr '\n' ' ' < "$state/inflight")) - production checked, then $state/inflight removed"
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
  scripts/copy-main-current.sh ../infra ../platform >> "$log" 2>&1 \
    || { say "REFUSED: the local infra or platform main is not origin's (the copy mirrors them) - see the log"; return 1; }
  am=$(ssh -o BatchMode=yes -o ConnectTimeout=15 ten "kubectl -n schnappy-infra exec deploy/schnappy-alertmanager -c alertmanager -- amtool config routes test --config.file=/etc/alertmanager/alertmanager.yml alertname=UpgradeCycle kind=veto unit=probe severity=warning notice=probe" 2>> "$log" | tail -n 1)
  [ "$am" = email-notice ] || { say "REFUSED: production's Alertmanager routes the cycle's notices to '${am:-nothing read}', not email-notice - platform's route not live"; return 1; }
  UPGRADE_VERIFY_SETTLE=0 UPGRADE_VERIFY_HOLD=0 scripts/upgrade-verify.sh < /dev/null >> "$log" 2>&1 \
    || { say "REFUSED: production is not settled and quiet now (see the log) - nothing applied on top of it"; return 1; }
  return 0
}
memory() {  # the copy must fit: the guard's own figure (22.5 GB of VMs + its 2 GB)
  local avail need=$(( 22528 + 2048 + 300 ))
  avail=$(awk '/^MemAvailable:/ {print int($2/1024)}' "${UPGRADE_MEMINFO:-/proc/meminfo}")
  [ "${avail:-0}" -ge "$need" ] || { say "REFUSED: memory - $avail of $need MB free: stop the radar (sudo systemctl stop radar-live), then run again"; return 1; }
}
today_applied() {  # one production apply a day
  local rec
  for rec in docs/upgrades/"${UPGRADE_TODAY:-$(date -u +%F)}"-*.md; do
    [ -e "$rec" ] && { say "REFUSED: a production apply today already ($rec) - one a day"; return 0; }
  done
  return 1
}
if [ -n "$preflight" ]; then
  gates 240 && memory && ! today_applied && { say "PREFLIGHT: a run may start"; exit 0; }
  exit 1
fi
gates 240 || exit 1
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
read_heads() {  # the unit's pull requests' heads and bases, "<repo> <number> <head> <base>" a line (into $1)
  [ -n "$dry" ] && { say "RUN scripts/upgrade-label.py $unit --heads"; : > "$1"; return 0; }
  scripts/upgrade-label.py "$unit" --heads > "$1" 2>> "$log"
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
merged=""
merge() {  # the unit merged at the proven heads onto the proven bases - nothing in: blocked; part in: paged
  run scripts/upgrade-label.py "$unit" --merge --expect "$heads"
  case $? in
    0) merged=1 ;;
    3) merged=1; page "partly merged - half the unit applies (see the log: what went in)"; exit 1 ;;
    *) notice blocked "$unit" "its merge refused - nothing merged" "$log"; exit 1 ;;
  esac
}
# a run stopped after its merge (the terminal closed, a kill): paged, never silent
on_signal() {
  if [ -n "$merged" ]; then page "the run was stopped after its merge - its production commands may not have run"; fi
  exit 1
}
trap on_signal HUP INT TERM

# a test environment's unit: the copy leaves the test environment out - it is its own proof (the test environment before
# production): no copy, no review; one-way left for the operator, else merged at the heads judged, settled, recorded
if [ "$action" = test ]; then
  stop_if_one_way
  if [ -n "$shadow" ]; then
    run scripts/upgrade-label.py "$unit" --comment "UPGRADE SHADOW $(date -u +%Y-%m-%dT%H:%M:%SZ) - test: the test environment's unit, merged first in a real run; nothing applied"
    say "SHADOW $unit"
    exit 0
  fi
  held_now
  read_heads "$heads" || { notice blocked "$unit" "its pull requests not read - nothing merged" "$log"; exit 1; }
  merge
  if ! run scripts/upgrade-verify.sh; then
    # its production twin waits: the test environment not settled is no proof for it
    run scripts/upgrade-label.py "${unit#test-}" upgrade-blocked || say "NOT LABELLED: ${unit#test-} upgrade-blocked - hold it by hand"
    notice blocked "$unit" "merged to the test environment, the cluster not settled after it - its production unit ${unit#test-} held (upgrade-blocked)" "$log"
    exit 1
  fi
  run scripts/upgrade-record.sh "$unit" "$log" || { notice blocked "$unit" "applied and verified, not recorded - push the record by hand" "$log"; exit 1; }
  notice applied "$unit" "the test environment's $unit applied and verified (its production unit next)" "$log"
  say "APPLIED $unit"
  exit 0
fi

memory || exit 1
stop_if_one_way

# clones of the unit's proven commits - the agents' working directory, outside every checkout (a commit there never
# lands in the operator's tree)
dirs=()
clones() {  # into $1, one per repo of the unit (from $heads), each on renovate/<unit> at its proven head
  local dir=$1 repo n sha base
  dirs+=("$dir")
  [ -n "$dry" ] && { say "RUN clones of renovate/$unit into $dir"; return 0; }
  rm -rf "$dir"; mkdir -p "$dir"
  while read -r repo n sha base; do
    [ -n "$repo" ] || continue
    bot_git clone -q "https://git.pmon.dev/$repo.git" "$dir/${repo#*/}" >> "$log" 2>&1 || return 1
    git -C "$dir/${repo#*/}" checkout -q -B "renovate/$unit" "$sha" >> "$log" 2>&1 || return 1
  done < "$heads"
}
# the agent's commits, checked, pushed by the runner - on top of the proven head, on the unit's branch, the bot's
push_fix() {
  local dir=$1 repo n sha base clone pushed=""
  while read -r repo n sha base; do
    clone=$dir/${repo#*/}
    [ -d "$clone" ] || continue
    [ "$(git -C "$clone" rev-parse HEAD)" != "$sha" ] || continue
    [ "$(git -C "$clone" symbolic-ref --short HEAD 2> /dev/null)" = "renovate/$unit" ] \
      || { say "the fix left $repo off renovate/$unit - not pushed"; return 1; }
    git -C "$clone" merge-base --is-ancestor "$sha" HEAD || { say "the fix rewrote $repo's proven commit - not pushed"; return 1; }
    run bot_git -C "$clone" push -q origin "HEAD:refs/heads/renovate/$unit" || { say "the fix's push to $repo refused"; return 1; }
    pushed=1
  done < "$heads"
  [ -z "$pushed" ] || run scripts/upgrade-label.py "$unit" stop-updating \
    || say "NOT LABELLED stop-updating - Renovate may rewrite the fixed branches"
}
cleanup() {
  run vagrant destroy -f
  [ -n "$dry" ] || rm -rf "${dirs[@]}" "$heads" "$heads.after"
}
trap cleanup EXIT

# 2. the proof, one fix - the copy destroyed when the run ends, however it ends (the radar may start again)
build() { run task test:copy:build || { say "COPY NOT BUILT - the unit untouched (see the log); run again"; exit 1; }; }
read_heads "$heads" || { notice blocked "$unit" "its pull requests not read - nothing proven" "$log"; exit 1; }
build
if ! run task test:copy:unit UNIT="$unit"; then
  say "RED: $unit - the agent's fix"
  fixdir=$work/$unit-fix-$$
  if clones "$fixdir"; then
    [ -n "$dry" ] || cp "$log" "$fixdir/proof.log"
    run_in "$fixdir" timeout "$agent_timeout" "${clean_env[@]}" "$agent" -p "upgrade-cycle fix: the unit renovate/$unit failed its proof on the Vagrant copy (its log: proof.log here). Follow the upgrade-fix instructions: the unit's branches are cloned here (one directory per repo); diagnose from the log, commit one fix in each repo it needs. Do not push - the runner does." "${fix_flags[@]}" \
      || say "the fix agent ended non-zero - its commits, if any, are checked all the same"
    push_fix "$fixdir" || { notice blocked "$unit" "its fix not pushed (see the log) - left for the operator" "$log"; exit 1; }
  else
    say "the unit's branches not cloned - no fix; the proof again decides"
  fi
  read_heads "$heads" || { notice blocked "$unit" "its pull requests not read after the fix" "$log"; exit 1; }
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
cmp -s "$heads" "$heads.after" || { notice blocked "$unit" "its branches moved during its proof - nothing applied (the next run proves them)" "$log"; exit 1; }

# 3. the review - from clones of the proven commits; CLEAN and the passes it ran, nothing else
review=$ops/.copy/upgrade-review-$unit-$(date +%s)-$$.txt
revdir=$work/$unit-review-$$
say "RUN $agent -p <the full review of renovate/$unit>"
if [ -z "$dry" ]; then
  clones "$revdir" || { notice blocked "$unit" "its branches not cloned for the review - nothing applied" "$log"; exit 1; }
  (cd "$revdir" && timeout "$agent_timeout" "${clean_env[@]}" "$agent" -p "upgrade-cycle review: run the full review of the unit renovate/$unit - its diff in each repo cloned here (one directory per repo) against origin/main, at medium. End with two lines: 'PASSES: <the passes that ran, comma-separated>' and 'VERDICT: CLEAN' or 'VERDICT: CRITICAL <what>'. Change nothing." "${review_flags[@]}") < /dev/null > "$review" 2>&1
  rc=$?
  cat "$review" >> "$log"
  verdict=$(grep -E '^VERDICT: ' "$review" | tail -1)
  passes=$(grep -E '^PASSES: .+' "$review" | tail -1)
  if [ "$rc" -ne 0 ] || [ "$verdict" != "VERDICT: CLEAN" ] || [ -z "$passes" ]; then
    run scripts/upgrade-label.py "$unit" upgrade-blocked || say "NOT LABELLED upgrade-blocked - the next run proves it again"
    notice blocked "$unit" "its review blocks it (${verdict:-no verdict}, ${passes:-no passes named}, exit $rc)" "$review"
    say "BLOCKED $unit"
    exit 1
  fi
fi
# proven and reviewed: the copy goes now - the radar may start, the apply needs none of it
run vagrant destroy -f

# shadow: proven and reviewed is where the run ends - the result on the pull requests, nothing applied
if [ -n "$shadow" ]; then
  run scripts/upgrade-label.py "$unit" --comment "UPGRADE SHADOW $(date -u +%Y-%m-%dT%H:%M:%SZ) - $action: proven on the Vagrant copy and reviewed clean; nothing applied"
  say "SHADOW $unit"
  exit 0
fi

# 4. the gate - a major's notice mailed first: its comment starts the 24 h, never one the operator was not told of
if [ "$action" = notice ]; then
  run scripts/upgrade-notice.sh veto "$unit" "major $unit proven and reviewed - applies after 24 h unless vetoed (label veto on its PRs)" "$log" \
    || { say "NOT NOTICED: the veto mail not sent - no clock started, the next run notices it again"; exit 1; }
  run scripts/upgrade-label.py "$unit" --comment "UPGRADE NOTICE $(date -u +%Y-%m-%dT%H:%M:%SZ) - applies after 24 h unless vetoed (label veto)" \
    || { say "NOT NOTICED: the comment not posted - the next run notices it again"; exit 1; }
  say "NOTICED $unit"
  exit 0
fi

# 5. the plan: its production commands, every one known - or the unit refused, nothing merged
if [ -n "$dry" ]; then
  say "RUN task test:copy:unit UNIT=$unit PLAN=true"; plan=""
else
  plan=$(task test:copy:unit UNIT="$unit" PLAN=true 2>> "$log" | grep -E '^test:copy:') \
    || { notice blocked "$unit" "its plan not read - nothing applied" "$log"; exit 1; }
fi
cmds=(); ops_part=""
while IFS= read -r step; do
  [ -n "$step" ] || continue
  case "$step" in
    "test:copy:playbook PLAYBOOK=upgrade-kubeadm.yml"*) v=$(sed -n "s/.*k8s_upgrade_to=\([^ ']*\).*/\1/p" <<< "$step")
      cmds+=("deploy:etcd:backup" "deploy:kubeadm:upgrade -- -e k8s_upgrade_to=$v") ;;
    "test:copy:playbook PLAYBOOK=setup-kubeadm.yml"*) v=$(sed -n "s/.*cilium_version=\([^ ']*\).*/\1/p" <<< "$step")
      cmds+=("deploy:cilium:upgrade -- -e cilium_version=$v") ;;
    "test:copy:playbook PLAYBOOK=setup-argocd.yml"*) cmds+=("deploy:argocd") ;;
    "test:copy:playbook PLAYBOOK=setup-host-hardening.yml"*) cmds+=("deploy:host-hardening") ;;
    "test:copy:playbook PLAYBOOK=upgrade-patroni.yml"*) cmds+=("deploy:patroni:upgrade") ;;
    "test:copy:playbook PLAYBOOK=upgrade-vault.yml"*) cmds+=("deploy:vault:upgrade") ;;
    "test:copy:playbook PLAYBOOK=upgrade-forgejo.yml"*) cmds+=("deploy:forgejo:upgrade") ;;
    "test:copy:change"*) continue ;;  # Argo applies infra's and platform's merge
    *) notice blocked "$unit" "a part with no production command: $step - nothing merged" "$log"; exit 1 ;;
  esac
  ops_part=1
done <<< "$plan"
stop_if_one_way

# 6. the apply - the gates again (hours since the start), still free, a journal of it written first
gates 150 || { notice blocked "$unit" "proven and reviewed, not applied: a gate refused it now (see the log) - the next run proves it again" "$log"; exit 1; }
held_now
[ -n "$dry" ] || printf 'unit %s\nheads %s\nstarted %s\n' "$unit" "$(tr '\n' ';' < "$heads")" "$(date -u +%FT%TZ)" > "$state/inflight"
merge
if [ -n "$ops_part" ]; then
  # fetch and fast-forward: a pull follows the operator's pull.rebase, and refused on the copy's inventory record
  run git -C "$ops" fetch -q origin main && run git -C "$ops" merge -q --ff-only origin/main \
    || { page "merged, ops not brought to origin's main - its production commands not run"; exit 1; }
fi
for c in "${cmds[@]}"; do
  read -ra words <<< "$c"
  run task --yes "${words[@]}" || { page "its production command failed: task $c"; exit 1; }
done

# 7. verify
if ! run scripts/upgrade-verify.sh; then
  page "applied, production not settled after it - see the log"
  exit 1
fi

# 8. record
run task test:copy:inventory || say "the inventory not read after it - the record says so"
run scripts/upgrade-record.sh "$unit" "$log" \
  || { notice blocked "$unit" "applied and verified, not recorded - push the record, then remove $state/inflight" "$log"; exit 1; }
[ -n "$dry" ] || rm -f "$state/inflight"
notice applied "$unit" "$kind $unit applied and verified (the copy is gone: the radar may start)" "$log"
say "APPLIED $unit"
