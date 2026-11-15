#!/usr/bin/env python3
"""Every pinned build hash read from what its vendor signs (the upgrade cycle's build-hash verification - its plan in
docs/plans, "Build hashes, verified").

A version Renovate moves takes its pinned hashes with it: this is the preset's post-upgrade task. Each pin's hashes for
the version in the tree are read from a checksum list the vendor signs, or from the artifact the vendor signs - gpg
checking the signature against the vendor's key, pinned by its primary fingerprint (renovate/keys/keys.json) - and
written where they differ. Vendors that sign nothing are read over TLS alone and say so.

Exit 1, the pin's file left as it was, on: a signature that does not check (an expired or revoked key's included), a
key not the pinned one, an artifact missing from the vendor's list, the vendor's own checksum file disagreeing with the
signed artifact or not naming it, a redirect off https. A vendor's newest signing key expiring within 60 days is warned
of by each run that reads it.
"""
import argparse
import hashlib
import json
import lzma
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

UA = "renovate-checksums (ops upgrade cycle)"
WARN_DAYS = 60


class Refused(Exception):
    pass


# each pin: its file, its version var, its shape - map (arch -> hash), single (one hash), versioned (version -> arch ->
# hash: a new version adds its entry, the ones before kept and each verified), wheels (a list of files, each with its
# sha256, no version var) - its key, the vendor that vouches. renovate: False - Renovate does not move it (why said):
# moved by hand, verified here all the same
PINS = [
    {"name": "vault", "file": "deploy/ansible/vars/vault.yml", "version": "vault_version", "shape": "map",
     "key": "vault_checksums", "arches": ["arm64", "amd64"], "vendor": "hashicorp", "product": "vault"},
    {"name": "forgejo", "file": "deploy/ansible/vars/forgejo.yml", "version": "forgejo_version", "shape": "map",
     "key": "forgejo_checksums", "arches": ["arm64", "amd64"], "vendor": "forgejo"},
    {"name": "helm", "file": "deploy/ansible/playbooks/setup-kubeadm.yml", "version": "helm_version", "shape": "single",
     "key": "helm_sha256", "arches": ["amd64"], "vendor": "helm", "renovate": False,
     "why": "a task's var behind creates: /usr/local/bin/helm - no host would take a new Helm, copy-unit proves none"},
    {"name": "node_exporter", "file": "deploy/ansible/playbooks/setup-host-hardening.yml",
     "version": "node_exporter_version", "shape": "single", "key": "node_exporter_sha256", "arches": ["amd64"],
     "vendor": "node_exporter"},
    {"name": "nexus", "file": "deploy/ansible/playbooks/setup-nexus.yml", "version": "nexus_version", "shape": "map",
     "key": "nexus_checksums", "arches": ["aarch_64", "x86_64"], "vendor": "nexus", "renovate": False,
     "why": "Sonatype's download names (3.90.1-01) are no registry's tags"},
    {"name": "versitygw", "file": "deploy/ansible/playbooks/tasks/versitygw.yml", "version": "vgw_version",
     "version_re": r"default\('([^']+)'\)", "shape": "versioned", "key": "vgw_checksums", "arches": ["amd64", "arm64"],
     "vendor": "versitygw", "renovate": False, "why": "its version is a set_fact's default, no annotated var"},
    {"name": "pytorch_cpu_wheels", "file": "deploy/ansible/playbooks/tasks/nexus-pytorch-cpu.yml", "shape": "wheels",
     "key": "pytorch_cpu_wheels", "vendor": "pytorch", "renovate": False,
     "why": "wheel files, no version var - kept in step with target-scorer's requirements/ci.txt"},
]

