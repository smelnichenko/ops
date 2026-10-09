#!/bin/bash
# What makes a full run's proof a proof, on throwaway repos: proof-start refuses an ops tree not committed - the
# Taskfile and the Vagrantfile among the proven paths; record_proof refuses an ops tree changed during the run and a
# step branch moved during the step; production's defaults phase refuses ops off main or not at origin/main. Each
# with its control, which goes on past that check (to a sentinel).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - "$PWD" <<'PY_PROOF_INTEGRITY'
import importlib.machinery, importlib.util, json, os, subprocess, sys, tempfile
src = sys.argv[1]
os.environ.update(GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
L = importlib.machinery.SourceFileLoader("up", os.path.join(src, "scripts", "upgrade-production.py"))
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("up", L))
L.exec_module(m)
def _unstubbed(name):
    def f(*a, **k):
        raise RuntimeError(f"proof-integrity: {name}() not stubbed - it would reach a host")
    return f
for _n in ("ansible", "remote", "ten", "host_work"):
    setattr(m, _n, _unstubbed(_n))
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
class Stop(Exception):
    pass
def stop(*a, **k):
    raise Stop()
class R:
    def __init__(self, rc=0, out=""):
        self.returncode, self.stdout, self.stderr = rc, out, ""
def outcome(f, *a):
    try:
        f(*a)
        return "returned"
    except Stop:
        return "past it"
    except SystemExit as e:
        return "REFUSED: " + str(e.code)
def git(d, *a):
    return subprocess.run(["git", "-C", d, *a], check=True, capture_output=True, text=True).stdout.strip()
def repos():
    """A root with ops (a clone of a bare origin, the proven paths committed), infra and platform (branch upgrade/02-b)."""
    t = tempfile.mkdtemp()
    subprocess.run(["git", "init", "-q", "--bare", "-b", "main", os.path.join(t, "ops.git")], check=True)
    subprocess.run(["git", "clone", "-q", os.path.join(t, "ops.git"), os.path.join(t, "ops")], check=True, capture_output=True)
    o = os.path.join(t, "ops")
    for p in ("scripts/x.py", "deploy/a.yml", "tests/t.sh", "Taskfile.yml", "Vagrantfile", "docs/n.md"):
        os.makedirs(os.path.dirname(os.path.join(o, p)) or o, exist_ok=True)
        open(os.path.join(o, p), "w").write("one\n")
    git(o, "add", "-A"); git(o, "commit", "-qm", "base"); git(o, "push", "-q", "origin", "main")
    for r in ("infra", "platform"):
        d = os.path.join(t, r)
        subprocess.run(["git", "init", "-q", "-b", "main", d], check=True)
        git(d, "commit", "-q", "--allow-empty", "-m", "base"); git(d, "branch", "upgrade/02-b")
    m.OPS, m.PROVEN = o, os.path.join(t, "proven")
    os.makedirs(m.PROVEN)
    return t, o
def patched(**kw):
    saved = {k: getattr(m, k) for k in kw}
    for k, v in kw.items():
        setattr(m, k, v)
    return saved
def restore(saved):
    for k, v in saved.items():
        setattr(m, k, v)
names = lambda: ["01-a", "02-b"]

# proof-start: the proven paths committed - the sentinel is the Ansible check that comes after
def start(edit):
    t, o = repos()
    if edit:
        open(os.path.join(o, edit), "a").write("changed\n")
    s = patched(step_names=names, ansible_now=stop)
    sd = (m.dflt.default_lines, m.dflt.pending)
    m.dflt.default_lines, m.dflt.pending = (lambda st: []), (lambda read: [])
    try:
        return outcome(m.proof_start)
    finally:
        restore(s)
        m.dflt.default_lines, m.dflt.pending = sd
check("proof-start control: a committed tree goes on", start(None), "past it")
check("proof-start control: a change outside the proven paths goes on", start("docs/n.md"), "past it")
for p in ("scripts/x.py", "Taskfile.yml", "Vagrantfile"):
    got = start(p)
    check(f"proof-start: {p} not committed - refused", (got.startswith("REFUSED"), "not committed" in got), (True, True))

# record_proof: the ops tree as the run started - the sentinel is the step list read after the branch check
def record_ops(edit):
    t, o = repos()
    json.dump({"ops": git(o, "rev-parse", "HEAD"), "run": "r", "branches": {}}, open(os.path.join(m.PROVEN, "run.json"), "w"))
    if edit:
        open(os.path.join(o, edit), "a").write("changed\n"); git(o, "commit", "-qam", "during")
    s = patched(step_names=stop, branch_moves=lambda *a: [])
    try:
        return outcome(m.record_proof, "02-b", "a", "b")
    finally:
        restore(s)
