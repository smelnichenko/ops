#!/bin/bash
# A full run that starts where production stands (scripts/upgrade-production.py resume-from, proof-start <from>): once
# production has done steps, a run from the first step it has not done - the copy built as those steps left
# production - proves the rest. In a throwaway ops repo with the real scripts:
#   resume-from: the first step the ledger has not done (no ledger: the first step); every step done: nothing to run
#   proof-start <from>: the tree's committed playbook defaults are exactly the steps before <from> with default lines
#     (production commits each step's before its done) - another set refused; <from> recorded in run.json
#   the proof: a step before the run's start must be done in production's ledger; from the start on, every step up to
#     the one asked about proven by the same run
#   the copy's build at a step: the setup-kubeadm arguments of every step up to it (their base lines), in step order
set -u
src=$(cd "$(dirname "$0")/../../../.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
o=$W/ops
mkdir -p "$o/scripts" "$o/deploy/ansible/playbooks" "$o/tests/ansible/upgrade/steps"
for f in upgrade-production.py upgrade-defaults.py upgrade-expected-inventory.py; do
  cp "$src/scripts/$f" "$o/scripts/"
done
printf 'foo_version: "1.0"\nbar_version: "1.0"\n' > "$o/deploy/ansible/playbooks/x.yml"
cat > "$o/tests/ansible/upgrade/steps/01-a.txt" <<'STEP'
image a 1 => image a 2
default deploy/ansible/playbooks/x.yml: foo_version: "1.0" => foo_version: "2.0"
base -e kubelet_x=true
STEP
printf 'image b 1 => image b 2\n' > "$o/tests/ansible/upgrade/steps/02-b.txt"
cat > "$o/tests/ansible/upgrade/steps/03-c.txt" <<'STEP'
image c 1 => image c 2
default deploy/ansible/playbooks/x.yml: bar_version: "1.0" => bar_version: "2.0"
base -e helm_y=false
STEP
printf '# committed steps\n' > "$o/tests/ansible/upgrade/defaults-committed.txt"
printf 'image a 1\nimage b 1\nimage c 1\n' > "$o/tests/ansible/upgrade/prod-inventory.txt"
cp "$src/.gitignore" "$o/.gitignore"
git -C "$o" init -q -b main && git -C "$o" add -A && git -C "$o" commit -q -m start
# the repos proof-start reads the step branches and main of, each with its origin
for r in infra platform; do
  git init -q --bare -b main "$W/$r.git" && git clone -q "$W/$r.git" "$W/$r" 2> /dev/null
  mkdir -p "$W/$r/clusters/production/app" && echo v1 > "$W/$r/clusters/production/app/values.yaml"
  git -C "$W/$r" add -A && git -C "$W/$r" commit -q -m main && git -C "$W/$r" push -q origin main
done
SRC=$src PYTHONDONTWRITEBYTECODE=1 python3 - "$o" <<'PY'
import contextlib, datetime, importlib.machinery, importlib.util, io, json, os, subprocess, sys
o = sys.argv[1]
loader = importlib.machinery.SourceFileLoader("up", os.path.join(o, "scripts", "upgrade-production.py"))
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("up", loader))
loader.exec_module(m)
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


def exits(f, *a):
    """f(*a)'s sys.exit message, or None when it returned."""
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            f(*a)
    except SystemExit as e:
        return str(e.code)
    return None


names = m.step_names()
at = datetime.datetime(2026, 10, 9, tzinfo=datetime.timezone.utc)
done = lambda *steps: [(at, s, "done", []) for s in steps]
resume = getattr(m, "resume_from", None)
check("resume-from: no ledger - the first step", resume(None) if resume else None, "01-a")
check("resume-from: the first step the ledger has not done", resume(done("01-a")) if resume else None, "02-b")
check("resume-from: a step done out of order counts only from the first not done",
      resume(done("01-a", "03-c")) if resume else None, "02-b")
check("resume-from: every step done - refused, nothing to run",
      "every step" in (exits(resume, done("01-a", "02-b", "03-c")) or "") if resume else None, True)

# proof-start from a step: the tree's committed defaults exactly the earlier steps' that have default lines
git = lambda *a: subprocess.run(["git", "-C", o, *a], capture_output=True, text=True, check=True).stdout
start = lambda *a: exits(m.proof_start, *a)
check("proof-start from the first step, nothing committed: taken", start("01-a"), None)
check("  run.json records where the run starts", json.load(open(os.path.join(o, ".upgrade/proven/run.json"))).get("from"),
      "01-a")
check("proof-start from 02-b with 01-a's defaults not committed: refused",
      "defaults" in (start("02-b") or ""), True)
subprocess.run([os.path.join(o, "scripts", "upgrade-defaults.py"), "--apply", "01-a"], check=True,
               capture_output=True)
git("commit", "-qam", "01-a defaults")
check("proof-start from 02-b with 01-a's defaults committed: taken", start("02-b"), None)
check("  run.json records 02-b", json.load(open(os.path.join(o, ".upgrade/proven/run.json"))).get("from"), "02-b")
check("proof-start from 03-c: taken (02-b has no default lines)", start("03-c"), None)
check("proof-start from 01-a with 01-a's defaults committed already: refused",
      "defaults" in (start("01-a") or ""), True)
check("proof-start from no step: refused", "no step" in (start("09-z") or ""), True)

# the proof of a step in a run from 02-b: 01-a by production's ledger, 02-b on by the run
m.app_tag_problems = lambda: []
m.unproven_changes = lambda *a, **k: []
m.floating_problems = lambda *a, **k: []
os.makedirs(m.PROVEN, exist_ok=True)


def prove(step, run, frm):
    m.write_json(m.proof_path(step), {"step": step, "run": run, "from": frm, "ops": "x", "repos": {},
                                      "floating": {"i:1": "sha256:1"}, "digests": {}})


for s in names:
    if os.path.exists(m.proof_path(s)):
        os.remove(m.proof_path(s))
prove("02-b", "R", "02-b")
prove("03-c", "R", "02-b")
about = lambda out: [p for p in out if "same full run" in p or "not done" in p]
pp = lambda step, done_steps: about(m.proof_problems(step, names, done=done_steps)) \
    if "done" in m.proof_problems.__code__.co_varnames else ["proof_problems takes no done steps"]
check("03-c: 01-a done in production, 02-b and 03-c by one run from 02-b - no problem", pp("03-c", ["01-a"]), [])
check("03-c: 01-a not done in production - refused",
      [p.split(" -")[0] for p in pp("03-c", [])], ["01-a is not done in production"])
prove("02-b", "R2", "02-b")
check("03-c: 02-b proven by another run - refused", len(pp("03-c", ["01-a"])), 1)
prove("02-b", "R", "02-b")
prove("01-a", "R0", "01-a")
check("02-b: 01-a done in production - its own older proof does not matter", pp("02-b", ["01-a"]), [])
prove("03-c", "R", "01-a")
check("03-c: a run from 01-a - 01-a must be proven by it, done or not", len(pp("03-c", ["01-a"])), 1)

# a proof counts only once its run completed - every step, then the backups restored at its end (proof-complete marks
# the run's proofs then; a run that failed at its end, or stopped at a step, leaves its proofs unmarked)
complete = getattr(m, "proof_complete", None)
incomplete = lambda step: [p for p in m.proof_problems(step, names, done=["01-a"]) if "did not complete" in p]
prove("02-b", "R", "02-b")
prove("03-c", "R", "02-b")
check("a proof of a run not marked complete: refused", len(incomplete("03-c")), 1)
json.dump({"ops": "x", "run": "R", "from": "02-b", "branches": {}}, open(os.path.join(m.PROVEN, "run.json"), "w"))
prove("01-a", "OTHER", "01-a")
check("proof-complete: taken", exits(complete) if complete else "no proof_complete", None)
check("  the run's proofs marked, another run's not",
      [json.load(open(m.proof_path(s_))).get("complete") for s_ in ("01-a", "02-b", "03-c")], [None, True, True])
check("a proof of a run marked complete: no problem", incomplete("03-c"), [])
os.remove(os.path.join(m.PROVEN, "run.json"))
check("proof-complete with no run started: refused", exits(complete) is not None if complete else None, True)

# the main the run mirrored (each repo's, local main = origin's at its start), recorded; production's main then may hold
# only the merged steps' commits and changes that render nothing for production (CD's test deploys, CI, docs)
W_ = os.path.dirname(o)
git_ = lambda r, *a: subprocess.run(["git", "-C", os.path.join(W_, r), *a], capture_output=True, text=True,
                                    check=True).stdout.strip()
for f in ("01-a", "02-b", "03-c"):
    if os.path.exists(m.proof_path(f)):
        os.remove(m.proof_path(f))
check("proof-start: local main as origin's - taken", start("03-c"), None)
run_main = json.load(open(os.path.join(m.PROVEN, "run.json"))).get("main")
check("  each repo's main recorded", run_main, {r: git_(r, "rev-parse", "main") for r in ("infra", "platform")})


def commit(repo, path, text, msg, push=True):
    full = os.path.join(W_, repo, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    open(full, "w").write(text)
    git_(repo, "add", "-A")
    git_(repo, "commit", "-qm", msg)
    if push:
        git_(repo, "push", "-q", "origin", "main")


commit("infra", "clusters/production/x.yaml", "local\n", "local only", push=False)
check("proof-start: local main ahead of origin's - refused", "origin" in (start("03-c") or ""), True)
git_("infra", "push", "-q", "origin", "main")
check("proof-start again, main pushed: taken", start("03-c"), None)
run_main = json.load(open(os.path.join(m.PROVEN, "run.json"))).get("main")
mp = getattr(m, "main_problems", None)
main_of = lambda: mp({"main": run_main}) if mp else ["no main_problems"]
check("main as the run mirrored it: no problem", main_of(), [])
commit("infra", "clusters/production/schnappy-test-apps/values.yaml", "t: 1\n", "deploy(test): x=1")
commit("platform", ".woodpecker/ci.yaml", "steps: {}\n", "ci: a step")
commit("platform", "helm/x/runbooks/README.md", "# r\n", "docs")
check("CD's test deploy, CI and docs since: no problem", main_of(), [])
commit("platform", "helm/schnappy/values.yaml", "masi: {}\n", "masi: a host")
got = main_of()
check("a change production renders since: refused, the commit and file named",
      (len(got), "helm/schnappy/values.yaml" in str(got), "masi: a host" in str(got)), (1, True, True))
git_("platform", "reset", "-q", "--hard", "HEAD~1")
git_("platform", "push", "-q", "-f", "origin", "main")
# a merged step's own commits: production's merges of the steps after the run's start
git_("infra", "checkout", "-q", "-b", "upgrade/03-c")
commit("infra", "clusters/production/app/values.yaml", "v2\n", "03-c", push=False)
git_("infra", "checkout", "-q", "main")
git_("infra", "merge", "-q", "--ff-only", "upgrade/03-c")
git_("infra", "push", "-q", "origin", "main")
git_("infra", "tag", "-m", "base x", "upgrade-merged/03-c", "upgrade/03-c")
check("a merged step's commit since: no problem", main_of(), [])
git_("infra", "tag", "-d", "upgrade-merged/03-c")
check("the same commit with no merged tag: refused", len(main_of()), 1)
check("a proof with no main recorded: refused", len(mp({}) if mp else [None]) >= 1, True)
kept_mp, m.main_problems = m.main_problems, (lambda proof: ["MAIN-X"])
prove("03-c", "R", "02-b")
check("every proof check judges production's main", "MAIN-X" in m.proof_problems("03-c", names, done=["01-a"]), True)
m.main_problems = kept_mp

# the copy's build at a step: every base line up to it
inv = lambda *a: subprocess.run([os.path.join(o, "scripts", "upgrade-expected-inventory.py"), *a],
                                capture_output=True, text=True)
check("--base-args 01-a", inv("--base-args", "01-a").stdout.strip(), "-e kubelet_x=true")
check("--base-args 02-b (none of its own)", inv("--base-args", "02-b").stdout.strip(), "-e kubelet_x=true")
check("--base-args 03-c, in step order", inv("--base-args", "03-c").stdout.strip(),
      "-e kubelet_x=true -e helm_y=false")
check("the inventory still reads a step with a base line", inv("03-c").returncode, 0)
# the copy is built after the step before the run's start (none before the first: production's baseline)
check("--before 01-a: none", (inv("--before", "01-a").returncode, inv("--before", "01-a").stdout.strip()), (0, ""))
check("--before 03-c: 02-b", inv("--before", "03-c").stdout.strip(), "02-b")
check("--before a step that is none: refused", inv("--before", "09-z").returncode, 1)
# the boot's checks of the steps' merges and Helm renders: from the run's start on (the steps before it are merged)
for script in ("upgrade-merge-order.py", "argo-helm-diff.py"):
    import shutil
    shutil.copy(os.path.join(os.environ["SRC"], "scripts", script), os.path.join(o, "scripts", script))
    r = subprocess.run([os.path.join(o, "scripts", script), "--from", "09-z"], capture_output=True, text=True)
    check(f"{script} --from a step that is none: refused, named", (r.returncode, "no step 09-z" in r.stderr), (1, True))
    # the steps it judges: from the given one on, every one
    sl = importlib.machinery.SourceFileLoader(script, os.path.join(o, "scripts", script))
    mod = importlib.util.module_from_spec(importlib.util.spec_from_loader(script, sl))
    sl.exec_module(mod)
    seen = []
    mod.check = lambda st: seen.append(st) or True
    sys.argv = [script, "--from", "02-b"]
    try:
        mod.main()
        code = 0
    except SystemExit as e:
        code = e.code
    check(f"{script} --from 02-b: 02-b and 03-c judged, all green", (code, seen), (0, ["02-b", "03-c"]))
print("upgrade-resume: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
