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
  pull) [ -z "${PULL_FAIL:-}" ] || { echo "Error: initializing source: pinging container registry: i/o timeout" >&2; exit 125; }; exit 0 ;;
  image) if [ "$1" = exists ] && [ -n "${IMAGE_MISSING:-}" ]; then exit 1; fi; exit 0 ;;
  ps) cat "$W/leftover-containers" 2> /dev/null; exit 0 ;;
  rm|logs)
    [ "$cmd" = logs ] && echo "LOG: recovery stopped"
    # RM_REFUSES=once: the first removal of a killed run's container fails (its conmon gone), the next one works;
    # RM_REFUSES=always: every one fails
    if [ "$cmd" = rm ] && [ -n "${RM_REFUSES:-}" ] && [[ "$*" == *4242* ]]; then
      if [ "$RM_REFUSES" = always ] || [ ! -e "$W/rm-refused" ]; then
        touch "$W/rm-refused"; echo "Error: cannot remove container: conmon exited prematurely" >&2; exit 125
      fi
    fi
    exit 0 ;;
  inspect) case "$*" in *pi-restore-etcd-*) echo "${ETCD_RUNNING:-true}" ;; *) echo "${PG_RUNNING:-true}" ;; esac; exit 0 ;;
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
      *pg_is_in_recovery*) [ -n "${RECOVERING:-}" ] && echo t || echo f ;;
      *pg_walfile_name*) echo "${SEG:-000000040000001D00000028}" ;;
      *string_agg*) echo "${DBS:-postgres monitor admin chat chess masi}" ;;
      *"from pg_class"*) if [ "${!#}" = "${EMPTY_DB:-}" ]; then echo 0; else echo "${TABLES:-7}"; fi ;;
      pg_dump*)
        # pg_dump 15+ fsyncs its file: /dev/null takes none (found on the Vagrant copy)
        case "$*" in *--no-sync*) ;; *) echo 'pg_dump: error: could not fsync file "/dev/null": Invalid argument' >&2; exit 1 ;; esac
        [ -z "${DUMP_FAIL:-}" ] || { echo "pg_dump: error: could not read block 3" >&2; exit 1; } ;;
      *"get /registry/namespaces/ --prefix"*)
        [ -n "${ETCD_SILENT:-}" ] || printf '/registry/namespaces/default\n'
        [ -n "${ETCD_SILENT:-}${NO_KUBE_SYSTEM:-}" ] || printf '/registry/namespaces/kube-system\n' ;;
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
      *service/*) [ -n "${NO_PATRONI:-}" ] || echo "service/pi/leader:pi1"; echo "service/pi/members/pi1:x" ;;
    esac ;;
  "lock -child-exit-code")
    # LOCK_HELD: another run holds it - consul lock gives up after its timeout, the child never started
    [ -z "${LOCK_HELD:-}" ] || { echo "lock held" >&2; exit 1; }
    # a second lock inside the first (the child not marked as holding it) waits for ever in production
    [ ! -e "$W/locked" ] || { echo "NESTED LOCK" >> "$W/calls"; exit 99; }
    touch "$W/locked"; shift 4; exec "$@" ;;
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
# initdb -D <run>/tier0/pg: the umask inherited, the run's and tier0's directories' modes, as the scratch Postgres sees them
[ "$tool" != initdb ] || echo "umask $(umask) run $(stat -c %a "${2%/tier0/pg}") tier0 $(stat -c %a "${2%/pg}")" > "$W/modes"
case "$tool" in
  initdb|pg_ctl|createdb) exit 0 ;;
  pg_restore) [ -z "${PGRESTORE_FAIL:-}" ] || { echo "pg_restore: error: could not execute query" >&2; exit 1; } ;;
  psql)
    case "$*" in
      *"-f "*) [ -z "${PSQL_FAIL:-}" ] || { echo 'psql: error: connection to server on socket failed'; exit 2; }
               echo 'psql:/x/pg-globals.sql:5: ERROR:  role "postgres" already exists'
               [ -z "${GLOBALS_ERROR:-}" ] || echo 'psql:/x/pg-globals.sql:9: ERROR:  syntax error at or near "ROLE"' ;;
      *) echo "${T0_TABLES:-12}" ;;
    esac ;;
esac
STUB_RUNUSER
printf '#!/bin/bash\necho "chown $*" >> "$W/calls"\n' > "$W/bin/chown"
printf '#!/bin/bash\n[ "$1" != show ] || echo "${NTP:-yes}"\n' > "$W/bin/timedatectl"
printf '#!/bin/bash\n[ -z "${CHRONY_NORMAL:-}" ] || echo "Leap status     : Normal"\n' > "$W/bin/chronyc"
printf '#!/bin/bash\necho "sleep $*" >> "$W/sleeps"\n' > "$W/bin/sleep"
chmod +x "$W/bin"/*

utc() { date -u -d "$1" "$2"; }
store() {  # a store as production's, made relative to now
  rm -rf "$W/locked" "$W/sleeps" "$W/rm-refused" "$W/store" "$W/calls" "$W/writes" "$W/postgres-args" "$W/modes" "$W/etcd-args" "$W/pgdata-at-start" "$W/memory" \
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
    # NO_INFO: the 2 h one without its backup.info (barman writes it last)
    if [ "$h" = 2 ] && [ -n "${NO_INFO:-}" ]; then rm "$pg/schnappy-production-postgres/base/$b/backup.info"; fi
  done
  # BASE_OLD=<h>: the only complete base backup <h> hours old
  if [ -n "${BASE_OLD:-}" ]; then
    rm -rf "$pg/schnappy-production-postgres/base/"*
    b=$(utc "-$BASE_OLD hours" +%Y%m%dT%H0130); mkdir -p "$pg/schnappy-production-postgres/base/$b"
    printf 'version=170004\nstatus=DONE\nend_wal=000000030000001D00000025\n' > "$pg/schnappy-production-postgres/base/$b/backup.info"
  fi
  mkdir -p "$pg/schnappy-production-postgres/wals/000000030000001D"
  for s in 25 26 27; do touch "$pg/schnappy-production-postgres/wals/000000030000001D/000000030000001D000000$s.gz"; done
  # the log before (1C) to its last segment: by the segment alone (FF) it would read furthest
  mkdir -p "$pg/schnappy-production-postgres/wals/000000030000001C"
  touch "$pg/schnappy-production-postgres/wals/000000030000001C/000000030000001C000000FF.gz"
  touch "$pg/schnappy-production-postgres/wals/000000030000001D/000000030000001D00000027.00000060.backup.gz"
  # STRAY: a segment of a higher timeline behind the real end (production's archive held one, 2026-10-15)
  if [ -n "${STRAY:-}" ]; then
    mkdir -p "$pg/schnappy-production-postgres/wals/000000090000001D"
    touch "$pg/schnappy-production-postgres/wals/000000090000001D/000000090000001D00000010.gz"
  fi
  # PROMOTED: a failover after the backup - timeline 5's history and its segments ahead (1D/2F, 1D/30); LATE: the old
  # primary archived a segment of its timeline past the fork (1D/40) - no recovery follows it
  if [ -n "${PROMOTED:-}" ]; then
    touch "$pg/schnappy-production-postgres/wals/00000005.history.gz"
    mkdir -p "$pg/schnappy-production-postgres/wals/000000050000001D"
    touch "$pg/schnappy-production-postgres/wals/000000050000001D/000000050000001D0000002F.gz" \
      "$pg/schnappy-production-postgres/wals/000000050000001D/000000050000001D00000030.gz"
  fi
  [ -z "${LATE:-}" ] || touch "$pg/schnappy-production-postgres/wals/000000030000001D/000000030000001D00000040.gz"
  # a promotion just archived: the new timeline's history, its first segment not yet - a name that sorts after every WAL
  touch "$pg/schnappy-production-postgres/wals/00000004.history.gz"
  mkdir -p "$S/etcd-backups"
  touch "$S/etcd-backups/etcd-$(utc "-${ETCD_AGE_H:-1} hours" +%Y%m%d-%H0003).db" "$S/etcd-backups/etcd-$(utc "-5 hours" +%Y%m%d-%H0003).db"
  if [ -z "${NO_TIER0:-}" ]; then
    local t
    t=$S/pi-backups/$(utc "-${TIER0_AGE_H:-3} hours" +%Y%m%dT%H4000Z)
    mkdir -p "$t"
    touch "$t/consul.snap" "$t/pg-globals.sql"
    [ -n "${NO_DUMPS:-}" ] || touch "$t/pg-forgejo.dump" "$t/pg-keycloak.dump"
    [ -z "${KC_FAILED:-}" ] || touch "$t/KEYCLOAK-EXPORT-FAILED"
  fi
  # the Pi's Postgres majors: text order and version order disagree
  mkdir -p "$S/restore-checks/pi1" "$W/pgroot/9.6/bin" "$W/pgroot/15/bin" "$W/pgroot/17/bin"
  echo 20200101T000000Z > "$S/restore-checks/pi1/last-success"
}
# production's base backup age limit, as the playbook sets it (the cases below are judged against it)
# the kernel's cgroup controllers as a Pi with its memory controller on lists them (MEMLESS: as pi2's did, 2026-10-16)
echo "cpuset cpu io memory pids" > "$W/cgroup-controllers"
BASE_MAX=$(sed -n 's/^    pi_restore_check_pg_base_max_age_h: *//p' deploy/ansible/playbooks/setup-pi-restore-check.yml)
# no looser than CNPG's daily 01:30 backup allows at this 05:30 check: the day before's is ~28 h old - past 30 h, a
# backup not made for a day would pass
check "the base backup's limit between the day before's (28 h) and a day missed (over 30 h)" \
  "$([ "$BASE_MAX" -ge 28 ] && [ "$BASE_MAX" -le 30 ] && echo within)" within
