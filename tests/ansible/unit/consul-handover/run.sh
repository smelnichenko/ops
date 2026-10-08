#!/bin/bash
# setup-consul's rolling restart hands over before each server goes down - each task as the playbook holds it, rendered
# by Ansible's templar, vault and consul stubs answering as Vault 1.21 and Consul 1.20 do: no restart while the Pis'
# tier-0 backup holds its Consul lock (a restart ends its session, and the backup) - read right before the restart; the
# active Vault on the Pi being restarted steps down first - only to a standby the other Pi has, unsealed - and the restart
# waits until the other's is active: run from the Pi holding the root token (setup-vault-pi's init play writes it there
# only), against both Pis' addresses, for pi2 as for pi1; a Vault running there whose status is not read is refused,
# never taken for a standby; each read bounded (no retries), each wait by the clock, not by its count of tries.
# Consul's raft leader on it hands leadership to another server first. Each refuses when the handover does not take.
# Patroni is paused after Vault's handover (it takes nothing of Consul's), before Consul's. All before the restart.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/vu"
echo "ROOT-TOKEN" > "$W/vu/root-token"
# vault: status by address - the restarting Pi's (HERE_IP) from here.json, the other's (OTHER_IP) from other.json, any
# other address unknown; each call's address, token and client bounds recorded; a status answers after STATUS_DELAY;
# a step-down hands over when STEP_TAKES is set
cat > "$W/bin/vault" <<'STUB'
#!/bin/bash
echo "vault $* (token ${VAULT_TOKEN:-none}) addr=${VAULT_ADDR:-} timeout=${VAULT_CLIENT_TIMEOUT:-} retries=${VAULT_MAX_RETRIES:-}" >> "$W/calls"
case "${VAULT_ADDR:-}" in
  "https://$HERE_IP:8200") f=here ;;
  "https://$OTHER_IP:8200") f=other ;;
  *) echo "Error checking seal status: dial tcp: lookup ${VAULT_ADDR:-}: no such host" >&2; exit 1 ;;
esac
case "$*" in
  "status -format=json") sleep "${STATUS_DELAY:-0}"
    [ -e "$W/$f.json" ] || { echo "Error checking seal status: connection refused" >&2; exit 1; }
    cat "$W/$f.json"; grep -q '"sealed": true' "$W/$f.json" && exit 2; exit 0 ;;
  "operator step-down") [ "$f" = here ] && [ "$VAULT_TOKEN" = ROOT-TOKEN ] || exit 2
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
  "operator raft list-peers") sleep "${LIST_DELAY:-0}"; l=$(cat "$W/leader")
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
import json, os, re, subprocess, sys, time
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
pause = next((t for t in every if "patroni-pause.py pause" in str(t.get("ansible.builtin.script"))), None)
restart = next(t for t in every if t.get("name") == "Restarted")
check("the three handovers and the pause found", [x is not None for x in (lock, vault, leader, pause)], [True] * 4)
if None in (lock, vault, leader, pause):
    print("consul-handover: FAILED"); sys.exit(1)
at = every.index
check("in order: Vault's handover, Patroni paused, Consul's handover, the backup's lock read, the restart at once",
      [at(vault) < at(pause) < at(leader) < at(lock), at(lock) + 1 == at(restart)], [True, True])
check("Vault's only on the Pis (none on the third server), and only where it runs",
      ("groups['pis']" in str(vault.get("when")), "_vault_unit" in str(vault.get("when"))), (True, True))
unit = next((t for t in every[:at(vault)] if (t.get("ansible.builtin.systemd") or {}).get("name") == "vault"
             and t.get("register") == "_vault_unit"), None)
check("the Vault unit read before it", unit is not None, True)
# the root token: written by setup-vault-pi's init play, on its hosts only
holders = [p["hosts"] for p in yaml.safe_load(open("deploy/ansible/playbooks/setup-vault-pi.yml")) if "root_token" in str(p)]
check("one play writes the root token (setup-vault-pi's init)", len(holders), 1)
HOSTS = {"pi1": "10.0.0.4", "pi2": "10.0.0.6"}
v = {**(play.get("vars") or {}), "inventory_hostname": "pi1", "_other_pi": "pi2", "groups": {"pis": ["pi1", "pi2"]},
     "hostvars": {n: {"ansible_host": ip} for n, ip in HOSTS.items()}, "consul_handover_seconds": 2}
