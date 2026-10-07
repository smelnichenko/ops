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
check("own: other blob names (a moved main) - the same", m.own_hash(D("values.yaml", 10, ["-  image: a:1",
      "+  image: a:2"]).replace("index 1..2", "index 7..9")), base)
mode = lambda new: f"diff --git a/s.sh b/s.sh\nold mode 100644\nnew mode {new}\n"
check("own: a mode change counts", m.own_hash(mode("100755")) != m.own_hash(mode("100644")), True)
binary = lambda data: (f"diff --git a/i.png b/i.png\nindex 1..2 100644\nGIT binary patch\nliteral 4\n{data}\n\n"
                       "literal 0\nHcmV?d00001\n")
check("own: a binary file's content counts", m.own_hash(binary("LcmZQzWMT")) != m.own_hash(binary("LcmZQzWMU")), True)

# the floating-image check reads production as the done steps leave it, and after the step's merges as it leaves it
# (step 47 replaces the floating postgresql:17: after its merge the kubelet may collect it)
pg17 = "image ghcr.io/cloudnative-pg/postgresql 17"
check("floating images before 47's merges: postgresql:17 in use", pg17 in m.proof_inventory(names, S47, False), True)
check("after them: not any more", pg17 in m.proof_inventory(names, S47, True), False)
# between a two-repo step's merges (its infra merge live): only what both sides use - postgresql:17, replaced by the
# first merge, may be gone already (the second merge was refused for good); 18, the second's, is not pulled yet
before47, after47 = m.proof_inventory(names, S47, False), m.proof_inventory(names, S47, True)
pg18 = next(l for l in after47 if l.startswith("image ghcr.io/cloudnative-pg/postgresql ") and l not in before47)
kept = next(l for l in before47 if l.startswith("image ") and l in after47)
between = m.proof_inventory(names, S47, False, partly=True)
check("between 47's merges: postgresql:17 not judged, 18 not yet, the rest as before",
      (pg17 in between, pg18 in between, kept in between), (False, False, True))

# the done phase's first call of a step that changes production (a throwaway certificate, a base backup) asks first:
# a no - or no terminal - runs nothing and records nothing
def done_calls(step, answer, events=()):
    calls, saved = [], {k: getattr(m, k) for k in ("ledger_for", "soak_state", "confirm", "ansible", "check", "record",
                                                   "proof_problems")}
    m.ledger_for = lambda st, ph, arg=None: (names, list(events), info[st])
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
check("done 24 (barman-check), yes: the backup taken and recorded (a red check later does not take it again)",
      done_calls("24-cnpg", True), ["asked", "playbooks/postgres-base-backup.yml", "base-backup", "checked"])
check("done 24 after a check-failed, its backup recorded: not taken again",
      done_calls("24-cnpg", False, ev("24-cnpg base-backup", "24-cnpg checked", "24-cnpg check-failed")), ["checked"])
check("done 24 (barman-check), no", done_calls("24-cnpg", False), ["asked", "refused"])
check("done 42 (neither) asks nothing", done_calls(S42, False), ["checked"])
check("done 47 with its base backup taken after the merges: none again, nothing asked",
      done_calls(S47, False, ev(f"{S47} base-backup")), ["checked"])
# the merge's promise when its base backup was declined or failed: done takes it, asked first
check("done 47 with no base backup at its merges (declined): done takes it", done_calls(S47, True),
      ["asked", "playbooks/postgres-base-backup.yml", "base-backup", "checked"])


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


PROOF_KW = []  # the keyword arguments each phase read the proof with


RUN_ARGS = []  # every command a phase ran (phase_calls), whole


def phase_calls(fn, *args, proof=(), registry=(), step_info=None, events=(), answer=True, ansible_ok=True,
                pushed=None, revs=None, ten_out="abc1234"):
    calls, keep = [], ("ledger_for", "proof_problems", "registry_problems", "run", "ansible", "record", "settled",
                       "inventory_check", "confirm", "check", "soak_state", "merged_base", "pushed_base", "step_info",
                       "ten", "image_pins")
    saved = {k: getattr(m, k) for k in keep}
    m.ledger_for = lambda st, ph, arg=None: (names, list(events), info[st])
    m.proof_problems = lambda *a, **k: PROOF_KW.append({x: k[x] for x in ("partly", "merged") if x in k}) or list(proof)
    m.registry_problems = lambda *a, **k: list(registry)
    def fake_run(cmd, **k):  # `revs`: what rev-parse answers per ref (abc1234 for any other)
        calls.append(("run", os.path.basename(cmd[0])))
        RUN_ARGS.append(list(cmd))
        if revs and "rev-parse" in cmd:
            return type("R", (), {"returncode": 0, "stdout": revs.get(cmd[-1], "abc1234")})()
        return _Done()
    m.run = fake_run
    m.ansible = lambda *a: calls.append(("ansible", a[0])) or ansible_ok
    m.record = lambda st, ev, *a: calls.append(("record", ev))
    m.settled = lambda minutes, *a, **k: calls.append(("settled", minutes)) or (True, dict.fromkeys(m.URLS.values(), "r"),
                                                                                ["app"])
    m.inventory_check = lambda *a: calls.append(("inventory",)) or True
    m.confirm = lambda q: calls.append(("asked",)) or answer
    m.ten = lambda command, **k: calls.append(("ten", command.split("/")[-1])) or type(
        "R", (), {"returncode": 0, "stdout": ten_out})()
    m.check = lambda *a, **k: True
    m.soak_state = lambda *a: (None, 0)
    m.merged_base = lambda *a: None
    m.pushed_base = lambda *a: pushed
    m.image_pins = lambda *a: set()
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
# the proof read as production stands at each merge: a two-repo step's second merge judges the images between them
PROOF_KW.clear()
phase_calls(m.merge, S47, "infra", events=ev(f"{S47} apps app"))
phase_calls(m.merge, S47, "platform", events=ev(f"{S47} apps app", f"{S47} merged infra a", f"{S47} settled infra a"))
check("merge reads the proof as production stands: 47's infra before the step, its platform between the merges",
      [k.get("partly", False) for k in PROOF_KW], [False, True])
got = phase_calls(m.merge, "22-apt-cacher-ng", "platform", registry=["REGISTRY-X"])
check("merge: refused by the registry check, nothing merged", (len(got), "REGISTRY-X" in got[-1][1]), (1, True))
got = phase_calls(m.merge, "57-sonarqube-26.9", "infra", events=ev("57-sonarqube-26.9 apps app"))
check("merge 57: the change shown (log, stat, diff) and asked about, merged, then Argo given its settle line's 50 "
      "minutes", [c for c in got if c[0] in ("run", "settled", "record", "asked")],
      [("run", "git"), ("run", "git"), ("run", "git"), ("run", "upgrade-merge-order.py"), ("run", "git"),
       ("run", "git"), ("run", "git"), ("asked",), ("run", "upgrade-merge-step.sh"), ("run", "git"), ("record", "merged"),
       ("settled", 50), ("record", "settled")])
# the merge checks and shows the change against production's main (origin's): a local main behind it - CD pushed
# meanwhile - refuses before the yes; the tip it checked is the one the merge pushes (the branch moved since: refused)
got = phase_calls(m.merge, "57-sonarqube-26.9", "infra", events=ev("57-sonarqube-26.9 apps app"),
                  revs={"main": "old", "origin/main": "new"})
check("merge 57, local main behind origin's: refused before anything is asked or pulled",
      ([c for c in got if c[0] in ("asked", "ansible")], got[-1][0], "pull --ff-only" in got[-1][1]),
      ([], "refused", True))
RUN_ARGS.clear()
got = phase_calls(m.merge, "57-sonarqube-26.9", "infra", events=ev("57-sonarqube-26.9 apps app"),
                  revs={"upgrade/57-sonarqube-26.9": "c4ecked"})
check("merge 57: shown against origin's main, the checked tip handed to the merge",
      ([a[-1] for a in RUN_ARGS if "diff" in a][:1], [a[-1] for a in RUN_ARGS if a[0].endswith("upgrade-merge-step.sh")]),
      (["origin/main..c4ecked"], ["c4ecked"]))
got = phase_calls(m.merge, "57-sonarqube-26.9", "infra", events=ev("57-sonarqube-26.9 apps app"), pushed="b4se")
check("merge 57 pushed by a run cut short before its tag: taken up (tagged) and recorded - not asked, nothing pulled",
      [c for c in got if c[0] in ("run", "ansible", "record", "asked")],
      [("run", "git"), ("run", "upgrade-merge-step.sh"), ("run", "git"), ("record", "merged"), ("record", "settled")])
