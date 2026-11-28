#!/bin/bash
# The copy's data check, its fourth play (tests/ansible/copy/data-check.yml): OpenSearch and the browser doing their work
# after a change - readiness probes that answer while neither does (OpenSearch's _cluster/health is 200 on a red
# cluster; browserless's /pressure answers while Chrome cannot start). Against a stub kubectl playing each: OpenSearch's
# status judged (red fails, yellow and green pass), a document of this run written, found and its index deleted, in that
# order - deleted on a failure too; the browser's page of this run rendered with its script run (a page without it fails),
# its status read (a 429 not taken: waited out), the token still required (a 200 without it fails), the token never on a
# command line here (the pod's shell expands it), the page on stdin, rendered headed as masi drives it; Centrifugo's
# publication of this run through its API and one through Kafka (events.notifications, its channel in the
# x-centrifugo-channels header) both read back from its history - either missing fails - and its API refusing a wrong key
# (one taken fails), its key never on a command line here; each exec into the workload, never a pod named once. Then the
# play: behind the Vagrant guard, the three workloads ready first (five minutes), the run's id the first play's.
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
  *"/_search?q=run:"*) [ -z "${OS_SEARCH_FAILS:-}" ] || { echo "curl: (22) 503" >&2; exit 22; }
    echo "{\"hits\": {\"total\": {\"value\": ${OS_HITS:-1}}}}" ;;
  *" -X DELETE "*) echo '{"acknowledged": true}' ;;
  *" http://127.0.0.1:9200/ "*) echo '{"version": {"number": "3.9.0"}}' ;;
  # the render: its body, then curl's -w status line
  *"content?token=\$TOKEN"*)
    run=$(sed -n 's/.*copy-check \([0-9A-Za-z]*\):.*/\1/p' "$W/calls" | tail -1)
    if [ "${PAGE:-rendered}" = rendered ]; then printf '<html><body><p id="x">copy-check %s:42</p></body></html>' "$run"
    else printf '<html><body><p id="x">copy-check %s:</p></body></html>' "$run"; fi
    printf '\n%s' "${PAGE_CODE:-200}" ;;
  *" http://127.0.0.1:3000/content "*) echo "${NO_TOKEN:-401}" ;;
  *" get statefulset/schnappy-production-opensearch -o jsonpath={.status.readyReplicas} "*) echo "${OS_READY:-1}" ;;
  *" get deployment/schnappy-production-masi-browser -o jsonpath={.status.readyReplicas} "*) echo "${BR_READY:-1}" ;;
  *" get deployment/schnappy-production-centrifugo -o jsonpath={.status.readyReplicas} "*) echo "${RT_READY:-1}" ;;
  # Centrifugo's API through the pod's wget (sh -c '<script>' <method> <body>): a publish remembered by its channel
  # (unless API_LOST), a history answering a remembered channel's publication, compact as Centrifugo writes it
  *" exec deployment/schnappy-production-centrifugo -c centrifugo -- sh -c "*" publish {"*)
    ch=$(sed -n 's/.* publish {"channel": "\([^"]*\)".*/\1/p' <<< "$a")
    [ -n "${API_LOST:-}" ] || echo "$ch" >> "$W/published"
    echo '{"result":{"offset":1,"epoch":"e"}}' ;;
  *" exec deployment/schnappy-production-centrifugo -c centrifugo -- sh -c "*" history {"*)
    ch=$(sed -n 's/.* history {"channel": "\([^"]*\)".*/\1/p' <<< "$a")
    run=$(sed -n 's/.*copy-check-\([0-9A-Za-z]*\)-.*/\1/p' <<< "$ch")
    if grep -qxF "$ch" "$W/published" 2> /dev/null; then echo "{\"result\":{\"publications\":[{\"data\":{\"run\":\"$run\"},\"offset\":1}],\"epoch\":\"e\",\"offset\":1}}"
    else echo '{"result":{"publications":[],"epoch":"e","offset":0}}'; fi ;;
  # a wrong key: busybox wget's refusal on stderr, exit 1 - unless the case has it taken
  *" exec deployment/schnappy-production-centrifugo -c centrifugo -- wget "*"X-API-Key: copy-check-wrong"*)
    [ -z "${WRONG_OK:-}" ] || exit 0
    echo "wget: server returned error: HTTP/1.1 401 Unauthorized" >&2; exit 1 ;;
  # Kafka's console producer: the line's x-centrifugo-channels header delivers it to that channel (unless KAFKA_LOST)
  *" exec -i pod/schnappy-production-kafka-0 -c kafka -- /opt/kafka/bin/kafka-console-producer.sh "*)
    line=$(sed -n 's/^stdin: //p' "$W/calls" | tail -1)
    ch=$(sed -n 's/^x-centrifugo-channels:\([^	]*\)	.*/\1/p' <<< "$line")
    [ -n "${KAFKA_LOST:-}" ] || [ -z "$ch" ] || echo "$ch" >> "$W/published" ;;
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
play = next(p for p in plays if p["name"] == "OpenSearch, the browser and Centrifugo doing their work")
T = {t["name"].split(" - ")[0]: t for t in play["tasks"]}
V = play["vars"]
RUN = "20261127T230000123456789"
def run(task, **env):
    for f in ("calls", "published"):
        if os.path.exists(os.path.join(W, f)):
            os.remove(os.path.join(W, f))
    calls = os.path.join(W, "calls")
    kubectl = render(V["kubectl"], **V)
    cmd = render(task["ansible.builtin.shell"]["cmd"], kubectl=kubectl, search=V["search"], browser=V["browser"],
                 realtime=V["realtime"], kafka_pod=V["kafka_pod"], run_id=RUN)
    r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True,
                       env={**os.environ, "PATH": W + "/bin:" + os.environ["PATH"], **env})
    result = {"rc": r.returncode, "stdout": r.stdout, "stdout_lines": r.stdout.splitlines()}
    reg = task["register"]
    ok = condition(task["until"], **{reg: result})
    return ok, (open(calls).read().splitlines() if os.path.exists(calls) else []), result
