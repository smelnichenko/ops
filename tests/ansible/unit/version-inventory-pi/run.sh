#!/bin/bash
# scripts/version-inventory-pi.sh against stubbed tools (systemctl, readlink, pgrep, curl, dpkg-query, the version
# commands): every service by the process it runs - a binary replaced under its process reads "stale", a service not
# running "not-running", a Keycloak holding two installs open "stale"; Patroni and Forgejo by what they serve; Debian
# packages only where installed, and a package dpkg has never seen (postgresql-18 on every Pi) neither a line nor a
# failure.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
stub() { printf '#!/bin/bash\n%s\n' "$2" > "$W/bin/$1"; chmod +x "$W/bin/$1"; }
stub hostname 'echo pi9'
stub systemctl 'u="${@: -1}"; v="PID_${u//-/_}"; echo "${!v:-0}"'
stub pgrep 'v="CHILD_$2"; [ -n "${!v:-}" ] && echo "${!v}" || exit 1'
stub readlink 'a="$1"
case "$a" in
  /proc/*/exe) p=${a#/proc/}; p=${p%/exe}; v="EXE_$p"; [ -n "${!v:-}" ] && echo "${!v}" || exit 1 ;;
  /proc/*/fd/*) p=${a#/proc/}; p=${p%%/*}; v="FD_$p"; [ -n "${!v:-}" ] && printf "%s\n" ${!v} || exit 1 ;;
  *) exit 1 ;;
esac'
stub curl 'for a; do u=$a; done
case "$u" in
  *:3000/api/v1/version) [ -n "${FORGEJO_JSON:-}" ] && echo "$FORGEJO_JSON" || exit 7 ;;
  *:8008/patroni) [ -n "${PATRONI_JSON:-}" ] && echo "$PATRONI_JSON" || exit 7 ;;
  *) exit 7 ;;
esac'
# as dpkg-query -W -f=FORMAT PKG...: each known package in FORMAT; any unknown one named on stderr and exit 1
stub dpkg-query 'fmt=""; pkgs=()
for a; do case "$a" in -W) ;; -f=*) fmt=${a#-f=} ;; *) pkgs+=("$a") ;; esac; done
rc=0
for p in "${pkgs[@]}"; do
  v="DPKG_${p//-/_}"; st="DPKGST_${p//-/_}"
  if [ -n "${!v:-}" ]; then
    o=${fmt//"\${db:Status-Abbrev}"/${!st:-ii }}; o=${o//"\${Package}"/$p}; o=${o//"\${Version}"/${!v}}; printf "%b" "$o"
  else echo "dpkg-query: no packages found matching $p" >&2; rc=1; fi
done
exit $rc'
stub versitygw 'echo "Version  : 1.6.0"'
stub vault 'echo "Vault v1.21.4 (f4f0f4eb), built 2026-02-03"'
stub consul 'printf "Consul v1.20.6\nRevision 1\n"'
stub caddy 'echo "v2.10.0 h1:abc="'
# pids above any pid_max: their /proc globs never match a real process
running=(PID_versitygw=9999901 EXE_9999901=/usr/bin/versitygw PID_vault=9999902 EXE_9999902=/usr/local/bin/vault
  PID_consul=9999903 EXE_9999903=/usr/local/bin/consul PID_caddy=9999904 EXE_9999904=/usr/local/bin/caddy
  'FORGEJO_JSON={"version":"15.0.9+gitea-1.22.0"}' 'PATRONI_JSON={"state":"running","patroni":{"version":"4.1.5","scope":"x"}}'
  PID_keycloak=9999905 'FD_9999905=/dev/null /opt/keycloak-26.5.7/bin/kc.sh' CHILD_9999905=9999906
  'FD_9999906=/opt/keycloak-26.5.7/lib/lib/main/a.jar /opt/keycloak-26.5.7/lib/lib/main/b.jar'
  DPKG_postgresql_17=17.11-0+deb13u1 DPKG_pgbouncer=1.24.1-1+deb13u2 DPKG_haproxy=3.0.11-1+deb13u3
  DPKG_glusterfs_server=11.1-6 DPKG_keepalived=1:2.3.3-1)
fails=0
case_() { # name, expected output; the rest: VAR=value for this case
  local name=$1 want=$2; shift 2
  out=$(env -i PATH="$W/bin:${FENCE:+$FENCE:}/usr/local/bin:/usr/bin:/bin" "$@" bash scripts/version-inventory-pi.sh 2>&1); rc=$?
  if [ "$rc" = 0 ] && [ "$out" = "$want" ]; then echo "PASS $name"
  else echo "FAIL $name (rc $rc)"; diff <(printf '%s\n' "$want") <(printf '%s\n' "$out") | sed 's/^/    /'; fails=$((fails + 1)); fi
}
all='pi pi9 versitygw 1.6.0
pi pi9 vault 1.21.4
pi pi9 consul 1.20.6
pi pi9 caddy 2.10.0
pi pi9 forgejo 15.0.9
pi pi9 patroni 4.1.5
pi pi9 keycloak 26.5.7
pi pi9 postgresql-17 17.11-0+deb13u1
pi pi9 pgbouncer 1.24.1-1+deb13u2
pi pi9 haproxy 3.0.11-1+deb13u3
pi pi9 glusterfs-server 11.1-6
pi pi9 keepalived 1:2.3.3-1'
case_ "every service running; postgresql-18 unknown to dpkg - no line, exit 0" "$all" "${running[@]}"
case_ "a binary replaced under its process reads stale" "$(sed 's/^pi pi9 vault .*/pi pi9 vault stale/' <<< "$all")" \
  "${running[@]}" "EXE_9999902=/usr/local/bin/vault (deleted)"
case_ "services not running read not-running" "$(sed -E 's/^(pi pi9 (consul|forgejo|patroni|keycloak)) .*/\1 not-running/' <<< "$all")" \
  "${running[@]}" PID_consul=0 FORGEJO_JSON= PATRONI_JSON= PID_keycloak=0
case_ "Keycloak holding two installs open reads stale" "$(sed 's/^pi pi9 keycloak .*/pi pi9 keycloak stale/' <<< "$all")" \
  "${running[@]}" 'FD_9999906=/opt/keycloak-26.4.2/lib/lib/main/a.jar'
case_ "a package removed but its config kept (rc) has no line" "$(grep -v haproxy <<< "$all")" "${running[@]}" "DPKGST_haproxy=rc "
echo "version-inventory-pi: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
