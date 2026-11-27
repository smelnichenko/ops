#!/usr/bin/env bash
# The upgrade cycle's run - task upgrade:run's second half, after Renovate (started by hand, run locally): one Renovate
# unit - picked (a step of an upgrade path only after the steps below it), proven on the Vagrant copy (one fix by the
# Claude agent when red), reviewed (its compatibility among the passes: each version it moves against what production
# runs, its path from the version running, one version everywhere), backed up before a one-way change, applied to production,
# verified, recorded, reported on the terminal and in its log (nothing mailed: the runs are started by hand - operator
# 2026-11-20). Nothing in production
# moves before the merge; from the merge on, a run that cannot finish PAGES (a one-way failure: the cycle paused, the
# runner refusing until it is resolved) - half a unit applied is never left unsaid. No shadow mode (operator 2026-11-15:
# "deploy once it works in vagrant tests"; its flag gone 2026-11-20 - the first applying run's gate it was had passed).
#
#   0. gates    before anything (and alone with --preflight, which task upgrade:run runs before Renovate) and again right
#               before the merge: no page open; no run stopped mid-apply (its journal - one found with no page
#               is paged now; one that ends verified is a record to push, said); ops on main,
#               origin's, clean but for the copy's inventory record; at the start, the local infra and platform mains
#               origin's but for CD's app promotions (the copy mirrors them); production settled and quiet (critical alerts included). The
#               copy's memory (the operator stops the radar) for a unit that builds it - refused, never waited
#   1. pick     scripts/upgrade-units.py pick - NOTHING / PAUSED end the run quietly; the units with no try on record
#               first (one that keeps failing never holds the queue: there is no blocked state, operator 2026-11-20);
#               a one-way unit whose store has a part with no backup yet (scripts/upgrade-stores.json) stopped at once,
#               the part named - ops' to fix, a try; one without Renovate's labels (its kind not known) never applied
#   2. prove    the unit's heads read (and its bases); its branches, in every repo, on main but for CD's promotions
#               (Renovate rebases only on a conflict: a unit behind brought up to date by Forgejo first, its new heads
#               waited for - an empty answer never a head; never read as the unit's defect); then its CI green (a
#               running one waited for an hour - still running: said, no try, the same heads still so a run later a
#               try; a red one a try, none at all a try) and main read again (it moved meanwhile: said, no try), each
#               checkout's branch the head its pull request names (Forgejo's record may lag); task test:copy:ready (the copy as built - its base snapshot reverted, or built; a copy that does not get ready ends the run - the unit
#               untouched), task test:copy:unit UNIT=<it>; red, or any finding of the review (3.): the agent's fix (two at most a run) - it commits in clones of the proven
#               commits outside every checkout; the runner fetches its commits into a repository of its own (the
#               agent's hooks and config never run), keeps them only on top of the proven head, inside the unit's own
#               kind of files (infra's clusters/, platform's helm/, ops' Ansible vars and playbooks - never CI,
#               scripts, tasks or an agent's instructions), plain UTF-8 text files alone (no symlink, no submodule, no
#               binary), each line it adds printable ASCII and tab (a NEL or a U+2028 is a line break to YAML and none
#               to git; a no-break space indenting a key, a look-alike letter: another key that reads the same), no
#               merge commit - every repo judged before any is pushed; the fix kept on record (.upgrade-cycle/fixes/<unit>.diff), the unit
#               labelled agent-fixed and stop-updating, then its tree pushed as the bot - one commit of the runner's on
#               the proven head (the agent's own commits - a step in between, its words, its author - never on Forgejo); Forgejo read until it shows them, their
#               CI waited for, proven again on a base built fresh; the heads after each proof the ones proven. What the
#               run cannot take further - red after its fix, no fix (the agent's NO FIX), a failure with no verdict (CI
#               red, a review or fix that did not finish, Forgejo refusing the update) - is said (the log and the
#               terminal, never a mail: nothing in it for the operator) and counts a try for the unit's pull requests
#               (the same name later is another unit): the next pick takes the units with none first; an apply clears
#               them
#   3. review   the review of the unit's diff (the agent, headless, --restricted: no instructions from the clones; the
#               reviewers' own agents handed to it, a definition that does not read refusing the review) - CLEAN is no
#               FINDING line at all, VERDICT: CLEAN and every pass named exactly; any finding, whatever its severity
#               (operator 2026-11-20: every severity, not criticals alone), goes to the agent's fix (2.), the unit proven and
#               reviewed again - findings left after the last fix a try, an INCOMPLETE or unfinished review a try. The
#               copy halted then, marked used (no change or check on it until the next run readies it - its base
#               snapshot kept)
#   4. (no gate) a major, a one-way unit and one carrying the agent's fix apply in the run that proves and reviews them,
#               as a patch does (operator 2026-11-21: no 24 h veto notice - the versions'
#               compatibility is what to make sure of) - compatibility is the review's pass (3.), a path of several steps the pick's order (1.)
#   5. plan     its production commands read from the proof's plan - a step with none, or a version that is none,
#               refuses the unit, nothing merged
#   6. apply    the gates again; the backups a one-way change needs (an etcd snapshot before Kubernetes, its store's from
#               scripts/upgrade-stores.json) - failing,
#               nothing merged; held (a veto, the kill switch) refused; a journal written (the
#               snapshot's name, the pull requests merged, each command - a closed terminal stops nothing from here
#               on); the unit's pull requests merged by the bot at the proven commits onto the proven bases (CD's app
#               promotions since aside; ops' main where the gate saw it, or nothing merged; a partial or unknown merge
#               - any exit but Forgejo's refusal - pages); ops
#               brought to origin's main (fetch, fast-forward) only when it holds the gate's main and the unit's own
#               merge alone; what a chart the unit moves stopped shipping deleted once Argo runs the new version
#               (scripts/upgrade-leftovers.py: declared objects only - prune is off; failing, paged); Argo settled on
#               the merge (infra's and platform's parts) before each production command
#   7. verify   Argo settled on the merge, every pod ready, no critical alert through the hold; red: paged
#   8. record   docs/upgrades/<date>-<unit>.md committed, production's inventory read again; the journal removed
#
# The agents run with a clean environment - never ops/.env (Vault's root token, the admin's password, the API key, which
# would bill instead of the account) and no git credential - and settings of their own (.claude/upgrade-agent/): both
# --restricted (their file tools in their clones alone, no instructions from the clones), their Bash sandboxed (nothing
# in the home directory readable but the clones, .git's hooks and config unwritable, no network - the
# release notes aside - WebFetch); the fix commits only (no checksum script: a pin is Renovate's, a fix that needs one
# is no fix), as an author of its own (Upgrade Fix Agent - never Renovate's e-mail: Renovate takes a branch whose
# commits carry it for unmodified and rebases over them); the review changes nothing. Their clones live outside every checkout. A test environment's unit after
# which anything not placed in the test environment is not settled (a read that failed, a critical alert) pages.
#
# Usage: scripts/upgrade-cycle.sh [--dry|--preflight]
#        --dry       every step said, nothing run (the gates read)
#        --preflight the gates (and the copy's memory) alone: exit 0 when a run may start
# Env:   UPGRADE_FORGEJO_TOKEN (the bot's), UPGRADE_AGENT (the agent's command, default claude), UPGRADE_AGENT_TIMEOUT
#        (seconds, 3600), UPGRADE_WORK (the agents' clones, default <ops>/../.upgrade-cycle-work - the agents' settings
#        let them read that one), UPGRADE_HEADS_READS (12) / UPGRADE_HEADS_WAIT (10 s): Forgejo read after a push until
#        it shows it; the harness's: UPGRADE_MEMINFO, UPGRADE_FORGEJO_GIT (the bot's git URL
#        base, default https://git.pmon.dev)
set -uo pipefail
# C's messages and byte order, UTF-8's encoding: what the runner starts includes Ansible (the copy's build, the apply's
# tasks), and Ansible refuses any locale encoding but UTF-8 - LC_ALL=C stopped the first build through the runner
# (2026-11-16, 'Detected None')
export LC_ALL=C.UTF-8
ops=$(cd "$(dirname "$0")/.." && pwd)
cd "$ops" || exit 1
dry=""; preflight=""
case "${1:-}" in
  "") ;;
  --dry) dry=1 ;;
  --preflight) preflight=1 ;;
  *) echo "REFUSED: upgrade-cycle.sh [--dry|--preflight]"; exit 2 ;;
