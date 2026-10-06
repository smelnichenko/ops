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
cp "$src/scripts/upgrade-production.py" "$src/scripts/upgrade-defaults.py" "$src/scripts/upgrade-expected-inventory.py" \
  "$o/scripts/"
printf 'other: 1\nfoo_version: "1.0"\n' > "$o/deploy/ansible/playbooks/x.yml"
printf 'default deploy/ansible/playbooks/x.yml: foo_version: "1.0" => foo_version: "2.0"\n' \
  > "$o/tests/ansible/upgrade/steps/01-a.txt"
printf '# nothing\n' > "$o/tests/ansible/upgrade/steps/02-b.txt"
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
print("upgrade-proof-freeze: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
