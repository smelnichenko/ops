#!/bin/bash
# scripts/copy-change-inventory.sh: the copy's inventory after a change, judged from the build - what the change moved
# (different from production after it, not at the build) printed and passed, alone even where the build's copy was
# stale in another line it mends; a difference the build had too failing (production moved since), named apart; what
# the checks changed after the change settled failing (a leftover); a comparison with no verdict (inventory-diff.sh
# crashed) failing, never "nothing moved"; any inventory missing refused; inventory-diff.sh's own rules (apps' images,
# allowed-missing) holding on each side.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
S=scripts/copy-change-inventory.sh
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi
}
printf '%s\n' 'image a/velero v1.18.4' 'image b/redis 8.1' 'argo-chart velero velero@12.2.0' 'image c/left-out v1' > "$W/prod"
printf '%s\n' 'image c/left-out v1' > "$W/allowed"
same() { grep -v 'c/left-out' "$W/prod"; }
same > "$W/build"
# the change moves Velero's image and chart; the checks change nothing
same | sed 's#v1.18.4#v1.19.0#; s#velero@12.2.0#velero@13.0.0#' > "$W/changed"
run() { out=$(bash "$S" "$@" 2>&1); }  # its output in $out, its exit its own
run "$W/prod" "$W/build" "$W/changed" "$W/changed" "$W/allowed"; rc=$?
check "a change's own differences: printed, passed, said" \
  "$rc $(grep -c '^  +image a/velero v1.19.0$' <<< "$out") $(grep -c '^  -image a/velero v1.18.4$' <<< "$out") $(grep -c "^INVENTORY: production's but for the change's own lines$" <<< "$out")" \
  "0 1 1 1"
check "  the allowed-missing line not reported" "$(grep -c 'left-out' <<< "$out")" 0
run "$W/prod" "$W/build" "$W/build" "$W/build" "$W/allowed"; rc=$?
check "no change in the inventory: said, passed" "$rc $(grep -c 'moved nothing' <<< "$out")" "0 1"
# production moved since the build: redis read at 8.0 then (the build matched it), 8.1 now
same | sed 's#redis 8.1#redis 8.0#' > "$W/stale"
same | sed 's#redis 8.1#redis 8.0#; s#v1.18.4#v1.19.0#' > "$W/stale-changed"
run "$W/prod" "$W/stale" "$W/stale-changed" "$W/stale-changed" "$W/allowed"; rc=$?
check "a difference the build had too: failed, named apart from the change's" \
  "$rc $(sed -n '/at its build too/,$p' <<< "$out" | grep -c 'redis 8.0') $(sed -n '/own differences/,/at its build too/p' <<< "$out" | grep -c 'velero v1.19.0') $(grep -c 'production moved since' <<< "$out")" \
  "1 1 1 1"
# the change mends the stale line and moves another: both its own, passed - the comparison's header lines no part of it
same | sed 's#v1.18.4#v1.19.0#' > "$W/mends"
run "$W/prod" "$W/stale" "$W/mends" "$W/mends" "$W/allowed"; rc=$?
check "a change that mends one stale line and moves another: its own alone, passed" \
  "$rc $(grep -c -e 'expected$' -e 'actual$' <<< "$out")" "0 0"
# a check's leftover: a Job image there after the checks, not right after the change
{ cat "$W/changed"; echo 'image d/kopia 0.16.0'; } > "$W/leftover"
run "$W/prod" "$W/build" "$W/changed" "$W/leftover" "$W/allowed"; rc=$?
check "a check's leftover (after the change settled): failed, named" \
  "$rc $(grep -c '^  +image d/kopia 0.16.0' <<< "$out") $(grep -c "a check's leftovers" <<< "$out")" "1 1 1"
