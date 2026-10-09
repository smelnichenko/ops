#!/bin/bash
# A step undone by its abort line (scripts/upgrade-production.py): its merge reverted on main leaves its later phases
# refused - a preview, playbooks, defaults or done on a cluster without the step's GitOps half proved nothing - and
# deploy:upgrade:abort records it aborted once the revert is checked and confirmed: its merged tag set aside, the step
# starting again from its begin (the ledger's events of the step before its abort no longer count). On throwaway repos.
set -u
src=$(cd "$(dirname "$0")/../../../.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
o=$W/ops
mkdir -p "$o/scripts" "$o/tests/ansible/upgrade/steps"
for f in upgrade-production.py upgrade-defaults.py upgrade-expected-inventory.py; do cp "$src/scripts/$f" "$o/scripts/"; done
printf 'image a 1 => image a 2\nbranch infra\n' > "$o/tests/ansible/upgrade/steps/01-a.txt"
printf 'image b 1 => image b 2\nbranch infra\n' > "$o/tests/ansible/upgrade/steps/02-b.txt"
printf '# committed steps\n' > "$o/tests/ansible/upgrade/defaults-committed.txt"
printf 'image a 1\nimage b 1\n' > "$o/tests/ansible/upgrade/prod-inventory.txt"
git -C "$o" init -q -b main && git -C "$o" add -A && git -C "$o" commit -q -m start
git init -q --bare -b main "$W/origin.git"
git clone -q "$W/origin.git" "$W/infra" 2> /dev/null
g() { git -C "$W/infra" "$@"; }
printf 'a: 1\n' > "$W/infra/a.yaml"; printf 'other: 1\n' > "$W/infra/o.yaml"
g add -A; g commit -q -m base; g push -q origin main
base=$(g rev-parse main)
g checkout -q -b upgrade/01-a; printf 'a: 2\n' > "$W/infra/a.yaml"; g commit -q -am 01-a; g checkout -q main
# merged as scripts/upgrade-merge-step.sh merges: fast-forward, pushed, tagged with the main it went onto
g merge -q --ff-only upgrade/01-a; g push -q origin main; g tag -m "base $base" upgrade-merged/01-a upgrade/01-a
g push -q origin refs/tags/upgrade-merged/01-a
PYTHONDONTWRITEBYTECODE=1 python3 - "$o" "$W/infra" <<'PY'
import contextlib, datetime, importlib.machinery, importlib.util, io, os, subprocess, sys
o, infra = sys.argv[1:]
loader = importlib.machinery.SourceFileLoader("up", os.path.join(o, "scripts", "upgrade-production.py"))
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("up", loader))
loader.exec_module(m)
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


g = lambda *a: subprocess.run(["git", "-C", infra, *a], capture_output=True, text=True, check=True).stdout.strip()
live = getattr(m, "merged_live_problems", None)
live_ = lambda: live("01-a", ["infra"]) if live else ["no merged_live_problems"]
check("merged, as it went live: no problem", live_(), [])
# another file changed on main since (CD): still live
open(os.path.join(infra, "o.yaml"), "w").write("other: 2\n")
g("commit", "-qam", "cd"); g("push", "-q", "origin", "main")
check("another file changed on main since: still live", live_(), [])
# the merge reverted (its abort line): not live, the file named
g("revert", "--no-edit", "upgrade-merged/01-a"); g("push", "-q", "origin", "main")
got = live_()
check("its merge reverted on main: a problem naming the file and the abort", (len(got), "a.yaml" in str(got),
                                                                               "abort" in str(got)), (1, True, True))

# abort: refused while the merge is live, else recorded aborted, the merged tag set aside, the step's earlier events
# dropped (it starts again from its begin)
at = lambda i: datetime.datetime(2026, 10, 9, 10, i, tzinfo=datetime.timezone.utc)
events = [(at(0), "01-a", "begun", []), (at(1), "01-a", "merged", ["infra", "x"]),
          (at(2), "01-a", "settled", ["infra", "x"])]
recorded, asked = [], []
m.ledger_for = lambda st, ph, arg=None: (m.step_names(), list(events), m.step_info(st))
m.record = lambda st, ev, *a, **k: recorded.append((st, ev, *a))
m.confirm = lambda q: asked.append(q) or True
abort = getattr(m, "abort", None)


def run_abort():
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            abort("01-a")
        return "ok"
    except SystemExit as e:
        return f"refused {e}"


g("reset", "-q", "--hard", "HEAD~1"); g("push", "-q", "-f", "origin", "main")  # the revert undone: live again
r = run_abort() if abort else "no abort"
check("abort while its merge is live: refused, nothing recorded, the tag kept",
      ("live" in r, recorded, g("tag", "-l", "upgrade-merged/01-a")), (True, [], "upgrade-merged/01-a"))
g("revert", "--no-edit", "upgrade-merged/01-a"); g("push", "-q", "origin", "main")
# its defaults committed (recorded, in the committed-steps record): refused until that commit is reverted too
committed = os.path.join(o, "tests/ansible/upgrade/defaults-committed.txt")
kept_record = open(committed).read()
open(committed, "a").write("01-a\n")
events.append((at(3), "01-a", "defaults", ["c0ffee"]))
r = run_abort() if abort else "no abort"
check("abort with its defaults committed: refused, nothing recorded, the tag kept",
      ("defaults" in r, recorded, g("tag", "-l", "upgrade-merged/01-a")), (True, [], "upgrade-merged/01-a"))
open(committed, "w").write(kept_record)  # that commit reverted
asked.clear()
r = run_abort() if abort else "no abort"
check("abort after the revert: asked, recorded aborted", (r, len(asked), recorded), ("ok", 1, [("01-a", "aborted")]))
check("  its merged tag set aside", (g("tag", "-l", "upgrade-merged/01-a"),
                                     g("tag", "-l", "upgrade-aborted/01-a-*").startswith("upgrade-aborted/01-a-")),
      ("", True))
origin_tags = subprocess.run(["git", "-C", os.path.join(os.path.dirname(infra), "origin.git"), "tag", "-l"],
                             capture_output=True, text=True).stdout.split()
check("  on origin too: the merged tag gone, the aborted one there",
      ("upgrade-merged/01-a" in origin_tags, any(t.startswith("upgrade-aborted/01-a-") for t in origin_tags)), (False, True))
m.fetch_main(infra)
check("  a fetch of main brings no merged tag back (it would refuse the re-merge)", g("tag", "-l", "upgrade-merged/01-a"), "")
current = getattr(m, "current", None)
after = events + [(at(5), "01-a", "aborted", []), (at(6), "01-a", "end", ["abort", "passed", "t"])]
names = m.step_names()
info = m.step_info("01-a")
check("after its abort the step begins again (its earlier events no longer count)",
      m.problems(names, "01-a", "begin", current(after), info) if current else "no current", [])
check("  and merges again", m.problems(names, "01-a", "merge", current(after + [(at(7), "01-a", "begun", [])]), info,
                                       "infra") if current else "no current", [])
check("  the ledger's other steps untouched", current(after + [(at(8), "02-b", "begun", [])])[-1][1:3]
      if current else None, ("02-b", "begun"))
check("abort of a step not begun: refused", m.problems(names, "02-b", "abort", [], m.step_info("02-b")) != [], True)
check("abort of a done step: refused",
      m.problems(names, "01-a", "abort", [(at(0), "01-a", "begun", []), (at(1), "01-a", "done", [])], info) != [], True)
print("upgrade-abort: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
