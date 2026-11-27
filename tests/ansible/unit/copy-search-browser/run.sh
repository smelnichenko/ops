#!/bin/bash
# The copy's data check, its fourth play (tests/ansible/copy/data-check.yml): OpenSearch and the browser doing their work
# after a change - readiness probes that answer while neither does (OpenSearch's _cluster/health is 200 on a red
# cluster; browserless's /pressure answers while Chrome cannot start). Against a stub kubectl playing each: OpenSearch's
# status judged (red fails, yellow and green pass), a document of this run written, found and its index deleted, in that
# order; the browser's page of this run rendered with its script run (a page without it fails), the token still required
# (a 200 without it fails), the token never on a command line here (the pod's shell expands it), the page on stdin. Then
# the play: behind the Vagrant guard, a running pod of each, the run's id the first play's.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
# kubectl: each exec recorded (its arguments, then what it was handed on stdin); OpenSearch's and the browser's answers
# as the case says
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/bash
printf '%s\n' "kubectl $*" >> "$W/calls"
case " $* " in
  *" exec -i "*) printf 'stdin: %s\n' "$(cat)" >> "$W/calls" ;;
esac
a=" $* "
case "$a" in
  # waiting for yellow, a red cluster is a 408 (curl -f fails) - unless the case has it answered (a guard of its own);
  # without the wait, OpenSearch answers 200 whatever the status
  *"_cluster/health?wait_for_status=yellow"*)
    [ "${OS_STATUS:-green}" != red ] || [ -n "${OS_RED_200:-}" ] || { echo "curl: (22) The requested URL returned error: 408" >&2; exit 22; }
    echo "{\"status\": \"${OS_STATUS:-green}\"}" ;;
  *"_cluster/health"*) echo "{\"status\": \"${OS_STATUS:-green}\"}" ;;
  *" -X PUT "*"/_doc/1?refresh=true"*) echo '{"result": "created"}' ;;
  *"/_search?q=run:"*) echo "{\"hits\": {\"total\": {\"value\": ${OS_HITS:-1}}}}" ;;
  *" -X DELETE "*) echo '{"acknowledged": true}' ;;
  *" http://127.0.0.1:9200/ "*) echo '{"version": {"number": "3.9.0"}}' ;;
  *"content?token=\$TOKEN"*)
    run=$(sed -n 's/.*copy-check \([0-9A-Za-z]*\):.*/\1/p' "$W/calls" | tail -1)
    if [ "${PAGE:-rendered}" = rendered ]; then echo "<html><body><p id=\"x\">copy-check $run:42</p></body></html>"
    else echo "<html><body><p id=\"x\">copy-check $run:</p></body></html>"; fi ;;
  *" http://127.0.0.1:3000/content "*) echo "${NO_TOKEN:-401}" ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
STUB
chmod +x "$W/bin/kubectl"
W=$W TOKEN=the-pods-token-never-here exec "$PY" - <<'PY_SB'
import os, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render  # noqa: E402
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    if got == want:
        print("PASS " + name)
    else:
        print("FAIL " + name + "\n    got  " + repr(got) + "\n    want " + repr(want))
        fails += 1
plays = yaml.safe_load(open("tests/ansible/copy/data-check.yml"))
play = next(p for p in plays if p["name"] == "OpenSearch and the browser doing their work")
T = {t["name"].split(" - ")[0]: t for t in play["tasks"]}
RUN = "20261127T230000123456789"
PODS = {"results": [{"stdout": "schnappy-production-opensearch-0"}, {"stdout": "schnappy-production-masi-browser-abc"}]}
def run(task, **env):
    calls = os.path.join(W, "calls")
    if os.path.exists(calls):
        os.remove(calls)
    cmd = render(task["ansible.builtin.shell"]["cmd"], kubectl=render(play["vars"]["kubectl"], **play["vars"]), _pods=PODS, run_id=RUN)
    r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True,
                       env={**os.environ, "PATH": W + "/bin:" + os.environ["PATH"], **env})
    result = {"rc": r.returncode, "stdout": r.stdout, "stdout_lines": r.stdout.splitlines()}
    reg = task["register"]
    ok = condition(task["until"], **{reg: result})
    return ok, (open(calls).read().splitlines() if os.path.exists(calls) else [])
