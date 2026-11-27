#!/usr/bin/env bash
# The upgrade cycle's proof of one Renovate unit on the built Vagrant copy: the unit's branch, renovate/<unit>, fetched
# from origin in infra, platform and ops; infra's and platform's mirrored onto the copy with every check (task
# test:copy:change), then each ops part the unit moves run as production would run it (task test:copy:playbook): the
# ops checkout's playbook (main's), the unit's new values from its own branch handed to it (-e, a vars file beside) -
# the ops checkout stays as it is; a unit moving istiod's chart, every sidecar brought to it after (restart-mesh-workloads.yml).
# A changed ops value with no known proof is refused: the unit is not proven, never
# waved through; so is a value that is no version or hash (the values reach Ansible on this workstation, where the
# operator's ssh, kube and Vault are in reach: a Jinja expression in one, or a connection setting, would run here).
#
# Usage: scripts/copy-unit.sh <unit> [--plan]     --plan: what it would run, one task a line; runs nothing
# Env:   COPY_UNIT_SRC (the directory holding infra, platform and ops - default this repo's parent; the harness's own)
#        COPY_UNIT_PINS (the build-hash check's command - default scripts/renovate-checksums.py; the harness's stub)
set -euo pipefail
export LC_ALL=C.UTF-8  # its proof steps run Ansible, which refuses any locale encoding but UTF-8 (LC_ALL=C: 'Detected None')
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

# what vouches for the build hashes - the vendors' keys, the script that checks them, the one command Renovate may run -
# is the operator's: a unit's branch that changes it is refused, never proven
if [ "$ops_ref" != main ]; then
  trust=$(git -C "$ops_repo" diff --name-only "main...$branch" -- renovate/keys scripts/renovate-checksums.py \
    renovate/allowed-commands.json)
  if [ -n "$trust" ]; then
    echo "REFUSED: $branch changes what vouches for the build hashes ($(echo $trust)) - the operator's, never a unit's"
    exit 1
  fi
fi