esac
# the cycle's state - the open pages, the journal of an apply under way, the run's lock:
# gitignored, not .copy's scratch
state=$ops/.upgrade-cycle
work=${UPGRADE_WORK:-$(dirname "$ops")/.upgrade-cycle-work}
forgejo=${UPGRADE_FORGEJO_GIT:-https://git.pmon.dev}
mkdir -p "$ops/.copy" "$state"
log=$ops/.copy/upgrade-cycle-$(date +%Y%m%d-%H%M%S)-$$.log  # each run its own: a verdict is never an earlier run's
# the console follows the log as it is written - every step's output, not the runner's own lines alone (operator
# 2026-11-22: "make all this logging visible on the console where task runs"); the log is the record, the console its
# reader: a reader gone (a closed terminal) costs it no line. The run's last line (END) ends the follower, waited for -
# what the task runs next never prints ahead of this run's tail; a run killed outright ends it through --pid
: >> "$log"
tail -n +1 -F -s 0.1 --pid=$$ "$log" 2> /dev/null | sed -Eu '/^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} END rc=[0-9]+$/q' &
follower=$!
say() { echo "$(date '+%F %T') $*" >> "$log"; }
console_end() { say "END rc=$1"; wait "$follower" 2> /dev/null; }
trap 'console_end $?' EXIT
# a step: said, and run unless --dry; its output in the log; nothing it runs reads the run's own input or holds its lock
# (a daemon a step leaves - the copy's host guard - would keep the next run out)
run() {
  say "RUN $*"
  [ -n "$dry" ] && return 0
  "$@" < /dev/null >> "$log" 2>&1 9>&-
}
# a run that ends short of applying: said in its log and on the terminal, never mailed - nothing in it for the operator
# (the next run takes the unit up; a cause in ops is mine to fix) - operator 2026-11-20: no mail from the cycle at all
stopped() { say "STOPPED $unit: $1${2:+ (details: $2)}"; }
unit=""
page() {  # a one-way failure: recorded (the runner refuses while it is open), the cycle paused on Forgejo, said - never mailed
  run scripts/upgrade-notice.sh page "$unit" "$1" "$log" || say "PAGE NOT RECORDED: $1 - the dashboard's pause holds the cycle"
  run scripts/upgrade-label.py --pause "UPGRADE PAUSED $(date -u +%Y-%m-%dT%H:%M:%SZ) - $unit: $1 - the operator's: production checked, then scripts/upgrade-notice.sh resolve $unit, $state/inflight removed (if there), and this label removed" \
    || say "NOT PAUSED: the dashboard's upgrades-paused not set - the runner's own record refuses the next run all the same"
}

# one run at a time, whoever starts it (task upgrade:run, Renovate's step of it, or by hand)
exec 9>> "$state/lock"
flock -n 9 || { echo "REFUSED: another upgrade run holds $state/lock"; exit 1; }

agent=${UPGRADE_AGENT:-claude}
agent_timeout=${UPGRADE_AGENT_TIMEOUT:-3600}
# the agents' environment: none of ops/.env, no git credential or config of the operator's, no repository above their
# clones; their commits the agent's own (never Renovate's identity: a branch it wrote to is one Renovate leaves alone)
clean_env=(env -i "HOME=$HOME" "PATH=$PATH" "LANG=C.UTF-8" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
           GIT_TERMINAL_PROMPT=0 "GIT_CEILING_DIRECTORIES=$work" "GIT_AUTHOR_NAME=Upgrade Fix Agent"
           GIT_AUTHOR_EMAIL=upgrade-fix@pmon.dev "GIT_COMMITTER_NAME=Upgrade Fix Agent" GIT_COMMITTER_EMAIL=upgrade-fix@pmon.dev)
fix_flags=(--restricted --tools "Bash,Read,Edit,Glob,Grep,WebFetch"
           --append-system-prompt-file "$ops/.claude/skills/upgrade-fix/SKILL.md"
           --settings "$ops/.claude/upgrade-agent/fix.json" --strict-mcp-config --permission-mode dontAsk --permission-prompts none)
# the review's reviewers: ops main's own agent definitions, handed over on the command line (--restricted reads no
# settings, skills or instructions from anywhere but its flags)
REVIEWERS="code-architecture-reviewer platform-reliability-reviewer test-quality-reviewer"
REVIEW_PASSES="correctness security architecture reliability tests compatibility"
reviewers_json() {
  python3 -I - "$ops/.claude/agents" $REVIEWERS <<'PY'
import json, re, sys
d, out = sys.argv[1], {}
for name in sys.argv[2:]:
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", open(f"{d}/{name}.md", encoding="utf-8").read(), re.S)
    fm = dict(line.split(": ", 1) for line in m.group(1).splitlines() if ": " in line)
    out[name] = {"description": fm["description"], "prompt": m.group(2).strip(),
                 "tools": [t.strip() for t in fm.get("tools", "").split(",") if t.strip()]}
    if not out[name]["description"].strip() or not out[name]["prompt"]:
        sys.exit(f"{name}: no description or no prompt")
print(json.dumps(out))
PY
}
bot_git() {  # git as the bot: its token through a credential helper of the call's own - to Forgejo's host alone, never
             # on a command line
  local host=${forgejo#*://}; host=${host%%/*}
  GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c "credential.helper=!f() { test \"\$1\" = get || exit 0; h=; while IFS== read -r k v && [ -n \"\$k\" ]; do [ \"\$k\" != host ] || h=\$v; done; test \"\$h\" = $host && printf 'username=renovate-bot\\npassword=%s\\n' \"\$UPGRADE_FORGEJO_TOKEN\"; }; f" "$@"
}


# 0. the gates
# infra's and platform's local mains brought to origin's when only behind it - on main, clean, a fast-forward: the
# runner merges there through Forgejo, so after a unit the next run found them behind and refused (test-curlimages-
# curl-8.x, the first chained run, 2026-11-17); one ahead, dirty or on another branch is left as it is - the check after
# refuses it, said
mains_forward() {
  local r
  [ -n "$dry" ] && { say "RUN git fetch, merge --ff-only (infra, platform: a main only behind origin's brought to it)"; return 0; }
  for r in ../infra ../platform; do
    [ "$(git -C "$r" rev-parse --abbrev-ref HEAD 2> /dev/null)" = main ] && [ -z "$(git -C "$r" status --porcelain 2>&1)" ] || continue
    git -C "$r" fetch -q origin main < /dev/null >> "$log" 2>&1 && git -C "$r" merge -q --ff-only origin/main < /dev/null >> "$log" 2>&1 || true
  done
}
gates() {  # $1: start or merge
  local open branch head origin
  open=$(scripts/upgrade-notice.sh open) || { say "REFUSED: the open pages not read"; return 1; }
  if [ -n "$open" ]; then
    say "REFUSED: a one-way failure's page is open ($(echo $open)) - its fix first, then: scripts/upgrade-notice.sh resolve <unit>"
    return 1
  fi
  if [ -e "$state/inflight" ] && tail -n 1 "$state/inflight" | grep -q ' verified$'; then
    say "REFUSED: the last apply verified, its record not pushed ($state/inflight) - task test:copy:inventory first (the record carries production's inventory after it), then push it (scripts/upgrade-record.sh) and remove the journal"
    return 1
  fi
  if [ -e "$state/inflight" ]; then
    # a run that stopped mid-apply with no page (killed outright, the machine off): paged now - its journal says how far
    unit=$(awk '$1 == "unit" {print $2; exit}' "$state/inflight")
    [[ $unit =~ ^[a-z0-9][a-z0-9.-]*$ ]] || unit=unknown-unit
    say "REFUSED: a run stopped mid-apply - its journal ($state/inflight):"; sed 's/^/  /' "$state/inflight" >> "$log"
    page "a run stopped mid-apply, found by the next run - its journal: $(tr '\n' ';' < "$state/inflight")"
    return 1
  fi
  branch=$(git -C "$ops" rev-parse --abbrev-ref HEAD 2> /dev/null)
  [ "$branch" = main ] || { say "REFUSED: ops is on '$branch', not main - its tasks are what applies"; return 1; }
  # the copy's build reads production's inventory into its record (tracked): that alone may differ
  [ -z "$(git -C "$ops" status --porcelain -- . ':!tests/ansible/copy/prod-inventory.txt' ':!tests/ansible/copy/pi-versions.yml' 2>&1)" ] \
    || { say "REFUSED: ops has changes not on main - its tasks are what applies"; return 1; }
  git -C "$ops" fetch -q origin main >> "$log" 2>&1 || { say "REFUSED: origin's main not read"; return 1; }
  head=$(git -C "$ops" rev-parse HEAD 2> /dev/null); origin=$(git -C "$ops" rev-parse origin/main 2> /dev/null)
  [ -n "$head" ] && [ "$head" = "$origin" ] || { say "REFUSED: ops is not origin's main (${head:0:12} here, ${origin:0:12} there)"; return 1; }
  if [ "$1" = start ]; then  # the copy mirrors the local mains (before the merge the base pin stands for them)
    mains_forward
    scripts/copy-main-current.sh ../infra ../platform >> "$log" 2>&1 \
      || { say "REFUSED: the local infra or platform main is not origin's (the copy mirrors them) - see the log"; return 1; }
  fi
  UPGRADE_VERIFY_SETTLE=0 UPGRADE_VERIFY_HOLD=0 scripts/upgrade-verify.sh < /dev/null >> "$log" 2>&1 \
    || { say "REFUSED: production is not settled and quiet now (see the log) - nothing applied on top of it"; return 1; }
  return 0
}
memory() {  # the copy must fit: the guard's own figure (22.5 GB of VMs + its 2 GB)
  local avail need=$(( 22528 + 2048 + 300 ))
  avail=$(awk '/^MemAvailable:/ {print int($2/1024)}' "${UPGRADE_MEMINFO:-/proc/meminfo}")
  [ "${avail:-0}" -ge "$need" ] || { say "REFUSED: memory - $avail of $need MB free: stop the radar (sudo systemctl stop radar-live) - or a copy left running (vagrant status; vagrant halt) - then run again"; return 1; }
}
if [ -n "$preflight" ]; then
  gates start && memory && { say "PREFLIGHT: a run may start"; exit 0; }
  exit 1
fi
gates start || exit 1
gate_head=$(git -C "$ops" rev-parse HEAD)  # what ops' main may hold at the merge: this, and the unit's own merge

# 1. the pick
picked=$(scripts/upgrade-units.py pick) || { say "NOT READ: Forgejo - the run changes nothing ($picked)"; exit 1; }
say "PICK $picked"
case "$picked" in
  NOTHING|PAUSED) exit 0 ;;
esac
read -r action unit kind <<< "$picked"
[[ $action =~ ^(test|prove)$ && $unit =~ ^[a-z0-9][a-z0-9.-]*$ && $kind =~ ^(patch|minor|major)$ ]] \
  || { say "REFUSED: the pick's answer '$picked'"; exit 1; }
[ "$action" != test ] || [[ $unit == test-* ]] || { say "REFUSED: a test action for '$unit' (no test- unit)"; exit 1; }
heads=$state/heads-$unit-$$
dirs=(); built=""
cleanup() {  # however the run ends: the copy halted when it was readied (the radar may start; its base snapshot kept
  # for the next run) and marked used - its Argo layer and this unit on it: no change or check until a run readies it -
  # the clones gone
  [ -z "$built" ] || run scripts/copy-snapshot.sh used || say "THE COPY NOT MARKED USED - task test:copy:drop by hand"
  [ -z "$built" ] || run vagrant halt || say "THE COPY NOT HALTED - the radar stays off: vagrant halt by hand"
  [ -n "$dry" ] || { chmod -R u+w "${dirs[@]}" 2> /dev/null; rm -rf "${dirs[@]}" "$heads" "$heads.after" "$heads.expected"; }
}
trap 'rc=$?; cleanup; console_end "$rc"' EXIT
tries_key=""
read_heads() {  # the unit's pull requests' heads and bases, "<repo> <number> <head> <base>" a line (into $1); the first
                # read names the pull requests a try is counted for (a later read that fails leaves the file empty)
  [ -n "$dry" ] && { say "RUN scripts/upgrade-label.py $unit --heads"; : > "$1"; return 0; }
  scripts/upgrade-label.py "$unit" --heads > "$1" 2>> "$log" || return 1
  [ -n "$tries_key" ] || tries_key=$(awk '{printf "%s%s#%s", (NR > 1 ? "," : ""), $1, $2}' "$1")
}
# each checkout's branch (fetch_unit's, the proof's own fetch) the head its pull request names: Forgejo's record of a
# pull request may lag its branch - the proof would prove one commit, the review and the merge another
branches_are_heads() {
  local repo head
  [ -z "$dry" ] || return 0
  while read -r repo _ head _ <&3; do
    [ "$(git -C "$(repo_dir "$repo")" rev-parse -q --verify "refs/heads/renovate/$unit" < /dev/null 2>> "$log")" = "$head" ] || return 1
  done 3< "$heads"
}
green() {  # every head's CI success - a running one waited for (an hour: Renovate's run just pushed it), a red one a
           # try (its third blocks), none at all a try (no pipeline started: a webhook lost - it never comes by itself);
           # hours of proof for a merge that refuses either are spent on nothing
  run scripts/upgrade-label.py "$unit" --green 3600
  case $? in
    0) ;;
    4) retry "its CI is red (the update breaking its own checks, or Woodpecker failing) - nothing proven" ;;
    5) retry "no CI on its heads after an hour (no pipeline started for them - a webhook lost?) - nothing proven" ;;
    *) still_running ;;
  esac
}
still_running() {  # its CI still running after an hour (Woodpecker's queue), or not read: no try - but the same heads so
                   # a run later are stuck, a try (the queue run after run behind one unit else)
  local key
  key=$(cut -d' ' -f1-3 "$heads" 2> /dev/null | tr '\n' ' ')
  if [ -n "$key" ] && [ "$(cat "$state/pending/$unit" 2> /dev/null)" = "$key" ]; then
    retry "its CI still not finished on the same heads a run later (stuck in Woodpecker) - nothing proven"
  fi
  [ -n "$dry" ] || { mkdir -p "$state/pending"; printf '%s' "$key" > "$state/pending/$unit"; }
  stopped "its CI still running after an hour (Woodpecker's queue), or not read - nothing proven, no try counted (the same heads so at the next run count one)" "$log"
  exit 1
}
# its branches on main as it stands but for CD's promotions (the proof refuses them else - never the unit's defect):
# Renovate rebases a branch only on a conflict, so the runner brings the unit it picked onto main itself - Forgejo's
# update (main merged into each pull request behind it), as the bot; what the unit changes stays
repo_dir() { case "$1" in schnappy/ops) echo "$ops" ;; *) echo "$ops/../${1#schnappy/}" ;; esac; }
fetch_unit() {  # the unit's branches into the local checkouts (the proof reads them there)
  local repo
  [ -z "$dry" ] || return 0
  for repo in $(cut -d' ' -f1 "$heads"); do
    git -C "$(repo_dir "$repo")" fetch -q origin main "+refs/heads/renovate/$unit:refs/heads/renovate/$unit" < /dev/null >> "$log" 2>&1 || return 1
  done
}
fresh() {
  local repo args=()
  [ -z "$dry" ] || { say "RUN scripts/copy-main-current.sh <the unit's branches>"; return 0; }
  for repo in $(cut -d' ' -f1 "$heads"); do args+=("$(repo_dir "$repo"):renovate/$unit"); done
  scripts/copy-main-current.sh "${args[@]}" < /dev/null >> "$log" 2>&1
}
# Forgejo shows an update of a pull request in a moment of its own: read until each head is its branch's tip
heads_updated() {
  local i repo tip ok
  for i in $(seq "${UPGRADE_HEADS_READS:-12}"); do
    [ "$i" = 1 ] || sleep "${UPGRADE_HEADS_WAIT:-10}"
    read_heads "$heads" || continue
    ok=1
    while read -r repo _ head _ <&3; do
      tip=$(git -C "$(repo_dir "$repo")" ls-remote origin "refs/heads/renovate/$unit" < /dev/null 2>> "$log" | cut -f1)
      [ -n "$tip" ] && [ "$tip" = "$head" ] || ok=""
    done 3< "$heads"
    [ -z "$ok" ] || return 0
  done
  return 1
}
fresh_or_end() {
  fetch_unit || { stopped "its branches not fetched (git: one checked out in a checkout of the operator's?) - nothing proven, no try counted" "$log"; exit 1; }
  if ! fresh; then
    run scripts/upgrade-label.py "$unit" --update || retry "its branches behind main, Forgejo's update refused (a conflict)"
    heads_updated || { stopped "its branches updated, Forgejo not showing the new heads yet - nothing proven, no try counted" "$log"; exit 1; }
  fi
  green
  fetch_unit || { stopped "its branches not fetched after their CI (git) - nothing proven, no try counted" "$log"; exit 1; }
  fresh || { stopped "main moved again while its CI ran (other work's pushes) - nothing proven, no try counted" "$log"; exit 1; }
  branches_are_heads || { stopped "its branches' tips not the heads its pull requests name (Forgejo's record behind its git) - nothing proven, no try counted" "$log"; exit 1; }
}

# a one-way change: Renovate's label (renovate/upgrade-cycle.json's rules) or its name a store's (the second net) - what
# its store needs before production, from scripts/upgrade-stores.json (scripts/upgrade-stores.py): the backups, run before
# the merge (one_way_backups, into the apply's pre-commands), or a part with none yet - blocked before anything is built,
# the message naming each (a vague "no backup path" told the operator nothing, 2026-11-17). A test environment's unit needs
# none (its data is no store to keep - the test environment is where a one-way change runs first). The labels or the
# table not read: nothing applied
unit_labels="" unit_store=""  # the one-way store the unit is (its fix may move that store's version alone)
one_way_backups=() one_way_taken=()
stop_if_one_way() {
  local labels line need judged=$unit
  labels=$(scripts/upgrade-units.py list) || { stopped "its labels not read from Forgejo - nothing applied" "$log"; exit 1; }
  line=$(awk -v u="$unit" '$1 == u' <<< "$labels")
  [ -n "$line" ] || { stopped "not in the open units any more - nothing applied" "$log"; exit 1; }
  [[ $line != *" UNLABELLED" ]] || { stopped "Renovate's labels not on it (its kind, its one-way mark not known) - nothing applied" "$log"; exit 1; }
  labels=$(awk '{print $4}' <<< "$line")
  unit_labels=$labels
  # a test environment's unit takes no backup, but runs only when its production twin could (one merged ahead of a twin
  # blocked for good left the test environment ahead of production - proving nothing after)
  [ "$action" != test ] || judged=${unit#test-}
  need=$(python3 -I scripts/upgrade-stores.py "$judged" "$labels" 2>> "$log") \
    || { stopped "what its one-way change needs not read (scripts/upgrade-stores.py, see the log) - nothing applied" "$log"; exit 1; }
  case "$need" in
    none) return 0 ;;
    store\ *)
      unit_store=$(awk 'NR == 1 {print $2}' <<< "$need")
      [ "$action" != test ] || { say "ONE-WAY $unit: its production twin's store can take it - no backup in the test environment"; return 0; }
      mapfile -t one_way_backups < <(sed -n 's/^backup //p' <<< "$need")
      mapfile -t one_way_taken < <(sed -n 's/^taken-by //p' <<< "$need")
      [ "$(( ${#one_way_backups[@]} + ${#one_way_taken[@]} ))" -gt 0 ] \
        || { stopped "a one-way change, its store's backups not read - nothing applied" "$log"; exit 1; }
      say "ONE-WAY $unit: ${need%%$'\n'*} - backed up before the merge: $(printf '%s; ' "${one_way_backups[@]}" "${one_way_taken[@]/#/its command }")"
      return 0 ;;
  esac
  retry "a one-way change its store cannot take yet$([ "$judged" = "$unit" ] || echo " (its production twin $judged's)") - $(awk '{sub(/^(missing|unknown) /, ""); printf "%s%s", (NR > 1 ? "; " : ""), $0}' <<< "$need") (scripts/upgrade-stores.json - ops' to fix) - nothing applied"
}
held_now() {  # a veto or the kill switch set since the pick: refused, nothing merged
  local held
  held=$(scripts/upgrade-units.py held "$unit") || { stopped "whether it is held not read - nothing merged" "$log"; exit 1; }
  [ -z "$held" ] || { stopped "held since its pick ($(echo $held)) - nothing merged" "$log"; exit 1; }
}
# what the run cannot take further - a failure, a finding its fixes did not clear, a refusal before anything is built:
# said (never mailed), a try recorded for the unit's pull requests (the same name later is another unit). There is no
# blocked state (operator 2026-11-20): the next pick takes the units with no try first (scripts/upgrade-units.py), so
# one that keeps failing never holds the queue, and is taken up again once the others are through; a cause in ops is
# mine to fix at once. A run that gets the unit further (applied, the test environment's merged) clears them
retry() {
  local n key
  [ -n "$tries_key" ] || read_heads "$heads.key" || say "its pull requests not read - the try recorded without them"
  key=${tries_key:-none}
  [ -n "$dry" ] || { mkdir -p "$state/tries"; echo "$key $(date -u +%FT%TZ) $1" >> "$state/tries/$unit"; }
  n=$(awk -v k="$key" '$1 == k' "$state/tries/$unit" 2> /dev/null | wc -l)
  stopped "$1 - the next run takes the units with no try first (this one's try ${n:-1})" "${2:-$log}"
  exit 1
}
progress() { [ -n "$dry" ] || rm -f "$state/tries/$unit" "$state/pending/$unit"; }
# the apply's journal: what a run that stops mid-apply leaves for the next one (and the operator) - how far it got
journal() { [ -n "$dry" ] || echo "$(date -u +%FT%TZ) $*" >> "$state/inflight"; }
start_journal() {
  # from here a closed terminal stops nothing: the merge and the commands finish, or page (an interrupt or a kill does)
  trap '' HUP
  [ -n "$dry" ] || printf 'unit %s\nlog %s\nheads %s\nsnapshot %s\nstarted %s\n' "$unit" "$log" "$(tr '\n' ';' < "$heads")" \
    "$(grep -o 'etcd-backup OK: [^ ]*' "$log" 2> /dev/null | tail -n 1 | cut -d' ' -f3)" "$(date -u +%FT%TZ)" > "$state/inflight"
}
merged=""
merge() {  # the unit merged at the proven heads onto the proven bases - nothing in: blocked; part in, or not known: paged
  if [ -z "$dry" ] && ! { git -C "$ops" fetch -q origin main < /dev/null >> "$log" 2>&1 && [ "$(git -C "$ops" rev-parse origin/main)" = "$gate_head" ]; }; then
    rm -f "$state/inflight"
    stopped "ops' main moved since the gate (or not read) - nothing merged, the next run proves it again" "$log"; exit 1
  fi
  merged=1  # from the call on a stop pages: it may have gone in
  journal "merge asked"
  run scripts/upgrade-label.py "$unit" --merge --expect "$heads"
  case $? in
    0) journal "merged: $(grep '^MERGED ' "$log" 2> /dev/null | cut -d' ' -f2 | tr '\n' ' ')" ;;
    1) merged=""; [ -n "$dry" ] || rm -f "$state/inflight"
       stopped "its merge refused - nothing merged" "$log"; exit 1 ;;
    *) page "partly merged, or not known whether (the merge ended $?) - half the unit may apply (see the log: what went in)"; exit 1 ;;
  esac
  # ops to origin's main (a pull follows the operator's pull.rebase): the record commits on it, the commands run from it -
  # origin's main the gate's plus the unit's own merge alone (anything else pushed since would run unreviewed)
  run git -C "$ops" fetch -q origin main || { page "merged, origin's ops main not read - what follows the merge not run"; exit 1; }
  if [ -z "$dry" ]; then
    local opshead extra
    opshead=$(awk '$1 == "schnappy/ops" {print $3}' "$heads")
    extra=$(git -C "$ops" rev-list origin/main --not "$gate_head" ${opshead:+"$opshead"} 2>> "$log")
    if [ -n "$opshead" ]; then
      [ "$(wc -l <<< "$extra")" = 1 ] && [ "$(git -C "$ops" rev-parse "$extra^1" 2>> "$log")" = "$gate_head" ] \
        && [ "$(git -C "$ops" rev-parse "$extra^2" 2>> "$log")" = "$opshead" ] \
        || { page "merged, ops' main holds more than the unit's merge ($(echo $extra | cut -c1-80)) - what follows not run"; exit 1; }
    elif [ -n "$extra" ]; then
      page "merged, ops' main moved since the gate ($(echo $extra | cut -c1-80)) - what follows not run"; exit 1
    fi
  fi
  run git -C "$ops" merge -q --ff-only origin/main || { page "merged, ops not brought to origin's main - what follows the merge not run"; exit 1; }
}
# a run stopped during or after its merge (an interrupt, a kill): paged, never silent
on_signal() {
  [ -z "$merged" ] || page "the run was stopped during or after its merge - what follows it may not have run"
  exit 1
}
trap on_signal HUP INT TERM
# the merge's commits on infra's and platform's main, for the unit's parts there: what Argo must have synced
revisions() {
  local repo revs="" sha
  [ -z "$dry" ] || { say "RUN git ls-remote origin refs/heads/main (infra, platform: the merge's commits)"; return 0; }
  for repo in infra platform; do
    grep -q "^schnappy/$repo " "$heads" 2> /dev/null || continue
    sha=$(git -C "$ops/../$repo" ls-remote origin refs/heads/main 2>> "$log" | cut -f1)
    [[ $sha =~ ^[0-9a-f]{40}$ ]] || { say "the merge's commit on $repo's main not read"; return 1; }
    revs+="$repo=$sha "
  done
  echo "${revs% }"
}

