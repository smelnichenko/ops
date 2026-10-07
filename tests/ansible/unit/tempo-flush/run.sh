#!/bin/bash
# scripts/tempo-flush.py against a kubectl stub answering Tempo's /metrics from a script of readings (blocks flushed,
# flush queue length, failed flushes) and recording /flush: Tempo's /flush only queues the flush and answers at once,
# and the merge that replaces Tempo's major followed it straight away - the spans still in the WAL were lost to the
# restart. Now the call waits until a block has been flushed since, and the queue is empty on two readings in a row;
# a failed flush, a failed call, no flush within the attempts, or a metric missing fail.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import importlib.machinery, importlib.util, os, sys, tempfile
l = importlib.machinery.SourceFileLoader("tf", "scripts/tempo-flush.py")
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("tf", l))
l.exec_module(m)
m.POLL, m.ATTEMPTS = 0, 6
work = tempfile.mkdtemp()
stub = os.path.join(work, "kubectl")
open(stub, "w").write("""#!/bin/bash
path=${@: -1}
case "$path" in
  */flush) echo flush >> "$W/calls"; exit "${FLUSH_RC:-0}" ;;
  */metrics)
    echo metrics >> "$W/calls"
    n=$(grep -c metrics "$W/calls")
    read -r flushed queue failed < <(sed -n "${n}p" "$W/readings")
    [ -n "$flushed" ] || read -r flushed queue failed < <(tail -n 1 "$W/readings")
    echo "# HELP tempo_ingester_blocks_flushed_total The total number of blocks flushed"
    [ -n "${NO_QUEUE:-}" ] || echo "tempo_ingester_flush_queue_length $queue"
    echo "tempo_ingester_blocks_flushed_total $flushed"
    echo "tempo_ingester_failed_flushes_total $failed"
    echo "tempo_ingester_live_traces{tenant=\\"single-tenant\\"} 23" ;;
esac
""")
os.chmod(stub, 0o755)
os.environ["PATH"] = work + ":" + os.environ["PATH"]
os.environ["W"] = work
fails = 0
def case(name, readings, want_ok, want_calls, want_msg=None, **env):
    global fails
    open(os.path.join(work, "readings"), "w").write("\n".join(readings) + "\n")
    open(os.path.join(work, "calls"), "w").close()
    for k in ("FLUSH_RC", "NO_QUEUE"):
        os.environ.pop(k, None)
    os.environ.update(env)
    try:
        m.flush(["kubectl"])
        ok, msg = True, ""
    except SystemExit as e:
        ok, msg = False, str(e)
    calls = open(os.path.join(work, "calls")).read().split()
    got = (ok, calls, bool(want_msg is None or want_msg in msg))
    want = (want_ok, want_calls, True)
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got} ({msg}), want {want}"))
M, F = "metrics", "flush"
case("a block flushed since, the queue empty twice: done", ["5 0 0", "5 1 0", "6 0 0", "6 0 0"], True, [M, F, M, M, M])
case("the counter up while a block still queued: waited for the queue",
     ["5 0 0", "6 1 0", "6 1 0", "6 0 0", "6 0 0"], True, [M, F, M, M, M, M])
case("the counter up and the queue empty once, then a block queued: one empty reading is not enough",
     ["5 0 0", "6 0 0", "6 1 0", "7 0 0", "7 0 0"], True, [M, F, M, M, M, M])
case("no block flushed within the attempts: fails", ["5 0 0"], False, [M, F] + [M] * 6, "no block flushed")
case("a flush failed: fails at once", ["5 0 0", "5 1 1"], False, [M, F, M], "failed")
case("the flush call failing: fails, nothing waited for", ["5 0 0"], False, [M, F], "flush", FLUSH_RC="1")
case("a metric missing: fails naming it, before any flush", ["5 0 0"], False, [M], "tempo_ingester_flush_queue_length",
     NO_QUEUE="1")
print("tempo-flush: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
