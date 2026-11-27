#!/bin/bash
# Keycloak's upgrade and its way back run by ansible-playbook for real (plan 122): upgrade-keycloak.yml and
# restore-keycloak.yml with their tasks, copied, against two stand-in Pis - connection local, each Pi a directory of
# state (the version /opt/keycloak names, the version running, its unit, its HTTP answer, its installs, its dumps) and a
# shell of its own that puts stubs first (stubs/: systemctl, pgrep, readlink, curl, ip, psql, pg_dump). The modules that
# touch a host are swapped by name for stand-ins (library/kc_*: systemd, uri, get_url, unarchive, stat, file). What the
# keycloak-upgrade harness cannot see is seen here, in each run's events: which Pi a run_once task ran on, hostvars
# across Pis, what a `when:` skipped, the order things happen across both Pis. The serve check's 15-min wait is cut to
# seconds in the copy (a Pi that never serves fails in seconds). Real psql, pg_dump and Keycloak: the copy's
# rehearsal (tests/ansible/copy/keycloak-way-back-check.yml).
set -u
H=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$H/../../../.." && pwd)
AP=$(command -v ansible-playbook 2>/dev/null \
  || { [ -x "$ROOT/deploy/ansible/venv/bin/ansible-playbook" ] && echo "$ROOT/deploy/ansible/venv/bin/ansible-playbook"; })
[ -x "${AP:-}" ] || { echo "keycloak-smoke: no ansible-playbook found (PATH, repo venv)"; exit 2; }
PY=$(dirname "$(readlink -f "$AP")")/python3; [ -x "$PY" ] || PY=python3
unset ANSIBLE_CONFIG
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
ck() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2], want [$3]"; fails=$((fails + 1)); fi; }

# ── the production playbooks, copied, each module that touches a host swapped for its stand-in ───────────────────
mkdir -p "$W/ansible/playbooks/tasks" "$W/ansible/vars" "$W/tmp"
cp "$ROOT"/deploy/ansible/playbooks/{upgrade,restore}-keycloak.yml "$W/ansible/playbooks/"
cp "$ROOT"/deploy/ansible/playbooks/tasks/keycloak-{dump,serves,restore}.yml "$W/ansible/playbooks/tasks/"
cp "$ROOT/deploy/ansible/vars/keycloak.yml" "$W/ansible/vars/"
"$PY" -I - "$W/ansible/playbooks" <<'PY_SWAP' || exit 1
import glob, os, re, sys
P = sys.argv[1]
files = sorted(glob.glob(os.path.join(P, "*.yml")) + glob.glob(os.path.join(P, "tasks", "*.yml")))
text = {f: open(f).read() for f in files}
used = {}
for m in ("systemd", "uri", "get_url", "unarchive", "stat", "file"):
    for f in files:
        used[m] = used.get(m, 0) + text[f].count(f"ansible.builtin.{m}:")
        text[f] = text[f].replace(f"ansible.builtin.{m}:", f"kc_{m}:")
# a module this harness does not stand in for would touch the machine it runs on: refused, by name
left = sorted({(os.path.basename(f), m) for f in files for m in re.findall(r"ansible\.builtin\.(\w+):", text[f])
               if m not in ("assert", "set_fact", "shell", "command", "include_tasks", "meta", "debug")})
# the serve check's wait cut to seconds; restore-keycloak's dumps read where each stand-in Pi keeps its own
edits = [("tasks/keycloak-serves.yml", "retries: 90", "retries: 3"), ("tasks/keycloak-serves.yml", "delay: 10", "delay: 1"),
         ("restore-keycloak.yml", "ls -1t /var/backups/keycloak/", "ls -1t dumps/")]
bad = [e for e in edits if text[os.path.join(P, e[0])].count(e[1]) != 1]
for f, a, b in edits:
    text[os.path.join(P, f)] = text[os.path.join(P, f)].replace(a, b)
missing = [m for m, n in used.items() if n == 0]
if left or bad or missing:
    print(f"keycloak-smoke: the playbooks changed under this harness - modules not stood in for {left}, "
          f"edits that found no single text {bad}, stand-ins nothing uses {missing}")
    sys.exit(1)
for f in files:
    open(f, "w").write(text[f])
PY_SWAP
printf '[defaults]\nretry_files_enabled = False\ninterpreter_python = %s\n' "$PY" > "$W/ansible.cfg"
for h in pi1 pi2; do
  printf '#!/bin/sh\nexport KC_HOST=%s PATH="%s:$PATH"\ncd "$KCS/%s" || exit 1\nexec /bin/sh "$@"\n' "$h" "$H/stubs" "$h" > "$W/shell-$h"
  chmod +x "$W/shell-$h"
done
cat > "$W/inv.yml" <<INV_KS
all:
  children:
    pis:
      hosts:
        pi1: {ansible_shell_executable: $W/shell-pi1}
        pi2: {ansible_shell_executable: $W/shell-pi2}
  vars:
    ansible_connection: local
    ansible_become: false
    keepalived_vip: 10.9.9.9
    postgres_admin_password: s3cret
INV_KS
SHA=$(printf 'ab%.0s' $(seq 32))

# ── the stand-in Pis, a run, what it did ─────────────────────────────────────────────────────────────────────────
# new <name> <the Pi holding the VIP, or none>: a fresh pair
new() { KCS="$W/run-$1"; export KCS; mkdir -p "$KCS/pi1/dumps" "$KCS/pi2/dumps"; : > "$KCS/events.log"; printf %s "$2" > "$KCS/vip"; }
# inst <pi> <version> [cut]: /opt/keycloak-<version> there - whole, or cut short (its runner missing)
inst() {
  mkdir -p "$KCS/installs/$1/$2/bin" "$KCS/installs/$1/$2/lib"; : > "$KCS/installs/$1/$2/bin/kc.sh"
  [ -n "${3:-}" ] || : > "$KCS/installs/$1/$2/lib/quarkus-run.jar"
}
# pi <pi> <version linked> <version(s) running, '' when down> [unit state]: the Pi's Keycloak, its linked install whole
pi() {
  inst "$1" "$2"; printf %s "$2" > "$KCS/$1/link"; printf %s "$3" > "$KCS/$1/running"
  printf %s "${4:-$([ -n "$3" ] && echo active || echo inactive)}" > "$KCS/$1/active"
  printf %s "$([ -n "$3" ] && echo 200 || echo 000)" > "$KCS/$1/http"
}
# dump <pi> <file name> [cut]: a dump in the Pi's dumps - whole (pg_dump's trailer), or cut short
dump() { { echo "CREATE TABLE realm();"; [ -n "${3:-}" ] || echo "-- PostgreSQL database dump complete"; } | gzip > "$KCS/$1/dumps/$2"; }
play() {
  local pb=$1; shift
  (cd "$W/ansible/playbooks" && ANSIBLE_CONFIG="$W/ansible.cfg" ANSIBLE_LIBRARY="$H/library" ANSIBLE_MODULE_UTILS="$H/module_utils" \
     ANSIBLE_LOCAL_TEMP="$W/tmp" ANSIBLE_REMOTE_TMP="$W/tmp" ANSIBLE_NOCOLOR=1 ANSIBLE_STDOUT_CALLBACK=default \
     ANSIBLE_HOST_KEY_CHECKING=False "$AP" -i "$W/inv.yml" "$pb" "$@") > "$KCS/out" 2>&1
  echo $? > "$KCS/rc"
}
up() { play upgrade-keycloak.yml -e keycloak_version=26.8.2 -e keycloak_sha256="$SHA" -e dump_dir=dumps "$@"; }
back() { play restore-keycloak.yml "$@"; }
rc() { cat "$KCS/rc"; }
refused() { [ "$(rc)" != 0 ] && grep -q -- "$1" "$KCS/out" && echo refused || echo "rc $(rc), '$1' $(grep -c -- "$1" "$KCS/out")x"; }
on() { awk -v e="$1" '$3 == e {print $2}' "$KCS/events.log" | paste -sd' ' -; }        # the Pis an event ran on, in order
onset() { awk -v e="$1" '$3 == e {print $2}' "$KCS/events.log" | sort -u | paste -sd' ' -; }  # ... on both Pis at once: which
nev() { wc -l < "$KCS/events.log" | tr -d ' '; }
first() { awk -v e="$1" '$3 == e {print NR; exit}' "$KCS/events.log"; }
last() { awk -v e="$1" '$3 == e {n = NR} END {print n}' "$KCS/events.log"; }
before() { local a b; a=$(last "$1"); b=$(first "$2"); [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] && echo yes || echo no; }
state() { echo "$(cat "$KCS/pi1/link")/$(cat "$KCS/pi1/running") $(cat "$KCS/pi2/link")/$(cat "$KCS/pi2/running")"; }
dumps() { (cd "$KCS" && ls pi1/dumps pi2/dumps | grep -c -E '^keycloak-[0-9]{8}T[0-9]{6}Z-'"$1"'-schema-26\.5\.0\.sql\.gz$'); }
said() { grep -q -- "$1" "$KCS/out" && echo said || echo silent; }

