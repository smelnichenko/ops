#!/usr/bin/env bash
# The upgrade cycle's run - task upgrade's second half, after Renovate (the operator's decisions of 2026-11-15: started
# by hand, run locally, no shadow): one Renovate unit - picked, proven on the Vagrant copy (one fix by the Claude agent
# when red), reviewed, gated (a major waits out its 24 h notice), backed up before a one-way change, applied to
# production, verified, recorded, reported (scripts/upgrade-notice.sh: one mail to the single admin address). A run
# that cannot finish changes nothing in production and says so.
#
#   0. gates    before anything (and alone with --preflight, which task upgrade runs before Renovate): outside the
#               backup windows; no one-way failure's page open (posted again - Alertmanager forgets them on a restart);
#               ops on main, clean and origin's (its tasks are what applies); the copy's memory free (the operator stops
#               the radar - refused at once, never a wait); no production apply recorded today (one a day)
#   1. pick     scripts/upgrade-units.py pick - NOTHING / PAUSED end the run quietly
#   2. prove    the unit's pull requests' heads read; task test:copy:build, task test:copy:unit UNIT=<it>; red: the
#               agent's fix (one, pushed to the unit's branches from clones of its own), proven again; red again:
#               labelled upgrade-blocked, reported; the heads after the proof the ones proven
#   3. review   the full review of the unit's diff (the agent, headless, from clones) - a Critical finding blocks
#   4. gate     patch/minor: on; a major's first run: its notice (UPGRADE NOTICE comment + mail), the run ends;
#               a major whose notice ran out unvetoed: on
#   5. backup   the unit's plan read (or blocked); a one-way change takes its stores' backup first (etcd for
#               Kubernetes: task deploy:etcd:backup, its result checked); one with no backup path yet is blocked
#   6. apply    outside a backup window (it waits one out); the unit's pull requests merged by the bot at the proven
#               commits (Argo syncs infra and platform); ops main pulled (checked), then each ops part's PRODUCTION
#               task, the proof's own order (task --yes deploy:...)
#   7. verify   Argo settled, every pod ready, no critical alert; red: paged (a one-way failure)
#   8. record   docs/upgrades/<date>-<unit>.md committed, production's inventory read again
#   the copy is destroyed when the run ends, however it ends (the operator's radar may start again)
#
# The agents (fix, review) run with a clean environment - never ops/.env (Vault's root token, the admin's password,
# the API key, which would bill instead of the account) - and settings of their own (.claude/upgrade-agent/), never
# the operator's; they work in clones under .copy/upgrade-fix/, never the operator's trees.
#
# Usage: scripts/upgrade-cycle.sh [--dry|--shadow|--preflight]
#        --dry       every step said, nothing run (the gates read)
#        --shadow    picked, proven, reviewed, the result a comment on the unit's pull requests - nothing applied
#        --preflight the gates alone: exit 0 when a run may start
# Env:   UPGRADE_FORGEJO_TOKEN (the bot's), UPGRADE_AGENT (the agent's command, default claude); the harness's:
#        UPGRADE_NOW_HM / UPGRADE_NOW_HM_FILE (HH:MM UTC - the file's lines one a read), UPGRADE_NOW_DOW (1-7),
#        UPGRADE_TODAY (YYYY-MM-DD UTC), UPGRADE_MEMINFO, UPGRADE_SLEEP
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
log=$ops/.copy/upgrade-cycle-$(date +%Y%m%d-%H%M%S)-$$.log  # each run its own: a verdict is never an earlier run's
mkdir -p "$ops/.copy"
say() { echo "$(date '+%F %T') $*" | tee -a "$log"; }
run() {  # a step: said, and run unless --dry; its output in the log
  say "RUN $*"
  [ -n "$dry" ] && return 0
  "$@" >> "$log" 2>&1
}
run_in() {  # a step run in a directory of its own (the agents' clones)
  local dir=$1; shift
  say "RUN (in $dir) $*"
  [ -n "$dry" ] && return 0
  (cd "$dir" && "$@") >> "$log" 2>&1
}
notice() { run scripts/upgrade-notice.sh "$@" || say "NOTICE NOT SENT: $1 $2 - its post failed (see the log)"; }
agent=${UPGRADE_AGENT:-claude}
# the agents' environment: none of ops/.env; the account's login from HOME; the copy's Vagrant for the fix's look
clean_env=(env -i "HOME=$HOME" "PATH=$PATH" "LANG=C.UTF-8" "VAGRANT_CWD=$ops")
agent_flags() {  # its own settings, the operator's skipped; anything they do not allow denied, never asked
  echo --setting-sources project,local --settings "$ops/.claude/upgrade-agent/$1.json" --strict-mcp-config \
    --permission-mode dontAsk --permission-prompts none
}

