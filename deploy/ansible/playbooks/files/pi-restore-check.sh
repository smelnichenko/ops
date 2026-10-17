#!/bin/bash
# The backups restored on a Pi, every other day - setup-pi-restore-check.yml (ops) explains it. Settings and
# credentials from the unit's EnvironmentFile. Four parts, each run whatever the others did, each its own process
# (a function run as an `if` condition runs with set -e off):
#   postgres  production's CNPG cluster from the store: the newest restorable base backup, every WAL archived after it,
#             in production's own Postgres image - replayed to the end, the newest WAL archived when the run began
#             reached, every database there and read back whole (pg_dump)
#   etcd      ten's newest hourly snapshot: restored (its hash checked), an etcd started on it, kube-system there
#   scylla    production's newest Scylla Manager snapshot: its schema into a scratch Scylla in production's image, every
#             table's SSTables of the snapshot loaded (nodetool refresh), each table read back
#   tier0     the Pis' own newest backup: Consul's snapshot into a throwaway agent (Vault's and Patroni's keys there),
#             every Patroni database dump into a scratch Postgres
# Nothing is written to the store but restore-checks/<this Pi>/: the restored Postgres archives nothing (archive_mode
# off) and listens on no address; etcd and Scylla run without a network. A day with every part green writes last-success,
# which infra's restore-check-age reads.
set -euo pipefail
# what it writes is root's alone - production's backups (etcd's every Secret, the Pis' dumps) and the restored servers'
# sockets: a directory any local user could pass through let any service account read them or log in to a restored
# Postgres as its superuser (trust - review of 2026-10-16). Each part gives its directory to the user that needs it
umask 077

store_age_h() {  # store_age_h <yyyymmddThhmmss UTC>: hours since then
  local t=$1
  echo $(( ($(date -u +%s) - $(date -u -d "${t:0:4}-${t:4:2}-${t:6:2} ${t:9:2}:${t:11:2}:${t:13:2}" +%s)) / 3600 ))
}

pg_bin() {  # this Pi's newest Postgres (the major Patroni runs here)
  local root=${PI_RESTORE_PG_ROOT:-/usr/lib/postgresql}
  echo "$root/$(find "$root" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort -V | tail -1)/bin"
}

# the kernel's memory cgroup controller: without it no container's --memory can be set (crun: "opening file
# `memory.max`") - Raspberry Pi OS boots with it off unless its command line turns it on (setup-pi-restore-check.yml)
memory_bounded() {
  grep -qw memory "$PI_RESTORE_CGROUP_CONTROLLERS" \
    || { echo "this Pi's kernel has no memory cgroup controller (cgroup_enable=memory cgroup_memory=1 on its command line, then a reboot): its containers cannot be bounded"; return 1; }
}