os_t = T["OpenSearch"]
ok, calls, _ = run(os_t)
index = "copy-check-" + RUN.lower()
order = [next((i for i, c in enumerate(calls) if is_(c)), -1) for is_ in
         (lambda c: "_cluster/health?wait_for_status=yellow" in c, lambda c: c.endswith(" http://127.0.0.1:9200/"),
          lambda c: " -X PUT " in c, lambda c: "/_search?q=run:" + RUN in c, lambda c: " -X DELETE " in c)]
check("OpenSearch: green, the document found - passes; its status, the version, the write, the search, the delete, in that order",
      (ok, order == sorted(order) and -1 not in order), (True, True))
check("  the index this run's own (lower case: an index name is); every exec into the workload's opensearch container",
      (all(index in c for c in calls if "-X PUT" in c or "-X DELETE" in c or "_search" in c),
       all(" exec statefulset/schnappy-production-opensearch -c opensearch -- curl -fsS " in c for c in calls)), (True, True))
check("  yellow passes; red (the wait for yellow refused) fails; the document not found fails",
      [run(os_t, OS_STATUS=s, OS_HITS=h)[0] for s, h in (("yellow", "1"), ("red", "1"), ("green", "0"))], [True, False, False])
check("  red answered (200) all the same: fails on the status read - each guard its own",
      run(os_t, OS_STATUS="red", OS_RED_200="1")[0], False)
ok, calls, _ = run(os_t, OS_SEARCH_FAILS="1")
check("  the search failing: fails - and the index deleted all the same", (ok, any(" -X DELETE " in c and index in c for c in calls)), (False, True))
br_t = T["The browser"]
ok, calls, res = run(br_t)
check("browser: a page of this run rendered with its script run (status 200), 401 without the token - passes", (ok, res["stdout_lines"]), (True, ["200", "1", "401"]))
check("  the script not run (the page as sent) fails; a request without the token answered (200) fails; its sessions full "
      "(429) not taken - its status said, the try again",
      [run(br_t, PAGE="raw")[0], run(br_t, NO_TOKEN="200")[0], run(br_t, PAGE_CODE="429")[2]["stdout_lines"][0], run(br_t, PAGE_CODE="429")[0]],
      [False, False, "429", False])
