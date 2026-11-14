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
#     trixie-security, or debian's trixie, trixie-updates, trixie-proposed-updates and sid - a version that reached
#     trixie from unstable was first published there), the snapshot's source added for the install only, signed by
#     Debian's archive keyring and pinned low (100): the versions asked for come from it, what they depend on from the
#     archive as before (sid's never a candidate) - a version snapshot does not have fails the run, named.
# Every installed package built from the same source at the same version moves with it (postgresql-17 with
# postgresql-client-17 and libpq5, glusterfs-server with glusterfs-common and -client): production runs them together.
# Downgrades allowed (that is the point), removals never (a dependent package removed would be a copy production is
# not); the services restart on the new binaries at the copy's cold boot after it.
#
# Usage: scripts/pi-apt-pin.sh <package>=<version>...
# Env:   PI_APT_SOURCES_DIR (default /etc/apt/sources.list.d), PI_APT_PREFS_DIR (default /etc/apt/preferences.d),
#        PI_APT_SNAPSHOT (default https://snapshot.debian.org) - tests
set -euo pipefail
# ranges as ASCII: under a UTF-8 locale bash's [A-Za-z] takes an accented letter too (usér passed the users check)
export LC_ALL=C
sources=${PI_APT_SOURCES_DIR:-/etc/apt/sources.list.d}
snapshot=${PI_APT_SNAPSHOT:-https://snapshot.debian.org}
list="$sources/copy-snapshot.list"
prefs="${PI_APT_PREFS_DIR:-/etc/apt/preferences.d}/copy-snapshot"
keyring=/usr/share/keyrings/debian-archive-keyring.gpg
export DEBIAN_FRONTEND=noninteractive
[ $# -gt 0 ] || { echo "usage: $0 <package>=<version>..."; exit 2; }
for spec in "$@"; do
  [[ $spec =~ ^[a-z0-9][a-z0-9.+-]*=([0-9]+:)?[0-9][0-9A-Za-z.+~-]*$ ]] || { echo "not <package>=<version>: '$spec'"; exit 2; }
done
apt_get() { apt-get -o DPkg::Lock::Timeout=600 "$@"; }
install() { apt_get install -y -qq --allow-downgrades --no-remove --no-install-recommends -o Dpkg::Options::=--force-confold "$@" > /dev/null; }
# a run killed half-way (its trap never ran) left its snapshot source: gone first, or the archive check below would
# read the snapshot's versions as the archive's
if [ -e "$list" ] || [ -e "$prefs" ]; then
  rm -f "$list" "$prefs"
  apt_get update -qq
fi
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
  # the packages built with it: same source, same version installed
  src=$(dpkg-query -W -f='${source:Package}' "$pkg")
  specs=("$pkg=$ver")
  while IFS='|' read -r st p s v; do
    [[ $st == [ih]i* && $s == "$src" && $v == "$have" && $p != "$pkg" ]] && specs+=("$p=$ver")
  done < <(dpkg-query -W -f='${db:Status-Abbrev}|${Package}|${source:Package}|${Version}\n')
  with=""
  [ "${#specs[@]}" -eq 1 ] || with=" (with ${specs[*]:1})"
  if apt-cache madison "$pkg" | awk -F'|' -v v="$ver" '{gsub(/ /, "", $2)} $2 == v {f = 1} END {exit !f}'; then
    install "${specs[@]}"
    echo "$pkg: $have -> $ver, from the archive$with"
    continue
  fi
  # snapshot.debian.org: where and when that version was first published (amd64: the VMs')
  enc=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$ver")
  info=$(curl -fsS --max-time 120 --retry 3 "$snapshot/mr/binary/$pkg/$enc/binfiles?fileinfo=1") \
    || { echo "$pkg $ver: not in the archive, and snapshot.debian.org did not answer for it"; exit 1; }
  pick=$(python3 -c '
import json, sys
d = json.loads(sys.argv[1])
amd = [x for x in d.get("result", []) if x.get("architecture") in ("amd64", "all")]
seen = sorted((f["archive_name"], f["first_seen"]) for x in amd for f in d.get("fileinfo", {}).get(x["hash"], []))
sec = [s for s in seen if s[0] == "debian-security"]
pick = (sec or [s for s in seen if s[0] == "debian"] or [("-", "-")])[0]
print(*pick)' "$info") || { echo "$pkg $ver: snapshot.debian.org's answer not read (not the JSON expected)"; exit 1; }
  read -r archive ts <<< "$pick"
  [[ $archive =~ ^debian(-security)?$ && $ts =~ ^[0-9]{8}T[0-9]{6}Z$ ]] \
    || { echo "$pkg $ver: neither in the archive nor on snapshot.debian.org for amd64"; exit 1; }
  if [ "$archive" = debian-security ]; then suites="trixie-security"; else suites="trixie trixie-updates trixie-proposed-updates sid"; fi
  trap 'rm -f "$list" "$prefs"' EXIT  # before the files exist: no way out leaves them
  printf 'Package: *\nPin: origin %s\nPin-Priority: 100\n' "${snapshot#*://}" > "$prefs"
  for s in $suites; do echo "deb [check-valid-until=no signed-by=$keyring] $snapshot/archive/$archive/$ts/ $s main"; done > "$list"
  # that source's index only (the others' kept), then the install with it
  apt_get update -qq -o Dir::Etc::SourceList="$list" -o Dir::Etc::SourceParts=/nonexistent -o APT::Get::List-Cleanup=0
  install "${specs[@]}"
  rm -f "$list" "$prefs"
  trap - EXIT
  apt_get update -qq  # the snapshot's index gone with its source
  echo "$pkg: $have -> $ver, from snapshot.debian.org ($archive $ts)$with"
done
