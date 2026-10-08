#!/bin/bash
# The three playbooks that pause Patroni around their work (setup-consul, setup-patroni, upgrade-patroni) - their
# not-paused check, pause and resume as the files hold them, against consul and patronictl stubs that answer as the real
# ones do: Consul's KV (ModifyIndex, check-and-set - a CAS delete of a missing key succeeds, measured on Consul 1.20.6)
# holding Patroni's DCS (the config's pause, each member's own), and patronictl 4.1's answers, its exit 0 on a failed
# pause or resume among them (ctl.py toggle_pause, read on pi1).
#
# Each pause puts a marker naming the playbook, the time and a nonce, check-and-set - one only: a marker there already
# refuses the run before any pause. A pause is proven by the DCS - the config and every member paused - not by
# patronictl's exit or its "Success": one not proven undoes what it may have done, then deletes its marker; one someone
# else made meanwhile ("already paused") is left as it is; a DCS unread after the request is not proven either. The
# resume reads the run's own marker first - a marker not its own, or none, means the pause is not its own: refused,
# nothing resumed - then resumes, proven the same way, and only then deletes its marker, check-and-set: one that does not
# take, or a DCS unread meanwhile, keeps the marker as it was (its index the pause said), so a retry resumes. The index
# is read from the pause's output as Ansible gives it - ansible.builtin.script runs under ssh -tt, its lines ending CR LF.
# The not-paused check refuses a paused config or member and a DCS it cannot read, naming the run a marker names (a
# Ctrl-C skips Ansible's always:); a marker of another shape is not echoed; no member at all says Patroni runs nowhere.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/kv"
printf 'scope: pg\nname: pi1\n' > "$W/patroni.yml"
# consul kv: a key's value in kv/<key>, its ModifyIndex in kv/<key>.idx, its name in kv/<key>.key (a counter in kv/.n)
cat > "$W/bin/consul" <<'STUB'
#!/usr/bin/env python3
import os, sys
W = os.environ["W"]
open(os.path.join(W, "calls"), "a").write("consul " + " ".join(sys.argv[1:]) + "\n")
# CONSUL_BLIP_AFTER: the first call after that one (e.g. "patronictl resume") fails - once
blip = os.environ.get("CONSUL_BLIP_AFTER")
if blip and not os.path.exists(os.path.join(W, "blipped")) and any(  # a call before this one (its own line is last)
        c.startswith(blip) for c in open(os.path.join(W, "calls")).read().splitlines()[:-1]):
    open(os.path.join(W, "blipped"), "w").close()
    sys.exit("Error querying Consul agent: Unexpected response code: 500 (No cluster leader)")
# CONSUL_DOWN_AFTER: every call after that one fails
down = os.environ.get("CONSUL_DOWN_AFTER")
if down and any(c.startswith(down) for c in open(os.path.join(W, "calls")).read().splitlines()[:-1]):
    sys.exit("Error querying Consul agent: Unexpected response code: 500 (No cluster leader)")
if os.environ.get("CONSUL_DOWN"):
    sys.exit("Error querying Consul agent: Get \"http://127.0.0.1:8500/v1/kv/x\": dial tcp 127.0.0.1:8500: connect: "
             "connection refused")
a = sys.argv[1:]
assert a[0] == "kv", a
op, a = a[1], a[2:]
flags = {}
while a and a[0].startswith("-"):
    k, _, v = a.pop(0).lstrip("-").partition("=")
    flags[k] = v
KV = os.path.join(W, "kv")
f = lambda key: os.path.join(KV, key.replace("/", "_"))  # noqa: E731
def put(key, value):
    n = int(open(os.path.join(KV, ".n")).read()) + 1 if os.path.exists(os.path.join(KV, ".n")) else 11
    open(os.path.join(KV, ".n"), "w").write(str(n))
    open(f(key), "w").write(value); open(f(key) + ".idx", "w").write(str(n)); open(f(key) + ".key", "w").write(key)
if op == "put":
    key, value = a
    if "cas" in flags and flags["modify-index"] == "0" and os.path.exists(f(key)):
        sys.exit(f"Error! Did not write to {key}: CAS performed with index=0 and key already exists.")
    put(key, value)
    print(f"Success! Data written to: {key}")
