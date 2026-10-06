#!/bin/bash
# scripts/check-mode-lint.py: a task reading a shell/command/uri result check mode skipped is named - in the play, in a
# block, in an imported file; one with check_mode: false is not skipped; a read with | default, a reader check mode
# skips itself, a reader past an end_host only the preview reaches, a task --tags leaves out - none named. Step 37's
# strimzi conversion as it was before its fix (59e2640^) is named, as its preview crashed; every step's playbook
# lines today are clean.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
python3 - <<'PY'
import importlib.machinery, importlib.util, os, subprocess, sys, tempfile
l = importlib.machinery.SourceFileLoader("c", "scripts/check-mode-lint.py")
c = importlib.util.module_from_spec(importlib.util.spec_from_loader("c", l))
l.exec_module(c)
work = tempfile.mkdtemp()
fails = 0
def check(name, got, want):
    global fails
    ok = got == want
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f": got {got}, want {want}"))
def play(tasks, tags=None, extra=None):
    """The reads named in a one-play playbook of `tasks` (YAML text, indented under tasks:)."""
    for name, text in (extra or {}).items():
        open(os.path.join(work, name), "w").write(text)
    path = os.path.join(work, "p.yml")
    open(path, "w").write("- hosts: x\n  tasks:\n" + tasks)
    return [x.split("reads ")[1].split(" -")[0] for x in c.lint(path, tags)]
PROBE = """    - name: probe
      ansible.builtin.command: cat /x
      register: _p
"""
READ = """    - name: read
      ansible.builtin.debug:
        msg: "{{ _p.stdout }}"
"""
check("a command's result read: named", play(PROBE + READ), ["_p.stdout"])
check("check_mode: false: it runs, not named", play(PROBE.replace("register:", "check_mode: false\n      register:")
                                                    + READ), [])
check("read with | default: not named", play(PROBE + READ.replace("_p.stdout }}", "_p.stdout | default('') }}")), [])
check("only .skipped read: not named", play(PROBE + READ.replace("_p.stdout", "_p.skipped")), [])
check("the reader under not ansible_check_mode: not named",
      play(PROBE + READ.replace("    - name: read\n", "    - name: read\n      when: not ansible_check_mode\n")), [])
check("a uri result: named", play(PROBE.replace("ansible.builtin.command: cat /x", "ansible.builtin.uri:\n        url: http://x")
                                  + READ), ["_p.stdout"])
check("in a block: named", play("    - block:\n" + "\n".join("    " + x for x in (PROBE + READ).splitlines()) + "\n"),
      ["_p.stdout"])
END = """    - name: the preview ends here
      when: ansible_check_mode
      block:
        - name: End
          ansible.builtin.meta: end_host
"""
check("a reader past a check-mode end_host: not named", play(PROBE + END + READ), [])
check("past an end_host any run may reach: named", play(PROBE + END.replace("when: ansible_check_mode",
                                                                             "when: _x | bool") + READ), ["_p.stdout"])
check("a probe the tags leave out: its reader too, not named",
      play(PROBE.replace("register:", "tags: [a]\n      register:") + READ.replace("    - name: read\n",
           "    - name: read\n      tags: [a]\n"), {"b"}), [])
check("a probe the tags select, its reader too: named",
      play(PROBE.replace("register:", "tags: [b]\n      register:") + READ.replace("    - name: read\n",
           "    - name: read\n      tags: [always]\n"), {"b"}), ["_p.stdout"])
check("an imported file's probe: named", play("    - ansible.builtin.import_tasks: probe.yml\n" + READ,
                                             extra={"probe.yml": "- name: probe\n  ansible.builtin.shell: cat /x\n"
                                                    "  register: _p\n"}), ["_p.stdout"])
# kept here as it was (git show 59e2640^:...): a shallow clone has no history that far back
old = open("tests/ansible/unit/check-mode-lint/strimzi-v1-conversion-before-59e2640.yml").read()
check("step 37's conversion before its fix: named",
      [x.split("reads ")[1].split(" -")[0] for x in c.lint("deploy/ansible/playbooks/strimzi-v1-conversion.yml",
                                                           None, old)], ["_after.stdout_lines"])
r = subprocess.run(["scripts/check-mode-lint.py"], capture_output=True, text=True)
check("every step's playbook lines today: clean", (r.returncode, r.stdout.strip().endswith("check mode skips")),
      (0, True))
print("check-mode-lint: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
