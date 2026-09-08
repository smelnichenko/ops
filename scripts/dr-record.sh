#!/usr/bin/env bash
# Record the last DR drill's result: push restore_verify_success to the prod
# pushgateway, but only if /tmp/dr-drill.log shows a genuinely passing run.
# Runs as a real bash script (not a Taskfile cmd) because task's built-in
# shell has no working `kill`/`$!`, so a backgrounded port-forward could
# never be cleaned up and leaked into the next run (bind failure → curl 56).
set -euo pipefail

LOG="${DR_DRILL_LOG:-/tmp/dr-drill.log}"
PROD_CTX="${DR_PROD_CONTEXT:-kubernetes-admin@kubernetes}"
LOCAL_PORT="${DR_PUSH_PORT:-19091}"

if ! grep -q 'ALL DR TESTS PASSED' "$LOG" || grep -qE 'failed=[1-9]' "$LOG"; then
  echo ">> DR drill did NOT pass — restore_verify_success NOT recorded." >&2
  exit 1
fi
echo ">> DR drill PASSED — recording restore_verify_success to the prod pushgateway"

CUR_CTX="$(kubectl config current-context)"
if [ "$CUR_CTX" != "$PROD_CTX" ]; then
  echo ">> Refusing to push: kube context '$CUR_CTX' != prod '$PROD_CTX' (override with DR_PROD_CONTEXT)." >&2
  exit 1
fi

PF_LOG="$(mktemp)"
kubectl --context "$PROD_CTX" port-forward -n schnappy-infra \
  svc/schnappy-pushgateway "${LOCAL_PORT}:9091" >"$PF_LOG" 2>&1 &
PF=$!
trap 'kill "$PF" 2>/dev/null || true; rm -f "$PF_LOG"' EXIT

# The local port opens before the tunnel is usable; a curl landing in that
# window gets a reset (curl 56), which --retry-connrefused does not cover.
# Wait for kubectl's ready line, then retry every error.
for _ in $(seq 1 30); do
  grep -q 'Forwarding from' "$PF_LOG" && break
  if ! kill -0 "$PF" 2>/dev/null; then
    echo ">> port-forward died:" >&2
    cat "$PF_LOG" >&2
    exit 1
  fi
  sleep 1
done

printf 'restore_verify_success 1\n' | \
  curl -sf --retry 30 --retry-all-errors --retry-delay 1 \
    --data-binary @- "http://127.0.0.1:${LOCAL_PORT}/metrics/job/dr-drill"
echo ">> Recorded restore_verify_success=1 (job=dr-drill); RestoreVerificationFailing reset."
