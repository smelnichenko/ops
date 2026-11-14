#!/bin/bash
# scripts/upgrade-record.sh - the upgrade cycle's record of an applied unit - in a throwaway git repo (the script copied
# into it, an inventory record beside): docs/upgrades/<date>-<unit>.md with the night's steps (its other lines left out,
# a secret in them masked) and production's inventory diff, committed as the renovate-bot, [CI SKIP], the inventory
# with it; not pushed without the bot's token (said, exit 1); refused: a name that is no unit's, a log not readable.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
REAL=$PWD
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
R=$W/ops
mkdir -p "$R/scripts" "$R/tests/ansible/copy"
cp "$REAL/scripts/upgrade-record.sh" "$R/scripts/"
printf 'image a 1\nimage b 1\n' > "$R/tests/ansible/copy/prod-inventory.txt"
(cd "$R" && g init -q && g add -A && g commit -qm base)
printf 'image a 2\nimage b 1\n' > "$R/tests/ansible/copy/prod-inventory.txt"
LOG=$W/night.log
cat > "$LOG" <<'L'
2026-11-20 20:00:01 PICK prove wave-patches patch
some tool chatter that is not a step
2026-11-20 20:00:02 RUN task test:copy:build
2026-11-20 21:10:00 RUN scripts/upgrade-label.py wave-patches --merge TOKEN=abc123
2026-11-20 22:30:00 APPLIED wave-patches
L
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi; }
out=$(cd "$R" && UPGRADE_RECORD_NO_PUSH=1 bash scripts/upgrade-record.sh wave-patches "$LOG" 2>&1); rc=$?
day=$(date -u +%Y-%m-%d)
rec="$R/docs/upgrades/$day-wave-patches.md"
check "recorded, committed" "$rc $(head -c 8 <<< "$out")" "0 RECORDED"
check "the night's steps alone, the secret masked" "$(sed -n '/^```$/,/^```$/p' "$rec" | sed -n 2,5p)" \
"2026-11-20 20:00:01 PICK prove wave-patches patch
2026-11-20 20:00:02 RUN task test:copy:build
2026-11-20 21:10:00 RUN scripts/upgrade-label.py wave-patches --merge TOKEN=***
2026-11-20 22:30:00 APPLIED wave-patches"
check "production's inventory diff in it" "$(sed -n '/^```diff$/,/^```$/p' "$rec" | grep -E '^[-+]' | tr '\n' ' ')" "-image a 1 +image a 2 "
check "committed as the renovate-bot, [CI SKIP], with the inventory" \
  "$(git -C "$R" log -1 --format='%an <%ae>|%s' ) $(git -C "$R" show --name-only --format= HEAD | sort | tr '\n' ' ')" \
  "Renovate Bot <renovate-bot@pmon.dev>|upgrade cycle: wave-patches applied $day [CI SKIP] docs/upgrades/$day-wave-patches.md tests/ansible/copy/prod-inventory.txt "
printf 'image a 3\n' > "$R/tests/ansible/copy/prod-inventory.txt"
out=$(cd "$R" && env -u UPGRADE_FORGEJO_TOKEN bash scripts/upgrade-record.sh valkey-9.x "$LOG" 2>&1); rc=$?
check "no token: committed, not pushed, said" "$rc $(tail -1 <<< "$out")" "1 NOT PUSHED: no UPGRADE_FORGEJO_TOKEN"
out=$(cd "$R" && bash scripts/upgrade-record.sh 'Bad/Unit' "$LOG" 2>&1); rc=$?
check "a name that is no unit's: refused" "$rc" 2
out=$(cd "$R" && bash scripts/upgrade-record.sh wave-patches /nope 2>&1); rc=$?
check "a log not readable: refused" "$rc" 2
echo "upgrade-record: $([ $fails -eq 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails -eq 0 ]