# ── upgrade-keycloak.yml ─────────────────────────────────────────────────────────────────────────────────────────
new A pi2; pi pi1 26.5.7 26.5.7; pi pi2 26.5.7 26.5.7; up
ck "A both on the old version, the VIP on pi2: done, both Pis running the target" "$(rc) $(state)" "0 26.8.2/26.8.2 26.8.2/26.8.2"
ck "A the schema read and the dump once, on the VIP's Pi (run_once, delegated); its dump there, named for the old version" \
   "$(on psql)|$(on pg_dump)|$(ls "$KCS/pi1/dumps" | wc -l) $(ls "$KCS/pi2/dumps" | wc -l) $(dumps 26\\.5\\.7)" "pi2|pi2|0 1 1"
ck "A the dump before any stop, every stop before any link, every link before any start" \
   "$(before pg_dump stopped) $(before stopped link) $(before link started)" "yes yes yes"
ck "A the VIP's Pi started first (it migrates), then the other" "$(on started)" "pi2 pi1"
ck "A each Pi: the tarball with its sha256, extracted, owned by keycloak, /opt/keycloak moved (force)" \
   "$(grep -c ' get_url sha256 ' "$KCS/events.log") $(onset unarchive) $(grep -c ' chown keycloak:keycloak recurse=True ' "$KCS/events.log") $(grep -c ' link 26.8.2 force=True' "$KCS/events.log")" \
   "2 pi1 pi2 2 2"
ck "A its summary: the Pi started first and the dump" "$(said 'pi2 started first; dump dumps/keycloak-')" said
new A2 pi1; pi pi1 26.5.7 26.5.7; pi pi2 26.5.7 26.5.7; up
ck "A2 the VIP on pi1: the dump there, pi1 started first" "$(rc) $(on pg_dump) | $(on started)" "0 pi1 | pi1 pi2"
new A3 none; pi pi1 26.5.7 26.5.7; pi pi2 26.5.7 26.5.7; up
ck "A3 the VIP on neither: the first in the play (pi1) dumps and starts first" "$(rc) $(on pg_dump) | $(on started)" "0 pi1 | pi1 pi2"
new B pi2; pi pi1 26.8.2 26.8.2; pi pi2 26.8.2 26.8.2; up
ck "B every Pi on the target and serving: nothing to do - nothing at all" "$(rc) $(nev)" "0 0"
new C pi2; pi pi1 26.8.2 ""; pi pi2 26.8.2 26.8.2; up
ck "C a run cut short after the swap (pi1 down on the target): taken forward - no download, dump, stop or link; started, VIP first" \
   "$(rc) [$(on get_url)$(on pg_dump)$(on psql)$(on stopped)$(on link)] $(on started) | $(state)" "0 [] pi2 pi1 | 26.8.2/26.8.2 26.8.2/26.8.2"
ck "C its summary says so" "$(said 'none - a run taken forward')" said
new G pi2; pi pi1 26.8.2 "" activating; pi pi2 26.8.2 26.8.2; up
ck "G taken forward, pi1's unit already starting (maybe migrating): pi1 first, whatever holds the VIP" "$(rc) $(on started)" "0 pi1 pi2"
new M pi2; pi pi1 26.5.7 ""; pi pi2 26.5.7 ""; up
ck "M a clean stop (both down on the old install): resumed - dumped, named for that install, moved, the VIP's first" \
   "$(rc) $(on pg_dump) $(dumps 26\\.5\\.7) $(on started) | $(state)" "0 pi2 1 pi2 pi1 | 26.8.2/26.8.2 26.8.2/26.8.2"
new K pi2; pi pi1 26.5.7 ""; pi pi2 26.8.2 26.8.2; up
ck "K a half-moved pair (pi1 down on the OLD install, pi2 on the target): refused, nothing done" \
   "$(refused 'neither a run to take forward') $(nev)" "refused 0"
