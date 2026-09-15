# The hook governs the whole workflow, so its parser gets a test of its own.
import importlib.util
spec = importlib.util.spec_from_file_location('kg', '/home/sm/.claude/hooks/keep-going.py')
kg = importlib.util.module_from_spec(spec); spec.loader.exec_module(kg)

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
