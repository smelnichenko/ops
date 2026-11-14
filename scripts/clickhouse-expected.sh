#!/usr/bin/env bash
# clickhouse-expected.sh - ClickHouse's compatibility setting and users as a platform ref sets them
# (helm/schnappy-observability/files/clickhouse-users.xml), for the copy's survival check - its seed (test:copy:argo,
# platform main) and its verify (scripts/copy-checks.sh, the ref under test) read the same: a change that moves the pin
# is held to its own value, never to a constant. Users: the file's, plus the image's `default` unless the file replaces
# the list.
#
# Usage: scripts/clickhouse-expected.sh <platform-ref>   ->   "<compatibility or -> <user,user...>" on one line
# Env:   COPY_PLATFORM_DIR (default ../platform)
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
platform_ref=${1:?usage: $0 <platform-ref>}
ch_xml=$(git -C "${COPY_PLATFORM_DIR:-$ops/../platform}" show \
  "$platform_ref:helm/schnappy-observability/files/clickhouse-users.xml") \
  || { echo "clickhouse-users.xml not read from platform $platform_ref" >&2; exit 1; }
read -r compat users < <(python3 -c '
import sys, xml.etree.ElementTree as ET
r = ET.fromstring(sys.stdin.read())
users = r.find("users")
names = set() if users is None else {u.tag for u in users}
if users is None or users.get("replace") != "replace":
    names.add("default")
print(r.findtext("profiles/default/compatibility") or "-", ",".join(sorted(names)))' <<< "$ch_xml") \
  || { echo "clickhouse-users.xml of platform $platform_ref: not parsed" >&2; exit 1; }
# both go into Ansible extra vars, where text is a template: a version, user names - nothing else from the ref
[[ $compat =~ ^(-|[0-9]+\.[0-9]+)$ && $users =~ ^[A-Za-z0-9_-]+(,[A-Za-z0-9_-]+)*$ ]] \
  || { echo "clickhouse-users.xml of platform $platform_ref: compatibility '$compat', users '$users' - not a version and user names" >&2; exit 1; }
echo "$compat $users"