got = phase_calls(m.merge, "57-sonarqube-26.9", "infra", events=ev("57-sonarqube-26.9 apps app"), answer=False)
check("merge 57, not confirmed: refused after the change was shown - nothing merged, nothing recorded",
      ([c for c in got if c[0] == "run" and c[1] == "upgrade-merge-step.sh" or c[0] == "record"], got[-1][0]),
      ([], "refused"))

# a barman-after-merge step: production's base backup on the new version as soon as its last merge settled (PostgreSQL
# 18 has none until then - its point-in-time recovery starts there), not hours later at done; only 47 has one (25's is
# about the Pi store its playbook upgrades: after that)
check("barman-after-merge: 47 only", [n for n in names if info[n].get("base_backup_after_merge")], [S47])
BB = [("asked",), ("ansible", "playbooks/postgres-base-backup.yml"), ("record", "base-backup")]
got = phase_calls(m.merge, S47, "platform", events=ev(f"{S47} apps app", f"{S47} merged infra a", f"{S47} settled infra a"))
check("merge 47 platform (its last): settled, then the base backup, asked first",
      [c for c in got if c[0] in ("ansible", "asked", "record")][-4:], [("record", "settled")] + BB)
got = phase_calls(m.merge, S47, "infra", events=ev(f"{S47} apps app"))
check("merge 47 infra, the cluster not on 18 yet: no base backup",
      [c for c in got if c == ("ansible", "playbooks/postgres-base-backup.yml")], [])
# the backup follows the merge that makes the new major live, not the step's last: 47's infra merge does (its platform
# merge renders nothing new) - the operator's pause between the merges, or a failed second settle, would leave 18
# running with no point to recover to
PG18 = "ghcr.io/cloudnative-pg/postgresql:18.6-system-bullseye@sha256:" + "9" * 64
got = phase_calls(m.merge, S47, "infra", events=ev(f"{S47} apps app"), ten_out=PG18)
check("merge 47 infra, the cluster running 18 once it settled: the base backup then, asked first",
      [c for c in got if c[0] in ("ansible", "asked", "record")][-4:], [("record", "settled")] + BB)
got = phase_calls(m.merge, S47, "platform", events=ev(f"{S47} apps app", f"{S47} merged infra a",
                                                      f"{S47} settled infra a", f"{S47} base-backup"), ten_out=PG18)
check("merge 47 platform, the backup taken at the infra merge: not again",
      [c for c in got if c == ("ansible", "playbooks/postgres-base-backup.yml")], [])
check("47's new major, read from its image line", m.postgres_target(S47),
      "ghcr.io/cloudnative-pg/postgresql:18.6-system-bullseye")
got = phase_calls(m.merge, "24-cnpg", "infra", events=ev("24-cnpg apps app"))
check("merge 24 infra (barman-check, not after the merge): no base backup - done takes it",
      [c for c in got if c == ("ansible", "playbooks/postgres-base-backup.yml")], [])
got = phase_calls(m.merge, S47, "platform", answer=False, events=ev(
    f"{S47} apps app", f"{S47} merged infra a", f"{S47} settled infra a", f"{S47} merged platform b"))
check("merge 47 platform, the backup not confirmed: settled recorded, no backup, not refused - done takes it",
      [c for c in got if c[0] in ("ansible", "record", "refused")], [("record", "settled")])

# a step's public images pulled on ten at its first merge, after the yes and before the push: a tag missing upstream
# stops it with nothing live, and the rollout does not wait on the pull with the old pod gone
S54 = "54-tempo-3"
m.image_pins = lambda step, name, tag: set()  # no pins in the step's branches (read on real repos: upgrade-merge-step)
check("prepull: 54's public image, as containerd names it", m.prepull_images(S54), ["docker.io/grafana/tempo:3.1.0"])
check("prepull: an added image (+ image) too", "quay.io/prometheus-operator/prometheus-config-reloader:v0.94.1"
      in m.prepull_images("27-kube-prometheus-stack"), True)
check("prepull: production's own registry left out (the registry check covers it)",
      [i for n in names for i in m.prepull_images(n) if i.startswith("git.pmon.dev/")], [])
check("prepull: one image under its short and its docker.io name pulled once (21's manager agent)",
      [i for i in m.prepull_images("21-scylla-operator-1.22") if "scylla-manager-agent" in i],
      ["docker.io/scylladb/scylla-manager-agent:3.12.1"])
