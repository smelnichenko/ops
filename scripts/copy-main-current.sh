#!/usr/bin/env bash
# copy-main-current.sh - refuse to build the Vagrant copy from a stale main: scripts/vagrant-gitops-mirror.py clones the
# LOCAL repos, so each one's main must be what production's Argo CD tracks (origin/main, fetched now). A local main
# behind origin builds yesterday's production; one ahead builds a change production does not have.
#
# Usage: scripts/copy-main-current.sh <repo dir>...
set -euo pipefail
[ "$#" -gt 0 ] || { echo "usage: $0 <repo dir>..."; exit 2; }
bad=0
for repo in "$@"; do
  git -C "$repo" fetch -q origin main
  here=$(git -C "$repo" rev-parse main)
  there=$(git -C "$repo" rev-parse origin/main)
  if [ "$here" = "$there" ]; then
    echo "$repo: main $here = origin/main"
  else
    echo "$repo: main $here, origin/main $there - bring main to origin/main first"
    bad=1
  fi
done
exit "$bad"