new Hd pi2; pi pi1 26.5.7 ""; pi pi2 26.5.7 26.5.7; up
ck "Hd one Pi down on the old install, the other up on it: refused, nothing done" "$(refused 'neither a run to take forward') $(nev)" "refused 0"
new I pi2; pi pi1 26.8.2 "" activating; pi pi2 26.8.2 "" activating; up
ck "I two Pis starting at once (two migrations): refused, nothing done" "$(refused 'two migrations of one database') $(nev)" "refused 0"
new D pi2; pi pi1 26.5.7 26.5.7; pi pi2 26.8.2 26.8.2; up
ck "D two versions on one database: refused, nothing done" "$(refused 'two versions on one database') $(nev)" "refused 0"
new T pi2; pi pi1 26.8.2 "26.5.7 26.8.2"; pi pi2 26.5.7 26.5.7; up
ck "T one Pi running two versions at once (a stale process): refused, nothing done" "$(refused 'at once - by hand') $(nev)" "refused 0"
new J pi2; pi pi1 27.0.1 27.0.1; pi pi2 27.0.1 27.0.1; up
ck "J newer than the target (a downgrade): refused, nothing done" "$(refused 'newer than 26.8.2') $(nev)" "refused 0"
new E pi2; pi pi1 26.5.7 26.5.7; pi pi2 26.5.7 26.5.7; up --limit pi1
ck "E --limit pi1: refused, nothing done" "$(refused 'REFUSED: the run has') $(nev)" "refused 0"
new L pi2; pi pi1 26.5.7 26.5.7; pi pi2 26.5.7 26.5.7; inst pi1 26.8.2 cut; up
ck "L a cut-short extract of the target on pi1 (skipped by creates): refused before the dump - nothing stopped" \
   "$(refused 'is incomplete') $(on unarchive) [$(on pg_dump)$(on stopped)$(on link)] $(state)" "refused pi2 [] 26.5.7/26.5.7 26.5.7/26.5.7"
new N pi2; pi pi1 26.5.7 26.5.7; pi pi2 26.5.7 26.5.7; echo yes > "$KCS/pi1/wont-start"; up
ck "N the other Pi not coming up on the target after its start: the run fails at the last serve check, the first serving" \
   "$([ "$(rc)" != 0 ] && echo failed) $(on started) $(state)" "failed pi2 pi1 26.8.2/ 26.8.2/26.8.2"
new F pi2; pi pi1 26.5.7 26.5.7; pi pi2 26.5.7 26.5.7; : > "$KCS/dump-fail"; up
ck "F pg_dump failing: refused with its own error before anything stops - no dump kept, nothing left aside" \
   "$(refused 'REFUSED: the Keycloak dump failed') $(said boom-from-stub) [$(on stopped)$(on link)] $(ls -A "$KCS/pi2/dumps" | wc -l) $(state)" \
   "refused said [] 0 26.5.7/26.5.7 26.5.7/26.5.7"
new F2 pi2; pi pi1 26.5.7 26.5.7; pi pi2 26.5.7 26.5.7; : > "$KCS/psql-fail"; up
ck "F2 the schema read failing: refused, saying so with psql's own error - no dump, nothing stopped" \
   "$(refused 'the database schema not read') $(said 'connection to server at 127.0.0.1 port 5000 failed') [$(on pg_dump)$(on stopped)]" \
   "refused said []"

# ── restore-keycloak.yml ─────────────────────────────────────────────────────────────────────────────────────────
OLD=keycloak-20261126T010000Z-26.5.6-schema-26.5.0.sql.gz; NEW=keycloak-20261127T010000Z-26.5.7-schema-26.5.0.sql.gz
two_on_target() { new "$1" "$2"; pi pi1 26.8.2 26.8.2; pi pi2 26.8.2 26.8.2; }
two_on_target R1 pi1; inst pi1 26.5.7; inst pi2 26.5.7; dump pi1 "$OLD"; dump pi2 "$NEW"; back -e keycloak_version=26.5.7 -e confirm="$NEW"
ck "R1 the newest dump (pi2's): restored, both Pis back on its version" "$(rc) $(state)" "0 26.5.7/26.5.7 26.5.7/26.5.7"
ck "R1 its SQL once, on the Pi holding it: dropped, created, loaded, the schema read" \
   "$(awk '$3 == "psql" {print $2 ":" $4}' "$KCS/events.log" | paste -sd' ' -)" "pi2:drop pi2:create pi2:load pi2:schema"
ck "R1 every Pi stopped before the drop, the database back before any link, the VIP's Pi started first" \
   "$(before stopped psql) $(before psql link) $(on started)" "yes yes pi1 pi2"
