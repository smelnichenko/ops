#!/bin/bash
# scripts/upgrade-notice.sh - the upgrade cycle's pages, recorded and never sent (operator 2026-11-20: no mail from the
# cycle - the runs are started by hand): a page written with what failed and the run's log, listed open until resolved
# (one recorded before 2026-11-20 as .json among them); a bad name, no summary, an unreadable log, a kind it no longer
# has (applied, veto, blocked, one-way-failed, repost) refused; nothing reaches the network (ssh, wget, curl - each
# recording - never run).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
check() {  # name got want
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got  $2"; echo "    want $3"; fails=$((fails + 1)); fi
}
mkdir -p "$W/bin"
for tool in ssh wget curl; do printf '#!/bin/sh\necho "%s $*" >> "%s/net"\nexit 0\n' "$tool" "$W" > "$W/bin/$tool"; chmod +x "$W/bin/$tool"; done
notice() {  # notice <args...>: its exit code; its output in $W/out
  PATH="$W/bin:$PATH" UPGRADE_PAGES="$W/pages" scripts/upgrade-notice.sh "$@" > "$W/out" 2>&1
  echo $?
}
echo "a run's log" > "$W/run.log"
check "a page: recorded with what failed and the run's log, said" \
  "$(notice page istio-1.32 "verify failed after the merge" "$W/run.log") $(grep -c "^PAGE istio-1.32: verify failed after the merge$" "$W/out") $(sed -n 's/^\(unit\|what\|log\) //p' "$W/pages/istio-1.32.page" | tr '\n' '|') $(grep -cE '^at [0-9]{4}-[0-9]{2}-[0-9]{2}T' "$W/pages/istio-1.32.page")" \
  "0 1 istio-1.32|verify failed after the merge|$W/run.log| 1"
check "  open: listed" "$(notice open) $(cat "$W/out")" "0 istio-1.32"
printf '[{"labels": {}}]\n' > "$W/pages/kafka-4.x.json"
check "  a page recorded before 2026-11-20 (.json): open too" "$(notice open) $(tr '\n' ' ' < "$W/out")" "0 istio-1.32 kafka-4.x "
check "resolve: the record gone, open no more" "$(notice resolve istio-1.32) $(cat "$W/out") $([ -e "$W/pages/istio-1.32.page" ] && echo kept || echo gone) $(notice open) $(tr '\n' ' ' < "$W/out")" \
  "0 RESOLVED istio-1.32 gone 0 kafka-4.x "
check "  the old one resolved the same" "$(notice resolve kafka-4.x) $(notice open) $(cat "$W/out")" "0 0 "
check "  resolve with no open page: refused" "$(notice resolve istio-1.32) $(grep -c 'no open page' "$W/out")" "1 1"
check "a page without its log: recorded" "$(notice page u1 "a one-way change failed") $(grep -c '^log ' "$W/pages/u1.page")" "0 0"
check "refused: a name that is no unit's, no summary, a log not readable" \
  "$(notice page 'Bad/Name' s) $(notice page u2 '') $(notice page u2 s "$W/missing") $([ -e "$W/pages/u2.page" ] && echo written || echo none)" "2 2 2 none"
check "refused: the kinds that mailed (applied, veto, blocked, one-way-failed), repost, nothing at all" \
  "$(for k in applied veto blocked one-way-failed repost ''; do notice $k u3 s; done | tr '\n' ' ')" "2 2 2 2 2 2 "
check "nothing reaches the network: no ssh, wget or curl run" "$(cat "$W/net" 2> /dev/null | wc -l)" "0"
check "the script's code names no network tool, mail or Alertmanager (its comments aside)" "$(grep -v '^ *#' scripts/upgrade-notice.sh | grep -ciE 'ssh|wget|curl|smtp|mail|alertmanager')" "0"
check "the mail sender gone (scripts/upgrade-mail.py)" "$([ -e scripts/upgrade-mail.py ] && echo there || echo gone)" "gone"
if [ "$fails" = 0 ]; then echo "upgrade-notice: ALL-PASS"; else echo "upgrade-notice: $fails FAILED"; exit 1; fi
