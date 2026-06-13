#!/usr/bin/env bash
# SonarQube server-state check for /full-review.
# Usage: sonar.sh [projectKey]
# Project key defaults to sonar.projectKey from ./sonar-project.properties,
# falling back to schnappy-<basename of cwd>. Token comes from the
# environment (SONARQUBE_TOKEN, e.g. via Taskfile dotenv) or ops/.env.
# The issues list is capped at ps=500 (API max) — check paging.total.
set -euo pipefail

KEY="${1:-}"
if [[ -z "$KEY" && -f sonar-project.properties ]]; then
  KEY=$(grep -oP '(?<=^sonar.projectKey=).*' sonar-project.properties || true)
fi
KEY="${KEY:-schnappy-$(basename "$PWD")}"

TOKEN="${SONARQUBE_TOKEN:-}"
if [[ -z "$TOKEN" ]]; then
  TOKEN=$(grep -oP '(?<=^SONARQUBE_TOKEN=).*' /home/sm/src/ops/.env || true)
fi
# Tolerate quoted values and CRLF line endings in .env.
TOKEN="${TOKEN%$'\r'}"; TOKEN="${TOKEN%\"}"; TOKEN="${TOKEN#\"}"
[[ -n "$TOKEN" ]] || { echo "SONARQUBE_TOKEN not found in env or /home/sm/src/ops/.env" >&2; exit 1; }

# Credentials go in via stdin config (-K -) to keep the token off argv,
# and --fail-with-body keeps SonarQube's JSON error diagnostic on 4xx.
sq() {
  curl -sS --fail-with-body -K - <<<"user = \"$TOKEN:\"" "$1"
}

rc=0
echo "projectKey=$KEY"
echo "--- quality gate ---"
sq "https://sonar.pmon.dev/api/qualitygates/project_status?projectKey=$KEY" || rc=$?
echo
echo "--- unresolved issues ---"
# Run even if the gate query failed: an unknown key fails both with the
# same diagnostic, while a gate-only hiccup still yields the issues list.
sq "https://sonar.pmon.dev/api/issues/search?components=$KEY&resolved=false&ps=500" || rc=$?
echo
exit "$rc"
