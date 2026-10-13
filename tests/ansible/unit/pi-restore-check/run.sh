#!/bin/bash
# setup-pi-restore-check.yml's files/pi-restore-check.sh, run for real against stubs: rclone serves a store made here
# (its times relative to now), podman plays production's Postgres image and etcd's, consul a throwaway agent, runuser
# the Pi's scratch Postgres. Green when every part restores; each part red on its own faults - the other parts still
# run, last-report says which, last-success stays where it was. The store is written under restore-checks/<this Pi>/
# only, never deleted from; the restored Postgres archives nothing and listens nowhere; etcd runs without a network.
# Then the playbook's wiring: the images and databases it names against production's (prod-inventory, step 47).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
SCRIPT=$PWD/deploy/ansible/playbooks/files/pi-restore-check.sh
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi
}
mkdir -p "$W/bin"
# --- rclone: the store is $W/store/<bucket>/<key>; every call logged, writes marked
cat > "$W/bin/rclone" <<'STUB_RCLONE'
#!/bin/bash
echo "rclone $*" >> "$W/calls"
S=$W/store
args=(); fmt=""; sep=";"; rec=""; dirs=""; files=""
while [ $# -gt 0 ]; do
  case "$1" in
    -R) rec=1 ;; --dirs-only) dirs=1 ;; --files-only) files=1 ;; -q) ;;
    --format) fmt=$2; shift ;; --separator) sep=$2; shift ;;
    *) args+=("$1") ;;
  esac
  shift
done
p() { local x=${1#store:}; echo "$S/$x"; }
case "${args[0]}" in
  lsf)
    d=$(p "${args[1]}"); [ -d "$d" ] || { echo "directory not found" >&2; exit 3; }
    if [ -n "$rec" ]; then
      (cd "$d" && find . -type f | sed 's#^\./##' | sort) | while read -r f; do
        if [ "$fmt" = pt ]; then echo "$f$sep$(date -r "$d/$f" '+%Y-%m-%d %H:%M:%S')"; else echo "$f"; fi
      done
    else
      for e in $(ls "$d"); do
        if [ -d "$d/$e" ]; then [ -n "$files" ] || echo "$e/"; else [ -n "$dirs" ] || echo "$e"; fi
      done
    fi ;;
  cat) cat "$(p "${args[1]}")" ;;
  copyto) cp "$(p "${args[1]}")" "${args[2]}" ;;
  copy) mkdir -p "${args[2]}"; cp -r "$(p "${args[1]}")/." "${args[2]}/" ;;
  mkdir) echo "WRITE mkdir ${args[1]}" >> "$W/writes"; mkdir -p "$(p "${args[1]}")" ;;
  rcat) echo "WRITE rcat ${args[1]}" >> "$W/writes"; f=$(p "${args[1]}"); mkdir -p "$(dirname "$f")"; cat > "$f" ;;
  *) echo "WRITE ${args[*]}" >> "$W/writes"; echo "rclone stub: ${args[0]} not served" >&2; exit 9 ;;
esac
STUB_RCLONE
# --- podman: production's Postgres image (barman-cloud-restore, postgres, psql, pg_dump) and etcd's
cat > "$W/bin/podman" <<'STUB_PODMAN'
#!/bin/bash
echo "podman $*" >> "$W/calls"
cmd=$1; shift
case "$cmd" in
  pull) exit 0 ;;
  ps) cat "$W/leftover-containers" 2> /dev/null; exit 0 ;;
  rm|logs) [ "$cmd" = logs ] && echo "LOG: recovery stopped"; exit 0 ;;
  inspect) echo "${PG_RUNNING:-true}"; exit 0 ;;
  run)
    vol=""; ep=""; detach=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -v) vol=${2%%:*}; shift ;; --entrypoint) ep=$2; shift ;; -d) detach=1 ;;
        --name|--network|--user|-e) shift ;; --rm) ;;
        --memory) echo "memory $2" >> "$W/memory"; shift ;;
        *) break ;;
      esac
      shift
    done
    image=$1; shift
    [ -n "$ep" ] && set -- "$ep" "$@"
    case "$1" in
      barman-cloud-restore) [ -z "${PG_RESTORE_FAIL:-}" ] || exit 1; mkdir -p "$vol/pgdata"; touch "$vol/pgdata/standby.signal" ;;
      postgres) echo "$*" > "$W/postgres-args"; ls "$vol/pgdata" > "$W/pgdata-at-start" ;;
      etcdutl)
        case "$2 $3" in
          "snapshot status") echo '{"hash":1,"revision":42,"totalKey":900,"totalSize":1000}' ;;
          "snapshot restore") [ -z "${ETCD_RESTORE_FAIL:-}" ] || { echo "snapshot file integrity check failed" >&2; exit 1; } ;;
        esac ;;
      etcd) echo "$image $*" > "$W/etcd-args" ;;
    esac
    [ -z "$detach" ] || echo container-id
    exit 0 ;;
  exec)
    shift  # the container
    case "$*" in
      *pg_is_in_recovery*) echo f ;;
      *pg_walfile_name*) echo "${SEG:-000000040000001D00000028}" ;;
      *string_agg*) echo "${DBS:-postgres monitor admin chat chess masi}" ;;
      *"from pg_class"*) if [ "${!#}" = "${EMPTY_DB:-}" ]; then echo 0; else echo "${TABLES:-7}"; fi ;;
      pg_dump*)
        # pg_dump 15+ fsyncs its file: /dev/null takes none (found on the Vagrant copy)
        case "$*" in *--no-sync*) ;; *) echo 'pg_dump: error: could not fsync file "/dev/null": Invalid argument' >&2; exit 1 ;; esac
        [ -z "${DUMP_FAIL:-}" ] || { echo "pg_dump: error: could not read block 3" >&2; exit 1; } ;;
      *"get /registry/namespaces/ --prefix"*) printf '/registry/namespaces/default\n/registry/namespaces/kube-system\n' ;;
      *"get /registry/namespaces/kube-system"*) [ -n "${NO_KUBE_SYSTEM:-}" ] || echo /registry/namespaces/kube-system ;;
    esac ;;
