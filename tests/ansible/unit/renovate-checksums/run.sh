#!/bin/bash
# scripts/renovate-checksums.py - every pinned build hash read from what its vendor signs - against a local mirror of
# the vendors (--mirror) signed by throwaway keys, on copies of the real files that hold the pins: each pin rewritten
# from its vendor's signed list or signed artifact (TLS alone where nothing is signed) and nothing else in the file;
# every way a signature, a key, a list or a vendor's own checksum file can fail refused, the file left as it was;
# --check, --changed/--base/--ref, --only, key expiry and --refresh-keys; every build hash under deploy/ansible covered,
# each playbook downloading the artifact the script hashes; the real keys; Renovate's wiring; ci-build-hashes.sh.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'gpgconf --homedir "$W/gnupg" --kill all 2> /dev/null; rm -rf "$W"' EXIT
command -v gpg > /dev/null || { echo "renovate-checksums: gpg missing - 1 FAILED"; exit 1; }
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" -I - <<'PYRC'
import fnmatch, hashlib, importlib.util, json, lzma, os, re, shutil, subprocess, sys, urllib.parse
import yaml
sys.path.insert(0, "tests/ansible/unit")
from plays import files  # noqa: E402
W = os.environ["W"]
OPS = os.getcwd()
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
spec = importlib.util.spec_from_file_location("rc", "scripts/renovate-checksums.py")
rc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rc)
PIN = {p["name"]: p for p in rc.PINS}
SIGNING = sorted(v for v, d in rc.VENDORS.items() if "sig" in d or "xz" in d)

# ── throwaway keys: the vendor's (a certify-only primary signing through its subkey, as HashiCorp's and Forgejo's do),
# a rogue one, one expired since it signed, one expiring in 30 days ──
G = os.path.join(W, "gnupg")
os.makedirs(G, mode=0o700)
def gpg(*a, **kw):
    return subprocess.run(["gpg", "--homedir", G, "--batch", "--no-tty", "--quiet", *a], capture_output=True, check=True, **kw)
def fprs(uid):
    return [l.split(":")[9] for l in gpg("--with-colons", "--list-keys", uid, text=True).stdout.splitlines() if l.startswith("fpr:")]
def make_key(uid, usage="sign", expire="never", *extra):
    gpg(*extra, "--passphrase", "", "--quick-gen-key", uid, "ed25519", usage, expire)
    return fprs(uid)[0]
VENDOR = make_key("Vendor <vendor@test>", "cert")
gpg("--passphrase", "", "--quick-add-key", VENDOR, "ed25519", "sign", "never")
VENDOR_SUB = fprs("Vendor <vendor@test>")[1]
ROGUE = make_key("Rogue <rogue@test>")
OLD = make_key("Old <old@test>", "sign", "1d", "--faked-system-time", "20200101T000000")
SOON = make_key("Soon <soon@test>", "sign", "30d")
def keys_dir(name, in_file, pinned):
    d = os.path.join(W, name)
    os.makedirs(d)
    armored = gpg("--armor", "--export", *in_file).stdout
    for v in SIGNING:
        open(os.path.join(d, f"{v}.asc"), "wb").write(armored)
    json.dump({v: {"file": f"{v}.asc", "fingerprints": pinned, "source": "test", "url": f"https://keys.test/{v}.asc"}
               for v in SIGNING}, open(os.path.join(d, "keys.json"), "w"))
    return d
good_keys = keys_dir("keys", [VENDOR], [VENDOR])
rogue_in_file = keys_dir("keys-rogue", [VENDOR, ROGUE], [VENDOR])  # a valid signature, not a pinned key
sub_pinned = keys_dir("keys-sub", [VENDOR], [VENDOR_SUB])           # the subkey pinned, not its primary
old_keys = keys_dir("keys-old", [VENDOR, OLD], [VENDOR, OLD])       # a key expired since it signed, pinned

