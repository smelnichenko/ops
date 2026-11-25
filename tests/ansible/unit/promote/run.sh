#!/bin/bash
# scripts/promote.sh and its two tasks (operator 2026-11-20: no mode variable - promote:check prints the plan, promote:run
# writes it; CONFIRM refused by both). Against a throwaway infra (a bare origin, a checkout, a second checkout that pushes
# as CD does): the plan read from the remote's newest test tags, nothing committed by a check; a run rewrites only the
# services named (none: every one), the quotes kept, committed and pushed; a name it does not know, a dirty checkout -
# refused with nothing written; a production line it cannot rewrite (a bare tag) - nothing committed. The tasks: preconditions run
# as go-task runs them (sh -c, a {{.NAME}} rendered to its value or empty), commands against a recording
# script.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
check() {  # name got want
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got  $2"; echo "    want $3"; fails=$((fails + 1)); fi
}
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
TEST=clusters/production/schnappy-test-apps/values.yaml
PROD=clusters/production/schnappy-production-apps/values.yaml
fresh() {  # a new origin and checkout: monitor, admin and site moved on test, masi not; chat, chess, game-scp not on test
  rm -rf "$W/origin.git" "$W/infra" "$W/cd"
  git init -q --bare -b main "$W/origin.git"
  git clone -q "$W/origin.git" "$W/infra" 2> /dev/null
  mkdir -p "$W/infra/$(dirname "$TEST")" "$W/infra/$(dirname "$PROD")"
  printf '%s\n' 'monitor:' '  image:' '    tag: "t-mon"  # monitor' 'admin:' '  tag: "t-adm" # admin' 'masi:' '  tag: "same"  # masi' \
    'site:' '  tag: "t-site"  # site' > "$W/infra/$TEST"
  printf '%s\n' 'monitor:' '  image:' '    tag: "p-mon"  # monitor' 'admin:' '  tag: "p-adm" # admin' 'masi:' '  tag: "same"  # masi' \
    'site:' "  tag: ${1:-\"p-site\"}  # site" > "$W/infra/$PROD"
  git -C "$W/infra" add -A && git -C "$W/infra" commit -q -m init && git -C "$W/infra" push -q origin main 2> /dev/null
}
promote() {  # [args...]: the script's exit code; its output in $W/out
  INFRA="$W/infra" scripts/promote.sh "$@" > "$W/out" 2>&1
  echo $?
}
head_of() { git -C "$W/origin.git" rev-parse main; }
prod_line() { grep "# $1" "$W/infra/$PROD" | sed 's/^ *//'; }

fresh
h0=$(head_of)
check "a service it does not know: refused" "$(promote --run monitr) $(grep -c "no service 'monitr'" "$W/out")" "2 1"
check "a check, none named: the plan for every service - moved, up to date, not on test - and nothing committed or pushed" \
  "$(promote) $(grep -cE '^  \+ (monitor: p-mon -> t-mon|admin: p-adm -> t-adm|site: p-site -> t-site)$' "$W/out") $(grep -c '^  = masi: same (up to date)$' "$W/out") $(grep -cE '^  ! (chat|chess|game-scp): not found' "$W/out") $(grep -c 'The plan only - task promote:run commits and pushes it' "$W/out") $([ "$(head_of)" = "$h0" ] && [ -z "$(git -C "$W/infra" status --porcelain)" ] && echo untouched)" \
  "0 3 1 3 1 untouched"
check "a run of one service: only it rewritten, its quotes kept, committed and pushed" \
  "$(promote --run monitor) $(prod_line monitor) | $(prod_line admin) | $(prod_line site) | $(git -C "$W/origin.git" log -1 --format=%s main) $(git -C "$W/origin.git" show main:"$PROD" | grep -c 'tag: "t-mon"  # monitor')" \
  '0 tag: "t-mon"  # monitor | tag: "p-adm" # admin | tag: "p-site"  # site | promote(prod): monitor from test 1'
# CD pushed a newer test tag since the checkout was last pulled: the run reads the remote's
git clone -q "$W/origin.git" "$W/cd" 2> /dev/null
sed -i 's/"t-adm"/"t-adm2"/' "$W/cd/$TEST" && git -C "$W/cd" commit -q -am "cd: admin" && git -C "$W/cd" push -q origin main 2> /dev/null
check "a run after CD pushed: the newest test tag promoted (the checkout pulled first)" \
  "$(promote --run admin) $(git -C "$W/origin.git" show main:"$PROD" | grep -c 'tag: "t-adm2" # admin')" "0 1"