esac
STUB_PODMAN
cat > "$W/bin/consul" <<'STUB_CONSUL'
#!/bin/bash
echo "consul $*" >> "$W/calls"
case "$1 $2" in
  "agent -dev") exec sleep 120 ;;
  "snapshot restore") exit 0 ;;
  "kv get")
    case "$*" in
      *vault/core/*) for i in $(seq "${VAULT_KEYS:-3}"); do echo "vault/core/k$i:x"; done ;;
      *service/*) echo "service/pi/leader:pi1"; echo "service/pi/members/pi1:x" ;;
    esac ;;
  "lock -child-exit-code") shift 5; exec "$@" ;;
esac
STUB_CONSUL
cat > "$W/bin/curl" <<'STUB_CURL'
#!/bin/bash
echo '"127.0.0.1:18300"'
STUB_CURL
# runuser -u postgres -- <tool> ...: the Pi's scratch Postgres
cat > "$W/bin/runuser" <<'STUB_RUNUSER'
#!/bin/bash
shift 3
echo "runuser $*" >> "$W/calls"
tool=${1##*/}; shift
case "$tool" in
  initdb|pg_ctl|createdb) exit 0 ;;
  pg_restore) [ -z "${PGRESTORE_FAIL:-}" ] || { echo "pg_restore: error: could not execute query" >&2; exit 1; } ;;
  psql)
    case "$*" in
      *"-f "*) echo 'psql:/x/pg-globals.sql:5: ERROR:  role "postgres" already exists'
               [ -z "${GLOBALS_ERROR:-}" ] || echo 'psql:/x/pg-globals.sql:9: ERROR:  syntax error at or near "ROLE"' ;;
      *) echo "${T0_TABLES:-12}" ;;
    esac ;;
