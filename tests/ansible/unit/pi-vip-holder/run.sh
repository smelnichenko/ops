#!/bin/bash
# The Pi holding the VIP (tasks/pi-vip-holder.yml), each Pi's `ip` stubbed (its own PATH, through its own interpreter)
# and an unreachable Pi's ssh refused: the holder found whichever Pi it is, also while the other is down (the case a
# task pinned to the first Pi failed); no Pi holding it and both holding it refused, saying so; an address the VIP
# is the start of (192.168.11.50 for .5) is not it; the VIP's prefix length whatever it is (production's is /24).
set -u
H=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$H/../../../.." && pwd)
AP=$(command -v ansible-playbook 2>/dev/null \
  || { [ -x "$ROOT/deploy/ansible/venv/bin/ansible-playbook" ] && echo "$ROOT/deploy/ansible/venv/bin/ansible-playbook"; })
[ -x "${AP:-}" ] || { echo "pi-vip-holder: no ansible-playbook found (PATH, repo venv)"; exit 2; }
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
PY=$(command -v python3)
for pi in pi1 pi2; do
  mkdir -p "$W/$pi"
  # `ip -o -4 addr show to <vip>/32` as iproute2 prints it: the line when this Pi has the address ($ADDR_<pi>), nothing else
  printf '#!/bin/sh\necho %s >> "%s/ip-calls"\ncase " $IPFAIL " in *" %s "*) echo "RTNETLINK answers: Operation not permitted" >&2; exit 2 ;; esac\na=$(eval echo "\\${ADDR_%s:-}")\n[ -n "$a" ] && printf "2: eth0    inet %%s scope global secondary proto 0x12 eth0\\\\       valid_lft forever preferred_lft forever\\n" "$a"\nexit 0\n' \
    "$pi" "$W" "$pi" "$pi" > "$W/$pi/ip"
  printf '#!/bin/sh\nPATH="%s:$PATH" exec "%s" "$@"\n' "$W/$pi" "$PY" > "$W/py-$pi"
  # arping -D (iputils): exit 1 when another host answers for the address ($DUP), 0 when none does; its call recorded
  # ARPING_RC: arping failing itself (2: not run, no rights) - not "no reply"
  printf '#!/bin/sh\necho "arping $* on %s" >> "%s/arping-calls"\n[ -z "$ARPING_RC" ] || { echo "arping: socket: Operation not permitted" >&2; exit "$ARPING_RC"; }\n[ -z "$DUP" ]\n' "$pi" "$W" > "$W/$pi/arping"
  chmod +x "$W/$pi/ip" "$W/py-$pi" "$W/$pi/arping"
done
# a Pi that is down: its ssh refused as ssh says it (exit 255) - this harness's own, before the unit runner's fence
printf '#!/bin/sh\necho "ssh: connect to host 192.0.2.1 port 22: Connection timed out" >&2\nexit 255\n' > "$W/ssh"
chmod +x "$W/ssh"
cat > "$W/play.yml" <<PLAY
- hosts: localhost
  gather_facts: false
  vars:
    keepalived_vip: 192.168.11.5
  tasks:
    - ansible.builtin.include_tasks: $ROOT/deploy/ansible/playbooks/tasks/pi-vip-holder.yml
    - ansible.builtin.debug:
        msg: "HOLDER={{ pi_vip_holder }}"
