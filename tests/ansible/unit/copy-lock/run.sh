#!/bin/bash
# scripts/copy-lock.sh: one copy run at a time - a lock held by a live owner (pid and start time) refuses another, named;
# the same owner (a nested task of one run) takes it again; a dead owner, or a pid reused by another process (its start
# time not the one recorded), is no owner; the outermost go-task ancestor is the owner. Every copy task takes it first.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
sleep 300 & a=$!
sleep 300 & b=$!
trap 'kill $a $b 2> /dev/null; rm -rf "$W"' EXIT
export COPY_LOCK_FILE=$W/lock
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi
}
take() { out=$(COPY_LOCK_OWNER=$1 bash scripts/copy-lock.sh 2>&1); }
take "$a"; rc=$?
check "a free copy: taken" "$rc $(cut -d' ' -f1 "$W/lock")" "0 $a"
take "$a"; rc=$?
check "  the same owner again (a nested task of its run): taken" "$rc" 0
take "$b"; rc=$?
check "another live owner: refused, named" "$rc $(grep -c "REFUSED: another copy run holds the Vagrant copy .*(pid $a)" <<< "$out")" "1 1"
read -r p s < "$W/lock"; echo "$p $((s + 1))" > "$W/lock"
take "$b"; rc=$?
check "the holder's pid with another start time (a reused pid): no owner - taken" "$rc $(cut -d' ' -f1 "$W/lock")" "0 $b"
kill "$b"; wait "$b" 2> /dev/null
take "$a"; rc=$?
check "the holder gone: taken" "$rc $(cut -d' ' -f1 "$W/lock")" "0 $a"
# the owner found: the outermost process named task above it (a nested task:'s own process is inside it)
mkdir -p "$W/bin"; ln -s "$(command -v bash)" "$W/bin/task"
o=$("$W/bin/task" -c "\"$W/bin/task\" -c 'COPY_LOCK_FILE=$W/lock2 bash scripts/copy-lock.sh > /dev/null; cut -d\" \" -f1 $W/lock2; echo \$PPID'; echo \$\$")
check "the owner: the outermost task process above it" "$(sed -n 1p <<< "$o")" "$(sed -n 3p <<< "$o")"
# every copy task takes it first
check "every copy task takes the lock first" "$(python3 -c '
import yaml
T = yaml.safe_load(open("Taskfile.yml"))["tasks"]
print(all(str((T[t]["cmds"][0] if isinstance(T[t]["cmds"][0], str) else T[t]["cmds"][0].get("cmd"))) == "scripts/copy-lock.sh"
          for t in ("test:copy:build", "test:copy:argo", "test:copy:change", "test:copy:playbook", "test:copy:check")))')" True
echo "copy-lock: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
