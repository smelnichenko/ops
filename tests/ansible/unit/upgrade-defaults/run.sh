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
tree = lambda p: open(p).read()
K8S, KUBEADM = ("13-kubernetes-1.34.12", "42-kubernetes-1.35", "43-kubernetes-1.36"), \
    "deploy/ansible/playbooks/setup-kubeadm.yml"
seq = d.applied(tree, [s for s in d.pending(tree) if s in K8S])
k = seq.get(KUBEADM, tree(KUBEADM))
check("13, 42, 43 in order end at 1.36.5 (the committed ones in the tree already)",
      ('k8s_version: "1.36"' in k, 'k8s_package_version: "1.36.5-1.1"' in k, "1.34.6-1.1" not in k), (True, True, True))
after13 = "\n".join(new for path, _, new in d.default_lines(K8S[0]) if path == KUBEADM) + "\n"
try:
    d.applied(lambda p: after13, [K8S[2]])
    check("43 right after 13 refuses", "applied", "refused")
except ValueError:
    check("43 right after 13 refuses (its old line is 42's new)", True, True)

# the steps production committed (the record, which --apply extends): lint and the targets branch start after them
with_lines = [s for s in d.step_names() if d.default_lines(s)]
H = "# header\n"
rec = lambda text, read=tree: (lambda p: text if p == d.COMMITTED else read(p))
check("the record in the tree is a valid one", d.pending(tree)[-1], with_lines[-1])
check("nothing committed: every step with default lines pending", d.pending(rec(H)), with_lines)
check("the first committed: the rest pending", d.pending(rec(H + with_lines[0] + "\n")), with_lines[1:])
try:
    d.pending(rec(H + with_lines[1] + "\n"))
    check("a record skipping a step refuses", "pending", "refused")
except ValueError as e:
    check("a record skipping a step refuses, naming the file", d.COMMITTED in str(e), True)
first = d.applied(rec(H), with_lines[:1])
check("applying a step adds it to the record", first[d.COMMITTED], H + with_lines[0] + "\n")
committed = lambda p: first.get(p) or tree(p)
check("after the first step's commit: the rest still apply, the record then lists every step",
      d.applied(committed, d.pending(committed))[d.COMMITTED], H + "".join(f"{s}\n" for s in with_lines))
try:
    d.applied(committed, with_lines)
    check("after the first step's commit: every step from the first no longer applies", "applied", "refused")
except ValueError:
    check("after the first step's commit: every step from the first no longer applies (why the record)", True, True)
path0, old0, _ = d.default_lines(with_lines[0])[0]
wrong = lambda p: tree(p).replace(old0, "# gone") if p == path0 else rec(H)(p)
try:
    d.applied(wrong, d.pending(wrong))
    check("an uncommitted step's missing old line still fails", "applied", "refused")
except ValueError as e:
    check("an uncommitted step's missing old line still fails", with_lines[0] in str(e), True)
print("upgrade-defaults: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
rc=$?
python3 scripts/upgrade-defaults.py --lint || rc=1
exit $rc
