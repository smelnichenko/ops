#!/bin/bash
# Every restart of a service both Pis run (Forgejo, HAProxy, Keycloak) under Consul's lock pi-restart
# (files/pi-restart-locked.sh): the restart handlers' scripts - setup-pi-services', setup-patroni's, Keycloak's restart
# tasks - each run whole inside it (the check of the other Pi, the restart, the wait); the helper itself run against a
# fake consul that behaves as Consul 1.20's does (exit 2 for any failure of the script, exit 0 when it lost the lock and
# killed the script) and says when it holds the lock: the script runs while it is held (never after a lock taken and
# let go), under bash; the helper's exit 0 only when the script's own was - a failed script, a lost lock: 1; the lock not
# had - nothing run; no argument - nothing run; its temporary files gone in every case; the consul it calls the one
# setup-consul.yml installs; installed by a task file both playbooks with such a restart import, before them,
# executable. Each Pi's journal kept on disk, 30 days or 1 GB, journald restarted onto it and its memory flushed. The lock itself is proven on the copy
# (tests/ansible/copy/forgejo-check.yml: a restart on pi2 waits while pi1 holds it, and pi1's script holds it).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
REAL=$PWD
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi; }
python3 - <<'PYCHECK' || fails=$((fails + 1))
import os, re, sys, yaml
fails = 0
def check(name, got, want):
    global fails
    if got == want:
        print("PASS " + name)
    else:
        fails += 1
        print(f"FAIL {name}\n    got:  {got!r}\n    want: {want!r}")
PB = "deploy/ansible/playbooks"
def tasks(play):
    out = []
    def walk(ts):
        for t in ts or []:
            out.append(t)
            for k in ("block", "rescue", "always"):
                walk(t.get(k))
    walk(play.get("tasks")); walk(play.get("handlers"))
    return out
def script(t):
    sh = t.get("ansible.builtin.shell")
    return sh if isinstance(sh, str) else (sh or {}).get("cmd", "") if isinstance(sh, dict) else ""
restarts = []
for f in (f"{PB}/setup-pi-services.yml", f"{PB}/setup-patroni.yml"):
    for play in yaml.safe_load(open(f)):
        restarts += [(f.split("/")[-1], t["name"], script(t)) for t in tasks(play) if re.search(r"systemctl restart (forgejo|haproxy|keycloak)\b", script(t))]
for t in yaml.safe_load(open(f"{PB}/tasks/keycloak-restart.yml")):
    if re.search(r"systemctl restart keycloak\b", script(t)):
        restarts.append(("keycloak-restart.yml", t["name"], script(t)))
check("the restarts found: Forgejo's and HAProxy's handlers, setup-patroni's Forgejo, Keycloak's three",
      sorted((f, n) for f, n, _ in restarts),
      sorted([("setup-pi-services.yml", "Restart Forgejo"), ("setup-pi-services.yml", "Restart HAProxy"),
              ("setup-patroni.yml", "Restart Forgejo"),
              ("keycloak-restart.yml", "Keycloak restarted where pending - a Pi where it does not serve (nothing served there to lose)"),
              ("keycloak-restart.yml", "Keycloak restarted where pending - the Pi without the VIP"),
              ("keycloak-restart.yml", "Keycloak restarted where pending - the Pi with the VIP (logins down while it starts)")]))
# no other playbook restarts them by systemctl (a restart added elsewhere would be outside the lock)
others = []
for root, _, files in os.walk(PB):
    for fn in files:
        p = os.path.join(root, fn)
        if fn.endswith(".yml") and p not in (f"{PB}/setup-pi-services.yml", f"{PB}/setup-patroni.yml", f"{PB}/tasks/keycloak-restart.yml"):
            if re.search(r"systemctl restart (forgejo|haproxy|keycloak)\b", open(p).read()):
                others.append(p)
check("  none elsewhere in the playbooks", others, [])
def locked(s):  # the whole script inside the lock: the helper first, its heredoc closed last - the line exactly
    lines = s.rstrip("\n").split("\n")
    m = re.fullmatch(r"/usr/local/bin/pi-restart-locked (\w+) <<'RESTART'", lines[0]) if lines else None
    return bool(m) and lines[-1] == "RESTART" and sum(1 for l in lines if l.strip() == "RESTART") == 1
