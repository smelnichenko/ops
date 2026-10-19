"""Every process's command line, read from /proc again and again while the playbook runs, against every secret the
fakes know (passwords set, tokens issued - fetched from the fake Forgejo's /_secrets) and the fixed ones in a file (the
admin's password, Vault's token): a secret on any command line is a hit. Any local user reads /proc/<pid>/cmdline.
argv: <forgejo port> <fixed secrets file, one a line> <result file>. SIGTERM ends it: the result written as JSON -
scans made, hits (pid, the start of the command, which secret by its index - never the secret).
"""
import json
import os
import signal
import sys
import time
import urllib.request

port, fixed_file, out = sys.argv[1], sys.argv[2], sys.argv[3]
fixed = [x for x in open(fixed_file).read().splitlines() if x]
known, hits, scans, last = list(fixed), [], 0, 0.0
stop = False


def end(*_):
    global stop
    stop = True


signal.signal(signal.SIGTERM, end)
me = os.getpid()
while not stop:
    if time.monotonic() - last > 0.05:
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/_secrets", timeout=2) as r:
                known = fixed + json.load(r)
        except OSError:
            pass
        last = time.monotonic()
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == me:
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmd = f.read().decode(errors="replace")
        except OSError:
            continue
        for i, s in enumerate(known):
            if s in cmd:
                hits.append({"pid": int(pid), "cmd": cmd.replace("\0", " ").replace(s, "***")[:60], "secret": i})
    scans += 1
    time.sleep(0.002)
with open(out, "w") as f:
    json.dump({"scans": scans, "hits": hits}, f)
