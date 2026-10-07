#!/bin/bash
# The repo's .ansible-lint, as CI's lint step applies it, on two fixture playbooks: a module argument the module does
# not document (apt's download_only - the full run 2026-10-07 found it only at step 14) fails the lint; the same task
# without it passes. The args rule is experimental: enabled, it only warned (warn_list's default), and a warning passed.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
command -v ansible-lint > /dev/null || { echo "FAIL no ansible-lint here"; echo "lint-config: 1 FAILED"; exit 1; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/playbooks"
cp .ansible-lint "$W/"
book() {  # book <file> <extra apt line>
  printf -- '---\n- name: Fixture\n  hosts: localhost\n  gather_facts: false\n  tasks:\n    - name: The package\n      ansible.builtin.apt:\n        name: rclone\n%s' "$2" > "$W/playbooks/$1"
}
book bad.yml "        download_only: true"$'\n'
book good.yml ""
fails=0
lint() { (cd "$W" && ansible-lint -c .ansible-lint "playbooks/$1" > "$W/$1.out" 2>&1); echo $?; }
rc=$(lint bad.yml)
if [ "$rc" != 0 ] && grep -q '^args\[module\]' "$W/bad.yml.out"; then echo "PASS an undocumented argument fails the lint"
else echo "FAIL an undocumented argument: rc $rc"; tail -5 "$W/bad.yml.out"; fails=$((fails + 1)); fi
rc=$(lint good.yml)
if [ "$rc" = 0 ]; then echo "PASS the task without it passes"
else echo "FAIL the clean fixture: rc $rc"; tail -5 "$W/good.yml.out"; fails=$((fails + 1)); fi
echo "lint-config: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
