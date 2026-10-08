#!/bin/bash
# setup-consul's rolling restart hands over before each server goes down - each task as the playbook holds it, rendered
# by Ansible's templar, vault and consul stubs answering as Vault 1.21 and Consul 1.20 do: no restart while the Pis'
# tier-0 backup holds its Consul lock (a restart ends its session, and the backup); the active Vault on the Pi being
# restarted steps down first - only to a standby the other Pi has, unsealed - and the restart waits until the other's is
# active; Consul's raft leader on it hands leadership to another server first. Each refuses when the handover does not
# take. All before the restart.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/vu"
echo "ROOT-TOKEN" > "$W/vu/root-token"
# vault: status by address (127.0.0.1 this Pi's, any other the other Pi's), from here.json / other.json; a step-down
# hands over when STEP_TAKES is set
cat > "$W/bin/vault" <<'STUB'
#!/bin/bash
echo "vault $* (token ${VAULT_TOKEN:-none})" >> "$W/calls"
case "$*" in
  "status -format=json") f=other; [[ $VAULT_ADDR == https://127.0.0.1:8200 ]] && f=here
    [ -e "$W/$f.json" ] || { echo "Error checking seal status: connection refused" >&2; exit 1; }
    cat "$W/$f.json"; grep -q '"sealed": true' "$W/$f.json" && exit 2; exit 0 ;;
  "operator step-down") [ "$VAULT_TOKEN" = ROOT-TOKEN ] || exit 2
    [ -z "${STEP_TAKES:-}${STEP_HALF:-}" ] || sed -i 's/"is_self": true/"is_self": false/' "$W/here.json"
    [ -z "${STEP_TAKES:-}" ] || sed -i 's/"is_self": false/"is_self": true/' "$W/other.json" ;;
esac
STUB
# consul: raft peers with the leader named in $W/leader; a transfer moves it to pi2 when TRANSFER_TAKES is set; the
# backup's lock key by LOCK (held, free, error)
cat > "$W/bin/consul" <<'STUB'
#!/bin/bash
echo "consul $*" >> "$W/calls"
case "$*" in
  "operator raft list-peers") l=$(cat "$W/leader")
    echo "Node    ID    Address            State     Voter  RaftProtocol  Commit Index  Trails Leader By"
    for n in pi1 pi2 target; do s=follower; [ "$n" = "$l" ] && s=leader; echo "$n  id-$n  10.0.0.$n:8300  $s  true  3  100  -"; done ;;
  "operator raft transfer-leader") [ -z "${TRANSFER_TAKES:-}" ] || echo pi2 > "$W/leader" ;;
  "kv get -detailed pi-tier0-backup/.lock")
    case "${LOCK:-free}" in
      held) printf 'CreateIndex      5\nFlags            3304740253564472344\nKey              pi-tier0-backup/.lock\nLockIndex        1\nModifyIndex      5\nSession          0b1e2f3a-aaaa-bbbb-cccc-1234567890ab\nValue            \n' ;;
      free) echo "Error! No key exists at: pi-tier0-backup/.lock" >&2; exit 1 ;;
      error) echo "Error querying Consul agent: connection refused" >&2; exit 1 ;;
    esac ;;
esac
STUB
chmod +x "$W/bin"/*
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import json, os, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render  # noqa: E402
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
def tasks(ts):
    for t in ts or []:
        yield t
        for k in ("block", "rescue", "always"):
            yield from tasks(t.get(k))
play = next(p for p in yaml.safe_load(open("deploy/ansible/playbooks/setup-consul.yml"))
            if p.get("name", "").startswith("Restart the Consul servers"))
every = list(tasks(play["tasks"]))
def find(word):
    return next((t for t in every if word in t.get("name", "")), None)
lock, vault, leader = find("backup holding"), find("Vault stepped down"), find("leadership moved")
restart = next(t for t in every if t.get("name") == "Restarted")
check("the three handovers found", [x is not None for x in (lock, vault, leader)], [True, True, True])
if None in (lock, vault, leader):
    print("consul-handover: FAILED"); sys.exit(1)
check("each before the restart", [every.index(x) < every.index(restart) for x in (lock, vault, leader)], [True] * 3)
check("Vault's only on the Pis (none on the third server)", "groups['pis']" in str(vault.get("when")), True)
v = {**(play.get("vars") or {}), "inventory_hostname": "pi1", "_other_pi": "pi2",
     "hostvars": {"pi2": {"ansible_host": "10.0.0.6"}}, "consul_handover_seconds": 2}
def run(task, here=None, other=None, leader_is="pi1", **env):
    for f in ("calls", "here.json", "other.json"):
        if os.path.exists(os.path.join(W, f)):
            os.remove(os.path.join(W, f))
    for f, d in (("here.json", here), ("other.json", other)):
        if d is not None:
            open(os.path.join(W, f), "w").write(json.dumps(d))
    open(os.path.join(W, "leader"), "w").write(leader_is)
    sh = task["ansible.builtin.shell"]
    sh = render(sh if isinstance(sh, str) else sh["cmd"], **v).replace("/etc/vault-unseal", os.path.join(W, "vu"))
    r = subprocess.run(["bash", "-c", sh], capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W, **env))
    calls = open(os.path.join(W, "calls")).read() if os.path.exists(os.path.join(W, "calls")) else ""
    return r.returncode, r.stdout + r.stderr, calls
active = {"sealed": False, "ha_enabled": True, "is_self": True}
standby = {"sealed": False, "ha_enabled": True, "is_self": False}
rc, out, calls = run(lock, LOCK="held")
check("the backup holding its lock: refused", (rc, "REFUSED" in out), (1, True))
check("no backup: passes", run(lock, LOCK="free")[0], 0)
rc, out, _ = run(lock, LOCK="error")
check("the lock not readable: refused (never read as free)", (rc, "REFUSED" in out), (1, True))
rc, out, calls = run(vault, here=active, other=standby, STEP_TAKES="1")
check("Vault active here, a standby there: stepped down, the other active, then passes",
      (rc, "operator step-down (token ROOT-TOKEN)" in calls, json.load(open(os.path.join(W, "other.json")))["is_self"]),
      (0, True, True))
rc, out, calls = run(vault, here=standby, other=active)
check("Vault not active here: nothing done", (rc, "step-down" in calls), (0, False))
rc, out, calls = run(vault, here=active, other={**standby, "sealed": True})
check("the other Pi's Vault sealed: refused before any step-down", (rc, "REFUSED" in out, "step-down" in calls), (1, True, False))
rc, out, calls = run(vault, here=active, other=None)
check("the other Pi's Vault unreachable: refused before any step-down", (rc, "step-down" in calls), (1, False))
rc, out, calls = run(vault, here=active, other=standby)
check("a step-down that does not take: refused", (rc, "REFUSED" in out), (1, True))
rc, out, calls = run(vault, here=active, other=standby, STEP_HALF="1")
check("stepped down here, the other never active (no active Vault): refused", (rc, "REFUSED" in out), (1, True))
rc, out, calls = run(leader, leader_is="pi1", TRANSFER_TAKES="1")
check("Consul's leader here: leadership moved first, then passes", (rc, "transfer-leader" in calls, open(os.path.join(W, "leader")).read().strip()),
      (0, True, "pi2"))
rc, out, calls = run(leader, leader_is="pi2")
check("not the leader: nothing done", (rc, "transfer-leader" in calls), (0, False))
rc, out, calls = run(leader, leader_is="pi1")
check("a transfer that does not take: refused", (rc, "REFUSED" in out), (1, True))
print("consul-handover: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
