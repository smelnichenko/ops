#!/bin/bash
# scripts/copy-host-guard.sh and the Vagrantfile's hook - the radar station on the workstation never starved by the VMs:
#   - vagrant up/reload/resume refused below the memory of the VMs it starts (the Vagrantfile's v.memory as written;
#     not those running already; only those named) plus the reserve, the numbers named; at exactly that, started and
#     watched. Every other command: nothing. Vagrant's own options skipped; a name that is no machine counts them all;
#     libvirt not answering, or a Vagrantfile with no size, refuses;
#   - the watcher: one at a time; available memory under the trip level on two polls running powers off the biggest
#     running VM (one low poll does not); the trip recorded, printed once by the next vagrant up; it ends three polls
#     after its VMs stopped, or after the grace when none started; libvirt not answering: still watching;
#   - the Vagrantfile's hook, loaded by ruby with Vagrant's DSL stubbed: vagrant's arguments passed whole, a refusal
#     (or a guard that cannot run) aborts the command, once per process.
# Against a virsh stub (first on PATH: the runner's fence catches a real one) whose `list` also sets the host's
# available memory for that poll from a queue - so "one low poll" and "two" are exact, not timed.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
REPO=$PWD
W=$(mktemp -d)
cleanup() {
  local f
  for f in "$W"/*/host-guard.pid; do [ -f "$f" ] && kill "$(cat "$f")" 2> /dev/null; done
  rm -rf "$W"
}
trap cleanup EXIT
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi
}
mkdir -p "$W/bin" "$W/ops"
cp Vagrantfile "$W/ops/Vagrantfile"   # its directory names the domains: ops_<machine>, as vagrant-libvirt does
cat > "$W/bin/virsh" <<'STUB_VIRSH'
#!/bin/bash
# virsh -c qemu:///system list --name | destroy <domain>
echo "$*" >> "$STUB/calls"
case "$*" in
  *" list --name")
    [ -e "$STUB/fail" ] && { echo "error: failed to connect to the hypervisor" >&2; exit 1; }
    if [ -s "$STUB/memq" ]; then
      echo "MemAvailable:   $(( $(head -1 "$STUB/memq") * 1024 )) kB" > "$STUB/meminfo"
      sed -i 1d "$STUB/memq"
    fi
    cat "$STUB/active" ;;
  *" destroy "*) d=${!#}; grep -vxF "$d" "$STUB/active" > "$STUB/active.n"; mv "$STUB/active.n" "$STUB/active" ;;
  *) echo "virsh stub: $*" >&2; exit 9 ;;
esac
STUB_VIRSH
chmod +x "$W/bin/virsh"
export PATH="$W/bin:$PATH" COPY_VAGRANTFILE="$W/ops/Vagrantfile" COPY_HOST_POLL=0.05 COPY_HOST_GRACE=600

n=0
fresh() {  # fresh <available MB> <active domains...>: a host of its own (stub state, .copy dir)
  n=$((n + 1))
  export STUB="$W/s$n" COPY_HOST_DIR="$W/d$n"
  mkdir -p "$STUB" "$COPY_HOST_DIR"
  export COPY_HOST_MEMINFO="$STUB/meminfo"
  echo "MemAvailable:   $(($1 * 1024)) kB" > "$STUB/meminfo"
  shift
  printf '%s\n' "$@" | sed '/^$/d' > "$STUB/active"
  : > "$STUB/memq"
}
guard() { out=$(bash scripts/copy-host-guard.sh "$@" 2>&1); }
watcher() { cat "$COPY_HOST_DIR/host-guard.pid" 2> /dev/null; }
pid_on() {  # alive, and no zombie (one reparented to a reaper that has not reaped it yet is gone); /proc - CI has no ps
  local st
  read -r st 2> /dev/null < "/proc/$1/stat" || return 1
  st=${st##*) }
  [ "${st%% *}" != Z ]
}
pid_off() { ! pid_on "$1"; }
alive() { local p; p=$(watcher); [ -n "$p" ] && pid_on "$p" && echo yes || echo no; }
stop_watcher() { local p; p=$(watcher); [ -n "$p" ] && kill "$p" 2> /dev/null; rm -f "$COPY_HOST_DIR/host-guard.pid"; }
polls() { grep -c ' list --name$' "$STUB/calls" 2> /dev/null || echo 0; }
polls_ge() { [ "$(polls)" -ge "$1" ]; }                                           # read anew on every wait's try
destroys_ge() { [ "$(grep -c destroy "$STUB/calls" 2> /dev/null || echo 0)" -ge "$1" ]; }
wait_for() {  # wait_for <seconds> <command...>: until it succeeds; 1 when the time ran out (never spins on)
  local end=$((SECONDS + $1)); shift
  until "$@"; do [ $SECONDS -lt $end ] || return 1; sleep 0.05; done
}

# --- vagrant up: the room it needs ---------------------------------------------------------------------------------
ALL=$((2048 + 2048 + 18432))
fresh $((ALL + 3072 - 1))
guard vagrant up; rc=$?
check "up, nothing running: the Vagrantfile's three VMs (pi1, pi2 2048 MB, kubeadm 18432 MB) + 3 GB - 1 MB short: refused, named" \
  "$rc $(grep -c "REFUSED vagrant up: the host has $((ALL + 3071)) MB available; the VMs it starts (pi1 2048 MB, pi2 2048 MB, kubeadm 18432 MB) need $ALL MB and 3072 MB stay" <<< "$out") $(alive)" "1 1 no"
fresh $((ALL + 3072))
guard vagrant up; rc=$?
check "  exactly that: started, and the watcher with it" "$rc $(alive)" "0 yes"
stop_watcher
fresh $((4096 + 3072 - 1)) ops_kubeadm
guard vagrant up; rc=$?
check "up with kubeadm running: only the Pis' memory needed - 1 MB short refused" "$rc $(grep -c 'need 4096 MB' <<< "$out")" "1 1"
fresh $((4096 + 3072)) ops_kubeadm
guard vagrant up; rc=$?
check "  exactly that: started" "$rc" 0
stop_watcher
fresh 5119
guard vagrant up --no-provision pi1; rc=$?
check "up pi1 --no-provision: the named VM only (2048 MB), the option skipped - 1 MB short refused" "$rc $(grep -c '(pi1 2048 MB) need 2048 MB' <<< "$out")" "1 1"
fresh 5120
guard vagrant --debug up pi1; rc=$?
check "--debug up pi1 (vagrant's own option first): judged as up pi1 - its 2048 MB + 3072, started and watched" \
  "$rc $(grep -c '2048 MB for the VMs vagrant up starts (pi1 2048 MB)' <<< "$out") $(alive)" "0 1 yes"
stop_watcher
fresh 5119
guard vagrant --debug up pi1; rc=$?
check "  1 MB short: refused" "$rc" 1
stop_watcher
fresh 5120
guard vagrant up '/pi.*/'; rc=$?
check "a name that is no machine (a regex): all of them counted - refused" "$rc $(grep -c "need $ALL MB" <<< "$out")" "1 1"
for cmd in reload resume; do
  fresh 100
  guard vagrant "$cmd"; rc=$?
  check "$cmd is guarded as up" "$rc $(grep -c "REFUSED vagrant $cmd" <<< "$out")" "1 1"
done
fresh 100
calls=0
for c in "status" "halt" "destroy -f" "ssh kubeadm" "provision" ""; do
  # shellcheck disable=SC2086
  guard vagrant $c; rc=$?
  [ "$rc $out $(alive)" = "0  no" ] && calls=$((calls + 1))
done
check "status, halt, destroy, ssh, provision, nothing: passed through silently, no watcher, libvirt not asked" \
  "$calls $(polls)" "6 0"
fresh 99999
touch "$STUB/fail"
guard vagrant up; rc=$?
check "libvirt not answering: refused, said (never read as nothing running)" \
  "$rc $(grep -c "REFUSED vagrant up: libvirt's domains could not be listed" <<< "$out") $(alive)" "1 1 no"
fresh 99999
printf 'config.vm.define "a" do |a|\n  # v.memory = 99999\n  v.memory = 1024\nend\nconfig.vm.define "b" do |b|\nend\n' > "$W/odd.rb"
COPY_VAGRANTFILE="$W/odd.rb" guard vagrant up; rc=$?
check "a commented v.memory not read; a machine with no size not counted" "$rc $(grep -c '(a 1024 MB) + 3072 MB kept' <<< "$out")" "0 1"
stop_watcher
printf 'config.vm.box = "x"\n' > "$W/none.rb"
COPY_VAGRANTFILE="$W/none.rb" guard vagrant up; rc=$?
check "a Vagrantfile with no v.memory: refused (it cannot be sized)" "$rc $(grep -c 'REFUSED: no VM with a v.memory' <<< "$out")" "1 1"

# --- the watcher --------------------------------------------------------------------------------------------------
fresh 9000 ops_pi1 ops_pi2 ops_kubeadm
guard watch; first=$(watcher)
guard watch; rc=$?
check "watch twice: one watcher, the second says so" "$rc $(grep -c "watches already (pid $first)" <<< "$out") $(watcher)" "0 1 $first"
# low, high, low, high...: never two low polls running - no power-off
printf '%s\n' 1000 9000 1000 9000 1000 9000 > "$STUB/memq"
wait_for 10 test ! -s "$STUB/memq"; wait_for 10 polls_ge 8
check "available memory low on single polls, never two running: nothing powered off" \
  "$(grep -c destroy "$STUB/calls") $(cat "$STUB/active" | tr '\n' ' ')" "0 ops_pi1 ops_pi2 ops_kubeadm "
# two low polls running: the biggest running VM off, once; then enough again
printf '%s\n' 2047 2047 9000 > "$STUB/memq"
wait_for 10 test ! -s "$STUB/memq"
wait_for 10 destroys_ge 1
check "under 2048 MB on two polls running: the biggest running VM (kubeadm) powered off, the Pis left" \
  "$(grep destroy "$STUB/calls" | tr '\n' ' ')/$(cat "$STUB/active" | tr '\n' ' ')" "-c qemu:///system destroy ops_kubeadm /ops_pi1 ops_pi2 "
check "  recorded: the log and the trip, the numbers and the VM named" \
  "$(grep -c '2047 MB available, under 2048 MB on two polls .*: ops_kubeadm powered off' "$COPY_HOST_DIR/host-guard.log") $(grep -c 'ops_kubeadm powered off' "$COPY_HOST_DIR/host-guard-tripped")" "1 1"
# still short with kubeadm gone: the next biggest goes too (pi1 and pi2 tie: the first)
printf '%s\n' 100 100 9000 > "$STUB/memq"
wait_for 10 destroys_ge 2
check "  still short after it: the next running VM off too" "$(grep destroy "$STUB/calls" | tail -1 | grep -c 'destroy ops_pi1') $(grep -c destroy "$STUB/calls")" "1 2"
stop_watcher
# the next vagrant up prints the trip once
fresh 99999
echo "2026-11-13 22:17:00 the host had 100 MB available ...: ops_kubeadm powered off" > "$COPY_HOST_DIR/host-guard-tripped"
guard vagrant up; one=$out
stop_watcher
guard vagrant up; two=$out
stop_watcher
check "the last trip printed by the next vagrant up, once" \
  "$(grep -c "the host guard's last trip: .*ops_kubeadm powered off" <<< "$one") $(grep -c 'last trip' <<< "$two")" "1 0"
# the end: three polls after its VMs stopped
fresh 9000 ops_kubeadm
guard watch; p=$(watcher)
wait_for 10 polls_ge 2
: > "$STUB/active"
wait_for 10 pid_off "$p"; gone=$?
check "its VMs stopped: the watcher ends" "$gone" 0
# none started: on until the grace, then ends
fresh 9000
COPY_HOST_GRACE=5 guard watch; p=$(watcher)
wait_for 10 polls_ge 4
check "  none started yet: still watching within the grace (vagrant up's box import, a first boot)" "$(pid_on "$p" && echo on)" on
wait_for 10 pid_off "$p"; gone=$?
check "  none started by the grace's end: ends" "$gone" 0
# libvirt not answering: still watching (never read as "nothing runs, end")
fresh 9000 ops_kubeadm
guard watch; p=$(watcher)
wait_for 10 polls_ge 2
touch "$STUB/fail"
c=$(polls); wait_for 10 polls_ge $((c + 6))
check "libvirt not answering: still watching, said in the log" \
  "$(pid_on "$p" && echo on) $([ "$(grep -c "could not be listed (virsh) - still watching" "$COPY_HOST_DIR/host-guard.log")" -ge 3 ] && echo said)" "on said"
stop_watcher

# --- the Vagrantfile's hook ----------------------------------------------------------------------------------------
if ! command -v ruby > /dev/null; then
  check "ruby present (the CI image carries it): the Vagrantfile's hook is tested by loading it" "none" "ruby"
else
  H=$W/hook
  mkdir -p "$H/scripts"
  cp Vagrantfile "$H/Vagrantfile"
  printf '#!/bin/bash\nprintf "%%s|" "$@" >> "%s/args"; echo >> "%s/args"\nexit "${GUARD_RC:-0}"\n' "$H" "$H" > "$H/scripts/copy-host-guard.sh"
  chmod +x "$H/scripts/copy-host-guard.sh"
  load_twice() {  # the Vagrantfile loaded twice in one process (Vagrant may), Vagrant's DSL a no-op
    ruby -e 'module Vagrant; def self.configure(*); end; end
             ARGV.replace(["--debug", "up", "--no-provision", "pi1"])
             load ENV["VF"]; load ENV["VF"]
             puts "configured"' 2>&1
  }
  out=$(VF=$H/Vagrantfile load_twice); rc=$?
  check "hook: vagrant's arguments passed whole, once per process; allowed - the Vagrantfile goes on" \
    "$rc $(cat "$H/args" 2> /dev/null) $(grep -c configured <<< "$out")" "0 vagrant|--debug|up|--no-provision|pi1| 1"
  rm -f "$H/args"
  out=$(GUARD_RC=1 VF=$H/Vagrantfile load_twice); rc=$?
  check "  refused: the command aborted, said, nothing configured" \
    "$rc $(grep -c "vagrant --debug up --no-provision pi1: refused by $H/scripts/copy-host-guard.sh" <<< "$out") $(grep -c configured <<< "$out")" "1 1 0"
  rm -f "$H/scripts/copy-host-guard.sh"
  out=$(VF=$H/Vagrantfile load_twice); rc=$?
  check "  the guard missing (cannot run): aborted too" "$rc $(grep -c configured <<< "$out")" "1 0"
fi
cd "$REPO" || exit 1
echo "copy-host-guard: $([ "$fails" -eq 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ "$fails" -eq 0 ]
