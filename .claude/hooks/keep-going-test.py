# The hook governs the whole workflow, so its parser gets a test of its own.
import importlib.util
spec = importlib.util.spec_from_file_location('kg', '/home/sm/.claude/hooks/keep-going.py')
kg = importlib.util.module_from_spec(spec); spec.loader.exec_module(kg)

# --- the GATE. It had no test, which is how a one-line escape hatch survived in it for weeks.
gate_cases = [
    ("the first block blocks", 1, True),
    ("a stop immediately AFTER a block still blocks — this is the regression", 2, True),
    ("and the one after that", 3, True),
    ("still blocking at the limit", kg.MAX_BLOCKS, True),
    ("gives up one past the limit, so a stuck session is never wedged", kg.MAX_BLOCKS + 1, False),
]
gate_fail = 0
for name, n, want in gate_cases:
    got = kg.should_block(n)
    if got != want:
        gate_fail += 1
        print(f"FAIL {name}: should_block({n}) = {got}, want {want}")
    else:
        print(f"ok   {name}")
if gate_fail:
    raise SystemExit(f"{gate_fail} gate case(s) failed")

cases = [
    ("a PR reference on a continuation line is NOT a heading",
     "- [x] did the thing.\n      #875 closed it.\n", 0),
    ("a real heading still ends the item",
     "- [x] did the thing.\n\n# Heading\n      #875 stray text\n", 1),
    ("a '- [x]' with no evidence anywhere is still open",
     "- [x] did the thing.\n      and some more words.\n", 1),
    ("an excuse in the body reopens it even with a PR",
     "- [x] did the thing in #875.\n      still open really.\n", 1),
    ("a sha counts as evidence",
     "- [x] did the thing.\n      86ca90c1 closed it.\n", 0),
    ("VERIFIED: counts as evidence",
     "- [x] did the thing.\n      VERIFIED: ran it twice.\n", 0),
    ("an open item is open",
     "- [ ] not done yet.\n", 1),
]
bad = 0
for name, text, want in cases:
    opened, _ = kg.parse_queue(text)
    got = len(opened)
    ok = got == want
    bad += not ok
    print(f"  {'ok ' if ok else 'FAIL'} {name}: expected {want} open, got {got}")
print("FAILURES:", bad)
raise SystemExit(1 if bad else 0)
