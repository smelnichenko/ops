#!/bin/bash
# task upgrade:run (the operator's decisions of 2026-11-15): Renovate on the workstation, then the runner - one task started
# by hand, no CI cron. scripts/upgrade-renovate.sh run against a docker that records what it is given: the image pinned,
# the bot's token by name and never on a command line, no bind mount, the allowed post-upgrade command from
# renovate/allowed-commands.json, lookup only when asked, a GitHub token only when there is one; Renovate's failure, a
# logged error or fatal, or a repository it did not read through (no renovate.json on its main: "disabled-no-config")
# stopping the task before the runner; refused beside a running runner (its lock). The tasks (operator 2026-11-20 - no
# mode variable, one mistyped was read as unset, and unset was the applying run): upgrade:check reads and nothing else,
# upgrade:run writes and applies - the old task's LOOKUP, RUNNER or SHADOW refused, the runner given the bot's token by
# environment.
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
# the pin read from the script (Renovate moves it: a literal here failed its own update's CI, ops#57 2026-11-16) - an exact
# x.y.z and its digest (a Docker Hub tag can move, and this image holds the bot's token: the wave-patches review,
# 2026-11-23), never a tag alone
pin=$(sed -n 's/^image=//p' scripts/upgrade-renovate.sh)
[[ $pin =~ ^renovate/renovate:[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}$ ]] && exact=exact || exact="not exact: $pin"
check "a run: docker run --rm, the image pinned exactly (x.y.z and its digest) and last" "$rc $(head -2 "$W/argv" | tr '\n' ' ')$(tail -1 "$W/argv") $exact" \
  "0 run --rm $pin exact"
check "the bot's token by name - its value on no argument; the container given it" \
  "$(grep -cx RENOVATE_TOKEN "$W/argv") $(grep -c "$TOKEN" "$W/argv") $(grep -c "^token=$TOKEN$" "$W/env")" "1 0 1"
check "no bind mount, no volume, no host network" "$(grep -cE '^(-v|--volume|--mount|--network|--net)(=|$)' "$W/argv")" "0"
check "the allowed post-upgrade command read from renovate/allowed-commands.json, passed by name" \
  "$(grep -cx RENOVATE_ALLOWED_COMMANDS "$W/argv") $([ "$(sed -n 's/^allowed=//p' "$W/env")" = "$(cat renovate/allowed-commands.json)" ] && echo same)" \
  "1 same"
check "Forgejo's API, the three repos, no onboarding, its config required, the bot as author, info logging; branches made" \
  "$(grep -cxE 'RENOVATE_PLATFORM=forgejo|RENOVATE_ENDPOINT=https://git.pmon.dev/api/v1/|RENOVATE_REPOSITORIES=schnappy/infra,schnappy/platform,schnappy/ops|RENOVATE_ONBOARDING=false|RENOVATE_REQUIRE_CONFIG=required|RENOVATE_GIT_AUTHOR=Renovate Bot <renovate-bot@pmon.dev>|LOG_LEVEL=info' "$W/argv") $(grep -c RENOVATE_DRY_RUN "$W/argv")" \
  "7 0"
check "no GitHub token: none passed (an empty one was a 401), and said - what the runner refuses without release notes" \
  "$(grep -c GITHUB_COM_TOKEN "$W/argv") $(grep -c '^github=unset$' "$W/env") $(grep -c '^NO GITHUB TOKEN ' "$W/out")" "0 1 1"
ARGS=(--lookup)
# a lookup prints what it found: Renovate's report (written in the container, printed after it behind a marker) summarised
# per repository, one line per dependency - its version now -> the newest offered, any other target noted
REPORT='{"problems":[],"repositories":{"schnappy/infra":{"problems":[],"branches":[],"packageFiles":{"argocd":[{"packageFile":"apps/istiod.yaml","deps":[{"depName":"istiod","currentValue":"1.31.4","updates":[{"newValue":"1.32.0","updateType":"minor","branchName":"renovate/istio-1.32"}]},{"depName":"postgres","currentValue":"17-alpine","currentVersion":"17","updates":[{"newValue":"18-alpine","newVersion":"18","updateType":"major","branchName":"renovate/postgres-18.x"},{"newValue":"19-alpine","newVersion":"19","updateType":"major","branchName":"renovate/postgres-19.x"}]},{"depName":"opensearch","currentValue":"3.9.0","updates":[{"newValue":"3.10.0","newVersion":"3.10.0","updateType":"minor"},{"newValue":"3.9.0","updateType":"digest","newDigest":"sha256:3bf4fe26aeb9"}]},{"depName":"nginx","currentValue":"1.27-alpine","updates":[{"newValue":"1.31-alpine","updateType":"minor"}]},{"depName":"nginx","currentValue":"1.28.3-alpine","updates":[{"newValue":"1.31.9-alpine","newVersion":"1.31.9","updateType":"minor"}]},{"depName":"kps","currentValue":"91.8.2","updates":[{"newValue":"100.1.0","newVersion":"100.1.0","updateType":"major"},{"newValue":"92.22.0","newVersion":"92.22.0","updateType":"major"}]},{"depName":"busybox","currentValue":"stable-musl","updates":[{"newValue":"stable-musl","updateType":"digest","newDigest":"sha256:abcdef1234567"}]},{"depName":"eclipse-temurin","currentValue":"25.0.4_7-jdk","currentVersion":"25.0.4_7-jdk","updates":[{"newValue":"25.0.5_8-jdk","updateType":"patch"}]},{"depName":"eclipse-temurin","currentValue":"25.0.4_7-jre","currentVersion":"25.0.4_7-jre","updates":[{"newValue":"25.0.5_8-jre","updateType":"patch"}]},{"depName":"java","packageName":"java-jdk","currentValue":"25","currentVersion":"25.0.5+8.0.LTS","updates":[]},{"depName":"java","packageName":"java-jdk","currentValue":"25","currentVersion":"25","updates":[]}]}]}},"schnappy/ops":{"problems":[],"branches":[],"packageFiles":{}},"schnappy/platform":{"problems":[],"branches":[],"packageFiles":{}}}}'
LOOKUP_LOG="$OK_LOG"$'\n''=== renovate report ==='$'\n'"${REPORT//done/x}"
check "--lookup: Renovate reads only, its report asked for in the container (no bind mount) and printed after it" \
  "$(run RENOVATE_TOKEN=$TOKEN FAKE_LOG="$LOOKUP_LOG") $(grep -cx RENOVATE_DRY_RUN=lookup "$W/argv") $(grep -cx RENOVATE_REPORT_TYPE=file "$W/argv") $(tail -1 "$W/argv" | grep -c 'cat /tmp/renovate-report.json')" "0 1 1 1"
check "  what it found printed: per repository, one line per dependency current -> newest (another target noted), no branch names" \
  "$(grep -c '^schnappy/infra: 7 to update$' "$W/out") $(grep -c '^  istiod: 1.31.4 -> 1.32.0 (minor)  \[apps/istiod.yaml\]$' "$W/out") $(grep -c '^  postgres: 17-alpine -> 19-alpine (major, also offered: 18-alpine)  \[apps/istiod.yaml\]$' "$W/out") $(grep -c '^ *renovate/' "$W/out") $(grep -c '^schnappy/ops: nothing to update$' "$W/out")" "1 1 1 0 1"