os_t = T["OpenSearch"]
ok, calls = run(os_t)
index = "copy-check-" + RUN.lower()
order = [next((i for i, c in enumerate(calls) if is_(c)), -1) for is_ in
         (lambda c: "_cluster/health?wait_for_status=yellow" in c, lambda c: c.endswith(" http://127.0.0.1:9200/"),
          lambda c: " -X PUT " in c, lambda c: "/_search?q=run:" + RUN in c, lambda c: " -X DELETE " in c)]
check("OpenSearch: green, the document found - passes; its status, the version, the write, the search, the delete, in that order",
      (ok, order == sorted(order) and -1 not in order), (True, True))
check("  the index this run's own (lower case: an index name is), in the opensearch container of the pod found",
      (all(index in c for c in calls if "-X PUT" in c or "-X DELETE" in c or "_search" in c),
       all(" exec schnappy-production-opensearch-0 -c opensearch -- curl -fsS " in c for c in calls)), (True, True))
check("  yellow passes; red (the wait for yellow refused) fails; the document not found fails",
      [run(os_t, OS_STATUS=s, OS_HITS=h)[0] for s, h in (("yellow", "1"), ("red", "1"), ("green", "0"))], [True, False, False])
check("  red answered (200) all the same: fails on the status read - each guard its own",
      run(os_t, OS_STATUS="red", OS_RED_200="1")[0], False)
br_t = T["The browser"]
ok, calls = run(br_t)
check("browser: a page of this run rendered with its script run, 401 without the token - passes", ok, True)
check("  the script not run (the page as sent) fails; a request without the token answered (200) fails",
      [run(br_t, PAGE="raw")[0], run(br_t, NO_TOKEN="200")[0]], [False, False])
argv = [c for c in calls if c.startswith("kubectl ")]
check("  the token expanded in the pod (\\$TOKEN on the line, quoted), never here; the page on stdin, carrying this run",
      (any("content?token=$TOKEN" in c for c in argv), any("the-pods-token-never-here" in c for c in calls),
       any(c.startswith("stdin: ") and RUN in c and "6 * 7" in c for c in calls),
       all(" exec -i schnappy-production-masi-browser-abc -c chromium -- " in c or " exec -i " not in c for c in argv)),
      (True, False, True, True))
check("the play: on the copy's target, behind the Vagrant guard first; a running pod of OpenSearch and of the browser, by component",
      (play["hosts"], list(play["tasks"][0].values())[1], T["The OpenSearch and browser pods (a running one each)"]["loop"],
       "--field-selector=status.phase=Running" in T["The OpenSearch and browser pods (a running one each)"]["ansible.builtin.command"]),
      ("target", "../vagrant-only.yml", ["opensearch", "masi-browser"], True))
pt = T["The OpenSearch and browser pods (a running one each)"]
check("  a pod restarting after the change waited for (two minutes at most); none running, or kubectl failing, not taken",
      (pt["retries"] * pt["delay"], condition(pt["until"], _pods={"rc": 0, "stdout": "p-0"}),
       condition(pt["until"], _pods={"rc": 0, "stdout": ""}), condition(pt["until"], _pods={"rc": 1, "stdout": "p-0"})),
      (120, True, False, False))
first = plays[0]["tasks"]
check("  the run's id the first play's (set before, on the same hosts), and this play after it",
      (any("run_id" in (t.get("ansible.builtin.set_fact") or {}) for t in first), plays[0]["hosts"], plays.index(play) > 0),
      (True, "target", True))
print("copy-search-browser: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_SB