PLAY
inv() {  # the Pis down given as arguments: reached over ssh (refused), the others locally through their own PATH
  printf 'all:\n  hosts:\n    localhost: { ansible_connection: local, ansible_python_interpreter: %s }\n  children:\n    pis:\n      hosts:\n' "$PY"
  for pi in pi1 pi2; do
    case " $* " in
      *" $pi "*) printf '        %s: { ansible_connection: ssh, ansible_host: 192.0.2.1 }\n' "$pi" ;;
      *) printf '        %s: { ansible_connection: local, ansible_python_interpreter: %s }\n' "$pi" "$W/py-$pi" ;;
    esac
  done
}
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi
}
case_() {  # name, want (0 passes / 1 fails), output must contain, pi1's address, pi2's address, [the Pis down]
  local name=$1 want=$2 grep=$3 a1=$4 a2=$5; shift 5
  inv "$@" > "$W/inv.yml"
  out=$(env PATH="$W:$PATH" ADDR_pi1="$a1" ADDR_pi2="$a2" ANSIBLE_NOCOLOR=1 ANSIBLE_HOST_KEY_CHECKING=0 \
        "$AP" -i "$W/inv.yml" "$W/play.yml" 2>&1); rc=$?; [ "$rc" = 0 ] || rc=1
  if [ "$rc" = "$want" ] && grep -qF -- "$grep" <<< "$out"; then echo "PASS $name"
  else echo "FAIL $name (rc $rc, want $want)"; printf '%s\n' "$out" | grep -E 'HOLDER|msg|FAILED|fatal' | tail -4 | sed 's/^/    /'
    fails=$((fails + 1)); fi
}
: > "$W/arping-calls"
case_ "pi1 holds the VIP: pi1" 0 "HOLDER=pi1" 192.168.11.5/24 ""
check "  both Pis read: no duplicate probe" "$(wc -l < "$W/arping-calls")" 0
case_ "pi2 holds the VIP: pi2" 0 "HOLDER=pi2" "" 192.168.11.5/24
case_ "pi1 down, pi2 holds the VIP: pi2 (the first Pi pinned failed here)" 0 "HOLDER=pi2" "" 192.168.11.5/24 pi1
case_ "  a /32 VIP the same" 0 "HOLDER=pi2" "" 192.168.11.5/32 pi1
case_ "no Pi holds it: refused, saying so" 1 "no Pi holds the VIP 192.168.11.5" "" ""
case_ "  pi1 down and pi2 without it: refused, pi1 named unreachable" 1 "unreachable: pi1" "" "" pi1
case_ "both hold it (a split keepalived): refused, both named" 1 "held by pi1 and pi2" 192.168.11.5/24 192.168.11.5/24
case_ "an address the VIP is the start of (.50) is not the VIP" 1 "no Pi holds the VIP" 192.168.11.50/24 ""
# a Pi's read failing is no "holds nothing": refused (the play fails), never read as free
IPFAIL=pi2 case_ "a Pi's read failing: refused, not read as free of the VIP" 1 "Operation not permitted" 192.168.11.5/24 ""
# a Pi reached whose read failed with no rc (sudo's prompt timing out: failed, msg, nothing else) is failed too - read as
# "holds nothing", a split keepalived on it would pass as one holder; the message says why, with no stderr to read
check "a read failing with no rc: refused as failed, its message said" "$(cd "$ROOT" && PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY_NORC'
import sys, yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render, condition
tasks = yaml.safe_load(open("deploy/ansible/playbooks/tasks/pi-vip-holder.yml"))
facts = next(t for t in tasks if "_pi_vip_failed" in str(t.get("ansible.builtin.set_fact", "")))["ansible.builtin.set_fact"]
check = next(t for t in tasks if t.get("name") == "Every Pi reached read")["ansible.builtin.assert"]
read = {"results": [{"item": "pi1", "rc": 0, "stdout": "2: eth0    inet 192.168.11.5/24 scope global eth0"},
                    {"item": "pi2", "failed": True, "msg": "Timeout (12s) waiting for privilege escalation prompt"},
                    {"item": "pi3", "unreachable": True, "msg": "ssh: timed out"}]}
failed = render(facts["_pi_vip_failed"], _pi_vip_read=read)
print([r["item"] for r in failed], condition(check["that"], _pi_vip_failed=failed),
      "privilege escalation" in render(check["fail_msg"], _pi_vip_failed=failed))
PY_NORC
)" "['pi2'] False True"
# a Pi unread (down): the holder asks the network - another host answering for the VIP refuses, none goes on
: > "$W/arping-calls"
case_ "pi1 down: the holder's duplicate probe run, no answer - on" 0 "HOLDER=pi2" "" 192.168.11.5/24 pi1
check "  the probe on the holder, on the VIP's interface" \
  "$(grep -c 'arping -D .*-I eth0 192.168.11.5 on pi2' "$W/arping-calls")" 1
DUP=1 case_ "  another host answering for the VIP (pi1 unread, still holding it): refused" 1 "arping" "" 192.168.11.5/24 pi1
ARPING_RC=2 case_ "  the probe itself failing (not 'no reply'): refused, its error said" 1 "Operation not permitted" "" 192.168.11.5/24 pi1
# tasks/vip-holder-only.yml: a play on the Pis goes on on the VIP's Pi alone - the other ends there
cat > "$W/only.yml" <<PLAY
- hosts: pis
  gather_facts: false
  vars:
    keepalived_vip: 192.168.11.5
  tasks:
    - ansible.builtin.import_tasks: $ROOT/deploy/ansible/playbooks/tasks/vip-holder-only.yml
    - ansible.builtin.debug:
        msg: "WENT ON {{ inventory_hostname }}"