check "  one dependency, one line - the tags the files disagree on listed together (two nginx: one line)" \
  "$(grep -c '^  nginx: .* -> ' "$W/out") $(grep -c '^  nginx: 1.27-alpine, 1.28.3-alpine -> 1.31.9-alpine (minor, also offered: 1.31-alpine)' "$W/out")" "1 1"
check "  every dependency pinned at more than one version listed, wherever it is (the two nginx: one drift line, its pins)" \
  "$(grep -c '^DIFFERENT VERSIONS of one dependency: 1$' "$W/out") $(grep -c '^  nginx: pinned at 1.27-alpine \[infra:apps/istiod.yaml\]; 1.28.3-alpine \[infra:apps/istiod.yaml\]$' "$W/out")" "1 1"
check "  a tag's flavours (one version, -jdk and -jre) on one line, each with its own target - never one flavour's target for the other" \
  "$(grep -c '^  eclipse-temurin: ' "$W/out") $(grep -c '^  eclipse-temurin: 25.0.4_7-jdk -> 25.0.5_8-jdk (patch); 25.0.4_7-jre -> 25.0.5_8-jre (patch)  \[apps/istiod.yaml\]$' "$W/out")" "1 1"
check "  flavours of one version are no drift (eclipse-temurin's -jdk and -jre: no line of it under DIFFERENT VERSIONS)" \
  "$(sed -n '/^DIFFERENT VERSIONS/,/^[^ ]/p' "$W/out" | grep -c 'eclipse-temurin')" "0"
check "  a pin naming its line (mise's java = \"25\", resolved to 25.0.5+8) beside the same line elsewhere: no drift - the pins as written" \
  "$(sed -n '/^DIFFERENT VERSIONS/,/^[^ ]/p' "$W/out" | grep -c 'java-jdk')" "0"
check "  the newest by its numbers, not as text (100.1.0 above 92.22.0)" "$(grep -c '^  kps: 91.8.2 -> 100.1.0 (major, also offered: 92.22.0)' "$W/out")" "1"
check "  a rebuild of the same tag (a digest update) said as one - beside a new version, and alone - never as a version" \
  "$(grep -c '^  opensearch: 3.9.0 -> 3.10.0 (minor, also offered: 3.9.0 rebuilt)  \[apps/istiod.yaml\]$' "$W/out") $(grep -c '^  busybox: stable-musl - same tag, new image (digest abcdef1)  \[apps/istiod.yaml\]$' "$W/out")" "1 1"
# the console (operator 2026-11-22: all of the logging visible on the console the task runs in): Renovate's log as it
# is written, before what follows it; the lookup's report (behind its marker) never printed raw
check "  its log on the console, the whole of it right before 'Renovate done'; the raw report not printed" \
  "$([ "$(grep -B "$(wc -l <<< "$OK_LOG")" '^Renovate done$' "$W/out" | head -n -1)" = "$OK_LOG" ] && echo whole-log-first) $(grep -c 'renovate report\|"repositories"' "$W/out")" \
  "whole-log-first 0"
log=$(sed -n 's/^Renovate lookup ([^)]*) - its log: //p' "$W/out")
check "  the log the checks read has no report in it (a report's own results never taken for a repository's)" \
  "$(grep -c 'renovate report' "$log") $([ -s "$log.report.json" ] && echo report-kept)" "0 report-kept"
check "  a lookup that left no report: the task fails, never 'nothing to update'" \
  "$(run RENOVATE_TOKEN=$TOKEN) $(grep -c 'report missing' "$W/out") $(grep -c 'nothing to update' "$W/out")" "1 1 0"
ARGS=()
check "a real run: no report asked for, nothing after the image" \
  "$(run RENOVATE_TOKEN=$TOKEN) $(grep -c RENOVATE_REPORT "$W/argv") $(tail -1 "$W/argv")" "0 0 $(sed -n 's/^image=//p' scripts/upgrade-renovate.sh)"
