#!/bin/bash
# scripts/upgrade-defaults.py: a default line replaces every line equal to its old one, keeping the indentation, and
# refuses a file without it; the steps' lines apply in step order to the working tree's playbooks (--lint); the
# committed ones revert to the baseline (production commits them during the rollout: defaults_baseline.py).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
python3 - <<'PY'
import importlib.machinery
import importlib.util
import sys

loader = importlib.machinery.SourceFileLoader("upgrade_defaults", "scripts/upgrade-defaults.py")
d = importlib.util.module_from_spec(importlib.util.spec_from_loader("upgrade_defaults", loader))
loader.exec_module(d)
hl = importlib.machinery.SourceFileLoader("defaults_baseline", "tests/ansible/unit/defaults_baseline.py")
helper = importlib.util.module_from_spec(importlib.util.spec_from_loader("defaults_baseline", hl))
hl.exec_module(helper)
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
# a rebuild installs the minor's CNI plugins and crictl as upgrade-kubeadm.yml leaves a node: setup-kubeadm's pins equal
# its minor_packages for k8s_version - in the tree, and after each Kubernetes step's default lines
import re, yaml
minor = yaml.safe_load(open("deploy/ansible/playbooks/upgrade-kubeadm.yml"))[0]["vars"]["minor_packages"]
def pins(text):
    v = lambda k: re.search(rf'^\s*{k}: "([^"]*)"', text, re.M)
    got = [f"kubernetes-cni={v('k8s_cni_version') and v('k8s_cni_version')[1]}",
           f"cri-tools={v('k8s_cri_tools_version') and v('k8s_cri_tools_version')[1]}"]
    return v("k8s_version")[1], got
for upto in ((), K8S[:2], K8S):
    text = d.applied(tree, [s for s in d.pending(tree) if s in upto]).get(KUBEADM, tree(KUBEADM)) if upto else tree(KUBEADM)
    ver, got = pins(text)
    check(f"setup-kubeadm's CNI and crictl pins at {ver} (after {upto[-1] if upto else 'the tree'}): the minor's",
          got, minor[ver])

# CI lints the playbooks with every committed step's lines in: none may make a line its 160 columns refuse
allin = d.applied(tree, d.pending(tree))
over = [f"{p}:{n}" for p, text in allin.items() if p.endswith(".yml")
        for n, line in enumerate(text.split("\n"), 1) if len(line) > 160]
check("every step's default lines applied: no playbook line over 160 columns", over, [])

after13 = "\n".join(new for path, _, new in d.default_lines(K8S[0]) if path == KUBEADM) + "\n"
try:
    d.applied(lambda p: after13, [K8S[2]])
    check("43 right after 13 refuses", "applied", "refused")
except ValueError:
    check("43 right after 13 refuses (its old line is 42's new)", True, True)

# the steps production committed (the record, which --apply extends): lint and the targets branch start after them
with_lines = [s for s in d.step_names() if d.default_lines(s)]
H = "# header\n"
# the baseline (what a full run proved): the tree with the committed steps' lines reverted - nothing committed in it
B = helper.baseline(d, tree)
base = lambda p: B[p] if p in B else tree(p)
rec = lambda text, read=base: (lambda p: text if p == d.COMMITTED else read(p))
done = [s for s in with_lines if s not in d.pending(tree)]
check("the baseline: every committed step's lines applied to it give the tree back",
      {p: c == tree(p) for p, c in d.applied(rec(H), done).items() if p != d.COMMITTED}, {p: True for p in B})
path1, _, new1 = d.default_lines(with_lines[0])[0]
one = rec(H + with_lines[0] + "\n", d.applied(base, with_lines[:1]).get)  # the first step committed, nothing else
try:
    helper.baseline(d, lambda p: one(p).replace(new1, "# gone") if p == path1 else (one(p) or base(p)))
    check("a committed step whose new line is gone: no baseline", "reverted", "refused")
except ValueError as e:
    check("a committed step whose new line is gone: no baseline, naming it", with_lines[0] in str(e), True)
# every step committed (44-eso-2.12 the last with default lines): nothing pending - an index into it turned CI red
recorded = [s for s in tree(d.COMMITTED).splitlines() if s and not s.startswith("#")]
check("the record in the tree is a valid one: its steps, then the pending ones, are every step with default lines",
      recorded + d.pending(tree), with_lines)
check("nothing committed: every step with default lines pending", d.pending(rec(H)), with_lines)
check("the first committed: the rest pending", d.pending(rec(H + with_lines[0] + "\n")), with_lines[1:])
try:
    d.pending(rec(H + with_lines[1] + "\n"))
    check("a record skipping a step refuses", "pending", "refused")
except ValueError as e:
    check("a record skipping a step refuses, naming the file", d.COMMITTED in str(e), True)
first = d.applied(rec(H), with_lines[:1])
check("applying a step adds it to the record", first[d.COMMITTED], H + with_lines[0] + "\n")
# the other files as the baseline has them - the tree has the committed steps' new lines (25-versitygw's commit turned
# CI red on 2026-10-14: its old line read from the tree, where its own commit had replaced it)
committed = lambda p: first.get(p) or base(p)
check("after the first step's commit: the rest still apply, the record then lists every step",
      d.applied(committed, d.pending(committed))[d.COMMITTED], H + "".join(f"{s}\n" for s in with_lines))
try:
    d.applied(committed, with_lines)
    check("after the first step's commit: every step from the first no longer applies", "applied", "refused")
except ValueError:
    check("after the first step's commit: every step from the first no longer applies (why the record)", True, True)
# every state the rollout writes - none to all of the steps committed: the rest apply on it, the record then lists all
states = {}
for k in range(len(with_lines) + 1):
    state = d.applied(rec(H), with_lines[:k]) if k else {d.COMMITTED: H}
    read = lambda p, st=state: st.get(p) or base(p)
    try:
        states[k] = d.applied(read, d.pending(read))[d.COMMITTED] if k < len(with_lines) else read(d.COMMITTED)
    except ValueError as e:
        states[k] = str(e)
check(f"each of the rollout's {len(with_lines) + 1} states: the rest of the steps apply, the record then lists all",
      states, dict.fromkeys(range(len(with_lines) + 1), H + "".join(f"{s}\n" for s in with_lines)))
path0, old0, _ = d.default_lines(with_lines[0])[0]
wrong = lambda p: base(p).replace(old0, "# gone") if p == path0 else rec(H)(p)
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