PLAY
only() {  # name, pi1's address, pi2's address, want (the hosts that went on), [the Pis down]
  inv "${@:5}" > "$W/inv.yml"
  out=$(env PATH="$W:$PATH" ADDR_pi1="$2" ADDR_pi2="$3" ANSIBLE_NOCOLOR=1 "$AP" -i "$W/inv.yml" "$W/only.yml" 2>&1)
  got=$(grep -o 'WENT ON pi[12]' <<< "$out" | sort | tr '\n' ' ')
  if [ "$got" = "$4" ]; then echo "PASS $1"; else echo "FAIL $1 (went on: '$got', want '$4')"; fails=$((fails + 1)); fi
}
: > "$W/ip-calls"
only "vip-holder-only: pi1 holds it - pi1 alone goes on" 192.168.11.5/24 "" "WENT ON pi1 "
# one reading for the whole play (each host reading the VIP itself, a move between the reads let two Pis each see a
# different holder): each Pi asked once, not once for every host of the play
check "  one reading: each Pi asked once" "$(sort "$W/ip-calls" | uniq -c | awk '{print $1}' | paste -sd,)" "1,1"
only "  pi2 holds it - pi2 alone goes on" "" 192.168.11.5/24 "WENT ON pi2 "
only "  pi1 down, pi2 holds it - pi2 goes on (the case the change is for)" "" 192.168.11.5/24 "WENT ON pi2 " pi1
# a --limit leaving the holder out: refused, not a green run that did nothing
inv > "$W/inv.yml"
out=$(env PATH="$W:$PATH" ADDR_pi1=192.168.11.5/24 ADDR_pi2= ANSIBLE_NOCOLOR=1 "$AP" -i "$W/inv.yml" --limit pi2 "$W/only.yml" 2>&1); rc=$?
check "  --limit without the holder: refused, nothing run" \
  "$([ "$rc" != 0 ] && echo refused) $(grep -q "outside this run" <<< "$out" && echo said) $(grep -c 'WENT ON' <<< "$out")" \
  "refused said 0"
# the probe's arping installed where the VIP is kept (keepalived's play), and iputils' (Habets' reads -D otherwise)
check "the duplicate probe's arping installed with keepalived, iputils' asserted" "$(cd "$ROOT" && "$PY" - <<'PY_ARP'
import sys, yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition
play = yaml.safe_load(open("deploy/ansible/playbooks/setup-keepalived.yml"))[0]
ts = play["tasks"]
inst = next((t for t in ts if "iputils-arping" in str((t.get("ansible.builtin.apt") or {}).get("name"))), None)
ver = next((t for t in ts if t.get("ansible.builtin.command") == "arping -V"), None)
ok = lambda out, rc=0: not condition(ver["failed_when"], **{ver["register"]: {"rc": rc, "stdout": out, "stderr": ""}})
print(play["hosts"], inst is not None, ver is not None and ts.index(inst) < ts.index(ver)
      and [ok("arping from iputils 20240905"), ok("ARPing 2.25, by Thomas Habets"), ok("", 127)] == [True, False, False])
PY_ARP
)" "pi1,pi2 True True"
# the Vault-admin plays (the root token on both Pis): on the Pis, the VIP's Pi alone going on before anything but
# its input's checks
for book in seed-vault-secrets create-environment delete-environment destroy-environment setup-keycloak-clients \
    setup-vault-cleanup-policy backup-vault-keys; do
  r=$(python3 - "$ROOT/deploy/ansible/playbooks/$book.yml" <<'PYCHK'
import sys, yaml
p = yaml.safe_load(open(sys.argv[1]))[0]
ts = (p.get("pre_tasks") or []) + (p.get("tasks") or [])
at = next((i for i, t in enumerate(ts) if t.get("ansible.builtin.import_tasks") == "tasks/vip-holder-only.yml"), None)
# first, or after nothing but its input's checks (asserts reach no Pi service)
print(p.get("hosts") == "pis" and at is not None and all("ansible.builtin.assert" in t for t in ts[:at]))
PYCHK
)
  check "$book: on the Pis, the VIP's Pi alone" "$r" True