# --apps: the app repos' Renovate (task upgrade:apps:run) - every app repo and the CI tool images (the bot has write on
# each since 2026-11-21),
# never the upgrade cycle's three; each read through; with --lookup too
APPS=schnappy/admin,schnappy/ansible-lint,schnappy/chat,schnappy/chess,schnappy/ci-tools,schnappy/hyperfoil,schnappy/masi,schnappy/monitor,schnappy/radar,schnappy/radio-scheduler,schnappy/site,schnappy/sonar-scanner,schnappy/target-scorer
APPS_LOG=$(for r in ${APPS//,/ }; do printf '%s\n' " INFO: Repository started (repository=$r)" " INFO: Repository finished (repository=$r)" \
  '       "result": "done",'; done)
ARGS=(--apps)
check "--apps: the thirteen app and CI-tool repos alone, a real run, each read through" \
  "$(run RENOVATE_TOKEN=$TOKEN FAKE_LOG="$APPS_LOG") $(grep -cx "RENOVATE_REPOSITORIES=$APPS" "$W/argv") $(grep -c RENOVATE_DRY_RUN "$W/argv") $(grep -cE 'schnappy/(infra|platform|ops)(,|$)' "$W/argv")" "0 1 0 0"
check "  one of them not read through (the last one's finish missing): the task fails" "$(run RENOVATE_TOKEN=$TOKEN FAKE_LOG="$(head -n -2 <<< "$APPS_LOG")")" "1"
ARGS=(--apps --lookup)
APPS_REPORT='{"problems":[],"repositories":{"schnappy/monitor":{"problems":[],"branches":[],"packageFiles":{}},"schnappy/masi":{"problems":[],"branches":[],"packageFiles":{}}}}'
check "  with --lookup: read only, what it found printed" \
  "$(run RENOVATE_TOKEN=$TOKEN FAKE_LOG="$APPS_LOG"$'\n''=== renovate report ==='$'\n'"$APPS_REPORT") $(grep -cx RENOVATE_DRY_RUN=lookup "$W/argv") $(grep -c '^nothing to update anywhere$' "$W/out") $(grep -c '^one version of each dependency everywhere$' "$W/out")" "0 1 1 1"
ARGS=(--bogus)
check "an argument it does not know: refused" "$(run RENOVATE_TOKEN=$TOKEN) $(grep -c REFUSED "$W/out")" "2 1"
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
# the tasks: upgrade:check - Renovate's lookup alone, nothing to give it (no variable, prompt, precondition or dependency);
# upgrade:run - a prompt, the copy lock and the runner's gates first, Renovate, then the runner given the bot's token by the
# environment; the old task's LOOKUP, RUNNER or SHADOW, at any value, refused (ignored, `upgrade:run SHADOW=true` was the
# applying run); `task upgrade` itself gone (go-task refuses a task it does not have). The app repos' the same:
# upgrade:apps:check their lookup alone, upgrade:apps:run writing - no prompt (operator 2026-11-20: the LOOKUP refusal
# suffices), LOOKUP at any value refused; renovate:apps gone. Their preconditions run as go-task
# runs them (sh -c, a {{.NAME}} rendered to its value or empty), their commands as rendered against scripts that record
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
got=$(W="$W" "$PY" - <<'PYCHECK'
import os, re, subprocess
import yaml
W = os.environ["W"]
tasks = yaml.safe_load(open("Taskfile.yml"))["tasks"]
def render(text, given):
    out = re.sub(r"\{\{\.(\w+)\}\}", lambda m: given.get(m.group(1), ""), text)
    assert "{{" not in out, f"a template this harness does not render: {out}"
    return out
TB = os.path.join(W, "tb")
os.makedirs(os.path.join(TB, "scripts"), exist_ok=True)
for name in ("copy-lock.sh", "upgrade-cycle.sh", "upgrade-renovate.sh", "upgrade-apps-merge.py", "upgrade-units.py"):
    path = os.path.join(TB, "scripts", name)
    # upgrade-units.py answers as the case says (replenish: APPROVED, OPEN, NOTHING), the others say nothing
    answer = '\necho "${REPLENISH:-NOTHING}"' if name == "upgrade-units.py" else ""
    open(path, "w").write(f'#!/bin/sh\necho "{name} $* token=${{UPGRADE_FORGEJO_TOKEN:-none}}" >> "$REC"{answer}\n')
    os.chmod(path, 0o755)
def admitted(t, given):
    return all(subprocess.run(["sh", "-c", render(p["sh"], given)], cwd=TB).returncode == 0 for p in t.get("preconditions", []))
def ran(t, replenish="NOTHING"):
    rec = os.path.join(TB, "rec")
    if os.path.exists(rec):
        os.remove(rec)
    for c in t["cmds"]:
        # what a command prints is the task's console, not this report: the record is what was run
        subprocess.run(["sh", "-c", render(c if isinstance(c, str) else c.get("cmd", ""), {})], cwd=TB, capture_output=True,
                       env={**os.environ, "REC": rec, "RENOVATE_TOKEN": "the-bots", "REPLENISH": replenish})
    return open(rec).read().split("\n")[:-1] if os.path.exists(rec) else []
check_t, run_t = tasks["upgrade:check"], tasks["upgrade:run"]
OLD = [{n: v} for n in ("LOOKUP", "RUNNER", "SHADOW") for v in ("true", "false", "1", "yes")]
print("upgrade" in tasks, sorted(k for k in check_t if k != "desc"), ran(check_t), sep="|")
print("PRODUCTION" in run_t.get("prompt", "") and "radar" in run_t.get("prompt", ""), run_t.get("deps"), run_t.get("vars"),
      any("ignore_error" in c for c in run_t["cmds"] if isinstance(c, dict)), admitted(run_t, {}),
      [g for g in OLD if admitted(run_t, g)], sep="|")
print(ran(run_t), ran(run_t, "APPROVED wave-patches infra,ops"), ran(run_t, "OPEN"), sep="|")
ac, ar = tasks["upgrade:apps:check"], tasks["upgrade:apps:run"]
print(any(k.startswith("renovate:apps") for k in tasks), sorted(k for k in ac if k != "desc"), ran(ac), sep="|")
print("prompt" in ar, ar.get("deps"), ar.get("vars"), admitted(ar, {}),
      [g for g in ({"LOOKUP": v} for v in ("true", "false", "1", "yes")) if admitted(ar, g)], ran(ar), sep="|")
ap, am = tasks["upgrade:apply"], tasks["upgrade:apps:merge"]
print("PRODUCTION" in ap.get("prompt", ""), ap.get("deps"), ap.get("vars"), admitted(ap, {}), ran(ap), sep="|")
print("prompt" in am, am.get("deps"), am.get("vars"), ran(am), sep="|")
PYCHECK
)
check "task upgrade gone; upgrade:check: Renovate's lookup alone - no variable, prompt, precondition or dependency to change it" \
  "$(sed -n 1p <<< "$got")" "False|['cmds']|['upgrade-renovate.sh --lookup token=none']"
check "upgrade:run: a prompt naming production and the radar, the venv first, no variable, no step's failure ignored; admitted with nothing given, refused with LOOKUP, RUNNER or SHADOW at any value" \
  "$(sed -n 2p <<< "$got")" "True|['deploy:install']|None|False|True|[]"
check "upgrade:run's commands as run: the lock, the gates, Renovate writing, replenish with the bot's token, the runner (no option) with the bot's token - Renovate again only when replenish approved a unit" \
  "$(sed -n 3p <<< "$got")" "['copy-lock.sh  token=none', 'upgrade-cycle.sh --preflight token=none', 'upgrade-renovate.sh  token=none', 'upgrade-units.py replenish token=the-bots', 'upgrade-cycle.sh  token=the-bots']|['copy-lock.sh  token=none', 'upgrade-cycle.sh --preflight token=none', 'upgrade-renovate.sh  token=none', 'upgrade-units.py replenish token=the-bots', 'upgrade-renovate.sh  token=none', 'upgrade-cycle.sh  token=the-bots']|['copy-lock.sh  token=none', 'upgrade-cycle.sh --preflight token=none', 'upgrade-renovate.sh  token=none', 'upgrade-units.py replenish token=the-bots', 'upgrade-cycle.sh  token=the-bots']"
check "task renovate:apps (and :check, :run) gone; upgrade:apps:check: the app repos' lookup alone - no variable, prompt, precondition or dependency" \
  "$(sed -n 4p <<< "$got")" "False|['cmds']|['upgrade-renovate.sh --apps --lookup token=none']"
check "upgrade:apps:run: no prompt, no variable; admitted with nothing given, refused with LOOKUP at any value; Renovate writing" \
  "$(sed -n 5p <<< "$got")" "False|None|None|True|[]|['upgrade-renovate.sh --apps token=none']"
# upgrade:apply (operator 2026-11-23: apply Renovate's PRs, never run Renovate unasked): upgrade:run without its Renovate step - the lock,
# the gates, the runner with the bot's token; upgrade:apps:merge: the app PRs driven to merged, nothing to give it
check "upgrade:apply: a prompt naming production, the venv first, no variable; the lock, the gates and the runner with the bot's token - Renovate never" \
  "$(sed -n 6p <<< "$got")" "True|['deploy:install']|None|True|['copy-lock.sh  token=none', 'upgrade-cycle.sh --preflight token=none', 'upgrade-cycle.sh  token=the-bots']"
check "upgrade:apps:merge: no prompt, no variable; the merge script alone" \
  "$(sed -n 7p <<< "$got")" "False|None|None|['upgrade-apps-merge.py  token=none']"
ARGS=()
exec 8>> .upgrade-cycle/lock
flock -n 8 || { echo "the lock is held by something else - the next check cannot run"; exit 1; }
check "Renovate beside a running runner (its lock held): refused, docker never run" \
  "$(run RENOVATE_TOKEN=$TOKEN) $([ -e "$W/argv" ] && echo ran || echo not-run) $(grep -c 'holds' "$W/out")" "1 not-run 1"
exec 8>&-
check "no CI cron runs Renovate any more (.woodpecker/renovate.yaml gone)" "$([ -e .woodpecker/renovate.yaml ] && echo present || echo gone)" "gone"
# platform's CI check runs the chart's Alertmanager image (its render step refuses the two apart): the preset finds both,
# one depName - one branch moves them together: a CI check that runs in production's image refuses the two apart
# (platform's alertmanager-render.sh and clickhouse-config-start.sh, infra's tests/stale-pr-envs-sweeper and
# tests/restore-check-age), so a unit that moved only production's stayed red for good (wave-patches, 2026-11-16: infra#36
# alpine/k8s 1.35.10, platform#38 ClickHouse 26.8.37.168) - the step's image and its CI_STEP_IMAGE_CHECK both, digest kept;
# CI's own tools (helm, kubeconform, postgres, Prometheus - its tag follows a chart's appVersion) never a unit; a values key
# named <x>Image read as an image (rcloneImage, CNPG's ephemeralImage - missed until 2026-11-18)
check "the preset moves CI's copies of production's images with production's: the same depName, version and digest, CI's own tools left out" \
  "$("$PY" - <<'PYPRESET'
import json, re
d = json.load(open("renovate/upgrade-cycle.json"))
def found(path, text):
    out = []
    for m in d["customManagers"]:
        if any(re.search(p.strip("/"), path) for p in m["managerFilePatterns"]):
            for s in m["matchStrings"]:
                out += [(g.group("depName"), g.group("currentValue"), bool(g.groupdict().get("currentDigest")))
                        for g in re.finditer(s.replace("(?<", "(?P<"), text)]
    return out
dig = "@sha256:" + "4" * 64
ci = ("  - name: stale-pr-envs-sweeper\n    image: alpine/k8s:1.35.9\n    commands:\n"
      "  - name: restore-check-age\n    image: rclone/rclone:1.75.1" + dig + "\n    environment:\n"
      "      CI_STEP_IMAGE_CHECK: rclone/rclone:1.75.1" + dig + "\n"
      "  - name: clickhouse-config-start\n    image: clickhouse/clickhouse-server:26.8.34.13-alpine\n    environment:\n"
      "      CI_STEP_IMAGE_CHECK: clickhouse/clickhouse-server:26.8.34.13-alpine\n"
      "  - name: rules-unit-tests\n    image: quay.io/prometheus/prometheus:v3.15.0\n"
      "  - name: alertmanager-check\n    image: prom/alertmanager:v0.34.1\n"
      "  - name: lint\n    image: alpine/helm:3.20.0\n  - name: kubeconform\n    image: ghcr.io/yannh/kubeconform:v0.7.0-alpine\n"
      "  - name: init-users-script\n    image: postgres:17-alpine\n")
prod = ("              image: alpine/k8s:1.35.9\n              image: rclone/rclone:1.75.1" + dig + "\n")
values = ("alertmanager:\n  image: prom/alertmanager:v0.34.1\nclickhouse:\n  image: clickhouse/clickhouse-server:26.8.34.13-alpine\n"
          "  backup:\n    rcloneImage: rclone/rclone:1.71.2\ncnpg:\n  ephemeralImage: ghcr.io/cloudnative-pg/postgresql:18.6-system-bullseye\n"
          "  imagePullPolicy: IfNotPresent\n  bootstrapServers: \"schnappy-kafka-bootstrap:9092\"\n")
print(found(".woodpecker/ci.yaml", ci))
print(found("clusters/production/cluster-config/restore-check-age.yaml", prod), found("helm/schnappy-observability/values.yaml", values))
PYPRESET
)" "[('alpine/k8s', '1.35.9', False), ('rclone/rclone', '1.75.1', True), ('rclone/rclone', '1.75.1', True), ('clickhouse/clickhouse-server', '26.8.34.13-alpine', False), ('clickhouse/clickhouse-server', '26.8.34.13-alpine', False), ('prom/alertmanager', 'v0.34.1', False)]
[('alpine/k8s', '1.35.9', False), ('rclone/rclone', '1.75.1', True)] [('prom/alertmanager', 'v0.34.1', False), ('clickhouse/clickhouse-server', '26.8.34.13-alpine', False), ('rclone/rclone', '1.71.2', False), ('ghcr.io/cloudnative-pg/postgresql', '18.6-system-bullseye', False)]"
# what Renovate moves in ops, the copy can prove: each ops value the preset reads (renovate_preset.reads: its managers,
# ignorePaths, the rules turning a dependency off) is one copy-unit.sh follows or proves - its file a vars file it hands
# over, or its key one that file's branch accepts - unless every dependency in the file goes to a manual- unit (never
# picked) or the file is named below with why. Tracked but unprovable, a unit carrying it was built (49 min), refused, and
# handed to the fix agent as red (2026-11-17's review: the data operators' chart versions annotated on their helm tasks,
# setup-velero's aws-cli). And the copy's checks pin no image production runs: Renovate reads nothing under tests/, so a
# pin stays behind production's (rclone, busybox) - they read it from the cluster (tasks/shell-image.yml)
check "every ops value Renovate moves has a proof on the copy (copy-unit.sh) or is named without one; the copy's checks pin no production image" \
  "$("$PY" - <<'PYPROVABLE'
