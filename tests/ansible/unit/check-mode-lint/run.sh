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
# a shell or command skipped in check mode still registers an empty stdout (ansible-core 2.20): | default never applies
# to it, and the empty value flows on - named; a uri's result has no json then, and | default applies - not named
check("a command's read with | default: named (its stdout is there, empty)",
      play(PROBE + READ.replace("_p.stdout }}", "_p.stdout | default('[]') }}")), ["_p.stdout"])
check("a uri's read with | default: not named", play(PROBE.replace("ansible.builtin.command: cat /x",
      "ansible.builtin.uri:\n        url: http://x") + READ.replace("_p.stdout }}", "_p.json | default({}) }}")), [])
check("only .skipped read: not named", play(PROBE + READ.replace("_p.stdout", "_p.skipped")), [])
check("the reader under not ansible_check_mode: not named",
      play(PROBE + READ.replace("    - name: read\n", "    - name: read\n      when: not ansible_check_mode\n")), [])
check("a uri result: named", play(PROBE.replace("ansible.builtin.command: cat /x", "ansible.builtin.uri:\n        url: http://x")
                                  + READ), ["_p.stdout"])
check("in a block: named", play("    - block:\n" + "\n".join("    " + x for x in (PROBE + READ).splitlines()) + "\n"),
      ["_p.stdout"])
# a block's own when, as Ansible evaluates a list - in its order, stopping at the first false: `not ansible_check_mode`
# first, the rest never read in a preview; after a read, that read is made
BLOCK = """    - name: a block
      when:
        - {first}
        - {second}
      block:
        - name: inside
          ansible.builtin.debug:
            msg: hi
"""
check("a block's own when: not ansible_check_mode first, then a read - not named",
      play(PROBE + BLOCK.format(first="not ansible_check_mode", second="_p.stdout == 'x'")), [])
check("a block's own when: a read, then not ansible_check_mode - named",
      play(PROBE + BLOCK.format(first="_p.stdout == 'x'", second="not ansible_check_mode")), ["_p.stdout"])
# a loop over a skipped register's results: a looped one's are skipped items (each read named as item's); one not looped
# has no results at all - that read is the one named, no item reads besides
LOOPED = PROBE.replace("ansible.builtin.command: cat /x", "ansible.builtin.command: cat {{ item }}\n      loop: [a, b]")
OVER = """    - name: over
      ansible.builtin.debug:
        msg: "{{ item.stdout }}"
      loop: "{{ _p.results }}"
"""
check("a loop over a skipped looped register's results: its items' reads named", play(LOOPED + OVER), ["item.stdout"])
check("over a skipped register not looped: its .results named, no item reads besides", play(PROBE + OVER),
      ["_p.results"])
# a looped register's items read otherwise than as a loop's item: by its loop_var, a Jinja for, map/selectattr, an index
VAR = OVER.replace("item.stdout", "r.stdout").replace('      loop: "{{ _p.results }}"\n',
                                                      '      loop: "{{ _p.results }}"\n      loop_control:\n        loop_var: r\n')
check("... over its results by another loop_var: its items' reads named", play(LOOPED + VAR), ["r.stdout"])
FOR = READ.replace("{{ _p.stdout }}", "{% for r in _p.results %}{{ r.stdout }}{% endfor %}")
check("... a Jinja for over its results: named", play(LOOPED + FOR), ["_p.results[].stdout"])
check("... map(attribute=) over its results: named",
      play(LOOPED + READ.replace("_p.stdout", "_p.results | map(attribute='stdout') | list")), ["_p.results[].stdout"])
check("... selectattr over its results: named",
      play(LOOPED + READ.replace("_p.stdout", "_p.results | selectattr('rc', 'eq', 0) | list")), ["_p.results[].rc"])
check("... one of its results by index: named", play(LOOPED + READ.replace("_p.stdout", "_p.results[0].json.ok")),
      ["_p.results[].json"])
check("... its results' count, each item's own item, a Jinja for reading item alone: not named",
      play(LOOPED + READ.replace("_p.stdout", "_p.results | length"))
      + play(LOOPED + READ.replace("_p.stdout", "_p.results | map(attribute='item') | list"))
      + play(LOOPED + READ.replace("{{ _p.stdout }}", "{% for r in _p.results %}{{ r.item }}{% endfor %}")), [])
# reads it once missed: its first or last item, results by subscript, a json_query, a with_together's item
check("... its first result's field ((results | first).f): named",
      play(LOOPED + READ.replace("_p.stdout", "(_p.results | first).stdout")), ["_p.results[].stdout"])
check("... its results by subscript (r['results'][0].f, r[\"results\"][0]['f']): named",
      play(LOOPED + READ.replace("_p.stdout", "_p['results'][0].stdout"))
      + play(LOOPED + "    - name: read\n      ansible.builtin.debug:\n        msg: '{{ _p[\"results\"][0][\"rc\"] }}'\n"),
      ["_p.results[].stdout", "_p.results[].rc"])
check("... a json_query over its results: named; over a register not looped: named",
      play(LOOPED + READ.replace("_p.stdout", "_p.results | json_query('[].stdout')"))
      + play(PROBE + READ.replace("_p.stdout", "_p | community.general.json_query('stdout_lines')")),
      ["_p.results[].stdout", "_p.stdout_lines"])
check("... a json_query of each item's own item: not named",
      play(LOOPED + READ.replace("_p.stdout", "_p.results | json_query('[].item')")), [])
check("... a json_query of the register itself over its results (results[*].f): named; results[*].item: not",
      play(LOOPED + READ.replace("_p.stdout", "_p | json_query('results[*].stdout')"))
      + play(LOOPED + READ.replace("_p.stdout", "_p | json_query('results[*].item')")), ["_p.results[].stdout"])
ZIP = """    - name: zipped
      ansible.builtin.debug:
        msg: "{{ item[0].stdout }} {{ item[1] }}"
      loop: "{{ _p.results | zip(['a', 'b']) | list }}"
"""
check("... a loop zipping its results with another list: the item's part from them read (item[0].stdout, item.0.rc) "
      "named, the other's not; zipped second: item[1]",
      play(LOOPED + ZIP) + play(LOOPED + ZIP.replace("item[0].stdout", "item.0.rc"))
      + play(LOOPED + ZIP.replace("_p.results | zip(['a', 'b'])", "['a', 'b'] | zip(_p.results)")
             .replace("{{ item[0].stdout }} {{ item[1] }}", "{{ item[0] }} {{ item[1].stdout }}")),
      ["item[0].stdout", "item.0.rc", "item[1].stdout"])
# a loop is rendered before the task's when is judged (ansible-core's TaskExecutor: its items first) - one whose when,
# or a block's, says it never runs in a preview still renders its loop there: a from_json of a skipped result's empty
# stdout failed the preview. Named - an include's, and a task's in such a block
INC_LOOP = """    - name: an include over a result
      when: not ansible_check_mode
      ansible.builtin.include_tasks: x.yml
      loop: "{{ _p.stdout | from_json }}"
"""
BLOCK_LOOP = """    - name: a block never in a preview
      when: not ansible_check_mode
      block:
        - name: over a result
          ansible.builtin.debug:
            msg: "{{ item }}"
          loop: "{{ _p.stdout | from_json }}"
"""
check("a loop rendered before its when: an include's, a task's in a never-in-a-preview block - named; their when's "
      "reads (never evaluated in a preview) not",
      (play(PROBE + INC_LOOP, extra={"x.yml": "- ansible.builtin.debug:\n    msg: hi\n"}), play(PROBE + BLOCK_LOOP),
       play(PROBE + BLOCK_LOOP.replace("      when: not ansible_check_mode\n",
                                        "      when: not ansible_check_mode and _p.stdout == 'x'\n")
            .replace('loop: "{{ _p.stdout | from_json }}"', "loop: [1]"))),
      (["_p.stdout"], ["_p.stdout"], []))
TOGETHER = """    - name: together
      ansible.builtin.debug:
        msg: "{{ item.0.stdout }} {{ item.1 }}"
      with_together:
        - "{{ _p.results }}"
        - [a, b]
"""
check("... a with_together over its results: the item's skipped part read (item.0.stdout) named, the other not",
      play(LOOPED + TOGETHER), ["item.0.stdout"])
check("... the same reading item.0.item alone: not named", play(LOOPED + TOGETHER.replace("item.0.stdout", "item.0.item")),
      [])
# a register's name inside another one's (x._p, hostvars-free): no read of it
check("another object's field named like the register (x._p.stdout): not named",
      play(PROBE + READ.replace("_p.stdout", "x._p.stdout")), [])
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
# a task keyword before the module key (become_user, async, timeout, ...) is no module: the probe still read as one
for kw in ("become_user: postgres", "async: 60", "timeout: 30", "remote_user: root", "module_defaults: {}",
           "delegate_facts: true", "any_errors_fatal: true", "ignore_unreachable: true", "become_method: sudo"):
    check(f"{kw.split(':')[0]} before the module: named", play(PROBE.replace("    - name: probe\n",
                                                                              f"    - name: probe\n      {kw}\n")
                                                               + READ), ["_p.stdout"])
# a probe in pre_tasks read in tasks, and a read in a handler: named; a task tagged never (no --tags): not run
def play_full(text):
    path = os.path.join(work, "p2.yml")
    open(path, "w").write(text)
    return [x.split("reads ")[1].split(" -")[0] for x in c.lint(path, None)]
check("a probe in pre_tasks, read in tasks: named", play_full("- hosts: x\n  pre_tasks:\n" + PROBE + "  tasks:\n"
                                                              + READ), ["_p.stdout"])
check("a read in a handler: named", play_full("- hosts: x\n  tasks:\n" + PROBE + "  handlers:\n" + READ),
      ["_p.stdout"])
check("a reader tagged never, no --tags: not named",
      play(PROBE + READ.replace("    - name: read\n", "    - name: read\n      tags: [never]\n")), [])
check("an imported file's probe: named", play("    - ansible.builtin.import_tasks: probe.yml\n" + READ,
                                             extra={"probe.yml": "- name: probe\n  ansible.builtin.shell: cat /x\n"
                                                    "  register: _p\n"}), ["_p.stdout"])
# a read by subscript is a read: _p['stdout'] as _p.stdout
check("a read by subscript: named", play(PROBE + READ.replace("_p.stdout", "_p['stdout']")), ["_p.stdout"])
# raw and script in check mode register no stdout at all (raw: skipped; script: skipped, or changed with creates) -
# | default applies to them, as to a uri's; read bare, named
for mod in ("ansible.builtin.raw: cat /x", "ansible.builtin.script: x.sh"):
    probe = PROBE.replace("ansible.builtin.command: cat /x", mod)
    check(f"{mod.split(':')[0]}'s read with | default: not named",
          play(probe + READ.replace("_p.stdout }}", "_p.stdout | default('') }}")), [])
    check(f"{mod.split(':')[0]}'s read bare: named", play(probe + READ), ["_p.stdout"])
# a loop keyword (with_items) before the module is no module either
check("with_items before the module: named", play(PROBE.replace("    - name: probe\n",
                                                               "    - name: probe\n      with_items: [1]\n") + READ),
      ["_p.stdout"])
# a dynamic include's tags are its own, not its tasks': with --tags b and the include tagged b, its untagged tasks do
# not run (they inherited the tag here, and a read that never runs was named)
INC = {"inc.yml": "- name: probe\n  ansible.builtin.command: cat /x\n  register: _p\n"
                  "- name: read\n  ansible.builtin.debug:\n    msg: '{{ _p.stdout }}'\n"}
check("an include_tasks tagged b, its untagged tasks under --tags b: not run, not named",
      play("    - ansible.builtin.include_tasks: inc.yml\n      tags: [b]\n", {"b"}, extra=INC), [])
# a play's tags reach an include's tasks (their block's parent is the play); the include's own do not
open(os.path.join(work, "inc.yml"), "w").write(INC["inc.yml"])
open(os.path.join(work, "p4.yml"), "w").write("- hosts: x\n  tags: [b]\n  tasks:\n"
                                              "    - ansible.builtin.include_tasks: inc.yml\n")
check("a play tagged b, an untagged include_tasks, --tags b: its tasks run, named",
      [x.split("reads ")[1].split(" -")[0] for x in c.lint(os.path.join(work, "p4.yml"), {"b"})], ["_p.stdout"])
open(os.path.join(work, "p5.yml"), "w").write("- hosts: x\n  tasks:\n    - tags: [b]\n      block:\n"
                                              "        - ansible.builtin.include_tasks: inc.yml\n")
check("a block tagged b around an untagged include_tasks, --tags b: its tasks run, named (measured, ansible-core 2.20)",
      [x.split("reads ")[1].split(" -")[0] for x in c.lint(os.path.join(work, "p5.yml"), {"b"})], ["_p.stdout"])
check("an import_tasks tagged b: its tasks inherit it, named",
      play("    - ansible.builtin.import_tasks: inc.yml\n      tags: [b]\n", {"b"}, extra=INC), ["_p.stdout"])
check("an include_tasks with apply tags b: its tasks run, named",
      play("    - ansible.builtin.include_tasks:\n        file: inc.yml\n        apply: {tags: [b]}\n      tags: [b]\n",
           {"b"}, extra=INC), ["_p.stdout"])
# a file the lint cannot follow is named, never skipped unseen
open(os.path.join(work, "p3.yml"), "w").write("- hosts: x\n  tasks:\n    - ansible.builtin.import_tasks: missing.yml\n")
got = c.lint(os.path.join(work, "p3.yml"), None)
check("an import of a file that is not there: named", (len(got), "not followed" in str(got)), (1, True))
# handlers run after each section (pre_tasks, tasks, post_tasks): one reading a probe of tasks that post_tasks
# registered again read the skipped one
FLUSHED = ("- hosts: x\n  tasks:\n" + PROBE.replace("    - name: probe\n", "    - name: probe\n      notify: h\n")
           + "  post_tasks:\n" + PROBE.replace("register:", "check_mode: false\n      register:")
           + "  handlers:\n" + READ.replace("    - name: read\n", "    - name: h\n"))
check("a handler flushed after tasks reads the probe tasks left skipped: named", play_full(FLUSHED), ["_p.stdout"])
# a block's and an include's own when/loop read too (a block whose when read a skipped probe was never seen)
check("a block's own when reads a skipped probe: named",
      play(PROBE + "    - name: blk\n      when: _p.rc != 0\n      block:\n        - name: x\n"
                   "          ansible.builtin.debug:\n            msg: hi\n"), ["_p.rc"])
# an include whose own when says it never runs in a preview: its vars and loop are never rendered there - not named;
# the same include without that when: named
NOPREV = """    - name: rec
      ansible.builtin.include_tasks: inc3.yml
      vars:
        h: "{{ _p.stdout }}"
      when: not ansible_check_mode
"""
check("an include under not ansible_check_mode reading a skipped probe in its vars: not named; without it: named",
      play(PROBE + NOPREV, extra={"inc3.yml": "- name: x\n  ansible.builtin.debug:\n    msg: hi\n"})
      + play(PROBE + NOPREV.replace("      when: not ansible_check_mode\n", ""),
             extra={"inc3.yml": "- name: x\n  ansible.builtin.debug:\n    msg: hi\n"}), ["_p.stdout"])
check("an include's own loop reads a skipped probe: named",
      play(PROBE + "    - name: inc\n      ansible.builtin.include_tasks: inc2.yml\n      loop: '{{ _p.stdout_lines }}'\n",
           extra={"inc2.yml": "- name: x\n  ansible.builtin.debug:\n    msg: hi\n"}), ["_p.stdout_lines"])
# a register lives on in the host's later plays, and other hosts read it through hostvars
check("a probe in one play, read in the next: named",
      play_full("- hosts: x\n  tasks:\n" + PROBE + "- hosts: x\n  tasks:\n" + READ), ["_p.stdout"])
check("read through hostvars in another play: named",
      play_full("- hosts: a\n  tasks:\n" + PROBE + "- hosts: b\n  tasks:\n"
                + READ.replace("_p.stdout", "hostvars['a']['_p'].stdout")), ["_p.stdout"])
check("a double-quoted subscript: named", play(PROBE + "    - name: read\n      ansible.builtin.debug:\n"
                                                       "        msg: '{{ _p[\"stdout\"] }}'\n"), ["_p.stdout"])
# a loop over a skipped looped register's results: its items are there, skipped - none holds a stdout
LOOPED = PROBE.replace("    - name: probe\n", "    - name: probe\n      loop: [1, 2]\n      when: not ansible_check_mode\n")
check("a loop over a skipped register's results reading item.stdout: named",
      play_full("- hosts: a\n  tasks:\n" + LOOPED + "- hosts: b\n  tasks:\n    - name: use\n"
                "      ansible.builtin.copy:\n        content: '{{ item.stdout }}'\n        dest: /x\n"
                "      loop: \"{{ hostvars['a']['_p'].results | default([]) }}\"\n"), ["item.stdout"])
check("its results read through hostvars by index or a filter: named",
      play_full("- hosts: a\n  tasks:\n" + LOOPED + "- hosts: b\n  tasks:\n"
                + READ.replace("_p.stdout", "hostvars['a']['_p'].results[0].stdout"))
      + play_full("- hosts: a\n  tasks:\n" + LOOPED + "- hosts: b\n  tasks:\n"
                  + READ.replace("_p.stdout", "hostvars['a']['_p'].results | map(attribute='rc') | list")),
      ["_p.results[].stdout", "_p.results[].rc"])
check("the same loop reading item.item alone: not named",
      play_full("- hosts: a\n  tasks:\n" + LOOPED + "- hosts: b\n  tasks:\n    - name: use\n"
                "      ansible.builtin.debug:\n        msg: '{{ item.item }}'\n"
                "      loop: \"{{ hostvars['a']['_p'].results | default([]) }}\"\n"), [])
# kept here as it was (git show 59e2640^:...): a shallow clone has no history that far back
old = open("tests/ansible/unit/check-mode-lint/strimzi-v1-conversion-before-59e2640.yml").read()
check("step 37's conversion before its fix: named",
      [x.split("reads ")[1].split(" -")[0] for x in c.lint("deploy/ansible/playbooks/strimzi-v1-conversion.yml",
                                                           None, old)], ["_after.stdout_lines"])
# the playbooks a deploy task hands the caller's arguments ({{.CLI_ARGS}}: a --check preview among them) are linted
# too, read from the Taskfile
linted = []
real_lint, c.lint = c.lint, lambda path, tags: linted.append(os.path.basename(path)) or []
argv, sys.argv = sys.argv, ["check-mode-lint.py"]
try:
    c.main()
except SystemExit:
    pass
c.lint, sys.argv = real_lint, argv
check("the playbooks a deploy task previews: linted by the default run (setup-keepalived's, setup-nexus' and "
      "setup-vault-pi's among them)", {"setup-keepalived.yml", "setup-nexus.yml", "setup-vault-pi.yml"} <= set(linted),
      True)
r = subprocess.run(["scripts/check-mode-lint.py"], capture_output=True, text=True)
check("every step's playbook lines today: clean", (r.returncode, r.stdout.strip().endswith("check mode skips")),
      (0, True))
print("check-mode-lint: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
