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

def verdict(prior_blocks, open_items=11):
    session = f"test-{prior_blocks}-{open_items}"
    state = {}
    if kg.STATE.exists():
        try:
            state = json.loads(kg.STATE.read_text())
        except ValueError:
            state = {}
    if prior_blocks:
        state[session] = {"n": prior_blocks, "open": open_items}
        kg.STATE.parent.mkdir(parents=True, exist_ok=True)
        kg.STATE.write_text(json.dumps(state))
    out = subprocess.run([sys.executable, HOOK], input=json.dumps({"session_id": session}),
                         capture_output=True, text=True, timeout=30).stdout.strip()
    state = json.loads(kg.STATE.read_text())
    state.pop(session, None)
    kg.STATE.write_text(json.dumps(state))
    if not out:
        return "allow"
    return json.loads(out).get("decision", "allow")

queue = pathlib.Path("/home/sm/src/radar/TODO.keepgoing")
if queue.exists() and kg.parse_queue(queue.read_text()):
    for name, prior in [("the first block blocks", 0),
                        ("the one straight after a block, the old one-shot regression", 1),
                        ("and the one after that", 2),
                        ("at the old MAX_BLOCKS limit of 12", 12),
                        ("past the limit, where it used to give up silently at n=37", 37),
                        ("and absurdly far past it", 500)]:
        got = verdict(prior)
        if got != "block":
            fail += 1
            print(f"FAIL {name}: after {prior} prior blocks it said {got!r}, want 'block'")
        else:
            print(f"ok   {name}")
else:
    print("skip gate cases: the radar queue is empty or absent, so blocking cannot be observed")

empty = tempfile.NamedTemporaryFile("w", suffix=".keepgoing", delete=False)
empty.write("# a queue with no items\n")
empty.close()
if kg.parse_queue(pathlib.Path(empty.name).read_text()):
    fail += 1
    print("FAIL a queue with no '- [' lines must parse as zero open items")
else:
    print("ok   an empty queue parses as nothing open, which is the only release")

if fail:
    raise SystemExit(f"{fail} gate case(s) failed")

cases = [
    ("a PR reference on a continuation line is NOT a heading",
     "- [x] did the thing.\n      #875 closed it.\n", 0),
    ("a real heading still ends the item",
     "- [x] did the thing.\n\n# Heading\n      #875 stray text\n", 1),
    ("a '- [x]' with no evidence anywhere is still open",
     "- [x] did the thing.\n", 1),
    ("VERIFIED: closes it, whatever the note goes on to say",
     "- [x] did the thing. VERIFIED: nope, still waiting on the radio.\n", 0),
    ("a plain open item is open",
     "- [ ] do the thing.\n", 1),
    ("a sha counts as evidence",
     "- [x] did the thing. 1559c6db did it.\n", 0),
    ("VERIFIED: counts as evidence",
     "- [x] did the thing. VERIFIED: 25 rows on /api/receivers.\n", 0),
    ("there is no third state to hide in",
     "- [!] waiting on hardware.\n", 1),
]
bad = 0
for name, text, want in cases:
    got = len(kg.parse_queue(text))
    if got != want:
        bad += 1
        print(f"FAIL {name}: {got} open, want {want}")
    else:
        print(f"ok   {name}")
if bad:
    raise SystemExit(f"{bad} parser case(s) failed")
print("all keep-going cases pass")