# a comparison that gave no verdict: failed, never "nothing moved"
mkdir -p "$W/broken/scripts"; cp "$S" "$W/broken/scripts/"
printf '#!/bin/bash\nexit 3\n' > "$W/broken/scripts/inventory-diff.sh"; chmod +x "$W/broken/scripts/inventory-diff.sh"
out=$(bash "$W/broken/scripts/copy-change-inventory.sh" "$W/prod" "$W/build" "$W/build" "$W/build" 2>&1); rc=$?
check "inventory-diff.sh crashing (no verdict): failed, said - not 'moved nothing'" \
  "$rc $(grep -c 'gave no verdict' <<< "$out") $(grep -c 'moved nothing' <<< "$out")" "1 1 0"
for i in 1 2 3 4; do
  a=("$W/prod" "$W/build" "$W/changed" "$W/changed"); a[$((i - 1))]=$W/nothing
  run "${a[@]}"; rc=$?
  check "inventory $i of 4 missing: refused" "$rc $(grep -c 'no inventory' <<< "$out")" "1 1"
done
run "$W/prod" "$W/build" "$W/changed"; rc=$?
check "fewer than four inventories: usage (exit 2)" "$rc" 2
# the unit's moves (a sixth argument, upgrade-units.py moves): every production line of a package at its old version on
# the copy at the new one after the change - "moved nothing" passed a unit whose version never reached the copy (the
# observability review, 2026-11-25)
# the moves' names: the harness's own (the real file's read below)
printf '%s\n' '# a comment' 'ci/tool - the CI'"'"'s own image, outside production' > "$W/names"
export COPY_MOVES_NAMES=$W/names
printf '%s\n' 'a/velero v1.18.4 v1.19.0' 'velero 12.2.0 13.0.0' 'ci/tool 1.0 2.0' > "$W/moves"
run "$W/prod" "$W/build" "$W/changed" "$W/changed" "$W/allowed" "$W/moves"; rc=$?
check "the unit's moves on the copy after the change (image and chart; a CI tool named as checked elsewhere): passed" \
  "$rc $(grep -c -E 'NOT MOVED|NOT CHECKED' <<< "$out")" "0 0"
run "$W/prod" "$W/build" "$W/build" "$W/build" "$W/allowed" "$W/moves"; rc=$?
check "  the change moved nothing of them: failed, each line named" \
  "$rc $(grep -c "^  NOT MOVED a/velero v1.18.4 -> v1.19.0: the copy lacks 'image a/velero v1.19.0'$" <<< "$out") $(grep -c "NOT MOVED velero 12.2.0 -> 13.0.0: the copy lacks 'argo-chart velero velero@13.0.0'" <<< "$out") $(grep -c 'did not move what its unit moves' <<< "$out")" \
  "1 1 1 1"
printf '%s\n' 'c/left-out v1 v2' > "$W/moves-left"
run "$W/prod" "$W/build" "$W/build" "$W/build" "$W/allowed" "$W/moves-left"; rc=$?
check "  a line the allow-list lets the copy lack (by version too): not required" "$rc" 0
printf '%s\n' 'image b/redis 8.1' 'image c/left-out *' > "$W/allowed-any"
run "$W/prod" "$W/build" "$W/build" "$W/build" "$W/allowed-any" "$W/moves-left"; rc=$?
check "  allowed by ' *' (any version): not required" "$rc" 0
printf '%s\n' 'velero 2.0 3.0' > "$W/moves-part"
run "$W/prod" "$W/build" "$W/build" "$W/build" "$W/allowed" "$W/moves-part"; rc=$?
check "  a version inside a longer one (2.0 in 12.2.0) never matched" "$rc" 0
run "$W/prod" "$W/build" "$W/changed" "$W/changed" "$W/allowed" "$W/none"; rc=$?
check "  the moves file not readable: refused" "$rc $(grep -c 'not readable' <<< "$out")" "1 1"
# a line carrying the version twice (a chart named for its version, its app version the same - Cilium's): moved in
# any of its places is moved - both (the chart and its app), or the chart alone; in none - named with both moved (the
# first place alone was required, 2026-11-27: wave-patches' try 3 failed with Cilium on 1.20.5 in both)
printf '%s\n' 'helm kube-system/cilium cilium-1.20.4 1.20.4' 'image b/redis 8.1' > "$W/prod2"
printf '%s\n' 'cilium 1.20.4 1.20.5' > "$W/moves2"
printf '%s\n' 'helm kube-system/cilium cilium-1.20.5 1.20.5' 'image b/redis 8.1' > "$W/both"
printf '%s\n' 'helm kube-system/cilium cilium-1.20.5 1.20.4' 'image b/redis 8.1' > "$W/chart"
run "$W/prod2" "$W/prod2" "$W/both" "$W/both" /dev/null "$W/moves2"; rc_both=$?
run "$W/prod2" "$W/prod2" "$W/chart" "$W/chart" /dev/null "$W/moves2"; rc_chart=$?
run "$W/prod2" "$W/prod2" "$W/prod2" "$W/prod2" /dev/null "$W/moves2"; rc_none=$?
check "a version in two places of a line: moved in both - passed; the chart alone - passed; in none - failed, named with both moved" \
  "$rc_both $rc_chart $rc_none $(grep -c "^  NOT MOVED cilium 1.20.4 -> 1.20.5: the copy lacks 'helm kube-system/cilium cilium-1.20.5 1.20.5'$" <<< "$out")" \
  "0 0 1 1"

