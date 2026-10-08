#!/bin/bash
# .woodpecker/ci.yaml: the tests' PromQL evaluated by promtool (the unit harnesses' stubs answer whatever is asked -
# only Prometheus evaluates the playbooks' expressions), on every test file there, the step the pipeline waits for;
# every step's image not this org's own pinned by its digest (a tag moves: the image that ran is the one asked for) -
# the clone's aside (Woodpecker gives a clone image credentials only when it is a trusted clone plugin).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
python3 - <<'PYCI'
import glob, re, sys
import yaml
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
ci = yaml.safe_load(open(".woodpecker/ci.yaml"))
steps = ci.get("steps") or []
steps = [dict(s, name=n) for n, s in steps.items()] if isinstance(steps, dict) else steps
prom = [s for s in steps if any("promtool test rules" in c for c in s.get("commands") or [])]
check("one step runs promtool's tests", len(prom), 1)
if prom:
    cmd = next(c for c in prom[0]["commands"] if "promtool test rules" in c)
    files = sorted(glob.glob("tests/promql/*.test.yml"))
    check("on every test file there (its glob)", (bool(files), sorted(glob.glob(cmd.split("promtool test rules", 1)[1].split()[0]))
                                                  == files), (True, True))
    check("the pipeline's last step waits for it", any(prom[0]["name"] in (s.get("depends_on") or []) for s in steps), True)
foreign = [(s.get("name"), s.get("image")) for s in steps if s.get("image") and not s["image"].startswith("git.pmon.dev/")]
check("every image not this org's own pinned by its digest",
      [x for x in foreign if not re.search(r"@sha256:[0-9a-f]{64}$", x[1])], [])
print("ci-steps: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCI
