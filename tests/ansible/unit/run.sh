#!/bin/bash
# Runs every Ansible unit harness (localhost plays, no infrastructure). Each
# harness directory carries its own run.sh; a non-zero exit fails the build.
# Usage: tests/ansible/unit/run.sh [harness directory, default this one]
set -u
H=$(cd "${1:-$(dirname "$0")}" && pwd)
# fenced: no harness reaches a real host - ssh, kubectl and vagrant here fail loudly (a harness's own stubs, earlier
# on its PATH, answer instead); one did, reading ten's clock over ssh (2026-10-07/08). Each call leaves a hit, and a
# harness that left one fails - also when it tolerated the call's failure (the exit 97 could pass a negative case, the
# FENCED line unseen). FENCE exported: a harness that rebuilds its PATH puts it first again
FENCE=$(mktemp -d)
export FENCE
trap 'rm -rf "$FENCE"' EXIT
for tool in ssh kubectl vagrant; do
  printf '#!/bin/sh\necho "FENCED: a unit harness ran %s $*" >&2\necho "%s $*" >> "%s/hits"\nexit 97\n' \
    "$tool" "$tool" "$FENCE" > "$FENCE/$tool"
  chmod +x "$FENCE/$tool"
done
export PATH="$FENCE:$PATH"
rc=0
for r in "$H"/*/run.sh; do
  echo "== $(basename "$(dirname "$r")")"
  # no signal blocked, as CI's container and a terminal start it: a caller's blocked SIGCHLD (a tool's shell) is
  # inherited, and a bash trap no longer runs during `wait` - build-with-pin's signal cases failed here, passing in CI.
  # SIGPIPE and SIGXFSZ back to their defaults: Python ignores them, and an ignored signal survives the exec (a write
  # to a closed pipe then no longer ends a shell - vagrant-smoke's heartbeat case)
  python3 -c 'import os, signal, sys
signal.pthread_sigmask(signal.SIG_SETMASK, [])
for s in (signal.SIGPIPE, signal.SIGXFSZ):
    signal.signal(s, signal.SIG_DFL)
os.execvp("bash", ["bash", sys.argv[1]])' "$r" || rc=1
  if [ -s "$FENCE/hits" ]; then
    echo "FENCED: $(basename "$(dirname "$r")") reached a real host: $(tr '\n' ';' < "$FENCE/hits")"
    rc=1
  fi
  : > "$FENCE/hits"
done
exit $rc