# the reference production runs: a digest the step's branches pin the tag to (47's postgresql 18) pulled with it - the
# tag alone may name another build by then; two digests for one tag refuse
D1, D2 = "sha256:" + "1" * 64, "sha256:" + "2" * 64
m.image_pins = lambda step, name, tag: {D1} if "postgresql" in name else set()
check("prepull: 47's postgresql 18 by the digest its branch pins",
      m.prepull_images(S47), [f"ghcr.io/cloudnative-pg/postgresql:18.6-system-bullseye@{D1}"])
m.image_pins = lambda step, name, tag: {D1, D2} if "postgresql" in name else set()
try:
    m.prepull_images(S47)
    got = "pulled"
except SystemExit as e:
    got = "refused" if "2 digests" in str(e) else str(e)
check("prepull: one tag pinned to two digests in the step's branches: refused", got, "refused")
m.image_pins = lambda step, name, tag: set()
got = phase_calls(m.merge, S54, "platform", events=ev(f"{S54} apps app"))
keep = [c for c in got if c in (("asked",), ("ansible", "playbooks/upgrade-prepull.yml"), ("run", "upgrade-merge-step.sh"))]
check("merge 54 platform (its first): asked, the images pulled, then merged", keep,
      [("asked",), ("ansible", "playbooks/upgrade-prepull.yml"), ("run", "upgrade-merge-step.sh")])
got = phase_calls(m.merge, S54, "infra", events=ev(f"{S54} apps app", f"{S54} merged platform a",
                                                   f"{S54} settled platform a"))
check("merge 54 infra (its second): pulled again - collected meanwhile, or the second repo's",
      [c for c in got if c[0] == "ansible"], [("ansible", "playbooks/upgrade-prepull.yml")])
got = phase_calls(m.merge, S54, "platform", events=ev(f"{S54} apps app"), ansible_ok=False)
check("merge 54, a pull failing: refused, nothing merged",
      ([c for c in got if c == ("run", "upgrade-merge-step.sh")], got[-1][0]), ([], "refused"))
got = phase_calls(m.merge, "22-apt-cacher-ng", "platform", events=ev("22-apt-cacher-ng apps app"))
check("merge 22 (only its own registry's image): nothing pulled", [c for c in got if c[0] == "ansible"], [])

# step 54 replaces Tempo's major: its WAL flushed right before the infra merge (after the yes), not before platform's
S54 = "54-tempo-3"
check("54 flushes Tempo before its infra merge", info[S54]["tempo_flush"], ["infra"])
RUN_ARGS.clear()
got = [c for c in phase_calls(m.merge, S54, "infra", events=ev(f"{S54} apps app")) if c[0] in ("ten", "asked", "run")]
check("merge 54 infra: asked, Tempo flushed (the flush waited for), then merged",
      [c for c in got if c[0] != "run" or c[1] in ("upgrade-merge-step.sh", "tempo-flush.py")],
      [("asked",), ("run", "tempo-flush.py"), ("run", "upgrade-merge-step.sh")])
check("merge 54 infra: the flush's kubectl is ten's", [a[1:] for a in RUN_ARGS if a[0].endswith("tempo-flush.py")],
      [["ssh", m.TEN, "kubectl"]])
RUN_ARGS.clear()
got = phase_calls(m.merge, S54, "platform", events=ev(f"{S54} apps app"))
check("merge 54 platform: no flush", [c for c in got if c in (("ten", "flush"), ("run", "tempo-flush.py"))], [])

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
import inspect, json
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


REVS = {m.URLS["infra"]: "infra-sha", m.URLS["platform"]: "platform-sha"}


def settled_cmd(apps_seen="", returned=None, **kw):
    """The command settled() runs on ten - argo-settled.py answering APPS `apps_seen`; settled()'s result in `returned`."""
    seen, saved = [], {k: getattr(m, k) for k in ("main_revisions", "run")}

    class _Out:
        returncode, stdout, stderr = 0, (f"APPS {apps_seen}\n" if apps_seen else ""), ""

    m.main_revisions = lambda: dict(REVS)
    m.run = lambda cmd, **k: seen.append(cmd[-1]) or _Out()
    try:
        got = m.settled(1, 4, 300, [], **kw)
        if returned is not None:
            returned.extend(got[2])
    finally:
        for k, v in saved.items():
            setattr(m, k, v)
    return seen[0]