import os, re, sys
sys.path.insert(0, "tests/ansible/unit")
import renovate_preset
cu = open("scripts/copy-unit.sh").read()
def pyset(name):
    return set(re.findall(r'"([^"]+)"', re.search(r"^%s = \{(.*?)\}" % name, cu, re.S | re.M).group(1)))
kubeadm_branch = cu[cu.index('if path == "deploy/ansible/playbooks/setup-kubeadm.yml":'):]
kubeadm_branch = kubeadm_branch[:kubeadm_branch.index("    elif path ==")]
PROVEN = {  # the keys each playbook's branch in copy-unit.sh accepts, read from it
    "deploy/ansible/playbooks/setup-kubeadm.yml": pyset("FOLLOW") | pyset("KUBEADM_PACKAGES") | set(re.findall(r'k == "(\w+)"', kubeadm_branch)),
    "deploy/ansible/playbooks/setup-istio.yml": pyset("FOLLOW"),
    "deploy/ansible/playbooks/setup-argocd.yml": pyset("ARGOCD"),
    "deploy/ansible/playbooks/setup-host-hardening.yml": pyset("NODE_EXPORTER"),
    "deploy/ansible/playbooks/setup-caddy.yml": pyset("CADDY"),
    "deploy/ansible/playbooks/setup-consul.yml": pyset("CONSUL"),
}
VARS_FILES = set(re.findall(r'"(deploy/ansible/vars/[^"]+)": \(', cu))
NO_PROOF = {  # tracked, with no proof path on the copy yet - such a unit is refused by the proof, after its build
    "deploy/ansible/playbooks/setup-pi-services.yml": "Keycloak",
}
bad, unproven = [], set()
for root, dirs, files in os.walk("deploy/ansible"):
    dirs[:] = [x for x in dirs if x not in ("collections", "venv")]
    for f in files:
        path = os.path.join(root, f)
        reads = renovate_preset.reads(path)
        if not reads or path in VARS_FILES or all(renovate_preset.manual(r["depName"]) for r in reads):
            continue
        if path in PROVEN:
            bad += [f"{path} {k}" for k in sorted({r["key"] for r in reads} - PROVEN[path])]
        elif path in NO_PROOF:
            unproven.add(NO_PROOF[path])
        else:
            bad.append(path)