esac
STUB_RUNUSER
for t in chown timedatectl; do printf '#!/bin/bash\n[ "$1" != show ] || echo yes\n' > "$W/bin/$t"; done
chmod +x "$W/bin"/*

utc() { date -u -d "$1" "$2"; }
store() {  # a store as production's, made relative to now
  rm -rf "$W/store" "$W/calls" "$W/writes" "$W/postgres-args" "$W/etcd-args" "$W/pgdata-at-start" "$W/memory" \
    "$W/leftover-containers"
  local S=$W/store pg=$W/store/postgres-backups
  # an old server (a rename ago) and production's: three base backups - 3 h ago ending in segment 25, 2 h ago in 26
  # (END_MISSING: in 99, never archived - an idle database's unfinished segment), the newest still being written;
  # segments 25-27 archived
  mkdir -p "$pg/schnappy-postgres/base/20260410T140130"
  printf 'status=DONE\nend_wal=000000010000000000000001\n' > "$pg/schnappy-postgres/base/20260410T140130/backup.info"
  local b end
  for h in 3 2 1; do
    b=$(utc "-$h hours" +%Y%m%dT%H0130)
    mkdir -p "$pg/schnappy-production-postgres/base/$b"
    end=000000030000001D000000$(( 28 - h ))
    if { [ "$h" = 2 ] && [ -n "${END_MISSING:-}" ]; } || [ -n "${NONE_RESTORABLE:-}" ]; then end=000000030000001D00000099; fi
    printf 'version=%s\nstatus=%s\nend_wal=%s\n' "${PG_VERSION:-170004}" "$([ "$h" = 1 ] && echo STARTED || echo DONE)" "$end" \
      > "$pg/schnappy-production-postgres/base/$b/backup.info"
  done
  if [ -n "${BASE_OLD:-}" ]; then
    rm -rf "$pg/schnappy-production-postgres/base/"*
    b=$(utc "-30 hours" +%Y%m%dT%H0130); mkdir -p "$pg/schnappy-production-postgres/base/$b"
    printf 'version=170004\nstatus=DONE\nend_wal=000000030000001D00000025\n' > "$pg/schnappy-production-postgres/base/$b/backup.info"
  fi
  mkdir -p "$pg/schnappy-production-postgres/wals/000000030000001D"
  for s in 25 26 27; do touch "$pg/schnappy-production-postgres/wals/000000030000001D/000000030000001D000000$s.gz"; done
  touch "$pg/schnappy-production-postgres/wals/000000030000001D/000000030000001D00000027.00000060.backup.gz"
  mkdir -p "$S/etcd-backups"
  touch "$S/etcd-backups/etcd-$(utc "-${ETCD_AGE_H:-1} hours" +%Y%m%d-%H0003).db" "$S/etcd-backups/etcd-$(utc "-5 hours" +%Y%m%d-%H0003).db"
  if [ -z "${NO_TIER0:-}" ]; then
    local t
    t=$S/pi-backups/$(utc "-${TIER0_AGE_H:-3} hours" +%Y%m%dT%H4000Z)
    mkdir -p "$t"
    touch "$t/consul.snap" "$t/pg-forgejo.dump" "$t/pg-keycloak.dump" "$t/pg-globals.sql"
    [ -z "${KC_FAILED:-}" ] || touch "$t/KEYCLOAK-EXPORT-FAILED"
  fi
  mkdir -p "$S/restore-checks/pi1"
  echo 20200101T000000Z > "$S/restore-checks/pi1/last-success"
}
run() {  # run <env...>: the script as the unit runs it (its lock held: PI_RESTORE_LOCKED), the exit
  env "$@" > /dev/null  # (a bad env word fails here, not as a red check)
  env -i PATH="$W/bin:/usr/bin:/bin" W="$W" HOME="$W" STORE_ENDPOINT=http://192.168.11.5:9000 \
    AWS_ACCESS_KEY_ID=a AWS_SECRET_ACCESS_KEY=s PI_RESTORE_NAME=pi1 PI_RESTORE_PARITY=0 PI_RESTORE_ANY_DAY=1 \
    PI_RESTORE_LOCKED=1 PI_RESTORE_PG_DATABASES="monitor admin chat chess masi" \
    PI_RESTORE_PG_IMAGE_17=ghcr.io/cloudnative-pg/postgresql:17 PI_RESTORE_ETCD_IMAGE=registry.k8s.io/etcd:3.6.5-0 \
    PI_RESTORE_PG_BASE_MAX_AGE_H=26 PI_RESTORE_PG_BACKUPS_LOOKED_AT=30 PI_RESTORE_PG_WAIT_POLLS=3 PI_RESTORE_ETCD_MAX_AGE_H=3 \
    PI_RESTORE_TIER0_MAX_AGE_H=30 PI_RESTORE_WORK="$W/work" PI_RESTORE_MIN_FREE_GB=0 PI_RESTORE_CONTAINER_MEMORY=1536m "$@" bash "$SCRIPT" > "$W/out" 2>&1
  echo "rc=$?"
}
agents() {  # the throwaway Consul agents (the stub's sleep 120) still running
  local f n=0
  for f in /proc/[0-9]*/cmdline; do
    [ "$(tr '\0' ' ' < "$f" 2> /dev/null)" != "sleep 120 " ] || n=$((n + 1))
  done
  echo $n
}
report() { cat "$W/store/restore-checks/pi1/last-report" 2> /dev/null; }
success() { cat "$W/store/restore-checks/pi1/last-success"; }
# red(): the part named red, the others green, last-success not moved
red() {  # red <name> <PART> <env...>
  local name=$1 part=$2; shift 2
  # the store made with the case's variables too (it reads some of them)
  (export "$@"; store)
  local rc; rc=$(run "$@")
  check "$name" "$rc $(report | grep -c "^$part FAILED:") $(success)" "rc=1 1 20200101T000000Z"
}

