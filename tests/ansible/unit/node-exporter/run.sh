#!/bin/bash
# setup-host-hardening.yml's node_exporter: the unit as rendered for production - bound to the node's LAN address (not
# every interface), the root filesystem and /boot kept while the kubelet's and containerd's per-pod mounts are left out
# (Go's regexp and Python's agree on this pattern), the download checked against the pinned sha256 and the binary
# replaced only when the version differs; the check at the end reads the root filesystem's free space.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml, jinja2' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 exec "$PY" - <<'PY_NODEEXP'
import re, shlex, sys, yaml, jinja2
fails = 0
def check(name, got, want):
    global fails
    print(("PASS " if got == want else "FAIL ") + name)
    if got != want:
        print(f"    got:  {got!r}\n    want: {want!r}")
        fails += 1
play = yaml.safe_load(open("deploy/ansible/playbooks/setup-host-hardening.yml"))[0]
v = dict(play["vars"])
tasks = {t["name"]: t for t in play["tasks"]}
env = jinja2.Environment(undefined=jinja2.StrictUndefined)
# the play's vars resolved as production's inventory leaves them (no node_ip_override)
for _ in range(3):
    v = {k: env.from_string(x).render(**v) if isinstance(x, str) else x for k, x in v.items()}
unit = env.from_string(tasks["Write node_exporter systemd unit"]["ansible.builtin.copy"]["content"]).render(**v)
# ExecStart and its continuation lines (each ending in a backslash)
lines = []
for l in unit.split("ExecStart=", 1)[1].splitlines():
    lines.append(l.strip().rstrip("\\"))
    if not l.rstrip().endswith("\\"):
        break
start = " ".join(lines)
args = shlex.split(start)
flag = lambda f: next((a.split("=", 1)[1] for a in args if a.startswith(f + "=")), None)
check("bound to ten's LAN address on 9100", flag("--web.listen-address"), "192.168.11.2:9100")
check("runs unprivileged", "DynamicUser=true" in unit, True)
exclude = re.compile(flag("--collector.filesystem.mount-points-exclude"))
kept = ["/", "/boot", "/boot/efi", "/var", "/opt", "/var/lib/kubelet"]
gone = ["/dev", "/proc", "/sys", "/run/credentials/x.service", "/var/lib/kubelet/pods/u/volumes/kubernetes.io~csi/v/mount",
        "/run/containerd/io.containerd.runtime.v2.task/k8s.io/id/rootfs", "/var/lib/containerd/io.containerd.grpc.v1.cri/x",
        "/run/netns/cni-1"]
check("the root filesystem and its peers kept", [m for m in kept if exclude.search(m)], [])
check("per-pod and pseudo mounts left out", [m for m in gone if not exclude.search(m)], [])
# Cilium's per-pod veths (lxc*) out of netdev and netclass; the node's own interfaces in
for f in ("--collector.netdev.device-exclude", "--collector.netclass.ignored-devices"):
    rx = re.compile(flag(f) or "^$never")
    check(f"{f}: the pods' lxc veths out, the node's own interfaces in",
          ([d for d in ("lxc4a1b2c3d4e5f", "lxc_health") if not rx.search(d)],
           [d for d in ("enp3s0", "eno1", "br0", "cilium_host", "cilium_vxlan", "lo") if rx.search(d)]), ([], []))
get = tasks["Download node_exporter, its checksum checked"]["ansible.builtin.get_url"]
check("the download checked against the pinned sha256", env.from_string(get["checksum"]).render(**v),
      "sha256:" + v["node_exporter_sha256"])
check("  a 64-hex sha256 pinned", bool(re.fullmatch(r"[0-9a-f]{64}", v["node_exporter_sha256"])), True)
check("  the release asset of the pinned version", env.from_string(get["url"]).render(**v),
      f"https://github.com/prometheus/node_exporter/releases/download/v{v['node_exporter_version']}/"
      f"node_exporter-{v['node_exporter_version']}.linux-amd64.tar.gz")
check("the binary replaced only on another version",
      tasks["Move node_exporter into place"]["when"], "_node_exporter_version.stdout != node_exporter_version")
check("the unpack reads the checked file, not the URL",
      tasks["Unpack node_exporter"]["ansible.builtin.unarchive"]["src"].endswith("/{{ node_exporter_archive_name }}"), True)
verify = tasks["Verify node_exporter serves the root filesystem"]["until"]
check("the check at the end reads /'s free space", "'mountpoint=\"/\"'" in verify and "node_filesystem_avail_bytes" in verify, True)
print("node-exporter: " + ("ALL-PASS" if fails == 0 else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_NODEEXP