run() {  # run <env...>: the script as the unit runs it (its lock held: PI_RESTORE_LOCKED), the exit
  env "$@" > /dev/null  # (a bad env word fails here, not as a red check)
  env -i PATH="$W/bin:/usr/bin:/bin" W="$W" HOME="$W" TZ=Europe/Tallinn PI_RESTORE_PG_ROOT="$W/pgroot" STORE_ENDPOINT=http://192.168.11.5:9000 \
    AWS_ACCESS_KEY_ID=a AWS_SECRET_ACCESS_KEY=s PI_RESTORE_NAME=pi1 PI_RESTORE_PARITY=0 PI_RESTORE_ANY_DAY=1 \
    PI_RESTORE_LOCKED=1 PI_RESTORE_PG_DATABASES="monitor admin chat chess masi" \
    PI_RESTORE_TIMESYNC_MARKER="$W/no-timesync-marker" PI_RESTORE_CGROUP_CONTROLLERS="$W/cgroup-controllers" \
    PI_RESTORE_PG_IMAGE_17=ghcr.io/cloudnative-pg/postgresql:17 PI_RESTORE_ETCD_IMAGE=registry.k8s.io/etcd:3.6.5-0 \
    PI_RESTORE_PG_BASE_MAX_AGE_H="$BASE_MAX" PI_RESTORE_PG_BACKUPS_LOOKED_AT=30 PI_RESTORE_PG_WAIT_POLLS=3 PI_RESTORE_ETCD_MAX_AGE_H=3 \
    PI_RESTORE_TIER0_MAX_AGE_H=30 PI_RESTORE_WORK="$W/work" PI_RESTORE_MIN_FREE_GB=0 PI_RESTORE_CONTAINER_MEMORY=1536m PI_RESTORE_ETCD_WAIT_POLLS=2 "$@" bash "$SCRIPT" > "$W/out" 2>&1
  echo "rc=$?"
}
agents() {  # this test's throwaway Consul agents (the stub's sleep 120, W in its environment) still running - another
  # run's (a test beside this one) not counted
  local f n=0
  for f in /proc/[0-9]*/cmdline; do
    [ "$(tr '\0' ' ' < "$f" 2> /dev/null)" = "sleep 120 " ] || continue
    tr '\0' '\n' < "${f%cmdline}environ" 2> /dev/null | grep -qxF "W=$W" && n=$((n + 1))
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
(export NO_INFO=1; store)
check "a base backup without its backup.info (still uploading): the one before it restored, green" \
  "$(run NO_INFO=1) $(report | grep -oE 'schnappy-production-postgres/[0-9T]+' | sed 's#.*/##')" \
  "rc=0 $(utc '-3 hours' +%Y%m%dT%H0130)"
store
check "the registry down, the images here already: green" "$(run PULL_FAIL=1)" "rc=0"
store
check "the registry down and an image not here: red" \
  "$(run PULL_FAIL=1 IMAGE_MISSING=1) $(report | grep -cE '^(POSTGRES|ETCD) FAILED:')" "rc=1 2"
store
run > /dev/null
check "  the newest WAL archived (not the .backup label) is what the replay had to reach" \
  "$(report | grep -oE 'newest archived at the start: [0-9A-F]+' | sed 's/.* //')" 000000030000001D00000027
check "  production's image for its major" "$(report | grep -oE '\(PostgreSQL 17, [^)]+\)')" \
  "(PostgreSQL 17, ghcr.io/cloudnative-pg/postgresql:17)"
check "  the restored Postgres: archives nothing, listens nowhere, no TLS, the store's WAL its restore_command" \
  "$(tr ' ' '\n' < "$W/postgres-args" | grep -cxE 'archive_mode=off|listen_addresses=|ssl=off|restore_command=barman-cloud-wal-restore')" 4
# root's alone: a directory any local user passes through, and a socket any may open, let any service account log in to
# a restored Postgres as its superuser (trust) or read production's dumps
check "  its files root's alone: the umask 077, the run's directory passable only, tier0's too, the dumps the scratch Postgres's" \
  "$(cat "$W/modes") $(grep -cE '^chown -R postgres: .*/tier0/b$' "$W/calls")" "umask 0077 run 711 tier0 711 1"
check "  both restored Postgres' sockets their user's alone" \
  "$(tr ' ' '\n' < "$W/postgres-args" | grep -cx 'unix_socket_permissions=0700') $(grep -cE '^runuser .*/pg_ctl .*unix_socket_permissions=0700 .* start$' "$W/calls")" "1 1"
check "  recovery to the end, then promoted: recovery.signal in the data when Postgres starts, the backup's standby.signal gone" \
  "$(grep -xE 'recovery.signal|standby.signal' "$W/pgdata-at-start" | paste -sd,)" "recovery.signal"
check "  etcd without a network" "$(grep -c -- '--network none' "$W/calls" | awk '{print ($1 >= 3)}')" 1
check "  every database dumped whole" "$(grep -c 'podman exec .* pg_dump' "$W/calls")" 5
check "  the store written under restore-checks/pi1/ only (and the bucket made), never deleted from" \
  "$(sed 's/^WRITE //' "$W/writes" | sort -u | paste -sd,)" \
  "mkdir store:restore-checks,rcat store:restore-checks/pi1/last-report,rcat store:restore-checks/pi1/last-success"
check "  the work directory gone, the containers removed, the throwaway Consul stopped" \
  "$(ls "$W/work" | wc -l) $(grep -oE '^podman rm -f -t 0 pi-restore-(pg|etcd)-[0-9]+' "$W/calls" | sort -u | wc -l) $(agents)" "0 2 0"
check "  each part's container gone when the part ends - Postgres's before etcd's first container" \
  "$(awk '/^podman rm -f -t 0 pi-restore-pg-/ && !r { r = NR } /^podman run .*etcd/ && !e { e = NR } END { print (r && e && r < e) }' "$W/calls")" 1

check "  the scratch Postgres stopped" "$(grep -cE '^runuser .*/pg_ctl -D .*/tier0/pg -m immediate stop' "$W/calls")" 1
check "  the Pi's newest Postgres (17 - text order would take 9.6)" \
  "$(grep -oE '^runuser [^ ]*/pg_restore' "$W/calls" | sort -u | sed 's#.*/pgroot/##')" "17/bin/pg_restore"
check "  every container memory-bounded (podman runs them outside the unit's cgroup)" \
  "$(( $(grep -c '^podman run' "$W/calls") - $(wc -l < "$W/memory") )) $(sort -u "$W/memory")" "0 memory 1536m"

# a run killed (SIGKILL, a reboot) left its directory and containers: the next run clears them first
store
mkdir -p "$W/work/run.KILLED/pg/pgdata"
printf 'pi-restore-pg-4242\npi-restore-etcd-4242\nsomething-else\n' > "$W/leftover-containers"
check "a killed run's leftovers: its directory and its containers removed before the run, nothing else" \
  "$(run) $(ls "$W/work" | wc -l) $(grep -cE '^podman rm -f -t 0 pi-restore-(pg|etcd)-4242' "$W/calls") $(grep -c 'rm -f something-else' "$W/calls")" \
  "rc=0 0 2 0"
store
printf 'pi-restore-pg-4242\n' > "$W/leftover-containers"
rm -f "$W/rm-refused"
check "a killed run's container refusing its first removal (its conmon gone): removed by the second, nothing said" \
  "$(run RM_REFUSES=once) $(grep -c '^podman rm -f -t 0 pi-restore-pg-4242' "$W/calls") $(grep -c 'not removed now' "$W/out")" \
  "rc=0 2 0"
store
printf 'pi-restore-pg-4242\n' > "$W/leftover-containers"
rm -f "$W/rm-refused"
check "a killed run's container refusing every removal: said, and the run goes on green" \
  "$(run RM_REFUSES=always) $(grep -c "a killed run's container pi-restore-pg-4242 not removed now" "$W/out")" "rc=0 1"
store
touch "$W/not-a-directory"
check "an early failure (its work directory cannot be made): red, and its line named - no run ends without a word" \
  "$(run PI_RESTORE_WORK="$W/not-a-directory/work") $(grep -c 'PI RESTORE CHECK: failed at line [0-9]' "$W/out")" "rc=1 1"
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
check "  the run under the lock: every part, last-success this run's, the lock not taken twice" \
  "$(report | grep -cE '^(POSTGRES|ETCD|TIER0) OK') $(success | grep -c 2020) $(grep -c 'NESTED LOCK' "$W/calls")" "3 0 0"
store
printf 'pi-restore-pg-4242\n' > "$W/leftover-containers"
check "another run holds the lock: its containers untouched, nothing restored" \
  "$(run PI_RESTORE_ANY_DAY=1 PI_RESTORE_LOCKED= LOCK_HELD=1) $(grep -c 'rm .*pi-restore-pg-4242' "$W/calls") $(grep -c '^rclone' "$W/calls")" "rc=1 0 0"
store
check "the clock never synchronized: no restore check, nothing read" \
  "$(run PI_RESTORE_LOCKED= NTP=no) $(grep -c 'not synchronized' "$W/out") $(cat "$W/calls" 2> /dev/null | grep -c '^rclone') $(wc -l < "$W/sleeps")" \
  "rc=1 1 0 59"
store
touch "$W/timesync-marker"
check "  timesyncd synchronized (its marker; timedatectl says no): the run goes on" \
  "$(run PI_RESTORE_LOCKED= NTP=no PI_RESTORE_TIMESYNC_MARKER="$W/timesync-marker") $(report | grep -cE ' OK')" "rc=0 3"
rm "$W/timesync-marker"
store
check "  chrony synchronized (timedatectl says no): the run goes on" "$(run PI_RESTORE_LOCKED= NTP=no CHRONY_NORMAL=1) $(report | grep -cE ' OK')" "rc=0 3"

# no memory cgroup controller (pi2's command line, 2026-10-16): Postgres and etcd red, saying why - no container started -
# tier0 (no container) restored
echo "cpuset cpu io pids" > "$W/cgroup-controllers"
store
check "no memory cgroup controller: every part red, saying so, no container run, no scratch Postgres" \
  "$(run) $(report | grep -c 'no memory cgroup controller') $(grep -c '^podman run' "$W/calls") $(grep -c 'initdb' "$W/calls")" \
  "rc=1 3 0 0"
echo "cpuset cpu io memory pids" > "$W/cgroup-controllers"
red "postgres: a major with no image: red" POSTGRES PG_VERSION=190002
red "postgres: the newest complete base backup just past the playbook's limit: red" POSTGRES BASE_OLD=$((BASE_MAX + 1))
# CNPG's backup daily at 01:30, this check at 05:30: an idle database's newest restorable one is the day before's
(export BASE_OLD=28; store)
check "  the day before's (28 h old): green" "$(run BASE_OLD=28)" "rc=0"
red "postgres: no backup restorable - every end WAL unarchived (archiving stopped): red" POSTGRES NONE_RESTORABLE=1
red "postgres: the restore fails: red" POSTGRES PG_RESTORE_FAIL=1
red "postgres: Postgres stops during the recovery: red" POSTGRES PG_RUNNING=false
red "postgres: replayed short of the newest WAL archived: red" POSTGRES SEG=000000040000001D00000026
red "  short by its log, past by its segment (1C/30 against 1D/27): red" POSTGRES SEG=000000040000001C00000030
red "  a stray higher timeline's segment behind the end in the archive: the bar not lowered - short still red" POSTGRES \
  SEG=000000040000001D00000026 STRAY=1
(export STRAY=1; store)
run STRAY=1 > /dev/null
check "  the furthest archived by position, not a higher timeline's by name" \
  "$(report | grep -oE 'newest archived at the start: [0-9A-F]+' | sed 's/.* //')" 000000030000001D00000027
# a failover after the backup: the recovery follows the promoted timeline (its history archived) - its furthest segment
# the bar, not the old primary's segment archived past the fork, which no recovery reaches
(export PROMOTED=1 LATE=1; store)
run PROMOTED=1 LATE=1 SEG=000000060000001D00000030 > /dev/null
check "  promoted after the backup: the bar the promoted timeline's furthest (1D/30), not the old primary's late 1D/40" \
  "$(report | grep -oE 'newest archived at the start: [0-9A-F]+' | sed 's/.* //') $(report | grep -c '^POSTGRES OK')" \
  "000000050000001D00000030 1"
red "  promoted, the replay short of the promoted timeline's end: red" POSTGRES PROMOTED=1 SEG=000000060000001D0000002F
red "postgres: still recovering after its polls: red" POSTGRES RECOVERING=1
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
red "etcd: stopped on the restored data: red" ETCD ETCD_RUNNING=false
red "etcd: serves no namespace within its wait: red" ETCD ETCD_SILENT=1
check "  said so, with etcd's own log" "$(grep -c 'served no namespace within 4 s' "$W/out") $(grep -c 'LOG: ' "$W/out")" "1 1"
red "tier0: no Pi backup at all: red" TIER0 NO_TIER0=1
red "tier0: the newest 40 h old: red" TIER0 TIER0_AGE_H=40
red "tier0: its Keycloak export failed: red" TIER0 KC_FAILED=1
red "tier0: Consul's snapshot without Vault's keys: red" TIER0 VAULT_KEYS=0
red "tier0: pg-globals.sql fails beyond postgres' own role: red" TIER0 GLOBALS_ERROR=1
red "tier0: a dump does not restore: red" TIER0 PGRESTORE_FAIL=1
red "tier0: a database restored with no table: red" TIER0 T0_TABLES=0
red "tier0: Consul's snapshot without Patroni's leader keys: red" TIER0 NO_PATRONI=1
red "tier0: no database dump in the backup: red" TIER0 NO_DUMPS=1
red "tier0: psql could not run pg-globals.sql: red" TIER0 PSQL_FAIL=1

# the playbook's wiring
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
check "the playbook names production's images (Postgres 17 as it ran; after every step: its Postgres 18 and etcd, digested)" "$(PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY_WIRING'
import importlib.machinery, importlib.util, os, re, yaml
v = yaml.safe_load(open("deploy/ansible/playbooks/setup-pi-restore-check.yml"))[0]["vars"]
L = importlib.machinery.SourceFileLoader("e", "scripts/upgrade-expected-inventory.py")
e = importlib.util.module_from_spec(importlib.util.spec_from_loader("e", L))
L.exec_module(e)
before = open("tests/ansible/upgrade/prod-inventory.txt").read().splitlines()
after = e.expected(sorted(f[:-4] for f in os.listdir(e.STEPS) if f.endswith(".txt")))
img = lambda inv, name: [l.split()[2] for l in inv if l.startswith("image " + name + " ")]
pg, etcd = "ghcr.io/cloudnative-pg/postgresql", "registry.k8s.io/etcd"
digested = lambda ref, name, tags: [re.fullmatch(re.escape(name) + r":(\S+)@sha256:[0-9a-f]{64}", ref)[1]] == tags
print(v["pi_restore_check_pg_images"]["17"] == pg + ":" + img(before, pg)[0],
      digested(v["pi_restore_check_pg_images"]["18"], pg, img(after, pg)),
      digested(v["pi_restore_check_etcd_image"], etcd, img(after, etcd)), sorted(v["pi_restore_check_pg_images"]))
PY_WIRING
)" "True True True ['17', '18']"
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
check "the playbook's settings file names every setting the script requires" "$("$PY" - "$SCRIPT" <<'PY_KEYS'
import re, sys, yaml
p = yaml.safe_load(open("deploy/ansible/playbooks/setup-pi-restore-check.yml"))[0]
env = next(t for t in p["tasks"] if t["name"].startswith("Its settings"))["ansible.builtin.copy"]["content"]
keys = set(re.findall(r"^([A-Z][A-Z0-9_]*)=", env, re.M))
need = set(re.findall(r'"\$\{([A-Z][A-Z0-9_]*):\?\}"', open(sys.argv[1]).read()))
print(sorted(need - keys), len(need) > 5)
PY_KEYS
)" "[] True"
# the start limit holds the first run and its two retries even when each hangs to its timeout - a 6 h window never held
# three 3 h runs 20 min apart, and the unit restarted for ever; its files root's alone (UMask, as the script's umask)
check "the unit: three starts, each to its timeout, within the start limit's window, the window ended before the timer's next day; its umask 0077" "$("$PY" - <<'PY_UNIT'
import re, yaml
p = yaml.safe_load(open("deploy/ansible/playbooks/setup-pi-restore-check.yml"))[0]
items = [i for t in p["tasks"] for i in (t.get("loop") or []) if isinstance(i, dict)]
unit = next(i["content"] for i in items if i.get("name") == "pi-restore-check.service")
timer = next(i["content"] for i in items if i.get("name") == "pi-restore-check.timer")
kv = dict(re.findall(r"^(\w+)=(.*)$", unit, re.M))
tv = dict(re.findall(r"^(\w+)=(.*)$", timer, re.M))
secs = lambda v: sum(int(n) * {"h": 3600, "min": 60, "s": 1}[u] for n, u in re.findall(r"(\d+)(h|min|s)", v))
burst, window = int(kv["StartLimitBurst"]), secs(kv["StartLimitIntervalSec"])
daily = bool(re.fullmatch(r"\{\{ pi_restore_check_on_calendar \}\}", tv["OnCalendar"])) \
    and p["vars"]["pi_restore_check_on_calendar"].startswith("*-*-* ")
