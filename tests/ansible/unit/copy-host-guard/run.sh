#!/bin/bash
# scripts/copy-host-guard.sh and the Vagrantfile's hook - the radar station on the workstation never starved by the VMs:
#   - vagrant up/reload/resume refused below the memory of the VMs it starts (the Vagrantfile's v.memory as written;
#     only those named, an option's value no name) plus what the running VMs have not touched yet plus the reserve, the
#     numbers named; at exactly that, started and watched. Every other command: nothing. Vagrant's own options skipped;
#     a name that is no machine counts them all; libvirt not answering, a VM without a size, a setting that is no number
#     refuse;
#   - the watcher: one at a time (its lifetime lock); short of memory on two polls running - available under the trip
#     level, or the memory stall (PSI full) over its level - the biggest running VM powered off (one poll does not); a
#     failed power-off said as such; the trip recorded, printed once by the next vagrant up; it ends after a whole grace
#     with no VM - not when a caller relied on it meanwhile; libvirt not answering: still watching; its start and end
#     logged; none of the caller's environment in it;
#   - the Vagrantfile's hook, loaded by ruby with Vagrant's DSL stubbed: vagrant's arguments passed whole, once per
#     process; a start the guard refuses or cannot judge aborted, any other command goes on; one start at a time.
# Against a virsh stub (first on PATH: the runner's fence catches a real one) whose `list` also sets the host's
# available memory and memory stall for that poll from a queue, and a clock (COPY_HOST_UPTIME) the test sets - so
# "one low poll" and "two", and every grace, are exact, not timed. Not driven here: a caller registering in the very
# moment the watcher decides to end (the callers' lock serialises the two) - one interleaving no stub can stop at.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
REPO=$PWD
W=$(mktemp -d)
cleanup() {  # every watcher of this test stopped before its stub goes: by its directory, whatever its pidfile says
  local e
  for e in /proc/[0-9]*/environ; do
    { tr '\0' '\n' < "$e"; } 2> /dev/null | grep -q "^COPY_HOST_DIR=$W/" && grep -q '_loop' "${e%environ}cmdline" 2> /dev/null \
      && kill "$(basename "${e%/environ}")" 2> /dev/null
  done
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
# virsh -c qemu:///system list --name | dommemstat <domain> | destroy <domain>
# its state beside the guard's (COPY_HOST_DIR/stub): the watcher keeps no environment but its own settings
STUB=${STUB:-$COPY_HOST_DIR/stub}
echo "$*" >> "$STUB/calls"
case "$*" in
  *" list --name")
    [ -e "$STUB/fail" ] && { echo "error: failed to connect to the hypervisor" >&2; exit 1; }
    if [ -s "$STUB/memq" ]; then  # "<available MB> [<PSI full avg10>]"
      read -r m p < "$STUB/memq"
      echo "MemAvailable:   $((m * 1024)) kB" > "$STUB/meminfo"
      printf 'some avg10=0.00 avg60=0.00 avg300=0.00 total=0\nfull avg10=%s.00 avg60=0.00 avg300=0.00 total=0\n' "${p:-0}" > "$STUB/psi"
      sed -i 1d "$STUB/memq"
    fi
    cat "$STUB/active" ;;
  *" dommemstat "*) d=${!#}; [ -e "$STUB/rss.$d" ] && echo "rss $(cat "$STUB/rss.$d")" ;;
  *" destroy "*)
    [ -e "$STUB/destroy-fails" ] && exit 1
    d=${!#}; grep -vxF "$d" "$STUB/active" > "$STUB/active.n"; mv "$STUB/active.n" "$STUB/active" ;;
  *) echo "virsh stub: $*" >&2; exit 9 ;;
esac
STUB_VIRSH
chmod +x "$W/bin/virsh"
# the guard's virsh named by path, not found on PATH: a watcher outliving this test's stub fails, never reaches libvirt
export PATH="$W/bin:$PATH" COPY_HOST_VIRSH="$W/bin/virsh" COPY_VAGRANTFILE="$W/ops/Vagrantfile" COPY_HOST_POLL=0.05 COPY_HOST_GRACE=600