check("settled: --restarts-expected when expected", "--restarts-expected" in settled_cmd(restart_step=S42,
                                                                                         restarts_expected=True), True)
check("settled: none otherwise", "--restarts-expected" in settled_cmd(restart_step=S47), False)
# Argo judged on the commits main has now - each repo's own (with none, any commit passed the settle)
import json, re, shlex
check("settled: Argo judged against main's commits, each repo's",
      json.loads(shlex.split(settled_cmd())[0].split("=", 1)[1]), REVS)
# preview environments: allowed beside production's apps, and never counted into the step's app set
returned = []
cmd_words = shlex.split(settled_cmd(apps_seen="app-a,pr-7-app,app-b", returned=returned))
allowed = cmd_words[cmd_words.index("--allow-extra-apps") + 1] if "--allow-extra-apps" in cmd_words else None
check("settled: a preview environment's app allowed beside the step's",
      [bool(allowed and re.search(allowed, a)) for a in ("pr-7-app", "app-a")], [True, False])
check("settled: the apps it returns leave the preview environments out", returned, ["app-a", "app-b"])
# a preview environment opened during a settle: its app and its pods left out, production's namespaces not
import re, shlex
words = shlex.split(settled_cmd())
ignored = words[words.index("--ignore-namespaces") + 1] if "--ignore-namespaces" in words else None
check("settled: the preview environments' namespaces left out, production's and the test environment's not",
      [bool(ignored and re.search(ignored, ns)) for ns in ("schnappy-pr-7", "schnappy-production", "schnappy-test",
                                                           "schnappy-infra")], [True, False, False, False])

# each phase that runs Ansible (ansible(...) in its function, or the step's playbook lines) has its Taskfile task depend
# on deploy:install - the venv and the collections; merge's pre-pull and base backup lacked it
import ast, yaml as _yaml
src = open("scripts/upgrade-production.py").read()
funcs = {n.name: ast.get_source_segment(src, n) for n in ast.parse(src).body if isinstance(n, ast.FunctionDef)}
runs_ansible = {f for f, body in funcs.items() if "ansible(" in body or "upgrade-step-playbooks.sh" in body} - {"ansible"}
tasks_ = _yaml.safe_load(open("Taskfile.yml"))["tasks"]
lacking = sorted(name for name, t in tasks_.items() if name.startswith("deploy:upgrade:")
                 and any(f"upgrade-production.py {ph} " in str(t.get("cmds")) for ph in runs_ansible)
                 and "deploy:install" not in (t.get("deps") or []))
check("every production phase that runs Ansible installs it first", lacking, [])
# the inventory check leaves the preview environments open now out (their images are no step's), as the test
# environment; its own files are removed after it
import tempfile
def inventory_run(namespaces):
    seen, saved = [], {k: getattr(m, k) for k in ("ten", "run", "WORK")}
    m.WORK = tempfile.mkdtemp()
    def ten(command, stdin=None, check=True):
        seen.append(command)
        out = "\n".join(f"namespace/{n}" for n in namespaces) if command.startswith("kubectl get namespaces") else ""
        return type("R", (), {"returncode": 0, "stdout": out, "stderr": ""})()
    m.ten = ten
    m.run = lambda cmd, **k: type("R", (), {"returncode": 0, "stdout": "", "stderr": ""})()
    try:
        ok = m.inventory_check(names[:1])
        left = os.listdir(m.WORK)
    finally:
        for k, v in saved.items():
            setattr(m, k, v)
    return ok, [c for c in seen if "INVENTORY_EXCLUDE_NAMESPACES=" in c], left
ok, cmds, left = inventory_run(["schnappy-production", "schnappy-test", "schnappy-pr-7", "schnappy-pr-12"])
excluded = shlex.split(cmds[0])[0].split("=", 1)[1].split() if cmds else []
check("inventory: the test environment and the preview environments open now left out, production not",
      sorted(excluded), sorted(m.TEST_NAMESPACES.split() + ["schnappy-pr-12", "schnappy-pr-7"]))
check("inventory: its own files removed after it", left, [])
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

# a phase claims the step: a start without an end refuses every other phase until it ends (or is released)
base47 = done_upto("46-postgres-18-test") + [f"{S47} apps app", f"{S47} begun"]
refused("a phase while another's start is open: refused, naming release",
        P(S47, "backup", ev(*base47, f"{S47} start backup postgres host:1"), "postgres"), ["has not ended", "release"])
