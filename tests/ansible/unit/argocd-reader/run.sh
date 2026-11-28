#!/bin/bash
# setup-argocd-reader.yml - Argo CD's own Forgejo account - run for real by ansible-playbook against the ci-bot
# harness's fake Forgejo and fake Vault (the real community.hashi_vault modules writing to it), ten's kubectl a stub,
# production's inventory shape (target an ungrouped host, two Pis), an infra checkout of fixtures:
#   - the repositories Argo CD reads derived from infra's manifests (scripts/argocd-repos.py): what Applications and
#     ApplicationSets clone, what a pull-request generator lists; another org's on the host, an unresolved one refused;
#   - the reader no admin, its teams scoped exactly (code read on what is cloned, code and pull requests read on what the PR
#     generator lists), holding it alone, read back as the reader (pushes nothing); a kill switch never undone;
#   - its read:repository token proven, written to Vault argocd/forgejo-readonly (token, username, what ten held for
#     retire) with every other property kept, with the version read; a failure deletes it again unless the Vault write
#     itself failed or Vault holds it; older tokens deleted only when Vault and ten do not hold them and over 3 h old;
#   - --tags retire deletes the admin's Argo CD tokens only once ten (read only) hands Argo CD the reader with Vault's
#     token, and none it would delete Vault or ten still hold;
#   - curl, forgejo, vault, ssh, kubectl, argocd fenced (a secret on a command line: secrets-off-argv's, read statically);
#   - seed-vault-secrets.yml's own argocd/forgejo-readonly tasks: Vault's kept over .env's old admin token.
# Needs hvac (the hashi_vault modules): the CI image has it; where it is missing this says SKIPPED.
set -u
H=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$H/../../../.." && pwd)
AP=$(command -v ansible-playbook 2>/dev/null \
  || { [ -x "$ROOT/deploy/ansible/venv/bin/ansible-playbook" ] && echo "$ROOT/deploy/ansible/venv/bin/ansible-playbook"; })
[ -x "${AP:-}" ] || { echo "argocd-reader: no ansible-playbook found (PATH, repo venv)"; exit 2; }
PY="$(dirname "$AP")/python3"; [ -x "$PY" ] || PY=python3
if ! "$PY" -c 'import hvac' 2> /dev/null; then
  echo "argocd-reader: SKIPPED here: no hvac beside $AP - the CI image runs it"
  exit 0
fi
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cd "$ROOT" || exit 1
# The bound is for a hang, never for the work: ~70 playbook runs take 400 s alone on 4 CPUs (the CI image, 2026-11-24),
# ~15 min beside three other harnesses in CI's suite, and past 20 when ten runs two builds at once (each ~30% slower) -
# 1200 s killed it on two Renovate pull requests that evening, silently, after its last PASS line.
LIMIT=2700
PYTHONDONTWRITEBYTECODE=1 timeout "$LIMIT" "$PY" -B "$H/drive.py" "$AP" "$W"
rc=$?
[ "$rc" -ne 124 ] || echo "argocd-reader: TIMED OUT after $LIMIT s - a hang, or the cases outgrew the bound"
exit "$rc"