# ── the mirror: each vendor's files where the script reads them ─────────────
V = {"vault": "1.22.0", "forgejo": "15.0.12", "helm": "v3.21.0", "node_exporter": "1.13.0", "nexus": "3.91.0-02",
     "versitygw": "1.9.0", "consul": "1.21.0", "keycloak": "26.6.0", "gateway_api": "v1.6.0"}
M = os.path.join(W, "mirror")
def put(url, data):
    p = os.path.join(M, url.split("://", 1)[1] + ("index.html" if url.endswith("/") else ""))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "wb").write(data if isinstance(data, bytes) else data.encode())
    return p
def sign(path, key=VENDOR_SUB, armor=False, faked=None, out=None):
    out = out or path + (".asc" if armor else ".sig")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    gpg(*(["--faked-system-time", faked] if faked else []), "--yes", "--local-user", key + "!",
        *(["--armor"] if armor else []), "--detach-sign", "-o", out, path)
    return out
def mirror_path(url):
    return os.path.join(M, url.split("://", 1)[1])
def h(data):
    return hashlib.sha256(data if isinstance(data, bytes) else data.encode()).hexdigest()
def listing(names_data):
    return "".join(f"{h(x)}  {n}\n" for n, x in names_data)
expect = {}
v = V["vault"]
zips = {a: f"vault {v} {a} zip".encode() for a in ("arm64", "amd64", "386")}
sums_url = f"https://releases.hashicorp.com/vault/{v}/vault_{v}_SHA256SUMS"
sign(put(sums_url, listing((f"vault_{v}_linux_{a}.zip", z) for a, z in zips.items())))
expect["vault"] = {a: h(zips[a]) for a in ("arm64", "amd64")}
v = V["consul"]
czips = {a: f"consul {v} {a} zip".encode() for a in ("arm64", "amd64")}
sign(put(f"https://releases.hashicorp.com/consul/{v}/consul_{v}_SHA256SUMS",
         listing((f"consul_{v}_linux_{a}.zip", z) for a, z in czips.items())))
expect["consul"] = {a: h(z) for a, z in czips.items()}
v = V["keycloak"]
kurl = f"https://github.com/keycloak/keycloak/releases/download/{v}/keycloak-{v}.tar.gz"
sign(put(kurl, f"keycloak {v} tarball"), armor=True)
expect["keycloak"] = {"noarch": h(f"keycloak {v} tarball")}
v = V["gateway_api"]
put(f"https://github.com/kubernetes-sigs/gateway-api/releases/download/{v}/standard-install.yaml", f"gateway api {v} crds")
expect["gateway_api"] = {"noarch": h(f"gateway api {v} crds")}
v = V["forgejo"]
fj = {a: f"https://code.forgejo.org/forgejo/forgejo/releases/download/v{v}/forgejo-{v}-linux-{a}" for a in ("arm64", "amd64")}
binaries = {a: f"forgejo {v} {a} binary".encode() for a in fj}
for a, base in fj.items():
    put(base + ".sha256", listing([(f"forgejo-{v}-linux-{a}", binaries[a])]))
    sign(put(base + ".xz", lzma.compress(binaries[a])), armor=True)
expect["forgejo"] = {a: h(b) for a, b in binaries.items()}
v = V["helm"]
name = f"helm-{v}-linux-amd64.tar.gz"
hl = put(f"https://get.helm.sh/{name}.sha256sum", listing([(name, f"helm {v} tarball")]))
sign(hl, armor=True, out=mirror_path(f"https://github.com/helm/helm/releases/download/{v}/{name}.sha256sum.asc"))
expect["helm"] = {"amd64": h(f"helm {v} tarball")}
v = V["node_exporter"]
put(f"https://github.com/prometheus/node_exporter/releases/download/v{v}/sha256sums.txt",
    listing((f"node_exporter-{v}.linux-{a}.tar.gz", f"ne {v} {a}") for a in ("amd64", "arm64")))
expect["node_exporter"] = {"amd64": h(f"ne {v} amd64")}
v = V["nexus"]
expect["nexus"] = {}
for a in ("aarch_64", "x86_64"):
    put(f"https://download.sonatype.com/nexus/3/nexus-{v}-linux-{a}.tar.gz.sha256", f"{h(f'nexus {v} {a}')}\n")
    expect["nexus"][a] = h(f"nexus {v} {a}")
