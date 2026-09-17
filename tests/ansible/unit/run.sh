#!/bin/bash
# Runs every Ansible unit harness (localhost plays, no infrastructure). Each
# harness directory carries its own run.sh; a non-zero exit fails the build.
set -u
H=$(cd "$(dirname "$0")" && pwd)
rc=0
for r in "$H"/*/run.sh; do
  echo "== $(basename "$(dirname "$r")")"
  bash "$r" || rc=1
done
exit $rc
