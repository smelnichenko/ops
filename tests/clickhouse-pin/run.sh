#!/bin/bash
# The ClickHouse rollback pin (the `compatibility` setting in the default profile, platform's clickhouse-users.xml):
# each upgrade's newer image, pinned to the version before it, writes and merges parts of production's logs table; the
# older image must then read every row back (the same count and checksum, no part detached, no read error). The same
# without the pin must fail - the run proves it can see the fault. With the real images, in docker on this machine
# (CI has no docker): steps 59 (24.8 -> 25.8) and 61 (25.8 -> 26.8).
#
# Measured 2026-10-06: both pins hold (602500 rows back on the older image); unpinned, 24.8 does not start on 25.8's
# parts, and 25.8 detaches 26.8's (half the rows gone).
#
# Usage: tests/clickhouse-pin/run.sh      (task test:clickhouse-pin)
set -uo pipefail
ops=$(cd "$(dirname "$0")/../.." && pwd)
schema=$ops/../platform/helm/schnappy-observability/files/clickhouse-logs-schema.sql
[ -r "$schema" ] || { echo "clickhouse-pin: no platform checkout next to ops ($schema)"; exit 2; }
W=$(mktemp -d "$ops/.upgrade/clickhouse-pin.XXXX")
container=clickhouse-pin-$$
cleanup() { docker rm -f "$container" > /dev/null 2>&1; docker volume rm -f "$container" > /dev/null 2>&1; rm -rf "$W"; }
trap cleanup EXIT
trap 'exit 130' INT TERM
sed 's/__TTL_DAYS__/3650/' "$schema" > "$W/logs.sql"
# each step's pin as its platform branch renders it (clickhouse-users.xml's default profile), not restated here
pin() {  # step -> the compatibility value of platform's upgrade/<step file's name>
  local branch
  branch=upgrade/$(basename "$ops"/tests/ansible/upgrade/steps/"$1"-*.txt .txt)
  git -C "$ops/../platform" show "$branch:helm/schnappy-observability/files/clickhouse-users.xml" \
    | sed -n 's|.*<compatibility>\([0-9.]*\)</compatibility>.*|\1|p'
}
pin59=$(pin 59) pin61=$(pin 61)
[ -n "$pin59" ] && [ -n "$pin61" ] || { echo "clickhouse-pin: no compatibility in steps 59/61's clickhouse-users.xml"; exit 2; }
for v in "$pin59" "$pin61"; do
  printf '<clickhouse><profiles><default><compatibility>%s</compatibility></default></profiles></clickhouse>\n' "$v" \
    > "$W/compat-$v.xml"
done

start() {  # image [compat file]: the server on the case's volume, answering
  docker rm -f "$container" > /dev/null 2>&1
  local args=(-d --name "$container" -v "$container:/var/lib/clickhouse")
  [ -n "${2:-}" ] && args+=(-v "$W/$2:/etc/clickhouse-server/users.d/compat.xml:ro")
  docker run "${args[@]}" "clickhouse/clickhouse-server:$1" > /dev/null || return 1
  for _ in $(seq 90); do
    docker exec "$container" clickhouse-client -q "SELECT 1" > /dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}
q() { docker exec "$container" clickhouse-client --format TSV -q "$1"; }
write() {  # first row, rows: a small insert makes a compact part, a large one wide parts
  q "INSERT INTO logs.podlogs SELECT toDateTime64('2026-10-01 00:00:00', 3, 'UTC') + number,
     ['info', 'warn'][number % 2 + 1], 'ns' || toString(number % 5), 'pod-' || toString(number), 'c', 'n',
     'app' || toString(number % 3), 'comp', 'stdout', repeat('message ', number % 40) || toString(number + $1),
     toString(number), '', map('k', toString(number)), map('f', toString(number % 7)) FROM numbers($1, $2)"
}
sums() { q "SELECT count(), sum(cityHash64(message, pod, mapValues(labels), mapValues(fields))) FROM logs.podlogs"; }

# case <old> <new> <compat file or ""> -> 0 when the old image read back everything the new one wrote, 1 when it did
# not, 2 when the case could not be set up (an image, the schema, a write on either) - never taken for either verdict
case_() {
  # a fresh volume each case (the container first: a volume in use is not removed - the next case ran on its parts)
  docker rm -f "$container" > /dev/null 2>&1
  docker volume rm -f "$container" > /dev/null 2>&1
  ! docker volume inspect "$container" > /dev/null 2>&1 || return 2
  start "$1" || return 2
  docker exec -i "$container" clickhouse-client --multiquery < "$W/logs.sql" || return 2
  write 0 1000 && write 1000 300000 || return 2
  start "$2" "$3" || return 2
  write 301000 1000 && write 302000 300000 && q "OPTIMIZE TABLE logs.podlogs FINAL" && write 602000 500 || return 2
  local new old detached errors
  new=$(sums) || return 2
  docker stop "$container" > /dev/null
  start "$1" || { echo "    $1 did not start on the parts"; return 1; }
  old=$(sums)
  detached=$(q "SELECT count() FROM system.detached_parts WHERE database = 'logs'")
  errors=$(docker logs "$container" 2>&1 | grep -ciE "cannot read|unknown serialization|corrupted|broken part")
  echo "    $2 wrote: $new; $1 read: $old, $detached parts detached, $errors read errors"
  [ "$new" = "$old" ] && [ "$detached" = 0 ] && [ "$errors" = 0 ]
}

# each step's images, from its step file's line: image clickhouse/clickhouse-server <old> => image ... <new>
images() { awk '$1 == "image" && $2 == "clickhouse/clickhouse-server" && $4 == "=>" {print $3, $7}' \
  "$ops"/tests/ansible/upgrade/steps/"$1"-*.txt; }
read -r old59 new59 < <(images 59)
read -r old61 new61 < <(images 61)
[ -n "${new59:-}" ] && [ -n "${new61:-}" ] || { echo "clickhouse-pin: no ClickHouse image line in steps 59 and 61"; exit 2; }

fails=0
check() {  # name, want (0 read back / 1 not), old, new, compat file
  local name=$1 want=$2; shift 2
  case_ "$@"; local rc=$?
  if [ "$rc" = "$want" ]; then echo "PASS $name"; else echo "FAIL $name (exit $rc)"; fails=$((fails + 1)); fi
}
check "59: $new59 pinned to $pin59 - $old59 reads its parts" 0 "$old59" "$new59" "compat-$pin59.xml"
check "59: $new59 unpinned - $old59 does not (the run sees the fault)" 1 "$old59" "$new59" ""
check "61: $new61 pinned to $pin61 - $old61 reads its parts" 0 "$old61" "$new61" "compat-$pin61.xml"
check "61: $new61 unpinned - $old61 does not (the run sees the fault)" 1 "$old61" "$new61" ""
echo "clickhouse-pin: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
