#!/bin/bash
# Runs every Ansible unit harness (localhost plays, no infrastructure). Each
# harness directory carries its own run.sh; a non-zero exit fails the build.
# Usage: tests/ansible/unit/run.sh [harness directory, default this one]
set -u
# a directory that is none fails (an empty H globbed /*/run.sh)
H=$(cd "${1:-$(dirname "$0")}" && pwd) || exit 1
# fenced: no harness reaches a real host - ssh, kubectl and vagrant here fail loudly (a harness's own stubs, earlier
# on its PATH, answer instead); one did, reading ten's clock over ssh (2026-10-07/08). Each call leaves a hit, and a
# harness that left one fails - also when it tolerated the call's failure (the exit 97 could pass a negative case, the
# FENCED line unseen). FENCE exported: a harness that rebuilds its PATH puts it first again
FENCE=$(mktemp -d)
export FENCE
trap 'rm -rf "$FENCE" "${scratch:-}"' EXIT
for tool in ssh kubectl vagrant; do
  printf '#!/bin/sh\necho "FENCED: a unit harness ran %s $*" >&2\necho "%s $*" >> "%s/hits"\nexit 97\n' \
    "$tool" "$tool" "$FENCE" > "$FENCE/$tool"
  chmod +x "$FENCE/$tool"
done
export PATH="$FENCE:$PATH"
shopt -s nullglob
harnesses=("$H"/*/run.sh)
[ "${#harnesses[@]}" -gt 0 ] || { echo "no harness in $H (a directory of harness directories)"; exit 1; }
rc=0
for r in "${harnesses[@]}"; do
  echo "== $(basename "$(dirname "$r")")"
  # a temp directory of its own, removed after it: what it leaves goes with it (eleven left Python temp directories
  # in /tmp - RAM here - on every run)
  scratch=$(mktemp -d)
  # each harness started as CI's container and a terminal start it: no signal blocked (a tool's shell blocks SIGCHLD -
  # harmless to bash's traps, measured 2026-10-08, but not how CI runs them); every signal a harness's cases send at
  # its default - an ignored one survives the exec and cannot be trapped by bash (a caller's `nohup` or background job
  # ignoring INT made a stop case pass on nothing); SIGPIPE and SIGXFSZ too: Python ignores them (a write to a closed
  # pipe then no longer ends a shell - vagrant-smoke's heartbeat case)
  TMPDIR=$scratch python3 -c 'import os, signal, sys
signal.pthread_sigmask(signal.SIG_SETMASK, [])
for s in (signal.SIGPIPE, signal.SIGXFSZ, signal.SIGINT, signal.SIGHUP, signal.SIGQUIT, signal.SIGTERM):
    signal.signal(s, signal.SIG_DFL)
os.execvp("bash", ["bash", sys.argv[1]])' "$r" || rc=1
  rm -rf "$scratch"
  if [ -s "$FENCE/hits" ]; then
    echo "FENCED: $(basename "$(dirname "$r")") reached a real host: $(tr '\n' ';' < "$FENCE/hits")"
    rc=1
  fi
  : > "$FENCE/hits"
done
exit $rc
