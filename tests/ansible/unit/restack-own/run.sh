#!/bin/bash
# scripts/upgrade-restack-in-place.sh's own(): a step branch's own change, compared before and after a restack - the
# same change at other line numbers hashes the same, the same lines under another section (git's function context: a
# YAML top-level key) do not, another value does not. The function as the script holds it, on a scratch repository.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi
}
fn=$(sed -n '/^own() {$/,/^}$/p' scripts/upgrade-restack-in-place.sh)
[ -n "$fn" ] || { echo "FAIL no own() in scripts/upgrade-restack-in-place.sh"; echo "restack-own: 1 FAILED"; exit 1; }
eval "$fn"
g() { git -C "$W/r" -c user.name=t -c user.email=t@t "$@" > /dev/null; }
mkdir "$W/r" && g init -q -b main
# two components, the same field under each
printf 'grafana:\n  image: a:1\n  x: 1\nmimir:\n  image: a:1\n  x: 1\n' > "$W/r/values.yaml"
g add values.yaml && g commit -qm base && base=$(git -C "$W/r" rev-parse HEAD)
change() {  # change <sed expression>: the commit of that change on base, its own()
  g checkout -q "$base" && sed -i "$1" "$W/r/values.yaml" && g commit -qam c
  (cd "$W/r" && own "$base" HEAD)
}
a=$(change '2s/a:1/a:2/')          # grafana's image
b=$(change '5s/a:1/a:2/')          # mimir's: the same lines, another section
c=$(change '2s/a:1/a:3/')          # grafana's, another value
# grafana's change again, on a base with lines added above its section (the change rebased: other line numbers)
g checkout -q "$base" && printf 'top: 1\nmore: 2\n%s\n' "$(cat "$W/r/values.yaml")" > "$W/r/values.yaml" && g commit -qam moved
base2=$(git -C "$W/r" rev-parse HEAD)
sed -i '4s/a:1/a:2/' "$W/r/values.yaml" && g commit -qam c2
d=$(cd "$W/r" && own "$base2" HEAD)
check "the same lines under another section: another change" "$([ "$a" != "$b" ] && echo differ)" "differ"
check "another value: another change" "$([ "$a" != "$c" ] && echo differ)" "differ"
check "the same change at other line numbers: the same" "$d" "$a"
echo "restack-own: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
