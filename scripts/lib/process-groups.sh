# process-groups.sh - a script's own jobs' process groups stopped, whole and bounded (sourced by
# upgrade-build-with-pin.sh and upgrade-step-checks.sh; each passes only groups of jobs it started itself).

# a process group with a member still running - read from /proc (CI's image has no ps); a zombie, a job's own exited
# leader not reaped yet, is none
group_alive() {  # group_alive <pgid>
  local g=$1 f st
  for f in /proc/[0-9]*/stat; do
    st=$(cat "$f" 2> /dev/null) || continue
    set -- ${st##*) }  # its state, parent, group (after the command name, which may hold spaces)
    [ "$3" = "$g" ] && [ "$1" != Z ] && return 0
  done
  return 1
}

# each group TERMed and continued (a stopped one acts on no TERM until then), given <grace> seconds for every member to
# end - not only its leader: a shell's subshell dies at once, the program under it may not - then killed, said
stop_groups() {  # stop_groups <grace seconds> <pgid>...
  local grace=$1 g end
  shift
  for g; do
    kill -TERM -- "-$g" 2> /dev/null
    kill -CONT -- "-$g" 2> /dev/null
  done
  end=$((SECONDS + grace))
  for g; do
    while group_alive "$g" && ((SECONDS < end)); do sleep 0.5; done
    if group_alive "$g"; then
      echo "job $g's processes outlived the stop by $grace s - killed"
      kill -KILL -- "-$g" 2> /dev/null
    fi
  done
}
