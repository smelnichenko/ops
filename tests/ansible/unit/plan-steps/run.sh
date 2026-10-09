#!/bin/bash
# docs/plans/100-cluster-upgrade.md's step table follows the step files (tests/ansible/upgrade/steps): every step once,
# none extra, in order - a step added, renamed or dropped in the files and not in the plan fails here.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
exec python3 - <<'PY_PLANSTEPS'
import os, re, sys
doc = open("docs/plans/100-cluster-upgrade.md").read()
sec = doc[doc.index("## Upgrade steps"):]
sec = sec[:sec.index("\n## ", 1)]
rows = [f"{m.group(1)}-{m.group(2)}" for m in re.finditer(r"^\| (\d\d) \| ([a-z0-9][a-z0-9.-]*)", sec, re.M)]
files = sorted(f[:-4] for f in os.listdir("tests/ansible/upgrade/steps") if f.endswith(".txt"))
ok = rows == files
print(("PASS" if ok else "FAIL") + f" the plan's step table: {len(rows)} rows, {len(files)} step files"
      + ("" if ok else f" - missing {sorted(set(files) - set(rows))}, extra {sorted(set(rows) - set(files))}"))
print("plan-steps: " + ("ALL-PASS" if ok else "1 FAILED"))
sys.exit(0 if ok else 1)
PY_PLANSTEPS
