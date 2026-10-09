#!/bin/bash
# scripts/upgrade-production.py's refusals no other harness makes fail: a branch changed after its proof (A01), an earlier
# step proven by another run or not at all (A02), a floating tag naming another build (A03), merge's stops - a failed
# merge-order check, a failed Tempo flush, Argo not settled after it (A04-A06) - begin on a production not as the done
# steps leave it (A07), check() red on an inventory difference alone (A08), the step's apps passed to the settle (A10),
# inventory-diff.sh's failure (A11). The module loaded, its calls to hosts replaced.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=$(command -v python3)
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - "$PWD" <<'PY_RUNNER_REFUSALS'
import datetime, importlib.machinery, importlib.util, json, os, subprocess, sys, tempfile
ops = sys.argv[1]
os.environ.update(GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
L = importlib.machinery.SourceFileLoader("up", os.path.join(ops, "scripts", "upgrade-production.py"))
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("up", L))
L.exec_module(m)
# anything that reaches a host fails here unless a case stubs it (a case once ran production's data check for real)
def _unstubbed(name):
    def f(*a, **k):
        raise RuntimeError(f"runner-refusals: {name}() not stubbed - it would reach a host")
    return f
for _n in ("ansible", "remote", "ten", "host_work"):
    setattr(m, _n, _unstubbed(_n))
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
def patched(**kw):
    saved = {k: getattr(m, k) for k in kw}
    for k, v in kw.items():
        setattr(m, k, v)
    return saved
def restore(saved):
    for k, v in saved.items():
        setattr(m, k, v)
class R:
    def __init__(self, rc=0, out="", err=""):
        self.returncode, self.stdout, self.stderr = rc, out, err

# A01: an unmerged branch whose change is not the one the full run proved
T = tempfile.mkdtemp()
g = lambda *a: subprocess.run(["git", "-C", os.path.join(T, "infra"), *a], check=True, capture_output=True, text=True).stdout.strip()
subprocess.run(["git", "init", "-q", "--bare", "-b", "main", os.path.join(T, "origin.git")], check=True)
subprocess.run(["git", "clone", "-q", os.path.join(T, "origin.git"), os.path.join(T, "infra")], check=True, capture_output=True)
open(os.path.join(T, "infra", "f"), "w").write("base\n"); g("add", "f"); g("commit", "-qm", "base"); g("push", "-q", "origin", "main")
g("checkout", "-qb", "upgrade/06-f"); open(os.path.join(T, "infra", "f"), "a").write("proven\n"); g("commit", "-qam", "proven")
os.makedirs(os.path.join(T, "ops")); os.makedirs(os.path.join(T, "proven"))
s = patched(OPS=os.path.join(T, "ops"), PROVEN=os.path.join(T, "proven"), floating_problems=lambda *a: [],
            app_tag_problems=lambda *a: [], unproven_changes=lambda *a: [], main_problems=lambda *a: [],
            ansible_now=lambda: "A")
own = m.own_change(os.path.join(T, "infra"), "origin/main", "upgrade/06-f")
json.dump({"run": "r", "ops": "x", "floating": {"a": "b"}, "repos": {"infra": {"own": own}}, "complete": True, "ansible": "A"},
          open(m.proof_path("06-f"), "w"))
check("A01 the proven branch: no problem", m.proof_problems("06-f", ["06-f"], "infra"), [])
open(os.path.join(T, "infra", "f"), "a").write("unproven\n"); g("commit", "-qam", "unproven")
got = m.proof_problems("06-f", ["06-f"], "infra")
check("A01 a commit added after the proof: refused", any("is not the change the full run proved" in p for p in got), True)
# A22: origin's main moved on (another step merged) and the branch not restacked onto it
g("reset", "-q", "--hard", "HEAD~1")
other = os.path.join(T, "other")
subprocess.run(["git", "clone", "-q", os.path.join(T, "origin.git"), other], check=True, capture_output=True)
open(os.path.join(other, "g"), "w").write("x\n")
for a in (["add", "g"], ["commit", "-qm", "another step"], ["push", "-q", "origin", "main"]):
    subprocess.run(["git", "-C", other, *a], check=True, capture_output=True)
got = m.proof_problems("06-f", ["06-f"], "infra")
check("A22 the branch not on origin's main (moved on): refused, restack named",
      any("does not contain origin/main" in p for p in got), True)
# A02: the steps before proven by another run, or not at all
N3 = m.step_names()[:3]
for st, run in zip(N3, ("r1", "r2", "r2")):
    json.dump({"run": run, "ops": "x", "floating": {"a": "b"}, "repos": {}, "complete": True, "ansible": "A"},
              open(m.proof_path(st), "w"))