test_only() {  # $1: verify's output - every line it complains of placed in the test environment
  python3 -I - "$1" <<'PY'
import re, sys
lines = [l for l in open(sys.argv[1]).read().splitlines()
         # verify's own headers, and its progress lines (each its time first: what a look found then, said again at its end)
         if l.strip() and not re.match(r"(SETTLED|NOT SETTLED|NOT QUIET)\b|\d\d:\d\d:\d\d ", l)]
test = [l for l in lines if re.match(r"(app schnappy-test(-[^ ]+)? |pod schnappy-test(-[^/ ]+)?/)", l)]
root = [l for l in lines if l.startswith("app root ")]
sys.exit(0 if lines and test and len(test) + len(root) == len(lines) else 1)
PY
}
# a test environment's unit: the copy leaves the test environment out - it is its own proof (the test environment before
# production): no copy, no review, no backup (its data is no store to keep); merged at the heads judged, settled, recorded
if [ "$action" = test ]; then
  stop_if_one_way
  read_heads "$heads" || { stopped "its pull requests not read - nothing merged" "$log"; exit 1; }
  green
  held_now
  start_journal
  merge
  revs=$(revisions) || { page "merged, the merge's commits not read - its verify not run"; exit 1; }
  vout=$ops/.copy/upgrade-verify-$unit-$$.txt
  say "RUN scripts/upgrade-verify.sh (the test environment's merge)"
  # its lines in the log (so on the console) as they come - its progress too -, and in $vout for test_only's reading
  if [ -z "$dry" ] && ! UPGRADE_VERIFY_REVISIONS="$revs" scripts/upgrade-verify.sh < /dev/null 2>&1 9>&- | tee "$vout" >> "$log" 9>&-; then
    # the test environment's charts can carry what reaches beyond it: anything not placed in it pages - an app of its
    # own (root aside, when it is its children that are not settled), a pod in its namespaces; a critical alert, a read
    # that failed, anything else: production's
    if ! test_only "$vout"; then
      page "merged to the test environment, production not settled after it (see the log)"; exit 1
    fi
    # its production twin behind the others (a try of its own): the test environment not settled is no proof for it -
    # its own proof on the copy still gates production; the test environment is mine to fix at once
    rm -f "$state/inflight"  # the test environment's: production untouched
    [ -n "$dry" ] || { mkdir -p "$state/tries"; echo "test-environment $(date -u +%FT%TZ) its test unit $unit merged, the test environment not settled after it" >> "$state/tries/${unit#test-}"; }
    stopped "merged to the test environment, it not settled after it - its production unit ${unit#test-} behind the others" "$log"
    exit 1
  fi
  journal "verified"
  run scripts/upgrade-record.sh "$unit" "$log" \
    || { stopped "applied and verified, not recorded - push the record, then remove $state/inflight" "$log"; exit 1; }
  [ -n "$dry" ] || rm -f "$state/inflight"
  progress
  say "APPLIED $unit: the test environment's, verified - its production unit next"
  exit 0
