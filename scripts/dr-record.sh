#!/usr/bin/env bash
# Record the last DR drill's result: push restore_verify_success to the prod
# pushgateway, but only if the drill log shows a fresh, genuinely passing run.
#
# The push runs INSIDE the pushgateway pod (kubectl exec + busybox wget), so
# there is no local tunnel: the previous port-forward version leaked under
# task's built-in shell (no kill/$!) and the next push hit a stale tunnel.
set -euo pipefail

LOG="${DR_DRILL_LOG:-/tmp/dr-drill.log}"
PROD_CTX="${DR_PROD_CONTEXT:-kubernetes-admin@kubernetes}"
MAX_AGE_MIN="${DR_LOG_MAX_AGE_MIN:-360}"

if [ ! -r "$LOG" ]; then
  echo ">> No drill log at $LOG — run \`task dr:drill\` first." >&2
  exit 1
fi
# A stale green log must not silence the alert without a drill having run.
if [ -n "$(find "$LOG" -mmin +"$MAX_AGE_MIN" 2>/dev/null)" ]; then
  echo ">> Drill log $LOG is older than ${MAX_AGE_MIN} min — refusing to record it." >&2
  exit 1
fi
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

# Pushgateway needs the trailing newline; busybox wget exits non-zero on a
# non-2xx response (-S shows the status line in the output).
if ! out="$(kubectl --context "$PROD_CTX" -n schnappy-infra exec deploy/schnappy-pushgateway -c pushgateway -- \
      wget -q -S -O /dev/null --post-data=$'restore_verify_success 1\n' \
        http://127.0.0.1:9091/metrics/job/dr-drill 2>&1)"; then
  echo ">> Push to the pushgateway FAILED:" >&2
  echo "$out" >&2
  exit 1
fi
echo "$out" | grep -m1 'HTTP/' || true
echo ">> Recorded restore_verify_success=1 (job=dr-drill); RestoreVerificationFailing reset."
