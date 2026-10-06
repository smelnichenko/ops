#!/bin/bash
# What production refuses as changed since the full run's proof (scripts/upgrade-production.py unproven_changes): the
# whole tree the proof covers - playbooks, every step file, the inventories and allow-lists, the scripts that judge a
# step green - but for the committed steps' playbook default lines. In a throwaway ops repo with the real scripts.
set -u
src=$(cd "$(dirname "$0")/../../../.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
o=$W/ops
mkdir -p "$o/scripts" "$o/deploy/ansible/playbooks" "$o/tests/ansible/upgrade/steps" "$o/docs"
for f in upgrade-production.py upgrade-defaults.py upgrade-expected-inventory.py; do
  cp "$src/scripts/$f" "$o/scripts/"
done
printf 'other: 1\nfoo_version: "1.0"\n' > "$o/deploy/ansible/playbooks/x.yml"
printf 'default deploy/ansible/playbooks/x.yml: foo_version: "1.0" => foo_version: "2.0"\n' \
  > "$o/tests/ansible/upgrade/steps/01-a.txt"
printf '# nothing\n' > "$o/tests/ansible/upgrade/steps/02-b.txt"
printf 'default deploy/ansible/playbooks/x.yml: other: 1 => other: 2\n' > "$o/tests/ansible/upgrade/steps/03-c.txt"
printf '# committed steps\n' > "$o/tests/ansible/upgrade/defaults-committed.txt"
printf 'image a 1\n' > "$o/tests/ansible/upgrade/prod-inventory.txt"
printf '#!/bin/sh\n' > "$o/scripts/inventory-diff.sh"
printf 'notes\n' > "$o/docs/n.md"
cp "$src/.gitignore" "$o/.gitignore"  # as ops ignores them (bytecode, .upgrade/)
git -C "$o" init -q -b main && git -C "$o" add -A && git -C "$o" commit -q -m proven
proven=$(git -C "$o" rev-parse HEAD)
python3 - "$o" "$proven" <<'PY'
import importlib.machinery, importlib.util, os, subprocess, sys
o, proven = sys.argv[1:]
loader = importlib.machinery.SourceFileLoader("up", os.path.join(o, "scripts", "upgrade-production.py"))
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("up", loader))
loader.exec_module(m)
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


def edit(path, text, mode="a"):
    with open(os.path.join(o, path), mode) as f:
        f.write(text)


def reset():
    subprocess.run(["git", "-C", o, "reset", "-q", "--hard", proven], check=True)
    subprocess.run(["git", "-C", o, "clean", "-qfd"], check=True)


X = "deploy/ansible/playbooks/x.yml"
defaults = lambda *a: subprocess.run([os.path.join(o, "scripts", "upgrade-defaults.py"), *a], capture_output=True,
                                     text=True)
check("the proven tree", m.unproven_changes(proven, []), [])
edit(X, 'other: 1\nfoo_version: "2.0"\n', "w")
check("a committed step's default line", m.unproven_changes(proven, ["01-a"]), [])
check("the same line, the step not committed", m.unproven_changes(proven, []), [X])
edit(X, "more: 2\n")
check("a playbook changed beyond the default line", m.unproven_changes(proven, ["01-a"]), [X])
reset()
for path in ("tests/ansible/upgrade/prod-inventory.txt", "scripts/inventory-diff.sh",
             "tests/ansible/upgrade/steps/02-b.txt"):
    edit(path, "x\n")
    check(f"edited: {path}", m.unproven_changes(proven, []), [path])
    reset()
edit("scripts/new-judge.sh", "#!/bin/sh\n")
check("an untracked script", m.unproven_changes(proven, []), ["scripts/new-judge.sh"])
reset()
edit("docs/n.md", "more\n")
check("docs are not proven", m.unproven_changes(proven, []), [])
reset()
# the defaults phase: --apply the next step only, its lines and the record; the proof check excuses exactly those
check("--apply out of order refuses", defaults("--apply", "03-c").returncode, 1)
check("--apply out of order: nothing written", m.unproven_changes(proven, []), [])
check("--apply the next step", defaults("--apply", "01-a").returncode, 0)
check("its lines and the record changed", m.unproven_changes(proven, []),
      ["deploy/ansible/playbooks/x.yml", "tests/ansible/upgrade/defaults-committed.txt"])
check("the proof check excuses both for the committed step", m.unproven_changes(proven, ["01-a"]), [])
check("--apply it again refuses", defaults("--apply", "01-a").returncode, 1)
check("the next one applies after it", defaults("--apply", "03-c").returncode, 0)
check("the proof check excuses both steps", m.unproven_changes(proven, ["01-a", "03-c"]), [])
check("but not with one step fewer", m.unproven_changes(proven, ["01-a"]),
      ["deploy/ansible/playbooks/x.yml", "tests/ansible/upgrade/defaults-committed.txt"])
check("lint after both", defaults("--lint").returncode, 0)
# a run proven after 01-a's defaults were committed (its commit carries them): only the later committed steps apply
subprocess.run(["git", "-C", o, "commit", "-q", "-am", "01-a and 03-c committed"], check=True)
reproven = subprocess.run(["git", "-C", o, "rev-parse", "HEAD"], capture_output=True, text=True,
                          check=True).stdout.strip()
check("a re-proof carrying the committed steps: nothing to excuse, nothing refused",
      m.unproven_changes(reproven, ["01-a", "03-c"]), [])

# the defaults phase cut short and run again: after a failed push, after a push whose ledger write failed
reset()
G = lambda *a: subprocess.run(["git", "-C", o, *a], capture_output=True, text=True, check=True).stdout.strip()
ORIGIN = os.path.join(os.path.dirname(o), "origin.git")
subprocess.run(["git", "init", "-q", "--bare", "-b", "main", ORIGIN], check=True)
G("remote", "add", "origin", ORIGIN)
G("push", "-q", "origin", "main")
recorded = []
m.ledger_for = lambda st, ph, arg=None: (m.step_names(), [], None)
proof_problems, m.proof_problems = m.proof_problems, (lambda *a, **k: [])
m.record = lambda st, ev, *a: recorded.append((st, ev, *a))
last = lambda: recorded[-1] if recorded else ("nothing recorded",)  # a failure above must not hide the checks below


def phase(step):
    try:
        m.defaults(step)
        return "ok"
    except SystemExit as e:
        return f"refused {e}"
    except subprocess.CalledProcessError as e:
        return f"failed {' '.join(e.cmd[3:5])}"


# refused by the proof: nothing committed, pushed or recorded
head0 = G("rev-parse", "HEAD")
m.proof_problems = lambda *a, **k: ["PROOF-X"]
r = phase("01-a")
check("01 refused by the proof: nothing committed, pushed or recorded",
      ("PROOF-X" in r, G("rev-parse", "HEAD"), G("rev-parse", "origin/main"), len(recorded)), (True, head0, head0, 0))
m.proof_problems = lambda *a, **k: []
check("01: committed, pushed, recorded",
      (phase("01-a"), last()[:2], G("rev-parse", "origin/main") == G("rev-parse", "HEAD")),
      ("ok", ("01-a", "defaults"), True))
check("01's commit recorded", last()[2:3], (G("rev-parse", "HEAD"),))
G("remote", "set-url", "--push", "origin", "/nonexistent")  # the fetch still works
n = len(recorded)
check("03: the push fails, nothing recorded", (phase("03-c"), len(recorded)), ("failed push -q", n))
G("config", "--unset", "remote.origin.pushurl")
step03 = G("rev-parse", "HEAD")
# the resume refused by its proof - which it asks with the step's own lines committed: nothing pushed or recorded
asked = []
m.proof_problems = lambda *a, **k: asked.append(k.get("defaulted_steps")) or ["PROOF-X"]
r = phase("03-c")
check("03's resume refused by the proof (asked with 03 committed): nothing pushed or recorded",
      ("PROOF-X" in r, "03-c" in (asked[-1] if asked else []), G("rev-parse", "origin/main") != step03, len(recorded)),
      (True, True, True, n))
m.proof_problems = lambda *a, **k: []
check("03 again: its commit pushed and recorded, no second commit",
      (phase("03-c"), last(), G("rev-parse", "origin/main"), G("rev-parse", "HEAD")),
      ("ok", ("03-c", "defaults", step03), step03, step03))
recorded.pop()
check("03 once more (the ledger write lost): recorded, nothing pushed or committed",
      (phase("03-c"), last(), G("rev-parse", "HEAD")), ("ok", ("03-c", "defaults", step03), step03))
if recorded:
    recorded.pop()
edit("docs/n.md", "later\n")
G("commit", "-qam", "later")
after = phase("03-c")
check("a commit after the step's: refused", after.startswith("refused") and "past the step's commit" in after, True)

# the app tags the full run ran (the overlay's) against infra main's production values - pushed from another clone
# (as CD does): the checkout next to ops sees them only by fetching
infra = os.path.join(os.path.dirname(o), "infra")
writer = os.path.join(os.path.dirname(o), "infra-cd")
I = lambda *a: subprocess.run(["git", "-C", infra, *a], capture_output=True, text=True, check=True).stdout.strip()
Wr = lambda *a: subprocess.run(["git", "-C", writer, *a], capture_output=True, text=True, check=True).stdout.strip()
os.makedirs(os.path.join(o, os.path.dirname(m.APP_OVERLAY)), exist_ok=True)
subprocess.run(["git", "init", "-q", "--bare", "-b", "main", infra + ".git"], check=True)
subprocess.run(["git", "clone", "-q", infra + ".git", writer], check=True, capture_output=True)


def production_tags(app, chat):
    os.makedirs(os.path.join(writer, os.path.dirname(m.APP_VALUES)), exist_ok=True)
    with open(os.path.join(writer, m.APP_VALUES), "w") as f:
        f.write(f'app:\n  image:\n    tag: "{app}"\n  replicas: 2\nchatService:\n  image:\n    tag: "{chat}"\n')
    Wr("add", "-A")
    Wr("commit", "-qm", "tags")
    Wr("push", "-q", "origin", "HEAD:main")
    if not os.path.exists(infra):
        subprocess.run(["git", "clone", "-q", infra + ".git", infra], check=True, capture_output=True)


edit(m.APP_OVERLAY, 'app:\n  image:\n    tag: "c1"\n  resources:\n    requests: { memory: 1Gi }\n'
     'chatService:\n  resources:\n    requests: { memory: 768Mi }\n', "w")
production_tags("p1", "p2")
check("production runs another app tag: refused, naming it", m.app_tag_problems(),
      ["app: production runs p1, the full run ran c1 - promote it first, or drop the overlay's tag and prove again"])
os.makedirs(m.PROVEN, exist_ok=True)
with open(os.path.join(m.PROVEN, "01-a.json"), "w") as f:
    f.write('{"run": "r", "ops": "%s", "floating": ["x"]}' % proven)
m.floating_problems, m.unproven_changes = (lambda *a: []), (lambda *a: [])
check("every phase's proof check refuses it", any(p.startswith("app: production runs p1")
                                                  for p in proof_problems("01-a", ["01-a"])), True)
production_tags("c1", "p2")
check("the same tag, pushed by CD meanwhile (an overlay key with no tag is not compared)", m.app_tag_problems(), [])
check("every phase's proof check passes it", proof_problems("01-a", ["01-a"]), [])

# a step merged already (tagged upgrade-merged/<step>, "base <sha>"): its change base..tag must be the proven one
with open(os.path.join(writer, "step-file"), "w") as f:
    f.write("the step's change\n")
Wr("add", "-A")
Wr("commit", "-qm", "01-a")
Wr("push", "-q", "origin", "HEAD:main")
I("fetch", "-q", "origin", "main")
base, tip = I("rev-parse", "origin/main~1"), I("rev-parse", "origin/main")
I("tag", "-a", "-m", f"base {base}", "upgrade-merged/01-a", tip)
own = m.own_change(infra, base, "upgrade-merged/01-a")
for want_own, name, expect in ((own, "the proven change", []),
                               ("another", "another change", ["infra upgrade-merged/01-a brought a change other than "
                                                              "the one the full run proved"])):
    with open(os.path.join(m.PROVEN, "01-a.json"), "w") as f:
        f.write('{"run": "r", "ops": "%s", "floating": ["x"], "repos": {"infra": {"own": "%s"}}}' % (proven, want_own))
    check(f"merged already, {name}", proof_problems("01-a", ["01-a"], repo="infra"), expect)
I("tag", "-d", "upgrade-merged/01-a")
I("commit", "-q", "--allow-empty", "-m", "never pushed")
I("tag", "-a", "-m", f"base {tip}", "upgrade-merged/01-a", "HEAD")
check("merged already, the tag not in origin/main", proof_problems("01-a", ["01-a"], repo="infra"),
      ["infra upgrade-merged/01-a is not in origin/main"])
print("upgrade-proof-freeze: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
