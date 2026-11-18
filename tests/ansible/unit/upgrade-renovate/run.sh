#!/bin/bash
# task upgrade (the operator's decisions of 2026-11-15): Renovate on the workstation, then the runner - one task started
# by hand, no CI cron. scripts/upgrade-renovate.sh run against a docker that records what it is given: the image pinned,
# the bot's token by name and never on a command line, no bind mount, the allowed post-upgrade command from
# renovate/allowed-commands.json, lookup only when asked, a GitHub token only when there is one; Renovate's failure, a
# logged error or fatal, or a repository it did not read through (no renovate.json on its main: "disabled-no-config")
# stopping the task before the runner; refused beside a running runner (its lock). The task: LOOKUP true or false alone,
# the applying run refused until the runner's record of a clean shadow proof, the runner given the bot's token by
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
# x.y.z, never a tag that moves
pin=$(sed -n 's/^image=//p' scripts/upgrade-renovate.sh)
[[ $pin =~ ^renovate/renovate:[0-9]+\.[0-9]+\.[0-9]+$ ]] && exact=exact || exact="not exact: $pin"
check "a run: docker run --rm, the image pinned exactly (x.y.z) and last" "$rc $(head -2 "$W/argv" | tr '\n' ' ')$(tail -1 "$W/argv") $exact" \
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
check "no GitHub token: none passed (an empty one was a 401)" "$(grep -c GITHUB_COM_TOKEN "$W/argv") $(grep -c '^github=unset$' "$W/env")" "0 1"
ARGS=(--lookup)
check "--lookup: Renovate reads only" "$(run RENOVATE_TOKEN=$TOKEN) $(grep -cx RENOVATE_DRY_RUN=lookup "$W/argv")" "0 1"
ARGS=()
# --apps: monitor's and masi's Renovate (task renovate:apps) - those two repos alone, read through; with --lookup too
APPS_LOG=$(printf '%s\n' ' INFO: Repository started (repository=schnappy/monitor)' ' INFO: Repository finished (repository=schnappy/monitor)' \
  '       "result": "done",' ' INFO: Repository started (repository=schnappy/masi)' ' INFO: Repository finished (repository=schnappy/masi)' \
  '       "result": "done",')
ARGS=(--apps)
check "--apps: monitor and masi alone, a real run, both read through" \
  "$(run RENOVATE_TOKEN=$TOKEN FAKE_LOG="$APPS_LOG") $(grep -cx 'RENOVATE_REPOSITORIES=schnappy/monitor,schnappy/masi' "$W/argv") $(grep -c RENOVATE_DRY_RUN "$W/argv") $(grep -c 'schnappy/infra' "$W/argv")" "0 1 0 0"
check "  one of them not read through: the task fails" "$(run RENOVATE_TOKEN=$TOKEN FAKE_LOG="$(head -3 <<< "$APPS_LOG")")" "1"
ARGS=(--apps --lookup)
check "  with --lookup: read only" "$(run RENOVATE_TOKEN=$TOKEN FAKE_LOG="$APPS_LOG") $(grep -cx RENOVATE_DRY_RUN=lookup "$W/argv")" "0 1"
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
TB = os.path.join(W, "tb")
os.makedirs(TB, exist_ok=True)
def admitted(lookup, runner, shadow="false", ps=None):
    # run where the task runs (ops' root - a directory of the harness's own: the runner's shadow record its to make)
    return all(subprocess.run(["sh", "-c", render(p, lookup, runner, shadow)], cwd=TB).returncode == 0 for p in (pre if ps is None else ps))
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
before = sorted(f"{l}/{r}/{x}" for l in TF for r in TF for x in TF if admitted(l, r, x))
os.makedirs(os.path.join(TB, ".upgrade-cycle"), exist_ok=True)
open(os.path.join(TB, ".upgrade-cycle/shadow-proven"), "w").write("unit wave-patches\n")
after = sorted(f"{l}/{r}/{x}" for l in TF for r in TF for x in TF if admitted(l, r, x))
os.remove(os.path.join(TB, ".upgrade-cycle/shadow-proven"))
print(len(cmds), "PRODUCTION" in t.get("prompt", "") and "radar" in t.get("prompt", ""),
      t["vars"]["LOOKUP"], t["vars"]["RUNNER"], t["vars"]["SHADOW"], t.get("deps"),
      any("ignore_error" in c for c in t["cmds"] if isinstance(c, dict)), before, after,
      [v for v in VALUES if all(admitted(v if i == 0 else "false", v if i == 1 else "false", v if i == 2 else "true", values_only)
                                for i in range(3))], sep="|")
print(ran("true", "true"), ran("false", "false"), ran("false", "true", "true"), ran("false", "true"), sep="|")
PYCHECK
)
check "task upgrade: a prompt naming production and the radar, LOOKUP false, RUNNER true and SHADOW false by default, no step's failure ignored; admitted: LOOKUP=true, RUNNER=false or SHADOW=true until the runner recorded the cycle's first clean shadow proof (.upgrade-cycle/shadow-proven), every mode after it; each value true or false alone (1, yes, TRUE, empty never)" \
  "$(head -1 <<< "$got")" "4|True|{{.LOOKUP | default \"false\"}}|{{.RUNNER | default \"true\"}}|{{.SHADOW | default \"false\"}}|['deploy:install']|False|['false/false/false', 'false/false/true', 'false/true/true', 'true/false/false', 'true/false/true', 'true/true/false', 'true/true/true']|['false/false/false', 'false/false/true', 'false/true/false', 'false/true/true', 'true/false/false', 'true/false/true', 'true/true/false', 'true/true/true']|['true', 'false']"
check "task upgrade's commands as run: LOOKUP=true - Renovate reads, nothing else; RUNNER=false - Renovate's branches alone; SHADOW=true - the lock, the gates, Renovate, the runner --shadow with the bot's token; the applying runner the same without --shadow" \
  "$(tail -1 <<< "$got")" "['upgrade-renovate.sh --lookup token=none']|['upgrade-renovate.sh  token=none']|['copy-lock.sh  token=none', 'upgrade-cycle.sh --preflight token=none', 'upgrade-renovate.sh  token=none', 'upgrade-cycle.sh --shadow token=the-bots']|['copy-lock.sh  token=none', 'upgrade-cycle.sh --preflight token=none', 'upgrade-renovate.sh  token=none', 'upgrade-cycle.sh  token=the-bots']"
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
                found.append((g.group("depName"), bool(re.fullmatch(r"\d+\.\d+\.\d+", g.group("currentValue"))), m.get("datasourceTemplate")))
print(found)
PYSELF
)" "[('renovate/renovate', True, 'docker')]"
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
if [ "$fails" = 0 ]; then echo "upgrade-renovate: ALL-PASS"; else echo "upgrade-renovate: $fails FAILED"; exit 1; fi
