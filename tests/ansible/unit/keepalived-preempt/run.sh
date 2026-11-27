#!/bin/bash
# setup-keepalived.yml: both Pis at one priority with preempting allowed - with pi1 at 150 and nopreempt a failing check
# moved nothing (a BACKUP with nopreempt accepts any non-zero advert: the copy, 2026-11-16) - damped (preempt_delay 30,
# Forgejo's check lighter than the services'); a config keepalived has not loaded reloaded one Pi at a time, the VIP's
# holder last (both at once moved the VIP 5 times in 8): pending when this run wrote it or its checksum is not the one
# recorded at the last reload, never where keepalived started now; a config keepalived's --config-test refuses never
# written; before any reload both Pis in the play, the holder read (once again in an election); the holder's reload
# after the other Pi is ready to take the VIP (keepalived running, not holding it, its checks passing - the task's own
# script run against stubs) and the holder read again unchanged; keepalived never restarted (its stop drop-in releases
# Nexus).
# The playbook's own Jinja rendered for each case (the pending truth table, a Pi out of the play), not its text matched.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml, jinja2' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - <<'PY_KAP'
import os, re, subprocess, sys, tempfile
import jinja2, yaml
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
plays = yaml.safe_load(open("deploy/ansible/playbooks/setup-keepalived.yml"))
setup = plays[0]
tasks = setup["tasks"]
by = {t.get("name", ""): (i, t) for i, t in enumerate(tasks)}
env = jinja2.Environment()
env.tests["changed"] = lambda r: bool((r or {}).get("changed"))
env.tests["match"] = lambda v, rx: re.match(rx, v) is not None
env.filters["regex_replace"] = lambda v, rx, rep: re.sub(rx, rep, v)
env.filters["extract"] = lambda k, d: d[k]
def render(expr, **ctx):
    out = env.from_string(expr).render(**ctx).strip()
    return {"True": True, "False": False}.get(out, out)
def bare(expr):  # "{{ x }}" -> x, for a when: or an until: already bare
    m = re.fullmatch(r"\s*\{\{(.*)\}\}\s*", expr, re.S)
    return "{{" + (m.group(1) if m else expr) + "}}"

prio = str(setup["vars"]["vrrp_priority"])
check("one priority on both Pis (an equal priority never preempts a healthy holder)",
      (render(prio, inventory_hostname="pi1"), render(prio, inventory_hostname="pi2")), ("100", "100"))
check("  both start as BACKUP", setup["vars"]["vrrp_state"], "BACKUP")
conf = by["Write Keepalived config"][1]
body = conf["ansible.builtin.copy"]["content"]
blocks = dict(re.findall(r"vrrp_script (\w+) \{(.*?)\}", body, re.S))
weight = lambda b: re.search(r"weight (-?\d+)", blocks.get(b, "")) and re.search(r"weight (-?\d+)", blocks[b]).group(1)
check("  no nopreempt in keepalived.conf: a check that fails moves the VIP; preempt_delay 30 - a restart under it moves nothing",
      ("nopreempt" in body, re.findall(r"preempt_delay (\d+)", body)), (False, ["30"]))
check("  the services weigh 50, Forgejo 20: a Pi with Forgejo alone down (80) still takes the VIP from a holder failing its "
      "services (50)", (weight("check_services"), weight("check_forgejo")), ("-50", "-20"))
check("the config's write registered (its change makes the reload pending), notifying nothing, validated by keepalived's own "
      "--config-test (a config it refuses never installed)",
      (conf.get("register"), "notify" in conf, conf["ansible.builtin.copy"].get("validate")),
      ("_ka_conf", False, "keepalived --config-test -f %s"))

ORDER = ["Keepalived's config as written and as last loaded", "Keepalived started by this run, or its config pending a reload",
         "Its reload pending - the config written now, or not the one loaded last", "Recorded as loaded where keepalived started now with it",
         "Any Pi pending", "Both Pis in the play before any reload - the holder's needs the other ready to take the VIP",
         "The Pi holding the VIP - its reload the last (an election just after a start takes ~4 s - read again once)",
         "The holder as read", "Reload Keepalived where pending - the Pi without the VIP first", "Its new config recorded as loaded there",
         "The other Pi's reload settling", "The other Pi's keepalived running - the holder's reload waits for it",
         "The other Pi ready to take the VIP - not holding it, its checks passing", "Both Pis still in the play before the holder's reload",
         "The Pi holding the VIP read again right before its reload", "Still the Pi read first - a VIP moved meanwhile refuses the reload",
         "Reload Keepalived where pending - the VIP's holder last", "Its new config recorded as loaded there too"]
idx = [by[n][0] if n in by else None for n in ORDER]
check("the reload's steps all there, in their order", None not in idx and idx == sorted(idx), True)
if None in idx:
    print("keepalived-preempt: " + f"{fails} FAILED"); sys.exit(1)
T = {n: by[n][1] for n in ORDER}
N = {n: i for i, n in enumerate(ORDER)}
O = lambda prefix: next(n for n in ORDER if n.startswith(prefix))

