#!/bin/bash
# scripts/upgrade-production.py's confirm() on a real terminal (a pty its controlling one): a "y" typed before the
# question (to an earlier prompt, or a key held down) is discarded - the answer is the one typed after it is asked; a
# production merge taken on input typed ahead is no operator's yes.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PYCT'
import importlib.machinery, importlib.util, os, pty, select, sys, time
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
def ask(typed_ahead, answer):
    """confirm()'s result with `typed_ahead` typed before the question and `answer` after it ("" none)."""
    pid, fd = pty.fork()
    if pid == 0:
        l = importlib.machinery.SourceFileLoader("up", "scripts/upgrade-production.py")
        m = importlib.util.module_from_spec(importlib.util.spec_from_loader("up", l))
        l.exec_module(m)
        time.sleep(0.5)  # the typed-ahead input in the terminal's buffer before the question
        os.write(1, b"RESULT " + str(m.confirm("merge?")).encode() + b"\n")
        os._exit(0)
    os.write(fd, typed_ahead.encode())
    out, asked = b"", False
    end = time.monotonic() + 10
    while time.monotonic() < end:
        r, _, _ = select.select([fd], [], [], 0.2)
        if not r:
            continue
        try:
            chunk = os.read(fd, 1024)
        except OSError:
            break
        if not chunk:
            break
        out += chunk
        if not asked and b"[y/N]" in out:
            asked = True
            os.write(fd, answer.encode())
        if b"RESULT " in out and out.rstrip().endswith((b"True", b"False")):
            break
    os.waitpid(pid, 0)
    text = out.decode(errors="replace")
    return text.split("RESULT ")[1].split()[0] if "RESULT " in text else f"no result: {text!r}"
check("a y typed before the question, n after it: no", ask("y\n", "n\n"), "False")
check("nothing before, y after it: yes", ask("", "y\n"), "True")
check("y before, y after: yes (the answer after the question)", ask("y\n", "y\n"), "True")
print("confirm-typeahead: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCT
