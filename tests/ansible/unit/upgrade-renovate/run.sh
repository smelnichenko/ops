#!/bin/bash
# task upgrade (the operator's decisions of 2026-11-15): Renovate on the workstation, then the runner - one task started
# by hand, no CI cron. scripts/upgrade-renovate.sh run against a docker that records what it is given: the image pinned,
# the bot's token by name and never on a command line, no bind mount, the allowed post-upgrade command from
# renovate/allowed-commands.json, lookup only when asked, a GitHub token only when there is one; Renovate's failure, a
# logged error or fatal, or a repository it did not read through (no renovate.json on its main: "disabled-no-config")
# stopping the task before the runner. The task: LOOKUP true or false alone, the real run refused until the runner's
# open items are done, the runner given the bot's token by environment.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
check() {  # name got want
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got  $2"; echo "    want $3"; fails=$((fails + 1)); fi
}
# Renovate's log as a run that read every repository writes it (text format, its JSON details indented)
OK_LOG=$(cat <<'LOG'
 INFO: Renovate started
 INFO: Repository started (repository=schnappy/infra)
 INFO: Repository finished (repository=schnappy/infra)
       "result": "done",
 INFO: Repository started (repository=schnappy/platform)
 INFO: Repository finished (repository=schnappy/platform)
       "result": "done",
 INFO: Repository started (repository=schnappy/ops)
 WARN: Some release(s) did not have a releaseTimestamp (repository=schnappy/ops)
 INFO: Repository finished (repository=schnappy/ops)
       "result": undefined,
LOG
)
export OK_LOG
# the docker: its arguments one per line, the environment it would pass, an exit code and a log as told (a good run's)
cat > "$W/docker" <<'FAKE'
#!/bin/bash
printf '%s\n' "$@" > "$W_OUT/argv"
{ echo "token=${RENOVATE_TOKEN-unset}"; echo "github=${GITHUB_COM_TOKEN-unset}"; echo "allowed=${RENOVATE_ALLOWED_COMMANDS-unset}"; } > "$W_OUT/env"
printf '%s\n' "${FAKE_LOG-$OK_LOG}"
exit "${FAKE_RC:-0}"
FAKE
chmod +x "$W/docker"
TOKEN=0123456789abcdef0123456789abcdef01234567
GH=ghp_abcdefghijklmnopqrstuvwxyz0123456789
run() {  # [env...]: the script's exit code; argv and env in $W
  rm -f "$W/argv" "$W/env"
  env -u RENOVATE_TOKEN -u RENOVATE_GITHUB_TOKEN -u GITHUB_COM_TOKEN W_OUT="$W" UPGRADE_DOCKER="$W/docker" "$@" \
    scripts/upgrade-renovate.sh "${ARGS[@]}" > "$W/out" 2>&1
  echo $?
}
ARGS=()
check "no bot token: refused, docker never run" "$(run) $([ -e "$W/argv" ] && echo ran || echo not-run) $(grep -c REFUSED "$W/out")" \
  "1 not-run 1"
rc=$(run RENOVATE_TOKEN=$TOKEN)
check "a run: docker run --rm, the image pinned exactly and last" "$rc $(head -2 "$W/argv" | tr '\n' ' ')$(tail -1 "$W/argv")" \
  "0 run --rm renovate/renovate:44.198.3"
check "the bot's token by name - its value on no argument; the container given it" \
  "$(grep -cx RENOVATE_TOKEN "$W/argv") $(grep -c "$TOKEN" "$W/argv") $(grep -c "^token=$TOKEN$" "$W/env")" "1 0 1"
check "no bind mount, no volume, no host network" "$(grep -cE '^(-v|--volume|--mount|--network|--net)(=|$)' "$W/argv")" "0"
check "the allowed post-upgrade command read from renovate/allowed-commands.json, passed by name" \
  "$(grep -cx RENOVATE_ALLOWED_COMMANDS "$W/argv") $([ "$(sed -n 's/^allowed=//p' "$W/env")" = "$(cat renovate/allowed-commands.json)" ] && echo same)" \
  "1 same"
check "Forgejo's API, the three repos, no onboarding, its config required, the bot as author, info logging; branches made" \
  "$(grep -cxE 'RENOVATE_PLATFORM=forgejo|RENOVATE_ENDPOINT=https://git.pmon.dev/api/v1/|RENOVATE_REPOSITORIES=schnappy/infra,schnappy/platform,schnappy/ops|RENOVATE_ONBOARDING=false|RENOVATE_REQUIRE_CONFIG=required|RENOVATE_GIT_AUTHOR=Renovate Bot <renovate-bot@pmon.dev>|LOG_LEVEL=info' "$W/argv") $(grep -c RENOVATE_DRY_RUN "$W/argv")" \
  "7 0"
check "no GitHub token: none passed (an empty one was a 401)" "$(grep -c GITHUB_COM_TOKEN "$W/argv") $(grep -c '^github=unset$' "$W/env")" "0 1"
ARGS=(--lookup)
check "--lookup: Renovate reads only" "$(run RENOVATE_TOKEN=$TOKEN) $(grep -cx RENOVATE_DRY_RUN=lookup "$W/argv")" "0 1"
ARGS=()
check "a GitHub token: passed by name, its value on no argument" \
  "$(run RENOVATE_TOKEN=$TOKEN RENOVATE_GITHUB_TOKEN=$GH) $(grep -cx GITHUB_COM_TOKEN "$W/argv") $(grep -c "$GH" "$W/argv") $(grep -c "^github=$GH$" "$W/env")" \
  "0 1 0 1"
