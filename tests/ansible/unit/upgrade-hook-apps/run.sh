#!/bin/bash
# scripts/upgrade-hook-apps.py - the production apps a unit's apply syncs: each whose chart runs a moved image in an Argo
# hook (out of Argo's diff: never run by the apply alone). Against a platform tree of its own: a hook's literal image and
# one from its values (a string, a {repository} map) by package; a digest row's package; a moved image outside any hook,
# or no move in a hook, syncs nothing; a chart running a hook that HOOK_APPS does not name, a hook image its values lack,
# one templated otherwise, no platform checkout - each refused (exit 2), named. Its HOOK_APPS covers platform's charts as
# they are when ../platform is here.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi; }
P=$W/platform
mkdir -p "$P/helm/schnappy/templates" "$P/helm/schnappy-data/templates" "$P/helm/schnappy-sonarqube/templates" \
  "$P/helm/schnappy-observability/templates"
hook() { printf '  annotations:\n    argocd.argoproj.io/hook: PostSync\n'; }
{ echo "kind: Job"; hook; echo "        - name: wait"; echo "          image: curlimages/curl:8.10.1@sha256:$(printf 'a%.0s' {1..64})"
  echo "        - name: k6"; echo "          image: {{ .Values.smokeTest.image }}"; } > "$P/helm/schnappy/templates/k6-postsync-job.yaml"
printf 'kind: Deployment\n          image: nginx:1.29-alpine\n' > "$P/helm/schnappy/templates/site.yaml"
printf 'smokeTest:\n  image: grafana/k6:1.7.1@sha256:%s\n' "$(printf 'b%.0s' {1..64})" > "$P/helm/schnappy/values.yaml"
{ echo "kind: Job"; hook; echo "          image: \"postgres:17-alpine\""; echo "          image: {{ .Values.scylla.image }}"; } \
  > "$P/helm/schnappy-data/templates/init.yaml"
printf 'scylla:\n  image:\n    repository: scylladb/scylla\n    tag: "2026.1.16"\n' > "$P/helm/schnappy-data/values.yaml"
{ echo "kind: Job"; hook; echo "          image: curlimages/curl:8.12.1"; } > "$P/helm/schnappy-sonarqube/templates/setup.yaml"
printf 'kind: Deployment\n          image: grafana/grafana:13.2.6\n' > "$P/helm/schnappy-observability/templates/grafana.yaml"
apps() {  # apps <moves...>: the script's answer (its lines joined), then its exit
  printf '%s\n' "$@" > "$W/moves"
  out=$("$PY" scripts/upgrade-hook-apps.py "$W/moves" "${PLATFORM:-$P}" 2>&1); rc=$?
  echo "$(tr '\n' ' ' <<< "$out" | sed 's/ $//') rc=$rc"
}
check "k6 moved (its hook's image from the chart's values): the apps' app" "$(apps 'grafana/k6 1.7.1 1.8.3')" "schnappy-production-apps rc=0"
check "curl moved (a literal image in two charts' hooks): both apps, each once" \
  "$(apps 'curlimages/curl 8.10.1 8.23.0' 'curlimages/curl 8.12.1 8.23.0')" "schnappy-production-apps schnappy-sonarqube rc=0"
check "postgres moved by its digest alone (a digest row, quoted in the template): the data app" \
  "$(apps 'postgres 6f30057 9a1b2c3 digest')" "schnappy-production-data rc=0"
check "scylla moved (its values a {repository, tag} map): the data app" "$(apps 'scylladb/scylla 2026.1.16 2026.1.17')" "schnappy-production-data rc=0"
check "a moved image no hook runs (nginx in a Deployment, Grafana in a chart without hooks): none" \
  "$(apps 'nginx 1.29-alpine 1.31-alpine' 'grafana/grafana 13.2.6 13.2.7')" " rc=0"
rm -f "$W/moves"
out=$("$PY" scripts/upgrade-hook-apps.py "$W/moves" "$P" 2>&1); rc=$?
check "no moves file (a unit that moved no image): none" "$out rc=$rc" " rc=0"
mkdir -p "$P/helm/schnappy-new/templates"; { echo "kind: Job"; hook; echo "          image: busybox:1.37"; } > "$P/helm/schnappy-new/templates/j.yaml"
check "a chart running a hook HOOK_APPS does not name: refused, named - a hook never synced fails closed" \
  "$(apps 'nginx 1 2' | grep -c 'REFUSED: helm/schnappy-new runs a hook (busybox)') $(apps 'nginx 1 2' | grep -o 'rc=.*')" "1 rc=2"
rm -r "$P/helm/schnappy-new"
cp "$P/helm/schnappy/values.yaml" "$W/values.keep"; printf 'other: {}\n' > "$P/helm/schnappy/values.yaml"
check "a hook's image from values its values lack: refused, named" "$(apps 'nginx 1 2' | grep -oE '(smokeTest.image not in its values|rc=.*)' | tr '\n' ' ')" \
  "smokeTest.image not in its values rc=2 "
cp "$W/values.keep" "$P/helm/schnappy/values.yaml"
cp "$P/helm/schnappy-sonarqube/templates/setup.yaml" "$W/setup.keep"
{ echo "kind: Job"; hook; echo '          image: {{ include "x.image" . }}'; } > "$P/helm/schnappy-sonarqube/templates/setup.yaml"
check "a hook's image templated another way: refused, not read" "$(apps 'nginx 1 2' | grep -oE '(not read|rc=.*)' | tr '\n' ' ')" "not read rc=2 "
cp "$W/setup.keep" "$P/helm/schnappy-sonarqube/templates/setup.yaml"
check "no platform checkout: refused" "$(PLATFORM=$W/none apps 'grafana/k6 1 2' | grep -oE '(no platform checkout|rc=.*)' | tr '\n' ' ')" \
  "no platform checkout rc=2 "
check "a registry with a port: its package keeps the port (the tag after it alone dropped)" \
  "$("$PY" -c 'import importlib.util as u, sys; s = u.spec_from_file_location("h", "scripts/upgrade-hook-apps.py"); m = u.module_from_spec(s); s.loader.exec_module(m); print(m.package("registry.local:5000/team/x:1.0@sha256:" + "c" * 64), m.package("registry.local:5000/team/x"))')" \
  "registry.local:5000/team/x registry.local:5000/team/x"
# platform's own charts, when its checkout is beside this one (a developer's; CI has none): every chart running a hook named
if [ -d ../platform/helm ]; then
  out=$("$PY" scripts/upgrade-hook-apps.py /dev/null ../platform 2>&1); rc=$?
  check "platform's charts as they are: every one running a hook named in HOOK_APPS (none refused)" "rc=$rc $out" "rc=0 "
fi
echo "upgrade-hook-apps: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
