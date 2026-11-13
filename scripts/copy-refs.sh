#!/usr/bin/env bash
# copy-refs.sh - what the Vagrant copy runs now, in .copy/copy-refs ("<infra ref> <platform ref>[ playbook:<file>]"),
# for a test:copy:check run on its own: the refs to check against, and whether the copy carries a change (any ref but
# main, or an ops playbook applied) - its inventory then judged as a change's. No file: the copy is main's.
#
# Usage: copy-refs.sh infra | platform | change       (prints the infra ref, the platform ref, yes/no)
#        copy-refs.sh set <infra ref> <platform ref>  (a build: main main; a change: its refs)
#        copy-refs.sh playbook <file>                 (an ops playbook applied on top of the refs)
set -euo pipefail
f=${COPY_REFS_FILE:-$(cd "$(dirname "$0")/.." && pwd)/.copy/copy-refs}
read_refs() {
  infra=main platform=main extra=""
  if [ -f "$f" ]; then read -r infra platform extra < "$f" || true; fi
  : "${infra:=main}" "${platform:=main}"
}
case "${1:-}" in
  infra) read_refs; echo "$infra" ;;
  platform) read_refs; echo "$platform" ;;
  change) read_refs; if [ "$infra $platform" = "main main" ] && [ -z "$extra" ]; then echo no; else echo yes; fi ;;
  set)
    [ "$#" = 3 ] || { echo "usage: $0 set <infra ref> <platform ref>"; exit 2; }
    mkdir -p "$(dirname "$f")"; echo "$2 $3" > "$f.new" && mv "$f.new" "$f" ;;
  playbook)
    [ "$#" = 2 ] || { echo "usage: $0 playbook <file>"; exit 2; }
    read_refs; mkdir -p "$(dirname "$f")"; echo "$infra $platform playbook:$2" > "$f.new" && mv "$f.new" "$f" ;;
  *) echo "usage: $0 infra|platform|change | set <infra> <platform> | playbook <file>"; exit 2 ;;
esac
