#!/bin/bash
# upgrade-kubeadm.yml's preview (--check) as the playbook holds it, run by ansible-playbook --check on localhost: the
# tasks that run in a preview (check_mode: false) answered as the node would - the cluster at the version before
# (the upgrade to come) or at the target already (a run cut short after the kubelet's restart) - every other module
# a no-op that check mode skips as it skips the real one. Both previews end cleanly: the cut-short one went on to the
# proofs, which check mode skips, and failed on their skipped results - production's preview (the ledger wants one
# before the playbooks) could never pass after such a run.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
PY=$(dirname "$(readlink -f "$AP")")/python3
[ -x "$PY" ] || PY=python3
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
W=$W "$PY" - <<'PY'
import os, yaml
W = os.environ["W"]
play = yaml.safe_load(open("deploy/ansible/playbooks/upgrade-kubeadm.yml"))
# the answers of the tasks a preview runs: their registers as the node gives them
ANSWERS = {
    "_running": {"rc": 0, "stdout": "{{ preview_running }}"},
    "_runtime": {"rc": 0, "stdout": "containerd://2.3.6"},
    "_grace_in_map": {"rc": 0, "stdout_lines": ["shutdownGracePeriod: 180s", "shutdownGracePeriodCriticalPods: 30s"]},
    "_package": {"rc": 0, "stdout": "1.34.12-1.1"},
}
KEEP = ("name", "when", "register", "check_mode", "vars", "loop", "loop_control", "changed_when", "failed_when", "until")


def stub(t):
    if "block" in t:
        return {**{k: v for k, v in t.items() if k not in ("block", "rescue", "always")},
                **{k: [stub(x) for x in t[k]] for k in ("block", "rescue", "always") if k in t}}
    keep = {k: v for k, v in t.items() if k in KEEP}
    if any(k in t for k in ("ansible.builtin.assert", "ansible.builtin.set_fact", "ansible.builtin.meta",
                            "ansible.builtin.debug", "ansible.builtin.fail")):
        return t
    if t.get("check_mode") is False:
        # runs in a preview: its answer (a task with none passes, as the node's would)
        reg = t.get("register")
        return {**{k: v for k, v in keep.items() if k not in ("register", "check_mode")},
                "ansible.builtin.set_fact": {reg: ANSWERS[reg]} if reg else {"_ran": True}}
    # skipped by check mode, as the real module is (a command), its register then {skipped: true}
    return {**{k: v for k, v in keep.items() if k != "changed_when"}, "ansible.builtin.command": "true"}


for p in play:
    p.pop("become", None)
    p["tasks"] = [stub(t) for t in p["tasks"]]
yaml.safe_dump(play, open(os.path.join(W, "play.yml"), "w"), sort_keys=False)
open(os.path.join(W, "hosts.yml"), "w").write(
    "all:\n  hosts:\n    target: {ansible_connection: local, ansible_python_interpreter: '{{ ansible_playbook_python }}'}\n")
PY
fails=0
case_() {  # case_ <name> <the version running> <want in the output>
  out=$(ANSIBLE_NOCOLOR=1 "$AP" --check -i "$W/hosts.yml" "$W/play.yml" -e k8s_upgrade_to=1.34.12 -e "preview_running=$2" 2>&1)
  rc=$?
  if [ $rc = 0 ] && grep -qF -- "$3" <<< "$out"; then echo "PASS $1"; return; fi
  echo "FAIL $1 (rc $rc)"; grep -E "fatal|ERROR|PREVIEW" <<< "$out" | head -3; fails=$((fails + 1))
}
case_ "the cluster before the target: the preview says what it would do, and ends" v1.33.5 "PREVIEW: would upgrade"
case_ "at the target already (a run cut short after the kubelet's restart): the preview ends before the proofs" \
  v1.34.12 "PREVIEW: Kubernetes at v1.34.12 already"
# the package revision given: the target's passes, another refused before anything runs
out=$(ANSIBLE_NOCOLOR=1 "$AP" --check -i "$W/hosts.yml" "$W/play.yml" -e k8s_upgrade_to=1.34.12 -e k8s_upgrade_package=1.34.12-1.1 \
  -e preview_running=v1.33.5 2>&1); rc=$?
if [ $rc = 0 ] && grep -qF "PREVIEW: would upgrade" <<< "$out"; then echo "PASS the target's own package revision given: on"
else echo "FAIL the target's own package revision given (rc $rc)"; fails=$((fails + 1)); fi
out=$(ANSIBLE_NOCOLOR=1 "$AP" --check -i "$W/hosts.yml" "$W/play.yml" -e k8s_upgrade_to=1.34.12 -e k8s_upgrade_package=1.34.11-1.1 \
  -e preview_running=v1.33.5 2>&1); rc=$?
if [ $rc != 0 ] && grep -qF "is not a revision of 1.34.12" <<< "$out"; then echo "PASS another version's package revision: refused"
else echo "FAIL another version's package revision (rc $rc)"; fails=$((fails + 1)); fi
# the selection itself, against the repository's index (curl stubbed): the given revision exactly, else the newest
r=$(W=$W "$PY" - <<'PYSEL'
import os, subprocess, sys, yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render
W = os.environ["W"]
play = yaml.safe_load(open("deploy/ansible/playbooks/upgrade-kubeadm.yml"))[0]
flat = lambda ts: [x for t in ts for x in [t] + flat(t.get("block", []) + t.get("rescue", []) + t.get("always", []))]
sel = next(t for t in flat(play["tasks"]) if t.get("register") == "_package")
os.makedirs(os.path.join(W, "bin"), exist_ok=True)
# the index as pkgs.k8s.io serves it: each version once an architecture (four kubeadm entries a version)
entries = "".join(f"Package: {p}\\nArchitecture: {a}\\nVersion: {v}\\n\\n" for p, v in (("kubeadm", "1.34.12-1.1"), ("kubeadm", "1.34.12-1.2"), ("kubelet", "1.34.12-1.9"))
                  for a in ("amd64", "arm64", "ppc64le", "s390x"))
open(os.path.join(W, "bin", "curl"), "w").write("#!/bin/bash\nprintf '" + entries + "'\n")
os.chmod(os.path.join(W, "bin", "curl"), 0o755)
def pick(pkg):
    cmd = render(sel["ansible.builtin.shell"], target="1.34.12", target_minor="1.34", target_package=pkg)
    r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"]))
    return r.stdout.strip()
print([pick("1.34.12-1.1"), pick(""), pick("1.34.12-1.3")])
# one line or the task fails (its failed_when): never several versions handed to apt as one
from templar import condition  # noqa: E402
fw = sel["failed_when"]
print([condition(fw, _package={"rc": 0, "stdout": o, "stdout_lines": o.splitlines()}) for o in ("1.34.12-1.1", "1.34.12-1.1\n1.34.12-1.1", "")])
PYSEL
)
if [ "$r" = "['1.34.12-1.1', '1.34.12-1.2', '']
[False, True, True]" ]; then echo "PASS the package (the index's four architectures a version): the given revision exactly, once (not the newest), the newest when none is given, none when it is gone - one line or the task fails"
else echo "FAIL the package selection: $r"; fails=$((fails + 1)); fi
echo "kubeadm-preview: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
