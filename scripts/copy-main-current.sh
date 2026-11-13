#!/usr/bin/env bash
# copy-main-current.sh - refuse to build or change the Vagrant copy on a stale base: scripts/vagrant-gitops-mirror.py
# clones the LOCAL repos, so each one's main must be what production's Argo CD tracks (origin/main, fetched now) - a
# local main behind origin builds yesterday's production; one ahead builds a change production does not have. A
# change's ref (<dir>:<ref>, not main) must contain origin/main: one cut from an older main tests "the change minus
# what production got since". When production's main moved since the copy was built (.copy/copy-built, the mains the
# build mirrored), the change's run is warned: those commits come with it and read as its own lines.
#
# Usage: scripts/copy-main-current.sh <repo dir>[:<ref>]...
# Env:   COPY_BUILT_FILE (default .copy/copy-built beside this script's repo: "<repo name> <commit>" lines)
set -euo pipefail
[ "$#" -gt 0 ] || { echo "usage: $0 <repo dir>[:<ref>]..."; exit 2; }
bad=0
built_file=${COPY_BUILT_FILE:-$(cd "$(dirname "$0")/.." && pwd)/.copy/copy-built}
for arg in "$@"; do
  repo=${arg%%:*}
  ref=main
  [ "$arg" = "$repo" ] || ref=${arg#*:}
  git -C "$repo" fetch -q origin main
  there=$(git -C "$repo" rev-parse origin/main)
  if [ "$ref" = main ]; then
    here=$(git -C "$repo" rev-parse main)
    if [ "$here" = "$there" ]; then
      echo "$repo: main $here = origin/main"
    else
      echo "$repo: main $here, origin/main $there - bring main to origin/main first"
      bad=1
    fi
  elif ! git -C "$repo" rev-parse -q --verify "$ref^{commit}" > /dev/null; then
    echo "$repo: no ref $ref"
    bad=1
  elif git -C "$repo" merge-base --is-ancestor "$there" "$ref"; then
    echo "$repo: $ref contains origin/main $there"
    built=$(awk -v r="$(basename "$repo")" '$1 == r {print $2}' "$built_file" 2> /dev/null || true)
    if [ -n "$built" ] && [ "$built" != "$there" ]; then
      echo "$repo: WARNING - production's main moved $(git -C "$repo" rev-list --count "$built..$there" 2> /dev/null || echo ?) commit(s) since the copy was built at $built: they come with $ref, its inventory reads them as its own"
    fi
  else
    echo "$repo: $ref does not contain origin/main $there - rebase it on origin/main first"
    bad=1
  fi
done
exit "$bad"