production = {re.sub(r"^docker\.io/(library/)?", "", l.split()[1]) for l in open("tests/ansible/copy/prod-inventory.txt")
              if l.startswith("image ")}
pinned = re.compile(r"(?<![\w./-])((?:docker\.io/)?[a-z0-9][a-z0-9._/-]*[a-z0-9]):[A-Za-z0-9][A-Za-z0-9._-]*")
PIN_OK = {}  # a production image a copy's check still pins - with why (none: each reads it from the cluster or the inventory)
copy_pins = set()
for root, _, files in os.walk("tests/ansible/copy"):
    for f in files:
        if f.endswith((".yml", ".yaml")):
            for line in open(os.path.join(root, f), encoding="utf-8", errors="replace"):
                for m in pinned.finditer(re.sub(r"(^|\s)#.*", "", line)):  # a comment pins nothing
                    name = re.sub(r"^docker[.]io/(library/)?", "", m.group(1))
                    if name in production:
                        copy_pins.add(f"{os.path.join(root, f)} {name}")
print(bad, sorted(unproven), sorted(copy_pins - set(PIN_OK)))
PYPROVABLE
)" "[] ['Keycloak'] []"
# a one-way change's needs are decided in one table (scripts/upgrade-stores.json): every package the preset marks one-way
# is a store's there and every store's package is marked; each store has its backups or names what is missing; each
# backup is a task ops has. A new kind of store fails here when the preset starts tracking it - never first met in a run
# as a vague "no backup path" (2026-11-17)
check "every one-way package a store's in scripts/upgrade-stores.json and back; each store backed up or its gap named; each backup a task; each store's real unit names its own alone" \
  "$("$PY" - <<'PYSTORES'
import json, re, yaml
d = json.load(open("renovate/upgrade-cycle.json"))
t = json.load(open("scripts/upgrade-stores.json"))
marked = {p for r in d["packageRules"] if "one-way" in (r.get("addLabels") or []) for p in r.get("matchPackageNames", [])}
named = {p for s in t["stores"] for p in s["packages"]}
empty = [s["store"] for s in t["stores"] if not (s["backups"] or s.get("taken_by") or s["missing"])]
tasks = set(yaml.safe_load(open("Taskfile.yml"))["tasks"])
unknown = [b for s in t["stores"] for b in s["backups"] + s.get("taken_by", [])
           if b.split()[0] not in tasks or not b.startswith(("deploy:", "check:production:"))]  # production's tasks alone
# each store's example unit names (Renovate's for its packages) matched by its own units alone
names = [(s["store"], e, [o["store"] for o in t["stores"] if re.search(o["units"], e)]) for s in t["stores"] for e in s["examples"]]
print(sorted(marked - named), sorted(named - marked), empty, unknown, [n for n in names if n[2] != [n[0]]])
PYSTORES
)" "[] [] [] [] []"
# a run rebases nothing that has no conflict (Woodpecker builds one at a time; infra's main moves many times a day - a
# rebase of every branch at every run was a queue of builds ahead of the apps' deploys); no cap per repo (it split one
# unit across the repos: its infra half waiting while its ops half was picked)
check "the preset: branches rebased on a conflict alone, no cap on pull requests or branches (a unit whole in every repo)" \
  "$("$PY" - <<'PYLIMIT'
import json
d = json.load(open("renovate/upgrade-cycle.json"))
print(d.get("rebaseWhen"), d.get("prConcurrentLimit"), d.get("branchConcurrentLimit"), d.get("prHourlyLimit"),
      any("prPriority" in r for r in d["packageRules"]))
PYLIMIT
)" "conflicted 0 0 0 False"
# Woodpecker a unit of its own (the copy runs no Woodpecker): renovate/manual-woodpecker - the prefix and the branch topic
# both (the wave-patches rule names its branch by group.branchTopic: a groupSlug alone left it on manual-wave-patches),
# the last rule naming the chart, so no group after it takes it back
check "the preset: Woodpecker's chart on renovate/manual-woodpecker, the last rule that names it" \
  "$("$PY" - <<'PYWOODPECKER'
import json, re
d = json.load(open("renovate/upgrade-cycle.json"))
CHART = "ghcr.io/woodpecker-ci/helm/woodpecker"
# Renovate's /regex/ (a search, flags after the last slash) or an exact name
hit = lambda p: re.search(p[1:p.rindex("/")], CHART) is not None if p.startswith("/") and p.rindex("/") > 0 else p == CHART
names = [i for i, r in enumerate(d["packageRules"]) if any(hit(p) for p in r.get("matchPackageNames", []))]
r = d["packageRules"][names[-1]] if names else {}
print(r.get("additionalBranchPrefix"), (r.get("group") or {}).get("branchTopic"), r.get("groupSlug"), names[-1] == len(d["packageRules"]) - 1 if names else None)
PYWOODPECKER
)" "manual- woodpecker woodpecker True"
# Renovate watches its own image: a custom manager whose file pattern and regex find upgrade-renovate.sh's image line,
# the depName and version read from it (nothing did before - 44.198.3 stood while 44.246.4 was out, 2026-11-16)
check "the preset: Renovate's own image in upgrade-renovate.sh watched, its name and version read from the line" \
  "$("$PY" - <<'PYSELF'
import json, re
d = json.load(open("renovate/upgrade-cycle.json"))
path = "scripts/upgrade-renovate.sh"
text = open(path).read()
pat = lambda p: re.search(p[1:p.rindex("/")], path) is not None
found = []
for m in d["customManagers"]:
    if any(pat(p) for p in m.get("managerFilePatterns", [])):
        for ms in m["matchStrings"]:
            for g in re.finditer(ms.replace("(?<", "(?P<"), text):
                found.append((g.group("depName"), bool(re.fullmatch(r"\d+\.\d+\.\d+", g.group("currentValue"))), m.get("datasourceTemplate"),
                              bool(re.fullmatch(r"sha256:[0-9a-f]{64}", g.group("currentDigest") or ""))))
print(found)
PYSELF
)" "[('renovate/renovate', True, 'docker', True)]"
# the Gateway API out of Istio's rule, on renovate/gateway-api-<X.Y> of its own (under istio's topic it was named by its own
# version: istio-1.6, istio-1.7 - picked before istio-1.32)
check "the preset: the Gateway API its own unit (gateway-api-<X.Y>), not in Istio's" \
  "$("$PY" - <<'PYGATEWAY'
