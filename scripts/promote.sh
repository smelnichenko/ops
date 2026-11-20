#!/usr/bin/env bash
# promote.sh - the test environment's image tags to production's: each service's tag in infra's test values read against
# production's, the plan printed; with --run, production's values rewritten, committed and pushed (Argo then syncs
# production). task promote:check prints the plan, task promote:run writes it - two tasks, no mode variable (operator
# 2026-11-20). The services named, or every one when none is (operator: "no SERVICES like SERVICES=all").
#
# Usage: scripts/promote.sh [--run] [all | <service>...]   (services: monitor admin chat chess masi site game-scp; none: all)
# Env:   INFRA (infra's checkout, default <ops>/../infra)
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
infra=${INFRA:-$(dirname "$ops")/infra}
ALL="monitor admin chat chess masi site game-scp"
run=""
names=()
for a in "$@"; do
  case "$a" in
    --run) run=1 ;;
    all) names+=($ALL) ;;
    *) [[ " $ALL " == *" $a "* ]] || { echo "REFUSED: no service '$a' - one of: $ALL (or all)" >&2; exit 2; }
       names+=("$a") ;;
  esac
done
[ "${#names[@]}" -gt 0 ] || names=($ALL)
cd "$infra"
# CD writes a tag commit to infra on every merge: the tags read from what is on the remote NOW, not from a checkout
# that may be hours old (a stale one promotes yesterday's image)
[ -z "$(git status --porcelain)" ] || { echo "REFUSED: infra has uncommitted changes - commit or discard them first" >&2; exit 1; }
git pull -q --rebase
TEST=clusters/production/schnappy-test-apps/values.yaml
PROD=clusters/production/schnappy-production-apps/values.yaml
tag_of() {  # tag_of <values file> <service>: the quoted tag on the line commented "# <service>"; nothing when there is none
  sed -n -E "s/.*tag: \"([^\"]+)\"[[:space:]]*#[[:space:]]*$2[[:space:]]*$/\1/p" "$1" | head -n 1
}
plan=(); svcs=""
for svc in "${names[@]}"; do
  tag=$(tag_of "$TEST" "$svc")
  if [ -z "$tag" ]; then echo "  ! $svc: not found in test values - skipping"; continue; fi
  cur=$(tag_of "$PROD" "$svc")
  if [ "$tag" = "$cur" ]; then
    echo "  = $svc: $cur (up to date)"
  else
    echo "  + $svc: ${cur:-<none>} -> $tag"
    plan+=("$svc=$tag"); svcs="$svcs $svc"
  fi
done
if [ "${#plan[@]}" = 0 ]; then echo "Nothing to promote."; exit 0; fi
if [ -z "$run" ]; then
  echo; echo "The plan only - task promote:run commits and pushes it (SERVICES=\"...\" limits it; Argo then syncs production)."
  exit 0
fi
for entry in "${plan[@]}"; do
  svc=${entry%=*}; tag=${entry#*=}
  # the quotes kept: CD's own promote step reads the quoted form
  sed -i -E "s|(tag: \")[^\"]*(\"[[:space:]]*#[[:space:]]*${svc}[[:space:]]*)$|\1${tag}\2|" "$PROD"
  [ "$(tag_of "$PROD" "$svc")" = "$tag" ] || { echo "NOT WRITTEN: $svc's tag in $PROD - nothing committed" >&2; git checkout -q -- "$PROD"; exit 1; }
done
git add "$PROD"
git commit -q -m "promote(prod):$svcs from test"
# a CD run may have pushed in the seconds since the pull above: the commit is made, so rebase it and push
# (2026-09-21: the push was rejected and the promotion sat unpushed until somebody noticed)
git pull -q --rebase
git push -q
echo "Promoted:$svcs. Argo will sync production."