print(burst, burst * (secs(kv["TimeoutStartSec"]) + secs(kv["RestartSec"])) <= window,
      daily and window + int(tv["RandomizedDelaySec"]) < 24 * 3600, kv["UMask"])
PY_UNIT
)" "3 True True 0077"
# the playbook turns the memory cgroup on at boot: an explicit cgroup_disable=memory taken off, each flag appended where
# missing - pi2's line (2026-10-16) gets both, pi1's (both twice already) none; leading blanks, a CRLF, look-alikes; the
# line kept one line, the same on a second run; each edit validated (one line, root=) before it is written; the
# controller wanted live, and the message saying the cause - no file, a preview, booted with the flags, or a reboot
check "the command line's memory cgroup: each line shape, a second run, the validator, the assert and its four causes" "$(PYTHONDONTWRITEBYTECODE=1 "$PY" - "$W" <<'PY_CMDLINE'
import os, re, subprocess, sys, yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render, condition
W = sys.argv[1]
p = yaml.safe_load(open("deploy/ansible/playbooks/setup-pi-restore-check.yml"))[0]
reps = [t for t in p["tasks"] if "ansible.builtin.replace" in t]
clear = next(t for t in reps if "cgroup_disable" in t["ansible.builtin.replace"]["regexp"])
add = next(t for t in reps if t.get("loop"))
a = next(t for t in p["tasks"] if "_cgroups" in str(t.get("ansible.builtin.assert", "")))
def sub(task, text, **v):  # as the replace module applies it: re.MULTILINE, its replacement's groups
    r = task["ansible.builtin.replace"]
    return re.compile(render(r["regexp"], **v), re.MULTILINE).sub(render(r["replace"], **v), text)
def apply(text):
    text = sub(clear, text)
    assert add["loop"] == "{{ pi_cmdline_memory_flags }}"
    for item in p["vars"]["pi_cmdline_memory_flags"]:
        text = sub(add, text, item=item)
    return text
flags = lambda t: [w for w in t.split() if w in ("cgroup_enable=memory", "cgroup_memory=1", "cgroup_disable=memory")]
lines = {
    "pi2": "console=tty1 console=serial0,115200 root=PARTUUID=771933d1-02 rootfstype=ext4 fsck.repair=yes rootwait cfg80211.ieee80211_regdom=EE ds=nocloud;i=rpi-imager-1775291628561\n",
    "pi1": "console=tty1 root=PARTUUID=6a821266-02 rootfstype=ext4 fsck.repair=yes rootwait cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory\n",
    "half": "console=tty1 root=X rootwait cgroup_memory=1\n",
    "near": "console=tty1 root=X rootwait cgroup_memory=10 xcgroup_enable=memory\n",
    "blanks": "  console=tty1 root=X rootwait\n",
    "crlf": "console=tty1 root=X rootwait\r\n",
    "disabled": "console=tty1 root=X cgroup_disable=memory rootwait\n",
}
out = {k: apply(v) for k, v in lines.items()}
ok = all(o.count("\n") == 1 and "\r" not in o and apply(o) == o and "root=" in o for o in out.values())
want = ["cgroup_enable=memory", "cgroup_memory=1"]
print(ok, out["pi1"] == lines["pi1"], [sorted(flags(out[k])) == sorted(want) for k in ("pi2", "half", "near", "blanks", "crlf", "disabled")])
# the validator as Ansible runs it (%s the file it would write)
assert add["ansible.builtin.replace"]["validate"] == clear["ansible.builtin.replace"]["validate"] == "{{ pi_cmdline_valid }}"
val = p["vars"]["pi_cmdline_valid"]
def valid(text):
    f = os.path.join(W, "cmdline-candidate.txt"); open(f, "w").write(text)
    return subprocess.run(val.replace("%s", f), shell=True).returncode == 0
