#!/bin/bash
# objectstore-manifest.py on a synthetic versitygw posix store (ETags and ACLs in user.* extended attributes, versitygw
# 1.8's .vgwlocks beside the buckets): a good archive and its restore pass; an archive missing an object, one without the attributes, an object whose content is
# not its ETag, a restore without the attributes or without a bucket - each fails, naming it.
set -u
M=$(cd "$(dirname "$0")/../../../../deploy/ansible/playbooks/files" && pwd)/objectstore-manifest.py
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$T" || exit 1
fails=0
expect() {  # expect <pass|fail> <name> <pattern the output must hold> <command...>
  want=$1 name=$2 pattern=$3; shift 3
  out=$("$@" 2>&1); rc=$?
  if { [ "$want" = pass ] && [ $rc = 0 ]; } || { [ "$want" = fail ] && [ $rc != 0 ]; }; then
    if grep -q -- "$pattern" <<< "$out"; then echo "ok    $name"; return; fi
  fi
  echo "FAIL  $name (rc=$rc): $out"; fails=$((fails + 1))
}
python3 - <<'PY'
import hashlib, os
os.makedirs("store/buckets/b1/k/.sgwtmp"); os.makedirs("store/buckets/b2")
for b in ("b1", "b2"):
    os.setxattr(f"store/buckets/{b}", "user.acl", b'{"Owner":"x"}')
for i in (1, 2, 3):
    p = f"store/buckets/b1/k/o{i}"
    open(p, "w").write(f"obj {i}\n")
    os.setxattr(p, "user.etag", ('"%s"' % hashlib.md5(open(p, "rb").read(), usedforsecurity=False).hexdigest()).encode())
open("store/buckets/b2/multi", "w").write("mp\n"); os.setxattr("store/buckets/b2/multi", "user.etag", b'"abc-2"')
open("store/buckets/b1/k/.sgwtmp/t", "w").write("in flight\n")
# versitygw 1.8's lock directory beside the buckets - no bucket (no S3 bucket name starts with a dot), no ACL
os.makedirs("store/buckets/.vgwlocks/1fb50d05/ab")
open("store/buckets/.vgwlocks/1fb50d05/ab/lock", "w").write("")
PY
X=(--xattrs --xattrs-include='user.*')
python3 "$M" manifest store/buckets > before.json
tar "${X[@]}" -C store -czf good.tgz .
python3 "$M" manifest store/buckets > after.json
expect pass "good archive" "4 objects in 2 buckets" python3 "$M" verify-tar good.tgz before.json after.json out.json
tar "${X[@]}" -C store --exclude=./buckets/b1/k/o2 -czf missing.tgz .
expect fail "archive missing an object" "b1/k/o2: not in the archive" python3 "$M" verify-tar missing.tgz before.json after.json x.json
tar -C store -czf plain.tgz .
expect fail "archive without the attributes" "ETag in the archive none" python3 "$M" verify-tar plain.tgz before.json after.json x.json
echo changed > store/buckets/b1/k/o3
tar "${X[@]}" -C store -czf content.tgz .
expect fail "content not its ETag" "b1/k/o3: ETag" python3 "$M" verify-tar content.tgz before.json after.json x.json
mkdir r1 r2
tar "${X[@]}" -C r1 -xzf good.tgz; tar -C r2 -xzf good.tgz
expect pass "restore" "4 objects in 2 buckets restored" python3 "$M" verify-tree r1/buckets out.json
expect fail "restore without the attributes" "bucket b1: missing or no ACL" python3 "$M" verify-tree r2/buckets out.json
rm -rf r1/buckets/b2
expect fail "restore without a bucket" "b2/multi: missing or no ETag" python3 "$M" verify-tree r1/buckets out.json
# a store whose ETags are under another attribute name: listed apart, and the archive check fails on it, not "0 objects"
python3 - <<'PY'
import os
os.makedirs("other/buckets/b1"); os.setxattr("other/buckets/b1", "user.acl", b'{"Owner":"x"}')
open("other/buckets/b1/o1", "w").write("x\n"); os.setxattr("other/buckets/b1/o1", "user.md5", b'"abc"')
PY
python3 "$M" manifest other/buckets > o-before.json
tar "${X[@]}" -C other -czf other.tgz .
python3 "$M" manifest other/buckets > o-after.json
expect fail "objects without an ETag" "b1/o1: no ETag in the store" python3 "$M" verify-tar other.tgz o-before.json o-after.json x.json
expect fail "nothing to check" "no object to check" python3 "$M" verify-tar other.tgz o-before.json o-after.json x.json
echo '{"buckets": ["b1"], "objects": {}}' > empty.json
expect fail "an empty list proves nothing" "holds no object" python3 "$M" verify-tree r2/buckets empty.json
[ "$fails" = 0 ] && echo "objectstore-manifest: ALL-PASS" || { echo "objectstore-manifest: $fails failed"; exit 1; }