# versitygw: the new version's list, and those of the versions the real file holds (their real hashes)
vg_real = open(PIN["versitygw"]["file"]).read().splitlines(keepends=True)
for older in rc.versions_held(vg_real, PIN["versitygw"]):
    at = rc.pin_lines(vg_real, PIN["versitygw"], older)
    put(f"https://github.com/versity/versitygw/releases/download/v{older}/checksums.txt",
        "".join(f"{rc.VALUE.match(vg_real[i]).group('hash')}  versitygw_{older}_linux_{a}.deb\n" for a, i in at.items()))
v = V["versitygw"]
put(f"https://github.com/versity/versitygw/releases/download/v{v}/checksums.txt",
    listing((f"versitygw_{v}_linux_{a}.deb", f"vgw {v} {a}") for a in ("amd64", "arm64")))
expect["versitygw"] = {a: h(f"vgw {v} {a}") for a in ("amd64", "arm64")}
# PyTorch's index pages: each wheel the real file lists, a new hash for it
wl = open(PIN["pytorch_cpu_wheels"]["file"]).read().splitlines(keepends=True)
wheels = list(rc.pin_lines(wl, PIN["pytorch_cpu_wheels"]))
expect["pytorch_cpu_wheels"] = {f: h(f"wheel {f}") for f in wheels}
def index_page(project, files_):
    return "<html>" + "".join(f'<a href="https://download-r2.pytorch.org/whl/cpu/{urllib.parse.quote(f)}#sha256='
                              f'{expect["pytorch_cpu_wheels"][f]}">{f}</a>' for f in files_) + "</html>"
for project in sorted({f.split("-", 1)[0] for f in wheels}):
    put(f"https://download.pytorch.org/whl/cpu/{project}/", index_page(project, [f for f in wheels if f.startswith(project + "-")]))
pristine = os.path.join(W, "mirror-pristine")
shutil.copytree(M, pristine)

# ── a repository: the real files that hold the pins, moved as Renovate moves them ──
R = os.path.join(W, "repo")
def sh(*a):
    return subprocess.run(["git", "-C", R, "-c", "user.name=t", "-c", "user.email=t@t", *a], capture_output=True,
                          text=True, check=True).stdout
def fresh_repo():
    shutil.rmtree(R, ignore_errors=True)
    for pin in rc.PINS:
        os.makedirs(os.path.join(R, os.path.dirname(pin["file"])), exist_ok=True)
        shutil.copyfile(pin["file"], os.path.join(R, pin["file"]))
    subprocess.run(["git", "init", "-q", "-b", "main", R], check=True)
    sh("add", "-A")
    sh("commit", "-qm", "base")
def bump(*names):
    for pin in rc.PINS:
        if pin["name"] not in names:
            continue
        p = os.path.join(R, pin["file"])
        s = open(p).read()
        if pin["shape"] == "wheels":  # a wheel's hash moved by hand: the pin must be read again
            s2 = s.replace(rc.VALUE.match(wl[rc.pin_lines(wl, pin)[wheels[0]]]).group("hash"), "0" * 64, 1)
        else:
            rx = (rf"^(\s*{pin['version']}:.*?default\(')[^']+" if "version_re" in pin
                  else rf"^(\s*{pin['version']}:\s*\"?)[^\"\s#]+")
            s2 = re.sub(rx, lambda m: m.group(1) + V[pin["name"]], s, count=1, flags=re.M)
        assert s2 != s, pin["name"]
        open(p, "w").write(s2)