print([valid(out["pi2"]), valid(out["pi2"] + "second line\n"), valid("console=tty1 rootwait\n"),
       valid("console=tty1 nfsroot=192.168.11.5:/srv rootwait\n"), valid(out["pi2"].rstrip("\n"))])
live = lambda c: condition(a["ansible.builtin.assert"]["that"], _cgroups={"results": [{"stdout": c}, {"stdout": ""}]})
def why(exists=True, changed=False, check=False, booted=""):
    v = dict(inventory_hostname="pi2", pi_cmdline_path="/boot/firmware/cmdline.txt", ansible_check_mode=check,
             _cmdline={"stat": {"exists": exists}},
             _cmdline_set={"changed": changed} if exists else {"skipped": True, "changed": False},
             _cmdline_cleared={"changed": False} if exists else {"skipped": True, "changed": False},
             _cgroups={"results": [{"stdout": "cpuset cpu io pids"}, {"stdout": booted}]})
    return render(a["ansible.builtin.assert"]["fail_msg"], **v)
msgs = [why(exists=False), why(changed=True, check=True), why(booted="console=tty1 cgroup_enable=memory cgroup_memory=1"),
        why(changed=True), why()]
print([live("cpuset cpu io memory pids"), live("cpuset cpu io pids"), live("")],
      ["not here" in msgs[0] or "cannot be turned on here" in msgs[0], "not --check" in msgs[1], "will not help" in msgs[2],
       "turns it on now: reboot it" in msgs[3], "turns it on: reboot it" in msgs[4],
       all("reboot it" not in m for m in msgs[:3])])