# where each vendor says its hashes ({v} version, {a} arch, {p} product, {f} wheel file, {project} its project):
#   list   a checksum list naming each artifact - sig: its detached signature (the vendor signs the list)
#   xz     the artifact, its sha256 file naming it, its .xz the vendor signs (.xz.asc): the .xz decompressed as it is
#          hashed - a third of the download, the binary never on disk
#   each   one sha256 file per artifact
#   index  a package index whose links carry #sha256=
VENDORS = {
    "hashicorp": {"list": "https://releases.hashicorp.com/{p}/{v}/{p}_{v}_SHA256SUMS", "sig": "{list}.sig",
                  "name": "{p}_{v}_linux_{a}.zip", "how": "signed: HashiCorp"},
    "helm": {"list": "https://get.helm.sh/helm-{v}-linux-{a}.tar.gz.sha256sum",
             "sig": "https://github.com/helm/helm/releases/download/{v}/helm-{v}-linux-{a}.tar.gz.sha256sum.asc",
             "name": "helm-{v}-linux-{a}.tar.gz", "how": "signed: Helm"},
    "forgejo": {"xz": "https://code.forgejo.org/forgejo/forgejo/releases/download/v{v}/forgejo-{v}-linux-{a}",
                "how": "signed: Forgejo"},
    "node_exporter": {"list": "https://github.com/prometheus/node_exporter/releases/download/v{v}/sha256sums.txt",
                      "name": "node_exporter-{v}.linux-{a}.tar.gz", "how": "TLS alone: Prometheus signs no release"},
    "versitygw": {"list": "https://github.com/versity/versitygw/releases/download/v{v}/checksums.txt",
                  "name": "versitygw_{v}_linux_{a}.deb", "how": "TLS alone: versitygw signs no release"},
    "nexus": {"each": "https://download.sonatype.com/nexus/3/nexus-{v}-linux-{a}.tar.gz.sha256",
              "how": "TLS alone: Sonatype signs no Nexus tarball"},
    "pytorch": {"index": "https://download.pytorch.org/whl/cpu/{project}/", "how": "TLS alone: PyTorch signs no wheel"},
}

HASH = re.compile(r"^[0-9a-f]{64}$")
# a pin's hash line: 'key: <hash>', 'key: "sha256:<hash>"', '- sha256: <hash>' - its hash alone is ever rewritten
VALUE = re.compile(r"^(?P<head>\s*(?:-\s+)?\S+:\s*\"?(?:sha256:)?)(?P<hash>[0-9a-f]{64})(?P<tail>.*)$", re.S)
DAY = "%Y-%m-%d"


class Fetcher:
    def __init__(self, mirror, work):
        self.mirror, self.work = mirror, work

    def path(self, url):
        """The URL's content in a file of its own (large binaries streamed, never held in memory)."""
        if not url.startswith("https://"):
            raise Refused(f"{url}: not https")
        name = os.path.join(self.work, hashlib.sha256(url.encode()).hexdigest()[:16] + "-" + url.rsplit("/", 1)[-1])
        if self.mirror:
            u = urllib.parse.urlsplit(url)
            src = os.path.join(self.mirror, u.netloc, u.path.lstrip("/") + ("index.html" if u.path.endswith("/") else ""))
            if not os.path.isfile(src):
                raise Refused(f"{url}: not found")
            shutil.copyfile(src, name)
            return name
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=300) as r, open(name, "wb") as f:
                # a redirect followed off https: what TLS vouched for ends there
                if not r.geturl().startswith("https://"):
                    raise Refused(f"{url}: redirected to {r.geturl()}, not https")
                shutil.copyfileobj(r, f, 1 << 20)
        except OSError as e:  # URLError and HTTPError are OSErrors
            raise Refused(f"{url}: {e}") from None
        return name

    def text(self, url):
        with open(self.path(url), encoding="utf-8") as f:
            return f.read()


def gpg_cmd(home):
    return ["gpg", "--homedir", home, "--batch", "--no-tty", "--quiet"]


def gpg_home(**kw):
    """A keyring of its own - a plain keyring file: its common.conf there (empty), GnuPG 2.4 starts no keyboxd for it,
    whose socket in the directory would pass the 107-character limit under a deep TMPDIR (the unit suite's: 'does not
    import')."""
    home = tempfile.mkdtemp(**kw)
    os.chmod(home, 0o700)
    open(os.path.join(home, "common.conf"), "w").close()
    return home