h1=$(head_of)
check "nothing moved for the services named: nothing committed" "$(promote --run masi) $(grep -c 'Nothing to promote' "$W/out") $([ "$(head_of)" = "$h1" ] && echo same)" "0 1 same"
echo "x" >> "$W/infra/README"
check "a dirty checkout: refused, nothing pulled or written" "$(promote --run site) $(grep -c 'uncommitted changes' "$W/out") $([ "$(head_of)" = "$h1" ] && echo same)" "1 1 same"
# production's line bare (CD's promote step once wrote it so, 2026-10-28): the rewrite cannot match it - nothing committed
fresh 'p-site'
h2=$(head_of)
check "a production tag it cannot rewrite (bare, no quotes): refused, nothing committed, the checkout clean" \
  "$(promote --run site) $(grep -c 'NOT WRITTEN: site' "$W/out") $([ "$(head_of)" = "$h2" ] && [ -z "$(git -C "$W/infra" status --porcelain)" ] && echo clean)" "1 1 clean"
fresh
check "a run with none named: every service on test whose tag moved, in one commit (all the same)" \
  "$(promote --run) $(git -C "$W/origin.git" log -1 --format=%s main) $(git -C "$W/origin.git" show main:"$PROD" | grep -cE 'tag: "t-(mon|adm|site)"') $(fresh; promote --run all) $(git -C "$W/origin.git" log -1 --format=%s main) $(git -C "$W/origin.git" show main:"$PROD" | grep -cE 'tag: "t-(mon|adm|site)"')" \
  "0 promote(prod): monitor admin site from test 3 0 promote(prod): monitor admin site from test 3"

# the tasks
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
got=$(W="$W" "$PY" - <<'PYCHECK'
import os, re, subprocess
import yaml
W = os.environ["W"]
tasks = yaml.safe_load(open("Taskfile.yml"))["tasks"]
def render(text, given):
    def one(m):
        return given.get(m.group(1), "")
    out = re.sub(r'\{\{\.(\w+)\}\}', one, text)
    assert "{{" not in out, f"a template this harness does not render: {out}"
    return out
TB = os.path.join(W, "tb")
os.makedirs(os.path.join(TB, "scripts"), exist_ok=True)
open(os.path.join(TB, "scripts", "promote.sh"), "w").write('#!/bin/sh\necho "promote.sh $*" >> "$REC"\n')
os.chmod(os.path.join(TB, "scripts", "promote.sh"), 0o755)
def ran(name, given):
    t = tasks[name]
    if not all(subprocess.run(["sh", "-c", render(p["sh"], given)], cwd=TB).returncode == 0 for p in t.get("preconditions", [])):
        return "refused"
    rec = os.path.join(TB, "rec")
    if os.path.exists(rec):
        os.remove(rec)
    for c in t["cmds"]:
        subprocess.run(["sh", "-c", render(c if isinstance(c, str) else c.get("cmd", ""), given)], cwd=TB, env={**os.environ, "REC": rec})
    return open(rec).read().strip() if os.path.exists(rec) else "nothing"
print([k for k in tasks if k == "promote:prod" or k.startswith("promote:prod:")],
      [(k, tasks[k].get("prompt"), tasks[k].get("deps"), tasks[k].get("vars")) for k in ("promote:check", "promote:run")])
print(ran("promote:check", {}), ran("promote:check", {"SERVICES": "monitor masi"}),
      [v for v in ("1", "0", "yes", "true") if ran("promote:check", {"CONFIRM": v}) != "refused"], sep="|")
print(ran("promote:run", {}), ran("promote:run", {"SERVICES": "all"}), ran("promote:run", {"SERVICES": "monitor masi"}),
      [v for v in ("1", "0", "yes", "true") if ran("promote:run", {"CONFIRM": v, "SERVICES": "monitor"}) != "refused"], sep="|")
PYCHECK
)
check "task promote:prod gone; promote:check and promote:run: no prompt, dependency or variable of their own" \
  "$(sed -n 1p <<< "$got")" "[] [('promote:check', None, None, None), ('promote:run', None, None, None)]"
check "promote:check: the plan - every service (none named) or the services named; CONFIRM at any value refused" \
  "$(sed -n 2p <<< "$got")" "promote.sh|promote.sh monitor masi|[]"
check "promote:run: --run - every service (none named), all, or the services named; CONFIRM at any value refused" \
  "$(sed -n 3p <<< "$got")" "promote.sh --run|promote.sh --run all|promote.sh --run monitor masi|[]"
if [ "$fails" = 0 ]; then echo "promote: ALL-PASS"; else echo "promote: $fails FAILED"; exit 1; fi