PY_CMDLINE
)" "True True [True, True, True, True, True, True]
[True, False, False, False, True]
[True, False, False] [True, True, True, True, True, True]"
# the same tasks through Ansible itself (the replace module, its validate, the when on a missing file, the reads in a
# preview, the message rendered), on fixture files: pi2's line turned on and said "reboot it"; the second run changes
# nothing and still says reboot; a preview writes nothing and says so; no command line file (the Vagrant VMs') - the
# edit skipped, the cause said; the controller live - green; booted with the flags and still none - "will not help"
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
CL=$W/cl; mkdir -p "$CL"
PYTHONDONTWRITEBYTECODE=1 "$PY" - "$CL" <<'PY_PLAY'
import sys, yaml
cl = sys.argv[1]
p = yaml.safe_load(open("deploy/ansible/playbooks/setup-pi-restore-check.yml"))[0]
names = [t["name"] for t in p["tasks"]]
first = names.index("The Pi's kernel command line")
tasks = p["tasks"][first:]
v = dict(p["vars"], pi_cmdline_path=f"{cl}/cmdline.txt", pi_cgroup_controllers=f"{cl}/controllers",
         pi_booted_cmdline=f"{cl}/proc-cmdline")
yaml.safe_dump([{"hosts": "localhost", "connection": "local", "gather_facts": False, "tasks": tasks, "vars": v}],
               open(f"{cl}/play.yml", "w"), sort_keys=False)