# a move production names nowhere: refused unless moves-names.txt names it (the wave-patches review, 2026-11-27:
# forgejo/forgejo, prom/node-exporter and renovate/renovate required nothing)
printf '%s\n' 'x/unnamed 1.0 2.0' > "$W/moves-unnamed"
run "$W/prod" "$W/build" "$W/changed" "$W/changed" "$W/allowed" "$W/moves-unnamed"; rc=$?
check "a move no production line names, at any version, and no entry for it: failed, said" \
  "$rc $(grep -c '^  NOT CHECKED x/unnamed 1.0 -> 2.0: no production line names it' <<< "$out")" "1 1"
printf '%s\n' 'b/redis 7.0 8.2' > "$W/moves-other"
run "$W/prod" "$W/build" "$W/changed" "$W/changed" "$W/allowed" "$W/moves-other"; rc=$?
check "  a package production names only at another version (a hook Job's image no pod runs at the old one): nothing to move, passed" \
  "$rc $(grep -c -E 'NOT MOVED|NOT CHECKED' <<< "$out")" "0 0"
# named another way: its lines checked too (a Pi's service under its own name)
printf '%s\n' 'pi pi1 svc 1.0' > "$W/prod-pi"; printf '%s\n' 'pi pi1 svc 2.0' > "$W/copy-pi"
printf '%s\n' 'org/svc = ^pi \S+ svc ' > "$W/names-pi"
printf '%s\n' 'org/svc 1.0 2.0' > "$W/moves-pi"
COPY_MOVES_NAMES=$W/names-pi run "$W/prod-pi" "$W/prod-pi" "$W/copy-pi" "$W/copy-pi" /dev/null "$W/moves-pi"; rc_moved=$?
COPY_MOVES_NAMES=$W/names-pi run "$W/prod-pi" "$W/prod-pi" "$W/prod-pi" "$W/prod-pi" /dev/null "$W/moves-pi"; rc_stayed=$?
COPY_MOVES_NAMES=$W/names run "$W/prod-pi" "$W/prod-pi" "$W/prod-pi" "$W/prod-pi" /dev/null "$W/moves-pi"; rc_unnamed=$?
check "  named another way (org/svc = ^pi \\S+ svc): moved on the copy - passed; not moved - failed; without the entry - not checked, failed" \
  "$rc_moved $rc_stayed $rc_unnamed $(grep -c 'NOT CHECKED org/svc' <<< "$out")" "0 1 1 1"
