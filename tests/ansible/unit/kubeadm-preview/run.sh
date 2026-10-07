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
echo "kubeadm-preview: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
