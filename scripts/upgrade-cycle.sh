#!/usr/bin/env bash
# The upgrade cycle's night (docs/plans/120-automated-upgrade-cycle.md, part 2): one Renovate unit - picked, proven on
# the Vagrant copy (one fix by the Claude agent when red), reviewed, gated (a major waits out its 24 h notice), backed
# up before a one-way change, applied to production, verified, recorded, reported (scripts/upgrade-notice.sh: one mail
# to the single admin address). A run that cannot finish changes nothing in production and says so.
#
#   1. window   outside the backup windows (UTC 01:50-04:00, 05:20-05:50); the copy must fit in memory - the operator
#               stops the radar for it: while it does not fit, one notice, then it waits until the night's deadline
#   2. pick     scripts/upgrade-units.py pick - NOTHING / PAUSED end the night quietly
#   3. prove    task test:copy:build, task test:copy:unit UNIT=<it>; red: the agent's fix (one, pushed to the unit's
#               branches), proven again; red again: labelled upgrade-blocked, reported, the night ends
#   4. review   the full review of the unit's diff (the agent, headless) - a Critical finding blocks like a red proof
#   5. gate     patch/minor: on; a major's first night: its notice (UPGRADE NOTICE comment + mail), the night ends;
#               a major whose notice ran out unvetoed: on
#   6. backup   a one-way change takes its stores' backup first (etcd for Kubernetes); one with no backup path yet is
#               blocked, never applied blind
#   7. apply    the unit's pull requests merged by the bot (Argo syncs infra and platform); ops main pulled, then each
#               ops part's PRODUCTION task, the proof's own order (task --yes deploy:...)
#   8. verify   Argo settled, every pod ready, no critical alert; red: reported (a one-way failure pages)
#   9. record   docs/upgrades/<date>-<unit>.md committed, production's inventory read again
#   the copy is destroyed when the night ends, however it ends (the operator's radar may start again)
#
# Usage: scripts/upgrade-cycle.sh [--dry|--shadow]
#        --dry     every step said, nothing run
#        --shadow  the plan's rollout step 2: picked, proven, reviewed, the result a comment on the unit's pull requests -
#                  no notice, no merge, nothing applied
# Env:   UPGRADE_DEADLINE (HH:MM local, the latest a proof may start - default 23:59), UPGRADE_FORGEJO_TOKEN (the bot's),
#        UPGRADE_AGENT (the agent's command, default claude), UPGRADE_NOW_HM (HH:MM UTC, the harness's clock)
set -uo pipefail
export LC_ALL=C
ops=$(cd "$(dirname "$0")/.." && pwd)
cd "$ops" || exit 1
dry=""; shadow=""
case "${1:-}" in
  "") ;;
  --dry) dry=1 ;;
  --shadow) shadow=1 ;;
  *) echo "REFUSED: upgrade-cycle.sh [--dry|--shadow]"; exit 2 ;;
esac
log=$ops/.copy/upgrade-cycle-$(date +%Y%m%d-%H%M%S)-$$.log  # each night its own: a verdict is never an earlier night's
mkdir -p "$ops/.copy"
say() { echo "$(date '+%F %T') $*" | tee -a "$log"; }
run() {  # a step: said, and run unless --dry; its output in the log
  say "RUN $*"
  [ -n "$dry" ] && return 0
  "$@" >> "$log" 2>&1
}
notice() { run scripts/upgrade-notice.sh "$@"; }
agent=${UPGRADE_AGENT:-claude}

# 1. the window
hm=${UPGRADE_NOW_HM:-$(date -u +%H:%M)}
for w in "01:50 04:00" "05:20 05:50"; do
  set -- $w
  if [[ ! $hm < $1 ]] && [[ ! $hm > $2 ]]; then say "WINDOW: $hm UTC is in a backup window ($1-$2) - not tonight"; exit 0; fi
done

# 2. the pick
picked=$(scripts/upgrade-units.py pick) || { say "NOT READ: Forgejo - the night changes nothing ($picked)"; exit 1; }
say "PICK $picked"
case "$picked" in
  NOTHING|PAUSED) exit 0 ;;
esac
read -r action unit kind <<< "$picked"
[[ $action =~ ^(prove|notice|apply)$ && $unit =~ ^[a-z0-9][a-z0-9.-]*$ && $kind =~ ^(patch|minor|major)$ ]] \
  || { say "REFUSED: the pick's answer '$picked'"; exit 1; }

# the copy must fit: the guard's own figure (22.5 GB of VMs + its 2 GB); one notice, then waits until the deadline
need=$(( 22528 + 2048 + 300 ))
deadline=${UPGRADE_DEADLINE:-23:59}
told=""
while :; do
  avail=$(awk '/^MemAvailable:/ {print int($2/1024)}' "${UPGRADE_MEMINFO:-/proc/meminfo}")
  [ "$avail" -ge "$need" ] && break
  if [ -z "$told" ]; then
    notice blocked "$unit" "tonight's unit waits for memory ($avail of $need MB) - stop the radar (sudo systemctl stop radar-live)"
    told=1
  fi
  if [ -n "$dry" ] || [[ $(date +%H:%M) > $deadline ]]; then say "MEMORY: $avail MB, $need needed - the unit waits for another night"; exit 0; fi
  sleep 300
