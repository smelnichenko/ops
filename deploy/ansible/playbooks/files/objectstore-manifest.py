#!/usr/bin/env python3
"""objectstore-manifest.py - what a versitygw posix store holds, and whether a copy of it holds the same.

The posix backend keeps each object as a file under <buckets>/<bucket>/<key> with its ETag in the user.etag extended
attribute, and each bucket's owner and ACL in the bucket directory's user.acl; uploads in flight live under
<bucket>/.sgwtmp. A copy without those attributes restores files no client may read.

  manifest <buckets dir>                         print {"buckets": [...], "objects": {"<bucket>/<key>": "<etag>"}}
  verify-tar <tar.gz> <before> <after> <out>     the archive (GNU tar --xattrs, entries ./buckets/...) against the
                                                 objects listed both before and after it was written with the same
                                                 ETag (an object only in one of them was written or deleted while
                                                 tar ran): each one in it with that ETag, a single-part one's content
                                                 its md5, every bucket of both lists with its ACL; the objects
                                                 checked are written to <out> - what a restore must give back
  verify-tree <buckets dir> <manifest>           a restored tree: every object of the manifest there with its ETag,
                                                 a single-part one's content its md5, every bucket with its ACL

Exit 1 with the differences named on any mismatch.
"""
import hashlib
import json
import os
import sys
import tarfile

SKIP = ".sgwtmp"


def etag_of(raw):
    return raw.decode() if isinstance(raw, bytes) else str(raw)


def bare(etag):
    return etag.strip().strip('"')


def md5_of(stream):
    h = hashlib.md5(usedforsecurity=False)  # S3's ETag of a single-part object, not a security use
    for chunk in iter(lambda: stream.read(1 << 20), b""):
        h.update(chunk)
    return h.hexdigest()


def manifest(root):
    """The live store's objects. One deleted while this walks is left out; one without an ETag is listed apart
    (noetag) - an upload not finished yet has none for a moment, but one without it in both lists verify-tar compares
    is a store whose objects this cannot check (another attribute name, a mount without user xattrs) and fails it."""
    buckets = sorted(b for b in os.listdir(root) if os.path.isdir(os.path.join(root, b)))
    objects, noetag, bad = {}, [], []
    for b in buckets:
        if "user.acl" not in os.listxattr(os.path.join(root, b)):
            bad.append(f"bucket {b}: no ACL")
        for dp, dns, fns in os.walk(os.path.join(root, b)):
            dns[:] = [d for d in dns if d != SKIP]
            for fn in fns:
                p = os.path.join(dp, fn)
                try:
                    objects[os.path.relpath(p, root)] = bare(etag_of(os.getxattr(p, "user.etag")))
                except FileNotFoundError:
                    pass
                except OSError:
                    noetag.append(os.path.relpath(p, root))
    return {"buckets": buckets, "objects": objects, "noetag": sorted(noetag)}, bad


def check_content(key, etag, stream, bad):
    if "-" in etag:  # a multipart ETag is not the md5 of the content
        return
    got = md5_of(stream)
    if got != etag:
        bad.append(f"{key}: ETag {etag}, content md5 {got}")


def archive_entries(archive, want, bad):
    """Stream the archive once: the buckets whose directory carries its ACL, and the wanted objects found (each one's
    ETag compared, a single-part one's content md5'd as it streams)."""
    seen, acl = set(), set()
    with tarfile.open(archive, "r|gz") as t:
        for m in t:
            name = m.name[2:] if m.name.startswith("./") else m.name
            rel = name[len("buckets/"):] if name.startswith("buckets/") else ""
            if m.isdir() and rel and "/" not in rel and "SCHILY.xattr.user.acl" in m.pax_headers:
                acl.add(rel)
            elif m.isfile() and rel in want:
                etag = bare(m.pax_headers.get("SCHILY.xattr.user.etag", ""))
                if etag != want[rel]:
                    bad.append(f"{rel}: ETag in the archive {etag or 'none'}, in the store {want[rel]}")
                else:
                    check_content(rel, etag, t.extractfile(m), bad)
                seen.add(rel)
    return seen, acl


def verify_tar(archive, before_path, after_path, out_path):
    before, after = (json.load(open(p)) for p in (before_path, after_path))
    want = {k: v for k, v in before["objects"].items() if after["objects"].get(k) == v}
    buckets = set(before["buckets"]) & set(after["buckets"])
    bad = [f"{k}: no ETag in the store (before and after the archive)"
           for k in sorted(set(before.get("noetag", [])) & set(after.get("noetag", [])))]
    # nothing to compare is no proof; and the store does not lose a tenth of its objects in the minutes tar runs
    if not want:
        bad.append(f"no object to check ({len(before['objects'])} before, {len(after['objects'])} after)")
    elif len(want) < 0.9 * len(before["objects"]):
        bad.append(f"only {len(want)} of {len(before['objects'])} objects unchanged while tar ran - run it again")
    seen, acl = archive_entries(archive, want, bad)
    bad += [f"{k}: not in the archive" for k in sorted(set(want) - seen)]
    bad += [f"bucket {b}: no ACL in the archive" for b in sorted(buckets - acl)]
    json.dump({"buckets": sorted(buckets), "objects": want}, open(out_path, "w"), sort_keys=True)
    return f"{len(want)} objects in {len(buckets)} buckets in the archive with their ETags and ACLs", bad


def verify_tree(root, manifest_path):
    m = json.load(open(manifest_path))
    bad = [] if m["objects"] else ["the backup's list holds no object - nothing proven"]
    for b in m["buckets"]:
        d = os.path.join(root, b)
        if not os.path.isdir(d) or "user.acl" not in os.listxattr(d):
            bad.append(f"bucket {b}: missing or no ACL")
    for key, etag in sorted(m["objects"].items()):
        p = os.path.join(root, key)
        try:
            got = bare(etag_of(os.getxattr(p, "user.etag")))
        except OSError:
            bad.append(f"{key}: missing or no ETag")
            continue
        if got != etag:
            bad.append(f"{key}: ETag {got}, the backup's {etag}")
            continue
        with open(p, "rb") as f:
            check_content(key, etag, f, bad)
    return f"{len(m['objects'])} objects in {len(m['buckets'])} buckets restored with their ETags and ACLs", bad


def main():
    mode, args = sys.argv[1], sys.argv[2:]
    if mode == "manifest":
        out, bad = manifest(args[0])
        if bad or not out["buckets"]:
            print("\n".join(bad[:50]) or "no bucket", file=sys.stderr)
            sys.exit(1)
        json.dump(out, sys.stdout, sort_keys=True)
        return
    summary, bad = verify_tar(*args) if mode == "verify-tar" else verify_tree(*args)
    if bad:
        print("\n".join(bad[:50]))
        sys.exit(1)
    print(summary)


if __name__ == "__main__":
    main()