PY_PLAY
# sync as the Pi's would be called, each call logged (the edits' flush to the card)
mkdir -p "$CL/bin"; printf '#!/bin/sh\necho "$*" >> %s/syncs\n' "$CL" > "$CL/bin/sync"; chmod +x "$CL/bin/sync"
cl_run() {  # cl_run <ansible args...>: rc and the message's cause
  local out rc
  out=$(ANSIBLE_NOCOLOR=1 PATH="$CL/bin:$PATH" "$AP" -i localhost, "$CL/play.yml" "$@" 2>&1); rc=$?
  [ "$rc" = 0 ] && echo "rc=0" && return
  echo "rc=$rc $(grep -oE 'turns it on now: reboot it|turns it on: reboot it|not --check|cannot be turned on here|will not help|reads another command line' <<< "$out" | head -1)"
}
syncs() { touch "$CL/syncs"; grep -cxF -- "-f $CL/cmdline.txt" "$CL/syncs"; }
PI2_LINE='console=tty1 console=serial0,115200 root=PARTUUID=771933d1-02 rootfstype=ext4 fsck.repair=yes rootwait ds=nocloud'
printf '%s\n' "$PI2_LINE" > "$CL/cmdline.txt"; echo "cpuset cpu io pids" > "$CL/controllers"; echo "$PI2_LINE" > "$CL/proc-cmdline"
check "Ansible itself: pi2's line turned on, said to reboot; written as wanted, the original kept once, synced" \
  "$(cl_run) $(grep -c ' ds=nocloud cgroup_enable=memory cgroup_memory=1$' "$CL/cmdline.txt") $(wc -l < "$CL/cmdline.txt") $(cmp -s <(printf '%s\n' "$PI2_LINE") "$CL/cmdline.txt.before-memory-cgroup" && echo kept) $(syncs)" \
  "rc=2 turns it on now: reboot it 1 1 kept 1"
check "  run again: nothing changed, the kept original untouched, nothing synced, still said to reboot" \
  "$(cl_run) $(cmp -s <(printf '%s\n' "$PI2_LINE") "$CL/cmdline.txt.before-memory-cgroup" && echo kept) $(ls "$CL" | grep -c '^cmdline.txt') $(syncs)" \
  "rc=2 turns it on: reboot it kept 2 1"
# pi2's file as it is (169 bytes, no newline at its end, 2026-10-16): still one line, both flags at its end
rm "$CL/cmdline.txt.before-memory-cgroup" "$CL/syncs"; printf '%s' "$PI2_LINE" > "$CL/cmdline.txt"
check "  pi2's line with no newline at its end: one line, both flags at its end, the original kept byte for byte" \
  "$(cl_run) $(grep -c '' "$CL/cmdline.txt") $(grep -c ' ds=nocloud cgroup_enable=memory cgroup_memory=1$' "$CL/cmdline.txt") $(cmp -s <(printf '%s' "$PI2_LINE") "$CL/cmdline.txt.before-memory-cgroup" && echo kept) $(syncs)" \
  "rc=2 turns it on now: reboot it 1 1 kept 1"
# a run cut short (one flag on, the kept copy the original): the kept copy stays the original, the line finished
printf '%s\n' "$PI2_LINE" > "$CL/cmdline.txt.before-memory-cgroup"; printf '%s\n' "$PI2_LINE cgroup_enable=memory" > "$CL/cmdline.txt"
check "  a run cut short: the line finished, the kept original untouched" \
  "$(cl_run) $(grep -c ' ds=nocloud cgroup_enable=memory cgroup_memory=1$' "$CL/cmdline.txt") $(cmp -s <(printf '%s\n' "$PI2_LINE") "$CL/cmdline.txt.before-memory-cgroup" && echo kept)" \
  "rc=2 turns it on now: reboot it 1 kept"
