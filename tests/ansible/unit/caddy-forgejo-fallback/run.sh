#!/bin/bash
# git.pmon.dev through either Pi's Forgejo: setup-caddy.yml's Caddyfile, rendered as Ansible renders it for each Pi,
# proxies to this Pi's Forgejo first and the other Pi's after it (lb_policy first, a request retried on the other at
# once, a health check on Forgejo's healthz); the other sites (Nexus runs on the VIP's Pi alone, Keycloak) keep one
# upstream; keepalived's check leaves Forgejo out (both Pis serve it: following it moved the VIP, Nexus with it, on a
# restart past 15 s) and keeps Keycloak, Patroni and versitygw. Caddy's behaviour itself is proven on the copy
# (tests/ansible/copy/forgejo-check.yml: each Pi's Forgejo stopped, git.pmon.dev served through its Caddy).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
python3 - <<'PYCHECK'
import re, sys, yaml, jinja2
fails = 0
def check(name, got, want):
    global fails
    if got == want:
        print("PASS " + name)
    else:
        fails += 1
        print(f"FAIL {name}\n    got:  {got!r}\n    want: {want!r}")
def task(path, name):
    for play in yaml.safe_load(open(path)):
        for t in play.get("tasks", []) or []:
            if t.get("name") == name:
                return play, t
    raise SystemExit(f"{path}: no task named {name!r}")
env = jinja2.Environment(undefined=jinja2.StrictUndefined)
env.filters["difference"] = lambda a, b: [x for x in a if x not in b]  # Ansible's filter, as it computes it
play, t = task("deploy/ansible/playbooks/setup-caddy.yml", "Write Caddyfile")
hosts = {"pi1": {"ansible_host": "192.168.11.4"}, "pi2": {"ansible_host": "192.168.11.6"}}
def caddyfile(me):
    peer = env.from_string(play["vars"].get("peer_ip", ""))  # none: the check says so, no crash
    peer = peer.render(hostvars=hosts, groups={"pis": ["pi1", "pi2"]}, inventory_hostname=me)
    return peer, env.from_string(t["ansible.builtin.copy"]["content"]).render(peer_ip=peer)
def site(text, name):  # the site block's lines (its own braces counted), or None
    m = re.search(r"^" + re.escape(name) + r" \{\n", text, re.M)
    if not m:
        return None
    depth, out = 1, []
    for line in text[m.end():].split("\n"):
        depth += line.count("{") - line.count("}")
        if depth <= 0:
            return out
        out.append(line.strip())
    return out
for me, peer_want in (("pi1", "192.168.11.6"), ("pi2", "192.168.11.4")):
    peer, text = caddyfile(me)
    check(f"{me}: its peer the other Pi's address", peer, peer_want)
    git = site(text, "git.pmon.dev") or []
    check(f"{me}: git.pmon.dev - this Pi's Forgejo first, the other Pi's after it", [l for l in git if l.startswith("reverse_proxy")],
          [f"reverse_proxy localhost:3000 {peer_want}:3000 {{"])
    opts = {l.split()[0]: " ".join(l.split()[1:]) for l in git if l and not l.startswith(("reverse_proxy", "import", "}"))}
    check(f"{me}:   the first that answers (never round-robin: the other Pi's while its own serves would be a Gluster "
          "reader across the LAN for nothing), a refused request tried on the other at once, Forgejo's health checked",
          (opts.get("lb_policy"), "lb_try_duration" in opts, opts.get("health_uri"), "health_interval" in opts),
          ("first", True, "/api/healthz", True))
    for other in ("nexus.pmon.dev", "nexus-docker.pmon.dev", "auth.pmon.dev"):
        lines = site(text, other)
        check(f"{me}: {other} one upstream, this Pi's (no peer)", [l for l in (lines or []) if l.startswith("reverse_proxy")] and
              len([l for l in lines if l.startswith("reverse_proxy")][0].split()), 2)
_, ks = task("deploy/ansible/playbooks/setup-keepalived.yml", "Create health check script")
script = ks["ansible.builtin.copy"]["content"]
probes = [l.strip() for l in script.split("\n") if l.strip().startswith("curl")]
check("keepalived's check: Forgejo left out (both Pis serve it through either Caddy)", [p for p in probes if ":3000" in p], [])
check("  Keycloak, Patroni and versitygw still checked", [re.search(r"localhost:(\d+)", p).group(1) for p in probes],
      ["8080", "8008", "9000"])
print(f"caddy-forgejo-fallback: {'ALL-PASS' if not fails else f'{fails} FAILED'}")
sys.exit(1 if fails else 0)
PYCHECK