fi

# release notes are no gate (operator 2026-11-25: a unit without them is never left out): Renovate fetches them where
# it can, and the review's compatibility pass judges each version moved by what it has - its notes, else the version
# rules and what the clones hold (review.md)
memory || exit 1
stop_if_one_way

# clones of the unit's proven commits - the agents' working directory, outside every checkout (a commit there never
# lands in the operator's tree)
clones() {  # into $1, one per repo of the unit (from $heads), each on renovate/<unit> at its proven head
  local dir=$1 repo n sha
  dirs+=("$dir")
  [ -n "$dry" ] && { say "RUN clones of renovate/$unit into $dir"; return 0; }
  rm -rf "$dir"; mkdir -p "$dir"
  while read -r repo n sha _ <&3; do
    [ -n "$repo" ] || continue
    bot_git clone -q "$forgejo/$repo.git" "$dir/${repo#*/}" < /dev/null >> "$log" 2>&1 9>&- || return 1
    git -C "$dir/${repo#*/}" checkout -q -B "renovate/$unit" "$sha" < /dev/null >> "$log" 2>&1 || return 1
  done 3< "$heads"
}
# the review's context: each repository the unit does not touch, at main, in $1/context/<repo> (one commit deep) - with
# the unit's own clones, all three repos: production's inventory (ops' tests/ansible/copy/prod-inventory.txt) and every
# other pin of a dependency the unit moves (one version everywhere) are read there - the review reads nothing outside
context_clones() {
  local dir=$1 repo
  [ -n "$dry" ] && { say "RUN context clones (the repos renovate/$unit does not touch, at main) into $dir/context"; return 0; }
  mkdir -p "$dir/context"
  for repo in schnappy/infra schnappy/platform schnappy/ops; do
    awk -v r="$repo" '$1 == r {f = 1} END {exit !f}' "$heads" && continue
    bot_git clone -q --depth 1 "$forgejo/$repo.git" "$dir/context/${repo#*/}" < /dev/null >> "$log" 2>&1 9>&- || return 1
  done
}
# beside each clone in $1: <repo>.diff and <repo>.commits, the unit's diff and commits against main - the review's
# reviewers read them with Read alone (their Bash is plain read-only git, one command a call: a reviewer's `cd <path>`
# then `git diff`, or a loop over `git -C`, is refused - the first unattended review, 2026-11-17, had its reviewers read
# platform's and ops' files at HEAD instead of the diff); --text: a file git takes for binary shown whole, never "Binary
# files differ" (a NUL or a stray encoding hiding a key from the review)
diffs() {
  local dir=$1 repo r
  while read -r repo _ <&3; do
    [ -n "$repo" ] || continue
    r=$dir/${repo#*/}
    git -C "$r" diff --text --no-ext-diff --no-textconv --no-color origin/main...HEAD > "$r.diff" 2>> "$log" < /dev/null || return 1
    git -C "$r" log --no-color --format='%h %an <%ae> %s' origin/main..HEAD > "$r.commits" 2>> "$log" < /dev/null || return 1
  done 3< "$heads"
}
# what the agent may change in each repo: the unit's own kind of files - never CI, scripts, tasks, the trust files or an
# agent's instructions (each would run, or steer a later run, unproven); of platform's charts their values alone - a
# template, a subchart or a chart's files/ is code, a Chart.yaml's dependency another chart, and what the agent writes
# reaches production in the run that proves it (no notice since 2026-11-21)
allowed() {  # allowed <repo> <path>
  case "$2" in
    */CLAUDE.md|CLAUDE.md|*/AGENTS.md|AGENTS.md|.claude/*|*/.claude/*|.woodpecker/*|.gitattributes|*/.gitattributes|.gitmodules|renovate.json) return 1 ;;
  esac
  # anchored: a case pattern's * crosses '/' (helm/x/ci/values.yaml, playbooks/tasks/*.yml, vars/vault-recovery/* got in)
  case "$1" in
    schnappy/infra) [[ $2 =~ ^clusters/[^[:space:]]+\.ya?ml$ ]] ;;
    schnappy/platform) [[ $2 =~ ^helm/[^/]+/values[^/]*\.yaml$ ]] ;;
    schnappy/ops) [[ $2 =~ ^deploy/ansible/(vars|playbooks)/[^/]+\.yml$ ]] ;;
    *) return 1 ;;
  esac
}
# a file of the agent's - its fix applies in the run that proves it, steered by upstream release notes no human read:
# UTF-8, each line it adds printable ASCII and tab, and judged on the parsed YAML - versions moved, an image's tag, a value
# renamed or dropped outside security paths, nothing new, no store but the unit's own (scripts/upgrade-fix-judge.py says
# what, and why each is refused, in the log)
plain_fix() {  # plain_fix <repository> <proven> <tip> <path> - judged on the parsed YAML (scripts/upgrade-fix-judge.py)
  FIX_STORE=$unit_store FIX_STORES_TABLE=$ops/scripts/upgrade-stores.json python3 -I "$ops/scripts/upgrade-fix-judge.py" "$@"
}
# the agent's commits, checked, pushed by the runner: fetched from its clone into a repository of the runner's own (its
# hooks and config - the agent's - never run), on top of the proven head, inside allowed(), their tree pushed as one
# commit of the runner's on the proven head - every repo judged before
# any is pushed (half a fix pushed, unlabelled, was a fix with no record of who wrote it); the unit labelled agent-fixed
# (and stop-updating: Renovate never rewrites the fixed branches) before the first push; pushed as the bot to Forgejo's URL
# itself; their diff kept on record (.upgrade-cycle/fixes). The heads file read on a descriptor of its own: nothing in the loop reads it away
fixed=""
push_fix() {
  local dir=$1 repo n sha clone mirror tip bad raw
  local -a push=()
  pushed=""  # this call's fix pushed (fixed: any of the run's)
  : > "$fixdiff"; : > "$fixdiff.stat"
  : > "$heads.expected"
  while read -r repo n sha _ <&3; do
    clone=$dir/${repo#*/}; mirror=$dir.push/${repo#*/}
    tip=$sha
    [ -d "$clone" ] || { say "the agent's clone of $repo is gone - not pushed"; return 1; }
    rm -rf "$mirror"; git init -q --bare "$mirror" < /dev/null
    git -C "$mirror" -c fetch.fsckObjects=true fetch -q --no-tags "$clone" "+refs/heads/renovate/$unit:refs/fix" < /dev/null >> "$log" 2>&1 \
      || { say "the fix left $repo without its branch renovate/$unit - not pushed"; return 1; }
    tip=$(git -C "$mirror" rev-parse refs/fix < /dev/null)
    if [ "$tip" != "$sha" ]; then
      git -C "$mirror" merge-base --is-ancestor "$sha" "$tip" < /dev/null || { say "the fix rewrote $repo's proven commit - not pushed"; return 1; }
      [ -z "$(git -C "$mirror" rev-list --merges "$sha..$tip" < /dev/null)" ] || { say "the fix holds a merge commit in $repo - nothing pushed"; return 1; }
      # each file: both sides of a rename (a script moved into clusters/ is a script gone from its place), a plain file
      # changed in place - no symlink (followed by whatever reads the tree unsandboxed), no submodule (another repo), no file
      # of its own (a new manifest, a new Argo application) and none deleted (a NetworkPolicy, a PeerAuthentication gone)
      # the files read, or nothing pushed (a failed diff listed none: the tree went up unjudged)
      raw=$(git -C "$mirror" diff --raw --no-renames "$sha" "$tip" < /dev/null) && [ -n "$raw" ] \
        || { say "the fix's files not read in $repo (its tip moved, its diff empty or failed) - nothing pushed"; return 1; }
      bad=$(while IFS=$'\t' read -r meta f; do
              mode=$(cut -d' ' -f2 <<< "$meta"); status=$(cut -d' ' -f5 <<< "$meta")
              { [[ $mode =~ ^(100644|100755)$ ]] && [ "$status" = M ] && allowed "$repo" "$f" \
                && plain_fix "$mirror" "$sha" "$tip" "$f" < /dev/null 2>> "$log"; } || echo "$f"
            done <<< "$raw")
      [ -z "$bad" ] || { say "the fix changed what it may not in $repo: $(echo $bad) - nothing pushed"; return 1; }
      { echo "=== $repo"; git -C "$mirror" diff --stat --no-ext-diff --no-textconv --no-color --no-renames "$sha" "$tip"; } < /dev/null >> "$fixdiff.stat"
      { echo "=== $repo"; git -C "$mirror" log --format='%h %s' "$sha..$tip" | LC_ALL=C tr -c '[:print:]\n' '?' | cut -c1-200
        git -C "$mirror" diff --text --no-ext-diff --no-textconv --no-color --no-renames "$sha" "$tip"; } < /dev/null >> "$fixdiff"
      # pushed as one commit of the runner's on the proven head - its tree the one judged: the agent's own commits (a
      # step in between with files it may not touch, its words - a closing keyword on the dashboard -, an author
      # it chose) never reach Forgejo
      tip=$(env GIT_AUTHOR_NAME="Upgrade Fix Agent" GIT_AUTHOR_EMAIL=upgrade-fix@pmon.dev GIT_COMMITTER_NAME="Upgrade Fix Agent" \
              GIT_COMMITTER_EMAIL=upgrade-fix@pmon.dev git -C "$mirror" commit-tree "$tip^{tree}" -p "$sha" \
              -m "upgrade-fix: renovate/$unit - the agent's fix, judged and committed by the upgrade runner" < /dev/null) \
        || { say "the fix's commit not made in $repo - nothing pushed"; return 1; }
      push+=("$repo $tip")
    fi
    echo "$repo $n $tip" >> "$heads.expected"
  done 3< "$heads"
  [ "${#push[@]}" -gt 0 ] || return 0
  # the fix on record before anything is pushed (.upgrade-cycle/fixes - its commit is on the pull requests too) - every repo's
  # stat first, then each commit and diff (appended: a second fix recorded with the first)
  if [ -z "$dry" ]; then
    mkdir -p "$state/fixes"
    # a unit of this name fixed before (applied, closed) is not this one: its record starts again
    [[ ,$unit_labels, == *,agent-fixed,* ]] || : > "$state/fixes/$unit.diff"
    { echo "=== the agent's fix of renovate/$unit, $(date -u +%FT%TZ) - files:"; cat "$fixdiff.stat"; cat "$fixdiff"; } >> "$state/fixes/$unit.diff"
  fi
  run scripts/upgrade-label.py "$unit" agent-fixed || { say "NOT LABELLED agent-fixed - nothing pushed: what the agent wrote would carry no mark of it"; return 1; }
  run scripts/upgrade-label.py "$unit" stop-updating || { say "NOT LABELLED stop-updating - nothing pushed: Renovate would rewrite the fixed branches"; return 1; }
  unit_labels+=",stop-updating"
  fixed=1 pushed=1  # labelled: from here a push that went in is on the unit's pull requests, whatever follows
  for p in "${push[@]}"; do
    read -r repo tip <<< "$p"
    run bot_git -C "$dir.push/${repo#*/}" -c core.hooksPath=/dev/null push -q "$forgejo/$repo.git" "$tip:refs/heads/renovate/$unit" \
      || { say "the fix's push to $repo refused (the unit labelled agent-fixed: what went in is reviewed again before any apply)"; return 1; }
  done
}
# Forgejo shows a push to a pull request in a moment of its own: read until the heads are the ones pushed
heads_pushed() {
  local i
  [ -n "$dry" ] && { say "RUN scripts/upgrade-label.py $unit --heads (until it shows the fix)"; return 0; }
  for i in $(seq "${UPGRADE_HEADS_READS:-12}"); do
    [ "$i" = 1 ] || sleep "${UPGRADE_HEADS_WAIT:-10}"
    read_heads "$heads" || continue
    cmp -s <(cut -d' ' -f1-3 "$heads") "$heads.expected" && return 0
  done
  return 1
}

# 2. the proof, one fix - the copy as built (its base snapshot reverted when fresh, else built and snapshotted), halted
# when the run ends, however it ends (the radar may start again)
build() { built=1; run task test:copy:ready || { say "COPY NOT READY - the unit untouched (see the log); run again"; exit 1; }; }
# the unit's plan read before the copy is built: a part the proof cannot take (an ops value copy-unit.sh has no proof for -
# Keycloak's; Consul's has its own since 2026-11-18) refused now - a try, the parts named, nothing built and no agent: the refusal is
# ops' to fix, never the unit's (it was built 49 min, refused, and handed to the fix agent as red - 2026-11-17's review)
preplan() {
  local out
  [ -z "$dry" ] || { say "RUN task test:copy:unit UNIT=$unit PLAN=true (before the build)"; return 0; }
  out=$(task test:copy:unit UNIT="$unit" PLAN=true 2>&1 < /dev/null 9>&-) && { printf '%s\n' "$out" >> "$log"; return 0; }
  printf '%s\n' "$out" >> "$log"
  if grep -q '^REFUSED:' <<< "$out"; then
    retry "the copy cannot prove it - $(grep -m1 '^REFUSED:' <<< "$out" | cut -c10-400) (scripts/copy-unit.sh's proof paths - ops' to fix) - nothing built"
  fi
  stopped "its plan not read before the build (see the log) - nothing built, no try counted" "$log"
  exit 1
}
read_heads "$heads" || { stopped "its pull requests not read - nothing proven" "$log"; exit 1; }
fresh_or_end
preplan
build
# the agent's fix - a red proof's, or the review's findings (3.); two at most a run: each judged and pushed by the
# runner, its CI green, the unit proven again on a base built fresh (the two proofs never share one base: a defect of
# the base read as the unit's twice). What it cannot take further is a try (retry) - the next run takes it up
fixes=0
fix_unit() {  # fix_unit <what it fixes> <the file the agent reads> <its name there> <the agent's task>
  local what=$1 input=$2 name=$3 task=$4 fixdir rc why
  [ "$fixes" -lt "${UPGRADE_FIX_ROUNDS:-2}" ] || retry "$what - this run's fixes spent (${UPGRADE_FIX_ROUNDS:-2})" "$input"
  fixes=$((fixes + 1))
  say "$what: $unit - handed to the fix agent (fix $fixes)"
  fixdir=$work/$unit-fix-$$-$fixes; fixdiff=$ops/.copy/upgrade-fix-$unit-$$-$fixes.diff; fixout=$ops/.copy/upgrade-fix-$unit-$$-$fixes.txt
  clones "$fixdir" || retry "$what; its branches not cloned for the agent - no fix"
  dirs+=("$fixdir.push")
  if [ -z "$dry" ]; then
    cp "$input" "$fixdir/$name"
    (cd "$fixdir" && timeout "$agent_timeout" "${clean_env[@]}" "$agent" -p "upgrade-cycle fix: the unit renovate/$unit $task Follow the upgrade-fix instructions: the unit's branches are cloned here (one directory per repo); commit one fix in each repo it needs. Do not push - the runner does." "${fix_flags[@]}") < /dev/null > "$fixout" 2>&1 9>&-
    rc=$?
    cat "$fixout" >> "$log"
    [ "$rc" = 0 ] || say "the fix agent ended $rc - its commits, if any, are checked all the same"
    push_fix "$fixdir" || retry "$what; its fix not pushed (see the log)"
    # no commit: the agent's NO FIX (a defect of the new version, or a cause outside the unit's files - ops' own,
    # mine to fix), or an agent that did not finish (a limit, a timeout)
    if [ -z "$pushed" ]; then
      why=$(grep -m1 '^NO FIX: ' "$fixout" | cut -c1-300)
      retry "$what; no fix${why:+ - $why}"
    fi
  else
    say "RUN $agent -p <the fix of renovate/$unit: $what>"
    say "RUN the agent's commits checked and pushed"
  fi
  heads_pushed || retry "its fix pushed, Forgejo not showing it on its pull requests"
  green  # the fix's own CI
  run scripts/copy-snapshot.sh forget "the proof after a fix builds its base fresh" || say "THE SNAPSHOT NOT FORGOTTEN - the proof may revert it"
  build
}
# what the unit moves ("<package> <from> <to>", its Renovate tables): the copy's inventory after the change must show
# production's lines of it at the new version (scripts/copy-change-inventory.sh, test:copy:check's last step)
prove() {
  local moves="$ops/.copy/unit-moves-$unit.txt"
  [ -n "$dry" ] || scripts/upgrade-units.py moves "$unit" > "$moves" 2>> "$log" \
    || { stopped "what the unit moves not read - nothing proven" "$log"; exit 1; }
  COPY_UNIT_MOVES="$moves" run task test:copy:unit UNIT="$unit"
}
# what was proven is what is reviewed and merged: the heads after each proof the ones read before it
proven_heads() {
  read_heads "$heads.after" || { stopped "its pull requests not read after its proof - nothing applied" "$log"; exit 1; }
  if ! { cmp -s <(cut -d' ' -f1-3 "$heads") <(cut -d' ' -f1-3 "$heads.after") && branches_are_heads; }; then
    stopped "its branches moved during its proof - nothing applied (the next run proves them)" "$log"; exit 1
  fi
}
if ! prove; then
  fix_unit "red" "$log" proof.log "failed its proof on the Vagrant copy (its log: proof.log here) - diagnose from the log."
  prove || retry "red after its fix"
fi
proven_heads

# 3. the review - from clones of the proven commits: CLEAN is no finding at all, every pass named; any finding goes to
# the agent's fix, then the unit is proven and reviewed again
review_unit() {  # 0: clean; 1: findings (in $review); a review that did not finish ends the run (a try)
  local rc verdict passes missing reviewers p
  review=$ops/.copy/upgrade-review-$unit-$(date +%s)-$$-$fixes.txt
  revdir=$work/$unit-review-$$-$fixes
  say "RUN $agent -p <the review of renovate/$unit>"
  [ -z "$dry" ] || return 0
  reviewers=$(reviewers_json 2>> "$log") || { stopped "the reviewers' definitions not read - not reviewed, nothing applied" "$log"; exit 1; }
  clones "$revdir" || { stopped "its branches not cloned for the review - nothing applied" "$log"; exit 1; }
  diffs "$revdir" || { stopped "its diffs not written for the review - nothing applied" "$log"; exit 1; }
  context_clones "$revdir" || { stopped "the other repos not cloned for the review's context - nothing applied" "$log"; exit 1; }
  # Renovate's tables and release notes (its pull requests' bodies) beside them - what the compatibility pass reads
  scripts/upgrade-units.py bodies "$unit" "$revdir" >> "$log" 2>&1 || { stopped "its pull requests' bodies not read for the review - nothing applied" "$log"; exit 1; }
  # what production runs NOW - the inventory test:copy:ready read this run (ops' committed copy may be older): the
  # compatibility pass judges each version moved against it
  cp -- "$ops/tests/ansible/copy/prod-inventory.txt" "$ops/tests/ansible/copy/pi-versions.yml" "$revdir/" 2>> "$log" \
    || { stopped "production's inventory not handed to the review - nothing applied" "$log"; exit 1; }
  (cd "$revdir" && timeout "$agent_timeout" "${clean_env[@]}" "$agent" -p "upgrade-cycle review: review the unit renovate/$unit - its diff in each repo cloned here (one directory per repo, its diff against origin/main in <repo>.diff, its commits in <repo>.commits and its pull request's body - Renovate's table and release notes - in <repo>.pr.md beside it; what production runs now in prod-inventory.txt and pi-versions.yml; the repos it does not touch at main in context/) - as the review instructions say. A version left elsewhere that the fix agent cannot move goes on a 'NOTE: <where> - <what>' line, never a FINDING. Each finding, whatever its severity, on a line of its own: 'FINDING: <critical|warning|suggestion> <where> - <what>'. End with two lines: 'PASSES: <the passes that ran, comma-separated>' and 'VERDICT: CLEAN' (no finding at all) or 'VERDICT: FINDINGS <how many>'. Change nothing." \
     --restricted --tools "Bash,Read,Glob,Grep,Agent,Skill" --agents "$reviewers" \
     --append-system-prompt-file "$ops/.claude/upgrade-agent/review.md" --settings "$ops/.claude/upgrade-agent/review.json" \
     --strict-mcp-config --permission-mode dontAsk --permission-prompts none) < /dev/null > "$review" 2>&1 9>&-
  rc=$?
  cat "$review" >> "$log"
  # the review's notes - stragglers the fix agent cannot reach (another repo, tests/, a CI image, a digest): said on the
  # terminal and kept in the record, aligned in ops by hand; they never hold the unit. Text the review wrote from upstream
  # release notes: printable alone (an escape sequence never reaches the terminal or the committed record), cut short
  grep -E '^NOTE: ' "$review" | head -50 | LC_ALL=C tr -c '[:print:]\n' '?' | cut -c1-300 \
    | while IFS= read -r note; do say "REVIEW $note"; done
  # a request the review refused (a release note asking for a resource, a permission, another source): the unit ends
  # here, a try - never handed to the fix agent as a task. A line refusing nothing ('REFUSE: none', 'n/a', '-') is no
  # refusal: the observability review wrote one beside its findings (2026-11-25) and the unit ended as refused
  refusal=$(grep -E '^REFUSE: ' "$review" | grep -viE '^REFUSE:[[:space:]]*(none|nothing|n/?a|-)[.]?[[:space:]]*$' | head -1)
  if [ -n "$refusal" ]; then
    retry "its review refused it: $(printf '%s' "$refusal" | LC_ALL=C tr -c '[:print:]' '?' | cut -c9-200)" "$review"
  fi
  verdict=$(grep -E '^VERDICT: ' "$review" | tail -1)
  passes=$(grep -E '^PASSES: .+' "$review" | tail -1)
  missing=""
  for p in $REVIEW_PASSES; do tr ',' '\n' <<< "${passes#PASSES: }" | sed 's/^ *//; s/ *$//' | grep -qxi "$p" || missing+=" $p"; done
  # any finding, whatever its severity - a later CLEAN never takes one back
  if grep -qE '^(FINDING: |VERDICT: (FINDINGS|CRITICAL))' "$review"; then
    say "FINDINGS $unit: $(grep -cE '^FINDING: ' "$review") - $(grep -m1 -E '^(FINDING: |VERDICT: (FINDINGS|CRITICAL))' "$review" | cut -c1-200)"
    return 1
  fi
  if [ "$rc" -ne 0 ] || [ "$verdict" != "VERDICT: CLEAN" ] || [ -n "$missing" ]; then
    retry "its review did not finish (${verdict:-no verdict}; passes missing:${missing:- none}; exit $rc)" "$review"
  fi
  return 0
}
while ! review_unit; do
  fix_unit "its review's findings" "$review" review.txt "was proven on the Vagrant copy, and its review found what review.txt here lists (its FINDING lines) - fix every one you can within the unit's own files; one you cannot (it lies outside them), name on a NO FIX line."
  prove || retry "red after the fix of its review's findings"
  proven_heads
done

# proven and reviewed: the copy halted now (its snapshot kept for the next run) - the radar may start, the apply needs none of it
copy_gone="the copy halted: the radar may start"
run scripts/copy-snapshot.sh used || say "THE COPY NOT MARKED USED - task test:copy:drop by hand"
if run vagrant halt; then built=""; else copy_gone="THE COPY NOT HALTED - the radar stays off"; say "$copy_gone"; fi

# 5. the plan: its production commands, every one known and its version one - or the unit refused, nothing merged
if [ -n "$dry" ]; then
  say "RUN task test:copy:unit UNIT=$unit PLAN=true"; plan=""
else
  plan=$(task test:copy:unit UNIT="$unit" PLAN=true 2>> "$log" 9>&- | grep -E '^test:copy:') \
    || { stopped "its plan not read - nothing applied" "$log"; exit 1; }
fi
pre=(); cmds=()
version_of() {  # the value of $1= in the step, a version or nothing
  local v
  v=$(sed -n "s/.*$1=\([^ ']*\).*/\1/p" <<< "$2")
  [[ $v =~ ^[0-9][0-9A-Za-z.+~-]*$ ]] && echo "$v"
}
while IFS= read -r step; do
  [ -n "$step" ] || continue
  case "$step" in
    "test:copy:playbook PLAYBOOK=upgrade-kubeadm.yml"*)
      v=$(version_of k8s_upgrade_to "$step") || { stopped "no Kubernetes version in its plan ($step) - nothing merged" "$log"; exit 1; }
      pre+=("deploy:etcd:backup"); cmds+=("deploy:kubeadm:upgrade -- -e k8s_upgrade_to=$v") ;;
    "test:copy:playbook PLAYBOOK=setup-kubeadm.yml"*)
      v=$(version_of cilium_version "$step") || { stopped "no Cilium version in its plan ($step) - nothing merged" "$log"; exit 1; }
      cmds+=("deploy:cilium:upgrade -- -e cilium_version=$v") ;;
    "test:copy:playbook PLAYBOOK=setup-argocd.yml"*) cmds+=("deploy:argocd") ;;
    "test:copy:playbook PLAYBOOK=setup-host-hardening.yml"*) cmds+=("deploy:host-hardening") ;;
    "test:copy:playbook PLAYBOOK=upgrade-patroni.yml"*) cmds+=("deploy:patroni:upgrade") ;;
    "test:copy:playbook PLAYBOOK=upgrade-consul.yml"*) cmds+=("deploy:consul:upgrade") ;;
    "test:copy:playbook PLAYBOOK=upgrade-vault.yml"*) cmds+=("deploy:vault:upgrade") ;;
    "test:copy:playbook PLAYBOOK=upgrade-forgejo.yml"*) cmds+=("deploy:forgejo:upgrade") ;;
    "test:copy:playbook PLAYBOOK=setup-caddy.yml"*) cmds+=("deploy:caddy") ;;  # it installs the version pinned
    "test:copy:playbook PLAYBOOK=upgrade-keycloak.yml"*) cmds+=("deploy:keycloak:upgrade") ;;  # its dump first, both Pis stopped, the VIP's first (plan 122)
    "test:copy:playbook PLAYBOOK=restart-mesh-workloads.yml"*)  # every sidecar on istiod's version - Argo applied it first
      v=$(version_of istio_version "$step") || { stopped "no Istio version in its plan ($step) - nothing merged" "$log"; exit 1; }
      cmds+=("deploy:mesh:restart -- -e istio_version=$v") ;;
    "test:copy:change"*) continue ;;  # Argo applies infra's and platform's merge
    "test:copy:renovate-image"*) continue ;;  # Renovate's image: no production command - the next Renovate run uses it
    *) stopped "a part with no production command: $step - nothing merged" "$log"; exit 1 ;;
  esac
done <<< "$plan"
stop_if_one_way
pre+=("${one_way_backups[@]}")  # a one-way store's backups, after the plan's own (an etcd snapshot) - each before the merge, the order theirs alone
for c in "${one_way_taken[@]}"; do  # a store whose backup its own command takes: that command in the plan, or nothing
  printf '%s\n' "${cmds[@]}" | grep -qx -- "$c" \
    || { stopped "a one-way change whose backup its command takes ($c) - not in its plan; nothing merged" "$log"; exit 1; }
done
# what production runs only as an Argo hook - k6, schnappy-production-apps' PostSync smoke test: Argo leaves hooks out of
# its diff, so the apply alone never runs the new version (production met it at the next unrelated sync, a failure
# failing that deploy - the observability review, 2026-11-25). Its app synced after the apply, the hook to succeed
if grep -q '^grafana/k6 ' "$ops/.copy/unit-moves-$unit.txt" 2> /dev/null; then
  cmds+=("deploy:argo:sync -- -e argo_app=schnappy-production-apps")
fi

# 6. the apply - the gates again (hours since the start), the backups a one-way change needs, still free, a journal
gates merge || { stopped "proven and reviewed, not applied: a gate refused it now (see the log) - the next run proves it again" "$log"; exit 1; }
gate_head=$(git -C "$ops" rev-parse HEAD)
for c in "${pre[@]}"; do
  read -ra words <<< "$c"
  run task --yes "${words[@]}" || { stopped "its backup before the change failed (task $c) - nothing merged" "$log"; exit 1; }