printf '%s\n' 'org/svc: ^pi svc' > "$W/names-bad"
COPY_MOVES_NAMES=$W/names-bad run "$W/prod-pi" "$W/prod-pi" "$W/copy-pi" "$W/copy-pi" /dev/null "$W/moves-pi"; rc=$?
check "  an entry of another shape: refused, said (a typo would pass a move unchecked)" "$rc $(grep -c 'UNREAD tests/ansible/copy/moves-names.txt' <<< "$out")" "1 1"
COPY_MOVES_NAMES=$W/missing run "$W/prod" "$W/build" "$W/changed" "$W/changed" "$W/allowed" "$W/moves"; rc=$?
check "  the names file not readable: refused" "$rc $(grep -c 'moves. names not readable' <<< "$out")" "1 1"
unset COPY_MOVES_NAMES
# the real file: every entry read; forgejo's lines named, node_exporter's and Renovate's image checked elsewhere
printf '%s\n' 'pi pi1 forgejo 15.0.11' 'pi pi2 forgejo 15.0.11' > "$W/prod-real"; sed 's/15.0.11/15.0.12/' "$W/prod-real" > "$W/copy-real"
printf '%s\n' 'forgejo/forgejo 15.0.11 15.0.12' 'prom/node-exporter 1.12.1 1.13.1' 'renovate/renovate 44.198.3 44.264.1' > "$W/moves-real"
run "$W/prod-real" "$W/prod-real" "$W/copy-real" "$W/copy-real" /dev/null "$W/moves-real"; rc_real=$?
run "$W/prod-real" "$W/prod-real" "$W/prod-real" "$W/prod-real" /dev/null "$W/moves-real"; rc_real_stayed=$?
check "  tests/ansible/copy/moves-names.txt itself: read whole; forgejo moved on both Pis - passed, not moved - failed" \
  "$rc_real $rc_real_stayed $(grep -c 'UNREAD' <<< "$out")" "0 1 0"