store
check "every part restores: green" "$(run)" "rc=0"
check "  last-success this run's" "$(success | grep -cE '^[0-9]{8}T[0-9]{6}Z$') $(success | grep -c 2020)" "1 0"
check "  last-report: the three parts OK" "$(report | grep -cE '^(POSTGRES|ETCD|TIER0) OK')" 3
check "  production's server (not the old one), its newest RESTORABLE backup (not the one still written)" \
  "$(report | grep -oE 'schnappy-production-postgres/[0-9T]+' | sed 's#.*/##')" "$(utc '-2 hours' +%Y%m%dT%H0130)"
(export END_MISSING=1; store)
check "an idle database (the newest complete backup's end segment unarchived): the backup before it restored, green" \
  "$(run END_MISSING=1) $(report | grep -oE 'schnappy-production-postgres/[0-9T]+' | sed 's#.*/##')" \
  "rc=0 $(utc '-3 hours' +%Y%m%dT%H0130)"
store
run > /dev/null
check "  the newest WAL archived (not the .backup label) is what the replay had to reach" \
  "$(report | grep -oE 'newest archived at the start: [0-9A-F]+' | sed 's/.* //')" 000000030000001D00000027
check "  production's image for its major" "$(report | grep -oE '\(PostgreSQL 17, [^)]+\)')" \
  "(PostgreSQL 17, ghcr.io/cloudnative-pg/postgresql:17)"
check "  the restored Postgres: archives nothing, listens nowhere, no TLS, the store's WAL its restore_command" \
  "$(tr ' ' '\n' < "$W/postgres-args" | grep -cxE 'archive_mode=off|listen_addresses=|ssl=off|restore_command=barman-cloud-wal-restore')" 4
check "  recovery to the end, then promoted: recovery.signal in the data when Postgres starts, the backup's standby.signal gone" \
  "$(grep -xE 'recovery.signal|standby.signal' "$W/pgdata-at-start" | paste -sd,)" "recovery.signal"
check "  etcd without a network" "$(grep -c -- '--network none' "$W/calls" | awk '{print ($1 >= 3)}')" 1
check "  every database dumped whole" "$(grep -c 'podman exec .* pg_dump' "$W/calls")" 5
check "  the store written under restore-checks/pi1/ only (and the bucket made), never deleted from" \
  "$(sed 's/^WRITE //' "$W/writes" | sort -u | paste -sd,)" \
  "mkdir store:restore-checks,rcat store:restore-checks/pi1/last-report,rcat store:restore-checks/pi1/last-success"
check "  the work directory gone, the containers removed, the throwaway Consul stopped" \
  "$(ls "$W/work" | wc -l) $(grep -c '^podman rm -f' "$W/calls") $(agents)" "0 2 0"

check "  every container memory-bounded (podman runs them outside the unit's cgroup)" \
  "$(( $(grep -c '^podman run' "$W/calls") - $(wc -l < "$W/memory") )) $(sort -u "$W/memory")" "0 memory 1536m"

# a run killed (SIGKILL, a reboot) left its directory and containers: the next run clears them first
store
mkdir -p "$W/work/run.KILLED/pg/pgdata"
printf 'pi-restore-pg-4242\npi-restore-etcd-4242\nsomething-else\n' > "$W/leftover-containers"
check "a killed run's leftovers: its directory and its containers removed before the run, nothing else" \
  "$(run) $(ls "$W/work" | wc -l) $(grep -cE '^podman rm -f pi-restore-(pg|etcd)-4242' "$W/calls") $(grep -c 'rm -f something-else' "$W/calls")" \
  "rc=0 0 1 0"
store
check "too little room for a restore: none started, red" \
  "$(run PI_RESTORE_MIN_FREE_GB=999999) $(grep -c 'no restore' "$W/out") $(grep -c '^podman run' "$W/calls" || true)" "rc=1 1 0"

store
check "not this Pi's day: nothing done" \
  "$(run PI_RESTORE_ANY_DAY= PI_RESTORE_LOCKED= PI_RESTORE_PARITY=$(( ($(date -u +%s) / 86400 + 1) % 2 ))) $(ls "$W/store/restore-checks/pi1") $(cat "$W/calls" 2> /dev/null | wc -l)" \
  "rc=0 last-success 0"
check "  said so" "$(grep -c "not pi1's day" "$W/out")" 1
store
check "its day: the lock taken (consul lock), then the run" \
  "$(run PI_RESTORE_ANY_DAY= PI_RESTORE_LOCKED= PI_RESTORE_PARITY=$(( $(date -u +%s) / 86400 % 2 ))) $(grep -c '^consul lock -child-exit-code -timeout=30m pi-restore-check' "$W/calls")" \
  "rc=0 1"

