#!/bin/bash
# scripts/upgrade-production.py's remote calls against an ssh stub: every one gives up on a dead connection (ssh's
# keep-alives) and a remote command that never answers ends the phase with a message instead of hanging it - a
# production phase waited for ever on one (no ssh option, no timeout).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import importlib.machinery, importlib.util, os, re, sys, tempfile, time
l = importlib.machinery.SourceFileLoader("up", "scripts/upgrade-production.py")
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("up", l))
l.exec_module(m)
work = tempfile.mkdtemp()
open(os.path.join(work, "ssh"), "w").write("""#!/bin/bash
echo "$*" >> "$W/calls"
cat > /dev/null
[ -z "${HANG:-}" ] || exec sleep 30
echo answered
""")
os.chmod(os.path.join(work, "ssh"), 0o755)
os.environ["PATH"] = work + ":" + os.environ["PATH"]
os.environ["W"] = work
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
def call(fn, hang):
    calls = os.path.join(work, "calls")
    if os.path.exists(calls):
        os.remove(calls)
    os.environ.pop("HANG", None)
    if hang:
        os.environ["HANG"] = "1"
    m.REMOTE_TIMEOUT = 1
    t = time.monotonic()
    try:
        fn()
        got = "answered"
    except SystemExit as e:
        got = "no answer" if "no answer" in str(e) else str(e)
    args = open(calls).read() if os.path.exists(calls) else ""
    return got, time.monotonic() - t < 10, all(o in args for o in ("ServerAliveInterval=", "ServerAliveCountMax=",
                                                                     "ConnectTimeout="))
check("ten answering: its output, ssh with keep-alives", call(lambda: m.ten("true"), False), ("answered", True, True))
check("ten never answering: the phase ends, said so", call(lambda: m.ten("true"), True), ("no answer", True, True))
pi = lambda: m.remote(m.PIS[0], "sudo -n bash -s", stdin="")
check("a Pi never answering: the same", call(pi, True), ("no answer", True, True))
# the class: no ssh call of the script without those options
src = open("scripts/upgrade-production.py").read()
check("every ssh call of the script goes through the options (ssh named once, in them)", src.count('"ssh"'), 1)
print("remote-timeouts: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