check("its end: the next phase may run",
      P(S47, "backup", ev(*base47, f"{S47} start backup postgres host:1", f"{S47} end backup failed"), "postgres"), [])
check("a released start: the next phase may run",
      P(S47, "backup", ev(*base47, f"{S47} start backup postgres host:1", f"{S47} end backup released"), "postgres"),
      [])
# an end closes only the start it ends - by its token (the claim's host:pid:nonce): a released run still alive, its end
# coming later, must not close the claim made after the release (an end with no token, as an older ledger's, closes it)
late = ev(*base47, f"{S47} start merge infra host:1:aa", f"{S47} end merge released host:1:aa",
          f"{S47} start preview host:2:bb", f"{S47} end merge passed host:1:aa")
refused("a released run's late end: the claim made after the release still open", P(S47, "backup", late, "postgres"),
        ["preview host:2:bb started"])
check("its own end closes it", P(S47, "backup", late + ev(f"{S47} end preview passed host:2:bb"), "postgres"), [])
# the claim is written against the read the checks were made on: a concurrent change refuses it
class _Rc:
    def __init__(self, rc, err=""):
        self.returncode, self.stdout, self.stderr = rc, "", err
def claim(replace_rc, err="Error from server (Conflict): the object has been modified"):
    sent, saved = [], {k: getattr(m, k) for k in ("read_ledger", "ten")}
    reads = iter(range(7, 99))  # each read a newer resourceVersion: a claim that re-read would send another
    m.read_ledger = lambda: ({"metadata": {"resourceVersion": str(next(reads))}, "data": {"events": ""}}, ev(*base47))
    m.ten = lambda command, stdin=None, check=True: sent.append(json.loads(stdin)) or _Rc(replace_rc, err)
    m.CLAIMED.clear()
    try:
        m.ledger_for(S47, "backup", "postgres")
        got = "claimed"
    except SystemExit as e:
        got = str(e)
    finally:
        for k, v in saved.items():
            setattr(m, k, v)
    return got, sent, list(m.CLAIMED)
got, sent, claimed = claim(0)
check("the claim: start written with the read's resourceVersion, its token kept for the end",
      (got, sent[0]["metadata"]["resourceVersion"], sent[0]["data"]["events"].split()[2:4],
       [c[:2] for c in claimed], sent[0]["data"]["events"].split()[-1] == claimed[0][2]),
      ("claimed", "7", ["start", "backup"], [(S47, "backup")], True))
got, _, claimed = claim(1)
check("a concurrent change: the claim refused, nothing claimed", (got.startswith("REFUSED: the ledger changed"), claimed),
      (True, []))
# another failure (the connection gone after the server took it): not "changed" - the write may have been made
got, _, claimed = claim(1, "Unable to connect to the server: connection reset by peer")
check("the write failing otherwise: said so - it may have been made", ("may have been made" in got, claimed),
      (True, []))
# main records the claimed phase's end, passed or failed
def main_ends(code):
    ends, saved = [], {k: getattr(m, k) for k in ("record", "begin")}
    m.record = lambda st, e, *a, **k: ends.append((st, e, *a))
    def fake_begin(step):
        m.CLAIMED.append((step, "begin", "host:1:aa"))
        if code:
            sys.exit(code)
    m.begin = fake_begin
    m.CLAIMED.clear()
    argv = sys.argv
    sys.argv = ["x", "begin", S47]
    try:
        m.main()
    except SystemExit:
        pass
    finally:
        sys.argv = argv
        for k, v in saved.items():
            setattr(m, k, v)
    return ends
check("a phase that passes: its end recorded passed, with its claim's token", main_ends(0),
      [(S47, "end", "begin", "passed", "host:1:aa")])
check("a phase that fails: its end recorded failed", main_ends("REFUSED: x"),
      [(S47, "end", "begin", "failed", "host:1:aa")])
# a run whose claim was closed meanwhile (released by hand, its run still alive) records nothing more: its events would
# land in another phase's claim
def recorded(lines):
    sent, saved = [], {k: getattr(m, k) for k in ("read_ledger", "ten")}
    text = "\n".join(f"2026-10-06T08:0{i}:00Z {l}" for i, l in enumerate(lines))
    m.read_ledger = lambda: ({"metadata": {"resourceVersion": "9"}, "data": {"events": text}}, m.parse_events(text))
    m.ten = lambda command, stdin=None, check=True: sent.append(stdin) or _Rc(0)
    m.CLAIMED[:] = [(S47, "merge", "host:1:aa")]
    try:
        m.record(S47, "merged", "infra", "abc")
        got = "recorded"
    except SystemExit as e:
        got = "refused" if "closed" in str(e) else str(e)
    finally:
        m.CLAIMED.clear()
        for k, v in saved.items():
            setattr(m, k, v)
    return got, len(sent)
