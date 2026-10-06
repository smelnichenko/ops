#!/bin/bash
# The production rollout's ledger (scripts/upgrade-production.py): which phase of which step may run, given the
# events so far - each refusal against the real step files where it matters (their branch order and wave0 lines),
# the soak, and the own-change hash the merge compares with the full run's proof.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
python3 - <<'EOF'
import datetime
import importlib.machinery
import importlib.util
import os
import sys

loader = importlib.machinery.SourceFileLoader("upgrade_production", "scripts/upgrade-production.py")
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("upgrade_production", loader))
loader.exec_module(m)

fails = 0
T0 = datetime.datetime(2026, 10, 6, 8, 0, tzinfo=datetime.timezone.utc)


def check(name, got, want):
    global fails
    ok = got == want
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f"\n  got  {got}\n  want {want}"))


def refused(name, got, words):
    """A refusal whose reason names `words`."""
    check(name, bool(got) and all(any(w in g for g in got) for w in words), True)


def ev(*lines):
    return [(T0 + datetime.timedelta(minutes=i), *l.split()[:2], l.split()[2:]) for i, l in enumerate(lines)]


names = m.step_names()
info = {n: m.step_info(n) for n in names}
done_upto = lambda last: [f"{n} done" for n in names[:names.index(last) + 1]]

# the real step files' facts the rules below lean on (a change to them should fail here, not in production)
check("47 merges infra, then platform", info["47-postgres-18"]["branches"], ["infra", "platform"])
check("54 merges platform, then infra", info["54-tempo-3"]["branches"], ["platform", "infra"])
check("47 backs up postgres first, soaks 60 min", (info["47-postgres-18"]["wave0"], info["47-postgres-18"]["soak"]),
      (["postgres"], 60))
i01 = info["01-argocd-root-retry"]
check("01 has no wave0 line, soaks 15 min", (i01["wave0"], i01["soak"]), ([], 15))
i37 = info["37-strimzi-conversion"]
check("37 has playbooks and leaves strimzi out of sync", (bool(i37["playbooks"]), i37["out_of_sync"]),
      (True, ["strimzi"]))

P = lambda step, phase, events, arg=None: m.problems(names, step, phase, events, info[step], arg)

# begin: every earlier step done; once
refused("begin 03 with 01 not done (00 and 02 are; 02 before the ledger)",
        P("03-istio-1.26", "begin", ev("00-gluster-boot done", "02-istio-chart-repo done")), ["01-argocd-root-retry"])
check("begin 01 with 00 and 02 done", P("01-argocd-root-retry", "begin",
                                        ev("00-gluster-boot done", "02-istio-chart-repo done")), [])
refused("begin 01 before 00", P("01-argocd-root-retry", "begin", ev("02-istio-chart-repo done")), ["00-gluster-boot"])
check("begin 00 first", P("00-gluster-boot", "begin", ev("02-istio-chart-repo done")), [])
check("begin 47 with 01..46 done", P("47-postgres-18", "begin", ev(*done_upto("46-postgres-18-test"))), [])
refused("begin 47 with 45 missing",
        P("47-postgres-18", "begin", ev(*[l for l in done_upto("46-postgres-18-test") if not l.startswith("45-")])),
        ["45-alertmanager-blackbox-ksm"])
refused("begin twice", P("01-argocd-root-retry", "begin", ev("01-argocd-root-retry begun")), ["begun already"])
refused("a done step refuses every phase", P("01-argocd-root-retry", "merge", ev("01-argocd-root-retry done"), "infra"),
        ["is done"])

# nothing before begin
for phase, arg in (("backup", "postgres"), ("merge", "infra"), ("playbooks", None), ("done", None), ("preview", None)):
    refused(f"{phase} before begin", P("47-postgres-18", phase, [], arg), ["not begun"])

S47 = "47-postgres-18"
b = [f"{S47} begun"]
# backup: only the step's own stores
check("backup postgres at 47", P(S47, "backup", ev(*b), "postgres"), [])
refused("backup kafka at 47", P(S47, "backup", ev(*b), "kafka"), ["backs up no kafka"])
# merge: after the backups, in the file's order
refused("merge 47 infra before its backup", P(S47, "merge", ev(*b), "infra"), ["not backed up yet: postgres"])
bb = b + [f"{S47} backup postgres"]
check("merge 47 infra after its backup", P(S47, "merge", ev(*bb), "infra"), [])
refused("merge 47 platform before infra settled", P(S47, "merge", ev(*bb), "platform"), ["merge infra first"])
refused("merge 47 platform with infra merged, not settled",
        P(S47, "merge", ev(*bb, f"{S47} merged infra abc"), "platform"), ["merge infra first"])
check("merge 47 infra again after merged, not settled (the settle resumes)",
      P(S47, "merge", ev(*bb, f"{S47} merged infra abc"), "infra"), [])
bs = bb + [f"{S47} merged infra abc", f"{S47} settled infra abc"]
check("merge 47 platform after infra settled", P(S47, "merge", ev(*bs), "platform"), [])
refused("merge 47 infra twice", P(S47, "merge", ev(*bs), "infra"), ["merged and settled already"])
refused("merge a repo the step has no branch for", P("01-argocd-root-retry", "merge", ev("01-argocd-root-retry begun"),
                                                     "platform"), ["no platform branch line"])
# playbooks: after every merge settled and the preview
refused("playbooks 47 before platform settled", P(S47, "playbooks", ev(*bs, f"{S47} previewed"), None), ["platform"])
ball = bs + [f"{S47} merged platform def", f"{S47} settled platform def"]
refused("playbooks 47 without the preview", P(S47, "playbooks", ev(*ball)), ["not previewed"])
check("playbooks 47 after the preview", P(S47, "playbooks", ev(*ball, f"{S47} previewed")), [])
# the preview: after every merge settled (its playbooks read the cluster the merges leave)
refused("preview 47 before its merges", P(S47, "preview", ev(*bb)), ["not merged and settled yet"])
refused("preview 47 with only infra settled", P(S47, "preview", ev(*bs)), ["platform"])
check("preview 47 after both merges settled", P(S47, "preview", ev(*ball)), [])
# Argo's settle after a merge: a step's settle line, else 30 minutes (SonarQube's migration hook allows 45 at 57)
check("57 settles 50 minutes, 42 the default 30",
      (info["57-sonarqube-26.9"]["settle"], info["42-kubernetes-1.35"]["settle"]), (50, 30))
# the step's new images from production's own registry, there before the merge (asked of Forgejo)
asked = []
check("22's apt-cacher-ng tag there", m.registry_problems("22-apt-cacher-ng", lambda n, v: asked.append((n, v)) or 200),
      [])
check("22 asks for the new tag, not the old", asked, [("apt-cacher-ng", "7b46aea")])
check("22's tag missing: refused, naming it", m.registry_problems("22-apt-cacher-ng", lambda n, v: 404),
      ["git.pmon.dev/schnappy/apt-cacher-ng:7b46aea is not in the registry (Forgejo's package API: 404)"])
check("a step without own-registry images asks nothing",
      m.registry_problems("42-kubernetes-1.35", lambda n, v: (_ for _ in ()).throw(AssertionError(n))), [])
# the order `deploy:upgrade:status` names the next phase in: step 47's pinned, every step's preview after its merges
check("47's phases in order", [(p, a) for p, a, _ in m.phases(info[S47])],
      [("begin", None), ("backup", "postgres"), ("merge", "infra"), ("merge", "platform"), ("preview", None),
       ("playbooks", None), ("done", None)])
order = {n: [p for p, _, _ in m.phases(info[n])] for n in names}
check("every step's preview after its merges",
      [n for n, o in order.items() if "preview" in o and "merge" in o
       and o.index("preview") < max(i for i, p in enumerate(o) if p == "merge")], [])
refused("playbooks 47 twice", P(S47, "playbooks", ev(*ball, f"{S47} previewed", f"{S47} playbooks")), ["ran already"])
refused("playbooks at a step without playbook lines", P("54-tempo-3", "playbooks", ev("54-tempo-3 begun")),
        ["no playbook lines"])
# done: after the playbook lines
refused("done 47 before its playbook lines", P(S47, "done", ev(*ball, f"{S47} previewed")),
        ["playbook lines have not run"])
check("done 47 after them", P(S47, "done", ev(*ball, f"{S47} previewed", f"{S47} playbooks")), [])
refused("done 01 before its merge", P("01-argocd-root-retry", "done", ev("01-argocd-root-retry begun")),
        ["not merged and settled yet: infra"])

# defaults: after the playbook lines, before done - only a step with default lines
S42 = "42-kubernetes-1.35"
check("42 moves playbook defaults; 47 none", (info[S42]["defaults"], info[S47]["defaults"]), (True, False))
d42 = [f"{S42} begun", f"{S42} backup etcd", f"{S42} merged infra a", f"{S42} settled infra a", f"{S42} previewed"] \
    if "etcd" in info[S42]["wave0"] else [f"{S42} begun", f"{S42} merged infra a", f"{S42} settled infra a",
                                          f"{S42} previewed"]
refused("defaults 42 before its playbook lines", P(S42, "defaults", ev(*d42)), ["playbook lines have not run"])
check("defaults 42 after them", P(S42, "defaults", ev(*d42, f"{S42} playbooks")), [])
refused("done 42 without its defaults", P(S42, "done", ev(*d42, f"{S42} playbooks")), ["defaults are not committed"])
check("done 42 with them", P(S42, "done", ev(*d42, f"{S42} playbooks", f"{S42} defaults abc")), [])
refused("defaults twice", P(S42, "defaults", ev(*d42, f"{S42} playbooks", f"{S42} defaults abc")),
        ["committed already"])
refused("defaults at a step without default lines", P(S47, "defaults", ev(*ball, f"{S47} previewed",
                                                                        f"{S47} playbooks")), ["no default lines"])

# the soak
e = ev(f"{S47} checked")
check("soak: 60 min from checked, 10 min in", m.soak_state(e, S47, 60, T0 + datetime.timedelta(minutes=10))[1], 3000.0)
check("soak: over after 60 min", m.soak_state(e, S47, 60, T0 + datetime.timedelta(minutes=61))[1], 0.0)
check("soak: a check-failed starts it again", m.soak_state(ev(f"{S47} checked", f"{S47} check-failed"), S47, 60, T0),
      (None, None))
check("soak: the latest checked after a failure",
      m.soak_state(ev(f"{S47} checked", f"{S47} check-failed", f"{S47} checked"), S47, 60,
                   T0 + datetime.timedelta(minutes=2))[0], T0 + datetime.timedelta(minutes=2))
check("ledger lines parse", m.parse_events("2026-10-06T08:00:00Z 47-postgres-18 merged infra abc\n"),
      [(T0, "47-postgres-18", "merged", ["infra", "abc"])])

# the own-change hash: the same change rebased (other line numbers) is the same; another change, file or line is not
D = lambda path, at, lines: (f"diff --git a/{path} b/{path}\nindex 1..2 100644\n--- a/{path}\n+++ b/{path}\n"
                             f"@@ -{at} +{at} @@\n" + "".join(l + "\n" for l in lines))
base = m.own_hash(D("values.yaml", 10, ["-  image: a:1", "+  image: a:2"]))
check("own: the same change at another line",
      m.own_hash(D("values.yaml", 42, ["-  image: a:1", "+  image: a:2"])), base)
check("own: another value differs", m.own_hash(D("values.yaml", 10, ["-  image: a:1", "+  image: a:3"])) != base, True)
check("own: another file differs", m.own_hash(D("other.yaml", 10, ["-  image: a:1", "+  image: a:2"])) != base, True)
check("own: a line more differs",
      m.own_hash(D("values.yaml", 10, ["-  image: a:1", "+  image: a:2", "+  pull: Always"])) != base, True)

# the done phase's first call of a step that changes production (a throwaway certificate, a base backup) asks first:
# a no - or no terminal - runs nothing and records nothing
def done_calls(step, answer):
    calls, saved = [], {k: getattr(m, k) for k in ("ledger_for", "soak_state", "confirm", "ansible", "check", "record",
                                                   "proof_problems")}
    m.ledger_for = lambda st, ph, arg=None: (names, [], info[st])
    m.proof_problems = lambda *a, **k: []
    m.soak_state = lambda *a: (None, 0)
    m.confirm = lambda q: calls.append("asked") or answer
    m.ansible = lambda *a: calls.append(a[0]) or True
    m.check = lambda *a, **k: True
    m.record = lambda st, ev, *a: calls.append(ev)
    try:
        m.done(step)
    except SystemExit:
        calls.append("refused")
    finally:
        for k, v in saved.items():
            setattr(m, k, v)
    return calls
S23 = "23-cert-manager"
check("done 23 (cert-renew), no", done_calls(S23, False), ["asked", "refused"])
check("done 23 (cert-renew), yes", done_calls(S23, True), ["asked", "playbooks/acme-check.yml", "checked"])
check("done 24 (barman-check), yes", done_calls("24-cnpg", True),
      ["asked", "playbooks/postgres-base-backup.yml", "checked"])
check("done 24 (barman-check), no", done_calls("24-cnpg", False), ["asked", "refused"])
check("done 42 (neither) asks nothing", done_calls(S42, False), ["checked"])


# done's soak and its deciding check: the time of the first green check passed on, a red one not recorded done
def done_run(step, soak, green):
    calls, checks, saved = [], [], {k: getattr(m, k) for k in ("ledger_for", "soak_state", "confirm", "ansible",
                                                               "check", "record", "proof_problems")}
    m.ledger_for = lambda st, ph, arg=None: (names, [], info[st])
    m.proof_problems = lambda *a, **k: []
    m.soak_state = lambda *a: soak
    m.confirm = lambda q: True
    m.ansible = lambda *a: True
    m.check = lambda *a, **k: checks.append((a, k)) or green
    m.record = lambda st, ev, *a: calls.append(ev)
    try:
        m.done(step)
    except SystemExit as e:
        calls.append("refused: " + str(e).split(":")[0])
    finally:
        for k, v in saved.items():
            setattr(m, k, v)
    return calls, checks
calls, checks = done_run(S42, (T0, 600), True)
check("done while soaking: refused, nothing checked", (calls, checks), (["refused: REFUSED"], []))
calls, checks = done_run(S42, (T0, 0), True)
check("done after the soak, green: done, judged since the first green check, deciding",
      (calls, checks), (["done"], [((S42, T0), {"deciding": True})]))
calls, checks = done_run(S42, (T0, 0), False)
check("done after the soak, red: check-failed, refused - not done", calls, ["check-failed", "refused: REFUSED"])
calls, checks = done_run(S42, (None, None), True)
check("done's first call: no since, not deciding, records checked", (calls, checks),
      (["checked"], [((S42, None), {"deciding": False})]))

# every phase consults the proof first: refused by it, a phase runs, merges, records and asks nothing
class _Done:
    returncode, stdout = 0, "abc1234"


def phase_calls(fn, *args, proof=(), registry=(), step_info=None, events=()):
    calls, keep = [], ("ledger_for", "proof_problems", "registry_problems", "run", "ansible", "record", "settled",
                       "inventory_check", "confirm", "check", "soak_state", "merged_base", "step_info")
    saved = {k: getattr(m, k) for k in keep}
    m.ledger_for = lambda st, ph, arg=None: (names, list(events), info[st])
    m.proof_problems = lambda *a, **k: list(proof)
    m.registry_problems = lambda *a, **k: list(registry)
    m.run = lambda cmd, **k: calls.append(("run", os.path.basename(cmd[0]))) or _Done()
    m.ansible = lambda *a: calls.append(("ansible", a[0])) or True
    m.record = lambda st, ev, *a: calls.append(("record", ev))
    m.settled = lambda minutes, *a, **k: calls.append(("settled", minutes)) or (True, dict.fromkeys(m.URLS.values(), "r"),
                                                                                ["app"])
    m.inventory_check = lambda *a: calls.append(("inventory",)) or True
    m.confirm = lambda q: calls.append(("asked",)) or True
    m.check = lambda *a, **k: True
    m.soak_state = lambda *a: (None, 0)
    m.merged_base = lambda *a: None
    if step_info:
        m.step_info = step_info
    try:
        fn(*args)
    except SystemExit as e:
        calls.append(("refused", str(e)))
    finally:
        for k, v in saved.items():
            setattr(m, k, v)
    return calls


for name, fn, args in (("begin", m.begin, (S47,)), ("backup", m.backup, (S47, "postgres")),
                       ("preview", m.preview, (S47,)), ("playbooks", m.playbooks, (S47,)), ("done", m.done, (S23,)),
                       ("merge", m.merge, (S47, "infra"))):
    got = phase_calls(fn, *args, proof=["PROOF-X"])
    check(f"{name}: refused by the proof, nothing done", (len(got), got[-1][0], "PROOF-X" in got[-1][1]),
          (1, "refused", True))
got = phase_calls(m.merge, "22-apt-cacher-ng", "platform", registry=["REGISTRY-X"])
check("merge: refused by the registry check, nothing merged", (len(got), "REGISTRY-X" in got[-1][1]), (1, True))
got = phase_calls(m.merge, "57-sonarqube-26.9", "infra", events=ev("57-sonarqube-26.9 apps app"))
check("merge 57: merged, then Argo given its settle line's 50 minutes",
      [c for c in got if c[0] in ("run", "settled", "record")],
      [("run", "upgrade-merge-order.py"), ("run", "upgrade-merge-step.sh"), ("run", "git"), ("record", "merged"),
       ("settled", 50), ("record", "settled")])

# the terminal question fails closed: no terminal (a cron, a pipe) is a no
import subprocess as _sp
r = _sp.run(["setsid", "-w", sys.executable, "-c",
             "import importlib.machinery, importlib.util\n"
             "l = importlib.machinery.SourceFileLoader('u', 'scripts/upgrade-production.py')\n"
             "m = importlib.util.module_from_spec(importlib.util.spec_from_loader('u', l)); l.exec_module(m)\n"
             "print(m.confirm('x?'))"], capture_output=True, text=True, stdin=_sp.DEVNULL)
check("confirm without a terminal is a no", r.stdout.strip(), "False")

# image names as containerd lists them, so the inventory's floating tags meet the preload's digests
check("full name: a library image", m.full_name("postgres"), "docker.io/library/postgres")
check("full name: a Docker Hub image", m.full_name("valkey/valkey"), "docker.io/valkey/valkey")
check("full name: a registry's", m.full_name("ghcr.io/cloudnative-pg/postgresql"), "ghcr.io/cloudnative-pg/postgresql")
check("full name: a registry with a port", m.full_name("localhost:5000/x"), "localhost:5000/x")

# a step that restarts the control plane (its restarts-control-plane line): the deciding check records its restarts
# without judging them - production's 42 and 43 restart every leader-elected controller in a row
import inspect
SETTLED = inspect.signature(m.settled)


def settle_args(step, since=None, deciding=True):
    """settled()'s arguments, by name, as check() calls it."""
    seen, saved = [], {k: getattr(m, k) for k in ("read_ledger", "inventory_check", "settled")}
    m.read_ledger = lambda: (None, [])
    m.inventory_check = lambda *a: True
    m.settled = lambda *a, **k: seen.append(SETTLED.bind(*a, **k).arguments) or (True, {}, [])
    try:
        m.check(step, since, deciding=deciding)
    finally:
        for k, v in saved.items():
            setattr(m, k, v)
    return seen[0]


a42, a47 = settle_args(S42), settle_args(S47)
check("the deciding check of 42: its restarts expected", (a42["restart_step"], a42["restarts_expected"]), (S42, True))
check("the deciding check of 47: its restarts judged", (a47["restart_step"], a47["restarts_expected"]), (S47, False))
first = settle_args(S47, deciding=False)
check("the first check: no restart history, the 300 s window, no since",
      (first.get("restart_step"), first["quiet"], first.get("restarted_since")), (None, 300, None))
at = T0 + datetime.timedelta(minutes=20)
check("the deciding check: restarts judged since the first green check's time, not a window before it",
      (settle_args(S47, at)["restarted_since"], settle_args(S47, at)["quiet"]), (at, 300))


def settled_cmd(**kw):
    seen, saved = [], {k: getattr(m, k) for k in ("main_revisions", "run")}

    class _Out:
        returncode, stdout, stderr = 0, "", ""

    m.main_revisions = lambda: dict.fromkeys(m.URLS.values(), "r")
    m.run = lambda cmd, **k: seen.append(cmd[-1]) or _Out()
    try:
        m.settled(1, 4, 300, [], **kw)
    finally:
        for k, v in saved.items():
            setattr(m, k, v)
    return seen[0]


check("settled: --restarts-expected when expected", "--restarts-expected" in settled_cmd(restart_step=S42,
                                                                                         restarts_expected=True), True)
check("settled: none otherwise", "--restarts-expected" in settled_cmd(restart_step=S47), False)

# status names the phase after the defaults one (its event carries the commit)
import contextlib, io
def status_of(lines):
    saved = m.read_ledger
    m.read_ledger = lambda: (None, ev(*lines))
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            m.status()
    finally:
        m.read_ledger = saved
    return [l for l in buf.getvalue().splitlines() if l.startswith("next: ")]
S13 = "13-kubernetes-1.34.12"
mid13 = done_upto("12-kubelet-shutdown-grace") + [f"{S13} apps app", f"{S13} begun", f"{S13} backup etcd",
                                                  f"{S13} previewed", f"{S13} playbooks"]
check("status after 13's playbooks: its defaults next", status_of(mid13), [f"next: {S13} defaults"])
check("status after 13's defaults (the event carries the commit): done next",
      [l.split(" - ")[0] for l in status_of(mid13 + [f"{S13} defaults deadbeef"])], [f"next: {S13} done"])

# begin records the app set before begun: cut short between them, it runs again rather than stranding the step
got = phase_calls(m.begin, S47, events=ev(*done_upto("46-postgres-18-test")))
check("begin: the app set recorded before begun", [c for c in got if c[0] == "record"],
      [("record", "apps"), ("record", "begun")])
check("begin with apps but no begun (cut short): may run again",
      P(S47, "begin", ev(*done_upto("46-postgres-18-test"), f"{S47} apps app")), [])

# merge without the step's app set: refused before anything is pushed
got = phase_calls(m.merge, S47, "infra", events=ev(f"{S47} begun"))
check("merge without an app set: refused, nothing run", ([c for c in got if c[0] == "run"], got[-1][0],
                                                          "no app set" in got[-1][1]), ([], "refused", True))

# a red settle while main moved (a CD push during the wait) is inconclusive: refused, nothing recorded
class _Out:
    returncode, stdout, stderr = 1, "NOT SETTLED\n", ""
saved = {k: getattr(m, k) for k in ("main_revisions", "run")}
revs = iter([dict.fromkeys(m.URLS.values(), "a"), dict.fromkeys(m.URLS.values(), "b")])
m.main_revisions = lambda: next(revs)
m.run = lambda cmd, **k: _Out()
try:
    m.settled(1, 4, 300, [])
    got = "returned"
except SystemExit as e:
    got = str(e)
finally:
    for k, v in saved.items():
        setattr(m, k, v)
check("a red settle with main moved meanwhile: INCONCLUSIVE, not red", got.startswith("INCONCLUSIVE"), True)
saved = {k: getattr(m, k) for k in ("main_revisions", "run")}
m.main_revisions = lambda: dict.fromkeys(m.URLS.values(), "a")
m.run = lambda cmd, **k: _Out()
try:
    got = m.settled(1, 4, 300, [])[0]
finally:
    for k, v in saved.items():
        setattr(m, k, v)
check("a red settle with main unmoved: red", got, False)

# check of a step that does not exist: refused by name, not a traceback
try:
    m.check("99-nothing")
    got = "ran"
except SystemExit as e:
    got = str(e)
check("check of an unknown step: refused", got, "REFUSED: no step 99-nothing")

print("upgrade-ledger: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
EOF
