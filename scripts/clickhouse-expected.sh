#!/usr/bin/env bash
# clickhouse-expected.sh - ClickHouse's compatibility setting and users as a platform ref sets them
# (helm/schnappy-observability/files/clickhouse-users.xml), for the copy's survival check - its seed (test:copy:argo,
# platform main) and its verify (scripts/copy-checks.sh, the ref under test) read the same: a change that moves the pin
# is held to its own value, never to a constant. Users: the file's, plus the image's `default` unless the file replaces
# the list - and, as infra's observability values turn them on (the infra ref), the backup job's user
# (clickhouse.backup.enabled: files/clickhouse-backup-user.xml) and Grafana's (clickhouse.grafanaUser:
# files/clickhouse-grafana-user.xml).
#
# Usage: scripts/clickhouse-expected.sh <platform-ref> [<infra-ref>]   ->   "<compatibility or -> <user,user...>" on one line
#        (no infra ref: the users file alone)
# Env:   COPY_PLATFORM_DIR (default ../platform), COPY_INFRA_DIR (default ../infra)
set -euo pipefail
# ranges as ASCII: under a UTF-8 locale bash's [A-Za-z] takes an accented letter too (usér passed the users check)
export LC_ALL=C
ops=$(cd "$(dirname "$0")/.." && pwd)
platform_ref=${1:?usage: $0 <platform-ref> [<infra-ref>]}
infra_ref=${2:-}
pdir=${COPY_PLATFORM_DIR:-$ops/../platform}
ch_xml=$(git -C "$pdir" show "$platform_ref:helm/schnappy-observability/files/clickhouse-users.xml") \
  || { echo "clickhouse-users.xml not read from platform $platform_ref" >&2; exit 1; }
# the extra users' files infra's values mount (each read from the platform ref; none without an infra ref)
extra=()
if [ -n "$infra_ref" ]; then
  values=$(git -C "${COPY_INFRA_DIR:-$ops/../infra}" show "$infra_ref:clusters/production/schnappy-observability/values.yaml") \
    || { echo "schnappy-observability's values not read from infra $infra_ref" >&2; exit 1; }
  on=$(python3 -c '
import sys, yaml
c = (yaml.safe_load(sys.stdin.read()) or {}).get("clickhouse") or {}
print(" ".join(f for f, v in (("clickhouse-backup-user.xml", (c.get("backup") or {}).get("enabled")),
                             ("clickhouse-grafana-user.xml", c.get("grafanaUser"))) if str(v).lower() == "true"))' <<< "$values") \
    || { echo "schnappy-observability's values of infra $infra_ref: not parsed" >&2; exit 1; }
  for f in $on; do
    x=$(git -C "$pdir" show "$platform_ref:helm/schnappy-observability/files/$f") \
      || { echo "$f not read from platform $platform_ref (infra $infra_ref turns it on)" >&2; exit 1; }
    extra+=("$x")
  done
fi
read -r compat users < <(python3 -c '
import sys, xml.etree.ElementTree as ET
docs = sys.stdin.read().split("\0")
r = ET.fromstring(docs[0])
users = r.find("users")
names = set() if users is None else {u.tag for u in users}
if users is None or users.get("replace") != "replace":
    names.add("default")
for d in docs[1:]:
    if d.strip():
        u = ET.fromstring(d).find("users")
        names |= set() if u is None else {x.tag for x in u}
print(r.findtext("profiles/default/compatibility") or "-", ",".join(sorted(names)))' \
  < <(printf '%s' "$ch_xml"; for x in "${extra[@]}"; do printf '\0%s' "$x"; done)) \
  || { echo "clickhouse-users.xml of platform $platform_ref: not parsed" >&2; exit 1; }
# both go into Ansible extra vars, where text is a template: a version, user names - nothing else from the ref
[[ $compat =~ ^(-|[0-9]+\.[0-9]+)$ && $users =~ ^[A-Za-z0-9_-]+(,[A-Za-z0-9_-]+)*$ ]] \
  || { echo "clickhouse-users.xml of platform $platform_ref: compatibility '$compat', users '$users' - not a version and user names" >&2; exit 1; }
echo "$compat $users"
