#!/bin/bash
# Ansible's virtualenv is no file of the repository's: none tracked under deploy/ansible/venv, and the ignore rule takes
# it as a directory (ops' own) and as a symlink (a clone's, pointing at ops' venv). `deploy/ansible/venv/` matched a
# directory alone: a clone's symlink was committed by a `git add -A deploy/ansible`, and ops' checkout of it replaced
# ops' venv (ignored, so git's to overwrite) with that symlink - the full run's build failed on it (2026-10-08 16:08)
set -u
cd "$(dirname "$0")/../../../.." || exit 1
fails=0
check() {
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi
}
check "nothing tracked under deploy/ansible/venv" "$(git ls-files -- deploy/ansible/venv | wc -l)" 0
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
seen() {  # seen <kind>: what git status lists in a repository of this .gitignore with the venv as that kind
  rm -rf "$W/r"; mkdir -p "$W/r/deploy/ansible"
  cp .gitignore "$W/r/"
  git -C "$W/r" init -q
  case $1 in
    directory) mkdir -p "$W/r/deploy/ansible/venv/bin"; : > "$W/r/deploy/ansible/venv/bin/python3" ;;
    symlink) ln -s /elsewhere/venv "$W/r/deploy/ansible/venv" ;;
  esac
  git -C "$W/r" status --porcelain --untracked-files=all | grep -c 'deploy/ansible/venv'
}
check "the venv ignored as a directory and as a symlink" "$(seen directory) $(seen symlink)" "0 0"
echo "venv-ignored: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
