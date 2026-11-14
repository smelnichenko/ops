#!/bin/bash
# scripts/pi-apt-pin.sh - a Vagrant copy's Pi moves each installed Debian package to production's version - against
# dpkg-query, apt-cache, apt-get and curl stubs (snapshot.debian.org's answers in the shape its API gives):
#   - at production's version: nothing installed; not installed here (or only its config left): said, never installed;
#   - in the archive at exactly that version (deb13u30 is not deb13u3): installed from it, downgrades allowed, removals
#     never, the old config kept; the packages built with it (same source, same version installed) moved with it, one
#     of another version left;
#   - not there: from snapshot.debian.org at the version's first publication - debian-security's trixie-security first,
#     else debian's trixie, trixie-updates, trixie-proposed-updates and sid; an arch-independent file counts; signed by
#     Debian's archive keyring, pinned low (100) while installing; that source's index alone updated, the install with
#     it (the same flags), the source and its pin gone after and the index updated without it; an epoch's colon encoded;
#     the API asked with a time bound and retries;
#   - a version snapshot does not have, an answer that is no JSON, snapshot not answering, the install failing: the run
#     fails, named, no snapshot source or pin left behind; one a killed run left is cleared first; a malformed argument
#     refused before anything runs.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi
}
mkdir -p "$W/bin"
# dpkg-query: $S/installed holds "<pkg> <status> <version> [<source>]" lines (the source the package's own by default)
cat > "$W/bin/dpkg-query" <<'STUB_DPKG'
#!/bin/bash
fmt="" pkg=""
for a in "$@"; do case "$a" in -W) ;; -f=*) fmt=${a#-f=} ;; *) pkg=$a ;; esac; done
if [ -z "$pkg" ]; then  # every package: status|package|source|version
  while read -r p st v src; do echo "$st|$p|${src:-$p}|$v"; done < "$S/installed"
  exit 0
fi
l=$(grep "^$pkg " "$S/installed") || exit 1
set -- $l
case "$fmt" in '${source:Package}') echo -n "${4:-$1}" ;; *) echo -n "$2 $3" ;; esac
STUB_DPKG
# apt-cache madison: $S/archive holds "<pkg> <version>" lines - what the archive serves
cat > "$W/bin/apt-cache" <<'STUB_APTCACHE'
#!/bin/bash
grep "^$2 " "$S/archive" | while read -r p v; do echo " $p | $v | http://deb.debian.org/debian trixie/main amd64 Packages"; done
STUB_APTCACHE
# apt-get: logged with the snapshot list's and pin's content at the time; install fails when $S/install-fails exists
cat > "$W/bin/apt-get" <<'STUB_APTGET'
#!/bin/bash
echo "apt-get $* | list: $(cat "$PI_APT_SOURCES_DIR/copy-snapshot.list" 2> /dev/null | tr '\n' ';') | pin: $(cat "$PI_APT_PREFS_DIR/copy-snapshot" 2> /dev/null | tr '\n' ';')" >> "$S/log"
case " $* " in *" install "*) [ ! -e "$S/install-fails" ] || exit 100 ;; esac
exit 0
STUB_APTGET
# curl: its arguments logged; the answer from $S/snapshot.json, or a failure when there is none
cat > "$W/bin/curl" <<'STUB_CURL'
#!/bin/bash
echo "curl $*" >> "$S/log"
[ -e "$S/snapshot.json" ] || exit 22
cat "$S/snapshot.json"
STUB_CURL
chmod +x "$W/bin/"*
export PATH="$W/bin:$PATH" PI_APT_SNAPSHOT=https://snap.test
n=0
fresh() {  # fresh: a Pi of its own
  n=$((n + 1)); export S="$W/s$n" PI_APT_SOURCES_DIR="$W/s$n/sources" PI_APT_PREFS_DIR="$W/s$n/prefs"
  mkdir -p "$S/sources" "$S/prefs"; : > "$S/installed"; : > "$S/archive"; : > "$S/log"
}
pin() { out=$(bash scripts/pi-apt-pin.sh "$@" 2>&1); }
installs() { grep -c ' install ' "$S/log"; }
left() { ls "$S/sources" "$S/prefs" | grep -c copy-snapshot; }
snap_json() {  # snap_json [--arch A] <archive:first_seen>... - the API's answer for one file seen there (arm64's elsewhere:
  # an earlier debian-security file - read, it would win)
  local arch=amd64 fi="" a
  [ "$1" = --arch ] && { arch=$2; shift 2; }
  for a in "$@"; do fi+="${fi:+,}{\"archive_name\": \"${a%%:*}\", \"first_seen\": \"${a#*:}\", \"path\": \"/pool/main/x\"}"; done
  echo "{\"result\": [{\"architecture\": \"$arch\", \"hash\": \"h1\"}, {\"architecture\": \"arm64\", \"hash\": \"h2\"}],
         \"fileinfo\": {\"h1\": [$fi], \"h2\": [{\"archive_name\": \"debian-security\", \"first_seen\": \"20000101T000000Z\"}]}}"
}
FLAGS="install -y -qq --allow-downgrades --no-remove --no-install-recommends -o Dpkg::Options::=--force-confold"

