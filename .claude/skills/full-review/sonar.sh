#!/usr/bin/env bash
# SonarQube server-state check for /full-review.
# Usage: sonar.sh [projectKey]
# Project key defaults to sonar.projectKey from ./sonar-project.properties,
# falling back to schnappy-<basename of cwd>. Token comes from ops/.env.
# The issues list is capped at ps=500 (API max) — check paging.total.
set -euo pipefail

KEY="${1:-}"
if [[ -z "$KEY" && -f sonar-project.properties ]]; then
  KEY=$(grep -oP '(?<=^sonar.projectKey=).*' sonar-project.properties || true)
fi
KEY="${KEY:-schnappy-$(basename "$PWD")}"

TOKEN=$(grep -oP '(?<=^SONARQUBE_TOKEN=).*' /home/sm/src/ops/.env || true)
[[ -n "$TOKEN" ]] || { echo "SONARQUBE_TOKEN not found in /home/sm/src/ops/.env" >&2; exit 1; }

# Credentials go in via stdin config (-K -) to keep the token off argv,
# and --fail-with-body keeps SonarQube's JSON error diagnostic on 4xx.
sq() {
  curl -sS --fail-with-body -K - <<<"user = \"$TOKEN:\"" "$1"
}

echo "projectKey=$KEY"
echo "--- quality gate ---"
sq "https://sonar.pmon.dev/api/qualitygates/project_status?projectKey=$KEY"
echo
echo "--- unresolved issues ---"
sq "https://sonar.pmon.dev/api/issues/search?components=$KEY&resolved=false&ps=500"
echo
