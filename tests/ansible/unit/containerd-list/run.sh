#!/bin/bash
# upgrade-containerd.yml's swap and its take-up as the playbook holds them, run by ansible-playbook on localhost: the
# list of the containers running when the kubelet stopped and the kubelet's state are real files, crictl a stub (the
# running and exited ids, its info failing as asked), the package and config steps no-ops or the failure injected.
# The list lives only while the kubelet has stayed stopped since it was written: every path that starts the kubelet
# (the swap done, a failure the rescue recovered, the kept config, a take-up) removes it; a run that keeps the kubelet
# stopped (a container lost) keeps it. A recovered failure, a CI pod deleted meanwhile, then the run again: it judges
# the containers running now - with the hours-old list it read the deleted pod as lost and left the kubelet stopped.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
PY=$(dirname "$(readlink -f "$AP")")/python3
[ -x "$PY" ] || PY=python3
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cat > "$W/crictl" <<'STUB'
#!/bin/bash
case "$*" in
  "ps -q --state running") for c in $RUNNING; do echo "$c"; done ;;
  "ps -a -q --state exited") for c in $EXITED; do echo "$c"; done ;;
  info) n=$(cat "$INFO_CALLS" 2> /dev/null || echo 0); echo $((n + 1)) > "$INFO_CALLS"
        [ "$n" -ge "${INFO_FAILS:-0}" ] || { echo "connection refused" >&2; exit 1; } ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$W/crictl"
W=$W "$PY" - <<'PY'
import os, yaml
W = os.environ["W"]
play = yaml.safe_load(open("deploy/ansible/playbooks/upgrade-containerd.yml"))[0]
tasks = play["tasks"]
names = [t.get("name", "") for t in tasks]
start = names.index("Keep the live config (the first run's - never overwritten by a re-run)")
end = names.index("Failed - the runtime runs on the kept config")
takeup = next(t for t in tasks if t.get("name", "").startswith("The swap done, the kubelet stopped"))
KEEP = ("name", "when", "register", "changed_when", "failed_when", "vars", "args", "loop", "loop_control")
INC = os.path.abspath("deploy/ansible/playbooks/tasks/containerd-known-containers.yml")


def stub(t, fail):
    """The task as it acts on the list and the kubelet: those kept or modelled, the rest a no-op, `fail`'s a failure."""
    if "block" in t:
        return {**{k: v for k, v in t.items() if k not in ("block", "rescue", "always")},
                **{k: [stub(x, fail) for x in t[k]] for k in ("block", "rescue", "always") if k in t}}
    keep = {k: v for k, v in t.items() if k in KEEP}
    if fail and t.get("name", "").startswith(fail):
        return {"name": t["name"], "ansible.builtin.fail": {"msg": "injected"}}
    svc = t.get("ansible.builtin.systemd_service", {})
    if svc.get("name") == "kubelet" and "state" in svc:
        return {"name": t["name"], "ansible.builtin.copy": {"content": svc["state"], "dest": "{{ kubelet_state }}"}}
    if t.get("ansible.builtin.include_tasks") == "tasks/containerd-known-containers.yml":
        return {**keep, "ansible.builtin.include_tasks": INC}
    body = str({k: v for k, v in t.items() if k.startswith("ansible.builtin.")})
    if any(k in t for k in ("ansible.builtin.shell", "ansible.builtin.command", "ansible.builtin.file")) \
            and ("before_file" in body or "crictl" in body):
        return {k: v for k, v in t.items() if k not in ("retries", "delay", "until", "become")}
    if any(k in t for k in ("ansible.builtin.fail", "ansible.builtin.assert", "ansible.builtin.set_fact",
                            "ansible.builtin.meta", "ansible.builtin.debug")):
        return t
    return {"name": t.get("name", ""), "ansible.builtin.debug": {"msg": "stub"},
            **({"when": t["when"]} if "when" in t else {})}


VARS = {"crictl": os.path.join(W, "crictl"), "before_file": os.path.join(W, "list"),
        "kubelet_state": os.path.join(W, "kubelet"), "_package": {"stdout": "2.3.6-1"}, "_runtime_line": "1.7.24",
        "_swapped": True, "_kubelet_now": {"status": {"ActiveState": "inactive"}}}
for name, part, fail in (("swap", tasks[start:end + 1], None),
                         ("install-fails", tasks[start:end + 1], "Install containerd.io "),
                         ("takeup", [takeup], None)):
    yaml.safe_dump([{"hosts": "localhost", "connection": "local", "gather_facts": False, "vars": VARS,
                     "tasks": [stub(t, fail) for t in part]}], open(os.path.join(W, name + ".yml"), "w"),
                   sort_keys=False)
PY
fails=0
run() {  # run <play> <env...>: the play's output in $out, its rc in $rc
  local p=$1; shift
  out=$(env "$@" INFO_CALLS="$W/info-calls" ANSIBLE_NOCOLOR=1 "$AP" -i localhost, "$W/$p.yml" 2>&1); rc=$?
  rm -f "$W/info-calls"
}
state() {  # the kubelet's state and whether the list is there
  echo "kubelet=$(cat "$W/kubelet" 2> /dev/null || echo untouched) list=$([ -e "$W/list" ] && echo kept || echo gone)"
}
expect() {  # expect <name> <rc 0|1> <state> <output must contain>
  local r=$rc; [ "$r" = 0 ] || r=1
  if [ "$r" = "$2" ] && [ "$(state)" = "$3" ] && grep -qF -- "$4" <<< "$out"; then echo "PASS $1"; return; fi
  echo "FAIL $1 (rc $rc, $(state); want rc $2, $3, '$4')"; grep -E "ERROR|fatal|msg" <<< "$out" | tail -3
  fails=$((fails + 1))
}
fresh() { rm -f "$W/list" "$W/kubelet"; }
fresh; run swap RUNNING="aaa bbb" EXITED=""
expect "the swap done: the kubelet started, the list gone" 0 "kubelet=started list=gone" "PLAY RECAP"
fresh; run install-fails RUNNING="aaa bbb" EXITED=""
expect "the install failed, recovered: the kubelet started, the list gone" 1 "kubelet=started list=gone" \
  "Failed before the restart - the kubelet is back"
run swap RUNNING="aaa" EXITED=""
expect "then a pod deleted, the run again: judged on the containers running now" 0 "kubelet=started list=gone" \
  "PLAY RECAP"
fresh; run swap RUNNING="aaa bbb" EXITED="" INFO_FAILS=1
expect "the CRI silent on the new config: the kept config, the kubelet started, the list gone" 1 \
  "kubelet=started list=gone" "did not serve the CRI"
fresh; printf 'aaa\nbbb\n' > "$W/list"; echo stopped > "$W/kubelet"; run takeup RUNNING="aaa bbb" EXITED=""
expect "a cut-short swap taken up: the kubelet started, the list gone" 0 "kubelet=started list=gone" \
  "the kubelet was stopped; every container known, started"
# the list as the stop left it (bbb ran then), bbb lost by the failure: nothing starts the kubelet, the list stays
fresh; printf 'aaa\nbbb\n' > "$W/list"; run install-fails RUNNING="aaa" EXITED=""
expect "the install failed and a container lost: the kubelet stays stopped, the list kept" 1 \
  "kubelet=stopped list=kept" "CONTAINERS LOST: bbb"
echo "containerd-list: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