now_hm() {  # the time, UTC - the harness's sequence when given (its last line stays)
  if [ -n "${UPGRADE_NOW_HM_FILE:-}" ]; then
    head -n 1 "$UPGRADE_NOW_HM_FILE"
    [ "$(wc -l < "$UPGRADE_NOW_HM_FILE")" -le 1 ] || sed -i 1d "$UPGRADE_NOW_HM_FILE"
  else
    echo "${UPGRADE_NOW_HM:-$(date -u +%H:%M)}"
  fi
}
# the backup windows (UTC) - nothing merged or applied in one:
#   00:50-04:00 every day   the offsite git mirror (04:00 local: 01:00 UTC in summer), CNPG's base backup 01:30, Velero's
#                           daily 02:00, the Pis' backups 02:40, ScyllaDB's backup and Sunday's Velero weekly 03:00
#   04:00-05:00 Sundays     ScyllaDB's repair
#   05:20-05:50 every day   the Pis' restore check 05:30
in_window() {  # the window the time is in ("<from>-<to>"), or nothing (exit 1)
  local hm dow w from to day
  hm=$(now_hm); dow=${UPGRADE_NOW_DOW:-$(date -u +%u)}
  for w in "00:50 04:00 any" "04:00 05:00 7" "05:20 05:50 any"; do
    read -r from to day <<< "$w"
    if { [ "$day" = any ] || [ "$day" = "$dow" ]; } && [[ ! $hm < $from ]] && [[ ! $hm > $to ]]; then
      echo "$from-$to at $hm"
      return 0
    fi
  done
  return 1
}

# 0. the gates
gates() {
  local w open branch head origin avail need today rec
  if w=$(in_window); then say "REFUSED: in a backup window ($w UTC) - run outside it"; return 1; fi
  open=$(scripts/upgrade-notice.sh open) || { say "REFUSED: the open pages not read"; return 1; }
  if [ -n "$open" ]; then
    run scripts/upgrade-notice.sh repost || say "NOTICE NOT SENT: the open pages' repost failed (see the log)"
    say "REFUSED: a one-way failure's page is open ($(echo $open)) - its fix first, then: scripts/upgrade-notice.sh resolve <unit>"
    return 1
  fi
  branch=$(git -C "$ops" rev-parse --abbrev-ref HEAD 2> /dev/null)
  [ "$branch" = main ] || { say "REFUSED: ops is on '$branch', not main - its tasks are what applies"; return 1; }
  [ -z "$(git -C "$ops" status --porcelain 2>&1)" ] || { say "REFUSED: ops has changes not on main - its tasks are what applies"; return 1; }
  git -C "$ops" fetch -q origin main >> "$log" 2>&1 || { say "REFUSED: origin's main not read"; return 1; }
  head=$(git -C "$ops" rev-parse HEAD 2> /dev/null); origin=$(git -C "$ops" rev-parse origin/main 2> /dev/null)
  [ -n "$head" ] && [ "$head" = "$origin" ] || { say "REFUSED: ops is not origin's main (${head:0:12} here, ${origin:0:12} there)"; return 1; }
  # the copy must fit: the guard's own figure (22.5 GB of VMs + its 2 GB)
  need=$(( 22528 + 2048 + 300 ))
  avail=$(awk '/^MemAvailable:/ {print int($2/1024)}' "${UPGRADE_MEMINFO:-/proc/meminfo}")
  [ "${avail:-0}" -ge "$need" ] || { say "REFUSED: memory - $avail of $need MB free: stop the radar (sudo systemctl stop radar-live), then run again"; return 1; }
  today=${UPGRADE_TODAY:-$(date -u +%F)}
  for rec in docs/upgrades/"$today"-*.md; do
    [ -e "$rec" ] && { say "REFUSED: a production apply today already ($rec) - one a day"; return 1; }
  done
  return 0
}
if [ -n "$preflight" ]; then
  gates && { say "PREFLIGHT: a run may start"; exit 0; }
  exit 1