check("  every one of them whole inside the lock (the check of the other Pi, the restart, the wait)",
      [(f, n) for f, n, s in restarts if not locked(s)], [])
check("  the restart itself never outside it", [(f, n) for f, n, s in restarts
      if any(re.search(r"systemctl restart", l) for l in s.split("<<'RESTART'")[0].splitlines())], [])
svc = yaml.safe_load(open(f"{PB}/setup-pi-services.yml"))[0]
by = {t.get("name"): t for t in tasks(svc)}
inst = yaml.safe_load(open(f"{PB}/tasks/pi-restart-lock.yml"))[0]
src = re.search(r"'(/files/[^']+)'", str(inst))
check("the helper installed every run (any tag's handler needs it), executable, from a file that is there",
      (inst.get("tags"), (inst.get("ansible.builtin.copy") or {}).get("dest"), (inst.get("ansible.builtin.copy") or {}).get("mode"),
       os.path.isfile(PB + src.group(1)) if src else None),
      (["always"], "/usr/local/bin/pi-restart-locked", "0755", True))
names = [t.get("name") for t in tasks(svc)]
imp = by.get("The Pi restart lock's helper", {})
check("  setup-pi-services imports it every run, before anything that could restart",
      (imp.get("ansible.builtin.import_tasks"), imp.get("tags"), names.index("The Pi restart lock's helper") < names.index("Install system packages")),
      ("tasks/pi-restart-lock.yml", ["always"], True))
pat = yaml.safe_load(open(f"{PB}/setup-patroni.yml"))
helper_play = next((i for i, p in enumerate(pat) if any((t.get("ansible.builtin.import_tasks") == "tasks/pi-restart-lock.yml") for t in tasks(p))), None)
restart_play = next(i for i, p in enumerate(pat) if any(re.search(r"pi-restart-locked", script(t)) for t in tasks(p)))
keycloak_play = next(i for i, p in enumerate(pat) if "keycloak-restart.yml" in str(p))
check("  setup-patroni imports it in a play of both Pis before its restarts (it may run before setup-pi-services)",
      (helper_play is not None and helper_play < min(restart_play, keycloak_play), pat[helper_play]["hosts"] if helper_play is not None else None),
      (True, "pi1,pi2"))
prs = next(script(t) for t in tasks(pat[restart_play]) if re.search(r"pi-restart-locked", script(t)))
check("  its Forgejo restart: the other Pi checked first, 10 min to serve again (its play's own budget for a fresh install)",
      ("! up {{ peer_ip }}" in prs, "+ 600 ))" in prs), (True, True))
consul_path = next(t["ansible.builtin.stat"]["path"] for p in yaml.safe_load(open(f"{PB}/setup-consul.yml")) for t in tasks(p)
                   if isinstance(t.get("ansible.builtin.stat"), dict) and str(t["ansible.builtin.stat"].get("path", "")).endswith("/consul"))
check("  the consul it calls the one setup-consul.yml installs", f'PI_RESTART_CONSUL:-{consul_path}' in open(f"{PB}/files/pi-restart-locked.sh").read(), True)
conf_t = by.get("The journal kept on disk - 30 days, 1 GB at most", {})
conf = conf_t.get("ansible.builtin.copy") or {}
d = (by.get("The journal's settings directory", {}).get("ansible.builtin.file") or {})
h = next((t for t in tasks(svc) if t.get("name") == "Restart journald"), {})
hs = script(h)
check("each Pi's journal on disk, 30 days or 1 GB at most, in a directory made for it; journald restarted onto it",
      (conf.get("dest"), conf.get("mode"), sorted(l for l in (conf.get("content") or "").splitlines() if "=" in l),
       (d.get("path"), d.get("state")), conf_t.get("notify"), [l.strip() for l in hs.splitlines() if l.strip().startswith(("systemctl", "journalctl"))]),
      ("/etc/systemd/journald.conf.d/retention.conf", "0644", ["MaxRetentionSec=30day", "Storage=persistent", "SystemMaxUse=1G"],
       ("/etc/systemd/journald.conf.d", "directory"), "Restart journald", ["systemctl restart systemd-journald", "journalctl --flush"]))