done
held_now
start_journal
merge
revs=$(revisions) || { page "merged, the merge's commits not read - its production commands not run"; exit 1; }
journal "revisions $revs"
# what a chart the unit moves stopped shipping (declared in scripts/upgrade-leftovers.json), deleted once Argo runs the
# new version - before any settle: prune is off, so those objects keep the app OutOfSync and verify never passes (the
# copy's change did the same; data-operators' scylla-operator v1.23.0, 2026-11-26)
[ -z "$dry" ] || say "RUN scripts/upgrade-leftovers.py --on ten --base <infra's base> --head <infra's head> (a unit with an infra part)"
infra_part=$(grep '^schnappy/infra ' "$heads" 2> /dev/null)
if [ -n "$infra_part" ]; then
  read -r _ _ infra_head infra_base <<< "$infra_part"
  [[ $infra_head =~ ^[0-9a-f]{40}$ && $infra_base =~ ^[0-9a-f]{40}$ ]] \
    || { page "merged, infra's proven base and head not read ($infra_part) - what its charts stopped shipping not cleared, production not verified"; exit 1; }
  journal "leftovers"
  run scripts/upgrade-leftovers.py --on ten --base "$infra_base" --head "$infra_head" \
    || { page "merged, what its charts stopped shipping not cleared (scripts/upgrade-leftovers.py, see the log) - production not verified"; exit 1; }
  journal "leftovers done"