def key_primaries_and_signers(path):
    """(the key file's primary fingerprints, [(fingerprint, expiry)] of its valid signing keys that expire)."""
    home = gpg_home()
    try:
        out = subprocess.run(gpg_cmd(home) + ["--with-colons", "--show-keys", path],
                             capture_output=True, text=True, check=True).stdout
    finally:
        shutil.rmtree(home, ignore_errors=True)
    primaries, signers, last = [], [], None
    for f in (line.split(":") for line in out.splitlines()):
        if f[0] in ("pub", "sub"):
            last = f
        elif f[0] == "fpr" and last is not None:
            if last[0] == "pub":
                primaries.append(f[9])
            own = last[11] if len(last) > 11 else ""
            if "s" in own and last[1] not in ("e", "r") and last[6]:
                signers.append((f[9], int(last[6])))
            last = None
    return primaries, signers


class Keys:
    def __init__(self, keys_dir, work):
        self.dir, self.work, self.homes = keys_dir, work, {}
        try:
            with open(os.path.join(keys_dir, "keys.json"), encoding="utf-8") as f:
                self.manifest = json.load(f)
        except (OSError, ValueError) as e:
            raise Refused(f"the vendors' keys not read ({keys_dir}/keys.json): {e}") from None

    def vendors(self):
        """(vendor, its entry) for each vendor keys.json pins - its comment left out."""
        return [(v, k) for v, k in sorted(self.manifest.items()) if isinstance(k, dict) and "file" in k]

    def vendor(self, vendor):
        k = self.manifest.get(vendor)
        if not isinstance(k, dict) or not k.get("fingerprints"):
            raise Refused(f"no pinned key for {vendor} in keys.json")
        return k

    def home(self, vendor):
        """A keyring holding the vendor's key alone, made once a run."""
        if vendor not in self.homes:
            home = gpg_home(dir=self.work, prefix="g.")
            imp = subprocess.run(gpg_cmd(home) + ["--import", os.path.join(self.dir, self.vendor(vendor)["file"])],
                                 capture_output=True)
            if imp.returncode != 0:
                raise Refused(f"{vendor}'s key file does not import")
            self.homes[vendor] = home
        return self.homes[vendor]

    def verify(self, vendor, sig, data):
        """The signature over the data checks, by a key of the vendor's pinned fingerprints. Returns the signer."""
        pinned = self.vendor(vendor)["fingerprints"]
        r = subprocess.run(gpg_cmd(self.home(vendor)) + ["--status-fd", "1", "--verify", sig, data],
                           capture_output=True, text=True)
        status = [line.split() for line in r.stdout.splitlines() if line.startswith("[GNUPG:] ")]
        words = {s[1] for s in status if len(s) > 1}
        # VALIDSIG's last field: the signing key's PRIMARY fingerprint (a subkey signs; its primary is what is pinned)
        valid = [s[-1] for s in status if len(s) > 2 and s[1] == "VALIDSIG"]
        if r.returncode != 0 or "GOODSIG" not in words or words & {"BADSIG", "ERRSIG", "EXPKEYSIG", "REVKEYSIG"}:
            raise Refused(f"{os.path.basename(data)}: {vendor}'s signature does not check ({sorted(words)})")
        if not valid or any(v not in pinned for v in valid):
            raise Refused(f"{os.path.basename(data)}: signed by {valid}, not {vendor}'s pinned keys alone")
        return valid[0]

    def expiring(self, vendors, now):
        """A warning for each of these vendors whose NEWEST signing key expires within WARN_DAYS - vendors sign with
        their newest (Forgejo 15.0.11: its 2027-06 subkey, not its 2027-01 one); an older one still signing fails closed
        when it expires (EXPKEYSIG: does not check)."""
        out = []
        for vendor, k in self.vendors():
            if vendor not in vendors:
                continue
            try:
                _, signers = key_primaries_and_signers(os.path.join(self.dir, k["file"]))
            except (OSError, subprocess.CalledProcessError) as e:
                out.append(f"WARNING: {vendor}'s key file not read: {e}")
                continue
            if signers:
                fpr, exp = max(signers, key=lambda s: s[1])
                if exp - now < WARN_DAYS * 86400:
                    out.append(f"WARNING: {vendor}'s newest signing key {fpr} expires {time.strftime(DAY, time.gmtime(exp))}"
                               " - scripts/renovate-checksums.py --refresh-keys (its signatures fail after it)")
        return out