elif op == "get" and "recurse" in flags:
    for name in sorted(os.listdir(KV)):
        if name.endswith(".key") and open(os.path.join(KV, name)).read().startswith(a[0]):
            key = open(os.path.join(KV, name)).read()
            print(f"{key}:{open(f(key)).read()}")
elif op == "get":
    key = a[0]
    if not os.path.exists(f(key)):
        sys.exit(f"Error! No key exists at: {key}")
    if "detailed" in flags and os.environ.get("CONSUL_SWAPPED"):
        print(f"ModifyIndex      99\nValue            setup-patroni 2026-10-08T02:00:00Z ef56ab78")
    elif "detailed" in flags:
        print(f"CreateIndex      {open(f(key) + '.idx').read()}\nFlags            0\nKey              {key}\n"
              f"LockIndex        0\nModifyIndex      {open(f(key) + '.idx').read()}\nSession          -\n"
              f"Value            {open(f(key)).read()}")
    else:
        print(open(f(key)).read())
elif op == "delete":
    key = a[0]
    if os.environ.get("DELETE_FAILS"):  # Consul answering 500 to the delete alone
        sys.exit(f"Error! Failed to delete key {key}: Unexpected response code: 500")
    if "cas" in flags and os.path.exists(f(key)) and open(f(key) + ".idx").read() != flags["modify-index"]:
        sys.exit(f"Error! Did not delete key {key}: CAS failed")
    for x in ("", ".idx", ".key"):
        if os.path.exists(f(key) + x):
            os.remove(f(key) + x)
    print(f"Success! Deleted key: {key}")
STUB
# patronictl: its DCS in the consul stub's store (service/pg/config, service/pg/members/<name>); PAUSE_MODE and
# RESUME_MODE pick what Patroni 4.1 answers - ok, failed (a member's 503: nothing changed), lags (the config changed, the
# last member not: "didn't recognized"), lie (the config changed, the last member not, "Success" all the same)
cat > "$W/bin/patronictl" <<'STUB'
#!/usr/bin/env python3
import json, os, sys
W = os.environ["W"]
args = [x for x in sys.argv[1:] if not x.startswith("-c") and not x.endswith(".yml")]
open(os.path.join(W, "calls"), "a").write("patronictl " + " ".join(args) + "\n")
if os.environ.get("CONSUL_DOWN"):
    sys.exit("Error: ConsulException: connection refused")
KV = os.path.join(W, "kv")
def path(key):
    return os.path.join(KV, key.replace("/", "_"))
def get(key):
    return json.loads(open(path(key)).read())
def put(key, d):
    open(path(key), "w").write(json.dumps(d))
members = sorted(n[len("service_pg_members_"):-4] for n in os.listdir(KV) if n.startswith("service_pg_members_")
                 and n.endswith(".key"))
config = get("service/pg/config")
if args[:1] == ["list"]:
    print("+ Cluster: pg")
    if config.get("pause"):
        print(" Maintenance mode: on")
    sys.exit(0)
want = args[:1] == ["pause"]
mode = os.environ.get("PAUSE_MODE" if want else "RESUME_MODE", "ok")
if bool(config.get("pause")) == want:
    sys.exit(f"Error: Cluster is {'already' if want else 'not'} paused")
word = "pause" if want else "resume"
if mode == "failed":
    print(f"Failed: {word} cluster management status code=503, (no leader)")
    sys.exit(0)
config["pause"] = True if want else None
put("service/pg/config", {k: v for k, v in config.items() if v is not None})
for i, name in enumerate(members):
    m = get(f"service/pg/members/{name}")
    if mode in ("lags", "lie") and i == len(members) - 1:
        continue
    m["pause"] = True if want else None
    put(f"service/pg/members/{name}", {k: v for k, v in m.items() if v is not None})
print(f"'{word}' request sent, waiting until it is recognized by all nodes")
if mode == "lags":
    print(f"{members[-1]} members didn't recognized pause state after 10 seconds")
else:
    print(f"Success: cluster management is {'paused' if want else 'resumed'}")
STUB
chmod +x "$W/bin"/*
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import json, os, shlex, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render  # noqa: E402
W = os.environ["W"]
KV = os.path.join(W, "kv")
KEY = os.path.join(KV, "ansible_patroni-paused-by")
fails = 0
def check(name, ok, detail=""):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f"\n  {detail}"))
def tasks(items):
    for t in items or []:
        yield t
        for k in ("block", "rescue", "always"):
            yield from tasks(t.get(k))
def text(t):
    for m in ("ansible.builtin.command", "ansible.builtin.shell", "ansible.builtin.script"):
        a = t.get(m)
        if a is not None:
            return a if isinstance(a, str) else a.get("cmd", "")
    return ""
def kv_put(key, value, idx):
    p = os.path.join(KV, key.replace("/", "_"))
    open(p, "w").write(value)
    open(p + ".idx", "w").write(str(idx))
    open(p + ".key", "w").write(key)
def state(paused=False, members_paused=None, marker=None, idx=7, members=("pi1", "pi2")):
    """The DCS: the config's pause, each member's (pi1, pi2: as `paused` unless given); the marker at index `idx`."""
    for f in os.listdir(KV):
        os.remove(os.path.join(KV, f))
    open(os.path.join(W, "calls"), "w").close()
    os.path.exists(os.path.join(W, "blipped")) and os.remove(os.path.join(W, "blipped"))
    kv_put("service/pg/config", json.dumps({"ttl": 30, "loop_wait": 10, **({"pause": True} if paused else {})}), 3)
    for name, p in zip(members, members_paused or (paused, paused)):
        kv_put(f"service/pg/members/{name}", json.dumps({"role": "primary" if name == "pi1" else "replica",
                                                         **({"pause": True} if p else {})}), 4)
    if marker is not None:
        kv_put("ansible/patroni-paused-by", marker, idx)
def dcs():
    """(config paused, [each member paused])."""
    get = lambda k: json.loads(open(os.path.join(KV, k.replace("/", "_"))).read())  # noqa: E731
    return bool(get("service/pg/config").get("pause")), [bool(get(f"service/pg/members/{n}").get("pause"))
                                                          for n in ("pi1", "pi2")]
def run(task, env=None, fresh=True, **st):
    """The task as Ansible runs it: a shell's text, rendered; a script's command line, rendered, on python3. `fresh`
    False: on the DCS the last run left (a retry)."""
    if fresh:
        state(**st)
    else:
        open(os.path.join(W, "calls"), "w").close()
    cmd = render(text(task), patronictl=f"patronictl -c {W}/patroni.yml", playbook_dir="deploy/ansible/playbooks")
    argv = ["bash", "-c", cmd] if "ansible.builtin.script" not in task else ["python3", *shlex.split(cmd)]
    r = subprocess.run(argv, capture_output=True, text=True, env=dict(
        os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], PATRONI_CONFIG=f"{W}/patroni.yml",
        PATRONI_PAUSE_WAIT="0.3", PATRONI_PAUSE_POLL="0.05", **(env or {})))
    calls = open(os.path.join(W, "calls")).read().splitlines()
    return r, calls, open(KEY).read() if os.path.exists(KEY) else None
def marker_idx():
    return open(KEY + ".idx").read() if os.path.exists(KEY + ".idx") else None
def acts(calls):
    """patronictl's pause/resume and consul's KV writes, in their order."""
    return [" ".join(c.split()[:2]) if c.startswith("patronictl") else " ".join(c.split()[:3]) for c in calls
            if c.split()[:2] in (["patronictl", "pause"], ["patronictl", "resume"])
            or c.split()[:3] in (["consul", "kv", "put"], ["consul", "kv", "delete"])]
for book in ("setup-consul", "setup-patroni", "upgrade-patroni"):
    every = [t for play in yaml.safe_load(open(f"deploy/ansible/playbooks/{book}.yml")) for t in tasks(play.get("tasks"))]
    pause = [t for t in every if ("pause --wait" in text(t) and "resume --wait" not in text(t))
             or "patroni-pause.py pause" in text(t)]
    resume = [t for t in every if "resume --wait" in text(t) or "patroni-pause.py resume" in text(t)]
    checks = [t for t in every if ("Maintenance mode" in text(t) and "REFUSED" in text(t))
              or "patroni-pause.py check" in text(t)]
    check(f"{book}: one pause, one resume, one not-paused check", (len(pause), len(resume), len(checks)) == (1, 1, 1),
          (len(pause), len(resume), len(checks)))
    if not (pause and resume and checks):
        continue
    p, rs, ck = pause[0], resume[0], checks[0]
    reg = p.get("register")
    def renv(out):
        return {n: str(render(str(x), **{reg: {"stdout": out}})) for n, x in (rs.get("environment") or {}).items()}
    # --- the pause
    r, calls, kv = run(p)
    check(f"{book}: the pause puts its marker (check-and-set: the playbook, the time, a nonce), then pauses - every "
          "member paused; its index said", r.returncode == 0 and kv is not None and kv.startswith(book + " ")
          and len(kv.split()) == 3 and f"MARKER 11" in r.stdout and acts(calls)[:2] == ["consul kv put", "patronictl pause"]
          and dcs() == (True, [True, True]), (r.returncode, r.stdout, r.stderr, calls, kv))
    r, calls, kv = run(p, env={"CONSUL_BLIP_AFTER": "consul kv put"})
    check(f"{book}: its marker's read-back failing once (Consul's leader moving): read again - paused, its index said",
          r.returncode == 0 and "MARKER 11" in r.stdout and dcs() == (True, [True, True]),
          (r.returncode, r.stdout, r.stderr, calls, kv))
    r, calls, kv = run(p, env={"CONSUL_DOWN_AFTER": "consul kv put"})
    check(f"{book}: its marker never read back: refused, nothing paused, the marker named (to delete once Consul answers)",
          r.returncode != 0 and "not read back" in r.stdout and kv is not None and kv in r.stdout
          and "patronictl pause" not in acts(calls), (r.returncode, r.stdout, r.stderr, calls, kv))
    r, calls, kv = run(p, env={"CONSUL_SWAPPED": "1"})
    check(f"{book}: the marker read back is not the one it put: refused - nothing paused",
          r.returncode != 0 and "not the one this run put" in r.stdout and "patronictl pause" not in acts(calls),
          (r.returncode, r.stdout, r.stderr, calls, kv))
    r, calls, kv = run(p, marker="setup-consul 2026-10-08T01:00:00Z ab12cd34")
    check(f"{book}: a marker there already: refused before any pause, the marker left as it was",
          r.returncode != 0 and "REFUSED" in r.stdout + r.stderr and "patronictl pause" not in acts(calls)
          and kv == "setup-consul 2026-10-08T01:00:00Z ab12cd34", (r.returncode, r.stdout, r.stderr, calls, kv))
    # someone paused it between the check and this pause: patronictl refuses (exit 1) - theirs, not undone
    r, calls, kv = run(p, paused=True)
    check(f"{book}: paused meanwhile by someone else: fails, its own marker deleted, their pause left",
          r.returncode != 0 and kv is None and "patronictl resume" not in acts(calls) and dcs() == (True, [True, True]),
          (r.returncode, r.stdout, r.stderr, calls, kv))
    r, calls, kv = run(p, env={"PAUSE_MODE": "failed"})
    check(f"{book}: patronictl exits 0 on 'Failed: ... status code=503': the pause fails, its marker deleted",
          r.returncode != 0 and kv is None and dcs() == (False, [False, False]),
          (r.returncode, r.stdout, r.stderr, calls, kv))
    for mode, says in (("lags", "a member not recognizing it (exit 0)"), ("lie", "'Success' with a member unpaused")):
        r, calls, kv = run(p, env={"PAUSE_MODE": mode})
        check(f"{book}: {says}: the pause fails - undone (resumed, every member), then its marker deleted",
              r.returncode != 0 and kv is None and dcs() == (False, [False, False])
              and acts(calls)[-2:] == ["patronictl resume", "consul kv delete"],
              (r.returncode, r.stdout, r.stderr, calls, kv))
    r, calls, kv = run(p, env={"CONSUL_BLIP_AFTER": "patronictl pause"})
    check(f"{book}: the DCS unread once after the pause request: not proven - undone (resumed, every member), then its "
          "marker deleted", r.returncode != 0 and kv is None and dcs() == (False, [False, False])
          and acts(calls)[-2:] == ["patronictl resume", "consul kv delete"], (r.returncode, r.stdout, r.stderr, calls, kv))
    r, calls, kv = run(p, env={"PAUSE_MODE": "lags", "RESUME_MODE": "failed"})
    check(f"{book}: a failed pause whose undoing fails too: its marker kept (it names the run), said so",
          r.returncode != 0 and kv is not None and kv.startswith(book + " ") and "STILL PAUSED" in r.stdout,
          (r.returncode, r.stdout, r.stderr, calls, kv))
    # --- the resume, given the pause's output
    mine = f"{book} 2026-10-08T01:00:00Z ab12cd34"
    r, calls, kv = run(rs, env=renv("PAUSED: ...\nMARKER 7"), paused=True, marker=mine, idx=7)
    check(f"{book}: the resume, its own marker read first: resumes - every member - then deletes the marker",
          r.returncode == 0 and kv is None and dcs() == (False, [False, False])
          and acts(calls) == ["patronictl resume", "consul kv delete"], (r.returncode, r.stdout, r.stderr, calls, kv))
    # ansible.builtin.script runs under ssh -tt: the pause's stdout as the register holds it ends its lines CR LF
    r, calls, kv = run(rs, env=renv("PAUSED: config paused, pi1 paused, pi2 paused\r\nMARKER 7\r\n"), paused=True,
                       marker=mine, idx=7)
    check(f"{book}: the pause's output with CR LF line ends (ssh -tt): its index read, resumed",
          r.returncode == 0 and kv is None and dcs() == (False, [False, False]), (r.returncode, r.stdout, r.stderr, calls, kv))
    r, calls, kv = run(rs, env={**renv("MARKER 7"), "CONSUL_BLIP_AFTER": "patronictl resume"}, paused=True, marker=mine,
                       idx=7)
    check(f"{book}: the DCS unread once after the resume request: fails, its marker kept as it was (its index)",
          r.returncode != 0 and kv == mine and marker_idx() == "7", (r.returncode, r.stdout, r.stderr, calls, kv))
    r, calls, kv = run(rs, env=renv("MARKER 7"), fresh=False)
    check(f"{book}: ... and its retry resumes, the marker deleted",
          r.returncode == 0 and kv is None and dcs() == (False, [False, False]), (r.returncode, r.stdout, r.stderr, calls, kv))
    r, calls, kv = run(rs, env={**renv("MARKER 7"), "DELETE_FAILS": "1"}, paused=True, marker=mine, idx=7)
    check(f"{book}: resumed, its marker not deleted: fails, said (the next run's pause refuses until it is gone)",
          r.returncode != 0 and "RESUMED" in r.stdout and "consul kv delete" in r.stdout and kv == mine
          and dcs() == (False, [False, False]), (r.returncode, r.stdout, r.stderr, calls, kv))
    r, calls, kv = run(rs, env=renv("MARKER 7"), paused=True, marker="setup-patroni 2026-10-08T02:00:00Z ef56ab78", idx=9)
    check(f"{book}: a marker put since (not its own): refused - nothing resumed, the marker left",
          r.returncode != 0 and kv == "setup-patroni 2026-10-08T02:00:00Z ef56ab78" and "patronictl resume" not in acts(calls)
          and dcs()[0], (r.returncode, r.stdout, r.stderr, calls, kv))
    r, calls, kv = run(rs, env=renv("MARKER 7"), paused=True)
    check(f"{book}: its marker gone (deleted by hand): refused - nothing resumed (Consul's CAS delete of a missing key "
          "succeeds)", r.returncode != 0 and "gone" in r.stdout and "patronictl resume" not in acts(calls) and dcs()[0],
          (r.returncode, r.stdout, r.stderr, calls, kv))
    r, calls, kv = run(rs, env=renv("MARKER 7"))
    check(f"{book}: its marker gone, the cluster not paused (resumed and cleared already): nothing to do - passes, said",
          r.returncode == 0 and "NOTHING TO RESUME" in r.stdout and "patronictl resume" not in acts(calls),
          (r.returncode, r.stdout, r.stderr, calls, kv))
    # its marker gone, the config resumed, a member still paused (Patroni's resume half taken): no "nothing to resume" -
    # refused, the member named
    r, calls, kv = run(rs, env=renv("MARKER 7"), members_paused=(False, True))
    check(f"{book}: its marker gone, a member still paused: refused - never 'nothing to resume'",
          r.returncode != 0 and "NOTHING TO RESUME" not in r.stdout and "patronictl resume" not in acts(calls),
          (r.returncode, r.stdout, r.stderr, calls, kv))
    # the task retried: one failed read (a Consul blip, likely while the block's own failure is Consul's) is no paused
    # cluster for good - the marker kept until the resume is proven makes a retry safe
    got = (bool(rs.get("register")), int(rs.get("retries", 0)) >= 3,
           str(rs.get("until", "")).replace(" ", "") == f"{rs.get('register')}.rc==0")
    check(f"{book}: the resume task retried (register, retries, until its exit 0)", got == (True, True, True), got)
    r, calls, kv = run(rs, env=renv("PAUSE FAILED: ..."), paused=True, marker=mine, idx=7)
    check(f"{book}: no MARKER in the pause's output: refused - nothing resumed, nothing deleted",
          r.returncode != 0 and "no MARKER" in r.stdout and kv == mine and "patronictl resume" not in acts(calls)
          and dcs()[0],
          (r.returncode, r.stdout, r.stderr, calls, kv))
    r, calls, kv = run(rs, env={**renv("MARKER 7"), "RESUME_MODE": "lags"}, paused=True, marker=mine, idx=7)
    check(f"{book}: a resume a member does not take (exit 0): fails, its marker kept as it was (its index)",
          r.returncode != 0 and kv == mine and marker_idx() == "7" and "STILL PAUSED" in r.stdout,
          (r.returncode, r.stdout, r.stderr, calls, kv))
    # --- the not-paused check
    r, calls, kv = run(ck, paused=True, marker="upgrade-patroni 2026-10-07T23:00:00Z")
    check(f"{book}: paused, an older run's marker: refused, naming the run, asking whether it still runs",
          r.returncode == 1 and "upgrade-patroni 2026-10-07T23:00:00Z" in r.stdout and "no longer running" in r.stdout,
          (r.returncode, r.stdout))
    r, calls, kv = run(ck, paused=True, marker="setup-consul 2026-10-08T01:00:00Z ab12cd34")
    check(f"{book}: paused, a marker with its nonce: refused, naming the run", r.returncode == 1
          and "setup-consul 2026-10-08T01:00:00Z ab12cd34" in r.stdout and "no longer running" in r.stdout,
          (r.returncode, r.stdout))
    r, calls, kv = run(ck, paused=True, marker="$(reboot) run patronictl remove")
    check(f"{book}: paused, a marker of another shape: refused, not echoed", r.returncode == 1
          and "reboot" not in r.stdout and "another shape" in r.stdout, (r.returncode, r.stdout))
    r, calls, kv = run(ck, paused=True, marker="upgrade-patroni 2026-10-07T23:00:00Z $(reboot)")
    check(f"{book}: paused, a run's shape with more after it: refused, not echoed", r.returncode == 1
          and "reboot" not in r.stdout and "another shape" in r.stdout, (r.returncode, r.stdout))
    r, calls, kv = run(ck, paused=True)
    check(f"{book}: paused, no marker (someone's maintenance): refused, no run named", r.returncode == 1
          and "REFUSED" in r.stdout and "no longer running" not in r.stdout, (r.returncode, r.stdout))
    r, calls, kv = run(ck, members_paused=(False, True))
    check(f"{book}: a member still paused (the config not - a resume half taken): refused", r.returncode == 1
          and "REFUSED" in r.stdout, (r.returncode, r.stdout))
    r, calls, kv = run(ck, env={"CONSUL_DOWN": "1"})
    check(f"{book}: the DCS not readable: refused", r.returncode == 1 and "REFUSED" in r.stdout, (r.returncode, r.stdout))
    r, calls, kv = run(ck, members=())
    check(f"{book}: no Patroni member in the DCS: refused, saying Patroni runs on no Pi - no resume advised",
          r.returncode == 1 and "runs on no Pi" in r.stdout and "patronictl resume" not in r.stdout, (r.returncode, r.stdout))
    r, calls, kv = run(ck)
    check(f"{book}: not paused: passes", r.returncode == 0, (r.returncode, r.stdout))
print("patroni-pause-marker: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
