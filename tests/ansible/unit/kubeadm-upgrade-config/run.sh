#!/bin/bash
# upgrade-kubeadm.yml's UpgradeConfiguration, rendered as the playbook holds it (its task's content, through Ansible):
# every field one kubeadm v1beta4 knows (its own `config print upgrade-defaults`, upgrade-defaults.yaml here, plus the
# apply fields it prints only when set) - kubeadm's `config validate` takes a misspelled or misplaced one silently and
# runs on its 2 m default; etcdAPICall is kubeadm's own upgradeManifests (the time it gives any static pod to restart);
# the target, the skipped kube-proxy phase and the preflight errors as given.
set -u
H=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$H/../../../.." && pwd)
AP=$(command -v ansible-playbook 2>/dev/null \
  || { [ -x "$ROOT/deploy/ansible/venv/bin/ansible-playbook" ] && echo "$ROOT/deploy/ansible/venv/bin/ansible-playbook"; })
[ -x "${AP:-}" ] || { echo "kubeadm-upgrade-config: no ansible-playbook found (PATH, repo venv)"; exit 2; }
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
python3 - "$ROOT" "$W" <<'PY'
import json, sys
import yaml
root, w = sys.argv[1:]
pb = yaml.safe_load(open(f"{root}/deploy/ansible/playbooks/upgrade-kubeadm.yml"))
def tasks(ts):
    for t in ts:
        yield t
        for k in ("block", "rescue", "always"):
            yield from tasks(t.get(k, []))
task = next(t for t in tasks(pb[0]["tasks"]) if t.get("ansible.builtin.copy", {}).get("dest") == "/etc/kubernetes/kubeadm-upgrade.yaml")
json.dump({"content": task["ansible.builtin.copy"]["content"], **task.get("vars", {})}, open(f"{w}/task.json", "w"))
PY
cat > "$W/play.yml" <<PLAY
- hosts: localhost
  gather_facts: false
  vars_files: [$W/task.json]
  vars:
    target: "{{ t }}"
    ignore_preflight: "{{ ip }}"
  tasks:
    - ansible.builtin.copy:
        content: "{{ content }}"
        dest: "$W/out-{{ t }}.yaml"
        mode: '0644'
PLAY
render() { ANSIBLE_NOCOLOR=1 "$AP" -c local -i localhost, "$W/play.yml" -e "t=$1" -e "ip=$2" > "$W/log" 2>&1 || { cat "$W/log"; exit 1; }; }
render 1.34.12 CoreDNSUnsupportedPlugins && render 1.35.9 ""
python3 - "$H/upgrade-defaults.yaml" "$W" <<'PY'
import re, sys
import yaml
defaults, w = yaml.safe_load(open(sys.argv[1])), sys.argv[2]
# the apply fields kubeadm prints only when set (v1beta4 UpgradeApplyConfiguration)
known = defaults
known["apply"].update(dict.fromkeys(("kubernetesVersion", "allowExperimentalUpgrades", "allowRCUpgrades", "dryRun",
                                     "forceUpgrade", "ignorePreflightErrors", "patches", "printConfig", "skipPhases")))
known["kind"], known["apiVersion"] = "UpgradeConfiguration", "kubeadm.k8s.io/v1beta4"
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))
def unknown(d, ref, path=""):
    out = []
    for k, v in d.items():
        if not isinstance(ref, dict) or k not in ref:
            out.append(path + k)
        elif isinstance(v, dict):
            out += unknown(v, ref[k], path + k + ".")
    return out
def seconds(d):
    return sum(int(n) * {"h": 3600, "m": 60, "s": 1}[u] for n, u in re.findall(r"(\d+)([hms])", d))
c = yaml.safe_load(open(f"{w}/out-1.34.12.yaml"))
check("every field one kubeadm knows", unknown(c, known), [])
check("kind and version", (c["apiVersion"], c["kind"]), ("kubeadm.k8s.io/v1beta4", "UpgradeConfiguration"))
check("etcdAPICall is kubeadm's own upgradeManifests (the time any static pod gets to restart)",
      seconds(c["timeouts"]["etcdAPICall"]), seconds(defaults["timeouts"]["upgradeManifests"]))
check("etcdAPICall longer than kubeadm's default (which failed step 13)",
      seconds(c["timeouts"]["etcdAPICall"]) > seconds(defaults["timeouts"]["etcdAPICall"]), True)
check("the target, the skipped kube-proxy phase, the preflight errors",
      (c["apply"]["kubernetesVersion"], c["apply"]["skipPhases"], c["apply"]["ignorePreflightErrors"]),
      ("v1.34.12", ["addon/kube-proxy"], ["CoreDNSUnsupportedPlugins"]))
c2 = yaml.safe_load(open(f"{w}/out-1.35.9.yaml"))
check("no preflight errors given: an empty list", (c2["apply"]["kubernetesVersion"], c2["apply"]["ignorePreflightErrors"]),
      ("v1.35.9", []))
print("kubeadm-upgrade-config: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
