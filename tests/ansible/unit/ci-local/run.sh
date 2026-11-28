#!/bin/bash
# scripts/ci-local.sh (task test:ci) - ops' CI steps as .woodpecker/ci.yaml has them, run here: against a stub docker
# (recording what it was asked) and a stub virsh. By default ansible-lint then ansible-unit, each in ci.yaml's image, its
# commands as one sh -e script, its environment, its memory limit (Gi as g), as the operator's user over this tree at
# CI's clone path; a step named alone; a step ci.yaml lacks refused; the copy's VMs running - refused, nothing run; a step
# failing stops there, named.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi; }
cat > "$W/docker" <<'STUB'
#!/bin/bash
n=$(ls "$W_OUT"/call.* 2> /dev/null | wc -l)
printf '%s\n' "$@" > "$W_OUT/call.$n"
[ -z "${FAIL_ON:-}" ] || ! grep -qxF -- "$FAIL_ON" "$W_OUT/call.$n" || exit 1
exit 0
STUB
cat > "$W/virsh" <<'STUB'
#!/bin/bash
printf '%s\n' ${VMS:-}
STUB
chmod +x "$W/docker" "$W/virsh"
run() {  # [env...] -- [args...]: the script's exit; its calls in $W/call.*
  rm -f "$W"/call.*
  local envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  shift
  env "${envs[@]}" W_OUT="$W" CI_LOCAL_DOCKER="$W/docker" CI_LOCAL_VIRSH="$W/virsh" scripts/ci-local.sh "$@" > "$W/out" 2>&1
  echo $?
}
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
want=$("$PY" - <<'PYWANT'
import yaml
d = yaml.safe_load(open(".woodpecker/ci.yaml"))
s = {x["name"]: x for x in d["steps"]}
for n in ("ansible-lint", "ansible-unit"):
    print(s[n]["image"], "|", "\n".join(s[n]["commands"]).replace("\n", "\\n"))
PYWANT
)
rc=$(run --)
got=""
for i in 0 1; do
  f="$W/call.$i"
  [ -e "$f" ] || { got="$got missing-call-$i"; continue; }
  img=$(grep -x -A2 -- '--entrypoint' "$f" | tail -1)  # --entrypoint sh <image>
  scr=$(tail -1 "$f")
  got="$got$(sed -n 1p "$f") $img | ${scr//$'\n'/\\n};"
done
check "by default: ansible-lint, then ansible-unit - each docker run in ci.yaml's image, its commands as the script" \
  "$rc$got" "0run $(sed -n 1p <<< "$want");run $(sed -n 2p <<< "$want");"
c0=$W/call.0 c1=$W/call.1
check "  as the operator's user, a home it can write, this tree at CI's clone path and there; sh -e" \
  "$(grep -cxF -- "$(id -u):$(id -g)" "$c0") $(grep -cx 'HOME=/tmp' "$c0") $(grep -cxF -- "$PWD:/woodpecker/src/git.pmon.dev/schnappy/ops" "$c0") $(grep -cx '/woodpecker/src/git.pmon.dev/schnappy/ops' "$c0") $(grep -cx -- '-ec' "$c0")" \
  "1 1 1 1 1"
check "  each step's memory limit (ansible-lint 1Gi, ansible-unit 2Gi: swap the same), the unit step's UNIT_JOBS" \
  "$(grep -cx -- '--memory=1g' "$c0") $(grep -cx -- '--memory-swap=1g' "$c0") $(grep -cx -- '--memory=2g' "$c1") $(grep -cx 'UNIT_JOBS=8' "$c1") $(grep -c 'UNIT_JOBS' "$c0")" \
  "1 1 1 1 0"
rc=$(run -- ansible-unit)
check "a step named alone: that step, once" "$rc $(ls "$W"/call.* | wc -l) $(grep -c 'tests/ansible/unit/run.sh' "$W/call.0")" "0 1 1"
rc=$(run -- no-such-step)
check "a step ci.yaml lacks: refused, nothing run" "$rc $(ls "$W"/call.* 2> /dev/null | wc -l) $(grep -c "no step 'no-such-step'" "$W/out")" "2 0 1"
rc=$(run VMS=ops_kubeadm --)
check "the copy's VMs running: refused, nothing run" "$rc $(ls "$W"/call.* 2> /dev/null | wc -l) $(grep -c 'REFUSED' "$W/out")" "1 0 1"
rc=$(run VMS=other_vm --)
check "  another VM (not the copy's): run" "$rc $(ls "$W"/call.* | wc -l)" "0 2"
rc=$(run FAIL_ON=--memory=1g --)
check "a step failing (ansible-lint): stopped there, named - the next never run" \
  "$rc $(ls "$W"/call.* | wc -l) $(grep -c 'step ansible-lint FAILED' "$W/out")" "1 1 1"
check "task test:ci: the script, nothing else" \
  "$("$PY" -c 'import yaml; t = yaml.safe_load(open("Taskfile.yml"))["tasks"]["test:ci"]; print([c if isinstance(c, str) else c.get("cmd") for c in t["cmds"]])')" \
  "['scripts/ci-local.sh {{.CLI_ARGS}}']"
echo "ci-local: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