for me, other_pi in (("pi1", "pi2"), ("pi2", "pi1")):
    check(f"restarting {me}: run where the root token is", render(str(vault.get("delegate_to")),
          **{**v, "inventory_hostname": me, "_other_pi": other_pi}), holders[0] if holders else None)
def run(task, here=None, other=None, leader_is="pi1", me="pi1", seconds=2, **env):
    v["inventory_hostname"], v["_other_pi"] = me, "pi2" if me == "pi1" else "pi1"
    v["consul_handover_seconds"] = seconds
    env = {"HERE_IP": HOSTS[me], "OTHER_IP": HOSTS[v["_other_pi"]], **env}
    for f in ("calls", "here.json", "other.json"):
        if os.path.exists(os.path.join(W, f)):
            os.remove(os.path.join(W, f))
    for f, d in (("here.json", here), ("other.json", other)):
        if d is not None:
            open(os.path.join(W, f), "w").write(json.dumps(d))
    open(os.path.join(W, "leader"), "w").write(leader_is)
    sh = task["ansible.builtin.shell"]
    sh = render(sh if isinstance(sh, str) else sh["cmd"], **v).replace("/etc/vault-unseal", os.path.join(W, "vu"))
    t0 = time.monotonic()
    r = subprocess.run(["bash", "-c", sh], capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W, **env))
    run.took = time.monotonic() - t0
    calls = open(os.path.join(W, "calls")).read() if os.path.exists(os.path.join(W, "calls")) else ""
    return r.returncode, r.stdout + r.stderr, calls
active = {"sealed": False, "ha_enabled": True, "is_self": True}
standby = {"sealed": False, "ha_enabled": True, "is_self": False}
rc, out, calls = run(lock, LOCK="held")
check("the backup holding its lock: refused", (rc, "REFUSED" in out), (1, True))
check("no backup: passes", run(lock, LOCK="free")[0], 0)
rc, out, _ = run(lock, LOCK="error")
check("the lock not readable: refused (never read as free)", (rc, "REFUSED" in out), (1, True))
for me in ("pi1", "pi2"):
    rc, out, calls = run(vault, here=active, other=standby, me=me, STEP_TAKES="1")
    check(f"restarting {me}, Vault active there, a standby on the other: stepped down (the token, {me}'s address), the "
          "other active, then passes", (rc, f"operator step-down (token ROOT-TOKEN) addr=https://{HOSTS[me]}:8200" in calls,
                                        json.load(open(os.path.join(W, "other.json")))["is_self"]), (0, True, True))
    check(f"restarting {me}: every Vault call bounded - a client timeout of at most 10 s, no retries",
          all(re.search(r"timeout=(\d+) retries=0$", c) and int(re.search(r"timeout=(\d+)", c).group(1)) <= 10
              for c in calls.splitlines() if c.startswith("vault ")) and "vault " in calls, True)
token = os.path.join(W, "vu", "root-token")
os.rename(token, token + ".away")
rc, out, calls = run(vault, here=active, other=standby, STEP_TAKES="1")
os.rename(token + ".away", token)
check("no root token where it should be: refused, saying so - no step-down", (rc, "root token" in out, "step-down" in calls),
      (1, True, False))
rc, out, calls = run(vault, here=None, other=standby)
check("Vault running here, its status not read: refused (never taken for a standby)", (rc, "REFUSED" in out), (1, True))
# a slow Vault (each status 1 s): the wait ends by the clock - 4 s after the step-down, give or take a round of reads
# (2 s) - not after 4 rounds (12 s and more)
rc, out, calls = run(vault, here=active, other=standby, seconds=4, STATUS_DELAY="1")
check("a step-down not taken, each read slow: refused when its time is up, not after its count of tries",
      (rc, run.took < 11), (1, True))
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
rc, out, calls = run(leader, leader_is="pi1", seconds=6, LIST_DELAY="1")
check("a transfer not taken, each read slow: refused when its time is up, not after its count of tries",
      (rc, run.took < 11), (1, True))
print("consul-handover: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