fresh
echo "haproxy ii 3.0.11-1+deb13u3" > "$S/installed"
pin haproxy=3.0.11-1+deb13u3; rc=$?
check "at production's version: nothing installed, said" "$rc $(installs) $(grep -c "haproxy: 3.0.11-1+deb13u3, production's" <<< "$out")" "0 0 1"
fresh
pin postgresql-18=18.1-1; rc=$?
check "not installed here: left so, said - never installed by this" "$rc $(installs) $(grep -c 'postgresql-18: not installed here' <<< "$out")" "0 0 1"
fresh
echo "haproxy rc 3.0.11-1+deb13u4" > "$S/installed"
pin haproxy=3.0.11-1+deb13u3; rc=$?
check "  removed, its config left (rc): not installed" "$rc $(installs)" "0 0"
fresh
echo "pgbouncer ii 1.24.1-1+deb13u3" > "$S/installed"; printf 'pgbouncer 1.24.1-1+deb13u3\npgbouncer 1.24.1-1+deb13u2\n' > "$S/archive"
pin pgbouncer=1.24.1-1+deb13u2; rc=$?
check "in the archive at that version: installed from it - downgrades allowed, no removal, the config kept, the lock waited - no snapshot asked" \
  "$rc $(grep -cF -- "-o DPkg::Lock::Timeout=600 $FLAGS pgbouncer=1.24.1-1+deb13u2 " "$S/log") $(grep -c curl "$S/log") $(grep -c 'pgbouncer: 1.24.1-1+deb13u3 -> 1.24.1-1+deb13u2, from the archive$' <<< "$out")" "0 1 0 1"
# the packages built with it move with it: same source, same version installed; one of another version stays
fresh
printf '%s\n' "postgresql-17 ii 17.12-0+deb13u1" "postgresql-client-17 ii 17.12-0+deb13u1 postgresql-17" \
  "libpq5 ii 17.12-0+deb13u1 postgresql-17" "postgresql-doc-17 ii 17.10-0+deb13u1 postgresql-17" "curl ii 8.14.1-2 curl" > "$S/installed"
echo "postgresql-17 17.11-0+deb13u1" > "$S/archive"
pin postgresql-17=17.11-0+deb13u1; rc=$?
check "  with it, in the same install: postgresql-client-17 and libpq5 (its source's, at its version); not another version's, not another source's" \
  "$rc $(grep -cF "$FLAGS postgresql-17=17.11-0+deb13u1 postgresql-client-17=17.11-0+deb13u1 libpq5=17.11-0+deb13u1 |" "$S/log") $(grep -c 'with postgresql-client-17=17.11-0+deb13u1 libpq5=17.11-0+deb13u1)' <<< "$out")" "0 1 1"
fresh
echo "haproxy ii 3.0.11-1+deb13u31" > "$S/installed"; echo "haproxy 3.0.11-1+deb13u30" > "$S/archive"
snap_json debian-security:20260522T201551Z > "$S/snapshot.json"
pin haproxy=3.0.11-1+deb13u3; rc=$?
check "  the archive's version matched exactly (deb13u30 is not deb13u3): to snapshot.debian.org" "$rc $(grep -c 'from snapshot.debian.org' <<< "$out")" "0 1"
# not in the archive: snapshot, debian-security first
fresh
echo "haproxy ii 3.0.11-1+deb13u4" > "$S/installed"; echo "haproxy 3.0.11-1+deb13u4" > "$S/archive"
snap_json debian:20260523T031937Z debian-security:20260522T201551Z > "$S/snapshot.json"
pin haproxy=3.0.11-1+deb13u3; rc=$?
L="deb [check-valid-until=no signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] https://snap.test/archive/debian-security/20260522T201551Z/ trixie-security main;"
P="Package: *;Pin: origin snap.test;Pin-Priority: 100;"
check "not in the archive: snapshot's debian-security (trixie-security) at its first publication, the API asked for amd64's file with a time bound and retries" \
  "$rc $(grep -c 'curl -fsS --max-time 120 --retry 3 https://snap.test/mr/binary/haproxy/3.0.11-1%2Bdeb13u3/binfiles?fileinfo=1' "$S/log") $(grep -c "from snapshot.debian.org (debian-security 20260522T201551Z)" <<< "$out")" "0 1 1"