# the sums parsed: each value explicit (an empty record is 'none loaded', never the config's)
facts = T[ORDER[1]]["ansible.builtin.set_fact"]
def parsed(lines):
    return render(facts["_ka_conf_sum"], _ka_sums={"stdout_lines": lines}), render(facts["_ka_loaded_sum"], _ka_sums={"stdout_lines": lines})
check("the sums read: the config's and the record's, each its own (an empty or missing record reads empty)",
      [parsed(["conf=aaa", "loaded=aaa"]), parsed(["conf=aaa", "loaded="])], [("aaa", "aaa"), ("aaa", "")])
check("  read in a preview too (check_mode false), failing when the config cannot be read",
      (T[ORDER[0]].get("check_mode"), "|| exit 1" in T[ORDER[0]]["ansible.builtin.shell"]), (False, True))
started = lambda state: render(facts["_ka_started_now"], _keepalived_start={"status": {"ActiveState": state}})
check("  started by this run: keepalived not active before the start task (activating or no status read: not started now)",
      (started("inactive"), started("failed"), started("active"), started("activating"),
       render(facts["_ka_started_now"], _keepalived_start={"status": {}})), (True, True, False, False, False))
pend = T[ORDER[2]]["ansible.builtin.set_fact"]["_ka_pending"]
table = {(s, w, same): render(pend, _ka_started_now=s, _ka_conf={"changed": w}, _ka_conf_sum="a", _ka_loaded_sum="a" if same else "b")
         for s in (True, False) for w in (True, False) for same in (True, False)}
check("pending: written now or not the record's - never where keepalived started now with it",
      table, {(True, True, True): False, (True, True, False): False, (True, False, True): False, (True, False, False): False,
              (False, True, True): True, (False, True, False): True, (False, False, True): False, (False, False, False): True})
check("  where started now: its checksum recorded, under that condition alone",
      (T[ORDER[3]].get("when"), T[ORDER[3]]["ansible.builtin.copy"]["dest"], "_ka_conf_sum" in T[ORDER[3]]["ansible.builtin.copy"]["content"]),
      ("_ka_started_now", "/etc/keepalived/.loaded.sha256", True))
anyp = T[ORDER[4]]["ansible.builtin.set_fact"]["_ka_any_pending"]
hv = lambda a, b: {"pi1": ({"_ka_pending": a} if a is not None else {}), "pi2": ({"_ka_pending": b} if b is not None else {})}
check("any pending: either Pi's in the play - one out of it (dead, a --limit) reloaded by nothing here, not counted",
      [render(anyp.strip(), ansible_play_hosts=[h for h, v in (("pi1", a), ("pi2", b)) if v is not None], hostvars=hv(a, b))
       for a, b in ((False, False), (True, False), (False, True), (False, None), (True, None))],
      [False, True, True, False, True])
gate = T[ORDER[5]]
check("before any reload: both Pis in the play (asserted) - a Pi pending with the other out refuses",
      (gate.get("when"), "groups['pis'] | difference(ansible_play_hosts)" in str((gate.get("ansible.builtin.assert") or {}).get("that"))),
      ("_ka_any_pending", True))
blk = T[O("The Pi holding the VIP - its reload the last")]
check("  the holder from tasks/pi-vip-holder.yml (fails closed), read once again after 10 s when the first read fails",
      ([t.get("ansible.builtin.include_tasks") for t in blk.get("block", [])], [t.get("ansible.builtin.include_tasks") or
       (t.get("ansible.builtin.pause") or {}).get("seconds") for t in blk.get("rescue", [])], blk.get("when")),
      (["tasks/pi-vip-holder.yml"], [10, "tasks/pi-vip-holder.yml"], "_ka_any_pending"))
whens = lambda name: str(T[name].get("when", "True"))
def fires(name, me, holder, pending, anyp=True):
    return render(bare(whens(name)), _ka_pending=pending, _ka_any_pending=anyp, inventory_hostname=me, _ka_holder=holder)
cases = [(me, pend_) for me in ("pi1", "pi2") for pend_ in (True, False)]
R1, R2 = O("Reload Keepalived where pending - the Pi without"), O("Reload Keepalived where pending - the VIP's holder")
C1, C2 = "Its new config recorded as loaded there", "Its new config recorded as loaded there too"
check("the reloads: the Pi without the VIP first, where pending; the holder last, where pending - never a restart",
      ([fires(R1, me, "pi2", p_) for me, p_ in cases], [fires(R2, me, "pi2", p_) for me, p_ in cases],
       T[R1]["ansible.builtin.systemd"]["state"], T[R2]["ansible.builtin.systemd"]["state"]),
      ([True, False, False, False], [False, False, True, False], "reloaded", "reloaded"))
check("  each recorded under its reload's own condition, the written checksum",
      [(T[r].get("when") == T[l].get("when"), T[r]["ansible.builtin.copy"]["dest"], "_ka_conf_sum" in T[r]["ansible.builtin.copy"]["content"])
       for r, l in ((C1, R1), (C2, R2))], [(True, "/etc/keepalived/.loaded.sha256", True)] * 2)