fi
gates || exit 1

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
heads=$ops/.copy/upgrade-heads-$unit-$$.txt
read_heads() {  # the unit's pull requests' heads, "<repo> <number> <sha>" a line (into $1)
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
    run scripts/upgrade-label.py "$unit" upgrade-blocked
    notice blocked "$unit" "a one-way change with no backup path in the cycle yet - left for the operator" "$log"
    exit 1
  fi
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
  run scripts/upgrade-label.py "$unit" --merge --expect "$heads" || { notice blocked "$unit" "its merge failed" "$log"; exit 1; }
  if ! run scripts/upgrade-verify.sh; then
    notice blocked "$unit" "merged to the test environment, the cluster not settled after it - see the log" "$log"
    exit 1
  fi
  run scripts/upgrade-record.sh "$unit" "$log"
  notice applied "$unit" "the test environment's $unit applied and verified (its production unit next)" "$log"
  say "APPLIED $unit"
  exit 0
fi

# clones of the unit's branches - the agents' working directory, never the operator's trees
clones() {  # into $1, one per repo of the unit (from $heads)
  local dir=$1 repo
  [ -n "$dry" ] && { say "RUN clones of renovate/$unit into $dir"; return 0; }
  rm -rf "$dir"; mkdir -p "$dir"
  while read -r repo _ _; do
    [ -n "$repo" ] || continue
    git clone -q --branch "renovate/$unit" "https://git.pmon.dev/$repo.git" "$dir/${repo#*/}" >> "$log" 2>&1 || return 1
  done < "$heads"
}

# 2. the proof, one fix - the copy destroyed when the run ends, however it ends (the radar may start again)
trap 'run vagrant destroy -f' EXIT
prove() { run task test:copy:build && run task test:copy:unit UNIT="$unit"; }
read_heads "$heads" || { notice blocked "$unit" "its pull requests not read - nothing proven" "$log"; exit 1; }
if ! prove; then
  say "RED: $unit - the agent's fix"
  fixdir=$ops/.copy/upgrade-fix/$unit-$$
  if clones "$fixdir"; then
    [ -n "$dry" ] || cp "$log" "$fixdir/proof.log"
    run_in "$fixdir" "${clean_env[@]}" "$agent" -p "upgrade-cycle fix: the unit renovate/$unit failed its proof on the Vagrant copy (its log: proof.log here). Use the upgrade-fix skill: the unit's branches are cloned here (one directory per repo); diagnose from the log and the copy, commit one fix in each repo it needs and push it (git push), nothing to main, nothing to production." $(agent_flags fix) \
      || say "the fix agent ended non-zero - the proof again decides"
  else
    say "the unit's branches not cloned - no fix; the proof again decides"
  fi
  before=$(cat "$heads")
  read_heads "$heads" || { notice blocked "$unit" "its pull requests not read after the fix" "$log"; exit 1; }
  # the agent's commits kept from Renovate (it leaves a branch labelled stop-updating as it is)
  [ "$(cat "$heads")" = "$before" ] || run scripts/upgrade-label.py "$unit" stop-updating
  if ! prove; then
    run scripts/upgrade-label.py "$unit" upgrade-blocked
    notice blocked "$unit" "red after its fix - left for the operator" "$log"
    say "BLOCKED $unit"
    exit 1
  fi
fi
# what was proven is what is merged: the heads after the proof the ones read before it
after=$ops/.copy/upgrade-heads-after-$unit-$$.txt
read_heads "$after" || { notice blocked "$unit" "its pull requests not read after its proof - nothing applied" "$log"; exit 1; }
cmp -s "$heads" "$after" || { notice blocked "$unit" "its branches moved during its proof - nothing applied (the next run proves them)" "$log"; exit 1; }

# 3. the review - judged by its own output's last verdict line, nothing else
review=$ops/.copy/upgrade-review-$unit-$(date +%s)-$$.txt
revdir=$ops/.copy/upgrade-fix/$unit-review-$$
say "RUN $agent -p <the full review of renovate/$unit>"
if [ -z "$dry" ]; then
  clones "$revdir" || { notice blocked "$unit" "its branches not cloned for the review - nothing applied" "$log"; exit 1; }
  (cd "$revdir" && "${clean_env[@]}" "$agent" -p "upgrade-cycle review: run the full review of the unit renovate/$unit - its diff in each repo cloned here (one directory per repo) against origin/main, at medium; end with one line 'VERDICT: CLEAN' or 'VERDICT: CRITICAL <what>'. Change nothing." $(agent_flags review)) > "$review" 2>&1
  rc=$?
  cat "$review" >> "$log"
  verdict=$(grep -E '^VERDICT: ' "$review" | tail -1)
  if [ "$rc" -ne 0 ] || [ "$verdict" != "VERDICT: CLEAN" ]; then
    run scripts/upgrade-label.py "$unit" upgrade-blocked
    notice blocked "$unit" "its review blocks it (${verdict:-no verdict}, exit $rc)" "$review"
    say "BLOCKED $unit"
    exit 1
  fi
fi

# shadow: proven and reviewed is where the run ends - the result on the pull requests, nothing applied
if [ -n "$shadow" ]; then
  run scripts/upgrade-label.py "$unit" --comment "UPGRADE SHADOW $(date -u +%Y-%m-%dT%H:%M:%SZ) - $action: proven on the Vagrant copy and reviewed clean; nothing applied"
  say "SHADOW $unit"
  exit 0
fi

# 4. the gate
if [ "$action" = notice ]; then
  run scripts/upgrade-label.py "$unit" --comment "UPGRADE NOTICE $(date -u +%Y-%m-%dT%H:%M:%SZ) - applies after 24 h unless vetoed (label veto)"
  notice veto "$unit" "major $unit proven and reviewed - applies after 24 h unless vetoed (label veto on its PRs)" "$log"
  say "NOTICED $unit"
  exit 0
fi

# 5. the plan (read, or nothing applied) and the backup before a one-way change
if [ -n "$dry" ]; then
  say "RUN task test:copy:unit UNIT=$unit PLAN=true"; plan=""
else
  plan=$(task test:copy:unit UNIT="$unit" PLAN=true 2>> "$log" | grep -E '^test:copy:') \
    || { notice blocked "$unit" "its plan not read - nothing applied" "$log"; exit 1; }
fi
if grep -q 'upgrade-kubeadm.yml' <<< "$plan"; then
  run task --yes deploy:etcd:backup || { notice blocked "$unit" "the etcd backup before it failed - nothing applied" "$log"; exit 1; }
fi
stop_if_one_way

# 6. the apply - outside a backup window (one waited out: the proof and the review took their time)
while w=$(in_window); do
  say "WINDOW: $w UTC - the apply waits it out"
  [ -n "$dry" ] && break
  ${UPGRADE_SLEEP:-sleep} 300
done
run scripts/upgrade-label.py "$unit" --merge --expect "$heads" || { notice blocked "$unit" "its merge failed" "$log"; exit 1; }
run git -C "$ops" pull -q --ff-only origin main \
  || { notice one-way-failed "$unit" "merged, but ops not pulled - its production tasks not run (Argo applies infra's and platform's halves)" "$log"; exit 1; }
while IFS= read -r step; do
  [ -n "$step" ] || continue
  case "$step" in
    "test:copy:playbook PLAYBOOK=upgrade-kubeadm.yml"*) v=$(sed -n "s/.*k8s_upgrade_to=\([^ ']*\).*/\1/p" <<< "$step")
      run task --yes deploy:kubeadm:upgrade -- -e "k8s_upgrade_to=$v" ;;
    "test:copy:playbook PLAYBOOK=setup-kubeadm.yml"*) v=$(sed -n "s/.*cilium_version=\([^ ']*\).*/\1/p" <<< "$step")
      run task --yes deploy:cilium:upgrade -- -e "cilium_version=$v" ;;
    "test:copy:playbook PLAYBOOK=setup-argocd.yml"*) run task --yes deploy:argocd ;;
    "test:copy:playbook PLAYBOOK=upgrade-patroni.yml"*) run task --yes deploy:patroni:upgrade ;;
    "test:copy:playbook PLAYBOOK=upgrade-vault.yml"*) run task --yes deploy:vault:upgrade ;;
    "test:copy:playbook PLAYBOOK=upgrade-forgejo.yml"*) run task --yes deploy:forgejo:upgrade ;;
    "test:copy:change"*) : ;;  # Argo applies infra's and platform's merge
    *) notice one-way-failed "$unit" "an ops part with no production task: $step - merged, not run" "$log"; exit 1 ;;
  esac || { notice one-way-failed "$unit" "its production task failed: $step" "$log"; exit 1; }
done <<< "$plan"

# 7. verify
if ! run scripts/upgrade-verify.sh; then
  notice one-way-failed "$unit" "applied, production not settled after it - see the log" "$log"
  exit 1
fi

# 8. record
run task test:copy:inventory
run scripts/upgrade-record.sh "$unit" "$log"
notice applied "$unit" "$kind $unit applied and verified (the copy is gone: the radar may start)" "$log"
say "APPLIED $unit"