check("its claim still open: recorded", recorded([f"{S47} start merge infra host:1:aa"]), ("recorded", 1))
check("its claim released meanwhile: refused, nothing written",
      recorded([f"{S47} start merge infra host:1:aa", f"{S47} end merge released host:1:aa"]), ("refused", 0))
check("released, and another phase claimed it: refused", recorded(
    [f"{S47} start merge infra host:1:aa", f"{S47} end merge released host:1:aa", f"{S47} start preview host:2:bb"]),
    ("refused", 0))
# release closes a start only when the run that made it is gone - not one alive on this host (a process this test
# starts, its command line naming the script, and stops)
import socket, subprocess, time
def released(pid):
    ends, saved = [], {k: getattr(m, k) for k in ("read_ledger", "confirm", "record")}
    token = f"{socket.gethostname()}:{pid}:cc"
    m.read_ledger = lambda: ({}, ev(f"{S47} start merge infra {token}"))
    m.confirm = lambda q: True
    m.record = lambda st, e, *a, **k: ends.append((e, *a))
    try:
        m.release(S47)
        got = ends
    except SystemExit as e:
        got = "refused" if "alive" in str(e) else str(e)
    finally:
        for k, v in saved.items():
            setattr(m, k, v)
    return got, token
child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)", "upgrade-production.py"])
for _ in range(50):  # until its exec shows (right after the fork its command line is still this one's)
    if "upgrade-production" in open(f"/proc/{child.pid}/cmdline").read():
        break
    time.sleep(0.1)
got, _ = released(child.pid)
check("release: the run that claimed it alive here - refused", got, "refused")
child.kill()
child.wait()
got, token = released(child.pid)
check("release: that run gone - its start closed, with its token", got, [("end", "merge", "released", token)])

# a proof is refused when any step branch moved, was made or deleted since the run started (proof-start's record) -
# the run then mixed states; a run.json from before that record refuses too
import tempfile
def proved(run_info, moved):
    saved = {k: getattr(m, k) for k in ("PROVEN", "ops_unchanged_since", "branch_moves")}
    m.PROVEN = tempfile.mkdtemp()
    json.dump(run_info, open(os.path.join(m.PROVEN, "run.json"), "w"))
    m.ops_unchanged_since = lambda *a: []
    m.branch_moves = lambda recorded: list(moved)
    try:
        m.record_proof(S47, "i", "p")
        got = "past the checks"
    except SystemExit as e:  # a later check (the floating digests, here none) is past these
        got = str(e) if "moved during the run" in str(e) or "proof-start" in str(e) else "past the checks"
    except Exception:
        got = "past the checks"
    finally:
        for k, v in saved.items():
            setattr(m, k, v)
    return got
check("a step branch moved during the run: refused",
      "moved during the run" in proved({"ops": "x", "run": "r", "branches": {}}, ["platform upgrade/50-x: a -> b"]), True)
check("none moved: past that check", proved({"ops": "x", "run": "r", "branches": {}}, []), "past the checks")
check("a run.json without the record: refused", "proof-start" in proved({"ops": "x", "run": "r"}, []), True)
# a step that moves ClickHouse's image (59, 61) is proven only with its rollback pin proven on the same platform commit
# and images, by the pin test of the run's ops commit (tests/clickhouse-pin's result; the full run starts it beside the
# build)
import json, tempfile
S59, S61 = "59-clickhouse-25.8", "61-clickhouse-26.8"
pin_file = os.path.join(tempfile.mkdtemp(), "clickhouse-pin.json")
img = {S59: ["24.8-alpine", "25.8.33.6-alpine"], S61: ["25.8.33.6-alpine", "26.8.15.10-alpine"]}
json.dump({"59": {"platform": "p59", "images": img[S59], "ops": "o"},
           "61": {"platform": "p61", "images": img[S61], "ops": "o"}}, open(pin_file, "w"))
