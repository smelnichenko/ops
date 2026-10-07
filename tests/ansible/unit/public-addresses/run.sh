#!/bin/bash
# tests/ansible/public-addresses.py - production's public addresses for the Vagrant isolation, from a public resolver
# (dig a stub): every A record, each a global address outside production's LAN - a resolver that answers the LAN's
# address (a router intercepting DNS) made the proof drop an address already dropped and probe it: "blocked", the
# public one still reachable. Nothing answered, a private or shared answer, the LAN's: refused.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
printf '#!/bin/sh\necho "$*" >> "$W/args"\nprintf "%%b" "$ANSWER"\nexit "${DIG_RC:-0}"\n' > "$W/bin/dig"
chmod +x "$W/bin/dig"
fails=0
case_() {  # case_ <name> <dig's answer> <want rc 0|1> <want output>
  out=$(W=$W ANSWER=$2 PATH="$W/bin:$PATH" python3 tests/ansible/public-addresses.py pmon.dev 192.168.11.0/24 2>&1)
  rc=$?; [ $rc = 0 ] || rc=1
  if [ "$rc" = "$3" ] && grep -qF -- "$4" <<< "$out"; then echo "PASS $1"; return; fi
  echo "FAIL $1 (rc $rc, want $3): $out"; fails=$((fails + 1))
}
case_ "one public address" '84.52.11.130\n' 0 "84.52.11.130"
case_ "two: both" '84.52.11.130\n84.52.11.131\n' 0 "84.52.11.130 84.52.11.131"
case_ "a CNAME before them: the addresses only" 'edge.example.net.\n84.52.11.130\n' 0 "84.52.11.130"
case_ "the LAN's address (DNS intercepted): refused" '192.168.11.2\n' 1 "not a public address"
case_ "a public one and the LAN's: refused" '84.52.11.130\n192.168.11.2\n' 1 "not a public address"
case_ "a private address elsewhere: refused" '10.0.0.5\n' 1 "not a public address"
case_ "a shared (CGNAT) address: refused" '100.64.0.7\n' 1 "not a public address"
case_ "nothing answered: refused" '' 1 "no A record"
DIG_RC=9 case_ "dig failing: refused" '' 1 "dig failed"
check_args=$(W=$W ANSWER='84.52.11.130\n' PATH="$W/bin:$PATH" python3 tests/ansible/public-addresses.py pmon.dev \
  192.168.11.0/24 > /dev/null 2>&1; tail -1 "$W/args")
if [ "$check_args" = "+short @1.1.1.1 pmon.dev A" ]; then echo "PASS asked of a public resolver"
else echo "FAIL asked as '$check_args'"; fails=$((fails + 1)); fi
echo "public-addresses: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
