#!/bin/bash
# setup-ci-bot.yml - Woodpecker CI's own Forgejo account - run for real by ansible-playbook against a fake Forgejo
# (its API as 15.x answers: users, teams, repositories as a caller sees them, scoped tokens; fakeforgejo.py) and a fake
# Vault (KV v2 with versions and check-and-set; fakevault.py), the real community.hashi_vault modules writing to it:
#   - the bot is no admin (one made admin by hand is made a user again), its two teams scoped exactly (code write on
#     infra alone + packages write; code read on what pipelines clone; nothing else, no repository made), holding the
#     bot alone - a team of that name with anyone else in it, or the bot in a team of anyone's, refused untouched;
#   - three tokens on the bot (minted as the bot), each its scope alone, proven, written to Vault with every other
#     property kept (read, merged, written with the version read); a rerun keeps the account and teams, mints anew and
#     keeps the ones Vault held, deleting older; a failure after a mint deletes the new ones, Vault unchanged; a sealed
#     Vault refuses before any mint; no preview;
#   - --tags retire deletes the admin's tokens .env names as CI's, only once Vault hands CI none of them;
#   - no secret on any command line over every run: every process's /proc/<pid>/cmdline read all the while
#     (argvwatch.py - a canary shows it bites), curl, forgejo, vault, ssh, kubectl fenced;
#   - seed-vault-secrets.yml's own woodpecker-ci tasks: Vault's CI bot properties kept over .env's old admin tokens,
#     a first install takes them from .env (the Vagrant copy's placeholders), a sealed Vault refuses.
# Needs hvac (the hashi_vault modules): the CI image has it; where it is missing this says SKIPPED.
set -u
H=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$H/../../../.." && pwd)
AP=$(command -v ansible-playbook 2>/dev/null \
  || { [ -x "$ROOT/deploy/ansible/venv/bin/ansible-playbook" ] && echo "$ROOT/deploy/ansible/venv/bin/ansible-playbook"; })
[ -x "${AP:-}" ] || { echo "ci-bot: no ansible-playbook found (PATH, repo venv)"; exit 2; }
PY="$(dirname "$AP")/python3"; [ -x "$PY" ] || PY=python3
if ! "$PY" -c 'import hvac' 2> /dev/null; then
  echo "ci-bot: SKIPPED here: no hvac beside $AP - the CI image runs it"
  exit 0
fi
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cd "$ROOT" || exit 1
PYTHONDONTWRITEBYTECODE=1 timeout 900 "$PY" -B "$H/drive.py" "$AP" "$W"
