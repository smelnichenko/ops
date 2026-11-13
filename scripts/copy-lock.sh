#!/usr/bin/env bash
# copy-lock.sh - one copy run at a time: the Vagrant copy and its record in .copy/ (the refs it runs, the mirrored
# commits a settle waits on, the inventories a change is judged by) are shared, and two runs interleaved - another
# session mirroring main while a change's checks run - pass the change on main's state. The lock is the outermost go-task
# process this runs under (test:copy:build calls test:copy:argo: one run, one owner), held while that process lives (its
# pid and start time: a pid reused by another process is no owner). Taken by every copy task first; another live owner
# refuses, named.
#
# Usage: scripts/copy-lock.sh
# Env:   COPY_LOCK_FILE (default .copy/copy-lock), COPY_LOCK_OWNER (a pid: the owner, for tests)
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
lock=${COPY_LOCK_FILE:-$ops/.copy/copy-lock}
mkdir -p "$(dirname "$lock")"
start_of() {  # start_of <pid>: its start in clock ticks since boot (/proc/<pid>/stat field 22); nothing when gone
  local st
  read -r st 2> /dev/null < "/proc/$1/stat" || return 0
  set -- ${st##*) }
  echo "${20}"
}
owner=${COPY_LOCK_OWNER:-}
if [ -z "$owner" ]; then
  # the outermost go-task process above this one; none (run by hand): this script's parent
  p=$PPID
  owner=$PPID
  while [ "$p" -gt 1 ]; do
    read -r comm 2> /dev/null < "/proc/$p/comm" || break
    [ "$comm" != task ] || owner=$p
    read -r st < "/proc/$p/stat"
    set -- ${st##*) }
    p=$2
  done
fi
me="$owner $(start_of "$owner")"
exec 9> "$lock.guard"
flock 9
if read -r held_pid held_start 2> /dev/null < "$lock" && [ "$held_pid $held_start" != "$me" ] \
  && [ -n "$held_start" ] && [ "$(start_of "$held_pid")" = "$held_start" ]; then
  echo "REFUSED: another copy run holds the Vagrant copy - $(tr '\0' ' ' < "/proc/$held_pid/cmdline" 2> /dev/null | cut -c1-120) (pid $held_pid)"
  exit 1
fi
echo "$me" > "$lock"
echo "the Vagrant copy held by pid $owner"
