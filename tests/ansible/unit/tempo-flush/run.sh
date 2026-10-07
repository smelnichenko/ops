#!/bin/bash
# scripts/tempo-flush.py against a kubectl stub (the kubeconfig's credentials, Tempo's trace queries by mode, /flush)
# and a curl stub (the marker's push): a marker trace of the script's own is pushed, seen held, Tempo flushed, and the
# script waits until a query of the store alone (?mode=blocks) returns the marker - the metrics it read before passed
# with our block still uploading (the flush queue's gauge drops when a worker takes the work), and refused when the
# head block was empty (nothing to flush). A failed push, a marker never held, a failed flush, a marker never in the
# store - or only in the ingester - fail; the credentials' copies are gone afterwards.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import base64, glob, importlib.machinery, importlib.util, json, os, sys, tempfile
l = importlib.machinery.SourceFileLoader("tf", "scripts/tempo-flush.py")
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("tf", l))
l.exec_module(m)
m.POLL_HELD, m.ATTEMPTS_HELD, m.POLL_STORED, m.ATTEMPTS_STORED = 0, 3, 0, 5
work = tempfile.mkdtemp()
b64 = lambda s: base64.b64encode(s.encode()).decode()
open(os.path.join(work, "config.json"), "w").write(json.dumps({
    "clusters": [{"cluster": {"server": "https://api.test:6443", "certificate-authority-data": b64("CA")}}],
    "users": [{"user": {"client-certificate-data": b64("CERT"), "client-key-data": b64("KEY")}}]}))
open(os.path.join(work, "kubectl"), "w").write("""#!/bin/bash
echo "kubectl $*" >> "$W/calls"
case "$*" in
  *"config view"*) cat "$W/config.json" ;;
  *"/proxy/flush"*) exit "${FLUSH_RC:-0}" ;;
  *"mode=blocks"*)
    n=$(grep -c "mode=blocks" "$W/calls")
    [ "$n" -ge "${STORED_AFTER:-999}" ] && cat "$W/trace" || { echo "trace not found" >&2; exit 1; } ;;
  *"/api/traces/"*) [ -z "${NEVER_HELD:-}" ] && cat "$W/trace" || { echo "trace not found" >&2; exit 1; } ;;
esac
""")
open(os.path.join(work, "curl"), "w").write("""#!/bin/bash
echo "curl $*" >> "$W/calls"
cat > "$W/pushed"
for a in "$@"; do case "$a" in */ca|*/cert|*/key) cp "$a" "$W/seen-$(basename "$a")" ;; esac; done
[ -z "${PUSH_FAILS:-}" ] || { echo "curl: (22) 503" >&2; exit 22; }
python3 -c 'import json, sys; s = json.load(open(sys.argv[1]))["resourceSpans"][0]["scopeSpans"][0]["spans"][0]
print(json.dumps({"batches": [{"scopeSpans": [{"spans": [{"name": s["name"], "traceId": s["traceId"]}]}]}]}))' \
  "$W/pushed" > "$W/trace"
""")
for f in ("kubectl", "curl"):
    os.chmod(os.path.join(work, f), 0o755)
os.environ["PATH"] = work + ":" + os.environ["PATH"]
os.environ["W"] = work
fails = 0
def case(name, want_ok, want, want_msg=None, **env):
    global fails
    for f in ("calls", "pushed", "trace", "seen-ca", "seen-cert", "seen-key"):
        p = os.path.join(work, f)
        if os.path.exists(p):
            os.remove(p)
    open(os.path.join(work, "calls"), "w").close()
    for k in ("FLUSH_RC", "STORED_AFTER", "NEVER_HELD", "PUSH_FAILS"):
        os.environ.pop(k, None)
    os.environ.update(env)
    left = set(glob.glob(os.path.join(tempfile.gettempdir(), "tempo-flush-*")))
    try:
        m.flush(["--kubeconfig", "/etc/kubernetes/admin.conf"])
        ok, msg = True, ""
    except SystemExit as e:
        ok, msg = e.code in (None, 0), str(e)
    calls = []
    for c in open(os.path.join(work, "calls")).read().splitlines():
        calls.append("config" if "config view" in c else "push" if c.startswith("curl") else "flush"
                     if "/proxy/flush" in c else "stored?" if "mode=blocks" in c else "held?" if "/api/traces/" in c
                     else c)
    got = (ok, calls, want_msg is None or want_msg in msg,
           set(glob.glob(os.path.join(tempfile.gettempdir(), "tempo-flush-*"))) - left == set())
    exp = (want_ok, want, True, True)
    fails += got != exp
    print(("PASS " if got == exp else "FAIL ") + name + ("" if got == exp else f": got {got} ({msg}), want {exp}"))
    return calls
C, P, H, F, S = "config", "push", "held?", "flush", "stored?"
case("the marker held, flushed, in the store at the third look: done", True, [C, P, H, F, S, S, S], STORED_AFTER="3")
pushed = json.load(open(os.path.join(work, "pushed")))
span = pushed["resourceSpans"][0]["scopeSpans"][0]["spans"][0]
calls = open(os.path.join(work, "calls")).read()
check = lambda n, g, w: print(("PASS " if g == w else "FAIL ") + n + ("" if g == w else f": got {g}, want {w}"))
for n, g, w in (("the marker: a trace ID of 32 hex, its own span", (len(span["traceId"]), all(c in "0123456789abcdef" for c in span["traceId"])), (32, True)),
                ("pushed to Tempo's OTLP/HTTP port through the API server's proxy, with the kubeconfig's client certificate",
                 ("/schnappy-tempo:4318/proxy/v1/traces" in calls, "https://api.test:6443" in calls,
                  open(os.path.join(work, "seen-cert")).read(), open(os.path.join(work, "seen-key")).read()),
                 (True, True, "CERT", "KEY")),
                ("every Tempo query bounded (--request-timeout)", all("--request-timeout" in c for c in calls.splitlines()
                                                                       if c.startswith("kubectl") and "--raw" in c), True),
                ("the stored marker looked for in the store alone (mode=blocks)", "?mode=blocks" in calls, True)):
    fails += g != w
    check(n, g, w)
case("never in the store within the attempts: fails", False, [C, P, H, F, S, S, S, S, S], "not in Tempo's store")
case("held by the ingester only (a plain query finds it, the store's never): fails", False, [C, P, H, F] + [S] * 5,
     "not in Tempo's store")
case("the push failing: fails, nothing flushed", False, [C, P], "push", PUSH_FAILS="1")
case("the marker never held: fails, nothing flushed", False, [C, P, H, H, H], "never held", NEVER_HELD="1")
case("the flush call failing: fails, nothing waited for", False, [C, P, H, F], "flush", FLUSH_RC="1", STORED_AFTER="1")
print("tempo-flush: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