done
# and nothing pins the first Pi any more: groups['pis'] | first (or [0], or groups.pis), a play or a delegation to pi1
# by name - each failed whatever ran there while that Pi was down; the VIP's Pi (this task), or run_once on the play's
# Pis, instead. Pinned by design, and only these: setup-vault-pi (Vault initialised on pi1, its shares and token copied
# from there), setup-nexus (the one-time bootstrap, its sentinel on the shared volume - a re-run skips it), setup-gluster
# (a backup volume created from one peer, its bricks on both - none made with a Pi down), setup-patroni and its
# Keycloak restore (a first install's dump, written on pi1's own disk by the Postgres it replaces)
pinned=$(grep -rnE "groups(\[.pis.\]|\.pis) *(\| *first|\[0\])|^ *(hosts|delegate_to): *[\"']?pi1[\"']? *$" \
  "$ROOT/deploy/ansible" --include='*.yml' | grep -v '/venv/' \
  | grep -vE "/playbooks/(setup-vault-pi|setup-nexus|setup-gluster|setup-patroni|tasks/patroni-keycloak-restore)\.yml:")
check "no playbook pins the first Pi (but Vault's init, Nexus's bootstrap, Gluster's volumes, Patroni's first install)" \
  "$pinned" ""
# every verify play checks each Pi (on pi1 alone it was skipped without a word while pi1 was down) - Gluster's backup
# volumes' aside (their creation's, above)
unverified=$(python3 - "$ROOT/deploy/ansible/playbooks" <<'PYVER'
import glob, sys, yaml
for f in sorted(glob.glob(sys.argv[1] + "/*.yml")):
    for p in yaml.safe_load(open(f)) or []:
        if isinstance(p, dict) and str(p.get("name", "")).startswith("Verify") and p.get("hosts") not in ("pis", "pi1,pi2", "target") \
                and (f.split("/")[-1], p["name"]) != ("setup-gluster.yml", "Verify backup volumes"):
            print(f.split("/")[-1], p["name"], p.get("hosts"))
PYVER
)
check "every verify play on each Pi" "$unverified" ""
# Gluster's status and heal take the volume's cluster-wide lock: a play running them on both Pis at once had one refused
# (pi2 left setup-gluster, its backup volumes never mounted - the full run of 2026-10-16): such a play one Pi at a time,
# and each such read asked again while the lock is held
locked=$(cd "$ROOT" && python3 - <<'PYGL'
import glob, re, yaml
for f in sorted(glob.glob("deploy/ansible/playbooks/*.yml")):
    for p in yaml.safe_load(open(f)) or []:
        if not isinstance(p, dict) or "tasks" not in p:
            continue
        hosts = str(p.get("hosts", ""))
        many = hosts in ("pis", "all") or "," in hosts or ":" in hosts
        for t in p["tasks"] or []:
            cmd = str(t.get("ansible.builtin.shell") or t.get("ansible.builtin.command") or "")
            if many and re.search(r"gluster volume (status|heal)", cmd) and not t.get("run_once"):
                if p.get("serial") != 1 or not t.get("until"):
                    print(f.split("/")[-1], p.get("name"), t.get("name"))
PYGL
)
check "every Gluster status/heal on several Pis one Pi at a time, asked again while locked" "$locked" ""
# Caddy's verify wants each Pi's own Caddy running (the VIP moving to a Pi without one serves nothing) - judged in a run,
# shown in a preview (a first install's has none yet)
check "Caddy's verify: running passes, stopped or absent fails - in a run; a preview never fails" "$(cd "$ROOT" && PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY_CADDY'
import sys, yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render, condition
ver = next(p for p in yaml.safe_load(open("deploy/ansible/playbooks/setup-caddy.yml")) if p.get("name") == "Verify Caddy")
a = next(t for t in ver["tasks"] if "caddy_status" in str(t.get("ansible.builtin.assert", "")))
fails = lambda state, cm=False: condition(a.get("when", True), ansible_check_mode=cm) and not condition(
    a["ansible.builtin.assert"]["that"], caddy_status={"stdout": state})
print(ver["hosts"], [fails("running"), fails("stopped"), fails("unknown"), fails("unknown", True)])
PY_CADDY
)" "pis [False, True, True, False]"
echo "pi-vip-holder: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
exit $((fails > 0))
