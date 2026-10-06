#!/bin/bash
# scripts/version-inventory.sh lists the binaries outside the packages that run instead of theirs - a runc in
# /usr/local/bin (the Vagrant copy ran nerdctl-full's 1.2.4 beside production's Debian runc) shows as its own line,
# which the inventory diff then refuses. kubectl, helm, dpkg-query and systemctl stubbed: the node part only.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/stubs" "$W/bin"
for t in kubectl helm; do
  printf '#!/bin/sh\ncase "$*" in *"-o json"*) echo '"'"'{"items": [], "serverVersion": {"gitVersion": "v0"}}'"'"';; "list -A -o json") echo "[]";; *) exit 1;; esac\n' > "$W/stubs/$t"
done
printf '#!/bin/sh\nexit 0\n' > "$W/stubs/dpkg-query"
printf '#!/bin/sh\necho /lib/systemd/system/containerd.service\n' > "$W/stubs/systemctl"
chmod +x "$W/stubs/"*
fails=0
check() {  # name, ok (0/1)
  if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}
inv() { PATH="$W/stubs:$PATH" INVENTORY_BIN_DIR="$W/bin" KUBECONFIG=/dev/null bash scripts/version-inventory.sh 2>&1; }
out=$(inv)
! grep -q "^binary " <<< "$out"; check "no binary outside the packages: no line" $?
printf '#!/bin/sh\necho "runc version 1.2.4"\necho "commit: v1.2.4-0-g6c52b3fc"\n' > "$W/bin/runc"
chmod +x "$W/bin/runc"
out=$(inv)
grep -qx "binary $W/bin/runc 1.2.4" <<< "$out"; check "a runc there: its line, with its version" $?
echo "version-inventory-binaries: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
