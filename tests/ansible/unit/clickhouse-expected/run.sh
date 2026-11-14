#!/bin/bash
# scripts/clickhouse-expected.sh - ClickHouse's compatibility setting and users as a platform ref sets them, for the
# copy's survival seed and verify - against a git repository of this test's own (COPY_PLATFORM_DIR):
#   - the compatibility the file's default profile names, `-` with none; the users the file lists, sorted, plus the
#     image's `default` unless the list replaces it; no <users> element: `default` alone;
#   - refused (nothing printed, exit 1): a compatibility that is no version (`25.`, `25`, a template), a user name
#     outside letters, digits, `_` and `-` (a dot, an accented letter - both valid XML names), a file that is no XML, a ref or file
#     not there; the reason said.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi
}
export COPY_PLATFORM_DIR="$W/platform"
F=helm/schnappy-observability/files/clickhouse-users.xml
git init -q "$COPY_PLATFORM_DIR"
mkdir -p "$COPY_PLATFORM_DIR/$(dirname "$F")"
ref() {  # ref <name> <xml>: a branch whose clickhouse-users.xml is that
  git -C "$COPY_PLATFORM_DIR" checkout -q -B "$1" 2> /dev/null
  printf '%s\n' "$2" > "$COPY_PLATFORM_DIR/$F"
  git -C "$COPY_PLATFORM_DIR" add -A && git -C "$COPY_PLATFORM_DIR" -c user.name=t -c user.email=t@t commit -qm "$1"
}
expect() { out=$(bash scripts/clickhouse-expected.sh "$1" 2> "$W/err"); rc=$?; err=$(cat "$W/err"); }
ref pinned '<clickhouse><profiles><default><compatibility>25.8</compatibility></default></profiles><users replace="replace"><schnappy/><grafana/></users></clickhouse>'
ref open '<clickhouse><profiles><default/></profiles><users><grafana/></users></clickhouse>'
ref nousers '<clickhouse><profiles><default><compatibility>26.3</compatibility></default></profiles></clickhouse>'
expect pinned
check "a pin and a replacing list: the compatibility, the users sorted, no default" "$rc $out" "0 25.8 grafana,schnappy"
expect open
check "no pin, a list that adds: '-', the image's default with the file's users" "$rc $out" "0 - default,grafana"
expect nousers
check "no <users> element: default alone" "$rc $out" "0 26.3 default"
for compat in "25." "25" "25.8.1" "{{lookup('pipe','id')}}"; do
  ref "c-$RANDOM" "<clickhouse><profiles><default><compatibility>$compat</compatibility></default></profiles><users><grafana/></users></clickhouse>"
  expect "$(git -C "$COPY_PLATFORM_DIR" branch --show-current)"
  check "a compatibility that is no major.minor version ($compat): refused, said, nothing printed" \
    "$rc ${out:-none} $(grep -c 'not a version and user names' <<< "$err")" "1 none 1"
done
for user in "a.b" "usér"; do
  ref "u-$RANDOM" "<clickhouse><profiles><default/></profiles><users><$user/><grafana/></users></clickhouse>"
  expect "$(git -C "$COPY_PLATFORM_DIR" branch --show-current)"
  check "a user name outside letters, digits, _ and - ($user, a valid XML name): refused, said" \
    "$rc ${out:-none} $(grep -c 'not a version and user names' <<< "$err")" "1 none 1"
done
ref broken '<clickhouse><users>'
expect broken
check "a file that is no XML: refused, said" "$rc ${out:-none} $(grep -c 'not parsed' <<< "$err")" "1 none 1"
expect no-such-ref
check "a ref not there: refused, said" "$rc ${out:-none} $(grep -c 'not read from platform no-such-ref' <<< "$err")" "1 none 1"
out=$(bash scripts/clickhouse-expected.sh 2>&1); rc=$?
check "no ref given: usage, refused" "$((rc != 0)) $(grep -c 'usage' <<< "$out")" "1 1"
echo "clickhouse-expected: $([ "$fails" -eq 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ "$fails" -eq 0 ]