import json
d = json.load(open("renovate/upgrade-cycle.json"))
gw = "https://github.com/kubernetes-sigs/gateway-api"
istio = [r for r in d["packageRules"] if r.get("groupSlug") == "istio"]
mine = [r for r in d["packageRules"] if r.get("groupSlug") == "gateway-api"]
print(any(gw in r["matchPackageNames"] for r in istio), [(r["matchPackageNames"], r["group"]["branchTopic"]) for r in mine])
PYGATEWAY
)" "False [(['https://github.com/kubernetes-sigs/gateway-api'], 'gateway-api-{{{newMajor}}}.{{{newMinor}}}')]"
# A pull request's body: the table of what changes (package, update, from -> to), Renovate's warnings, and the release
# notes - what the review's compatibility pass reads (<repo>.pr.md, operator 2026-11-21: the versions' compatibility
# is what to make sure of); no header, configuration, controls, footer or the "no github.com credentials" note (operator
# 2026-11-20 - the release notes cut then, when the pull requests were mailed; the repos unwatched since). Renovate puts its
# debug comment after the template whatever it holds (upgrade-units.py reads the unit's labels there)
check "the preset: a pull request's body the table of what changes, Renovate's warnings and the release notes, nothing else" \
  "$("$PY" -c 'import json; print(json.load(open("renovate/upgrade-cycle.json")).get("prBodyTemplate"))')" "{{{table}}}{{{warnings}}}{{{changelogs}}}"
# the app repos' shared preset (renovate/apps.json, each app repo's renovate.json extends it): one JDK and one Node
# everywhere - the Gradle toolchain read by a regex manager (its major alone), the JDK images, mise's java and the toolchain
# one group; node images, mise's node and @types/node one group, LTS (even) majors only; first-party images never touched
check "the apps preset: the Gradle toolchain's major read (and nothing longer), its datasource Adoptium's, LTS majors only for node, the groups, first-party off" \
  "$("$PY" - <<'PYAPPS'
import json, re
d = json.load(open("renovate/apps.json"))
m = d["customManagers"][0]
rx = re.compile(m["matchStrings"][0].replace("(?<", "(?P<"))  # JavaScript's named group, as Renovate reads it
got = [g.group("currentValue") for g in rx.finditer("java {\n toolchain {\n  languageVersion = JavaLanguageVersion.of(25)\n }\n}\nJavaLanguageVersion.of(x)")]
files = re.compile(m["managerFilePatterns"][0].strip("/"))
node = next(r for r in d["packageRules"] if r.get("groupName") == "node")
allowed = re.compile(node["allowedVersions"].strip("/"))
lts = [v for v in ("22-alpine", "24", "26.13.1", "25", "23-alpine", "v24.1.0") if allowed.search(v)]
groups = sorted(r["groupName"] for r in d["packageRules"] if r.get("groupName"))
off = [r for r in d["packageRules"] if r.get("enabled") is False and "git\\.pmon\\.dev" in "".join(r.get("matchPackageNames", []))]
print(got, bool(files.search("build.gradle")), bool(files.search("backend/build.gradle.kts")), bool(files.search("settings.gradle")),
      m["datasourceTemplate"], m["extractVersionTemplate"], lts, groups, len(off), "config:recommended" in d["extends"])
PYAPPS
)" "['25'] True True False java-version ^(?<version>\d+) ['22-alpine', '24', '26.13.1', 'v24.1.0'] ['app majors', 'app wave', 'base image digests', 'java', 'node', 'playwright', 'spring boot'] 1 True"
# The app wave (operator 2026-11-23: the infra wave's grouping for the app repos too): a repo's patches, minors, digests and pins one pull request
# (renovate/app-wave) - java, node, playwright, Spring Boot's minors and the six Dockerfiles' weekly digests their own
# groups; a repo's majors one pull request of their own (renovate/major-app-majors, "per-repo majors group is good
# idea, do it"), java's, node's and playwright's in their groups, Spring Boot's its own (major-spring-boot); automerged
# only when all its updates are (a minor in it: merged by hand). No rule names a branch topic, so none of the wave's
# stays on a group after it; each branch resolved as Renovate merges the rules
check "the apps preset: patches, minors, digests and pins one pull request a repo, its majors another - the groups and Spring Boot their own" \
  "$("$PY" - <<'PYAPPWAVE'
import json, sys
sys.path.insert(0, "tests/ansible/unit")
from renovate_preset import branch, resolved
d = json.load(open("renovate/apps.json"))
B = "org.springframework.boot:org.springframework.boot.gradle.plugin"
cases = [("org.postgresql:postgresql", "patch"), ("com.github.spotbugs", "minor"), ("org.testcontainers:testcontainers-bom", "minor"),
         ("react", "minor"), ("redis", "digest"), ("react", "pin"), (B, "patch"), (B, "minor"), (B, "major"), ("react", "major"),
         ("eclipse-temurin", "minor"), ("node", "minor"), ("@playwright/test", "minor"), ("com.fasterxml.jackson:jackson-bom", "major"),
         ("eclipse-temurin", "major"), ("node", "major"), ("@playwright/test", "major")]
dock = [("eclipse-temurin", "digest", "schnappy/monitor"), ("eclipse-temurin", "pinDigest", "schnappy/site"),
        ("alpine", "digest", "schnappy/ci-tools")]
print([branch(p, k, preset=d) for p, k in cases],
      [branch(p, k, preset=d, repo=r, manager="dockerfile") for p, k, r in dock],
      [bool(resolved(p, k, preset=d).get("automerge")) for p, k in (("org.postgresql:postgresql", "patch"), ("com.github.spotbugs", "minor"))],
      any("branchTopic" in (r.get("group") or {}) for r in d["packageRules"]))
PYAPPWAVE
)" "['app-wave', 'app-wave', 'app-wave', 'app-wave', 'app-wave', 'app-wave', 'app-wave', 'spring-boot', 'major-spring-boot', 'major-app-majors', 'java', 'node', 'playwright', 'major-app-majors', 'major-java', 'major-node', 'major-playwright'] ['base-image-digests', 'base-image-digests', 'app-wave'] [True, False] False"
# target-scorer's Python minor and its locked torch/torchvision move only with a re-lock (its pip-compile lock is for
# one Python; a Python 3.15 image over the 3.13 lock was CI red, #48): not proposed there - patches still - and another
# repo's Python minor still in its wave
check "the apps preset: target-scorer's Python and torch minors and majors not proposed, their patches and other repos' still" \
  "$("$PY" - <<'PYTS'
import json, sys
sys.path.insert(0, "tests/ansible/unit")
from renovate_preset import branch
d = json.load(open("renovate/apps.json"))
TS = "schnappy/target-scorer"
print([branch(p, k, preset=d, repo=TS) for p, k in (("python", "minor"), ("python", "major"), ("torch", "minor"), ("torchvision", "major"))],
      [branch(p, k, preset=d, repo=TS) for p, k in (("python", "patch"), ("torch", "patch"), ("pillow", "minor"))],
      branch("python", "minor", preset=d, repo="schnappy/radar"))