check "Renovate failing: the task stops (non-zero), its log's end shown" \
  "$(run RENOVATE_TOKEN=$TOKEN FAKE_RC=3 FAKE_LOG='FATAL: boom') $(grep -c 'boom' "$W/out")" "1 1"
check "Renovate ending 0 with an error or a fatal logged (text, JSON 50 or 60): the task stops before the runner; a warning alone goes on" \
  "$(run RENOVATE_TOKEN=$TOKEN FAKE_LOG="$OK_LOG"$'\n ERROR: Repository has unknown error (repository=schnappy/infra)') $(run RENOVATE_TOKEN=$TOKEN FAKE_LOG="$OK_LOG"$'\n FATAL: Authentication failure') $(run RENOVATE_TOKEN=$TOKEN FAKE_LOG="$OK_LOG"$'\n{"level":50,"msg":"Repository has unknown error"}') $(run RENOVATE_TOKEN=$TOKEN FAKE_LOG="$OK_LOG"$'\n{"level":60,"msg":"fatal"}') $(run RENOVATE_TOKEN=$TOKEN FAKE_LOG="$OK_LOG"$'\n WARN: Package lookup failures')" \
  "1 1 1 1 0"
# 2026-11-15's lookup, as it logged it: infra and platform skipped - their renovate.json not on main yet
SKIPPED=$(cat <<'LOG'
 INFO: Repository started (repository=schnappy/infra)
 INFO: Repository is disabled - skipping (repository=schnappy/infra)
 INFO: Repository finished (repository=schnappy/infra)
       "result": "disabled-no-config",
 INFO: Repository started (repository=schnappy/platform)
 INFO: Repository is disabled - skipping (repository=schnappy/platform)
 INFO: Repository finished (repository=schnappy/platform)
       "result": "disabled-no-config",
 INFO: Repository started (repository=schnappy/ops)
 INFO: Repository finished (repository=schnappy/ops)
       "result": undefined,
LOG
)
check "a repository not read through (skipped without its renovate.json, two of three finished, an error result): the task stops before the runner" \
  "$(run RENOVATE_TOKEN=$TOKEN FAKE_LOG="$SKIPPED") $(grep -c 'did not read every repository' "$W/out") $(run RENOVATE_TOKEN=$TOKEN FAKE_LOG="$(printf '%s\n' "$OK_LOG" | head -n 6)") $(run RENOVATE_TOKEN=$TOKEN FAKE_LOG="${OK_LOG/\"result\": \"done\"/\"result\": \"external-host-error\"}")" \
  "1 1 1 1"
ARGS=(--force)
check "an unknown argument refused" "$(run RENOVATE_TOKEN=$TOKEN) $([ -e "$W/argv" ] && echo ran || echo not-run)" "2 not-run"
# the task: Renovate first, the runner after it unless LOOKUP, given the bot's token by the environment; a prompt; its
# preconditions run as go-task runs them (sh -c, LOOKUP rendered) for each value one might type
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
got=$("$PY" - <<'PYCHECK'
import subprocess
import yaml
t = yaml.safe_load(open("Taskfile.yml"))["tasks"]["upgrade"]
cmds = [c if isinstance(c, str) else c.get("cmd", "") for c in t["cmds"]]
pre = [p["sh"] for p in t.get("preconditions", [])]
def admitted(v, ps=None):
    return all(subprocess.run(["sh", "-c", p.replace("{{.LOOKUP}}", v)]).returncode == 0 for p in (pre if ps is None else ps))
VALUES = ("true", "false", "1", "yes", "TRUE", "")
# the value check on its own (it stays when the real run's refusal goes): true or false, nothing else
values_only = [p for p in pre if "= false" in p]
print(len(cmds), cmds[0].startswith("scripts/upgrade-renovate.sh"), '{{if eq .LOOKUP "true"}}--lookup{{end}}' in cmds[0],
      cmds[1] == '[ "{{.LOOKUP}}" = true ] || UPGRADE_FORGEJO_TOKEN="$RENOVATE_TOKEN" scripts/upgrade-cycle.sh',
      "--shadow" not in " ".join(cmds), "PRODUCTION" in t.get("prompt", "") and "radar" in t.get("prompt", ""),
      t["vars"]["LOOKUP"], t.get("deps"), any("ignore_error" in c for c in t["cmds"] if isinstance(c, dict)),
      [v for v in VALUES if admitted(v)], len(values_only), [v for v in VALUES if admitted(v, values_only)])
PYCHECK
)
check "task upgrade: Renovate, then the runner for real (no --shadow) unless LOOKUP=true, its token from the environment, behind a prompt naming production and the radar; no step's failure ignored; LOOKUP=true alone admitted (true or false only - 1, yes, TRUE refused; the real run refused until the runner's open items are done)" \
  "$got" "2 True True True True True {{.LOOKUP | default \"false\"}} ['deploy:install'] False ['true'] 1 ['true', 'false']"
check "no CI cron runs Renovate any more (.woodpecker/renovate.yaml gone)" "$([ -e .woodpecker/renovate.yaml ] && echo present || echo gone)" "gone"
if [ "$fails" = 0 ]; then echo "upgrade-renovate: ALL-PASS"; else echo "upgrade-renovate: $fails FAILED"; exit 1; fi
