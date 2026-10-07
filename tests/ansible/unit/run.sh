#!/bin/bash
# Runs every Ansible unit harness (localhost plays, no infrastructure). Each
# harness directory carries its own run.sh; a non-zero exit fails the build.
set -u
H=$(cd "$(dirname "$0")" && pwd)
# fenced: no harness reaches a real host - ssh, kubectl and vagrant here fail loudly (a harness's own stubs, earlier
# on its PATH, answer instead); one did, reading ten's clock over ssh (2026-10-07/08)
FENCE=$(mktemp -d)
trap 'rm -rf "$FENCE"' EXIT
for tool in ssh kubectl vagrant; do
  printf '#!/bin/sh\necho "FENCED: a unit harness ran %s $*" >&2\nexit 97\n' "$tool" > "$FENCE/$tool"
  chmod +x "$FENCE/$tool"
done
export PATH="$FENCE:$PATH"
rc=0
for r in "$H"/*/run.sh; do
  echo "== $(basename "$(dirname "$r")")"
  bash "$r" || rc=1
done
exit $rc