done

# 3. the proof, one fix - the copy destroyed when the night ends, however it ends (the radar may start again)
trap 'run vagrant destroy -f' EXIT
prove() { run task test:copy:build && run task test:copy:unit UNIT="$unit"; }
if ! prove; then
  say "RED: $unit - the agent's fix"
  run "$agent" -p "upgrade-cycle fix: the unit renovate/$unit failed its proof on the Vagrant copy (log $log). Use the upgrade-fix skill: diagnose from the log and the copy, push one fix commit to renovate/$unit in each repo it needs (label the PRs stop-updating), nothing to main, nothing to production." \
    || true
  if ! prove; then
    run scripts/upgrade-label.py "$unit" upgrade-blocked
    notice blocked "$unit" "red after its fix - left for the operator" "$log"
    say "BLOCKED $unit"
    exit 1
  fi
fi

# 4. the review - judged by its own output's last verdict line, nothing else
review=$ops/.copy/upgrade-review-$unit-$(date +%s)-$$.txt
say "RUN $agent -p <the full review of renovate/$unit>"
if [ -z "$dry" ]; then
  "$agent" -p "upgrade-cycle review: run the full review of the unit renovate/$unit (its diff in infra, platform and ops against main) at medium; end with one line 'VERDICT: CLEAN' or 'VERDICT: CRITICAL <what>'. Fix nothing on main." > "$review" 2>&1
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

# shadow: proven and reviewed is where the night ends - the result on the pull requests, nothing applied
if [ -n "$shadow" ]; then
  run scripts/upgrade-label.py "$unit" --comment "UPGRADE SHADOW $(date -u +%Y-%m-%dT%H:%M:%SZ) - $action: proven on the Vagrant copy and reviewed clean; nothing applied (rollout step 2)"
  say "SHADOW $unit"
  exit 0
fi

# 5. the gate
if [ "$action" = notice ]; then
  run scripts/upgrade-label.py "$unit" --comment "UPGRADE NOTICE $(date -u +%Y-%m-%dT%H:%M:%SZ) - applies after 24 h unless vetoed (label veto)"
  notice veto "$unit" "major $unit proven and reviewed - applies after 24 h unless vetoed (label veto on its PRs)" "$log"
  say "NOTICED $unit"
  exit 0
fi

# 6. the backup before a one-way change
plan=$(task test:copy:unit UNIT="$unit" PLAN=true 2> /dev/null | grep -E '^test:copy:') || true
if grep -q 'upgrade-kubeadm.yml' <<< "$plan"; then
  run ssh ten "kubectl -n kube-system create job --from=cronjob/etcd-backup etcd-backup-before-$unit && kubectl -n kube-system wait --for=condition=complete job/etcd-backup-before-$unit --timeout=300s"
fi
if grep -qE '(postgresql|scylla|kafka|clickhouse|strimzi|grafana|consul|vault)-[0-9]+\.x' <<< "$unit"; then
  run scripts/upgrade-label.py "$unit" upgrade-blocked
  notice blocked "$unit" "a one-way change with no backup path in the cycle yet - left for the operator" "$log"
  exit 1
fi

# 7. the apply: merges, then the ops parts' production tasks
run scripts/upgrade-label.py "$unit" --merge || { notice blocked "$unit" "its merge failed" "$log"; exit 1; }
run git -C "$ops" pull -q --ff-only origin main
while IFS= read -r step; do
  case "$step" in
    "test:copy:playbook PLAYBOOK=upgrade-kubeadm.yml"*) v=$(sed -n "s/.*k8s_upgrade_to=\([^ ']*\).*/\1/p" <<< "$step")
      run task --yes deploy:kubeadm:upgrade -- -e "k8s_upgrade_to=$v" ;;
    "test:copy:playbook PLAYBOOK=setup-kubeadm.yml"*) v=$(sed -n "s/.*cilium_version=\([^ ']*\).*/\1/p" <<< "$step")
      run task --yes deploy:cilium:upgrade -- -e "cilium_version=$v" ;;
    "test:copy:playbook PLAYBOOK=upgrade-patroni.yml"*) run task --yes deploy:patroni:upgrade ;;
    "test:copy:playbook PLAYBOOK=upgrade-vault.yml"*) run task --yes deploy:vault:upgrade ;;
    "test:copy:playbook PLAYBOOK=upgrade-forgejo.yml"*) run task --yes deploy:forgejo:upgrade ;;
    "test:copy:change"*) : ;;  # Argo applies infra's and platform's merge
    *) notice one-way-failed "$unit" "an ops part with no production task: $step - merged, not run" "$log"; exit 1 ;;
  esac || { notice one-way-failed "$unit" "its production task failed: $step" "$log"; exit 1; }
done <<< "$plan"

# 8. verify
if ! run scripts/upgrade-verify.sh; then
  notice one-way-failed "$unit" "applied, production not settled after it - see the log" "$log"
  exit 1
fi

# 9. record
run task test:copy:inventory
run scripts/upgrade-record.sh "$unit" "$log"
notice applied "$unit" "$kind $unit applied and verified (the copy is gone: the radar may start)" "$log"
say "APPLIED $unit"
