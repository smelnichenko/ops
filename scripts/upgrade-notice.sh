#!/usr/bin/env bash
# The upgrade cycle's pages - a one-way change that failed part-way through its apply, production perhaps half
# changed: recorded here, and the runner refuses to start while one is open, until production is checked, the fix done
# and the page resolved. Nothing is mailed or posted anywhere (operator 2026-11-20: the runs are started by hand and
# their terminal says what happened) - the runner prints the page where it stops.
#
# Usage: scripts/upgrade-notice.sh page <unit> <summary> [<details file>]   record a page (its details: the run's log)
#        scripts/upgrade-notice.sh resolve <unit>                            production checked, the fix done: its record gone
#        scripts/upgrade-notice.sh open                                      the open pages' units, one a line
# Env:   UPGRADE_PAGES  where the pages are recorded (default ops' .upgrade-cycle/pages - not .copy's scratch: the
#                       runner's refusal must outlive a cleanup)
set -euo pipefail
export LC_ALL=C
ops=$(cd "$(dirname "$0")/.." && pwd)
pages=${UPGRADE_PAGES:-$ops/.upgrade-cycle/pages}
usage="REFUSED: upgrade-notice.sh page <unit> <summary> [<details file>] | resolve <unit> | open"

valid_unit() { [[ ${1:-} =~ ^[a-z0-9][a-z0-9.-]*$ ]] || { echo "REFUSED: '${1:-}' is no unit's name"; exit 2; }; }

case "${1:-}" in
  open)
    [ $# -eq 1 ] || { echo "$usage"; exit 2; }
    # a page recorded before 2026-11-20 is a .json file: still open
    for f in "$pages"/*.page "$pages"/*.json; do [ -e "$f" ] && basename "${f%.*}"; done
    exit 0 ;;
  resolve)
    [ $# -eq 2 ] || { echo "$usage"; exit 2; }
    valid_unit "$2"
    [ -e "$pages/$2.page" ] || [ -e "$pages/$2.json" ] || { echo "REFUSED: no open page for $2"; exit 1; }
    rm -f "$pages/$2.page" "$pages/$2.json"
    echo "RESOLVED $2"
    exit 0 ;;
  page)
    [ $# -ge 3 ] && [ $# -le 4 ] || { echo "$usage"; exit 2; }
    valid_unit "$2"
    [ -n "$3" ] || { echo "REFUSED: a page says what failed (its summary)"; exit 2; }
    [ -z "${4:-}" ] || [ -r "$4" ] || { echo "REFUSED: $4 not readable"; exit 2; }
    mkdir -p "$pages"
    { echo "unit $2"; echo "at $(date -u +%FT%TZ)"; echo "what $3"; [ -z "${4:-}" ] || echo "log $4"; } > "$pages/$2.page"
    echo "PAGE $2: $3"
    exit 0 ;;
  *) echo "$usage"; exit 2 ;;
esac
