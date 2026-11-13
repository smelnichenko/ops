#!/bin/bash
# scripts/production-inventory.sh in a copy of its tree, ssh a stub playing ten and the Pis: production's inventory read
# (the test environment and the open preview environments left out - asked of ten by name), sorted, the Pis' pins
# written; refused, both files left as they were: ten listing no namespace, ten's or a Pi's inventory empty, a Pi
# service stale, not running or of no known version, the pins not written (two Pis at two versions).
set -u
ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts" "$T/deploy/ansible/playbooks/tasks" "$T/tests/ansible/copy" "$T/bin"
cp "$ROOT"/scripts/{production-inventory.sh,pi-versions.py,version-inventory.sh,version-inventory-pi.sh} "$T/scripts/"
cp -r "$ROOT/deploy/ansible/vars" "$T/deploy/ansible/"
cp "$ROOT"/deploy/ansible/playbooks/{setup-consul,setup-pi-services,setup-caddy}.yml "$T/deploy/ansible/playbooks/"
cp "$ROOT/deploy/ansible/playbooks/tasks/versitygw.yml" "$T/deploy/ansible/playbooks/tasks/"
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=$ROOT/deploy/ansible/venv/bin/python3
# the playbooks' own versions: the Pis run those (nothing to pin)
own=$("$PY" - "$T" <<'PY'
import re, sys, yaml
t = sys.argv[1]; pb = f"{t}/deploy/ansible/playbooks"
v = lambda f, k: str(yaml.safe_load(open(f"{t}/deploy/ansible/vars/{f}.yml"))[k])
pv = lambda f, k: str(yaml.safe_load(open(f"{pb}/{f}.yml"))[0]["vars"][k])
print(" ".join([f"forgejo={v('forgejo', 'forgejo_version')}", f"patroni={v('patroni', 'patroni_version')}",
                f"vault={v('vault', 'vault_version')}", f"consul={pv('setup-consul', 'consul_version')}",
                f"keycloak={pv('setup-pi-services', 'keycloak_version')}", f"caddy={pv('setup-caddy', 'caddy_version')}",
                "versitygw=" + re.search(r"vgw_version \| default\('([0-9.]+)'\)", open(f"{pb}/tasks/versitygw.yml").read())[1]]))
PY
)
# ssh <options...> <host> <command>: ten lists $NAMESPACES and answers its inventory (the exclusion it was asked for
# recorded); a Pi answers $PI_LINES (its name in place of @), pi2's $PI2_EXTRA after - or nothing (PI2_EMPTY)
cat > "$T/bin/ssh" <<'STUB'
#!/bin/bash
while [ "${1#-}" != "$1" ]; do shift 2; done
host=$1 cmd=$2
case "$host:$cmd" in
  *192.168.11.2:kubectl\ get\ namespaces*) printf '%s' "$NAMESPACES" ;;
  *192.168.11.2:INVENTORY_EXCLUDE_NAMESPACES=*) cat > /dev/null; echo "$cmd" > "$STUB_DIR/excluded"; printf '%s' "$TEN" ;;
  *192.168.11.4:*) cat > /dev/null; printf '%s' "${PI_LINES//@/pi1}" ;;
  *192.168.11.6:*) cat > /dev/null; [ -n "${PI2_EMPTY:-}" ] || printf '%s' "${PI_LINES//@/pi2}${PI2_EXTRA:-}" ;;
  *) echo "ssh stub: $*" >&2; exit 9 ;;
esac
STUB
chmod +x "$T/bin/ssh"
pi_lines=""
for kv in $own; do pi_lines+="pi @ ${kv%%=*} ${kv#*=}"$'\n'; done
export STUB_DIR=$T PATH="$T/bin:$PATH"
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi
}
INV=$T/tests/ansible/copy/prod-inventory.txt PINS=$T/tests/ansible/copy/pi-versions.yml
reset_files() { echo "OLD INVENTORY" > "$INV"; echo "# old pins" > "$PINS"; }
run() { out=$(bash "$T/scripts/production-inventory.sh" 2>&1); }
unchanged() { [ "$(cat "$INV")" = "OLD INVENTORY" ] && [ "$(cat "$PINS")" = "# old pins" ] && echo unchanged || echo changed; }
reset_files
NAMESPACES=$'namespace/default\nnamespace/schnappy-test\nnamespace/schnappy-pr-12\nnamespace/schnappy-pr-x\n' \
  TEN=$'image b/two 2\nimage a/one 1\n' PI_LINES=$pi_lines run; rc=$?
check "production read: ten's and both Pis' lines, sorted; nothing to pin" \
  "$rc $(head -2 "$INV" | tr '\n' ' ')$(grep -c '^pi pi[12] ' "$INV") $(grep -v '^#' "$PINS")" \
  "0 image a/one 1 image b/two 2 $((2 * $(wc -w <<< "$own"))) {}"
check "  the test environment and the open preview environments left out - only schnappy-pr-<number>" \
  "$(cat "$T/excluded")" "INVENTORY_EXCLUDE_NAMESPACES='schnappy-test schnappy-pr-12' bash -s"
reset_files
NAMESPACES="" TEN=$'image a/one 1\n' PI_LINES=$pi_lines run; rc=$?
check "ten listing no namespace (ssh failed): refused, both files as they were" "$rc $(unchanged)" "1 unchanged"
reset_files
NAMESPACES=$'namespace/default\n' TEN="" PI_LINES=$pi_lines run; rc=$?
check "ten's inventory empty: refused, both files as they were" "$rc $(unchanged)" "1 unchanged"
reset_files
NAMESPACES=$'namespace/default\n' TEN=$'image a/one 1\n' PI_LINES=$pi_lines PI2_EMPTY=1 run; rc=$?
check "one Pi's inventory empty (the other's alone would pin): refused, said, both files as they were" \
  "$rc $(grep -c "192.168.11.6's inventory came back empty" <<< "$out") $(unchanged)" "1 1 unchanged"
for word in stale not-running unknown; do
  reset_files
  NAMESPACES=$'namespace/default\n' TEN=$'image a/one 1\n' PI_LINES="${pi_lines}pi @ forgejo-runner $word"$'\n' run; rc=$?
  check "a Pi service $word: refused, said, both files as they were" \
    "$rc $(grep -c 'production.s version is not known' <<< "$out") $(unchanged)" "1 1 unchanged"
done
reset_files
NAMESPACES=$'namespace/default\n' TEN=$'image a/one 1\n' PI_LINES=$pi_lines PI2_EXTRA=$'pi pi2 patroni 0.0.1\n' run; rc=$?
check "the pins not written (the Pis at two Patroni versions): refused, both files as they were - never one without the other" \
  "$rc $(unchanged)" "1 unchanged"
echo "production-inventory: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
