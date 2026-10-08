#!/bin/bash
# The Vagrant copy's isolation drops production's LAN (nftables), and production's LAN carries an IPv6 prefix too
# (ten: fd0a:94e6:20b4:9f6b::/64, read 2026-10-08) - so both isolations (the Pis', the cluster node's) prove
# the VM has no IPv6 beyond link-local, failing closed the day a box or a libvirt network gives it one. Their checks as
# the playbooks hold them, `ip` a stub: link-local only passes; a ULA route, a global address each fail; `ip` failing
# fails (it read as "no IPv6"); a kernel with no IPv6 passes. And each guard drops production's IPv6 prefix as well.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/ip" <<'STUB'
#!/bin/bash
[ -z "${IP_FAILS:-}" ] || { echo "RTNETLINK answers: Operation not supported" >&2; exit 2; }
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
    sh = (sh if isinstance(sh, str) else sh["cmd"]).replace("/proc/net/if_inet6", os.path.join(W, "if_inet6"))
    for name, env, want, kernel6 in (("link-local only: passes", {}, 0, True),
                                     ("a ULA route: fails", {"ROUTE": "fd0a:94e6:20b4:9f6b::/64 dev eth1 proto ra"}, 1,
                                      True),
                                     ("a global address: fails", {"ADDR": "2001:db8::5/64"}, 1, True),
                                     ("ip failing: fails (never read as no IPv6)", {"IP_FAILS": "1"}, 1, True),
                                     ("a kernel with no IPv6: passes", {"IP_FAILS": "1"}, 0, False)):
        f = os.path.join(W, "if_inet6")
        if kernel6:
            open(f, "w").close()
        elif os.path.exists(f):
            os.remove(f)
        r = subprocess.run(["bash", "-c", sh], capture_output=True, text=True,
                           env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], **env))
        ok = min(r.returncode, 1) == want
        fails += not ok
        print(f"{'PASS' if ok else 'FAIL'} {book}: {name}" + ("" if ok else f" (rc {r.returncode}: {r.stdout}{r.stderr})"))
    # the guard's nft rules drop production's IPv6 prefix too (every output chain; the cluster's forward chain as well)
    sys.path.insert(0, "tests/ansible/unit")
    from templar import render  # noqa: E402
    # the play's own vars over its vars_files' (production's LAN: deploy/ansible/vars/production-lan.yml)
    def with_files(p):
        out = {}
        for f in p.get("vars_files") or []:
            out.update(yaml.safe_load(open(os.path.join(os.path.dirname(book), f))) or {})
        return {**out, **(p.get("vars") or {})}
    play_vars = next(with_files(p) for p in yaml.safe_load(open(book)) if "production_lan" in with_files(p))
    nft = next(t for t in tasks if "table inet vagrant_isolation {" in str(t))
    body = nft.get("ansible.builtin.copy", {}).get("content") or str(nft.get("ansible.builtin.shell", ""))
    text = render(body, **{k: v for k, v in play_vars.items()}, production_public=["203.0.113.1"])
    chains = [l for l in text.splitlines() if "chain " in l and "daddr" in l]
    ok = bool(chains) and all("ip6 daddr fd0a:94e6:20b4:9f6b::/64 drop" in l for l in chains)
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {book}: the guard drops production's IPv6 prefix in every chain" + ("" if ok else f" ({chains})"))
print("isolation-ipv6: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
