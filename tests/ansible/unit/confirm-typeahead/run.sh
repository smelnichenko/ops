#!/bin/bash
# scripts/upgrade-production.py's confirm() on a real terminal (a pty its controlling one): a "y" typed before the
# question (to an earlier prompt, or a key held down) is discarded - the answer is the one typed after it is asked; a
# production merge taken on input typed ahead is no operator's yes.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PYCT'
import importlib.machinery, importlib.util, os, pty, select, signal, sys, time
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
def ask(typed_ahead, answer, setup=None):
    """confirm()'s result with `typed_ahead` typed before the question and `answer` after it ("" none); `setup`: what
    the child does first - "flush-fails" (the terminal's flush raising termios.error), "background" (in a process
    group of its own: not the terminal's foreground), "moved" (in the foreground when checked, moved to a group of its
    own - Ctrl-Z, bg - before its read)."""
    pid, fd = pty.fork()
    if pid == 0:
        l = importlib.machinery.SourceFileLoader("up", "scripts/upgrade-production.py")
        m = importlib.util.module_from_spec(importlib.util.spec_from_loader("up", l))
        l.exec_module(m)
        if setup == "flush-fails":
            def tcflush(*_):
                raise m.termios.error(5, "Input/output error")
            m.termios.tcflush = tcflush
        elif setup == "moved":
            gpid = os.fork()
            if gpid:
                os.waitpid(gpid, 0)
                os._exit(0)
            flush = m.termios.tcflush
            def tcflush(fd, queue):
                flush(fd, queue)
                os.setpgid(0, 0)  # the terminal's background from here: its read stopped it (SIGTTIN)
            m.termios.tcflush = tcflush
        elif setup == "background":
            # pty.fork's child leads its session (no group of its own for it): its child asks, from a group of its own
            gpid = os.fork()
            if gpid:
                os.waitpid(gpid, 0)
                os._exit(0)
            os.setpgid(0, 0)
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
    # bounded: a child stopped at the question (SIGTTOU, a background flush) is killed - its stopped child then gets
    # SIGHUP from the kernel (its group orphaned) - and reads as no result
    if os.waitpid(pid, os.WNOHANG) == (0, 0):
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
    text = out.decode(errors="replace")
    ASKED.append(text)
    return text.split("RESULT ")[1].split()[0] if "RESULT " in text else f"no result: {text!r}"
ASKED = []  # each ask's terminal output
check("a y typed before the question, n after it: no", ask("y\n", "n\n"), "False")
check("nothing before, y after it: yes", ask("", "y\n"), "True")
check("y before, y after: yes (the answer after the question)", ask("y\n", "y\n"), "True")
check("the terminal's flush failing (termios.error, no OSError): no - never a crash", ask("", "y\n", "flush-fails"),
      "False")
# a phase run in the background of its terminal (a job, `&`): the flush would stop it there (SIGTTOU), holding its
# claim - it answers no at once, said
check("not the terminal's foreground: no, at once (not stopped at the question), said",
      (ask("", "y\n", "background"), "not asked: this runs in its terminal's background" in ASKED[-1]), ("False", True))
# moved to the terminal's background between the check and the read (Ctrl-Z, bg): the read stopped it there (SIGTTIN),
# its claim held - it answers no, never stopped
check("moved to the background after the check: no, not stopped at the read", ask("", "y\n", "moved"), "False")
# its SIGTTIN and SIGTTOU handlers put back as they were, whatever its answer (left ignored, the caller's own job
# control changed under it) - here with no terminal at all (a session of its own): a no
import subprocess  # noqa: E402
code = """
import importlib.machinery, importlib.util, signal
l = importlib.machinery.SourceFileLoader("up", "scripts/upgrade-production.py")
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("up", l))
l.exec_module(m)
mine = lambda *a: None
signal.signal(signal.SIGTTIN, mine)
signal.signal(signal.SIGTTOU, signal.SIG_DFL)
got = m.confirm("merge?")
print(got, signal.getsignal(signal.SIGTTIN) is mine, signal.getsignal(signal.SIGTTOU) == signal.SIG_DFL)
"""
r = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, start_new_session=True,
                   stdin=subprocess.DEVNULL, env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
check("its SIGTTIN and SIGTTOU handlers put back as they were (no terminal: a no)", r.stdout.strip() or r.stderr[-200:],
      "False True True")
print("confirm-typeahead: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCT
