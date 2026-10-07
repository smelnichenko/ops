#!/bin/bash
# The Vagrant copy's isolation drops production's LAN by IPv4 only (nftables), and production's LAN carries an IPv6
# prefix too (ten: fd0a:94e6:20b4:9f6b::/64, read 2026-10-08) - so both isolations (the Pis', the cluster node's) prove
# the VM has no IPv6 beyond link-local, failing closed the day a box or a libvirt network gives it one. Their checks as
# the playbooks hold them, `ip` a stub: link-local only passes; a ULA route, a global address each fail.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/ip" <<'STUB'
#!/bin/bash
case "$*" in
  "-6 route show")
    echo "fe80::/64 dev eth0 proto kernel metric 256 pref medium"
    echo "multicast ff00::/8 dev eth0 table local proto kernel metric 256 pref medium"
    [ -z "${ROUTE:-}" ] || echo "$ROUTE" ;;
  "-6 addr show scope global") [ -z "${ADDR:-}" ] || echo "    inet6 $ADDR scope global" ;;
esac
STUB
chmod +x "$W/bin/ip"
W=$W "$PY" - <<'PY'
import os, subprocess, sys
import yaml
W = os.environ["W"]
fails = 0
for book in ("tests/ansible/isolate-pis.yml", "tests/ansible/upgrade/isolate-cluster.yml"):
    tasks = [t for p in yaml.safe_load(open(book)) for t in p.get("tasks") or []]
    found = [t for t in tasks if "ip -6 route show" in str(t.get("ansible.builtin.shell", ""))]
    ok = len(found) == 1
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {book}: an IPv6 check")
    if not ok:
        continue
    sh = found[0]["ansible.builtin.shell"]
    sh = sh if isinstance(sh, str) else sh["cmd"]
    for name, env, want in (("link-local only: passes", {}, 0),
                            ("a ULA route: fails", {"ROUTE": "fd0a:94e6:20b4:9f6b::/64 dev eth1 proto ra"}, 1),
                            ("a global address: fails", {"ADDR": "2001:db8::5/64"}, 1)):
        r = subprocess.run(["bash", "-c", sh], capture_output=True, text=True,
                           env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], **env))
        ok = min(r.returncode, 1) == want
        fails += not ok
        print(f"{'PASS' if ok else 'FAIL'} {book}: {name}" + ("" if ok else f" (rc {r.returncode}: {r.stdout}{r.stderr})"))
print("isolation-ipv6: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