def listed(text, name, what):
    """A checksum list's hash for name ('<hash>  <name>' lines)."""
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1].lstrip("*") == name and HASH.match(parts[0]):
            return parts[0]
    raise Refused(f"{name}: not in {what}")


def first_hash(text, what):
    parts = text.split()
    if not parts or not HASH.match(parts[0]):
        raise Refused(f"{what}: no sha256 in it")
    return parts[0]


def _from_lists(vd, vendor, fill, labels, fetch, keys):
    """A checksum list naming each artifact, its signature checked where the vendor signs it."""
    out, texts, signer = {}, {}, None
    for a in labels:
        url = fill(vd["list"], a=a)
        if url not in texts:
            path = fetch.path(url)
            if "sig" in vd:
                signer = keys.verify(vendor, fetch.path(fill(vd["sig"], a=a, list=url)), path)
            with open(path, encoding="utf-8") as f:
                texts[url] = f.read()
        out[a] = listed(texts[url], fill(vd["name"], a=a), url)
    return out, signer


def _xz_sha256(xz, base):
    """The sha256 of the .xz's content, decompressed as it is read."""
    h, d = hashlib.sha256(), lzma.LZMADecompressor()
    try:
        with open(xz, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(d.decompress(chunk))
    except lzma.LZMAError as e:
        raise Refused(f"{base}.xz: {e}") from None
    if not d.eof:
        raise Refused(f"{base}.xz: truncated")
    return h.hexdigest()


def _from_xz(vd, vendor, fill, labels, fetch, keys):
    """Each artifact through its .xz the vendor signs, its own .sha256 naming it and agreeing."""
    out, signer = {}, None
    for a in labels:
        base = fill(vd["xz"], a=a)
        # the small files first: a release half uploaded is refused before its binary is fetched
        own = listed(fetch.text(base + ".sha256"), base.rsplit("/", 1)[-1], base + ".sha256")
        sig = fetch.path(base + ".xz.asc")
        xz = fetch.path(base + ".xz")
        try:
            signer = keys.verify(vendor, sig, xz)
            digest = _xz_sha256(xz, base)
        finally:
            os.remove(xz)
        if own != digest:
            raise Refused(f"{base}.sha256 says {own}, the signed artifact is {digest}")
        out[a] = own
    return out, signer


def _from_each(vd, vendor, fill, labels, fetch, keys):
    """One sha256 file per artifact."""
    return {a: first_hash(fetch.text(fill(vd["each"], a=a)), fill(vd["each"], a=a)) for a in labels}, None


def _from_index(vd, vendor, fill, labels, fetch, keys):
    """A package index whose links carry #sha256= - labels its files."""
    out, pages = {}, {}
    for f in labels:
        project = f.split("-", 1)[0]
        if project not in pages:
            pages[project] = fetch.text(fill(vd["index"], project=project))
        m = re.search(re.escape(urllib.parse.quote(f)) + r"#sha256=([0-9a-f]{64})", pages[project])
        if not m:
            raise Refused(f"{f}: not in PyTorch's cpu index for {project}")
        out[f] = m.group(1)
    return out, None


READERS = {"list": _from_lists, "xz": _from_xz, "each": _from_each, "index": _from_index}


def hashes(pin, version, labels, fetch, keys):
    """{label: sha256} for the version's artifacts (labels: its arches, or its wheel files), and how it was vouched."""
    vd = VENDORS[pin["vendor"]]
    fill = lambda t, **kw: t.format(v=version, p=pin.get("product", ""), **kw)  # noqa: E731
    out, signer = READERS[next(k for k in READERS if k in vd)](vd, pin["vendor"], fill, labels, fetch, keys)
    return out, vd["how"] + (f" {signer}" if signer else "")


def read_version(lines, pin):
    key = pin["version"]
    rx = rf"^\s*{key}:.*?{pin['version_re']}" if "version_re" in pin else rf"^\s*{key}:\s*\"?([^\"\s#]+)\"?"
    found = [m.group(1) for m in (re.match(rx, l) for l in lines) if m]
    if len(found) != 1:
        raise Refused(f"{pin['file']}: {len(found)} lines set {key} - want one")
    return found[0]


def indent(line):
    return len(line) - len(line.lstrip())


def children(lines, start):
    """A mapping's direct children - {key: line index} - the line after its last one, and the children's indent."""
    own, child, at, end = indent(lines[start]), None, {}, start + 1
    for i in range(start + 1, len(lines)):
        l = lines[i]
        if not l.strip() or l.lstrip().startswith("#"):
            continue
        if indent(l) <= own:
            break
        child = indent(l) if child is None else child
        m = re.match(r"^\s+\"?([^\":\s]+)\"?:", l) if indent(l) == child else None
        if m:
            at[m.group(1)] = i
        end = i + 1
    return at, end, child


def top(lines, pin):
    """The pin's mapping (or list) - children(...) of the one line that opens its key."""
    start = [i for i, l in enumerate(lines) if re.match(rf"^\s*{pin['key']}:\s*$", l)]
    if len(start) != 1:
        raise Refused(f"{pin['file']}: {len(start)} lines open {pin['key']} - want one")
    return start[0], children(lines, start[0])


def _wheel_lines(lines, pin, start):
    """{wheel file: its sha256 line} - '- file: <f>' then 'sha256: <h>'."""
    out, current = {}, None
    for i in range(start + 1, len(lines)):
        l = lines[i]
        if l.strip() and indent(l) <= indent(lines[start]):
            break
        m = re.match(r"^\s*-\s+file:\s*(\S+)", l)
        if m:
            current = m.group(1)
        elif current and re.match(r"^\s+sha256:", l):
            out[current], current = i, None
    if not out:
        raise Refused(f"{pin['file']}: {pin['key']} lists no wheel with its sha256")
    return out


def _single_line(lines, pin):
    at = [i for i, l in enumerate(lines) if re.match(rf"^\s*{pin['key']}:", l)]
    if len(at) != 1:
        raise Refused(f"{pin['file']}: {len(at)} lines set {pin['key']} - want one")
    return {pin["arches"][0]: at[0]}


def pin_lines(lines, pin, version=None):
    """{label: line index} of the pin's hashes (for the version) - empty for a versioned map without that version."""
    if pin["shape"] == "single":
        return _single_line(lines, pin)
    start, (at, _, _) = top(lines, pin)
    if pin["shape"] == "wheels":
        return _wheel_lines(lines, pin, start)
    if pin["shape"] == "versioned":
        if version not in at:
            return {}
        at, _, _ = children(lines, at[version])
    missing = [a for a in pin["arches"] if a not in at]
    if missing:
        held = f" {version}" if pin["shape"] == "versioned" else ""
        raise Refused(f"{pin['file']}: {pin['key']}{held} has no {missing}")
    return {a: at[a] for a in pin["arches"]}


def versions_held(lines, pin):
    return list(top(lines, pin)[1][0])


def add_version(lines, pin, version, want):
    """A versioned map's entry for a new version, after its last one, written as the ones before it."""
    _, (at, end, child) = top(lines, pin)
    if not at:
        raise Refused(f"{pin['file']}: {pin['key']} has no version to write a new one as")
    last = max(at.values())
    q = '"' if lines[last].lstrip().startswith('"') else ""
    grandchild = children(lines, last)[2]
    block = [f"{' ' * child}{q}{version}{q}:\n"] + [f"{' ' * grandchild}{a}: {want[a]}\n" for a in pin["arches"]]
    return lines[:end] + block + lines[end:]


def git(root, *a):
    return subprocess.run(["git", "-C", root, *a], capture_output=True, text=True, check=True).stdout


def moved_files(args):
    """{file: its +/- lines} for every pin file, against --base: the working tree, or with --ref that ref from where
    it left the base. One merge-base and one diff a run."""
    head = args.ref or "HEAD"
    since = args.base if args.base == head else git(args.root, "merge-base", args.base, head).strip()
    diff = git(args.root, "diff", "--unified=0", since, *([args.ref] if args.ref else []), "--",
               *sorted({p["file"] for p in PINS}))
    out, current = {}, None
    for l in diff.splitlines():
        if l.startswith("diff --git "):
            current = out.setdefault(l.split(" b/", 1)[1], [])
        elif current is not None and l[:1] in "+-" and not l.startswith(("+++", "---")):
            current.append(l[1:])
    return out


def changed(pin, moved):
    """The pin's version line, a hash line or a wheel's file line moved."""
    return any(VALUE.match(l) or re.match(r"^\s*-\s+file:", l)
               or ("version" in pin and re.match(rf"^\s*{pin['version']}:", l)) for l in moved.get(pin["file"], []))


def read_lines(args, pin):
    if args.ref:
        return git(args.root, "show", f"{args.ref}:{pin['file']}").splitlines(keepends=True)
    with open(os.path.join(args.root, pin["file"]), encoding="utf-8") as f:
        return f.read().splitlines(keepends=True)


def write_lines(args, pin, lines):
    path = os.path.join(args.root, pin["file"])
    tmp = path + ".renovate-checksums"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.writelines(lines)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def compare(lines, pin, version, fetch, keys):
    """(the pin's hash lines, the vendor's hashes, the pin's own, how vouched) for the version."""
    at = pin_lines(lines, pin, version)
    want, how = hashes(pin, version, list(at) if pin["shape"] == "wheels" else pin["arches"], fetch, keys)
    current = {}
    for a, i in at.items():
        m = VALUE.match(lines[i])
        if not m:
            raise Refused(f"{pin['file']}:{i + 1}: no sha256 on the {a} line")
        current[a] = m.group("hash")
    return at, want, current, how


def _check_older(lines, pin, version, fetch, keys):
    """A versioned map's entries for the versions before it: each verified, never rewritten (a mismatch refused)."""
    for older in versions_held(lines, pin):
        if older == version:
            continue
        _, want, current, _ = compare(lines, pin, older, fetch, keys)
        bad = [a for a in want if current.get(a) != want[a]]
        if bad:
            raise Refused(f"{pin['key']} {older} ({' '.join(bad)}) is not the vendor's - never rewritten")


def _rewritten(lines, pin, version, at, want):
    if not at:
        lines = add_version(lines, pin, version, want)
    for a, i in at.items():
        m = VALUE.match(lines[i])
        lines[i] = m.group("head") + want[a] + m.group("tail")
    return lines


def run_pin(pin, args, fetch, keys):
    lines = read_lines(args, pin)
    version = None if pin["shape"] == "wheels" else read_version(lines, pin)
    at, want, current, how = compare(lines, pin, version, fetch, keys)
    if pin["shape"] == "versioned":
        _check_older(lines, pin, version, fetch, keys)
    stale = [a for a in want if current.get(a) != want[a]]
    state = {a: "MISSING" if a not in current else "STALE" if a in stale else "ok" for a in want}
    said = f"{pin['name']} {version or f'{len(want)} wheels'}: " + ", ".join(f"{a} {st}" for a, st in state.items()) + f" ({how})"
    if stale and not args.check:
        write_lines(args, pin, _rewritten(lines, pin, version, at, want))
        said += " - rewritten"
    return said, bool(stale)


def refresh_keys(keys, fetch):
    """Each vendor's key file read again from its url, kept only when every pinned primary is still in it."""
    failed = False
    for vendor, k in keys.vendors():
        try:
            new = fetch.path(k["url"])
            primaries, signers = key_primaries_and_signers(new)
            gone = [f for f in k["fingerprints"] if f not in primaries]
            if gone:
                raise Refused(f"{k['url']} lacks the pinned {gone} - not taken")
            shutil.copyfile(new, os.path.join(keys.dir, k["file"]))
            latest = max((e for _, e in signers), default=0)
            print(f"{vendor}: {k['file']} taken from {k['url']} (signing keys valid to "
                  f"{time.strftime(DAY, time.gmtime(latest)) if latest else 'no expiry'})")
        except (Refused, OSError, KeyError, subprocess.CalledProcessError) as e:
            failed = True
            print(f"FAILED: {vendor}: {e}")
    return 1 if failed else 0


def parse_args():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--check", action="store_true", help="compare, write nothing; exit 1 on a stale pin")
    ap.add_argument("--changed", action="store_true",
                    help="only the pins whose version or hash lines differ from --base; said when none did")
    ap.add_argument("--base", default="HEAD", help="for --changed (default HEAD: Renovate's branch, its bump not yet "
                    "committed; origin/main on a committed branch - the fix step, CI)")
    ap.add_argument("--ref", default=None, help="with --check: the pins as REF holds them (git show), not the working "
                    "tree; with --changed, those it moved since it left --base (copy-unit.sh: a unit's branch)")
    ap.add_argument("--only", nargs="+", default=None, metavar="PIN", help="these pins alone")
    ap.add_argument("--root", default=".", help="the repository (default here)")
    ap.add_argument("--keys", default=None, help="the vendors' keys (default ROOT/renovate/keys)")
    ap.add_argument("--mirror", default=None, help="every URL read from DIR/<host>/<path> (the harness)")
    ap.add_argument("--refresh-keys", action="store_true", help="each vendor's key file taken again from its url "
                    "(keys.json) - only while every pinned primary fingerprint is still in it")
    return ap.parse_args()


def run_pins(pins, args, moved, fetch, keys):
    """Each pin read (with --changed, those that moved): (failed, stale, the vendors read)."""
    failed, stale, read = [], [], set()
    for pin in pins:
        if moved is not None and not changed(pin, moved):
            continue
        read.add(pin["vendor"])
        try:
            said, was_stale = run_pin(pin, args, fetch, keys)
        except (Refused, OSError, KeyError, ValueError, subprocess.CalledProcessError) as e:
            failed.append(pin["name"])
            print(f"FAILED: {pin['name']}: {e}")
            continue
        print(said)
        if was_stale:
            stale.append(pin["name"])
    for w in keys.expiring(read, time.time()):
        print(w)
    return failed, stale, read


def verdict(args, failed, stale, read):
    if args.changed and not read:
        print(f"no pin's version or hash moved since {args.base} - nothing read")
    if failed:
        print(f"FAILED: {' '.join(failed)} - their files left as they were")
        return 1
    if args.check and stale:
        print(f"STALE: {' '.join(stale)}")
        return 1
    return 0


def main():
    args = parse_args()
    if args.ref and not args.check:
        print("REFUSED: --ref reads a branch's pins - with --check alone (nothing is written to a ref)")
        return 2
    pins = [p for p in PINS if args.only is None or p["name"] in args.only]
    if args.only and len(pins) != len(set(args.only)):
        print(f"REFUSED: no pin named {sorted(set(args.only) - {p['name'] for p in pins})}")
        return 2
    with tempfile.TemporaryDirectory(prefix="renovate-checksums.") as work:
        try:
            keys = Keys(args.keys or os.path.join(args.root, "renovate", "keys"), work)
            fetch = Fetcher(args.mirror, work)
            if args.refresh_keys:
                return refresh_keys(keys, fetch)
            moved = moved_files(args) if args.changed else None
        except Refused as e:
            print(f"FAILED: {e}")
            return 1
        except subprocess.CalledProcessError as e:
            print(f"FAILED: what moved since {args.base} not read: {e.stderr.strip()}")
            return 1
        failed, stale, read = run_pins(pins, args, moved, fetch, keys)
    return verdict(args, failed, stale, read)


if __name__ == "__main__":
    sys.exit(main())
