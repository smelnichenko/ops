#!/usr/bin/env bash
# pi-apt-pin.sh <package>=<version>... - on a Vagrant copy's Pi (root): each Debian package installed here moved to
# production's version (tests/ansible/copy/pi-versions.yml's pi_apt_versions). Debian's archive serves only a
# package's newest version, and production's Pis run the security level they last took (2026-11-14: haproxy deb13u3
# and postgresql-17 17.11 there, the archive at deb13u4 and 17.12) - the copy built from the archive had newer
# packages than production, and an upgrade proven on it would have started from versions production never ran.
#   - at production's version already: nothing;
#   - not installed here: nothing, said (the copy's inventory then shows it missing - never installed by this);
#   - in the archive at that version: installed from it;
#   - else from snapshot.debian.org, at the time that version was first published (its archive: debian-security's
#     trixie-security, or debian's trixie, trixie-updates and trixie-proposed-updates), the snapshot's source added for
#     the install only - a version snapshot does not have fails the run, named.
# Downgrades allowed (that is the point); the services restart on the new binaries at the copy's cold boot after it.
#
# Usage: scripts/pi-apt-pin.sh <package>=<version>...
# Env:   PI_APT_SOURCES_DIR (default /etc/apt/sources.list.d), PI_APT_SNAPSHOT (default https://snapshot.debian.org) - tests
set -euo pipefail
sources=${PI_APT_SOURCES_DIR:-/etc/apt/sources.list.d}
snapshot=${PI_APT_SNAPSHOT:-https://snapshot.debian.org}
export DEBIAN_FRONTEND=noninteractive
[ $# -gt 0 ] || { echo "usage: $0 <package>=<version>..."; exit 2; }
for spec in "$@"; do
  [[ $spec =~ ^[a-z0-9][a-z0-9.+-]*=([0-9]+:)?[0-9][0-9A-Za-z.+~-]*$ ]] || { echo "not <package>=<version>: '$spec'"; exit 2; }
done
apt_get() { apt-get -o DPkg::Lock::Timeout=600 "$@"; }
for spec in "$@"; do
  pkg=${spec%%=*} ver=${spec#*=}
  if ! have=$(dpkg-query -W -f='${db:Status-Abbrev} ${Version}' "$pkg" 2> /dev/null) || [[ $have != [ih]i* ]]; then
    echo "$pkg: not installed here - left so (production runs $ver)"
    continue
  fi
  have=${have##* }
  if [ "$have" = "$ver" ]; then
    echo "$pkg: $ver, production's"
    continue
  fi
  if apt-cache madison "$pkg" | awk -F'|' -v v="$ver" '{gsub(/ /, "", $2)} $2 == v {f = 1} END {exit !f}'; then
    apt_get install -y -qq --allow-downgrades --no-install-recommends -o Dpkg::Options::=--force-confold "$pkg=$ver" > /dev/null
    echo "$pkg: $have -> $ver, from the archive"
    continue
  fi
  # snapshot.debian.org: where and when that version was first published (amd64: the VMs')
  enc=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$ver")
  info=$(curl -fsS --max-time 120 --retry 3 "$snapshot/mr/binary/$pkg/$enc/binfiles?fileinfo=1") \
    || { echo "$pkg $ver: not in the archive, and snapshot.debian.org did not answer for it"; exit 1; }
  read -r archive ts < <(python3 -c '
import json, sys
d = json.loads(sys.argv[1])
amd = [x for x in d.get("result", []) if x.get("architecture") in ("amd64", "all")]
seen = sorted((f["archive_name"], f["first_seen"]) for x in amd for f in d.get("fileinfo", {}).get(x["hash"], []))
sec = [s for s in seen if s[0] == "debian-security"]
pick = (sec or [s for s in seen if s[0] == "debian"] or [("-", "-")])[0]
print(*pick)' "$info") || true
  [[ ${archive:-} =~ ^debian(-security)?$ && ${ts:-} =~ ^[0-9]{8}T[0-9]{6}Z$ ]] \
    || { echo "$pkg $ver: neither in the archive nor on snapshot.debian.org for amd64"; exit 1; }
  if [ "$archive" = debian-security ]; then suites="trixie-security"; else suites="trixie trixie-updates trixie-proposed-updates"; fi
  list="$sources/copy-snapshot.list"
  for s in $suites; do echo "deb [check-valid-until=no] $snapshot/archive/$archive/$ts/ $s main"; done > "$list"
  trap 'rm -f "$list"' EXIT
  # that source's index only (the others' kept), then the install with it
  apt_get update -qq -o Dir::Etc::SourceList="$list" -o Dir::Etc::SourceParts=/nonexistent -o APT::Get::List-Cleanup=0
  apt_get install -y -qq --allow-downgrades --no-install-recommends -o Dpkg::Options::=--force-confold "$pkg=$ver" > /dev/null
  rm -f "$list"
  trap - EXIT
  apt_get update -qq  # the snapshot's index gone with its source
  echo "$pkg: $have -> $ver, from snapshot.debian.org ($archive $ts)"
done