check("A02 the same run throughout: none", m.proof_problems(N3[2], N3[1:]), [])
got = m.proof_problems(N3[2], N3)
check("A02 an earlier step proven by another run: refused", any(f"{N3[0]} was not proven by the same full run" in p for p in got), True)
os.remove(m.proof_path(N3[0]))
got = m.proof_problems(N3[2], N3)
check("A02 an earlier step not proven at all: refused", any(f"{N3[0]} was not proven by the same full run" in p for p in got), True)
restore(s)
# A03: a floating tag on ten naming another build than the full run ran
listing = ("REF TYPE DIGEST SIZE PLATFORMS LABELS\n"
           "docker.io/library/postgres:17 application/vnd.oci.image.index.v1+json sha256:bbb 1 linux/amd64 -\n")
s = patched(ten=lambda c, **k: R(0, listing))
check("A03 another build under the tag: named",
      len(m.floating_problems({"docker.io/library/postgres:17": "sha256:aaa"}, ["image postgres 17"])), 1)
check("A03 the same build: none", m.floating_problems({"docker.io/library/postgres:17": "sha256:bbb"}, ["image postgres 17"]), [])
restore(s)

# A04-A06: merge's refusals on a failed merge-order check, a failed Tempo flush, Argo not settled
def merge_calls(step, repo, fail=(), settled_ok=True, events=None):
    calls = []
    names = m.step_names()
    def run(cmd, **k):
        base = os.path.basename(cmd[0])
        calls.append(base)
        if "rev-parse" in cmd:
            return R(0, "c" * 40)
        return R(1 if base in fail else 0)
    def remote(host, command, stdin=None, timeout=None, capture=True):
        calls.append("tempo-flush" if "flush" in (stdin or "") else "remote")
        return R(1 if "tempo-flush" in fail else 0)
    s = patched(ledger_for=lambda st, ph, arg=None: (names, events or [], m.step_info(st)), proof_problems=lambda *a, **k: [],
                registry_problems=lambda *a, **k: [], run=run, remote=remote, confirm=lambda q: True,
                ansible=lambda *a: calls.append(a[0]) or True, prepull_images=lambda *a: [],
                merged_base=lambda *a: None, pushed_base=lambda *a: None, read_ledger=lambda: ({"data": {"events": ""}}, []),
                record=lambda st, ev, *a, **k: calls.append("record " + ev), step_apps=lambda *a: ["app"],
                settled=lambda *a, **k: (settled_ok, dict.fromkeys(m.URLS.values(), "r"), ["app"]),
                cluster_runs=lambda *a: False, claim_problems=lambda *a: [], merged_live_problems=lambda *a: [],
                host_work=lambda cmd, **k: calls.append(os.path.basename(cmd[0])) or R(0))
    try:
        m.merge(step, repo)
        calls.append("returned")
    except SystemExit as e:
        calls.append("refused")
    finally:
        restore(s)
    return calls
# the control: the same merges with nothing failing push and record settled - each refusal below is that one
for st in ("47-postgres-18", "54-tempo-3", "57-sonarqube-26.9"):
    got = merge_calls(st, "infra")
    check(f"A04-A06 control: {st} with nothing failing pushed, settled recorded",
          ("upgrade-merge-step.sh" in got, "record settled" in got), (True, True))
got = merge_calls("47-postgres-18", "infra", fail=("upgrade-merge-order.py",))
check("A04 the merge-order check failing: refused, nothing pushed",
      ("upgrade-merge-step.sh" in got, got[-1]), (False, "refused"))
got = merge_calls("54-tempo-3", "infra", fail=("tempo-flush",))
check("A05 Tempo's flush failing: refused, nothing pushed", ("upgrade-merge-step.sh" in got, got[-1]), (False, "refused"))
got = merge_calls("57-sonarqube-26.9", "infra", settled_ok=False)
check("A06 Argo not settled after the merge: refused, no settled recorded",
      ("record settled" in got, got[-1]), (False, "refused"))
# A07: begin with production not as the done steps leave it
def begin_calls(inv_ok, settle_ok):
    calls = []
    names = m.step_names()
    s = patched(ledger_for=lambda st, ph, arg=None: (names, [], m.step_info(st)), proof_problems=lambda *a, **k: [],
                vault_login_problems=lambda: [], inventory_check=lambda *a: inv_ok,
                settled=lambda *a, **k: (settle_ok, {}, ["app"]), record=lambda st, ev, *a, **k: calls.append(ev))
    try:
        m.begin("01-argocd-root-retry")
        calls.append("returned")
    except SystemExit:
        calls.append("refused")
    finally:
        restore(s)
    return calls
check("A07 control: begin as the done steps leave production: recorded", begin_calls(True, True)[-1], "returned")
check("A07 begin, the inventory differing: refused, nothing recorded", begin_calls(False, True), ["refused"])
check("A07 begin, Argo not settled: refused, nothing recorded", begin_calls(True, False), ["refused"])
# A08: check() red on an inventory difference alone
def check_with(inventory_ok):
    s = patched(read_ledger=lambda: (None, []), inventory_check=lambda *a: inventory_ok,
                settled=lambda *a, **k: (True, {}, []), ansible=lambda *a: True, running_digest_problems=lambda *a: [])
    try:
        return m.check("01-argocd-root-retry")
    finally:
        restore(s)
check("A08 control: check with every part green is green", check_with(True), True)
check("A08 check: an inventory difference alone is red", check_with(False), False)
# A10: the step's app set reaches argo-settled as --expect-apps
sent = []
s = patched(main_revisions=lambda: dict.fromkeys(m.URLS.values(), "r"),
            remote=lambda h, c, stdin=None, timeout=None, capture=True: sent.append(c) or R(0, "APPS a,b\n"))
m.settled(1, [], ["a", "b"])
restore(s)
check("A10 settled(apps): --expect-apps a,b", "--expect-apps a,b" in sent[0], True)
# A11: inventory-diff.sh red is the inventory check red
s = patched(ten=lambda c, stdin=None, check=True: R(0, ""), remote=lambda *a, **k: R(0, ""),
            run=lambda cmd, **k: R(1 if cmd[0].endswith("inventory-diff.sh") else 0), WORK=tempfile.mkdtemp())
check("A11 inventory-diff.sh failing: the check is red", m.inventory_check([]), False)
restore(s)
# M01: a step line whose "before" is not in the inventory at that step (a stale step file): stops
def expected_with(line):
    d = tempfile.mkdtemp()
    os.makedirs(os.path.join(d, "steps"))
    open(os.path.join(d, "prod-inventory.txt"), "w").write("image a 1\n")
    open(os.path.join(d, "steps", "01-x.txt"), "w").write(line + "\n")
    saved = (m.inv.UPGRADE, m.inv.STEPS)
    m.inv.UPGRADE, m.inv.STEPS = d, os.path.join(d, "steps")
    try:
        return sorted(m.inv.expected(["01-x"]))
    except SystemExit as e:
        return "stale" if "the step file is stale" in str(e.code) else str(e.code)
    finally:
        m.inv.UPGRADE, m.inv.STEPS = saved
check("M01 control: a line from what the inventory holds applies", expected_with("image a 1 => image a 2"), ["image a 2"])
check("M01 a line from what it does not hold: stopped as stale", expected_with("image a 0 => image a 2"), "stale")
# S6: a step's wave0 backup and its preview fresh where the one-way change goes live (merge, playbooks)
st = "43-kubernetes-1.36"
info43 = m.step_info(st)
now = datetime.datetime.now(datetime.timezone.utc)
ago = lambda h: now - datetime.timedelta(hours=h)
def ev(backup_h, preview_h=None, settled=False):
    out = [(ago(30), st, "begun", []), (ago(backup_h), st, "backup", ["etcd"])]
    if settled:
        out += [(ago(1), st, "merged", ["infra", "c" * 40]), (ago(1), st, "settled", ["infra", "r"])]
    if preview_h is not None:
        out += [(ago(preview_h), st, "previewed", [])]
    return out
fresh = lambda ps: [p for p in ps if "ago" in p]
check("S6 control: a backup an hour old - the merge may run", fresh(m.problems(m.step_names(), st, "merge", ev(1), info43, "infra")), [])
check("S6 a backup 7 h old: the merge refused, named", len(fresh(m.problems(m.step_names(), st, "merge", ev(7), info43, "infra"))), 1)
check("S6 control: backup and preview an hour old - the playbooks may run",
      fresh(m.problems(m.step_names(), st, "playbooks", ev(1, 1, True), info43)), [])
check("S6 a preview 7 h old: the playbooks refused, named",
      len(fresh(m.problems(m.step_names(), st, "playbooks", ev(1, 7, True), info43))), 1)
check("S6 a backup 7 h old: the playbooks refused too (the kubeadm upgrade is the one-way change)",
      len(fresh(m.problems(m.step_names(), st, "playbooks", ev(7, 1, True), info43))), 1)
print("runner-refusals: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_RUNNER_REFUSALS