PYTS
)" "[None, None, None, None] ['app-wave', 'app-wave', 'app-wave'] app-wave"
# site's eslint 10 and TypeScript 6.1+ held by their plugins' peer ranges (site#86: the majors PR did not resolve): the
# hold site's alone - radar's TypeScript 7 still proposed
check "the apps preset: site's eslint below 10, TypeScript below 6.1 and jsdom below 29, another repo's not held" \
  "$("$PY" - <<'PYSITE'
import json, sys
sys.path.insert(0, "tests/ansible/unit")
from renovate_preset import resolved
d = json.load(open("renovate/apps.json"))
print([resolved(p, "major", preset=d, repo="schnappy/site").get("allowedVersions") for p in ("eslint", "@eslint/js", "typescript", "jsdom", "vite")],
      resolved("typescript", "major", preset=d, repo="schnappy/radar").get("allowedVersions"),
      resolved("jsdom", "major", preset=d, repo="schnappy/radar").get("allowedVersions"))
PYSITE
)" "['<10', '<10', '<6.1', '<29', None] None None"
# the six services' Dockerfile base images pinned by tag and digest (operator 2026-11-21: option C): the dockerfile manager
# alone, those six repos alone (CI step images and the CI tool images stay plain tags), the digests one weekly group
check "the apps preset: digests pinned for the six services' Dockerfiles alone - not the CI tool images, not CI steps; their digest moves one Monday group" \
  "$("$PY" - <<'PYPIN'
import json
d = json.load(open("renovate/apps.json"))
pin = [r for r in d["packageRules"] if r.get("pinDigests")]
grp = [r for r in d["packageRules"] if r.get("groupName") == "base image digests"]
six = ["schnappy/admin", "schnappy/chat", "schnappy/chess", "schnappy/masi", "schnappy/monitor", "schnappy/site"]
tools = {"schnappy/ci-tools", "schnappy/ansible-lint", "schnappy/sonar-scanner", "schnappy/hyperfoil"}
print(len(pin), pin[0]["matchManagers"], sorted(pin[0]["matchRepositories"]) == six, bool(tools & set(pin[0]["matchRepositories"])),
      grp[0]["matchManagers"], sorted(grp[0]["matchUpdateTypes"]), grp[0]["matchRepositories"] == pin[0]["matchRepositories"],
      grp[0]["schedule"])
PYPIN
)" "1 ['dockerfile'] True False ['dockerfile'] ['digest', 'pin', 'pinDigest'] True ['* * * * 1']"
# the Gradle wrapper's checksum moved with its version (apps preset): the command allowed for a release version alone
# (never shell text from a crafted one), Gradle's sum written when it is 64 hex, the file as it was otherwise
check "the apps preset's wrapper checksum: allowed for 9.9.2 alone; the sum written; garbage, a failed fetch, no sum line: the file as it was" \
  "$("$PY" - "$W" <<'PYGW'
import json, os, re, subprocess, sys
w = sys.argv[1]
rule = next(r for r in json.load(open("renovate/apps.json"))["packageRules"] if r.get("matchManagers") == ["gradle-wrapper"])
cmd = rule["postUpgradeTasks"]["commands"][0]
allowed = json.load(open("renovate/allowed-commands.json"))
def ok(v):
    return any(re.fullmatch(a, cmd.replace("{{{newVersion}}}", v)) for a in allowed)
bad = [v for v in ("9.9.2; touch /tmp/x", "9.9.2$(id)", "9.9.2 x", "9") if ok(v)]
GOOD = "971fcd7150ca4ba04852c0b2ca0d2d0ab9468e14b03473eab19528809914c76b"
OLD = "distributionUrl=http\\://nexus/x/gradle-9.9.2-bin.zip\ndistributionSha256Sum=" + "a" * 64 + "\n"
def run(curl_out, curl_rc=0, text=OLD):
    d = os.path.join(w, "gw"); os.makedirs(os.path.join(d, "gradle/wrapper"), exist_ok=True)
    bin_ = os.path.join(w, "gwbin"); os.makedirs(bin_, exist_ok=True)
    open(os.path.join(bin_, "curl"), "w").write(f"#!/bin/sh\necho \"$*\" > {w}/gw-curl-args\nprintf '%s\\n' '{curl_out}'\nexit {curl_rc}\n")
    os.chmod(os.path.join(bin_, "curl"), 0o755)
    f = os.path.join(d, "gradle/wrapper/gradle-wrapper.properties"); open(f, "w").write(text)
    r = subprocess.run(["sh", "-c", cmd.replace("{{{newVersion}}}", "9.9.2")], cwd=d, env={**os.environ, "PATH": bin_ + ":" + os.environ["PATH"]},
                       capture_output=True, text=True)
    return r.returncode, open(f).read()
rc, good = run(GOOD)
args = open(os.path.join(w, "gw-curl-args")).read().strip()
rc2, garbage = run("<html>not a sum</html>")
rc3, failed = run("", 22)
rc4, none = run(GOOD, text="distributionUrl=x\n")
print(ok("9.9.2"), bad, rc, good.splitlines()[1] == "distributionSha256Sum=" + GOOD, "--proto =https" in args and "services.gradle.org/distributions/gradle-9.9.2-bin.zip.sha256" in args,
      rc2 != 0 and garbage == OLD, rc3 != 0 and failed == OLD, rc4 == 0 and none == "distributionUrl=x\n")
PYGW
)" "True [] 0 True True True True True"
# The wave (operator 2026-11-23: ~30 minors a unit each was a week of runs): every patch, digest and minor on
# renovate/wave-patches - a store's minor its own unit (the rule's list is scripts/upgrade-stores.json's packages), a
# family's minor its family's, a major its own. Each update's branch resolved as Renovate merges the rules: in order, a
# later one overriding, the group object merged - the wave's group.branchTopic stays on a family that names none
# (Woodpecker's manual-wave-patches, 2026-11-16); its patterns as Renovate's string-match reads them (a list of
# negations alone: every one must hold)
check "the preset: patches, digests and minors on the wave - a store's minor its own, a family's its family's" \
  "$("$PY" - <<'PYWAVE'
import json, sys
sys.path.insert(0, "tests/ansible/unit")
from renovate_preset import PRESET, branch
t = json.load(open("scripts/upgrade-stores.json"))
wave = next(r for r in PRESET["packageRules"] if r.get("groupSlug") == "wave-patches" and r.get("matchUpdateTypes") == ["minor"])
cases = [
    ("nginx", "patch"), ("nginx", "digest"), ("nginx", "minor"), ("valkey/valkey", "minor"), ("prom/alertmanager", "minor"),
    ("ghcr.io/cloudnative-pg/postgresql", "digest"), ("ghcr.io/cloudnative-pg/postgresql", "minor"),
    ("kube-prometheus-stack", "minor"), ("grafana", "minor"), ("strimzi-kafka-operator", "minor"), ("scylla-operator", "minor"),
    ("argo-cd", "minor"), ("hashicorp/vault", "minor"), ("forgejo/forgejo", "minor"), ("istiod", "minor", "1.32.0"),
    ("registry.k8s.io/kube-apiserver", "minor", "1.37.2"), ("scylladb/scylla", "minor", "2026.3.6"),
    ("https://github.com/kubernetes-sigs/gateway-api", "minor", "1.7.0"), ("ghcr.io/woodpecker-ci/helm/woodpecker", "minor"),
    ("quay.io/strimzi/kafka", "minor"), ("clickhouse/clickhouse-server", "minor"), ("grafana/grafana", "minor"),
    ("hashicorp/consul", "minor")]