red "postgres: a major with no image: red" POSTGRES PG_VERSION=190002
red "postgres: the newest complete base backup 30 h old: red" POSTGRES BASE_OLD=1
red "postgres: no backup restorable - every end WAL unarchived (archiving stopped): red" POSTGRES NONE_RESTORABLE=1
red "postgres: the restore fails: red" POSTGRES PG_RESTORE_FAIL=1
red "postgres: Postgres stops during the recovery: red" POSTGRES PG_RUNNING=false
red "postgres: replayed short of the newest WAL archived: red" POSTGRES SEG=000000040000001D00000026
red "postgres: a database missing: red" POSTGRES DBS="postgres monitor admin chat masi"
red "postgres: no table in any database: red" POSTGRES TABLES=0
store
check "postgres: one database empty (an app not deployed - masi in production), the rest with tables: green, the counts said" \
  "$(run EMPTY_DB=masi) $(report | grep -oE 'databases \(tables\) [^,]+' )" "rc=0 databases (tables) monitor:7 admin:7 chat:7 chess:7 masi:0"
red "postgres: a database not read back whole: red" POSTGRES DUMP_FAIL=1
store
run PG_RESTORE_FAIL=1 > /dev/null
check "  one part red, the others still run and are reported" "$(report | grep -cE '^(ETCD|TIER0) OK')" 2
check "  the run's exit says it" "$(grep -c 'PI RESTORE CHECK .* FAILED: POSTGRES' "$W/out")" 1
red "etcd: the newest snapshot 5 h old: red" ETCD ETCD_AGE_H=5
red "etcd: the snapshot does not restore (hash): red" ETCD ETCD_RESTORE_FAIL=1
red "etcd: no kube-system in it: red" ETCD NO_KUBE_SYSTEM=1
red "tier0: no Pi backup at all: red" TIER0 NO_TIER0=1
red "tier0: the newest 40 h old: red" TIER0 TIER0_AGE_H=40
red "tier0: its Keycloak export failed: red" TIER0 KC_FAILED=1
red "tier0: Consul's snapshot without Vault's keys: red" TIER0 VAULT_KEYS=0
red "tier0: pg-globals.sql fails beyond postgres' own role: red" TIER0 GLOBALS_ERROR=1
red "tier0: a dump does not restore: red" TIER0 PGRESTORE_FAIL=1
red "tier0: a database restored with no table: red" TIER0 T0_TABLES=0

# the playbook's wiring
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
check "the playbook names production's images (prod-inventory's Postgres 17 and etcd, step 47's Postgres 18)" "$("$PY" - <<'PY_WIRING'
import re, yaml
v = yaml.safe_load(open("deploy/ansible/playbooks/setup-pi-restore-check.yml"))[0]["vars"]
inv = open("tests/ansible/upgrade/prod-inventory.txt").read().splitlines()
img = lambda name: [l.split()[2] for l in inv if l.startswith("image " + name + " ")]
s47 = open("tests/ansible/upgrade/steps/47-postgres-18.txt").read()
to18 = re.search(r"=> image ghcr\.io/cloudnative-pg/postgresql (\S+)", s47).group(1)
print(v["pi_restore_check_pg_images"] == {"17": "ghcr.io/cloudnative-pg/postgresql:" + img("ghcr.io/cloudnative-pg/postgresql")[0],
                                          "18": "ghcr.io/cloudnative-pg/postgresql:" + to18},
      v["pi_restore_check_etcd_image"] == "registry.k8s.io/etcd:" + img("registry.k8s.io/etcd")[0])
PY_WIRING
)" "True True"
check "the two Pis on opposite days (pi1 even, pi2 odd), the store through the VIP" "$("$PY" - <<'PY_PARITY'
import yaml
p = yaml.safe_load(open("deploy/ansible/playbooks/setup-pi-restore-check.yml"))[0]
env = next(t for t in p["tasks"] if t["name"].startswith("Its settings"))["ansible.builtin.copy"]["content"]
for inv in ("production", "vagrant"):
    pis = list(yaml.safe_load(open(f"deploy/ansible/inventory/{inv}.yml"))["all"]["children"]["pis"]["hosts"])
    print(pis, [pis.index(h) % 2 for h in pis], end=" ")
print("PI_RESTORE_PARITY={{ groups['pis'].index(inventory_hostname) % 2 }}" in env,
      "STORE_ENDPOINT=http://{{ keepalived_vip }}:9000" in env)
PY_PARITY
)" "['pi1', 'pi2'] [0, 1] ['pi1', 'pi2'] [0, 1] True True"
echo "pi-restore-check: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