check "  that source's index alone updated, the install with it - signed by Debian's keyring, pinned at 100, the same flags - then the index updated without it, source and pin gone" \
  "$(grep -cF "update -qq -o Dir::Etc::SourceList=$S/sources/copy-snapshot.list -o Dir::Etc::SourceParts=/nonexistent -o APT::Get::List-Cleanup=0 | list: $L | pin: $P" "$S/log") $(grep -cF "$FLAGS haproxy=3.0.11-1+deb13u3 | list: $L | pin: $P" "$S/log") $(tail -1 "$S/log" | grep -c 'update -qq | list:  | pin: $') $(left)" "1 1 1 0"
fresh
echo "postgresql-17 ii 17.12-0+deb13u1" > "$S/installed"
snap_json debian:20260819T030017Z > "$S/snapshot.json"
pin postgresql-17=17.11-0+deb13u1; rc=$?
check "  debian only: its trixie, trixie-updates, trixie-proposed-updates and sid at that time (a version from unstable)" \
  "$rc $(grep -c 'install .*postgresql-17=17.11-0+deb13u1 | list: deb \[[^]]*\] https://snap.test/archive/debian/20260819T030017Z/ trixie main;deb .* trixie-updates main;deb .* trixie-proposed-updates main;deb .* sid main;' "$S/log")" "0 1"
fresh
echo "keepalived ii 1:2.3.4-1" > "$S/installed"
snap_json debian:20250412T151927Z > "$S/snapshot.json"
pin keepalived=1:2.3.3-1; rc=$?
check "  an epoch's colon encoded in the API's URL" "$rc $(grep -c 'https://snap.test/mr/binary/keepalived/1%3A2.3.3-1/binfiles' "$S/log")" "0 1"
fresh
echo "tzdata ii 2026a-1" > "$S/installed"
snap_json --arch all debian:20251020T080000Z > "$S/snapshot.json"
pin tzdata=2025b-1; rc=$?
check "  an arch-independent package (its file all, no amd64): found on snapshot" "$rc $(grep -c 'from snapshot.debian.org (debian 20251020T080000Z)' <<< "$out")" "0 1"
# failures
fresh
echo "haproxy ii 3.0.11-1+deb13u4" > "$S/installed"
echo '{"result": [], "fileinfo": {}}' > "$S/snapshot.json"
pin haproxy=3.0.11-1+deb13u3; rc=$?
check "a version snapshot does not have: the run fails, named, nothing installed" \
  "$rc $(grep -c 'haproxy 3.0.11-1+deb13u3: neither in the archive nor on snapshot.debian.org' <<< "$out") $(installs)" "1 1 0"
fresh
echo "haproxy ii 3.0.11-1+deb13u4" > "$S/installed"
echo '<html>rate limited</html>' > "$S/snapshot.json"
pin haproxy=3.0.11-1+deb13u3; rc=$?
check "snapshot answering what is no JSON: fails, said so (not 'neither in the archive')" \
  "$rc $(grep -c "snapshot.debian.org's answer not read" <<< "$out") $(installs)" "1 1 0"
fresh
echo "haproxy ii 3.0.11-1+deb13u4" > "$S/installed"
pin haproxy=3.0.11-1+deb13u3; rc=$?
check "snapshot not answering: fails, named" "$rc $(grep -c 'snapshot.debian.org did not answer' <<< "$out") $(installs)" "1 1 0"
fresh
echo "haproxy ii 3.0.11-1+deb13u4" > "$S/installed"; touch "$S/install-fails"
snap_json debian-security:20260522T201551Z > "$S/snapshot.json"
pin haproxy=3.0.11-1+deb13u3; rc=$?
check "the install failing: the run fails, no snapshot source or pin left behind" "$((rc != 0)) $(left)" "1 0"
fresh
echo "haproxy ii 3.0.11-1+deb13u3" > "$S/installed"
echo "deb https://snap.test/archive/debian/x/ trixie main" > "$S/sources/copy-snapshot.list"; echo "Pin-Priority: 100" > "$S/prefs/copy-snapshot"
pin haproxy=3.0.11-1+deb13u3; rc=$?
check "a killed run's snapshot source and pin: cleared first, the index updated without them" \
  "$rc $(left) $(head -1 "$S/log" | grep -c '^apt-get -o DPkg::Lock::Timeout=600 update -qq | list:  | pin: $')" "0 0 1"
fresh
echo "haproxy ii 3.0.11-1+deb13u3" > "$S/installed"
pin haproxy=3.0.11-1+deb13u3 'x;rm -rf /=1'; rc=$?
check "a malformed argument: refused (exit 2) before anything runs" "$rc $(grep -c "not <package>=<version>: 'x;rm -rf /=1'" <<< "$out") $(wc -l < "$S/log")" "2 1 0"
pin; rc=$?
check "  no argument: usage (exit 2)" "$rc" 2
echo "pi-apt-pin: $([ "$fails" -eq 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ "$fails" -eq 0 ]