argv = [c for c in calls if c.startswith("kubectl ")]
check("  the token expanded in the pod (\\$TOKEN on the line, quoted), never here; the page on stdin, carrying this run; "
      "every exec into the workload's chromium container",
      (any("content?token=$TOKEN" in c for c in argv), any("the-pods-token-never-here" in c for c in calls),
       any(c.startswith("stdin: ") and RUN in c and "6 * 7" in c for c in calls),
       bool(argv) and all(" exec -i deployment/schnappy-production-masi-browser -c chromium -- " in c for c in argv)),
      (True, False, True, True))
check("  headed, as masi drives it (headless=false on its call): the virtual screen an upgrade can break",
      any("content?token=$TOKEN&headless=false" in c for c in argv), True)
rt_t = T["Centrifugo"]
ok, calls, res = run(rt_t, CENTRIFUGO_HTTP_API_KEY="the-api-key-never-here")
check("Centrifugo: this run's publication through its API and one through Kafka both in its history, a wrong key refused (401) - passes",
      (ok, res["stdout_lines"]), (True, ["1", "1", "401"]))
check("  the API's publication missing from history fails; Kafka's (its consumer not delivering) fails; a wrong key taken fails",
      [run(rt_t, API_LOST="1")[0], run(rt_t, KAFKA_LOST="1")[0], run(rt_t, WRONG_OK="1")[0]], [False, False, False])
argv = [c for c in calls if c.startswith("kubectl ")]
kafka_in = [c for c in calls if c.startswith("stdin: x-centrifugo-channels:")]
check("  its key expanded in the pod ($CENTRIFUGO_HTTP_API_KEY on the line), never here; Kafka's line to events.notifications, "
      "headers parsed, its channel this run's in x-centrifugo-channels; every exec into the workload's container",
      (any("$CENTRIFUGO_HTTP_API_KEY" in c for c in argv), any("the-api-key-never-here" in c for c in calls),
       kafka_in == [f'stdin: x-centrifugo-channels:notifications:copy-check-{RUN}-kafka\t{{"run": "{RUN}"}}'],
       any("--topic events.notifications --reader-property parse.headers=true" in c for c in argv),
       bool(argv) and all(" exec deployment/schnappy-production-centrifugo -c centrifugo -- " in c
                          or " exec -i pod/schnappy-production-kafka-0 -c kafka -- " in c for c in argv)),
      (True, False, True, True, True))
check("  a try waits for the consumer's first poll after a restart (two minutes): retries x delay",
      rt_t.get("retries", 0) * rt_t.get("delay", 0), 120)
check("  a try waits long enough for a busy browser or a slow cluster (two minutes; one): retries x delay",
      (br_t.get("retries", 0) * br_t.get("delay", 0), os_t.get("retries", 0) * os_t.get("delay", 0)), (120, 60))
rt = T["OpenSearch, the browser and Centrifugo ready (a ready replica each)"]
check("the play: on the copy's target, behind the Vagrant guard first; both workloads read ready first (five minutes at most)",
      (play["hosts"], list(play["tasks"][0].values())[1], [render(i, **V) for i in rt["loop"]], rt.get("retries", 0) * rt.get("delay", 0),
       [condition(rt["until"], _ready={"rc": rc, "stdout": out}) for rc, out in ((0, "1"), (0, "0"), (0, ""), (1, "1"))],
       [t["name"] for t in play["tasks"]].index(rt["name"]) < [t["name"] for t in play["tasks"]].index(os_t["name"])),
      ("target", "../vagrant-only.yml", ["statefulset/schnappy-production-opensearch", "deployment/schnappy-production-masi-browser",
                                          "deployment/schnappy-production-centrifugo"],
       300, [True, False, False, False], True))
first = plays[0]["tasks"]
check("  the run's id the first play's (set before, on the same hosts), and this play after it",
      (any("run_id" in (t.get("ansible.builtin.set_fact") or {}) for t in first), plays[0]["hosts"], plays.index(play) > 0),
      (True, "target", True))
print("copy-search-browser: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_SB
