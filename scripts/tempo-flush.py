#!/usr/bin/env python3
"""Tempo's live spans flushed into its store, the flush waited for.

Tempo's /flush only queues the work and answers at once: a merge replacing Tempo's major straight after it could stop
Tempo with the spans still in its WAL, which the next major does not replay. Done when Tempo has flushed a block since
the call (tempo_ingester_blocks_flushed_total past its value before) and its flush queue is empty on two readings in a
row (a completed block queues its own flush); a failed flush, no flush within the attempts, or a metric missing fail.
Tempo runs as one pod (its Service reaches the one ingester).

Usage: scripts/tempo-flush.py <kubectl command...>
  production: scripts/tempo-flush.py ssh sm@192.168.11.2 kubectl
  Vagrant:    scripts/tempo-flush.py kubectl --kubeconfig /etc/kubernetes/admin.conf
"""
import re
import subprocess
import sys
import time

TEMPO = "/api/v1/namespaces/schnappy-infra/services/schnappy-tempo:3200/proxy"
FLUSHED, QUEUE, FAILED = ("tempo_ingester_blocks_flushed_total", "tempo_ingester_flush_queue_length",
                          "tempo_ingester_failed_flushes_total")
POLL, ATTEMPTS = 2, 60


def get(kubectl, path):
    out = subprocess.run(kubectl + ["get", "--raw", TEMPO + path], capture_output=True, text=True)
    if out.returncode:
        sys.exit(f"Tempo {path}: rc {out.returncode}: {out.stderr.strip()}")
    return out.stdout


def metrics(kubectl):
    text = get(kubectl, "/metrics")
    found = {}
    for name in (FLUSHED, QUEUE, FAILED):
        m = re.search(rf"^{name} (\S+)$", text, re.M)
        if not m:
            sys.exit(f"Tempo's /metrics has no {name} - its flush cannot be followed")
        found[name] = float(m.group(1))
    return found


def flush(kubectl):
    before = metrics(kubectl)
    get(kubectl, "/flush")
    empty = 0
    for _ in range(ATTEMPTS):
        time.sleep(POLL)
        now = metrics(kubectl)
        if now[FAILED] > before[FAILED]:
            sys.exit(f"a Tempo flush failed ({FAILED} {before[FAILED]:g} -> {now[FAILED]:g})")
        empty = empty + 1 if now[FLUSHED] > before[FLUSHED] and now[QUEUE] == 0 else 0
        if empty == 2:
            print(f"TEMPO FLUSHED: {now[FLUSHED] - before[FLUSHED]:g} block(s) into the store, nothing queued")
            return
    sys.exit(f"no block flushed and the queue emptied within {POLL * ATTEMPTS} s of Tempo's /flush ({FLUSHED} "
             f"{before[FLUSHED]:g} -> {now[FLUSHED]:g}, {QUEUE} {now[QUEUE]:g}) - Tempo's spans may still be in its WAL")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    flush(sys.argv[1:])