check("pin: 59 on the commit and images it proved", m.pin_problems(S59, "p59", "o", pin_file), [])
check("pin: 61 on the commit and images it proved", m.pin_problems(S61, "p61", "o", pin_file), [])
check("pin: 59 on another platform commit - refused", len(m.pin_problems(S59, "other", "o", pin_file)), 1)
check("pin: proven by another ops commit's pin test - refused", len(m.pin_problems(S59, "p59", "o2", pin_file)), 1)
# the round trip: tests/clickhouse-pin/run.sh's own lines that write the result, with the step files' images, read back
# by pin_problems (they were tested apart, against hand-written JSON)
pin_sh = open("tests/clickhouse-pin/run.sh").read()
writer = pin_sh[pin_sh.index("{ printf '{\"59\""):pin_sh.index('} > "$result"') + len('} > "$result"')]
written = os.path.join(tempfile.mkdtemp(), "written.json")
subprocess.run(["bash", "-c", writer], check=True, env=dict(
    os.environ, result=written, ops_sha="o", sha59="p59", old59=img[S59][0], new59=img[S59][1], pin59="24.8",
    sha61="p61", old61=img[S61][0], new61=img[S61][1], pin61="25.8"))
check("pin: the result run.sh writes, read back - 59 and 61 proven",
      (m.pin_problems(S59, "p59", "o", written), m.pin_problems(S61, "p61", "o", written)), ([], []))
json.dump({"61": {"platform": "p61", "images": img[S61], "ops": "o"}}, open(pin_file, "w"))
check("pin: 59 with no result of its own (the run failed it) - refused",
      len(m.pin_problems(S59, "p59", "o", pin_file)), 1)
json.dump({"59": {"platform": "p59", "images": ["24.8-alpine", "25.3-alpine"], "ops": "o"}}, open(pin_file, "w"))
check("pin: 59 proven for other images - refused", len(m.pin_problems(S59, "p59", "o", pin_file)), 1)
os.remove(pin_file)
check("pin: no result at all - refused", len(m.pin_problems(S59, "p59", "o", pin_file)), 1)
check("pin: a step that does not move ClickHouse wants none", m.pin_problems(S47, "x", "o", pin_file), [])
check("pin: exactly 59 and 61 move ClickHouse's image",
      [n for n in names if m.pin_problems(n, "x", "o", pin_file)], [S59, S61])


def record_59(pin):
    """record-proof of 59 with git and the tree stubbed; `pin` the rollback pin's result (None: no file)."""
    work = tempfile.mkdtemp()
    json.dump({"run": "r", "ops": "o", "branches": {}}, open(os.path.join(work, "run.json"), "w"))
    if pin is not None:
        json.dump(pin, open(os.path.join(work, "pin.json"), "w"))

    class _Out:
        def __init__(self, out):
            self.stdout, self.returncode = out, 0

    def run(cmd, **k):
        if cmd[-2:-1] == ["--refs"]:
            return _Out("upgrade/59-x upgrade/59-y")
        return _Out({"upgrade/59-x": "i59", "upgrade/59-y": "p59"}.get(cmd[-1], "z"))
    keep = ("PROVEN", "PIN_RESULT", "run", "ops_unchanged_since", "floating_digests", "own_change", "branch_moves")
    saved = {k: getattr(m, k) for k in keep}
    m.PROVEN, m.PIN_RESULT, m.run = work, os.path.join(work, "pin.json"), run
    m.ops_unchanged_since, m.floating_digests, m.own_change = (lambda *a: []), (lambda: {}), (lambda *a: "own")
    m.branch_moves = lambda recorded: []
    try:
        m.record_proof(S59, "i59", "p59")
        return "recorded" if os.path.exists(os.path.join(work, S59 + ".json")) else "nothing"
    except SystemExit as e:
        return f"refused, nothing recorded: {not os.path.exists(os.path.join(work, S59 + '.json'))}"
    finally:
        for k, v in saved.items():
            setattr(m, k, v)


check("record-proof 59 with its pin proven: recorded",
      record_59({"59": {"platform": "p59", "images": img[S59], "ops": "o"}}), "recorded")
check("record-proof 59 without a pin result: refused, nothing recorded", record_59(None),
      "refused, nothing recorded: True")
check("record-proof 59 with a pin another ops commit's test proved: refused, nothing recorded",
      record_59({"59": {"platform": "p59", "images": img[S59], "ops": "an earlier ops"}}),
      "refused, nothing recorded: True")

print("upgrade-ledger: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
EOF
