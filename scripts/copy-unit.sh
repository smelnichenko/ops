#!/usr/bin/env bash
# The upgrade cycle's proof of one Renovate unit on the built Vagrant copy (docs/plans/120-automated-upgrade-cycle.md,
# part 2 step 2): the unit's branch, renovate/<unit>, fetched from origin in infra, platform and ops; infra's and
# platform's mirrored onto the copy with every check (task test:copy:change), then each ops part the unit moves run as
# production would run it (task test:copy:playbook), its new values read from the unit's own branch - the ops checkout
# stays as it is. A changed ops value with no known proof is refused: the unit is not proven, never waved through.
#
# Usage: scripts/copy-unit.sh <unit> [--plan]     --plan: what it would run, one task a line; runs nothing
# Env:   COPY_UNIT_SRC (the directory holding infra, platform and ops - default this repo's parent; the harness's own)
set -euo pipefail
export LC_ALL=C
unit=${1:-}
mode=${2:-run}
[[ $unit =~ ^[a-z0-9][a-z0-9.-]*$ ]] || { echo "REFUSED: copy-unit.sh <unit> [--plan] - a unit's name (renovate/<it>), not '$unit'"; exit 2; }
[[ $mode == run || $mode == --plan ]] || { echo "REFUSED: copy-unit.sh <unit> [--plan] - not '$mode'"; exit 2; }
ops=$(cd "$(dirname "$0")/.." && pwd)
src=${COPY_UNIT_SRC:-$(dirname "$ops")}
ops_repo=$src/ops
branch=renovate/$unit
py=$ops/deploy/ansible/venv/bin/python3
[ -x "$py" ] || py=python3

# the unit's branch in each repo, fetched (a repo the unit does not touch has none: main stands for it)
ref_of() {
  local repo=$1
  if git -C "$repo" ls-remote --exit-code --heads origin "$branch" > /dev/null 2>&1; then
    git -C "$repo" fetch -q origin "+refs/heads/$branch:refs/heads/$branch"
    echo "$branch"
  else
    echo main
  fi
}
infra_ref=$(ref_of "$src/infra")
platform_ref=$(ref_of "$src/platform")
ops_ref=$(ref_of "$ops_repo")
if [ "$infra_ref" = main ] && [ "$platform_ref" = main ] && [ "$ops_ref" = main ]; then
  echo "REFUSED: no branch $branch in infra, platform or ops - no such unit"
  exit 1
fi

steps=()
if [ "$infra_ref" != main ] || [ "$platform_ref" != main ]; then
  steps+=("test:copy:change INFRA_REF=$infra_ref PLATFORM_REF=$platform_ref")
fi

# the ops part: each value the unit's branch changes, mapped to the playbook production runs for it
if [ "$ops_ref" != main ]; then
  # the unit's vars files, read from its branch, where test:copy:playbook reads them (-e @<file>)
  mkdir -p "$ops_repo/.copy"
  out=$(mktemp -d "$ops_repo/.copy/unit-$unit.XXXXXX")
  ops_steps=$(OPS="$ops_repo" BRANCH="$branch" OUT="$out" "$py" - <<'PY'
import os, subprocess, sys
import yaml
OPS, BRANCH, OUT = os.environ["OPS"], os.environ["BRANCH"], os.environ["OUT"]
def show(ref, path):
    r = subprocess.run(["git", "-C", OPS, "show", f"{ref}:{path}"], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None
changed = subprocess.run(["git", "-C", OPS, "diff", "--name-only", f"main...{BRANCH}"], capture_output=True, text=True,
                         check=True).stdout.split()
# the values ops restates from production's Argo charts (defaults-follow-production): they move with the infra unit
FOLLOW = {"cert_manager_version", "external_secrets_chart_version", "metrics_server_chart_version", "istio_version",
          "argocd_chart_version", "local_path_provisioner_version", "gateway_api_version"}
def play_vars(text):
    doc = yaml.safe_load(text) or []
    return (doc[0].get("vars") or {}) if isinstance(doc, list) and doc and isinstance(doc[0], dict) else {}
steps, refused = [], []
import re
VERSION = re.compile(r"[0-9][0-9A-Za-z.+~-]*", re.ASCII)  # a value that reaches a command line: a version, nothing else
def version(v):
    v = str(v)
    if not VERSION.fullmatch(v):
        raise SystemExit(f"REFUSED: the unit's value {v!r} is no version")
    return v
VARS_FILES = {  # a vars file -> its playbook and the arguments production's task passes (the Vagrant ones beside)
    "deploy/ansible/vars/patroni.yml": ("upgrade-patroni.yml", ""),
    "deploy/ansible/vars/vault.yml": ("upgrade-vault.yml", "-e @vars/vault-vagrant.yml"),
    "deploy/ansible/vars/forgejo.yml": ("upgrade-forgejo.yml", ""),
}
ORDER = {"upgrade-kubeadm.yml": 0, "setup-kubeadm.yml": 1, "upgrade-patroni.yml": 2, "upgrade-vault.yml": 3,
         "upgrade-forgejo.yml": 4}
for path in changed:
    if not path.startswith("deploy/ansible/"):
        continue  # renovate.json and the like: no part of a deploy
    if path == "deploy/ansible/playbooks/setup-kubeadm.yml":
        old, new = play_vars(show("main", path) or ""), play_vars(show(BRANCH, path) or "")
        for k in sorted(set(old) | set(new)):
            if old.get(k) == new.get(k):
                continue
            if k == "k8s_package_version":
                steps.append(("upgrade-kubeadm.yml", f"-e k8s_upgrade_to={version(new[k]).split('-')[0]}", True))
            elif k == "cilium_version":
                steps.append(("setup-kubeadm.yml", f"--tags cilium -e cilium_version={version(new[k])}", False))
            elif k in FOLLOW or k in ("k8s_version", "k8s_cni_version", "k8s_cri_tools_version"):
                continue  # production's Argo charts, or the packages kubeadm's upgrade brings along
            else:
                refused.append(f"{path} {k}")
    elif path in VARS_FILES:
        text = show(BRANCH, path)
        if text is None:
            refused.append(f"{path} (gone on the branch)")
            continue
        dest = os.path.join(OUT, os.path.basename(path))
        open(dest, "w").write(text)
        playbook, extra = VARS_FILES[path]
        steps.append((playbook, f"-e @{dest} {extra}".strip(), False))
    else:
        refused.append(path)
if refused:
    print("REFUSED: the unit changes ops values with no known proof: " + ", ".join(refused))
    sys.exit(1)
for playbook, args, restarts in sorted(steps, key=lambda s: ORDER[s[0]]):
    print(f"test:copy:playbook PLAYBOOK={playbook} ARGS='{args}'" + (" RESTARTS_EXPECTED=true" if restarts else ""))
PY
) || { echo "$ops_steps"; exit 1; }
  while IFS= read -r line; do [ -n "$line" ] && steps+=("$line"); done <<< "$ops_steps"
fi

if [ "${#steps[@]}" -eq 0 ]; then
  echo "REFUSED: $branch changes nothing a proof runs - nothing to prove"
  exit 1
fi
for s in "${steps[@]}"; do echo "$s"; done
[ "$mode" = run ] || exit 0
for s in "${steps[@]}"; do
  echo "=== UNIT $unit: task $s"
  eval "task $s"
done
echo "=== UNIT $unit PROVEN"
