#!/bin/bash
# scripts/upgrade-defaults.py: a default line replaces every line equal to its old one, keeping the indentation, and
# refuses a file without it; the steps' lines apply in step order to the working tree's playbooks (--lint).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
python3 - <<'PY'
import importlib.machinery
import importlib.util
import sys

loader = importlib.machinery.SourceFileLoader("upgrade_defaults", "scripts/upgrade-defaults.py")
d = importlib.util.module_from_spec(importlib.util.spec_from_loader("upgrade_defaults", loader))
loader.exec_module(d)
fails = 0


def check(name, got, want):
    global fails
    ok = got == want
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f"\n  got  {got!r}\n  want {want!r}"))


src = 'vars:\n    cilium_version: "1.19.1"\n    x: 1\n'
check("the line replaced, its indentation kept",
      d.apply(src, 'cilium_version: "1.19.1"', 'cilium_version: "1.19.8"', "t"),
      'vars:\n    cilium_version: "1.19.8"\n    x: 1\n')
two = '  a:\n    chart_version: "1.20.2"\n  b:\n      chart_version: "1.20.2"\n'
check("every equal line replaced",
      d.apply(two, 'chart_version: "1.20.2"', 'chart_version: "v1.20.3"', "t"),
      '  a:\n    chart_version: "v1.20.3"\n  b:\n      chart_version: "v1.20.3"\n')
try:
    d.apply(src, 'cilium_version: "1.20.0"', 'cilium_version: "1.20.2"', "t")
    check("a missing old line refuses", "applied", "refused")
except ValueError as e:
    check("a missing old line refuses, naming it", "no line 'cilium_version: \"1.20.0\"'" in str(e), True)
check("a default line parses into its file, old line and new",
      d.LINE.fullmatch('default f.yml: a: "1" => a: "2"').groups(), ("f.yml", 'a: "1"', 'a: "2"'))
seq = d.applied(lambda p: open(p).read(), ["13-kubernetes-1.34.12", "42-kubernetes-1.35", "43-kubernetes-1.36"])
k = seq["deploy/ansible/playbooks/setup-kubeadm.yml"]
check("13, 42, 43 in order end at 1.36.5",
      ('k8s_version: "1.36"' in k, 'k8s_package_version: "1.36.5-1.1"' in k, "1.34.6-1.1" not in k), (True, True, True))
try:
    d.applied(lambda p: open(p).read(), ["43-kubernetes-1.36"])
    check("43 without 42 refuses", "applied", "refused")
except ValueError:
    check("43 without 42 refuses (its old line is 42's new)", True, True)
print("upgrade-defaults: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
rc=$?
python3 scripts/upgrade-defaults.py --lint || rc=1
exit $rc
