#!/usr/bin/env bash
# copy-refs.sh - what the Vagrant copy runs now, in .copy/copy-refs ("<infra ref>@<commit> <platform ref>@<commit>
# [playbook:<file>...]"), for a test:copy:check run on its own: the commits to check against (a branch moved since reads
# the commit the copy runs, not its new tip), and whether the copy carries a change - a ref but main, or an ops playbook
# applied (it stays applied whatever is mirrored after it: only a build clears it). Written before the change is
# applied: one that fails half-way is still judged a change (fail closed). No file: the copy is main's.
#
# Usage: copy-refs.sh infra | platform | change       (the infra commit, the platform commit, yes/no)
#        copy-refs.sh reset                           (a build from nothing)
#        copy-refs.sh set <infra ref> <platform ref>  (a build: main main; a change: its refs - resolved to commits now)
#        copy-refs.sh playbook <file>                 (an ops playbook applied on top)
# Env:   COPY_INFRA_DIR, COPY_PLATFORM_DIR (default ../infra, ../platform beside ops); COPY_REFS_FILE
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
f=${COPY_REFS_FILE:-$ops/.copy/copy-refs}
infra_dir=${COPY_INFRA_DIR:-$ops/../infra}
platform_dir=${COPY_PLATFORM_DIR:-$ops/../platform}
read_refs() {
  infra=main platform=main extra=""
  if [ -f "$f" ]; then read -r infra platform extra < "$f" || true; fi
  infra=${infra:-main}
  platform=${platform:-main}
}
write() { mkdir -p "$(dirname "$f")"; echo "$1" > "$f.new" && mv "$f.new" "$f"; }
commit_of() {  # commit_of <repo dir> <ref>: "<ref>@<commit>"
  local c
  c=$(git -C "$1" rev-parse -q --verify "$2^{commit}") || { echo "no ref $2 in $1" >&2; return 1; }
  echo "$2@$c"
}
case "${1:-}" in
  infra) read_refs; echo "${infra##*@}" ;;
  platform) read_refs; echo "${platform##*@}" ;;
  change)
    read_refs
    if [ "${infra%@*} ${platform%@*}" = "main main" ] && [ -z "$extra" ]; then echo no; else echo yes; fi ;;
  reset) rm -f "$f" ;;
  set)
    [ "$#" = 3 ] || { echo "usage: $0 set <infra ref> <platform ref>"; exit 2; }
    read_refs
    i=$(commit_of "$infra_dir" "$2") && p=$(commit_of "$platform_dir" "$3")
    write "$i $p${extra:+ $extra}" ;;
  playbook)
    [ "$#" = 2 ] || { echo "usage: $0 playbook <file>"; exit 2; }
    read_refs
    write "$infra $platform${extra:+ $extra} playbook:$2" ;;
  *) echo "usage: $0 infra|platform|change | reset | set <infra> <platform> | playbook <file>"; exit 2 ;;
esac
