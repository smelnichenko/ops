#!/usr/bin/env bash
# ci-local.sh [step...] - ops' CI steps run here as Woodpecker runs them, before a push: each step of .woodpecker/ci.yaml
# named (by default ansible-lint and ansible-unit - what every ops change must pass), in its own image, with its commands,
# its environment and its memory limit, as the operator's user over this tree at the path CI's clone has. Read from
# ci.yaml itself: what runs here is what CI runs (the unit suite alone missed a playbook's 162-column line - ops#93,
# 2026-11-28). Never beside a copy run: the suite's 8 harnesses at once are a heavy run (the host guard's kill,
# 2026-11-18).
# Usage: scripts/ci-local.sh [step...]   (task test:ci)
# Env:   CI_LOCAL_DOCKER, CI_LOCAL_VIRSH (the harness's stubs; default docker, virsh)
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
cd "$ops"
if "${CI_LOCAL_VIRSH:-virsh}" -c qemu:///system list --name 2> /dev/null | grep '^ops_' > /dev/null; then  # read to the end: a reader leaving early is the writer's SIGPIPE
  echo "REFUSED: the copy's VMs run - no heavy local run beside them (vagrant halt first, or wait for the copy run)"
  exit 1
fi
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
steps=("$@")
[ "${#steps[@]}" -gt 0 ] || steps=(ansible-lint ansible-unit)
work=/woodpecker/src/git.pmon.dev/schnappy/ops  # CI's clone path: a harness that reads its own path sees CI's
owner="$(id -u):$(id -g)"  # the bind mount's owner; a variable: secrets-off-argv reads "-u):$" as a password
for step in "${steps[@]}"; do
  # the step as ci.yaml has it, one field a line (image, memory, then each environment entry, then the commands as one
  # script - Woodpecker runs them in sh, each failing the step)
  spec=$("$PY" - "$step" <<'PY_STEP'
import sys, yaml
d = yaml.safe_load(open(".woodpecker/ci.yaml"))
s = next((x for x in d.get("steps") or [] if x.get("name") == sys.argv[1]), None)
if s is None:
    sys.exit(f"REFUSED: no step {sys.argv[1]!r} in .woodpecker/ci.yaml")
mem = str((((s.get("backend_options") or {}).get("kubernetes") or {}).get("resources") or {}).get("limits", {}).get("memory", ""))
mem = mem.replace("Gi", "g").replace("Mi", "m")
print(s["image"])
print(mem)
for k, v in (s.get("environment") or {}).items():
    print(f"env {k}={v}")
print("script")
print("\n".join(s["commands"]))
PY_STEP
) || exit 2
  image=$(sed -n 1p <<< "$spec")
  mem=$(sed -n 2p <<< "$spec")
  envs=()
  while IFS= read -r e; do envs+=(-e "${e#env }"); done < <(sed -n '3,/^script$/p' <<< "$spec" | grep '^env ' || true)
  script=$(sed -n '/^script$/,$p' <<< "$spec" | tail -n +2)
  echo "=== ci-local: $step ($image${mem:+, memory $mem})"
  "${CI_LOCAL_DOCKER:-docker}" run --rm --user "$owner" -e HOME=/tmp "${envs[@]}" \
    ${mem:+--memory="$mem" --memory-swap="$mem"} -v "$ops:$work" -w "$work" --entrypoint sh "$image" -ec "$script" \
    || { echo "ci-local: step $step FAILED"; exit 1; }
  echo "=== ci-local: $step passed"
done
echo "ci-local: ${steps[*]} passed"