part_postgres() {
  local w=$1/pg name="pi-restore-pg-$$" server="" id="" newest="" s b
  memory_bounded || return 1
  mkdir -p "$w"
  # the server written last: production's (an old one - before a rename, before a major upgrade - stops getting
  # backups)
  for s in $(rclone lsf --dirs-only store:postgres-backups); do
    s=${s%/}
    b=$(rclone lsf --dirs-only "store:postgres-backups/$s/base" 2> /dev/null | grep -E '^[0-9]{8}T[0-9]{6}/$' | sort | tail -1)
    b=${b%/}
    if [ -n "$b" ] && [[ "$b" > "$newest" ]]; then newest=$b; server=$s; fi
  done
  [ -n "$server" ] || { echo "no base backup in postgres-backups"; return 1; }
  # every WAL segment archived (the timeline aside, as a recovery reads them), and the timelines a promotion's history
  # file names
  local listing wals histories wal
  listing=$(rclone lsf -R --files-only "store:postgres-backups/$server/wals" | sed 's#.*/##')
  wals=$(awk '/^[0-9A-F]{24}(\.[a-z0-9]+)?$/ { print substr($0, 1, 24) }' <<< "$listing" | sort -u)
  histories=$(awk '/^[0-9A-F]{8}\.history(\.[a-z0-9]+)?$/ { print substr($0, 1, 8) }' <<< "$listing" | sort -u)
  [ -n "$wals" ] || { echo "$server: no WAL archived"; return 1; }
  # its newest restorable backup: complete (one still being written has no status=DONE) and its end WAL archived - an
  # idle database leaves the newest backup's end segment unfinished, so unarchived, for as long as nothing writes. A
  # day of hourly backups looked at: archiving stopped leaves none restorable, and the age below says so
  local info="" end_wal
  for b in $(rclone lsf --dirs-only "store:postgres-backups/$server/base" | grep -E '^[0-9]{8}T[0-9]{6}/$' | sort -r \
      | head -"$PI_RESTORE_PG_BACKUPS_LOOKED_AT"); do
    # none yet (barman writes it last), or unreadable now: not this one
    info=$(rclone cat "store:postgres-backups/$server/base/${b}backup.info" 2> /dev/null) || continue
    grep -qx 'status=DONE' <<< "$info" || continue
    end_wal=$(sed -n 's/^end_wal=//p' <<< "$info")
    if [ -n "$end_wal" ] && grep -qx "$end_wal" <<< "$wals"; then id=${b%/}; break; fi
  done
  [ -n "$id" ] || { echo "$server: none of its $PI_RESTORE_PG_BACKUPS_LOOKED_AT newest base backups is restorable (complete, its end WAL archived)"; return 1; }
  # the bar the replay must reach: the furthest segment archived on the timeline the recovery ends on - the newest a
  # history file names from the backup's on (a promotion's), else the backup's own; one with nothing archived yet (a
  # promotion just made) gives way to the one before. By position across all timelines a segment the old primary
  # archived past a fork could never be reached; by name a timeline with no history - a stray, as production's archive
  # holds one of a timeline 3 (2026-10-15) - lowered the bar. Neither is followed by a recovery, neither counts
  local tli candidates
  candidates=$( { echo "${end_wal:0:8}"; awk -v b="${end_wal:0:8}" '$0 > b' <<< "$histories"; } | sort -ru)
  for tli in $candidates; do
    # (awk, not grep: none on a timeline is an answer here, not a failure under pipefail)
    wal=$(awk -v t="$tli" 'substr($0, 1, 8) == t { print substr($0, 9, 16), $0 }' <<< "$wals" | sort | tail -1 | cut -d' ' -f2)
    [ -z "$wal" ] || break
  done
  local version major image
  version=$(sed -n 's/^version=//p' <<< "$info")
  major=$(( version / 10000 ))
  image_var="PI_RESTORE_PG_IMAGE_$major"
  image=${!image_var:-}
  [ -n "$image" ] || { echo "$server/$id is PostgreSQL $major: no image for it ($image_var)"; return 1; }
  local age
  age=$(store_age_h "$id")
  [ "$age" -le "$PI_RESTORE_PG_BASE_MAX_AGE_H" ] \
    || { echo "$server's newest restorable base backup $id is $age h old (limit $PI_RESTORE_PG_BASE_MAX_AGE_H h)"; return 1; }
  # a registry down is no reason to fail when the image is here already
  podman pull -q "$image" > /dev/null || podman image exists "$image"
  # the image's postgres user (CNPG's images: 26) owns the data
  chown 26:26 "$w"
  podman run --rm --network host --memory "$PI_RESTORE_CONTAINER_MEMORY" --user 26:26 -e AWS_ACCESS_KEY_ID \
    -e AWS_SECRET_ACCESS_KEY -v "$w:/w" \
    --entrypoint barman-cloud-restore "$image" --cloud-provider aws-s3 --endpoint-url "$STORE_ENDPOINT" \
    s3://postgres-backups "$server" "$id" /w/pgdata
  # recovery to the end of the archive, then promoted; CNPG's own settings that point at its controller (sockets,
  # logs, certificates, the archive command) overridden
  touch "$w/pgdata/recovery.signal"
  rm -f "$w/pgdata/standby.signal"
  printf 'local all all trust\n' > "$w/hba.conf"
  chown 26:26 "$w/pgdata/recovery.signal" "$w/hba.conf"
  podman run -d --name "$name" --network host --memory "$PI_RESTORE_CONTAINER_MEMORY" --user 26:26 -e AWS_ACCESS_KEY_ID \
    -e AWS_SECRET_ACCESS_KEY -v "$w:/w" \
    --entrypoint postgres "$image" -D /w/pgdata -c listen_addresses= -c unix_socket_directories=/w -c port=5432 \
    -c ssl=off -c archive_mode=off -c logging_collector=off -c log_destination=stderr -c hba_file=/w/hba.conf \
    -c unix_socket_permissions=0700 \
    -c shared_buffers=256MB \
    -c "restore_command=barman-cloud-wal-restore --cloud-provider aws-s3 --endpoint-url $STORE_ENDPOINT s3://postgres-backups $server %f %p" \
    > /dev/null
  echo "$name" >> "$1/containers"
  # gone when this part ends, its memory free before the next part starts (the run's cleanup removes it on a kill)
  # shellcheck disable=SC2064  # the name now: the function's locals are gone when the part's process exits
  trap "podman rm -f -t 0 $name > /dev/null 2>&1 || true" EXIT
  local i state r=""
  for i in $(seq "$PI_RESTORE_PG_WAIT_POLLS"); do
    state=$(podman inspect -f '{{.State.Running}}' "$name")
    if [ "$state" != true ]; then
      podman logs --tail 30 "$name" 2>&1 || true
      echo "$server/$id: Postgres stopped during the recovery"; return 1
    fi
    r=$(podman exec "$name" psql -h /w -U postgres -Atc 'select pg_is_in_recovery()' 2> /dev/null || true)
    [ "$r" != f ] || break
    sleep 5
  done
  [ "$r" = f ] || { podman logs --tail 30 "$name" 2>&1 || true; echo "$server/$id: still recovering after $(( PI_RESTORE_PG_WAIT_POLLS * 5 )) s"; return 1; }
  q() { podman exec "$name" psql -h /w -U postgres -v ON_ERROR_STOP=1 -Atc "$1" "${2:-postgres}"; }
  # promoted on a new timeline, after the last WAL replayed: its segment (the timeline aside) not before the newest
  # archived when this run began
  local seg
  seg=$(q 'select pg_walfile_name(pg_current_wal_lsn())')
  [[ ! "${seg:8:16}" < "${wal:8:16}" ]] \
    || { echo "$server/$id: replayed to $seg, short of $wal - the furthest archived on timeline $tli (the one the recovery follows) when the run began"; return 1; }
  local have db missing=() tables total=0 counts=()
  have=" $(q "select string_agg(datname, ' ') from pg_database where not datistemplate") "
  for db in $PI_RESTORE_PG_DATABASES; do
    [[ "$have" == *" $db "* ]] || missing+=("$db")
  done
  [ "${#missing[@]}" = 0 ] || { echo "$server/$id: databases missing: ${missing[*]} (has:$have)"; return 1; }
  for db in $PI_RESTORE_PG_DATABASES; do
    # an app not deployed yet has its database and no table (masi in production): a database may be empty, the
    # cluster may not
    tables=$(q "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where c.relkind = 'r' and n.nspname not in ('pg_catalog', 'information_schema')" "$db")
    total=$(( total + tables ))
    counts+=("$db:$tables")
    # every row read: a page the restore got wrong fails the dump (--no-sync: /dev/null takes no fsync)
    podman exec "$name" pg_dump -h /w -U postgres --no-sync --format=custom --file=/dev/null "$db"
  done
  [ "$total" -gt 0 ] || { echo "$server/$id: restored with no table in any database (${counts[*]})"; return 1; }
  echo "POSTGRES OK: $server/$id (PostgreSQL $major, $image) replayed to $seg (newest archived at the start: $wal);" \
    "databases (tables) ${counts[*]}, each read back whole"
}

