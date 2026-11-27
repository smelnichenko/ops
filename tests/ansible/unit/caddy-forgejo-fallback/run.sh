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
_, kf = task("deploy/ansible/playbooks/setup-keepalived.yml", "Create Forgejo's health check script")
# the check scripts as written, run against a stub curl: it fails for a URL on a port in DOWN, takes SLOW seconds,
# and notes its arguments - which services fail each script, which are left out, the probes at once
import os, subprocess, tempfile, time
stubdir = tempfile.mkdtemp(dir=os.environ.get("TMPDIR"))
# the stub honours -m as curl does: a probe slower than its bound is cut there and fails (curl's 28)
open(os.path.join(stubdir, "curl"), "w").write("""#!/bin/bash
echo "$*" >> "$STUBLOG"
m=; a=("$@")
for ((i = 0; i < ${#a[@]}; i++)); do [ "${a[i]}" = -m ] && m=${a[i+1]}; done
slow=${SLOW:-0}
if [ -n "$m" ] && awk -v s="$slow" -v m="$m" 'BEGIN { exit !(s > m) }'; then sleep "$m"; exit 28; fi
sleep "$slow"
url=${!#}
for port in $DOWN; do case "$url" in *:$port/*) exit 7 ;; esac; done
exit 0
""")
os.chmod(os.path.join(stubdir, "curl"), 0o755)
def run_check(content, down="", slow="0"):
    log = os.path.join(stubdir, "log"); open(log, "w").close()
    t = time.monotonic()
    r = subprocess.run(["bash", "-c", content], env=dict(os.environ, PATH=stubdir + ":" + os.environ["PATH"], DOWN=down,
                       SLOW=slow, STUBLOG=log), capture_output=True, text=True, timeout=60)
    return r.returncode, time.monotonic() - t, open(log).read().splitlines()
services, forgejo = ks["ansible.builtin.copy"]["content"], kf["ansible.builtin.copy"]["content"]
check("keepalived's check: every service answering - passes", run_check(services)[0], 0)
check("  Caddy, Keycloak or versitygw down - fails (each alone)", [run_check(services, port)[0] != 0 for port in ("2019", "8080", "9000")],
      [True, True, True])
check("  Forgejo (a check of its own) and Patroni (nothing through the VIP reaches it) down - still passes",
      [run_check(services, port)[0] for port in ("3000", "8008")], [0, 0])
bounded = lambda c: bool(re.search(r"(^| )--connect-timeout 1( |$)", c) and re.search(r"(^| )-m 2( |$)", c))
rc, took, calls = run_check(services, slow="1.5")
check("  the probes at once (three probes of 1.5 s in under 2.5 s), each bounded (--connect-timeout 1 -m 2), each its URL",
      (rc, took < 2.5, sorted(c.split()[-1] for c in calls), all(bounded(c) for c in calls)),
      (0, True, ["http://127.0.0.1:2019/config/", "http://localhost:8080/realms/master", "http://localhost:9000/health"], True))
rc, took, _ = run_check(services, slow="10")
check("  a hung probe cut at its 2 s: the check fails, well inside keepalived's 4 s timeout", (rc != 0, took < 3), (True, True))
check("Forgejo's own check: its healthz on this Pi (its database too) - fails with it down, passes with it up, bounded",
      (run_check(forgejo, "3000")[0] != 0, run_check(forgejo)[0], [c.split()[-1] for c in run_check(forgejo)[2]],
       all(bounded(c) for c in run_check(forgejo)[2])),
      (True, 0, ["http://localhost:3000/api/healthz"], True))
_, kc = task("deploy/ansible/playbooks/setup-keepalived.yml", "Write Keepalived config")
conf = kc["ansible.builtin.copy"]["content"]
blocks = dict(re.findall(r"vrrp_script (\w+) \{(.*?)\}", conf, re.S))
def opts(b):
    return {k: v for k, v in re.findall(r"^\s*(\w+) (\S+)", b, re.M)}
f, c = opts(blocks.get("check_forgejo", "")), opts(blocks.get("check_services", ""))
check("  Forgejo's window a minute (12 failed checks 5 s apart, its restarts 3-11 s), the others' 15 s; both tracked; each "
      "check's timeout under its interval (its probes 2 s); rise 2",
      ((f.get("interval"), f.get("fall"), f.get("timeout"), f.get("rise")), (c.get("interval"), c.get("fall"), c.get("timeout"), c.get("rise")),
       re.findall(r"track_script \{\s*(.*?)\s*\}", conf, re.S)[0].split()),
      (("5", "12", "4", "2"), ("5", "3", "4", "2"), ["check_services", "check_forgejo"]))
print(f"caddy-forgejo-fallback: {'ALL-PASS' if not fails else f'{fails} FAILED'}")
sys.exit(1 if fails else 0)
PYCHECK
