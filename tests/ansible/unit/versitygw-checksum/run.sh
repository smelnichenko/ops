#!/bin/bash
# The Pis' versitygw package (deploy/ansible/playbooks/tasks/versitygw.yml), installed as root on both: downloaded
# from GitHub with its sha256 checked (vgw_checksums, per version and arch; the release's checksums.txt, its assets'
# digests and the files' own sums agreed 2026-10-09), then installed from that file - apt took the URL with no check.
# A version with no checksum is refused before anything is fetched; every version a step or the default installs has
# both arches'. The task file read as Ansible reads it, its conditions and the checksum rendered by Ansible's templar.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY'
import glob, re, sys
sys.path.insert(0, "tests/ansible/unit")
from plays import actions, load, tasks  # noqa: E402
from templar import condition, render  # noqa: E402
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


F = "deploy/ansible/playbooks/tasks/versitygw.yml"
ts = tasks(load(F))
act = [(i, m.split(".")[-1], v, t) for i, t in enumerate(ts) for m, v in actions(t)]
apt = next((a for a in act if a[1] == "apt" and "deb" in (a[2] or {})), None)
get = next((a for a in act if a[1] == "get_url" and "versitygw" in str((a[2] or {}).get("url"))), None)
sums = next((a for a in act if a[1] == "set_fact" and "vgw_checksums" in (a[2] or {})), None)
check("the package installed from a file, not a URL", apt is not None and "://" not in apt[2]["deb"], True)
check("  the file get_url fetched, before the install", (get is not None and apt is not None
                                                        and get[2].get("dest") == apt[2]["deb"] and get[0] < apt[0]),
      True)
table = sums[2]["vgw_checksums"] if sums else {}
# the versions installed: the default (before and after its step's default line) and each step's -e vgw_version
text = open(F).read()
versions = set(re.findall(r"vgw_version \| default\('([0-9.]+)'\)", text))
for s in glob.glob("tests/ansible/upgrade/steps/*.txt"):
    st = open(s).read()
    versions |= set(re.findall(r"-e vgw_version=([0-9.]+)", st))
    versions |= set(re.findall(r"vgw_version \| default\('([0-9.]+)'\)", st))
check("the versions installed found", sorted(versions), ["1.6.0", "1.8.0"])
for v in sorted(versions):
    for arch in ("amd64", "arm64"):
        got = render(get[2]["checksum"], vgw_version=v, forgejo_arch=arch, vgw_checksums=table) if get else None
        check(f"  {v} {arch}: its sha256 checked", bool(got and re.fullmatch(r"sha256:[0-9a-f]{64}", got)), True)
        url = render(get[2]["url"], vgw_version=v, forgejo_arch=arch) if get else ""
        check(f"  {v} {arch}: from its release", url,
              f"https://github.com/versity/versitygw/releases/download/v{v}/versitygw_{v}_linux_{arch}.deb")
guard = next((a for a in act if a[1] == "assert" and "vgw_checksums" in str(a[2].get("that"))), None)
check("a version without a checksum refused, before the download",
      (guard is not None and get is not None and guard[0] < get[0],
       [condition(guard[2]["that"], vgw_version=v, forgejo_arch="arm64", vgw_checksums=table) if guard else None
        for v in ("1.8.0", "9.9.9")]), (True, [True, False]))
print("versitygw-checksum: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
