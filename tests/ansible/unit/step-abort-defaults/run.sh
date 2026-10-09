#!/bin/bash
# A step whose default lines production commits after it (scripts/upgrade-defaults.py) says in its abort text that
# that commit is reverted first: deploy:upgrade:abort refuses while the step's defaults stand committed
# (upgrade-production.py's abort), and a playbook re-run on the committed defaults puts the step back. Every step
# file's comment lines from its "# abort:" up to the next line that is not a comment.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import glob, os, re, sys
fails, seen = 0, []
for f in sorted(glob.glob("tests/ansible/upgrade/steps/*.txt")):
    lines = open(f).read().splitlines()
    if not any(l.startswith("default ") for l in lines):
        continue
    i = next((n for n, l in enumerate(lines) if l.startswith("# abort:")), None)
    text = ""
    if i is not None:
        for l in lines[i:]:
            if not l.startswith("#"):
                break
            text += l[1:] + " "
    seen.append(os.path.basename(f)[:-4])
    if not re.search(r"defaults commit", text):
        fails += 1
        print(f"FAIL {os.path.basename(f)}: its abort text does not name its defaults commit")
print(f"steps with default lines: {len(seen)}")
fails += len(seen) < 10
print("step-abort-defaults: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
