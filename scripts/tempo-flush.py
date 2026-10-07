#!/usr/bin/env python3
"""Tempo's live spans flushed into its store, the flush proven by a marker trace of our own.

Tempo's /flush only queues the work and answers at once, and its metrics tell neither when our block is stored (the
flush queue's gauge drops when a worker takes the work, not when it is done; the flushed-blocks counter rises for any
block) nor whether there was anything to flush (an empty head block flushes nothing). So a marker trace is pushed
(OTLP/HTTP through the API server's service proxy, with the kubeconfig's client certificate), seen held by Tempo, then
/flush is called, and the script waits until a query of the store alone (?mode=blocks) returns the marker: its block,
with every span cut into it before the call, is in the store. The store's view lags by Tempo's blocklist poll (5
minutes by default) - the wait allows for it. A merge replacing Tempo's major then loses nothing the next major would
not replay from the WAL but what arrived after the call.

Runs where kubectl runs - production: on ten (ssh sm@192.168.11.2 python3 - < scripts/tempo-flush.py), the Vagrant
copy: on its node. The client certificate's copies live in a directory of the run's own, removed after the push.

Usage: scripts/tempo-flush.py [--kubeconfig <file>]
"""
import base64
import json
import os
import secrets
import shutil
import subprocess
import sys
import tempfile
import time

TEMPO = "/api/v1/namespaces/schnappy-infra/services/schnappy-tempo"
MARKER = "upgrade-tempo-flush"
POLL_HELD, ATTEMPTS_HELD = 2, 30
POLL_STORED, ATTEMPTS_STORED = 10, 60  # Tempo's blocklist poll (5 m) and the flush itself


def kubectl(args, kubeconfig):
    return ["kubectl"] + (["--kubeconfig", kubeconfig] if kubeconfig else []) + ["--request-timeout=30s"] + args


def get(path, kubeconfig):
    """Tempo's HTTP API at path (port 3200) through the API server: (found, output)."""
    out = subprocess.run(kubectl(["get", "--raw", f"{TEMPO}:3200/proxy{path}"], kubeconfig), capture_output=True,
                         text=True)
    return out.returncode == 0, out.stdout + out.stderr


def push(trace_id, kubeconfig):
    """The marker, one span, to Tempo's OTLP/HTTP receiver - curl, as kubectl's own POST sends a content type Tempo
    refuses (415)."""
    view = subprocess.run(kubectl(["config", "view", "--raw", "--minify", "-o", "json"], kubeconfig),
                          capture_output=True, text=True)
    if view.returncode:
        sys.exit(f"the kubeconfig could not be read: {view.stderr.strip()}")
    config = json.loads(view.stdout)
    cluster, user = config["clusters"][0]["cluster"], config["users"][0]["user"]
    if "client-certificate-data" not in user:
        sys.exit("the kubeconfig has no client certificate to push the marker trace with")
    d = tempfile.mkdtemp(prefix="tempo-flush-")
    try:
        for name, key, data in (("ca", "certificate-authority-data", cluster), ("cert", "client-certificate-data", user),
                                ("key", "client-key-data", user)):
            with open(os.path.join(d, name), "wb") as f:
                f.write(base64.b64decode(data[key]))
        now = time.time_ns()
        span = {"traceId": trace_id, "spanId": secrets.token_hex(8), "name": MARKER, "kind": 1,
                "startTimeUnixNano": str(now - 1_000_000_000), "endTimeUnixNano": str(now)}
        body = {"resourceSpans": [{"resource": {"attributes": [{"key": "service.name",
                                                                "value": {"stringValue": "upgrade-check"}}]},
                                   "scopeSpans": [{"spans": [span]}]}]}
        out = subprocess.run(["curl", "-fsS", "--max-time", "30", "--cacert", os.path.join(d, "ca"),
                              "--cert", os.path.join(d, "cert"), "--key", os.path.join(d, "key"),
                              "-H", "Content-Type: application/json",
                              f"{cluster['server']}{TEMPO}:4318/proxy/v1/traces", "--data-binary", "@-"],
                             input=json.dumps(body), capture_output=True, text=True)
    finally:
        shutil.rmtree(d)
    if out.returncode:
        sys.exit(f"the marker trace's push failed: {out.stderr.strip()}")


def wait_for(path, attempts, poll, kubeconfig):
    for i in range(attempts):
        found, out = get(path, kubeconfig)
        if found and MARKER in out:
            return True
        if i + 1 < attempts:
            time.sleep(poll)
    return False


def flush(args):
    kubeconfig = args[args.index("--kubeconfig") + 1] if "--kubeconfig" in args else None
    trace_id = secrets.token_hex(16)
    push(trace_id, kubeconfig)
    if not wait_for(f"/api/traces/{trace_id}", ATTEMPTS_HELD, POLL_HELD, kubeconfig):
        sys.exit(f"the marker trace {trace_id} was never held by Tempo - nothing flushed")
    found, out = get("/flush", kubeconfig)
    if not found:
        sys.exit(f"Tempo's /flush failed: {out.strip()}")
    if not wait_for(f"/api/traces/{trace_id}?mode=blocks", ATTEMPTS_STORED, POLL_STORED, kubeconfig):
        sys.exit(f"the marker trace {trace_id} is not in Tempo's store {POLL_STORED * ATTEMPTS_STORED} s after its "
                 f"/flush - the spans it held may still be in its WAL")
    print(f"TEMPO FLUSHED: the marker trace {trace_id}, pushed before the flush, is in the store")


if __name__ == "__main__":
    flush(sys.argv[1:])
