#!/bin/bash
# The harnesses' own instrument, tests/ansible/unit/templar.py: a when:/failed_when:/until: list holds when every entry
# does (as Ansible reads a task's when: list and assert's that:) - not any (with any, ten harnesses stayed green); a
# bare bool is itself; a string is a conditional, Ansible's filters and tests at hand; render keeps native types.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYTPL'
import sys
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render  # noqa: E402
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
check("a list: every entry must hold", [condition(["true", "false"]), condition(["false", "true"]),
                                        condition(["true", "1 == 1"]), condition([])], [False, False, True, True])
check("a list of bools", [condition([True]), condition([True, False])], [True, False])
check("a bare bool", [condition(True), condition(False)], [True, False])
check("a string: Ansible's tests and filters, variables", [condition("x is match('^a ')", x="a b"),
                                                            condition("x | bool", x="no"), condition("x.rc != 0", x={"rc": 1})],
      [True, False, True])
check("render: Ansible's filters, native types", [render("{{ x | bool }}", x="yes"), render("{{ [1, 2] | max }}")], [True, 2])
print("templar-self: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYTPL
