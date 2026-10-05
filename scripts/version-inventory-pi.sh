#!/usr/bin/env bash
# version-inventory-pi.sh - what a Pi runs, in the inventory's line format, prefixed by the Pi: "pi <host> <name>
# <version>". Where the process can be asked, the version it runs, not the package's: a binary replaced under a
# running service reads "stale" (the file it runs is deleted) until it restarts; a service not running reads
# "not-running". Debian's packages by their package version.
# Read-only. Runs ON a Pi (production pi1/pi2, or the Vagrant Pi VMs):
#   ssh pi1 'sudo bash -s' < scripts/version-inventory-pi.sh
set -euo pipefail
host=$(hostname -s)
line() { echo "pi $host $1 $2"; }

# a service's binary, asked for its version - unless the process runs a replaced (deleted) file or none runs
binary() {  # name, unit, path, command printing the version
  local pid exe
  pid=$(systemctl show -p MainPID --value "$2")
  if [ "$pid" = 0 ]; then line "$1" not-running; return; fi
  exe=$(readlink "/proc/$pid/exe")
  if [ "$exe" != "$3" ]; then line "$1" stale; return; fi
  line "$1" "$(eval "$4")"
}
binary versitygw versitygw /usr/bin/versitygw "versitygw --version | awk '/^Version/ {print \$3}'"
binary vault vault /usr/local/bin/vault "vault version | awk '{print \$2}' | sed 's/^v//'"
binary consul consul /usr/local/bin/consul "consul version | awk 'NR == 1 {print \$2}' | sed 's/^v//'"
binary caddy caddy /usr/local/bin/caddy "caddy version | awk '{print \$1}' | sed 's/^v//'"

# Forgejo by the version it serves
if v=$(curl -fsS --max-time 5 http://127.0.0.1:3000/api/v1/version 2>/dev/null); then
  line forgejo "$(python3 -c 'import json, sys; print(json.load(sys.stdin)["version"].split("+")[0])' <<< "$v")"
else
  line forgejo not-running
fi
# Patroni by the version it serves (a pip upgrade without a restart still runs the old one)
if v=$(curl -fsS --max-time 5 http://127.0.0.1:8008/patroni 2>/dev/null); then
  line patroni "$(python3 -c 'import json, sys; print(json.load(sys.stdin)["patroni"]["version"])' <<< "$v")"
else
  line patroni not-running
fi
# Keycloak by the install its processes hold open (/opt/keycloak is a symlink a new install moves; the running
# kc.sh and java keep the directory they started from)
kc_pid=$(systemctl show -p MainPID --value keycloak)
if [ "$kc_pid" = 0 ]; then
  line keycloak not-running
else
  kc=$(for p in "$kc_pid" $(pgrep -P "$kc_pid" || true); do readlink /proc/"$p"/fd/* 2>/dev/null || true; done \
    | sed -n 's|^/opt/keycloak-\([^/]*\)/.*|\1|p' | sort -u)
  case "$kc" in
    '') line keycloak unknown ;;
    *[[:space:]]*) line keycloak stale ;;
    *) line keycloak "$kc" ;;
  esac
fi
# Nexus's install (it runs on the VIP's Pi only)
if [ -f /opt/nexus/.version ]; then line nexus "$(cat /opt/nexus/.version)"; fi
# Debian's, each installed one (dpkg-query fails for a package it has never seen: not installed)
for pkg in postgresql-17 postgresql-18 pgbouncer haproxy glusterfs-server keepalived; do
  if st=$(dpkg-query -W -f='${db:Status-Abbrev} ${Version}' "$pkg" 2>/dev/null); then
    case "$st" in [ih]i*) line "$pkg" "${st##* }" ;; esac
  fi
done