sys.exit(1 if fails else 0)
PYCHECK
# the helper against a fake consul: it says when it holds the lock and when it lets it go, and runs the child between;
# told the lock is not had, it runs nothing
H=$REAL/deploy/ansible/playbooks/files/pi-restart-locked.sh
cat > "$W/consul" <<'FAKE'
#!/bin/bash
# as Consul 1.20's lock: 2 for a failed child, 0 when the lock is lost (the child killed with TERM)
printf '%s\n' "$@" > "$W/args"
[ ! -e "$W/nolock" ] || { echo "Lock acquisition failed: no cluster leader" >&2; exit 1; }
while [ "$#" -gt 0 ] && [ "$1" != pi-restart ]; do shift; done
shift
echo acquired >> "$W/order"
if [ -e "$W/lose" ]; then
  "$@" & child=$!
  for _ in $(seq 50); do [ -e "$W/started" ] && break; sleep 0.1; done
  kill -TERM "$child"; wait "$child"; echo released >> "$W/order"; exit 0
fi
"$@"; rc=$?
echo released >> "$W/order"
[ "$rc" = 0 ] || exit 2
exit 0
FAKE
sed -i "s|\$W|$W|g" "$W/consul"; chmod +x "$W/consul"
run() { PI_RESTART_CONSUL=$W/consul TMPDIR=$W bash "$H" "$@"; }
temps() { find "$W" -name 'pi-restart.*' | wc -l; }
# shellcheck disable=SC2016  # the script's own $(id -u), expanded where it runs
out=$(printf '%s\n' '[[ a == a ]] || exit 9' 'set -o pipefail' "echo body >> $W/order" 'echo "ran as $(id -u)"' | run forgejo); rc=$?
check "the script on stdin run inside the lock (bash: [[ ]], pipefail), exit 0 when it ended 0" "$out rc=$rc" "ran as $(id -u) rc=0"
check "  while the lock is held - taken before it, let go after it" "$(tr '\n' ' ' < "$W/order")" "acquired body released "
check "  the lock: no shell between, pi-restart, its waiting bounded, this host and what is restarted named" \
  "$(head -5 "$W/args" | tr '\n' ' ')" "lock -shell=false -timeout=20m -name=$(hostname) forgejo pi-restart "
check "  its temporary files removed" "$(temps)" "0"
out=$(echo 'exit 7' | run forgejo 2>&1); rc=$?
check "a script that failed (consul lock's own exit 2 says nothing of it): exit 1, the script's exit said" \
  "rc=$rc $(grep -o "the script's exit 7" <<< "$out")" "rc=1 the script's exit 7"
touch "$W/lose"
out=$(echo "touch $W/started; sleep 30; echo SLEPT-THROUGH" | run forgejo 2>&1); rc=$?
check "the lock lost while the script ran (consul lock kills it and exits 0): exit 1 - never a restart taken for done" \
  "rc=$rc $(grep -o "the script's exit 143" <<< "$out") $(grep -c SLEPT-THROUGH <<< "$out") $(temps)" "rc=1 the script's exit 143 0 0"
rm -f "$W/lose"
touch "$W/nolock"
out=$(echo 'touch "'"$W"'/ran"' | run keycloak 2> /dev/null); rc=$?
check "the lock not had (no quorum, no Consul): nothing run, exit 1, no temporary script left" \
  "rc=$rc $([ -e "$W/ran" ] && echo ran || echo 'not run') $(temps)" "rc=1 not run 0"
rm -f "$W/nolock"
out=$(echo 'touch "'"$W"'/ran2"' | run 2> /dev/null); rc=$?
check "no argument (what is restarted): refused, nothing run" "$([ "$rc" != 0 ] && echo refused) $([ -e "$W/ran2" ] && echo ran || echo 'not run') $(temps)" "refused not run 0"
echo "pi-restart-lock: $([ $fails -eq 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails -eq 0 ]