unit, peer = T[O("The other Pi's keepalived running")], T[O("The other Pi ready to take the VIP")]
check("the other Pi before the holder's reload - reloaded or not: a settle, its keepalived running, ready (a minute at most "
      "each) - its readiness not judged in a preview (the scripts it runs may be the run's own, unwritten)",
      ([fires(O("The other Pi's keepalived running"), me, "pi2", p_) for me, p_ in cases],
       [fires(O("The other Pi ready"), me, "pi2", p_) for me, p_ in cases],
       (T[O("The other Pi's reload settling")].get("ansible.builtin.pause") or {}).get("seconds"),
       unit.get("until"), peer.get("until"), render(bare(str(peer.get("when"))), _ka_any_pending=True, inventory_hostname="pi1",
                                                    _ka_holder="pi2", ansible_check_mode=True),
       all(t.get("retries", 0) * t.get("delay", 0) >= 30 for t in (unit, peer))),
      ([True, True, False, False], [True, True, False, False], 5,
       "_ka_peer_unit.status.ActiveState | default('') == 'active'", "_ka_peer.stdout == 'READY'", False, True))
still, reread, same = (T[O("Both Pis still in the play")], T[O("The Pi holding the VIP read again")],
                      T[O("Still the Pi read first")])
check("  then both Pis still in the play, the holder read again and the same - the holder's reload refused otherwise",
      (still.get("when"), "difference(ansible_play_hosts)" in str((still.get("ansible.builtin.assert") or {}).get("that")),
       reread.get("ansible.builtin.include_tasks"), (same.get("ansible.builtin.assert") or {}).get("that")),
      ("_ka_any_pending", True, "tasks/pi-vip-holder.yml", "pi_vip_holder == _ka_holder"))
# nothing pending anywhere (a re-run with nothing to load): every step from the holder's read to the last record skipped -
# rendered with the holder never read (strict: a gate that reaches _ka_holder fails), each gated on a pending fact
strict = jinja2.Environment(undefined=jinja2.StrictUndefined)
def skipped(name):
    try:
        out = strict.from_string(bare(whens(name))).render(_ka_pending=False, _ka_any_pending=False, inventory_hostname="pi1").strip()
    except jinja2.UndefinedError as e:
        return f"undefined: {e}"
    return out == "False"
GATED = ORDER[N[O("Both Pis in the play before any reload")]:]
check("nothing pending: the holder's read, the reloads, the records, the waits and the asserts all skipped - the holder never read",
      {n: skipped(n) for n in GATED}, {n: True for n in GATED})
check("  each step from the holder's read to the last record gated on a pending fact",
      [n for n in GATED if not re.search(r"_ka_(any_)?pending", whens(n))], [])

# the other Pi's readiness, judged by the task's own script (stub ip; the check scripts' paths its stubs): ready with
# keepalived's checks passing and the VIP elsewhere; holding the VIP, or either check failing - not ready, said
work = tempfile.mkdtemp(dir=os.environ.get("TMPDIR"))
stub = os.path.join(work, "bin")
os.makedirs(stub)
open(os.path.join(stub, "ip"), "w").write('#!/bin/bash\n[ -e "' + work + '/holds" ] && echo "2: eth0    inet 192.168.11.5/24 scope global secondary eth0"\nexit 0\n')
for chk in ("check_services", "check_forgejo"):
    open(os.path.join(work, chk + ".sh"), "w").write('#!/bin/bash\n[ ! -e "' + work + '/' + chk + '.fails" ]\n')
    os.chmod(os.path.join(work, chk + ".sh"), 0o755)
os.chmod(os.path.join(stub, "ip"), 0o755)
ready_script = env.from_string(peer["ansible.builtin.shell"]).render(keepalived_vip="192.168.11.5").replace("/etc/keepalived/", work + "/")
def ready(holds=False, fails=()):
    for f in ("holds", "check_services.fails", "check_forgejo.fails"):
        if os.path.exists(os.path.join(work, f)):
            os.remove(os.path.join(work, f))
    if holds:
        open(os.path.join(work, "holds"), "w").close()
    for f in fails:
        open(os.path.join(work, f + ".fails"), "w").close()
    r = subprocess.run(["bash", "-c", ready_script], env=dict(os.environ, PATH=stub + ":" + os.environ["PATH"]), capture_output=True,
                       text=True, timeout=30)
    return r.returncode, r.stdout.strip()
check("the other Pi ready: the VIP elsewhere, its checks passing - READY; holding the VIP, its services' or its Forgejo check "
      "failing - not, said", [ready(), ready(holds=True), ready(fails=["check_services"]), ready(fails=["check_forgejo"])],
      [(0, "READY"), (1, "holds the VIP"), (1, "its services' check fails"), (1, "its Forgejo check fails")])

text = open("deploy/ansible/playbooks/setup-keepalived.yml").read()
check("keepalived never restarted by the play (its stop drop-in releases Nexus, a restart moves the VIP)",
      re.findall(r"name: keepalived\n\s+state: restarted", text), [])
print("keepalived-preempt: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_KAP