def run(*a, keys=None, root=None):
    r = subprocess.run([sys.executable, "-I", "scripts/renovate-checksums.py", "--root", root or R, "--keys",
                        keys or good_keys, "--mirror", M, *a], capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr
def pins_now(only=None):
    out = {}
    for pin in rc.PINS:
        if only and pin["name"] != only:
            continue
        lines = open(os.path.join(R, pin["file"])).read().splitlines(keepends=True)
        version = None if pin["shape"] == "wheels" else rc.read_version(lines, pin)
        out[pin["name"]] = {a: rc.VALUE.match(lines[i]).group("hash") for a, i in rc.pin_lines(lines, pin, version).items()}
    return out
def diff_lines():
    d = subprocess.run(["git", "-C", R, "diff", "--unified=0"], capture_output=True, text=True).stdout
    return [l for l in d.splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---"))]
def reset_mirror():
    shutil.rmtree(M)
    shutil.copytree(pristine, M)

fresh_repo()
bump(*PIN)
code, out = run("--changed")
check("every pin moved: each rewritten from its vendor's signed material (or TLS, said); 0",
      (code, pins_now() == expect, out.count("rewritten"), "signed: HashiCorp" in out, "signed: Forgejo" in out,
       "signed: Helm" in out, "signed: Keycloak" in out, "TLS alone" in out), (0, True, 10, True, True, True, True, True))
changed = diff_lines()
check("  nothing else in the files changed: each moved version and each pin's hash, the rest as it was (the nexus "
      "map's sha256: prefix and quotes kept); versitygw's new version an entry of its own, as the ones before it",
      (all(re.search(r"_version:|^\+\s+\"1\.9\.0\":$|^[-+]\s+(-\s+)?\S+:\s*\"?(sha256:)?[0-9a-f]{64}", l) for l in changed),
       len([l for l in changed if l.startswith("+")]), any('"sha256:' + expect["nexus"]["x86_64"] + '"' in l for l in changed),
       len([l for l in changed if l.startswith("-") and "_version:" not in l])),
      (True, 9 + 8 + 4 + 3 + 2, True, 8 + 4 + 2))
vg_text = open(os.path.join(R, PIN["versitygw"]["file"])).read()
check("  versitygw's new entry after the ones before it", re.findall(r'^\s+"(\d+\.\d+\.\d+)":$', vg_text, re.M)[-1:], ["1.9.0"])
code, out = run("--check")
check("  --check after it: every pin ok; 0", (code, out.count("STALE"), out.count(" ok")), (0, 0, 16))

# --check: a stale pin, a missing versitygw entry - said, nothing written
p = os.path.join(R, PIN["vault"]["file"])
stale = open(p).read().replace(expect["vault"]["arm64"], "0" * 64)
open(p, "w").write(stale)
code, out = run("--check")
check("--check with a stale pin: said (STALE: vault), exit 1, nothing written", (code, "STALE: vault" in out, open(p).read() == stale), (1, True, True))
fresh_repo()
bump("versitygw")
code, out = run("--check", "--only", "versitygw")
check("--check with versitygw's new version not yet an entry: MISSING, STALE: versitygw, exit 1, nothing written",
      (code, "amd64 MISSING" in out, "STALE: versitygw" in out, [l for l in diff_lines() if "vgw_version:" not in l]),
      (1, True, True, []))

# --changed: nothing moved - nothing read, said
fresh_repo()
shutil.rmtree(M)
os.makedirs(M)
code, out = run("--changed")
check("--changed with nothing moved: no pin read (nothing fetched), said; 0", (code, "nothing read" in out, "FAILED" in out), (0, True, False))
reset_mirror()

# --base: a bump already committed (the fix step on renovate/<unit>, CI): HEAD sees nothing, the base sees it
fresh_repo()
sh("switch", "-qc", "renovate/vault")
bump("vault")
sh("commit", "-qam", "vault")
code, out = run("--changed")
check("a committed bump with --changed alone (against HEAD): nothing read, said - never a silent pass",
      (code, "no pin's version or hash moved since HEAD" in out), (0, True))
code, out = run("--changed", "--base", "main")
check("  with --base main: vault read and rewritten, its stale pins the vendor's now", (code, "vault 1.22.0" in out,
      "rewritten" in out, pins_now("vault")["vault"] == expect["vault"]), (0, True, True, True))
# --ref: the branch's pins read from git, the working tree on main untouched
sh("checkout", "-q", "--", ".")
sh("switch", "-q", "main")
code, out = run("--check", "--changed", "--base", "main", "--ref", "renovate/vault")
check("--check --changed --base main --ref renovate/vault: the branch's moved pin read from the branch (STALE: its "
      "old hashes), the working tree on main untouched; exit 1",
      (code, "STALE: vault" in out, "forgejo" in out, diff_lines()), (1, True, False, []))
code, out = run("--ref", "renovate/vault")
check("--ref without --check: refused (nothing is written to a ref), exit 2", (code, "REFUSED" in out), (2, True))
code, out = run("--check", "--changed", "--base", "no-such-ref")
check("--changed against a base git does not know: refused, said, exit 1", (code, "not read" in out), (1, True))

# --only: those pins alone (a mirror holding vault's files alone: any other read would fail)
fresh_repo()
bump("vault", "forgejo")
shutil.rmtree(M)
shutil.copytree(os.path.join(pristine, "releases.hashicorp.com"), os.path.join(M, "releases.hashicorp.com"))
code, out = run("--changed", "--only", "vault")
check("--only vault: vault alone read and rewritten (forgejo's bump left), 0",
      (code, "vault 1.22.0" in out, "forgejo" in out, pins_now("vault")["vault"] == expect["vault"]), (0, True, False, True))
reset_mirror()

def refused(case, setup, keys=None, pin="vault", other="node_exporter"):
    fresh_repo()
    bump(pin, other)
    reset_mirror()
    setup()
    f = os.path.join(R, PIN[pin]["file"])
    before = open(f).read()  # as it was before the run: left so
    code, out = run("--changed", keys=keys)
    check(f"{case}: {pin} refused (FAILED, its file as it was), {other} still done; exit 1",
          (code, f"FAILED: {pin}" in out, open(f).read() == before, pins_now(other)[other] == expect[other]),
          (1, True, True, True))
    return out
sums_path = mirror_path(sums_url)
def swapped():
    text = open(sums_path).read()
    open(sums_path, "w").write(text.replace(expect["vault"]["arm64"], h(b"evil")))
refused("the signed list changed after signing (a mirror's swap)", swapped)
out = refused("signed by a key the vendor's key file lacks", lambda: sign(sums_path, key=ROGUE))
check("  said: the signature does not check", "does not check" in out, True)
out = refused("a valid signature by a key in the vendor's file but not pinned", lambda: sign(sums_path, key=ROGUE), keys=rogue_in_file)
check("  said: not the pinned keys", "not hashicorp's pinned keys alone" in out, True)
refused("the signing subkey's own fingerprint pinned, not its primary's (VALIDSIG's primary is what counts)",
        lambda: None, keys=sub_pinned)
out = refused("a signature by a key expired since (EXPKEYSIG)", lambda: sign(sums_path, key=OLD, faked="20200101T060000"),
              keys=old_keys)
check("  said: does not check (EXPKEYSIG)", "does not check" in out and "EXPKEYSIG" in out, True)
def good_and_bad():
    sig = sign(sums_path)
    open(sig, "ab").write(open(sign(put("https://elsewhere.test/other", "other data")), "rb").read())
out = refused("a pinned key's good signature beside a bad one in the same file", good_and_bad)
check("  said: does not check", "does not check" in out, True)
def no_arm64():
    kept_lines = [l for l in open(sums_path) if "linux_arm64" not in l]
    open(sums_path, "w").write("".join(kept_lines))
    sign(sums_path)
out = refused("an artifact missing from the signed list", no_arm64)
check("  said: not in the signed SHA256SUMS", "vault_1.22.0_linux_arm64.zip: not in" in out, True)
fa = fj["amd64"]
fname = fa.rsplit("/", 1)[1]
out = refused("Forgejo's own .sha256 disagreeing with its signed .xz", lambda: put(fa + ".sha256", f"{h(b'other')}  {fname}\n"),
              pin="forgejo")
check("  said: the checksum file and the signed artifact disagree", "the signed artifact is" in out, True)
out = refused("Forgejo's .sha256 naming another file (an older signed binary served under the new name)",
              lambda: put(fa + ".sha256", f"{h(binaries['amd64'])}  forgejo-15.0.1-linux-amd64\n"), pin="forgejo")
check("  said: the artifact not in its checksum file", f"{fname}: not in" in out, True)
refused("Forgejo's .xz swapped with its .sha256 (its signature then fails)",
        lambda: (put(fa + ".xz", lzma.compress(b"swapped")), put(fa + ".sha256", f"{h(b'swapped')}  {fname}\n")), pin="forgejo")
out = refused("Forgejo's .xz signed but cut short", lambda: sign(put(fa + ".xz", lzma.compress(binaries["amd64"])[:-8]), armor=True),
              pin="forgejo")
check("  said: truncated, or not xz", "truncated" in out or "xz" in out, True)
def older_versitygw_lies():
    held = rc.versions_held(vg_real, PIN["versitygw"])
    put(f"https://github.com/versity/versitygw/releases/download/v{held[0]}/checksums.txt",
        f"{h(b'x')}  versitygw_{held[0]}_linux_amd64.deb\n{h(b'y')}  versitygw_{held[0]}_linux_arm64.deb\n")
out = refused("an older versitygw entry the vendor's list does not vouch for", older_versitygw_lies, pin="versitygw")
check("  said: never rewritten", "never rewritten" in out, True)
out = refused("two lines setting vault_version",
              lambda: open(os.path.join(R, PIN["vault"]["file"]), "a").write('vault_version: "1.0.0"\n'))
check("  said: 2 lines set it", "2 lines set vault_version" in out, True)
out = refused("a pinned wheel missing from PyTorch's index",
              lambda: put(f"https://download.pytorch.org/whl/cpu/{wheels[0].split('-', 1)[0]}/", "<html></html>"),
              pin="pytorch_cpu_wheels")
check("  said: not in PyTorch's cpu index", "not in PyTorch's cpu index" in out, True)

code, out = run("--only", "nope")
check("--only a name no pin has: refused, exit 2", (code, "no pin named" in out), (2, True))

# signing keys expiring: warned of for each vendor a run reads (its newest signing key under 60 days), not otherwise
soon_keys = keys_dir("keys-soon", [SOON], [SOON])
fresh_repo()
bump("vault")
code, out = run("--changed", keys=soon_keys)
check("a vendor read whose newest signing key expires within 60 days: WARNING naming --refresh-keys; none for one "
      "that does not, none for a vendor not read",
      ("WARNING: hashicorp's newest signing key" in out and "--refresh-keys" in out, "WARNING: forgejo" in out,
       "WARNING" in run("--changed")[1]), (True, False, False))

# --refresh-keys: taken while every pinned primary is in the url's file; refused (the file kept) otherwise
rk = keys_dir("keys-refresh", [VENDOR], [VENDOR])
gpg("--passphrase", "", "--quick-add-key", VENDOR, "ed25519", "sign", "2y")  # the vendor's new signing subkey
for v in SIGNING:
    put(f"https://keys.test/{v}.asc", gpg("--armor", "--export", VENDOR).stdout)
before_rk = open(os.path.join(rk, "forgejo.asc"), "rb").read()
code, out = run("--refresh-keys", keys=rk)
check("--refresh-keys: each vendor's file taken from its url (a new subkey in it), its pinned primary kept; 0",
      (code, out.count(" taken from "), open(os.path.join(rk, "forgejo.asc"), "rb").read() != before_rk), (0, len(SIGNING), True))
put("https://keys.test/forgejo.asc", gpg("--armor", "--export", ROGUE).stdout)
kept = open(os.path.join(rk, "forgejo.asc"), "rb").read()
code, out = run("--refresh-keys", keys=rk)
check("  a url serving another key: refused, the file kept, exit 1",
      (code, "FAILED: forgejo" in out, open(os.path.join(rk, "forgejo.asc"), "rb").read() == kept), (1, True, True))
reset_mirror()

# every build hash under deploy/ansible verified: each 64-hex literal (no image digest) a line the script locates
covered = set()
for pin in rc.PINS:
    lines = open(pin["file"]).read().splitlines(keepends=True)
    versions = (rc.versions_held(lines, pin) if pin["shape"] == "versioned"
                else [None if pin["shape"] == "wheels" else rc.read_version(lines, pin)])
    covered |= {(pin["file"], i) for ver in versions for i in rc.pin_lines(lines, pin, ver).values()}
literals = {(path, i) for path in files("deploy/ansible")
            for i, l in enumerate(open(path, encoding="utf-8"))
            if "@sha256:" not in l and re.search(r"(?<![0-9a-f])[0-9a-f]{64}(?![0-9a-f])", l)}
check("every build hash under deploy/ansible is a line the script verifies (none left out), and there are hashes to "
      "verify (the scan reads the tree)", (sorted(literals - covered), len(literals) >= 18), ([], True))

# each playbook downloads the artifact the script hashes: its URL, rendered with a version and an arch, names it
DOWNLOADS = {  # pin -> the playbooks' download lines (their file, a marker on the line)
    "vault": [("upgrade-vault.yml", "url: \"https://releases.hashicorp.com/vault/"), ("setup-vault-pi.yml", "url: \"https://releases.hashicorp.com/vault/")],
    "consul": [("setup-consul.yml", "url: \"https://releases.hashicorp.com/consul/")],
    "keycloak": [("setup-pi-services.yml", "url: \"https://github.com/keycloak/")],
    "gateway_api": [("setup-kubeadm.yml", "url: \"https://github.com/kubernetes-sigs/gateway-api/")],
    "forgejo": [("setup-pi-services.yml", "url: \"https://code.forgejo.org/"), ("upgrade-forgejo.yml", "url: \"https://code.forgejo.org/")],
    "helm": [("setup-kubeadm.yml", "https://get.helm.sh/helm-")],
    "node_exporter": [("setup-host-hardening.yml", "node_exporter_archive_name:")],
    "nexus": [("setup-nexus.yml", "url: \"https://download.sonatype.com/")],
    "versitygw": [("tasks/versitygw.yml", "url: \"https://github.com/versity/")],
}
def artifact(pin, v, a):
    vd = rc.VENDORS[pin["vendor"]]
    fill = lambda t: t.format(v=v, a=a, p=pin.get("product", ""))  # noqa: E731
    if "name" in vd:
        return fill(vd["name"])
    return fill(vd.get("xz") or vd.get("artifact") or vd["each"].removesuffix(".sha256")).rsplit("/", 1)[1]
bad = []
for n, places in DOWNLOADS.items():
    pin = PIN[n]
    for f, marker in places:
        hits = [l for l in open(f"deploy/ansible/playbooks/{f}") if marker in l]
        if len(hits) != 1:
            bad.append(f"{f}: {len(hits)} lines with {marker!r}")
            continue
        url = re.findall(r'"([^"]*\{\{[^"]*)"', hits[0])[-1]
        for a in pin["arches"]:
            got = re.sub(r"\{\{\s*([a-z_]+)\s*\}\}", lambda m: "1.2.3" if m.group(1) == pin["version"]
                         else a if m.group(1).endswith("arch") else m.group(0), url).rsplit("/", 1)[-1]
            if got != artifact(pin, "1.2.3", a):
                bad.append(f"{f} ({a}): downloads {got}, the script hashes {artifact(pin, '1.2.3', a)}")
check("each pin's playbooks download the artifact the script hashes (their URL's name, a version and arch put in)", bad, [])

# the real keys: each pinned fingerprint a primary of its vendor's file; each vendor an https url to refresh from
real = json.load(open("renovate/keys/keys.json"))
vendors = sorted(v for v, k in real.items() if isinstance(k, dict))
bad = {}
for v in vendors:
    prim, _ = rc.key_primaries_and_signers(os.path.join("renovate/keys", real[v]["file"]))
    bad[v] = [f for f in real[v]["fingerprints"] if f not in prim] + ([] if real[v].get("url", "").startswith("https://") else ["no url"])
check("the real keys: every pinned fingerprint a primary key in its vendor's file, every vendor an https url - and a "
      "key for every vendor the script checks a signature of", (bad, vendors), ({v: [] for v in vendors}, SIGNING))

# Renovate runs it: the preset's post-upgrade task once a branch on every ops update; the one allowed command, read
# from renovate/allowed-commands.json by the pipeline
CMD = "python3 -I scripts/renovate-checksums.py --changed"
preset = json.load(open("renovate/upgrade-cycle.json"))
tasks = [r for r in preset["packageRules"] if "postUpgradeTasks" in r]
check("the preset: one post-upgrade task, the script's --changed, once a branch, on every ops update, its files every "
      "pin's", (len(tasks), tasks[0].get("matchRepositories"), tasks[0]["postUpgradeTasks"]["commands"],
                tasks[0]["postUpgradeTasks"].get("executionMode"),
                [p["file"] for p in rc.PINS if not any(fnmatch.fnmatch(p["file"], g.replace("**", "*"))
                                                       for g in tasks[0]["postUpgradeTasks"]["fileFilters"])]),
      (1, ["schnappy/ops"], [CMD], "branch", []))
allowed = json.load(open("renovate/allowed-commands.json"))
launcher = open("scripts/upgrade-renovate.sh").read()
check("the allowed commands: that one, nothing chained to it; task upgrade's Renovate (scripts/upgrade-renovate.sh) "
      "reads them from renovate/allowed-commands.json",
      ([bool(re.match(rx, CMD)) for rx in allowed], [bool(re.match(rx, CMD + "; rm -rf /")) for rx in allowed],
       'RENOVATE_ALLOWED_COMMANDS=$(cat "$ops/renovate/allowed-commands.json")' in launcher),
      ([True], [False], True))
annotated = {p["name"]: bool(re.search(rf"#\s*renovate:.*\n\s*{p['version']}:", open(p["file"]).read()))
             for p in rc.PINS if "version" in p}
check("each pin Renovate moves is annotated where its version is; each it does not move is not, and says why",
      ({n: a for n, a in annotated.items() if PIN[n].get("renovate", True) != a},
       [p["name"] for p in rc.PINS if p.get("renovate", True) is False and not p.get("why")]), ({}, []))

# ci-build-hashes.sh: a push's moved pins against the commit before it; every pin when the keys change
fresh_repo()
os.makedirs(os.path.join(R, "scripts"))
shutil.copyfile("scripts/ci-build-hashes.sh", os.path.join(R, "scripts/ci-build-hashes.sh"))
shutil.copyfile("scripts/renovate-checksums.py", os.path.join(R, "scripts/renovate-checksums.py"))
shutil.copytree(good_keys, os.path.join(R, "renovate/keys"))
sh("add", "-A")
sh("commit", "-qm", "the checker")
prev = sh("rev-parse", "HEAD").strip()
bump("vault")
sh("commit", "-qam", "vault, its old pins")
def ci(prev_sha):
    r = subprocess.run(["bash", os.path.join(R, "scripts/ci-build-hashes.sh"), "--mirror", M], capture_output=True,
                       text=True, env=dict(os.environ, CI_PIPELINE_EVENT="push", CI_PREV_COMMIT_SHA=prev_sha))
    return r.returncode, r.stdout + r.stderr
code, out = ci(prev)
check("ci-build-hashes.sh on a push: the pin it moved checked (STALE: vault - a bump without its hashes), the others "
      "not read; exit 1", (code, "STALE: vault" in out, "forgejo" in out), (1, True, False))
open(os.path.join(R, "renovate/keys/keys.json"), "a").write("\n")
sh("commit", "-qam", "the keys touched")
code, out = ci(prev)
check("  the keys changed too: every pin checked (forgejo's too, its version not moved)",
      (code, "every pin checked" in out, "forgejo" in out), (1, True, True))
code, out = ci("0" * 40)
check("  a base the clone does not hold: refused, nothing waved through", (code, "not in this clone" in out), (1, True))
print("renovate-checksums: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYRC
