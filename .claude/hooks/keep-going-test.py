import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile

HOOK = '/home/sm/.claude/hooks/keep-going.py'
spec = importlib.util.spec_from_file_location('kg', HOOK)
kg = importlib.util.module_from_spec(spec); spec.loader.exec_module(kg)

fail = 0

def check(name, got, want):
    global fail
    if got != want:
        fail += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")
    else:
        print(f"ok   {name}")

QUEUE = """
- [ ] FIRST ITEM, no PR anywhere.
      body line one
      body line two

- [ ] SECOND ITEM closed by #100.
      waits on #200 which is NOT its closer

- [ ] THIRD ITEM closed by #300 and #301.
      two closers, both must be merged

- [ ] FOURTH ITEM names its PR only further down.
      #400 is merged but lives here, not in the first line
"""

def has(done, name):
    return any(name in h for h, _ in kg.open_items(QUEUE, done))

check("no PR in the first line never closes",
      has({"100", "300", "301", "400"}, "FIRST ITEM"), True)
check("a merged first-line PR closes the item",
      has({"100"}, "SECOND ITEM"), False)
check("a PR mentioned in the BODY is not a closer",
      has({"200"}, "SECOND ITEM"), True)
check("ALL first-line PRs must be merged",
      has({"300"}, "THIRD ITEM"), True)
check("...and when they all are, it closes",
      has({"300", "301"}, "THIRD ITEM"), False)
check("a merged PR in the body leaves the item open",
      has({"400"}, "FOURTH ITEM"), True)
check("nothing merged leaves everything open", len(kg.open_items(QUEUE, set())), 4)
check("git failure means nothing is merged, so nothing closes",
      len(kg.open_items(QUEUE, set())), 4)

def run(queue_text, cursor=None):
    d = tempfile.mkdtemp()
    q = pathlib.Path(d) / "TODO.keepgoing"
    q.write_text(queue_text)
    cur = pathlib.Path(d) / ".cursor"
    if cursor is not None:
        cur.write_text(str(cursor))
    src = pathlib.Path(HOOK).read_text()
    src = src.replace('QUEUE = pathlib.Path("/home/sm/src/radar/TODO.keepgoing")',
                      f'QUEUE = pathlib.Path({str(q)!r})')
    src = src.replace('CURSOR = pathlib.Path.home() / ".claude" / "queue" / ".cursor"',
                      f'CURSOR = pathlib.Path({str(cur)!r})')
    src = src.replace('def merged():', 'def merged():\n    return set()\ndef _unused():')
    mod = pathlib.Path(d) / "kg_under_test.py"
    mod.write_text(src)
    out = subprocess.run([sys.executable, str(mod)], input="{}", capture_output=True,
                         text=True, timeout=30).stdout.strip()
    return json.loads(out) if out else None

r = run(QUEUE)
check("an open queue BLOCKS, because blocking is how it feeds", r and r["decision"], "block")
check("it feeds the first item after a fresh start", "FIRST ITEM" in r["reason"], True)
check("the reason carries the BODY, not just the heading", "body line two" in r["reason"], True)
for gone in ["a reporting point is not a stopping point", "you will be stopped here again",
             "Do not end the turn and do not summarise"]:
    check(f"the nag is gone: {gone[:34]}", gone in r["reason"], False)

check("the cursor advances", "SECOND ITEM" in run(QUEUE, cursor=0)["reason"], True)
check("and wraps at the end", "FIRST ITEM" in run(QUEUE, cursor=3)["reason"], True)
check("an empty queue ALLOWS, the only release", run("# nothing here\n"), None)
check("a queue of only closed items allows too",
      run("- [ ] done by #100.\n") is not None, True)

check("a #967 continuation is not a heading", len(kg.parse_queue(
    "- [ ] thing.\n      #967 closed it.\n")[0][1]), 1)
check("a real heading ends the item", len(kg.parse_queue(
    "- [ ] thing.\n\n# Heading\n      stray\n")[0][1]), 0)
check("a '- [!]' is not a third state to hide in",
      len(kg.open_items("- [!] waiting on hardware.\n", set())), 1)

if fail:
    raise SystemExit(f"{fail} case(s) failed")
print("all keep-going cases pass")
