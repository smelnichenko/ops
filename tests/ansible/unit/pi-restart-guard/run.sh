#!/bin/bash
# The Pis' restarts never take the last serving copy of a service down (setup-pi-services' Forgejo, Keycloak and
# HAProxy handlers, tasks/versitygw.yml's restart loop): throttle and a loop run the second Pi even after the first
# one's restart failed. Each command as the playbook holds it, run with curl answering for the hosts set up, systemctl
# and sleep stubbed: serving here and not on the other Pi - refused, nothing restarted; serving on both - restarted;
# serving on neither (a first install, a service down already) - restarted.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
python3 - <<'PY'
import os, subprocess, sys, tempfile
import yaml
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))
work = tempfile.mkdtemp()
stubs = os.path.join(work, "bin"); os.makedirs(stubs)
def stub(name, body):
    with open(os.path.join(stubs, name), "w") as f:
        f.write("#!/bin/bash\n" + body)
    os.chmod(os.path.join(stubs, name), 0o755)
# curl: success for a URL whose host is in $UP, or this host's own address once systemctl restarted the service
stub("curl", 'for a in "$@"; do case $a in http*) u=$a;; esac; done\n'
             'h=${u#*://}; h=${h%%[:/]*}\n'
             'case $h in 127.0.0.1|localhost) [ -e "$WORK/restarted" ] && exit 0;; esac\n'
             'for x in $UP; do [ "$x" = "$h" ] && exit 0; done\nexit 22\n')
stub("systemctl", 'echo "$*" >> "$WORK/calls"; case $1 in restart) touch "$WORK/restarted";; esac; exit 0\n')
stub("sleep", "exit 0\n")
pb = yaml.safe_load(open("deploy/ansible/playbooks/setup-pi-services.yml"))
handlers = {h["name"]: h["ansible.builtin.shell"] for h in pb[0]["handlers"] if "ansible.builtin.shell" in h}
vgw = next(t for t in yaml.safe_load(open("deploy/ansible/playbooks/tasks/versitygw.yml"))
           if t.get("name", "").startswith("Restart versitygw"))["ansible.builtin.shell"]
cmds = {n: handlers[n] for n in ("Restart Forgejo", "Restart Keycloak", "Restart HAProxy")}
cmds["Restart versitygw (loop)"] = vgw
SUBST = {"{{ peer_ip }}": "10.0.0.2", "{{ _peer }}": "10.0.0.2", "{{ inventory_hostname }}": "pi1", "{{ item }}": "pi1",
         "{{ vgw_port }}": "9000"}
def run(cmd, up):
    for k, v in SUBST.items():
        cmd = cmd.replace(k, v)
    assert "{{" not in cmd, cmd
    for f in ("restarted", "calls"):
        if os.path.exists(os.path.join(work, f)):
            os.remove(os.path.join(work, f))
    if "127.0.0.1" in up:
        open(os.path.join(work, "restarted"), "w").close()  # serving here before the restart
    env = dict(os.environ, PATH=stubs + ":" + os.environ["PATH"], WORK=work, UP=" ".join(up))
    r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, env=env)
    calls = open(os.path.join(work, "calls")).read() if os.path.exists(os.path.join(work, "calls")) else ""
    return r.returncode, any(c.startswith("restart ") for c in calls.splitlines()), r.stderr
for name, cmd in cmds.items():
    rc, restarted, err = run(cmd, ["127.0.0.1", "localhost"])
    check(f"{name}: serving here, not on the other Pi - refused, nothing restarted",
          (rc != 0, restarted, "REFUSED" in err), (True, False, True))
    rc, restarted, _ = run(cmd, ["127.0.0.1", "localhost", "10.0.0.2"])
    check(f"{name}: serving on both - restarted", (rc, restarted), (0, True))
    rc, restarted, _ = run(cmd, [])
    check(f"{name}: serving on neither (a first install) - restarted", (rc, restarted), (0, True))
print("pi-restart-guard: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