# Istio's sidecars. A unit moving istiod's chart (infra's istiod app) is proven with every meshed pod's proxy on the
# chart's version: production's restart-mesh-workloads.yml on the copy after Argo applied the chart (the data tier one
# workload at a time, then the rest, until every sidecar runs that version), and task deploy:mesh:restart in production
# (the runner's apply). Proven without it - istiod 1.32 against the 1.31 proxies alone - production's pods, the data
# stores among them, would take the unproven proxy whenever each rescheduled, and the old proxy left in production's
# inventory would block every later copy build (the istio-1.32 review's CRITICAL, 2026-11-20). Ops restates the version
# (defaults-follow-production): an ops istio_version that is not the chart's, or one moving without it, is refused.
istio_to=""
if [ "$infra_ref" != main ]; then
  istio_to=$(INFRA="$src/infra" BRANCH="$branch" "$py" - <<'PY'
import os, re, subprocess, sys
import yaml
APP = "clusters/production/argocd/apps/istiod.yaml"
INFRA, BRANCH = os.environ["INFRA"], os.environ["BRANCH"]
def chart(ref):
    r = subprocess.run(["git", "-C", INFRA, "show", f"{ref}:{APP}"], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    spec = (yaml.safe_load(r.stdout) or {}).get("spec") or {}
    revs = [str(s.get("targetRevision")) for s in spec.get("sources") or [spec.get("source") or {}]
            if s.get("chart") == "istiod"]
    if len(revs) != 1:
        print(f"REFUSED: {APP} at {ref} holds {len(revs)} istiod charts, not one")
        sys.exit(1)
    return revs[0]
# what the unit changes, as copy-unit.sh reads every change (main...branch): its merge base against its tip - a branch cut
# before main moved Istio still reads the old version at its tip, a move it never made (a downgrade planned)
if not subprocess.run(["git", "-C", INFRA, "diff", "--name-only", f"main...{BRANCH}", "--", APP], capture_output=True,
                      text=True, check=True).stdout.split():
    sys.exit(0)
base = subprocess.run(["git", "-C", INFRA, "merge-base", "main", BRANCH], capture_output=True, text=True,
                      check=True).stdout.strip()
old, new = chart(base), chart(BRANCH)
if new != old:
    if new is None or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", new, re.ASCII):
        print(f"REFUSED: istiod's chart on the branch is no X.Y.Z version ({new!r})")
        sys.exit(1)
    print(new)
PY
  ) || { echo "$istio_to"; exit 1; }
fi
if [ -n "$istio_to" ]; then
  for f in deploy/ansible/playbooks/setup-istio.yml deploy/ansible/playbooks/setup-kubeadm.yml; do
    v=$({ git -C "$ops_repo" show "$ops_ref:$f" 2> /dev/null || true; } | "$py" -c 'import sys, yaml
d = yaml.safe_load(sys.stdin) or []
print(((d[0].get("vars") or {}) if isinstance(d, list) and d and isinstance(d[0], dict) else {}).get("istio_version", ""))')
    if [ -n "$v" ] && [ "$v" != "$istio_to" ]; then
      echo "REFUSED: $branch moves istiod's chart to $istio_to, ops' istio_version in $f is $v (defaults-follow-production: its copy build and pre-pulled images would be another Istio)"
      exit 1
    fi
  done
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
  ops_steps=$(OPS="$ops_repo" BRANCH="$branch" OUT="$out" ISTIO_TO="$istio_to" "$py" - <<'PY'
import os, subprocess, sys
import yaml
OPS, BRANCH, OUT = os.environ["OPS"], os.environ["BRANCH"], os.environ["OUT"]
def show(ref, path):
    r = subprocess.run(["git", "-C", OPS, "show", f"{ref}:{path}"], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None
changed = subprocess.run(["git", "-C", OPS, "diff", "--name-only", f"main...{BRANCH}"], capture_output=True, text=True,
                         check=True).stdout.split()
BASE = subprocess.run(["git", "-C", OPS, "merge-base", "main", BRANCH], capture_output=True, text=True,
                      check=True).stdout.strip()
def istio_moves(path):
    """the unit moves ops' istio_version in path: its merge base against its tip (a branch cut before main moved it
    reads the old one, a move it never made)"""
    return play_vars(show(BASE, path) or "").get("istio_version") != play_vars(show(BRANCH, path) or "").get("istio_version")
# the values ops restates from production's Argo charts (defaults-follow-production): they move with the infra unit
FOLLOW = {"cert_manager_version", "external_secrets_chart_version", "metrics_server_chart_version", "istio_version",
          "argocd_chart_version", "local_path_provisioner_version", "gateway_api_version", "gateway_api_sha256",
          "cnpg_chart_version", "strimzi_chart_version", "scylla_operator_chart_version", "scylla_manager_chart_version"}
# the packages kubeadm's upgrade brings along with Kubernetes (upgrade-kubeadm.yml's minor_packages): no step of their own
KUBEADM_PACKAGES = {"k8s_version", "k8s_cni_version", "k8s_cri_tools_version"}
def play_vars(text):
    doc = yaml.safe_load(text) or []
    return (doc[0].get("vars") or {}) if isinstance(doc, list) and doc and isinstance(doc[0], dict) else {}
def without_vars(text):
    """the playbook as parsed, its first play's vars left out - what else it changes is a task"""
    doc = yaml.safe_load(text or "") or []
    if isinstance(doc, list) and doc and isinstance(doc[0], dict):
        doc[0] = {k: v for k, v in doc[0].items() if k != "vars"}
    return doc
steps, refused, smokes = [], [], []
import re
VERSION = re.compile(r"[0-9][0-9A-Za-z.+~-]*", re.ASCII)  # a value that reaches a command line: a version, nothing else
def version(v):
    v = str(v)
    if not VERSION.fullmatch(v):
        raise SystemExit(f"REFUSED: the unit's value {v!r} is no version")
    return v
# what a vars file handed to Ansible may change: versions and hashes, under plain keys - never a template (Ansible renders
# a value where it is used: "{{ lookup('pipe', ...) }}" runs on this workstation) nor a connection setting (ansible_*:
# an ssh ProxyCommand runs here too)
PIN = re.compile(r"v?[0-9][0-9A-Za-z.+~-]*|[0-9a-f]{64}", re.ASCII)
KEY = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*", re.ASCII)
def pins(old, new, where):
    bad = []
    def walk(o, n, path):
        if o == n:
            return
        if isinstance(n, dict):
            o = o if isinstance(o, dict) else {}
            for k, v in n.items():
                if not KEY.fullmatch(str(k)) or (not path and str(k).startswith("ansible_")):
                    bad.append(f"{where} {path}{str(k)[:60]!r} (no plain key)")
                else:
                    walk(o.get(k), v, f"{path}{k}.")
        elif isinstance(n, list):
            o = o if isinstance(o, list) else []
            for i, v in enumerate(n):
                walk(o[i] if i < len(o) else None, v, f"{path}{i}.")
        elif n is not None and not isinstance(n, bool) and not PIN.fullmatch(str(n)):
            bad.append(f"{where} {path.rstrip('.')} {str(n)[:60]!r} (no version or hash)")
    walk(old, new, "")
    return bad
def load(text, where):
    try:
        return yaml.safe_load(text or "") or {}
    except yaml.YAMLError as e:  # a tag safe_load does not know (!vault, !unsafe) among them
        raise SystemExit(f"REFUSED: {where} on the branch not read as plain YAML ({str(e).splitlines()[0]})")
def vars_file(values, name):
    """the branch's moved values, written where test:copy:playbook reads them (-e @<file>)"""
    dest = os.path.join(OUT, name)
    with open(dest, "w") as f:
        yaml.safe_dump(values, f, default_flow_style=False)
    return dest
VARS_FILES = {  # a vars file -> its playbook and the arguments production's task passes (the Vagrant ones beside)
    "deploy/ansible/vars/patroni.yml": ("upgrade-patroni.yml", ""),
    "deploy/ansible/vars/vault.yml": ("upgrade-vault.yml", "-e @vars/vault-vagrant.yml"),
    "deploy/ansible/vars/forgejo.yml": ("upgrade-forgejo.yml", ""),
    "deploy/ansible/vars/keycloak.yml": ("upgrade-keycloak.yml", ""),
}
# Consul before Vault: Consul is Vault's storage (and Patroni's DCS)
ORDER = {"upgrade-kubeadm.yml": 0, "setup-kubeadm.yml": 1, "setup-argocd.yml": 2, "upgrade-patroni.yml": 3,
         "upgrade-consul.yml": 4, "upgrade-vault.yml": 5, "upgrade-forgejo.yml": 6, "setup-host-hardening.yml": 7,
         "setup-caddy.yml": 8, "upgrade-keycloak.yml": 9}
# node_exporter on ten: its version and the hash that moves with it - production's setup-host-hardening.yml on the copy
NODE_EXPORTER = {"node_exporter_version", "node_exporter_sha256"}
# Argo CD itself (no Argo app holds it): its chart default and the image pinned on a chart - setup-argocd.yml on the copy
# with the copy's Vault values (as test:copy:build installs it), its pods restarting
ARGOCD = {"argocd_chart_default", "argocd_image_pins"}
# Caddy on the Pis: its version - production's setup-caddy.yml on the copy's Pis, which installs the version pinned
# (and its Verify play checks that version running)
CADDY = {"caddy_version"}
# Consul's three servers: its version and the zips' hashes that move with it - production's upgrade-consul.yml on the
# copy (setup-consul.yml installs only where Consul is not: a running one moves through the upgrade's rolling order)
CONSUL = {"consul_version", "consul_checksums"}
for path in changed:
    if path == "scripts/upgrade-renovate.sh":
        # Renovate's own image (the copy runs no Renovate): the new image smoke-run here - it starts and its config
        # validator reads both presets (task test:copy:renovate-image) - one renovate/renovate:x.y.z@sha256 pin, else
        # refused (the wave-patches review, 2026-11-23: it rode a wave unproven)
        image = re.findall(r"(?m)^image=(\S+)$", show(BRANCH, path) or "")
        if len(image) == 1 and re.fullmatch(r"renovate/renovate:\d+\.\d+\.\d+@sha256:[0-9a-f]{64}", image[0]):
            smokes.append(f"test:copy:renovate-image IMAGE={image[0]}")
        else:
            refused.append(f"{path} (its image not one renovate/renovate:x.y.z@sha256 pin)")
        continue
    if not path.startswith("deploy/ansible/"):
        # no proof here: refused, never skipped - the Renovate image rode a wave unproven that way (its review,
        # 2026-11-23); anything else Renovate moves outside deploy/ansible needs a proof of its own first
        refused.append(f"{path} (outside deploy/ansible: no proof on the copy)")
        continue
    if path == "deploy/ansible/playbooks/setup-kubeadm.yml":
        old, new = play_vars(show("main", path) or ""), play_vars(show(BRANCH, path) or "")
        if without_vars(show("main", path)) != without_vars(show(BRANCH, path)):
            refused.append(f"{path} (its tasks)")  # main's tasks are what the copy runs: a changed task is unproven
        # every value it changes is handed to Ansible somewhere (a FOLLOW value by no-downgrade's loop, run on each
        # tag): a version or a hash, whether or not this proof runs it
        refused += pins(old, new, path)
        for k in sorted(set(old) | set(new)):
            if old.get(k) == new.get(k):
                continue
            if k == "k8s_package_version":
                steps.append(("upgrade-kubeadm.yml", f"-e k8s_upgrade_to={version(new[k]).split('-')[0]}", True))
            elif k == "cilium_version":
                steps.append(("setup-kubeadm.yml", f"--tags cilium -e cilium_version={version(new[k])}", False))
            elif k == "istio_version" and not os.environ["ISTIO_TO"] and istio_moves(path):
                refused.append(f"{path} istio_version (istiod's chart does not move with it)")
            elif k in FOLLOW or k in KUBEADM_PACKAGES:
                continue  # production's Argo charts, or the packages kubeadm's upgrade brings along
            else:
                refused.append(f"{path} {k}")
    elif path == "deploy/ansible/playbooks/setup-argocd.yml":
        old, new = play_vars(show("main", path) or ""), play_vars(show(BRANCH, path) or "")
        moved = sorted(k for k in set(old) | set(new) if old.get(k) != new.get(k))
        if without_vars(show("main", path)) != without_vars(show(BRANCH, path)):
            refused.append(f"{path} (its tasks)")  # main's tasks are what the copy runs: a changed task is unproven
        elif not moved or set(moved) - ARGOCD:
            refused.append(f"{path} {' '.join(sorted(set(moved) - ARGOCD)) or '(its tasks)'}")
        else:
            version(new["argocd_chart_default"])
            moved_values = {k: new[k] for k in moved if k in new}
            refused += pins({k: old.get(k) for k in moved}, moved_values, path)
            dest = vars_file(moved_values, "setup-argocd-vars.yml")
            steps.append(("setup-argocd.yml", f"-e @{dest} -e @vars/vault-vagrant.yml", True))
    elif path == "deploy/ansible/playbooks/setup-host-hardening.yml":
        old, new = play_vars(show("main", path) or ""), play_vars(show(BRANCH, path) or "")
        moved = sorted(k for k in set(old) | set(new) if old.get(k) != new.get(k))
        if without_vars(show("main", path)) != without_vars(show(BRANCH, path)):
            refused.append(f"{path} (its tasks)")
        elif not moved or set(moved) - NODE_EXPORTER:
            refused.append(f"{path} {' '.join(sorted(set(moved) - NODE_EXPORTER)) or '(its tasks)'}")
        else:
            version(new["node_exporter_version"])
            moved_values = {k: new[k] for k in moved if k in new}
            refused += pins({k: old.get(k) for k in moved}, moved_values, path)
            steps.append(("setup-host-hardening.yml", f"-e @{vars_file(moved_values, 'setup-host-hardening-vars.yml')}", False))
    elif path == "deploy/ansible/playbooks/setup-consul.yml":
        old, new = play_vars(show("main", path) or ""), play_vars(show(BRANCH, path) or "")
        moved = sorted(k for k in set(old) | set(new) if old.get(k) != new.get(k))
        if without_vars(show("main", path)) != without_vars(show(BRANCH, path)):
            refused.append(f"{path} (its tasks)")
        elif not moved or set(moved) - CONSUL:
            refused.append(f"{path} {' '.join(sorted(set(moved) - CONSUL)) or '(its tasks)'}")
        else:
            version(new["consul_version"])
            moved_values = {k: new[k] for k in CONSUL if k in new}
            refused += pins({k: old.get(k) for k in moved}, {k: new[k] for k in moved if k in new}, path)
            steps.append(("upgrade-consul.yml", f"-e @{vars_file(moved_values, 'upgrade-consul-vars.yml')}", False))
    elif path == "deploy/ansible/playbooks/setup-caddy.yml":
        old, new = play_vars(show("main", path) or ""), play_vars(show(BRANCH, path) or "")
        moved = sorted(k for k in set(old) | set(new) if old.get(k) != new.get(k))
        if without_vars(show("main", path)) != without_vars(show(BRANCH, path)):
            refused.append(f"{path} (its tasks)")
        elif not moved or set(moved) - CADDY:
            refused.append(f"{path} {' '.join(sorted(set(moved) - CADDY)) or '(its tasks)'}")
        else:
            version(new["caddy_version"])
            moved_values = {k: new[k] for k in moved if k in new}
            refused += pins({k: old.get(k) for k in moved}, moved_values, path)
            steps.append(("setup-caddy.yml", f"-e @{vars_file(moved_values, 'setup-caddy-vars.yml')}", False))
    elif path == "deploy/ansible/playbooks/setup-istio.yml":
        # Istio's version restated from production's istiod chart (defaults-follow-production): it moves with the infra
        # unit, proven by Argo on the copy - no step of its own; anything else in it is unproven
        old, new = play_vars(show("main", path) or ""), play_vars(show(BRANCH, path) or "")
        moved = sorted(k for k in set(old) | set(new) if old.get(k) != new.get(k))
        if without_vars(show("main", path)) != without_vars(show(BRANCH, path)):
            refused.append(f"{path} (its tasks)")
        elif set(moved) - FOLLOW:
            refused.append(f"{path} {' '.join(sorted(set(moved) - FOLLOW))}")
        elif "istio_version" in moved and not os.environ["ISTIO_TO"] and istio_moves(path):
            refused.append(f"{path} istio_version (istiod's chart does not move with it)")
        else:
            refused += pins(old, new, path)
    elif path in VARS_FILES:
        text = show(BRANCH, path)
        if text is None:
            refused.append(f"{path} (gone on the branch)")
            continue
        refused += pins(load(show("main", path), path), load(text, path), path)
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
for line in smokes:
    print(line)
PY
) || { echo "$ops_steps"; exit 1; }
  while IFS= read -r line; do [ -n "$line" ] && steps+=("$line"); done <<< "$ops_steps"
fi
# the sidecars brought to istiod's new version: after Argo applied the chart (test:copy:change) and any ops part
[ -z "$istio_to" ] || steps+=("test:copy:playbook PLAYBOOK=restart-mesh-workloads.yml ARGS='-e istio_version=$istio_to'")

if [ "${#steps[@]}" -eq 0 ]; then
  echo "REFUSED: $branch changes nothing a proof runs - nothing to prove"
  exit 1
fi
for s in "${steps[@]}"; do echo "$s"; done
[ "$mode" = run ] || exit 0
# the branch's build hashes, each what its vendor signs, checked against main's keys before anything is proven (a
# Renovate post-upgrade task that failed left the old pins: refused here, by name)
if [ "$ops_ref" != main ]; then
  echo "=== UNIT $unit: its build hashes"
  ${COPY_UNIT_PINS:-python3 -I $ops/scripts/renovate-checksums.py} --check --changed --base main --ref "$branch" \
    --root "$ops_repo" --keys "$ops/renovate/keys" || { echo "REFUSED: $branch's build hashes - not proven"; exit 1; }
fi
for s in "${steps[@]}"; do
  echo "=== UNIT $unit: task $s"
  eval "task $s"
done
echo "=== UNIT $unit PROVEN"
