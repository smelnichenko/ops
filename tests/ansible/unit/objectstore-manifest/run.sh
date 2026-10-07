#!/bin/bash
# objectstore-manifest.py on a synthetic versitygw posix store (ETags and ACLs in user.* extended attributes, versitygw
# 1.8's .vgwlocks beside the buckets): a good archive and its restore pass; an archive missing an object, one without
# the attributes or without a bucket's ACL, an object whose content is not its ETag, a restore without the attributes,
# without a bucket or with an object's content changed - each fails, naming it. Only the objects the same before and
# after the archive are checked (one written while tar ran is left out), and not when a tenth of them changed; a store
# with a bucket that has no ACL gives no manifest.
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
# an archive with the ETags but no bucket ACL
tar --xattrs --xattrs-include='user.etag' -C store -czf noacl.tgz .
expect fail "archive without a bucket's ACL" "bucket b1: no ACL in the archive" python3 "$M" verify-tar noacl.tgz before.json after.json x.json
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
# a restored object whose content is not its ETag (the attribute kept)
mkdir r3; tar "${X[@]}" -C r3 -xzf good.tgz
echo tampered > r3/buckets/b1/k/o1
expect fail "restore with an object's content changed" "b1/k/o1: ETag .*content md5" python3 "$M" verify-tree r3/buckets out.json
# a store with a bucket without its ACL gives no manifest
python3 - <<'PY'
import os
os.makedirs("bare/buckets/b1"); os.makedirs("bare/buckets/b2"); os.setxattr("bare/buckets/b1", "user.acl", b'{"Owner":"x"}')
PY
expect fail "a bucket without its ACL in the store" "bucket b2: no ACL" python3 "$M" manifest bare/buckets
# objects written while tar ran: 20 single-part objects, the archive taken after one (or two of ten) changed - the
# changed ones are in the archive at their new ETag, which neither list agrees on
python3 - <<'PY'
import hashlib, os
for store, n in (("w20", 20), ("w10", 10)):
    os.makedirs(f"{store}/buckets/b1"); os.setxattr(f"{store}/buckets/b1", "user.acl", b'{"Owner":"x"}')
    for i in range(n):
        p = f"{store}/buckets/b1/o{i}"
        open(p, "w").write(f"obj {i}\n")
        os.setxattr(p, "user.etag", ('"%s"' % hashlib.md5(open(p, "rb").read(), usedforsecurity=False).hexdigest()).encode())
PY
rewrite() {  # rewrite <file>: new content, its ETag with it
  python3 -c 'import hashlib, os, sys
p = sys.argv[1]; open(p, "w").write("rewritten\n")
os.setxattr(p, "user.etag", ("\"%s\"" % hashlib.md5(open(p, "rb").read(), usedforsecurity=False).hexdigest()).encode())' "$1"
}
python3 "$M" manifest w20/buckets > w20-before.json
rewrite w20/buckets/b1/o0
tar "${X[@]}" -C w20 -czf w20.tgz .
python3 "$M" manifest w20/buckets > w20-after.json
expect pass "an object written while tar ran is left out" "19 objects in 1 buckets" python3 "$M" verify-tar w20.tgz w20-before.json w20-after.json w20-out.json
python3 "$M" manifest w10/buckets > w10-before.json
rewrite w10/buckets/b1/o0; rewrite w10/buckets/b1/o1
tar "${X[@]}" -C w10 -czf w10.tgz .
python3 "$M" manifest w10/buckets > w10-after.json
expect fail "a fifth of the objects written while tar ran" "only 8 of 10 objects unchanged" python3 "$M" verify-tar w10.tgz w10-before.json w10-after.json x.json
# what the restore is judged against: only the objects unchanged while tar ran (o0 rewritten is not among them)
expect pass "the restore's list leaves out an object written while tar ran" "19 0" python3 -c '
import json; o = json.load(open("w20-out.json"))["objects"]; print(len(o), int("b1/o0" in o))'
# an upload in flight (no ETag yet) in the list before the archive only: nothing wrong
python3 -c 'import json; m = json.load(open("before.json")); m["noetag"] = ["b1/k/new"]; json.dump(m, open("inflight.json", "w"))'
expect pass "an upload in flight before the archive only" "4 objects in 2 buckets" python3 "$M" verify-tar good.tgz inflight.json after.json x.json
# a bucket made while tar ran (in the list after it only) is not wanted in the archive
python3 -c 'import json; m = json.load(open("after.json")); m["buckets"].append("b3"); json.dump(m, open("after-b3.json", "w"))'
expect pass "a bucket made while tar ran" "4 objects in 2 buckets" python3 "$M" verify-tar good.tgz before.json after-b3.json x.json
# a restored multipart object (its content not checked) whose ETag changed
mkdir r4; tar "${X[@]}" -C r4 -xzf good.tgz
python3 -c 'import os; os.setxattr("r4/buckets/b2/multi", "user.etag", b"\"zzz-2\"")'
expect fail "a restored object's ETag changed" "b2/multi: ETag zzz-2" python3 "$M" verify-tree r4/buckets out.json
# a store with no bucket at all gives no manifest
mkdir -p none/buckets
expect fail "a store with no bucket" "no bucket" python3 "$M" manifest none/buckets
[ "$fails" = 0 ] && echo "objectstore-manifest: ALL-PASS" || { echo "objectstore-manifest: $fails failed"; exit 1; }