two_on_target R2 pi1; inst pi1 26.5.6; inst pi2 26.5.6; dump pi1 "$OLD"; dump pi2 "$NEW"
back -e keycloak_version=26.5.6 -e keycloak_restore_dump="dumps/$OLD" -e keycloak_restore_host=pi1 -e confirm="$OLD"
ck "R2 the dump given (pi1's older one): restored there, its version back" "$(rc) $(onset psql) $(state)" \
   "0 pi1 26.5.6/26.5.6 26.5.6/26.5.6"
two_on_target R7 pi2; inst pi1 26.5.7; inst pi2 26.5.7; dump pi1 "$NEW"; dump pi2 "$OLD"; back -e keycloak_version=26.5.7 -e confirm="$NEW"
ck "R7 the newest dump on pi1 (first in the play), the VIP on pi2: pi1's restored, pi2 started first" \
   "$(rc) $(onset psql) $(on started)" "0 pi1 pi2 pi1"
two_on_target R11 pi1; inst pi1 26.5.7; inst pi2 26.5.7; dump pi2 "$NEW"; echo yes > "$KCS/pi2/wont-start"; back -e keycloak_version=26.5.7 -e confirm="$NEW"
ck "R11 the other Pi not coming up after the restore: the run fails at the last serve check, the first serving" \
   "$([ "$(rc)" != 0 ] && echo failed) $(on started) $(state)" "failed pi1 pi2 26.5.7/26.5.7 26.5.7/"
two_on_target R3 pi1; inst pi1 26.5.7; dump pi2 "$NEW"; back -e keycloak_version=26.5.7 -e confirm="$NEW"
ck "R3 the dump's version's install gone on pi2: refused, nothing stopped, no SQL" "$(refused 'is gone on pi2') $(nev)" "refused 0"
two_on_target R4 pi1; inst pi1 26.5.7; inst pi2 26.5.7; back -e keycloak_version=26.5.7 -e confirm=x
ck "R4 no dump on either Pi: refused, nothing done" "$(refused 'no Keycloak dump to restore') $(nev)" "refused 0"
two_on_target R5 pi1; inst pi1 26.5.7; inst pi2 26.5.7; dump pi2 "$NEW"; : > "$KCS/psql-fail"; back -e keycloak_version=26.5.7 -e confirm="$NEW"
ck "R5 the restore's SQL failing: refused, Keycloak left stopped on both, no link moved, nothing started" \
   "$(refused 'the Keycloak restore failed') [$(on link)$(on started)] $(state)" "refused [] 26.8.2/ 26.8.2/"
two_on_target R6 pi1; inst pi1 26.5.7; inst pi2 26.5.7; dump pi2 "$NEW"; back -e keycloak_version=26.5.7 -e confirm="$NEW" --limit pi1
ck "R6 --limit pi1: refused, nothing done" "$(refused 'REFUSED: the run has') $(nev)" "refused 0"
two_on_target R8 pi1; inst pi1 26.5.7; inst pi2 26.5.7; dump pi2 "$NEW"; back -e keycloak_version=26.8.2 -e confirm="$NEW"
ck "R8 the unit not reverted (the pin still the new version): refused, nothing done" "$(refused 'revert the unit first') $(nev)" "refused 0"
two_on_target R9 pi1; inst pi1 26.5.7; inst pi2 26.5.7; dump pi2 "$NEW"; back -e keycloak_version=26.5.7 -e confirm="$OLD"
ck "R9 confirmed with another dump's name: refused, nothing done" "$(refused "confirm with -e confirm=$NEW") $(nev)" "refused 0"
two_on_target R10 pi1; inst pi1 26.5.7; inst pi2 26.5.7; dump pi2 "$NEW" cut; back -e keycloak_version=26.5.7 -e confirm="$NEW"
ck "R10 the newest dump cut short (no pg_dump trailer): refused before anything stops" "$(refused 'is cut short') $(nev)" "refused 0"

# ── both, in turn - the copy's rehearsal without a real database ────────────────────────────────────────────────
new Z pi2; pi pi1 26.5.7 26.5.7; pi pi2 26.5.7 26.5.7; up; up_rc=$(rc)
back -e keycloak_version=26.5.7 -e confirm="$(ls "$KCS/pi2/dumps")"
ck "Z upgraded, then the way back with the upgrade's own dump: both Pis on the old version again, its SQL where the dump was taken" \
   "$up_rc $(rc) $(state) $(awk '$3 == "psql" && $4 != "schema" {print $2}' "$KCS/events.log" | sort -u)" "0 0 26.5.7/26.5.7 26.5.7/26.5.7 pi2"

echo "keycloak-smoke: $([ "$fails" = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ "$fails" = 0 ]