# a kept copy older than the line now (the Pi cloned, a new root=; the flags off again): replaced by the line now - an
# undo to the old one would not boot
printf '%s\n' "console=tty1 root=PARTUUID=00000000-02 rootwait" > "$CL/cmdline.txt.before-memory-cgroup"; printf '%s\n' "$PI2_LINE" > "$CL/cmdline.txt"
check "  a kept copy older than the line: replaced by the line as it was before this run" \
  "$(cl_run) $(cmp -s <(printf '%s\n' "$PI2_LINE") "$CL/cmdline.txt.before-memory-cgroup" && echo kept)" \
  "rc=2 turns it on now: reboot it kept"
# config.txt pointing the firmware at another command line: the edit not made, the cause said
printf '%s\n' "$PI2_LINE" > "$CL/cmdline.txt"; cp "$CL/cmdline.txt" "$CL/before"; printf '[all]\n os_prefix=next/\n' > "$CL/config.txt"
check "  config.txt points the firmware elsewhere (os_prefix=): red, said so, the line untouched" \
  "$(cl_run) $(cmp -s "$CL/before" "$CL/cmdline.txt" && echo untouched)" "rc=2 reads another command line untouched"
printf '[all]\n# os_prefix=next/\narm_64bit=1\n' > "$CL/config.txt"
check "  config.txt with it commented out: the edit made" "$(cl_run)" "rc=2 turns it on now: reboot it"
rm "$CL/config.txt"
printf '%s\n' "$PI2_LINE" > "$CL/cmdline.txt"; cp "$CL/cmdline.txt" "$CL/before"
check "  a preview (--check): nothing written, said so" "$(cl_run --check) $(cmp -s "$CL/before" "$CL/cmdline.txt" && echo untouched)" \
  "rc=2 not --check untouched"
rm "$CL/cmdline.txt"
check "  no command line file (a VM): the edit skipped, the cause said" "$(cl_run)" "rc=2 cannot be turned on here"
rm -f "$CL/cmdline.txt.before-memory-cgroup" "$CL/syncs"; echo "console=tty1 root=X rootwait cgroup_enable=memory cgroup_memory=1" > "$CL/cmdline.txt"
cp "$CL/cmdline.txt" "$CL/before"; echo "cpuset cpu io memory pids" > "$CL/controllers"
check "  the controller live: green; a line already right - not written, no copy kept, nothing synced" \
  "$(cl_run) $(cmp -s "$CL/before" "$CL/cmdline.txt" && echo untouched) $(ls "$CL" | grep -c '^cmdline.txt\.') $(syncs)" "rc=0 untouched 0 0"
check "  the controller live, a preview (--check): green - the reads run in a preview too" "$(cl_run --check)" "rc=0"
echo "cpuset cpu io pids" > "$CL/controllers"; echo "$PI2_LINE cgroup_enable=memory cgroup_memory=1" > "$CL/proc-cmdline"
check "  booted with the flags, still no controller: a reboot will not help" "$(cl_run)" "rc=2 will not help"
# the boot partition is FAT: no name with ':' (Ansible's backup names carry a time - pi2's edit refused, 2026-10-16) - no
# edit of the command line keeps an Ansible backup, and every name written beside it is FAT-safe
check "the boot partition FAT: no Ansible backup on the command line's edits, every name written there FAT-safe" "$("$PY" - <<'PY_FAT'
import re, yaml
p = yaml.safe_load(open("deploy/ansible/playbooks/setup-pi-restore-check.yml"))[0]
ts = [t for t in p["tasks"] if "pi_cmdline_path" in str(t) or "/boot/firmware" in str(t)]
backups = [t["name"] for t in ts if any(isinstance(a, dict) and a.get("backup") for a in t.values())]
dests = [t["ansible.builtin.copy"]["dest"].replace("{{ pi_cmdline_path }}", "cmdline.txt") for t in ts if "ansible.builtin.copy" in t]
print(backups, dests, all(re.fullmatch(r"[A-Za-z0-9._-]+", d) for d in dests))
PY_FAT
)" "[] ['cmdline.txt.before-memory-cgroup'] True"
# the script reads the same path the playbook writes into its settings, and needs it
check "the controllers' path: the playbook's one variable, in the settings the script requires" "$(PYTHONDONTWRITEBYTECODE=1 "$PY" - "$SCRIPT" <<'PY_PATH'
import re, sys, yaml
p = yaml.safe_load(open("deploy/ansible/playbooks/setup-pi-restore-check.yml"))[0]
env = next(t for t in p["tasks"] if t["name"].startswith("Its settings"))["ansible.builtin.copy"]["content"]
script = open(sys.argv[1]).read()
print("PI_RESTORE_CGROUP_CONTROLLERS={{ pi_cgroup_controllers }}" in env, p["vars"]["pi_cgroup_controllers"],
      '"${PI_RESTORE_CGROUP_CONTROLLERS:?}"' in script, 'grep -qw memory "$PI_RESTORE_CGROUP_CONTROLLERS"' in script)
PY_PATH
)" "True /sys/fs/cgroup/cgroup.controllers True True"
echo "pi-restore-check: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