# digest moves (Renovate's digest rows): judged on the image-digest lines; a version move's digest line - the new
# version's at any digest (its pin moves with it)
digest_case() {  # name, want rc, moves, the copy's lines after the change (beside production's others), [allowed]
  printf '%s\n' 'image ghcr.io/cloudnative-pg/postgresql 18.7-standard-trixie' \
    'image-digest ghcr.io/cloudnative-pg/postgresql 18.7-standard-trixie b4bbd2e' 'image opensearchproject/opensearch 3.9.0' \
    'image-digest opensearchproject/opensearch 3.9.0 3b55f6b' 'pkg kubelet 1.34.6-1.1' > "$W/dp"
  printf '%s\n' "$3" > "$W/dm"
  { grep -v -E 'cloudnative-pg/postgresql|opensearch' "$W/dp"; printf '%s\n' "$4"; } | LC_ALL=C sort > "$W/da"
  printf '%s\n' "${5:-}" > "$W/dal"
  printf '%s\n' "${DIGEST_NAMES:-}" > "$W/dn"
  printf '%s\n' "${EXTRA_PROD:-}" | grep . >> "$W/dp"
  out=$(COPY_MOVES_NAMES="$W/dn" scripts/copy-change-inventory.sh "$W/dp" "$W/dp" "$W/da" "$W/da" "$W/dal" "$W/dm" 2>&1); rc=$?
  if [ "$rc" = "$2" ] && { [ -z "${WANT_OUT:-}" ] || grep -qF -- "$WANT_OUT" <<< "$out"; }; then echo "PASS $1"
  else echo "FAIL $1 (rc $rc, want $2)"; sed 's/^/    /' <<< "$out"; fails=$((fails + 1)); fi
}
PG='image ghcr.io/cloudnative-pg/postgresql 18.7-standard-trixie'
OS='image opensearchproject/opensearch 3.9.0
image-digest opensearchproject/opensearch 3.9.0 3b55f6b'
digest_case "a digest move on the copy: passes" 0 'ghcr.io/cloudnative-pg/postgresql b4bbd2e c437b7c digest' "$PG
image-digest ghcr.io/cloudnative-pg/postgresql 18.7-standard-trixie c437b7c
$OS"
digest_case "  the old digest still on the copy: fails (NOT MOVED)" 1 'ghcr.io/cloudnative-pg/postgresql b4bbd2e c437b7c digest' "$PG
image-digest ghcr.io/cloudnative-pg/postgresql 18.7-standard-trixie b4bbd2e
$OS"
digest_case "  another digest than the move's: fails" 1 'ghcr.io/cloudnative-pg/postgresql b4bbd2e c437b7c digest' "$PG
image-digest ghcr.io/cloudnative-pg/postgresql 18.7-standard-trixie 0000000
$OS"
PGD='image-digest ghcr.io/cloudnative-pg/postgresql 18.7-standard-trixie b4bbd2e'
digest_case "a version move: the new version's tag line and its digest line at any digest - passes" 0 'opensearchproject/opensearch 3.9.0 3.10.0' "$PG
$PGD
image opensearchproject/opensearch 3.10.0
image-digest opensearchproject/opensearch 3.10.0 3bf4fe2"
digest_case "  the new version's digest line missing: fails" 1 'opensearchproject/opensearch 3.9.0 3.10.0' "$PG
$PGD
image opensearchproject/opensearch 3.10.0"
digest_case "  the old version's digest line left (the tag moved, the pin not): fails" 1 'opensearchproject/opensearch 3.9.0 3.10.0' "$PG
$PGD
image opensearchproject/opensearch 3.10.0
image-digest opensearchproject/opensearch 3.9.0 3bf4fe2"
digest_case "  a left-out image (allowed by name) moved: its digest line left out with it - passes" 0 'opensearchproject/opensearch 3.9.0 3.10.0' "$PG
$PGD" 'image opensearchproject/opensearch *'
# a digest move of an image production runs only unpinned (an ops pin - the Pi restore check's etcd): nothing here can
# check it - refused unless moves-names.txt names its digest moves (<package>@digest), which leaves its version moves judged
ETCD='image registry.k8s.io/etcd 3.6.8-0'
WANT_OUT="NOT CHECKED registry.k8s.io/etcd 3971894 -> 4444444: production runs no image of it pinned by digest" \
  EXTRA_PROD="$ETCD" digest_case "a digest move production runs no pinned image of: NOT CHECKED - fails" 1 'registry.k8s.io/etcd 3971894 4444444 digest' "$PG
$PGD
$OS
$ETCD"
DIGEST_NAMES='registry.k8s.io/etcd@digest - checked elsewhere' EXTRA_PROD="$ETCD" \
  digest_case "  named in moves-names.txt (@digest): passes" 0 'registry.k8s.io/etcd 3971894 4444444 digest' "$PG
$PGD
$OS
$ETCD"
DIGEST_NAMES='registry.k8s.io/etcd@digest - checked elsewhere' EXTRA_PROD="$ETCD" \
  digest_case "  an @digest entry leaves the version moves judged: its tag not moved - fails" 1 'registry.k8s.io/etcd 3.6.8-0 3.6.9-0' "$PG
$PGD
$OS
$ETCD"
EXTRA_PROD='image-digest example.io/opensearchproject/opensearch-dashboards 3.9.0 3b55f6b' \
  digest_case "  an image named only like it (another name ending in it) is no pinned line of it" 0 'opensearchproject/opensearch 3b55f6b 3bf4fe2 digest' "$PG
$PGD
image opensearchproject/opensearch 3.9.0
image-digest opensearchproject/opensearch 3.9.0 3bf4fe2
image-digest example.io/opensearchproject/opensearch-dashboards 3.9.0 3b55f6b"
# a version of seven digits is a version (only a marked line is a digest move); a digest move unmarked is no digest move
EXTRA_PROD='image example.io/tool 2026112' \
  digest_case "a version of seven digits, unmarked: judged as a version - its line moved, passes" 0 'example.io/tool 2026112 2026113' "$PG
$PGD
$OS
image example.io/tool 2026113"
echo "copy-change-inventory: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
