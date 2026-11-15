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
# the task: the copy lock and the runner's gates first, Renovate, then the runner - none of the three but Renovate with
# LOOKUP or RUNNER=false; the runner given the bot's token by the environment; a prompt; its preconditions run as
# go-task runs them (sh -c, the vars rendered) for each value one might type; its commands run as rendered, against a
# shell that records them, for each mode
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
got=$(W="$W" "$PY" - <<'PYCHECK'
import os, subprocess
import yaml
W = os.environ["W"]
t = yaml.safe_load(open("Taskfile.yml"))["tasks"]["upgrade"]
cmds = [c if isinstance(c, str) else c.get("cmd", "") for c in t["cmds"]]
pre = [p["sh"] for p in t.get("preconditions", [])]
def render(text, lookup, runner, shadow="false"):
    text = text.replace("{{.LOOKUP}}", lookup).replace("{{.RUNNER}}", runner).replace("{{.SHADOW}}", shadow)
    text = text.replace('{{if eq .SHADOW "true"}}--shadow{{end}}', "--shadow" if shadow == "true" else "")
    return text.replace('{{if eq .LOOKUP "true"}}--lookup{{end}}', "--lookup" if lookup == "true" else "")
def admitted(lookup, runner, shadow="false", ps=None):
    return all(subprocess.run(["sh", "-c", render(p, lookup, runner, shadow)]).returncode == 0 for p in (pre if ps is None else ps))
VALUES = ("true", "false", "1", "yes", "TRUE", "")
# the value checks on their own (they stay when the applying runner's refusal goes): true or false, nothing else
values_only = [p for p in pre if p.count("{{.") == 2 and "= false" in p]
# each command as go-task would run it, its scripts recording (the lock, the gates, Renovate, the runner)
os.makedirs(os.path.join(W, "tb", "scripts"), exist_ok=True)
for name in ("copy-lock.sh", "upgrade-cycle.sh", "upgrade-renovate.sh"):
    path = os.path.join(W, "tb", "scripts", name)
    open(path, "w").write(f'#!/bin/sh\necho "{name} $* token=${{UPGRADE_FORGEJO_TOKEN:-none}}" >> "$REC"\n')
    os.chmod(path, 0o755)
def ran(lookup, runner, shadow="false"):
    rec = os.path.join(W, "tb", "rec")
    if os.path.exists(rec):
        os.remove(rec)
    for c in cmds:
        subprocess.run(["sh", "-c", render(c, lookup, runner, shadow)], cwd=os.path.join(W, "tb"),
                       env={**os.environ, "REC": rec, "RENOVATE_TOKEN": "the-bots"})
    return open(rec).read().split("\n")[:-1] if os.path.exists(rec) else []
TF = ("true", "false")
print(len(cmds), "PRODUCTION" in t.get("prompt", "") and "radar" in t.get("prompt", ""),
      t["vars"]["LOOKUP"], t["vars"]["RUNNER"], t["vars"]["SHADOW"], t.get("deps"),
      any("ignore_error" in c for c in t["cmds"] if isinstance(c, dict)),
      sorted(f"{l}/{r}/{x}" for l in TF for r in TF for x in TF if admitted(l, r, x)),
      [v for v in VALUES if all(admitted(v if i == 0 else "false", v if i == 1 else "false", v if i == 2 else "true", values_only)
                                for i in range(3))], sep="|")
print(ran("true", "true"), ran("false", "false"), ran("false", "true", "true"), ran("false", "true"), sep="|")
PYCHECK
)
check "task upgrade: a prompt naming production and the radar, LOOKUP false, RUNNER true and SHADOW false by default, no step's failure ignored; admitted: LOOKUP=true, RUNNER=false or SHADOW=true (the applying runner refused until the cycle's first proof); each value true or false alone (1, yes, TRUE, empty never)" \
  "$(head -1 <<< "$got")" "4|True|{{.LOOKUP | default \"false\"}}|{{.RUNNER | default \"true\"}}|{{.SHADOW | default \"false\"}}|['deploy:install']|False|['false/false/false', 'false/false/true', 'false/true/true', 'true/false/false', 'true/false/true', 'true/true/false', 'true/true/true']|['true', 'false']"
check "task upgrade's commands as run: LOOKUP=true - Renovate reads, nothing else; RUNNER=false - Renovate's branches alone; SHADOW=true - the lock, the gates, Renovate, the runner --shadow with the bot's token; the applying runner the same without --shadow" \
  "$(tail -1 <<< "$got")" "['upgrade-renovate.sh --lookup token=none']|['upgrade-renovate.sh  token=none']|['copy-lock.sh  token=none', 'upgrade-cycle.sh --preflight token=none', 'upgrade-renovate.sh  token=none', 'upgrade-cycle.sh --shadow token=the-bots']|['copy-lock.sh  token=none', 'upgrade-cycle.sh --preflight token=none', 'upgrade-renovate.sh  token=none', 'upgrade-cycle.sh  token=the-bots']"
check "no CI cron runs Renovate any more (.woodpecker/renovate.yaml gone)" "$([ -e .woodpecker/renovate.yaml ] && echo present || echo gone)" "gone"
if [ "$fails" = 0 ]; then echo "upgrade-renovate: ALL-PASS"; else echo "upgrade-renovate: $fails FAILED"; exit 1; fi