n=0
fresh() {  # fresh <available MB> <active domains...>: a host of its own (stub state, clock at 100 s, .copy dir)
  n=$((n + 1))
  export COPY_HOST_DIR="$W/d$n" STUB="$W/d$n/stub"
  mkdir -p "$STUB" "$COPY_HOST_DIR"
  export COPY_HOST_MEMINFO="$STUB/meminfo" COPY_HOST_PSI="$STUB/psi" COPY_HOST_UPTIME="$STUB/uptime"
  echo "MemAvailable:   $(($1 * 1024)) kB" > "$STUB/meminfo"
  printf 'some avg10=0.00 avg60=0.00 avg300=0.00 total=0\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n' > "$STUB/psi"
  echo "100.00 200.00" > "$STUB/uptime"
  shift
  printf '%s\n' "$@" | sed '/^$/d' > "$STUB/active"
  : > "$STUB/memq"
}
clock() { echo "$1.00 0.00" > "$STUB/uptime"; }
guard() { out=$(timeout 30 bash scripts/copy-host-guard.sh "$@" 2>&1); }  # a hang (a lock never let go) a failure, said
watcher() { cat "$COPY_HOST_DIR/host-guard.pid" 2> /dev/null; }
pid_on() {  # alive, and no zombie; /proc - CI has no ps
  local st
  read -r st 2> /dev/null < "/proc/$1/stat" || return 1
  st=${st##*) }
  [ "${st%% *}" != Z ]
}
pid_off() { ! pid_on "$1"; }
alive() { local p; p=$(watcher); [ -n "$p" ] && pid_on "$p" && echo yes || echo no; }
stop_watcher() { local p; p=$(watcher); [ -n "$p" ] && kill "$p" 2> /dev/null && wait_for 10 pid_off "$p"; rm -f "$COPY_HOST_DIR/host-guard.pid"; }
count() { local c; c=$(grep -c "$1" "$2" 2> /dev/null); echo "${c:-0}"; }  # 0 for a file not there yet
polls() { count ' list --name$' "$STUB/calls"; }
polls_ge() { [ "$(polls)" -ge "$1" ]; }                                           # read anew on every wait's try
destroys_ge() { [ "$(count destroy "$STUB/calls")" -ge "$1" ]; }
wait_for() {  # wait_for <seconds> <command...>: until it succeeds; 1 when the time ran out (never spins on)
  local end=$((SECONDS + $1)); shift
  until "$@"; do [ $SECONDS -lt $end ] || return 1; sleep 0.05; done
}

# --- vagrant up: the room it needs ---------------------------------------------------------------------------------
ALL=$((2048 + 2048 + 18432))
fresh $((ALL + 2560 - 1))
guard vagrant up; rc=$?
check "up, nothing running: the Vagrantfile's three VMs (pi1, pi2 2048 MB, kubeadm 18432 MB) + 2560 MB - 1 MB short: refused, named" \
  "$rc $(grep -c "REFUSED vagrant up: the host has $((ALL + 2559)) MB available; the VMs it starts (pi1 2048 MB, pi2 2048 MB, kubeadm 18432 MB) need $ALL MB, the running VMs may still take 0 MB, and 2560 MB stay" <<< "$out") $(alive)" "1 1 no"
fresh $((ALL + 2560))
guard vagrant up; rc=$?
check "  exactly that: started, and the watcher with it" "$rc $(alive)" "0 yes"
stop_watcher
# kubeadm running, its guest has touched 4 GB of its 18: the other 14 GB are promised, still counted as available
fresh $((4096 + 14336 + 2560 - 1)) ops_kubeadm
echo $((4096 * 1024)) > "$STUB/rss.ops_kubeadm"
guard vagrant up; rc=$?
check "up with kubeadm running: the Pis' memory and what kubeadm has not touched yet (14336 MB) needed - 1 MB short refused" \
  "$rc $(grep -c 'need 4096 MB, the running VMs may still take 14336 MB' <<< "$out")" "1 1"
fresh $((4096 + 14336 + 2560)) ops_kubeadm
echo $((4096 * 1024)) > "$STUB/rss.ops_kubeadm"
guard vagrant up; rc=$?
check "  exactly that: started" "$rc" 0
stop_watcher
fresh 4607
guard vagrant up --no-provision pi1; rc=$?
check "up pi1 --no-provision: the named VM only (2048 MB), the option skipped - 1 MB short refused" "$rc $(grep -c '(pi1 2048 MB) need 2048 MB' <<< "$out")" "1 1"
fresh 4608
guard vagrant --debug up pi1; rc=$?
check "--debug up pi1 (vagrant's own option first): judged as up pi1 - its 2048 MB + 2560, started and watched" \
  "$rc $(grep -c '2048 MB for the VMs vagrant up starts (pi1 2048 MB)' <<< "$out") $(alive)" "0 1 yes"
stop_watcher
fresh 4607
guard vagrant --debug up pi1; rc=$?
check "  1 MB short: refused" "$rc" 1
fresh 4608
guard vagrant up pi1 --provider libvirt; rc=$?
check "up pi1 --provider libvirt: the option's value is no machine name - pi1 alone counted, started" \
  "$rc $(grep -c '(pi1 2048 MB)' <<< "$out")" "0 1"
stop_watcher
fresh 4608
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
mkdir -p "$W/odd"
printf 'config.vm.define "a" do |a|\n  # v.memory = 99999\n  v.memory = 1024\nend\n' > "$W/odd/Vagrantfile"
COPY_VAGRANTFILE="$W/odd/Vagrantfile" guard vagrant up; rc=$?
check "a commented v.memory not read" "$rc $(grep -c '(a 1024 MB) + 0 MB the running ones may still take + 2560 MB kept' <<< "$out")" "0 1"
stop_watcher
printf 'config.vm.define "a" do |a|\n  v.memory = 1024\nend\nconfig.vm.define "b" do |b|\nend\n' > "$W/odd/Vagrantfile"
COPY_VAGRANTFILE="$W/odd/Vagrantfile" guard vagrant up; rc=$?
check "a VM without a v.memory: refused (it could not be counted nor powered off)" "$rc $(grep -c 'without a v.memory' <<< "$out")" "1 1"
printf 'config.vm.box = "x"\n' > "$W/odd/Vagrantfile"
COPY_VAGRANTFILE="$W/odd/Vagrantfile" guard vagrant up; rc=$?
check "  a Vagrantfile with none at all: refused" "$rc $(grep -c 'without a v.memory' <<< "$out")" "1 1"
for set in COPY_HOST_TRIP_MB=2G COPY_HOST_RESERVE_MB=2.5 COPY_HOST_PSI_FULL=x COPY_HOST_GRACE=-1 COPY_HOST_POLL=fast; do
  fresh 99999
  out=$(env "$set" bash scripts/copy-host-guard.sh vagrant up 2>&1); rc1=$?
  out2=$(env "$set" bash scripts/copy-host-guard.sh watch 2>&1); rc2=$?
  check "a setting that is no number ($set): up and watch refused (exit 2), said - never a guard that cannot trip" \
    "$rc1 $rc2 $(printf '%s\n%s\n' "$out" "$out2" | grep -c 'REFUSED: copy-host-guard') $(alive)" "2 2 2 no"
done

# another domain on the host (another project's, one renamed, one of a similar name) is none of ours
fresh $((ALL + 2560 - 1)) other_kubeadm kubeadm ops_kubeadm-old ops_pi10
guard vagrant up; rc=$?
check "domains not ours (other_kubeadm, kubeadm, ops_kubeadm-old, ops_pi10): none counted running - all three VMs needed" \
  "$rc $(grep -c "need $ALL MB, the running VMs may still take 0 MB" <<< "$out")" "1 1"

# --- the watcher --------------------------------------------------------------------------------------------------
fresh 9000 ops_pi1 ops_pi2 ops_kubeadm
guard watch; first=$(watcher)
guard watch; rc=$?
check "watch twice: one watcher (its lifetime lock), the second says so" "$rc $(grep -c "watches already (pid $first)" <<< "$out") $(watcher)" "0 1 $first"
check "  its start logged" "$(grep -c "watcher $first started" "$COPY_HOST_DIR/host-guard.log")" 1
# none of the caller's environment: production's .env, loaded by the Taskfile, never lives in it
check "  its environment: its settings only (its virsh by path), not the caller's (a variable the caller exported absent)" \
  "$(tr '\0' '\n' < "/proc/$first/environ" | grep -c "^COPY_HOST_POLL=0.05\$\|^COPY_HOST_VIRSH=$W/bin/virsh\$") $(tr '\0' '\n' < "/proc/$first/environ" | grep -c '^STUB=')" "2 0"
# low, high, low, high...: never two low polls running - no power-off
printf '%s\n' 1000 9000 1000 9000 "9000 90" 9000 "9000 90" 9000 > "$STUB/memq"
wait_for 10 test ! -s "$STUB/memq"; wait_for 10 polls_ge 10
check "short of memory on single polls (available or stall), never two running: nothing powered off" \
  "$(grep -c destroy "$STUB/calls") $(cat "$STUB/active" | tr '\n' ' ')" "0 ops_pi1 ops_pi2 ops_kubeadm "
# two low polls running: the biggest running VM off, once; then enough again
printf '%s\n' 2047 2047 9000 > "$STUB/memq"
wait_for 10 test ! -s "$STUB/memq"
wait_for 10 destroys_ge 1
check "under 2048 MB on two polls running: the biggest running VM (kubeadm) powered off, the Pis left" \
  "$(grep destroy "$STUB/calls" | tr '\n' ' ')/$(cat "$STUB/active" | tr '\n' ' ')" "-c qemu:///system destroy ops_kubeadm /ops_pi1 ops_pi2 "
wait_for 5 grep -q 'ops_kubeadm powered off' "$COPY_HOST_DIR/host-guard-tripped"
check "  recorded: the log and the trip, the numbers and the VM named" \
  "$(grep -c '2047 MB available and 0% memory stall on two polls .*: ops_kubeadm powered off' "$COPY_HOST_DIR/host-guard.log") $(grep -c 'ops_kubeadm powered off' "$COPY_HOST_DIR/host-guard-tripped")" "1 1"
# the memory stall alone (available plenty): over 25% on two polls running - the next biggest off
printf '%s\n' "9000 30" "9000 26" 9000 > "$STUB/memq"
wait_for 10 destroys_ge 2
wait_for 5 grep -q '26% memory stall' "$COPY_HOST_DIR/host-guard.log"
check "  the memory stall over 25% on two polls running, memory available: the next running VM off" \
  "$(grep destroy "$STUB/calls" | tail -1 | grep -c 'destroy ops_pi1') $(grep -c '26% memory stall.*ops_pi1 powered off' "$COPY_HOST_DIR/host-guard.log")" "1 1"
# a power-off that fails: said as such, never "powered off"; the watcher goes on
touch "$STUB/destroy-fails"
printf '%s\n' 100 100 9000 > "$STUB/memq"
wait_for 10 destroys_ge 3
wait_for 5 grep -q 'NOT powered off' "$COPY_HOST_DIR/host-guard.log"
check "a power-off that fails: logged NOT powered off with virsh's failure, the watcher still on" \
  "$(grep -c 'ops_pi2 NOT powered off - virsh destroy failed' "$COPY_HOST_DIR/host-guard.log") $(grep -c 'ops_pi2 powered off' "$COPY_HOST_DIR/host-guard.log") $(alive)" "1 0 yes"
stop_watcher
check "  its end logged" "$(grep -c "watcher $first ended" "$COPY_HOST_DIR/host-guard.log")" 1
# the next vagrant up prints the trip once
fresh 99999
echo "2026-11-13 22:17:00 the host had 100 MB available ...: ops_kubeadm powered off" > "$COPY_HOST_DIR/host-guard-tripped"
guard vagrant up; one=$out
stop_watcher
guard vagrant up; two=$out
stop_watcher
check "the last trip printed by the next vagrant up, once" \
  "$(grep -c "the host guard's last trip: .*ops_kubeadm powered off" <<< "$one") $(grep -c 'last trip' <<< "$two")" "1 0"
# the trip's VM by whole name: machines whose names hold one another (pi, pi10) - only the running one is a candidate
fresh 9000 ops_pi
mkdir -p "$W/sub/ops"
printf 'config.vm.define "pi" do |a|\n  v.memory = 1024\nend\nconfig.vm.define "pi10" do |b|\n  v.memory = 4096\nend\n' > "$W/sub/ops/Vagrantfile"
COPY_VAGRANTFILE="$W/sub/ops/Vagrantfile" guard watch
printf '%s\n' 100 100 9000 > "$STUB/memq"
wait_for 10 destroys_ge 1
check "a trip with machines named pi and pi10, pi alone running: pi powered off (never pi10, not running)" \
  "$(grep destroy "$STUB/calls" | head -1 | awk '{print $NF}')" "ops_pi"
stop_watcher
# one watcher for two callers at once (the callers' lock); in a session of its own (no run's Ctrl-C reaches it); a second
# caller returns while the first watcher lives (its lock never held by the watcher)
fresh 9000 ops_kubeadm
bash scripts/copy-host-guard.sh watch > "$W/w1.out" 2>&1 & w1=$!
bash scripts/copy-host-guard.sh watch > "$W/w2.out" 2>&1 & w2=$!
wait "$w1" "$w2"
loops=$(for e in /proc/[0-9]*/environ; do { tr '\0' '\n' < "$e"; } 2> /dev/null | grep -qxF "COPY_HOST_DIR=$COPY_HOST_DIR" && grep -q '_loop' "${e%environ}cmdline" 2> /dev/null && echo x; done | wc -l)
check "two watch calls at once: one watcher, the other says it watches" "$loops $(cat "$W/w1.out" "$W/w2.out" | grep -c 'watches already')" "1 1"
p=$(watcher)
read -r st < "/proc/$p/stat"; st=${st##*) }; set -- $st; loop_sid=$4   # after the name: state ppid pgrp session
read -r st < "/proc/$$/stat"; st=${st##*) }; set -- $st; my_sid=$4
check "  the watcher in a session of its own (its own leader)" "$([ "$loop_sid" = "$p" ] && [ "$loop_sid" != "$my_sid" ] && echo yes)" yes
timeout 10 bash scripts/copy-host-guard.sh watch > /dev/null 2>&1; rc=$?
check "  a caller while it lives returns at once (not held by a lock the watcher kept)" "$rc" 0
stop_watcher

# its lifetime: on a whole grace after its VMs stopped (the clock is the test's), then ends
fresh 9000 ops_kubeadm
COPY_HOST_GRACE=10 guard watch; p=$(watcher)
wait_for 10 polls_ge 2
: > "$STUB/active"; clock 109; c=$(polls); wait_for 10 polls_ge $((c + 4))
check "its VMs stopped: still watching within the grace (a halt before an up, a destroy before a build)" "$(pid_on "$p" && echo on)" on
clock 111
wait_for 10 pid_off "$p"; gone=$?
check "  a whole grace with no VM: ends" "$gone" 0
# a caller relying on it while it is quiet keeps it: the race of a vagrant up right after a destroy
fresh 9000 ops_kubeadm
COPY_HOST_GRACE=10 guard watch; p=$(watcher)
wait_for 10 polls_ge 2
: > "$STUB/active"; clock 105
COPY_HOST_GRACE=10 guard watch; rc=$?
clock 111; c=$(polls); wait_for 10 polls_ge $((c + 4))
check "a watch while it is quiet (a vagrant up after a destroy): it says it watches, and the grace starts again" \
  "$rc $(grep -c 'watches already' <<< "$out") $(pid_on "$p" && echo on)" "0 1 on"
echo ops_kubeadm > "$STUB/active"; clock 130; c=$(polls); wait_for 10 polls_ge $((c + 4))
check "  the VMs back: still the same watcher, watching" "$(pid_on "$p" && echo on) $(watcher)" "on $p"
: > "$STUB/active"; clock 150; c=$(polls); wait_for 10 polls_ge $((c + 4)); clock 161
wait_for 10 pid_off "$p"; gone=$?
check "  a whole grace with no VM and no caller since: ends" "$gone" 0
# none started: on until the grace, then ends
fresh 9000
COPY_HOST_GRACE=10 guard watch; p=$(watcher)
wait_for 10 polls_ge 4
check "none started yet: still watching within the grace (vagrant up's box import, a first boot)" "$(pid_on "$p" && echo on)" on
clock 111
wait_for 10 pid_off "$p"; gone=$?
check "  none started by the grace's end: ends" "$gone" 0
# libvirt not answering: still watching (never read as "nothing runs, end"), said once
fresh 9000 ops_kubeadm
COPY_HOST_GRACE=10 guard watch; p=$(watcher)
wait_for 10 polls_ge 2
touch "$STUB/fail"; clock 200
c=$(polls); wait_for 10 polls_ge $((c + 6))
check "libvirt not answering: still watching past the grace, said once" \
  "$(pid_on "$p" && echo on) $(grep -c "could not be listed (virsh) - still watching" "$COPY_HOST_DIR/host-guard.log")" "on 1"
stop_watcher

# its virsh gone (a test's stub removed while the watcher lives): never another virsh found on PATH - libvirt untouched
fresh 9000 ops_kubeadm
mkdir -p "$W/decoy"
printf '#!/bin/bash\necho "$*" >> %s/decoy/calls\n' "$W" > "$W/decoy/virsh"; chmod +x "$W/decoy/virsh"
PATH="$W/decoy:$PATH" COPY_HOST_VIRSH="$W/gone/virsh" COPY_HOST_GRACE=10 guard watch; p=$(watcher)
clock 200; wait_for 10 grep -q 'could not be listed' "$COPY_HOST_DIR/host-guard.log"; sleep 0.3
check "its virsh missing: still watching, said - and no virsh on PATH ever called in its place" \
  "$(pid_on "$p" && echo on) $([ -e "$W/decoy/calls" ] && echo called || echo untouched)" "on untouched"
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
  load_twice() {  # the Vagrantfile loaded twice in one process (Vagrant may), Vagrant's DSL a no-op; ARGS: its ARGV
    ruby -e 'module Vagrant; def self.configure(*); end; end
             ARGV.replace(ENV["ARGS"].split(" "))
             load ENV["VF"]; load ENV["VF"]
             puts "configured"' 2>&1
  }
  out=$(ARGS="--debug up --no-provision pi1" VF=$H/Vagrantfile load_twice); rc=$?
  check "hook: vagrant's arguments passed whole, once per process; allowed - the Vagrantfile goes on" \
    "$rc $(cat "$H/args" 2> /dev/null) $(grep -c configured <<< "$out")" "0 vagrant|--debug|up|--no-provision|pi1| 1"
  rm -f "$H/args"
  out=$(GUARD_RC=1 ARGS="--debug up --no-provision pi1" VF=$H/Vagrantfile load_twice); rc=$?
  check "  a start refused: the command aborted, said, nothing configured" \
    "$rc $(grep -c "vagrant --debug up --no-provision pi1: refused by $H/scripts/copy-host-guard.sh" <<< "$out") $(grep -c configured <<< "$out")" "1 1 0"
  out=$(GUARD_RC=1 ARGS="halt" VF=$H/Vagrantfile load_twice); rc=$?
  check "  any other command goes on whatever the guard says (halt frees memory)" "$rc $(grep -c configured <<< "$out")" "0 1"
  # one start at a time: another process holding the start lock refuses a start, never a destroy
  ruby -e 'f = File.open(ARGV[0], File::RDWR | File::CREAT); f.flock(File::LOCK_EX); STDOUT.puts "held"; STDOUT.flush; sleep 30' \
    "$H/.copy/vagrant-start.lock" > "$W/holder.out" 2>&1 &
  holder=$!
  wait_for 10 grep -q held "$W/holder.out"
  out=$(ARGS="up pi1" VF=$H/Vagrantfile load_twice); rc=$?
  out2=$(ARGS="destroy -f" VF=$H/Vagrantfile load_twice); rc2=$?
  kill "$holder" 2> /dev/null; wait "$holder" 2> /dev/null
  check "  another start under way (the start lock held): a start refused, said; a destroy goes on" \
    "$rc $(grep -c 'another vagrant up, reload or resume runs here' <<< "$out") $rc2 $(grep -c configured <<< "$out2")" "1 1 0 1"
  out=$(ARGS="up pi1" VF=$H/Vagrantfile load_twice); rc=$?
  check "    the lock free again: the start goes on" "$rc $(grep -c configured <<< "$out")" "0 1"
  rm -f "$H/scripts/copy-host-guard.sh"
  out=$(ARGS="up pi1" VF=$H/Vagrantfile load_twice); rc=$?
  out2=$(ARGS="halt" VF=$H/Vagrantfile load_twice); rc2=$?
  check "  the guard missing (cannot run): a start aborted; a halt goes on" \
    "$rc $(grep -c configured <<< "$out") $rc2 $(grep -c configured <<< "$out2")" "1 0 0 1"
fi
cd "$REPO" || exit 1
echo "copy-host-guard: $([ "$fails" -eq 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ "$fails" -eq 0 ]
