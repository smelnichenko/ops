# process-groups.sh - a script's own jobs' process groups stopped, whole and bounded (sourced by
# upgrade-build-with-pin.sh and upgrade-step-checks.sh; each passes only groups of jobs it started itself).

# whole seconds since boot into the variable named: a clock no wall-clock step moves (bash's SECONDS follows the wall
# clock - a step back held a deadline for the step's length, one forward ended a grace at once); no subshell
uptime_s() {  # uptime_s <variable>
  local _up
  read -r _up _ < /proc/uptime
  printf -v "$1" '%s' "${_up%.*}"
}

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

# a process group with a member still running - read from /proc (CI's image has no ps) by the read builtin (a cat per
# process made one scan 0.6 s); a zombie, a job's own exited leader not reaped yet, is none. The job's own process
# counts too while it leads no group yet: a job started under setsid is in this shell's group until setsid has run
group_alive() {  # group_alive <pgid>
  local g=$1 f st p
  for f in /proc/[0-9]*/stat; do
    read -r st 2> /dev/null < "$f" || continue
    p=${f#/proc/}
    p=${p%/stat}
    set -- ${st##*) }  # its state, parent, group
    { [ "$3" = "$g" ] || [ "$p" = "$g" ]; } && [ "$1" != Z ] && return 0
  done
  return 1
}

# each group TERMed and continued (a stopped one acts on no TERM until then) - the job's own process by its PID when it
# leads no group yet (signalled before its setsid ran, the group's TERM found none and was lost: KILLed after the
# grace, its own traps never run) - given <grace> seconds for every member to end - not only its leader: a shell's
# subshell dies at once, the program under it may not - then killed, said
stop_groups() {  # stop_groups <grace seconds> <pgid>...
  local grace=$1 g end now
  shift
  for g; do
    kill -TERM -- "-$g" 2> /dev/null || kill -TERM "$g" 2> /dev/null
    kill -CONT -- "-$g" 2> /dev/null || kill -CONT "$g" 2> /dev/null
  done
  uptime_s now
  end=$((now + grace))
  for g; do
    while group_alive "$g" && uptime_s now && ((now < end)); do sleep 0.5; done
    if group_alive "$g"; then
      echo "job $g's processes outlived the stop by $grace s - killed"
      kill -KILL -- "-$g" 2> /dev/null || kill -KILL "$g" 2> /dev/null
    fi
  done
}
