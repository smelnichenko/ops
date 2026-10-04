#!/usr/bin/env bash
# version-inventory-pi.sh - what a Pi runs that the upgrade changes, in the inventory's line format, prefixed by the
# Pi: "pi <host> versitygw <version>". The version of the process running, not of the package: a package upgrade
# leaves the gateway on the replaced binary until it restarts - then it reads "stale" (the binary it runs is deleted).
# Read-only. Runs ON a Pi (production pi1/pi2, or the Vagrant Pi VMs):
#   ssh pi1 'sudo bash -s' < scripts/version-inventory-pi.sh
set -euo pipefail
host=$(hostname -s)
pid=$(systemctl show -p MainPID --value versitygw)
if [ "$pid" = 0 ]; then
  echo "pi $host versitygw not-running"
elif [ "$(readlink "/proc/$pid/exe")" != /usr/bin/versitygw ]; then
  echo "pi $host versitygw stale"
else
  echo "pi $host versitygw $(versitygw --version | awk '/^Version/ {print $3}')"
fi
