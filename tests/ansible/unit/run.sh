#!/bin/bash
# Runs every Ansible unit harness (localhost plays, no infrastructure). Each
# harness directory carries its own run.sh; a non-zero exit fails the build.
# Usage: tests/ansible/unit/run.sh [harness directory, default this one]
# UNIT_JOBS harnesses run side by side, as processes (default 4: CI's container has 4 CPUs - one by one the suite
# outgrew Woodpecker's 60 min limit, 2026-10-20); each one's output is printed whole, in the suite's order.
set -u
# a directory that is none fails (an empty H globbed /*/run.sh)
H=$(cd "${1:-$(dirname "$0")}" && pwd) || exit 1
JOBS=${UNIT_JOBS:-4}
[[ $JOBS =~ ^[1-9][0-9]*$ ]] || { echo "UNIT_JOBS=$JOBS: a positive number of harnesses at once"; exit 1; }
# everything the runner makes lives here, removed at its end (a harness's own temp directory too: eleven left Python
# temp directories in /tmp - RAM here - on every run)
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
shopt -s nullglob
harnesses=("$H"/*/run.sh)
[ "${#harnesses[@]}" -gt 0 ] || { echo "no harness in $H (a directory of harness directories)"; exit 1; }

# run_one <index> <run.sh>: the harness's output in $ROOT/<index>.log, its verdict (0/1) in $ROOT/<index>.rc
run_one() {
  local i=$1 r=$2 name fence scratch rc=0
  name=$(basename "$(dirname "$r")")
  # fenced: no harness reaches a real host - ssh, kubectl and vagrant here fail loudly (a harness's own stubs, earlier
  # on its PATH, answer instead); one did, reading ten's clock over ssh (2026-10-07/08). Each call leaves a hit, and a
  # harness that left one fails - also when it tolerated the call's failure (the exit 97 could pass a negative case, the
  # FENCED line unseen). A fence of its own per harness, so the one named is the one that called; FENCE exported: a
  # harness that rebuilds its PATH puts it first again
  fence="$ROOT/fence-$i"; scratch="$ROOT/tmp-$i"
  mkdir -p "$fence" "$scratch"
  for tool in ssh kubectl vagrant; do
    printf '#!/bin/sh\necho "FENCED: a unit harness ran %s $*" >&2\necho "%s $*" >> "%s/hits"\nexit 97\n' \
      "$tool" "$tool" "$fence" > "$fence/$tool"
    chmod +x "$fence/$tool"
  done
  {
    echo "== $name"
    # each harness started as CI's container and a terminal start it: no signal blocked (a tool's shell blocks SIGCHLD -
    # harmless to bash's traps, measured 2026-10-08, but not how CI runs them); every signal a harness's cases send at
    # its default - an ignored one survives the exec and cannot be trapped by bash (a caller's `nohup`, or this runner's
    # own background jobs, which ignore INT and QUIT, made a stop case pass on nothing); SIGPIPE and SIGXFSZ too: Python
    # ignores them (a write to a closed pipe then no longer ends a shell - vagrant-smoke's heartbeat case)
    FENCE=$fence PATH="$fence:$PATH" TMPDIR=$scratch python3 -c 'import os, signal, sys
signal.pthread_sigmask(signal.SIG_SETMASK, [])
for s in (signal.SIGPIPE, signal.SIGXFSZ, signal.SIGINT, signal.SIGHUP, signal.SIGQUIT, signal.SIGTERM):
    signal.signal(s, signal.SIG_DFL)
os.execvp("bash", ["bash", sys.argv[1]])' "$r" < /dev/null || rc=1
    if [ -s "$fence/hits" ]; then
      echo "FENCED: $name reached a real host: $(tr '\n' ';' < "$fence/hits")"
      rc=1
    fi
  } > "$ROOT/$i.log" 2>&1
  rm -rf "$fence" "$scratch"
  echo "$rc" > "$ROOT/$i.rc.tmp" && mv "$ROOT/$i.rc.tmp" "$ROOT/$i.rc"
}

rc=0
next=0   # the first harness whose output is not printed yet
# flush: print every finished harness's output from $next on, in the suite's order, up to the first still running
flush() {
  while [ "$next" -lt "${#harnesses[@]}" ] && [ -e "$ROOT/$next.rc" ]; do
    cat "$ROOT/$next.log"
    [ "$(cat "$ROOT/$next.rc")" = 0 ] || rc=1
    next=$((next + 1))
  done
}
running=0
for i in "${!harnesses[@]}"; do
  if [ "$running" -ge "$JOBS" ]; then
    wait -n
    running=$((running - 1))
    flush
  fi
  run_one "$i" "${harnesses[$i]}" &
  running=$((running + 1))
done
wait
flush
exit $rc
