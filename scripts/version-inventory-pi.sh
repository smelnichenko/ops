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
# Patroni's package (pip), Keycloak's and Nexus's installs (Nexus runs on the VIP's Pi only)
line patroni "$(patroni --version 2>/dev/null | awk '{print $2}' || echo none)"
line keycloak "$(readlink -f /opt/keycloak 2>/dev/null | sed -n 's|^/opt/keycloak-||p')"
[ -f /opt/nexus/.version ] && line nexus "$(cat /opt/nexus/.version)"
# Debian's
dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' \
  postgresql-17 postgresql-18 pgbouncer haproxy glusterfs-server keepalived 2>/dev/null \
  | awk -v h="$host" '$1 ~ /^[ih]i/ {print "pi", h, $2, $3}'