check("record_proof control: the ops tree as the run started goes on", record_ops(None), "past it")
check("record_proof control: a change outside the proven paths goes on", record_ops("docs/n.md"), "past it")
for p in ("scripts/x.py", "Taskfile.yml"):
    got = record_ops(p)
    check(f"record_proof: {p} changed during the run - refused", "the ops tree changed during the run" in got, True)

# record_proof: the step's branch as the step ran it
def record_sha(moved):
    t, o = repos()
    json.dump({"ops": git(o, "rev-parse", "HEAD"), "run": "r", "branches": {}}, open(os.path.join(m.PROVEN, "run.json"), "w"))
    shas = {r: git(os.path.join(t, r), "rev-parse", "upgrade/02-b") for r in ("infra", "platform")}
    if moved:
        d = os.path.join(t, "infra")
        git(d, "checkout", "-q", "upgrade/02-b"); git(d, "commit", "-q", "--allow-empty", "-m", "moved")
    real = m.run
    written = []
    s = patched(ops_unchanged_since=lambda *a: [], branch_moves=lambda *a: [], step_names=names,
                run=lambda cmd, **k: R(0, "upgrade/02-b upgrade/02-b") if cmd[0] == m.INVENTORY else real(cmd, **k),
                step_digests=lambda *a: {}, step_images=lambda *a: [], floating_digests=lambda: {},
                step_info=lambda st: {"branches": ["infra"]}, own_change=lambda *a: "own", pin_problems=lambda *a: [],
                write_json=lambda path, data, **k: written.append(path))
    try:
        return outcome(m.record_proof, "02-b", shas["infra"], shas["platform"]), len(written)
    finally:
        restore(s)
check("record_proof control: the branches as the step ran them - the proof written", record_sha(False), ("returned", 1))
got = record_sha(True)
check("record_proof: infra's branch moved during the step - refused, nothing written",
      ("moved during the step" in got[0], got[1]), (True, 0))

# defaults: ops on main and at origin/main - the sentinel is the default lines' apply that comes after
def defaults(state):
    t, o = repos()
    if state == "branch":
        git(o, "checkout", "-q", "-b", "elsewhere")
    elif state == "ahead":
        open(os.path.join(o, "docs/n.md"), "a").write("x\n"); git(o, "commit", "-qam", "local only")
    real = m.run
    s = patched(ledger_for=lambda st, ph, arg=None: (names(), [], {}), proof_problems=lambda *a, **k: [],
                merged_live_problems=lambda *a: [], step_info=lambda st: {"branches": []},
                run=lambda cmd, **k: stop() if cmd[0].endswith("upgrade-defaults.py") else real(cmd, **k))
    try:
        return outcome(m.defaults, "02-b")
    finally:
        restore(s)
check("defaults control: on main at origin/main goes on", defaults(None), "past it")
check("defaults: ops on another branch - refused", "ops is not on main" in defaults("branch"), True)
check("defaults: ops main ahead of origin/main - refused", "ops is not at origin/main" in defaults("ahead"), True)
# defaults resumed: its commit made (and pushed or not) by a run cut short before its ledger record, then another ops
# commit on top - pushed: recorded; not pushed: refused (its push would carry the later commit unasked)
def defaults_resume(pushed):
    t, o = repos()
    rel = m.dflt.COMMITTED
    os.makedirs(os.path.dirname(os.path.join(o, rel)), exist_ok=True)
    open(os.path.join(o, rel), "a").write("02-b\n")
    git(o, "add", rel); git(o, "commit", "-qm", "upgrade 02-b: its playbook defaults (in production)")
    if pushed:
        git(o, "push", "-q", "origin", "main")
    open(os.path.join(o, "docs/n.md"), "a").write("later\n"); git(o, "commit", "-qam", "a later ops commit")
    if pushed:
        git(o, "push", "-q", "origin", "main")
    recorded = []
    s = patched(ledger_for=lambda st, ph, arg=None: (names(), [], {}), proof_problems=lambda *a, **k: [],
                record=lambda st, ev, *a: recorded.append(ev), confirm=lambda q: False)
    try:
        return outcome(m.defaults, "02-b"), recorded
    finally:
        restore(s)
got = defaults_resume(True)
check("defaults resumed, its commit pushed, ops past it: recorded", got, ("returned", ["defaults"]))
got = defaults_resume(False)
check("defaults resumed, its commit not pushed, ops past it: refused, nothing recorded",
      ("past the step's commit" in got[0], got[1]), (True, []))
print("proof-integrity: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_PROOF_INTEGRITY