part_etcd() {
  local w=$1/etcd name="pi-restore-etcd-$$" snap age
  memory_bounded || return 1
  mkdir -p "$w"
  snap=$(rclone lsf --files-only store:etcd-backups | grep -E '^etcd-[0-9]{8}-[0-9]{6}\.db$' | sort | tail -1)
  [ -n "$snap" ] || { echo "no snapshot in etcd-backups"; return 1; }
  local t=${snap#etcd-}
  t=${t%.db}
  age=$(store_age_h "${t:0:8}T${t:9:6}")
  [ "$age" -le "$PI_RESTORE_ETCD_MAX_AGE_H" ] || { echo "the newest etcd snapshot $snap is $age h old (limit $PI_RESTORE_ETCD_MAX_AGE_H h)"; return 1; }
  rclone copyto "store:etcd-backups/$snap" "$w/snap.db"
  podman pull -q "$PI_RESTORE_ETCD_IMAGE" > /dev/null || podman image exists "$PI_RESTORE_ETCD_IMAGE"
  local e=(podman run --rm --network none --memory "$PI_RESTORE_CONTAINER_MEMORY" -v "$w:/w" "$PI_RESTORE_ETCD_IMAGE")
  local status
  status=$("${e[@]}" etcdutl snapshot status /w/snap.db -w json)
  # the restore checks the snapshot's hash
  "${e[@]}" etcdutl snapshot restore /w/snap.db --data-dir /w/data --name restore \
    --initial-cluster restore=http://127.0.0.1:2380 --initial-advertise-peer-urls http://127.0.0.1:2380 > /dev/null
  podman run -d --name "$name" --network none --memory "$PI_RESTORE_CONTAINER_MEMORY" -v "$w:/w" "$PI_RESTORE_ETCD_IMAGE" \
    etcd --data-dir /w/data --name restore \
    --listen-client-urls http://127.0.0.1:2379 --advertise-client-urls http://127.0.0.1:2379 \
    --listen-peer-urls http://127.0.0.1:2380 --initial-advertise-peer-urls http://127.0.0.1:2380 \
    --initial-cluster restore=http://127.0.0.1:2380 > /dev/null
  echo "$name" >> "$1/containers"
  # gone when this part ends, its memory free before the next part starts (the run's cleanup removes it on a kill)
  # shellcheck disable=SC2064  # the name now: the function's locals are gone when the part's process exits
  trap "podman rm -f -t 0 $name > /dev/null 2>&1 || true" EXIT
  # the namespaces, read once etcd serves (it elects itself first): kube-system among them. One read - judged on what it
  # returned (a second query on its own once failed with nothing to show)
  local i ns=0 keys=""
  for i in $(seq "$PI_RESTORE_ETCD_WAIT_POLLS"); do
    if [ "$(podman inspect -f '{{.State.Running}}' "$name")" != true ]; then
      podman logs --tail 30 "$name" 2>&1 || true
      echo "$snap: etcd stopped on the restored data"; return 1
    fi
    keys=$(podman exec "$name" etcdctl --endpoints http://127.0.0.1:2379 get /registry/namespaces/ --prefix --keys-only 2>&1 \
      || true)
    ns=$(grep -c '^/registry/namespaces/' <<< "$keys" || true)
    [ "$ns" -gt 0 ] && break
    sleep 2
  done
  if [ "$ns" -eq 0 ]; then
    podman logs --tail 30 "$name" 2>&1 || true
    echo "$keys" | tail -5
    echo "$snap: etcd on the restored data served no namespace within $(( PI_RESTORE_ETCD_WAIT_POLLS * 2 )) s"; return 1
  fi
  if ! grep -qx /registry/namespaces/kube-system <<< "$keys"; then
    grep '^/registry/namespaces/' <<< "$keys" | head -30
    echo "$snap: restored, but no kube-system namespace in it"; return 1
  fi
  echo "ETCD OK: $snap ($age h old; $status) restored, $ns namespaces in it, kube-system among them"
}

# production's Scylla from Scylla Manager's backups (backup/{meta,schema,sst}/cluster/<id>/ in scylla-backups): the newest
# snapshot of the cluster backed up last, its schema (the CQL Scylla Manager saved with it) into a scratch Scylla in
# production's image, every table's SSTables of that snapshot loaded, each table read back
part_scylla() {
  local w=$1/scylla name="pi-restore-scylla-$$" b=store:scylla-backups/backup cluster="" tag="" c t age
  memory_bounded || return 1
  mkdir -p "$w/sst"
  # the cluster snapshotted last: production's (an old one - before a re-create - stops getting snapshots)
  for c in $(rclone lsf --dirs-only "$b/meta/cluster" | sed 's#/$##'); do
    t=$(rclone lsf -R --files-only "$b/meta/cluster/$c" \
      | sed -n 's/.*_tag_\(sm_[0-9]\{14\}UTC\)_manifest\.json\.gz$/\1/p' | sort | tail -1)
    if [ -n "$t" ] && [[ "$t" > "$tag" ]]; then tag=$t; cluster=$c; fi
  done
  [ -n "$cluster" ] || { echo "no snapshot in scylla-backups"; return 1; }
  age=$(store_age_h "${tag:3:8}T${tag:11:6}")
  [ "$age" -le "$PI_RESTORE_SCYLLA_MAX_AGE_H" ] \
    || { echo "the newest Scylla snapshot $cluster/$tag is $age h old (limit $PI_RESTORE_SCYLLA_MAX_AGE_H h)"; return 1; }
  # its manifests (one a node) and the schema saved with it
  local m schema n=0
  rclone lsf -R --files-only "$b/meta/cluster/$cluster" | { grep "_tag_${tag}_manifest\.json\.gz$" || true; } > "$w/manifests"
  while read -r m; do
    n=$(( n + 1 ))
    rclone cat "$b/meta/cluster/$cluster/$m" | gzip -dc > "$w/manifest.$n.json"
    echo "$m" >> "$w/manifest-paths"
  done < "$w/manifests"
  schema=$(rclone lsf --files-only "$b/schema/cluster/$cluster" | { grep "_tag_${tag}_schema_with_internals\.json\.gz$" || true; } \
    | head -1)
  [ -n "$schema" ] || { echo "$cluster/$tag: no schema saved with it"; return 1; }
  rclone cat "$b/schema/cluster/$cluster/$schema" | gzip -dc > "$w/schema.json"
  # the keyspaces of its own (system ones are the scratch Scylla's): their CQL, and each table's files of the snapshot -
  # one list a node, the paths under that node's sst/ directory (the store keeps every snapshot's files side by side)
  python3 - "$w" <<'PY_SCYLLA'
import json, sys
w = sys.argv[1]
own = lambda ks: not ks.startswith("system")
with open(f"{w}/schema.cql", "w") as out:
    for r in json.load(open(f"{w}/schema.json")):
        if own(r["keyspace"]):
            out.write(r["cql_stmt"].rstrip().rstrip(";") + ";\n")
paths = open(f"{w}/manifest-paths").read().split()
tables = set()
for i, path in enumerate(paths, 1):
    node = path.split("/")[3]  # dc/<dc>/node/<node>/task_...
    with open(f"{w}/files.{node}", "w") as out:
        open(f"{w}/prefix.{node}", "w").write(path.rsplit("/", 1)[0] + "\n")
        for t in json.load(open(f"{w}/manifest.{i}.json"))["index"]:
            if own(t["keyspace"]) and t["files"]:
                tables.add(f'{t["keyspace"]}.{t["table"]}')
                for f in t["files"]:
                    out.write(f'keyspace/{t["keyspace"]}/table/{t["table"]}/{t["version"]}/{f}\n')
open(f"{w}/tables", "w").write("".join(f"{t}\n" for t in sorted(tables)))
PY_SCYLLA
  [ -s "$w/tables" ] || { echo "$cluster/$tag: no table of its own with data in the snapshot"; return 1; }
  local f node
  for f in "$w"/files.*; do
    node=${f##*/files.}
    rclone copy --files-from-raw "$f" "$b/sst/cluster/$cluster/$(cat "$w/prefix.$node")" "$w/sst/$node"
  done
  podman pull -q "$PI_RESTORE_SCYLLA_IMAGE" > /dev/null || podman image exists "$PI_RESTORE_SCYLLA_IMAGE"
  # Seastar keeps memory back for the system: a reserve of its own (256M), the rest of the container bar 256M its own
  # (1G in 1536m - with its default reserve it refused: "insufficient physical memory", seen 2026-10-17)
  local mem=${PI_RESTORE_CONTAINER_MEMORY%[mM]}
  [[ "$mem" =~ ^[0-9]+$ ]] && [ "$mem" -ge 1536 ] \
    || { echo "PI_RESTORE_CONTAINER_MEMORY=$PI_RESTORE_CONTAINER_MEMORY: Scylla wants at least 1536m"; return 1; }
  # its data in the container (a bind mount is the host's, not Scylla's user's); the snapshot's files read-only beside it
  podman run -d --name "$name" --network none --memory "$PI_RESTORE_CONTAINER_MEMORY" -v "$w:/w:ro" \
    "$PI_RESTORE_SCYLLA_IMAGE" --smp 1 --memory "$(( mem - 512 ))M" --reserve-memory 256M --overprovisioned 1 \
    --developer-mode 1 --listen-address 127.0.0.1 --rpc-address 127.0.0.1 --seeds 127.0.0.1 > /dev/null
  echo "$name" >> "$1/containers"
  # shellcheck disable=SC2064  # the name now: the function's locals are gone when the part's process exits
  trap "podman rm -f -t 0 $name > /dev/null 2>&1 || true" EXIT
  local i up=""
  for i in $(seq "$PI_RESTORE_SCYLLA_WAIT_POLLS"); do
    if [ "$(podman inspect -f '{{.State.Running}}' "$name")" != true ]; then
      podman logs --tail 30 "$name" 2>&1 || true
      echo "$cluster/$tag: Scylla stopped before it served"; return 1
    fi
    podman exec "$name" cqlsh -e "SELECT now() FROM system.local" > /dev/null 2>&1 && { up=1; break; }
    sleep 3
  done
  if [ -z "$up" ]; then
    podman logs --tail 30 "$name" 2>&1 || true
    echo "$cluster/$tag: Scylla served no CQL within $(( PI_RESTORE_SCYLLA_WAIT_POLLS * 3 )) s"; return 1
  fi
  podman exec "$name" cqlsh -f /w/schema.cql > "$w/schema.log" 2>&1 \
    || { tail -10 "$w/schema.log"; echo "$cluster/$tag: its schema did not apply"; return 1; }
  # each table's files into its upload directory, Scylla's own, then loaded; read back whole
  local ks tb dir rows counts=() total=0
  while IFS=. read -r ks tb; do
    dir=$(podman exec "$name" sh -c "ls -d /var/lib/scylla/data/$ks/$tb-*" 2> /dev/null | head -1)
    [ -n "$dir" ] || { echo "$cluster/$tag: $ks.$tb not created by its schema"; return 1; }
    podman exec -u root "$name" sh -c \
      "cp /w/sst/*/keyspace/$ks/table/$tb/*/* '$dir/upload/' && chown -R scylla:scylla '$dir/upload'"
    podman exec "$name" nodetool refresh "$ks" "$tb" > "$w/refresh.log" 2>&1 \
      || { tail -5 "$w/refresh.log"; echo "$cluster/$tag: $ks.$tb's SSTables did not load"; return 1; }
    rows=$(podman exec "$name" cqlsh --request-timeout=300 -e "SELECT count(*) FROM $ks.$tb" \
      | sed -n 's/^ *\([0-9][0-9]*\) *$/\1/p' | head -1)
    [ -n "$rows" ] || { echo "$cluster/$tag: $ks.$tb not read back"; return 1; }
    counts+=("$ks.$tb:$rows"); total=$(( total + rows ))
  done < "$w/tables"
  [ "$total" -gt 0 ] || { echo "$cluster/$tag: restored with no row in any table (${counts[*]})"; return 1; }
  echo "SCYLLA OK: $cluster/$tag ($age h old, $PI_RESTORE_SCYLLA_IMAGE) restored; tables (rows) ${counts[*]}, each read back"
}

part_tier0() {
  local w=$1/tier0 d age
  # its scratch Postgres and Consul agent run in the unit's cgroup: its MemoryMax is no bound without the controller
  memory_bounded || return 1
  mkdir -p "$w"
  d=$(rclone lsf --dirs-only store:pi-backups | grep -E '^[0-9]{8}T[0-9]{6}Z/$' | sort | tail -1)
  d=${d%/}
  [ -n "$d" ] || { echo "no backup in pi-backups"; return 1; }
  age=$(store_age_h "${d%Z}")
  [ "$age" -le "$PI_RESTORE_TIER0_MAX_AGE_H" ] || { echo "the Pis' newest backup $d is $age h old (limit $PI_RESTORE_TIER0_MAX_AGE_H h)"; return 1; }
  rclone copy "store:pi-backups/$d" "$w/b"
  # the dumps read by the scratch Postgres's own user, through this part's directory (passable, not readable)
  chmod 0711 "$w"
  chown -R postgres: "$w/b"
  [ ! -e "$w/b/KEYCLOAK-EXPORT-FAILED" ] || { echo "$d: its Keycloak export failed"; return 1; }
  # Consul's snapshot into a throwaway dev agent on other ports (as test-pi-backups.yml restores it)
  consul agent -dev -node=restore-check -data-dir="$w/consul" -bind=127.0.0.1 -client=127.0.0.1 \
    -http-port=18500 -server-port=18300 -serf-lan-port=18301 -serf-wan-port=-1 -dns-port=-1 -grpc-port=-1 -grpc-tls-port=-1 \
    > "$w/consul.log" 2>&1 &
  echo $! > "$1/consul.pid"
  local i
  for i in $(seq 60); do
    [ "$(curl -s --max-time 5 http://127.0.0.1:18500/v1/status/leader)" = '"127.0.0.1:18300"' ] && break
    sleep 1
  done
  consul snapshot restore -http-addr=127.0.0.1:18500 "$w/b/consul.snap" > /dev/null
  local vault patroni
  vault=$(consul kv get -http-addr=127.0.0.1:18500 -recurse vault/core/ | grep -c . || true)
  patroni=$(consul kv get -http-addr=127.0.0.1:18500 -recurse service/ | grep -c '/leader:' || true)
  [ "$vault" -gt 0 ] && [ "$patroni" -gt 0 ] \
    || { echo "$d: Consul's snapshot restored with $vault vault/core keys and $patroni Patroni leader keys"; return 1; }
  # every Patroni database into a scratch Postgres of this Pi's own
  local bin
  bin=$(pg_bin)
  mkdir -p "$w/pg" "$w/sock"
  chown postgres: "$w/pg" "$w/sock"
  runuser -u postgres -- "$bin/initdb" -D "$w/pg" -U postgres --auth=trust > /dev/null
  runuser -u postgres -- "$bin/pg_ctl" -D "$w/pg" -l "$w/pg/log" -w \
    -o "-c listen_addresses='' -c unix_socket_directories=$w/sock -c unix_socket_permissions=0700 -c port=55432" \
    start > /dev/null
  echo "$w/pg" > "$1/scratch-pg"
  local P=(-h "$w/sock" -p 55432 -U postgres)
  # the roles first (the dumps' owners); postgres itself exists already - its CREATE fails, nothing else may
  local rc=0
  runuser -u postgres -- "$bin/psql" "${P[@]}" -q -f "$w/b/pg-globals.sql" > "$w/globals.log" 2>&1 || rc=$?
  [ "$rc" = 0 ] || { cat "$w/globals.log"; echo "$d: psql could not run pg-globals.sql (exit $rc)"; return 1; }
  if grep 'ERROR' "$w/globals.log" | grep -v 'role "postgres" already exists' | grep -q .; then
    cat "$w/globals.log"; echo "$d: pg-globals.sql did not restore"; return 1
  fi
  local f db tables dbs=()
  for f in "$w"/b/pg-*.dump; do
    [ -e "$f" ] || { echo "$d: no database dump"; return 1; }
    db=${f##*/pg-}
    db=${db%.dump}
    runuser -u postgres -- "$bin/createdb" "${P[@]}" "$db"
    runuser -u postgres -- "$bin/pg_restore" "${P[@]}" --exit-on-error -d "$db" "$f"
    tables=$(runuser -u postgres -- "$bin/psql" "${P[@]}" -Atc "select count(*) from pg_class c
      join pg_namespace n on n.oid = c.relnamespace where c.relkind = 'r'
      and n.nspname not in ('pg_catalog', 'information_schema')" "$db")
    [ "$tables" -gt 0 ] || { echo "$d: database $db restored with no table"; return 1; }
    dbs+=("$db:$tables")
  done
  echo "TIER0 OK: $d ($age h old) - Consul: $vault vault/core keys, $patroni Patroni leader keys; databases (tables):" \
    "${dbs[*]}"
}

cleanup() {  # cleanup <work>: what the parts started, then the work directory
  local w=$1 c
  if [ -f "$w/containers" ]; then
    # -t 0: no stop wait - consul lock's SIGKILL follows its SIGTERM within seconds
    while read -r c; do podman rm -f -t 0 "$c" > /dev/null 2>&1 || true; done < "$w/containers"
  fi
  [ ! -f "$w/consul.pid" ] || kill "$(cat "$w/consul.pid")" 2> /dev/null || true
  if [ -f "$w/scratch-pg" ]; then
    runuser -u postgres -- "$(pg_bin)/pg_ctl" \
      -D "$(cat "$w/scratch-pg")" -m immediate stop > /dev/null 2>&1 || true
  fi
  rm -rf "$w"
  # the images a moved tag left behind
  podman image prune -f > /dev/null 2>&1 || true
}

# a part: its own process, so set -e holds in it
if [ "${1:-}" = --part ]; then
  "part_$2" "$3"
  exit
fi

: "${PI_RESTORE_NAME:?}" "${PI_RESTORE_PARITY:?}" "${PI_RESTORE_PG_DATABASES:?}" "${PI_RESTORE_ETCD_IMAGE:?}"
: "${STORE_ENDPOINT:?}" "${PI_RESTORE_PG_BASE_MAX_AGE_H:?}" "${PI_RESTORE_PG_BACKUPS_LOOKED_AT:?}" "${PI_RESTORE_PG_WAIT_POLLS:?}"
: "${PI_RESTORE_ETCD_MAX_AGE_H:?}" "${PI_RESTORE_TIER0_MAX_AGE_H:?}" "${PI_RESTORE_WORK:?}" "${PI_RESTORE_MIN_FREE_GB:?}"
: "${PI_RESTORE_CONTAINER_MEMORY:?}" "${PI_RESTORE_ETCD_WAIT_POLLS:?}" "${PI_RESTORE_CGROUP_CONTROLLERS:?}"
: "${PI_RESTORE_SCYLLA_IMAGE:?}" "${PI_RESTORE_SCYLLA_MAX_AGE_H:?}" "${PI_RESTORE_SCYLLA_WAIT_POLLS:?}"

if [ -z "${PI_RESTORE_LOCKED:-}" ]; then
  # the clock synchronized first (as pi-tier0-backup's): the day's parity and every age below read it
  for i in $(seq 60); do
    [ "$(timedatectl show -p NTPSynchronized --value 2> /dev/null)" = yes ] && break
    if [ -e "${PI_RESTORE_TIMESYNC_MARKER:-/run/systemd/timesync/synchronized}" ] \
        || chronyc -n tracking 2> /dev/null | grep -q '^Leap status *: Normal$'; then
      break
    fi
    [ "$i" != 60 ] || { echo "the clock is not synchronized (timedatectl) - no restore check" >&2; exit 1; }
    sleep 10
  done
  # every other day each: the two Pis take turns (PI_RESTORE_ANY_DAY=1 runs it today - a test, a check by hand)
  day=$(( $(date -u +%s) / 86400 ))
  if [ $(( day % 2 )) != "$PI_RESTORE_PARITY" ] && [ -z "${PI_RESTORE_ANY_DAY:-}" ]; then
    echo "not $PI_RESTORE_NAME's day (UTC day $day; it takes the $([ "$PI_RESTORE_PARITY" = 0 ] && echo even || echo odd) ones)"
    exit 0
  fi
  # never two at once (a late timer, a run by hand): Consul's lock, the run's failure passed on
  PI_RESTORE_LOCKED=1 exec consul lock -child-exit-code -timeout=30m pi-restore-check "$0"
fi

# an early failure here names its line: no run ends without a word
trap 'echo "PI RESTORE CHECK: failed at line $LINENO" >&2' ERR
mkdir -p "$PI_RESTORE_WORK"
# what a killed run left (SIGKILL past the unit's timeout, a reboot - its EXIT trap never ran): its containers and its
# directory, before this run takes the room. Under the lock, so never a running one's
# A container whose run was killed lost its conmon with it: the first removal fails ("conmon exited prematurely") and
# records it exited, the second removes it (seen on the Vagrant copy). One refusing both is said, and the run goes on -
# it takes memory, not this run's names
for c in $(podman ps -a --format '{{.Names}}' | { grep -E '^pi-restore-(pg|etcd|scylla)-[0-9]+$' || true; }); do
  podman rm -f -t 0 "$c" > /dev/null 2>&1 || podman rm -f -t 0 "$c" > /dev/null \
    || echo "PI RESTORE CHECK: a killed run's container $c not removed now" >&2
done
rm -rf "$PI_RESTORE_WORK"/run.*
# room for a restore: a full disk on a Pi stops Vault, Consul and Patroni with it
free_gb=$(( $(df --output=avail -k "$PI_RESTORE_WORK" | tail -1) / 1024 / 1024 ))
[ "$free_gb" -ge "$PI_RESTORE_MIN_FREE_GB" ] \
  || { echo "PI RESTORE CHECK: $free_gb GiB free under $PI_RESTORE_WORK, under $PI_RESTORE_MIN_FREE_GB GiB - no restore"; exit 1; }
work=$(mktemp -d "$PI_RESTORE_WORK/run.XXXXXX")
# passable, not readable: each part's own directory is its user's alone
chmod 0711 "$work"
trap 'cleanup "$work"' EXIT
ts=$(date -u +%Y%m%dT%H%M%SZ)
for part in postgres etcd scylla tier0; do
  if "$0" --part "$part" "$work" > "$work/$part.log" 2>&1; then
    tail -1 "$work/$part.log"
  else
    echo "${part^^} FAILED:"
    tail -20 "$work/$part.log" | sed 's/^/  /'
  fi
done 2>&1 | tee "$work/report"
# the parts that failed, from the report (the loop ran in the pipeline's subshell)
mapfile -t failed < <(sed -n 's/^\([A-Z0-9]*\) FAILED:$/\1/p' "$work/report")
rclone mkdir store:restore-checks
{ echo "$ts $PI_RESTORE_NAME"; cat "$work/report"; } | rclone rcat "store:restore-checks/$PI_RESTORE_NAME/last-report"
if [ "${#failed[@]}" != 0 ]; then
  echo "PI RESTORE CHECK $ts FAILED: ${failed[*]}"
  exit 1
fi
echo "$ts" | rclone rcat "store:restore-checks/$PI_RESTORE_NAME/last-success"
echo "PI RESTORE CHECK $ts: every part restored"