fi
if [ -n "$revs" ] && [ "${#cmds[@]}" -gt 0 ]; then
  # Argo applies infra's and platform's part first, as on the copy - a command (kubeadm restarting the API server)
  # in the middle of its sync fails the sync
  UPGRADE_VERIFY_REVISIONS="$revs" UPGRADE_VERIFY_HOLD=0 run scripts/upgrade-verify.sh \
    || { page "merged, Argo not settled on it - its production commands not run"; exit 1; }
fi
for c in "${cmds[@]}"; do
  read -ra words <<< "$c"
  journal "command $c"
  run task --yes "${words[@]}" || { page "its production command failed: task $c"; exit 1; }
  journal "command done $c"
done

# 7. verify
if ! UPGRADE_VERIFY_REVISIONS="$revs" run scripts/upgrade-verify.sh; then
  page "applied, production not settled after it - see the log"
  exit 1
fi
journal "verified"

# 8. record
run task test:copy:inventory || say "the inventory not read after it - the record says so"
run scripts/upgrade-record.sh "$unit" "$log" \
  || { stopped "applied and verified, not recorded - push the record, then remove $state/inflight" "$log"; exit 1; }
[ -n "$dry" ] || rm -f "$state/inflight" "$state/tries/$unit" "$state/fixes/$unit.diff"  # the fix's commit merged with it
withfix=""
[ -z "$fixed" ] && [[ ,$unit_labels, != *,agent-fixed,* ]] || withfix=", with the agent's fix (its commit merged with it)"
say "APPLIED $unit: $kind$withfix, applied and verified ($copy_gone)"
