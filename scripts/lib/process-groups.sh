# process-groups.sh - a script's own jobs stopped, whole and bounded: each job's process group, and the session it leads
# when it leads one (setsid) - every group of it: a check its script started in a group of its own (set -m) among them
# (sourced by upgrade-full-steps.sh, upgrade-build-with-pin.sh and upgrade-step-checks.sh; each passes only jobs it
# started itself). A process that leaves the session (Ansible's workers call setsid) is stopped only by its own parent.

# hundredths of a second since boot into the variable named: a clock no wall-clock step moves (bash's SECONDS follows
# the wall clock - a step back held a deadline for the step's length, one forward ended a grace at once), finer than a
# second (whole seconds made a 1 s grace anything from none to a second); no subshell
uptime_cs() {  # uptime_cs <variable>
  local _up
  read -r _up _ < /proc/uptime
  _up=${_up/./}
  printf -v "$1" '%s' "$((10#$_up))"
}

# the clock ticks /proc/<pid>/stat counts a process's start in (100 on Linux as built here; asked once)
_clk_tck=$(getconf CLK_TCK 2> /dev/null) || _clk_tck=100
[[ $_clk_tck =~ ^[1-9][0-9]*$ ]] || _clk_tck=100

# this shell's jobs still its own children (running, stopped, or ended and not reaped) into the array named: `jobs -p`
# also lists one bash reaped already, whose PID the system may since have given another process
own_jobs() {  # own_jobs <array>
  local -n _jobs=$1
  local _p _st
  _jobs=()
  for _p in $(jobs -p); do
    read -r _st 2> /dev/null < "/proc/$_p/stat" || continue
    set -- ${_st##*) }  # its state, parent (after the command name, which may hold spaces)
    [ "$2" = "$$" ] && _jobs+=("$_p")
  done
}

# the process is this shell's child and runs (a zombie, ended and not reaped, does not): a PID kept after its job was
# reaped may be another process's by now - never one to wait on or signal by its number
child_alive() {  # child_alive <pid>
  local st
  read -r st 2> /dev/null < "/proc/$1/stat" || return 1
  set -- ${st##*) }
  [ "$2" = "$$" ] && [ "$1" != Z ]
}

# a job with a process still running - in its group, or in the session it leads - read from /proc (CI's image has no
# ps) by the read builtin (a cat per process made one scan 0.6 s); a zombie is none. The job's own process counts too
# while it leads no group yet (a job started under setsid is in this shell's group until setsid has run) - while it is
# this shell's child: a PID alone matched another process once the job was reaped
group_alive() {  # group_alive <pgid>
  local g=$1 f st p
  for f in /proc/[0-9]*/stat; do
    read -r st 2> /dev/null < "$f" || continue
    p=${f#/proc/}
    p=${p%/stat}
    set -- ${st##*) }  # its state, parent, group, session
    [ "$1" != Z ] || continue
    { [ "$3" = "$g" ] || [ "$4" = "$g" ] || { [ "$p" = "$g" ] && [ "$2" = "$$" ]; }; } && return 0
  done
  return 1
}

# every process group of the session the job leads, its own among them, into the array named (none: it leads none)
session_groups() {  # session_groups <sid> <array>
  local _sid=$1 _f _st
  local -n _groups=$2
  _groups=()
  for _f in /proc/[0-9]*/stat; do
    read -r _st 2> /dev/null < "$_f" || continue
    set -- ${_st##*) }
    [ "$4" = "$_sid" ] && [[ " ${_groups[*]} " != *" $3 "* ]] && _groups+=("$3")
  done
}

# a signal to the job whole: its group, every group of the session it leads; by its PID while it leads no group yet -
# only while it is this shell's child. With a variable: the time just before it was sent (uptime_cs), read the moment
# the clock has ticked over - a process started in the same hundredth before the signal (forked during the scan) then
# reads as started before it, not after (its lost TERM would never be sent again: the concurrency review, 2026-10-12)
signal_job() {  # signal_job <signal> <pgid> [<variable>]
  local sig=$1 g=$2 x groups _sj_a _sj_b _sj_i
  session_groups "$g" groups
  if [ -n "${3:-}" ]; then
    uptime_cs _sj_a
    for ((_sj_i = 0; _sj_i < 1000000; _sj_i++)); do uptime_cs _sj_b; ((_sj_b > _sj_a)) && break; done
    printf -v "$3" '%s' "$_sj_b"
  fi
  kill "-$sig" -- "-$g" 2> /dev/null || { child_alive "$g" && kill "-$sig" "$g" 2> /dev/null; }
  for x in "${groups[@]}"; do [ "$x" = "$g" ] || kill "-$sig" -- "-$x" 2> /dev/null; done
}

# the job's running processes - its group, the session it leads, its own while it leads no group yet (as group_alive)
# - into the array named, each "<pid> <parent>"
job_processes() {  # job_processes <pgid> <array>
  local _g=$1 _f _st _p
  local -n _procs=$2
  _procs=()
  for _f in /proc/[0-9]*/stat; do
    read -r _st 2> /dev/null < "$_f" || continue
    _p=${_f#/proc/}
    _p=${_p%/stat}
    set -- ${_st##*) }
    [ "$1" != Z ] || continue
    { [ "$3" = "$_g" ] || [ "$4" = "$_g" ] || { [ "$_p" = "$_g" ] && [ "$2" = "$$" ]; }; } && _procs+=("$_p $2")
  done
}

# the process runs with TERM at its default - neither caught nor ignored
term_default() {  # term_default <pid>
  local k v ign="" cgt=""
  while read -r k v; do
    case $k in SigIgn:) ign=$v ;; SigCgt:) cgt=$v ;; esac
  done 2> /dev/null < "/proc/$1/status"
  [ -n "$ign" ] && [ -n "$cgt" ] && (( ((16#$ign | 16#$cgt) & 0x4000) == 0 ))
}

# every process of the job of that name stopped (STOP) and waited for, one deadline for all (0.5 s on the clock):
# until every thread of each is stopped - a fork any thread was in (go-task runs 20 and more) completes first, so a
# look after it sees every child it has (a main thread read alone showed T with another thread's fork still running:
# 17 in 20 - the reviews, 2026-10-11). The variable gets the wholly stopped ones: KILLed by name. One not wholly
# stopped at the deadline (a thread still in a fork, or in the kernel) stays STOP-pending, out of this look - the next
# look waits for it again; one that never stops is KILLed at the grace's end. A process named so only after this read
# (forked, then exec'd as the name) waits for the next look, stopped first - KILLed on a list read before its fork,
# its child was never TERMed
# a process's start (clock ticks since boot, /proc/<pid>/stat field 22) into the variable named; empty when gone
start_of() {  # start_of <pid> <variable>
  local _so_st
  printf -v "$2" '%s' ""
  read -r _so_st 2> /dev/null < "/proc/$1/stat" || return 0
  set -- "$2" ${_so_st##*) }
  printf -v "$1" '%s' "${21}"
}

# each process STOPped: its start (start_of), so a KILL or CONT later goes to that process, never to a pid reused
declare -gA _pg_started=()

stop_named() {  # stop_named <pgid> <name> <variable: " <pid> ... " each wholly stopped>
  local g=$1 name=$2 procs x p comm pending=() notyet
  local -n _stopped=$3
  _stopped=" "
  job_processes "$g" procs
  for x in "${procs[@]}"; do
    p=${x% *}
    read -r comm 2> /dev/null < "/proc/$p/comm" && [ "$comm" = "$name" ] || continue
    kill -STOP "$p" 2> /dev/null && { pending+=("$p"); _stopped+="$p "; start_of "$p" "_pg_started[$p]"; }
  done
  wait_stopped notyet "${pending[@]}"
  for p in $notyet; do _stopped=${_stopped/ $p / }; done
}

# each process waited for, one deadline for all (0.5 s on uptime_cs's clock), until every one of its threads is
# stopped (or it is gone); the variable gets those still not wholly stopped at the deadline. Locals prefixed: the
# caller's variable is a nameref. The proc root is a variable for its test only
wait_stopped() {  # wait_stopped <variable: " <pid> ... "> <pid>...
  local -n _ws_left=$1
  shift
  local _ws_pending=("$@") _ws_next _ws_p _ws_t _ws_st _ws_now _ws_end _ws_root=${_procfs_root:-/proc}
  uptime_cs _ws_now
  _ws_end=$((_ws_now + 50))
  while ((${#_ws_pending[@]} > 0)); do
    _ws_next=()
    for _ws_p in "${_ws_pending[@]}"; do
      [ -e "$_ws_root/$_ws_p/stat" ] || continue
      for _ws_t in "$_ws_root/$_ws_p/task/"[0-9]*/stat; do
        read -r _ws_st 2> /dev/null < "$_ws_t" || continue
        set -- ${_ws_st##*) }
        case $1 in T | t | Z | X) ;; *) _ws_next+=("$_ws_p"); break ;; esac
      done
    done
    _ws_pending=("${_ws_next[@]}")
    ((${#_ws_pending[@]} > 0)) || break
    uptime_cs _ws_now
    ((_ws_now < _ws_end)) || break
    sleep 0.01
  done
  _ws_left=" ${_ws_pending[*]} "
}

# the stop's TERM sent again where it was lost: a process of the job's there when it was sent (started before it) still
# running with TERM at its default never got it - a job just forked loses one (its signals still its parent's
# handlers until it resets them; the step's checks' stop waited out their bound) - and with it what it started since:
# at its default, or catching it and not there when it was sent (it never got one - sent once, then counted sent).
# With a name, every process of the job of that name KILLed (go-task: one a command started during the grace swallowed
# the TERM and ran the step's next command), what it started since the TERM a lost process's. Never again to one that
# catches the TERM (its handler runs once), nor to what a handler started (a cleanup's own commands)
resend_term() {  # resend_term <pgid> <the TERM's time, uptime_cs> <sent variable: " <pid> ... "> [<command name>]
  local g=$1 term_at=$2 name=${4:-} procs x p comm st lost=" " changed=1 stopped=" " killed=" "
  local -n _sent=$3
  local -A parent=() deflt=()
  [ -z "$name" ] || stop_named "$g" "$name" stopped
  job_processes "$g" procs
  for x in "${procs[@]}"; do
    p=${x% *}
    parent[$p]=${x#* }
    term_default "$p" && deflt[$p]=1
    # there when the TERM went - by its start (hundredths since boot, as uptime_cs): a list read before the TERM missed
    # one forked between the read and the TERM that lost it (it ran to the grace, KILLed)
    if read -r st 2> /dev/null < "/proc/$p/stat"; then
      set -- ${st##*) }
      (( ${20} * 100 / _clk_tck >= term_at )) || [[ $_sent == *" $p "* ]] || _sent+="$p "
    fi
    if [[ $stopped == *" $p "* ]] && read -r comm 2> /dev/null < "/proc/$p/comm" && [ "$comm" = "$name" ] \
      && start_of "$p" st && [ -n "$st" ] && [ "$st" = "${_pg_started[$p]:-}" ]; then
      kill -KILL "$p" 2> /dev/null
      killed+="$p "
      lost+="$p "
    fi
  done
  for p in "${!deflt[@]}"; do [[ $_sent != *" $p "* ]] || lost+="$p "; done
  # one started since the TERM whose parent left the job (re-parented: a lost process it was forked by ended of the
  # TERM sent again before the look saw it) - lost with it; never TERMed, it ran to the grace, KILLed
  for p in "${!deflt[@]}"; do
    [[ $_sent == *" $p "* ]] || [ -n "${parent[${parent[$p]}]+x}" ] || lost+="$p "
  done
  while ((changed)); do
    changed=0
    for p in "${!parent[@]}"; do
      [[ $lost != *" $p "* ]] && [[ $lost == *" ${parent[$p]} "* ]] || continue
      [ -n "${deflt[$p]:-}" ] || [[ $_sent != *" $p "* ]] || continue
      lost+="$p "
      changed=1
    done
  done
  for p in $lost; do
    kill -TERM "$p" 2> /dev/null
    [ -n "${deflt[$p]:-}" ] || [[ $_sent == *" $p "* ]] || _sent+="$p "
  done
  # one stopped and not KILLed (its name changed) runs on - only one this look listed, and only the process stopped
  # (its start the same: a pid gone since may be reused)
  for p in $stopped; do
    [[ $killed == *" $p "* ]] && continue
    [ -n "${parent[$p]+x}" ] || continue
    start_of "$p" st
    [ "$st" = "${_pg_started[$p]:-}" ] && kill -CONT "$p" 2> /dev/null
  done
}

# every process of the session the job leads with that command name KILLed at once - no other of the session, none
# outside it (go-task: it ran the step's next command once the running one ended, the stop's grace still running)
kill_named() {  # kill_named <sid> <name>
  local sid=$1 name=$2 f st p comm
  for f in /proc/[0-9]*/stat; do
    read -r st 2> /dev/null < "$f" || continue
    p=${f#/proc/}
    p=${p%/stat}
    set -- ${st##*) }
    [ "$4" = "$sid" ] && [ "$1" != Z ] || continue
    read -r comm 2> /dev/null < "/proc/$p/comm" && [ "$comm" = "$name" ] && kill -KILL "$p" 2> /dev/null
  done
}

# each job TERMed and continued whole (a stopped group acts on no TERM until then; a TERM lost sent again) - given
# <grace> seconds for every process of it to end - not only its leader: a shell's subshell dies at once, the program
# under it may not - then KILLed whole, again until none is left (one forked during a pass), and only then said: a
# write to an output whose reader is gone (a tee ended by the Ctrl-C) may end the caller, and the KILL must be sent by
# then. One the KILL did not end (uninterruptible, in the kernel) named, not said killed. -n <name>: every process of
# that name KILLed at once, before the TERM and at each look during the grace (go-task: kill_named)
stop_groups() {  # stop_groups [-n <command name>] <grace seconds> <pgid>...
  local name="" grace g end now t pass sent=" " procs x left
  local -A term_at=()
  # the jobs a KILL did not end, for the caller: a wait for one never ends (in the kernel)
  stop_left=""
  [ "$1" != -n ] || { name=$2; shift 2; }
  grace=$1
  shift
  for g; do
    [ -z "$name" ] || kill_named "$g" "$name"
    # its TERM's time, just before it went: a process started before it was there (one started after - a handler's
    # cleanup command among them - never lost it)
    signal_job TERM "$g" t
    term_at[$g]=$t
    signal_job CONT "$g"
  done
  uptime_cs now
  end=$((now + grace * 100))
  for g; do
    while group_alive "$g" && uptime_cs now && ((now < end)); do
      sleep 0.2
      resend_term "$g" "${term_at[$g]}" sent "$name"
    done
    if group_alive "$g"; then
      for ((pass = 0; pass < 10; pass++)); do
        signal_job KILL "$g"
        sleep 0.1
        group_alive "$g" || break
      done
      job_processes "$g" procs
      if [ "${#procs[@]}" -eq 0 ]; then
        echo "job $g's processes outlived the stop by $grace s - killed"
      else
        left=""
        for x in "${procs[@]}"; do left+=" ${x% *}"; done
        echo "job $g's processes outlived the stop by $grace s - KILL sent, still there:$left"
        stop_left+=" $g"
      fi
    fi
  done
}