print([branch(c[0], c[1], version=c[2] if len(c) > 2 else "1.2.0") for c in cases],
      branch("nginx", "minor", "clusters/production/schnappy-test/values.yaml"),
      sorted(p[1:] for p in wave["matchPackageNames"]) == sorted({p for s in t["stores"] for p in s["packages"]}))
PYWAVE
)" "['wave-patches', 'wave-patches', 'wave-patches', 'wave-patches', 'wave-patches', 'wave-patches', 'own', 'observability', 'grafana-1.2', 'data-operators', 'data-operators', 'argocd', 'pi-services', 'pi-services', 'istio-1.32', 'kubernetes-1.37', 'scylladb-2026.3', 'gateway-api-1.7', 'manual-woodpecker', 'data-operators', 'clickhouse-1.2', 'grafana-1.2', 'pi-services'] test-wave-patches True"
# The observability review (2026-11-25): Grafana's and ClickHouse's minors rode in renovate/observability, labelled
# upgrade-cycle alone - a store's version outside its own unit, so nothing backed it up (Grafana migrates its database
# one way on every new version from 13 on). Each its own unit now, renovate/<store>-<X.Y>, labelled one-way - its name
# the store's in scripts/upgrade-stores.json; Grafana's k6 (no store) stays in observability
check "the preset: Grafana's and ClickHouse's minors each a one-way unit of its own, named for its store; k6 in observability" \
  "$("$PY" - <<'PYSTOREMIN'
import json, re, sys
sys.path.insert(0, "tests/ansible/unit")
from renovate_preset import branch, resolved
t = {s["store"]: s for s in json.load(open("scripts/upgrade-stores.json"))["stores"]}
got = [(p, branch(p, "minor", version=v), "one-way" in resolved(p, "minor").get("addLabels", []))
       for p, v in (("grafana", "13.3.2"), ("grafana/grafana", "13.3.2"), ("clickhouse/clickhouse-server", "26.8.1"))]
print(got, [bool(re.search(t[s]["units"], b)) for s, (_, b, _) in zip(("grafana", "grafana", "clickhouse"), got)],
      branch("grafana/k6", "minor", version="1.8.3"), "one-way" in resolved("grafana/k6", "minor").get("addLabels", []))
PYSTOREMIN
)" "[('grafana', 'grafana-13.3', True), ('grafana/grafana', 'grafana-13.3', True), ('clickhouse/clickhouse-server', 'clickhouse-26.8', True)] [True, True, True] observability False"
# The wave-patches review (2026-11-23): SonarQube a store of its own (every release migrates its database one way) - its
# updates out of the wave and the majors, on renovate/sonarqube-<N>.x, labelled one-way. Woodpecker's own database and
# Renovate's image stay in the cycle's units (operator 2026-11-23: a manual unit defeats the automation - never a
# manual- unit for them): the runner waits for an idle Woodpecker before a merge that restarts its database, and the
# copy proof smoke-runs a new Renovate image
check "the preset: SonarQube a one-way unit of its own; Woodpecker's database and Renovate's image in the wave, no manual unit" \
  "$("$PY" - <<'PYSPLIT'
import sys
sys.path.insert(0, "tests/ansible/unit")
from renovate_preset import branch, resolved
print([branch("sonarqube", k, version="26.10.0") for k in ("patch", "minor", "major")],
      ["one-way" in resolved("sonarqube", k).get("addLabels", []) for k in ("minor", "major")],
      branch("ghcr.io/cloudnative-pg/postgresql", "digest", path="clusters/production/woodpecker/manifests/postgres.yaml"),
      branch("ghcr.io/cloudnative-pg/postgresql", "digest", path="clusters/production/schnappy-production-data/values.yaml"),
      [branch("renovate/renovate", k, path="scripts/upgrade-renovate.sh") for k in ("patch", "minor", "digest")])
PYSPLIT
)" "['sonarqube-26.x', 'sonarqube-26.x', 'sonarqube-26.x'] [True, True] wave-patches wave-patches ['wave-patches', 'wave-patches', 'wave-patches']"
# The majors that can be undone in one unit too (operator 2026-11-23): renovate/wave-majors, each package's newest
# major alone (two majors of one package in one branch collide - Renovate keeps either); a store's major (one-way,
# backed up first) and a release line's (Kubernetes, Cilium, Istio, the Gateway API, ScyllaDB) each its own unit - the
# rule's list exactly the stores' packages and the release lines' rule's (Woodpecker's newest alone too: its updates
# share manual-woodpecker, where two majors would collide)
check "the preset: majors that can be undone on wave-majors, the newest alone - a store's and a release line's major its own" \
  "$("$PY" - <<'PYMAJORS'
import json, sys
sys.path.insert(0, "tests/ansible/unit")
from renovate_preset import PRESET, branch, resolved
t = json.load(open("scripts/upgrade-stores.json"))
R = PRESET["packageRules"]
group = next(r for r in R if r.get("groupSlug") == "wave-majors")
newest = next(r for r in R if r.get("separateMultipleMajor") is False)
lines = next(r for r in R if r.get("separateMultipleMinor") is True)
alone = {p for s in t["stores"] for p in s["packages"]} | set(lines["matchPackageNames"])
cases = ["kube-prometheus-stack", "grafana/k6", "postgres", "nginx", "argo-cd", "ghcr.io/cloudnative-pg/postgresql",
         "hashicorp/vault", "hashicorp/consul", "scylladb/scylla", "quay.io/strimzi/kafka", "grafana/grafana",
         "registry.k8s.io/kube-apiserver", "istiod", "cilium", "https://github.com/kubernetes-sigs/gateway-api",
         "ghcr.io/woodpecker-ci/helm/woodpecker"]
print([branch(c, "major") for c in cases], branch("nginx", "major", "clusters/production/schnappy-test/values.yaml"),
      [resolved(c).get("separateMultipleMajor", PRESET["separateMultipleMajor"]) for c in cases],
      {p[1:] for p in group["matchPackageNames"]} == alone, newest["matchPackageNames"] == group["matchPackageNames"],
      "major" in resolved("kube-prometheus-stack", "major").get("addLabels", []))
PYMAJORS
)" "['wave-majors', 'wave-majors', 'wave-majors', 'wave-majors', 'wave-majors', 'own', 'own', 'own', 'own', 'own', 'own', 'own', 'own', 'own', 'own', 'manual-woodpecker'] test-wave-majors [False, False, False, False, False, True, True, True, True, True, True, True, True, True, True, False] True True True"
if [ "$fails" = 0 ]; then echo "upgrade-renovate: ALL-PASS"; else echo "upgrade-renovate: $fails FAILED"; exit 1; fi
