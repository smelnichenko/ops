#!/bin/bash
# pi-restart-locked <what> - the restart script on stdin run while holding Consul's lock pi-restart: one restart of a
# service both Pis run (Forgejo, HAProxy, Keycloak) at a time, across both Pis and every Ansible run - two runs at once
# each found the other Pi serving and restarted their own, both down together. The script's own check of the other
# Pi, its restart and its wait for the service run inside the lock. Consul's session holds it while the script runs.
#
# The verdict is the script's own exit, recorded by the script itself: consul lock exits 0 when it lost the lock (this
# Pi's Consul agent restarted, its node critical) and killed the script, and 2 for any failure of the script - neither
# says what happened (Consul 1.20, measured 2026-11-16). Exit 0 only when the script ran to its own exit 0; otherwise 1,
# said. No quorum (or no Consul): no lock, no script, exit 1.
#
# Not under the lock (each stops or starts the services on purpose, both Pis at once or by their own rule): dpkg's own
# restarts of a package (HAProxy's, Forgejo with it), upgrade-forgejo.yml's stop-migrate-start, setup-gluster.yml's
# first stops, the Keycloak dump's restore. A session left by a holder killed hard frees itself (its TTL, then
# Consul's 15 s lock delay); `consul kv get -detailed pi-restart/.lock` names it.
#
# Installed by tasks/pi-restart-lock.yml; PI_RESTART_CONSUL (tests) names the consul binary.
set -euo pipefail
what=${1:?usage: pi-restart-locked <what> < script}
dir=$(mktemp -d "${TMPDIR:-/run}/pi-restart.XXXXXX")
trap 'rm -rf "$dir"' EXIT
# the script records its own exit (a signal - the lock lost - recorded as 143: bash's EXIT trap alone says 0 after one)
{ printf 'trap %q EXIT\ntrap %q TERM HUP INT\n' "echo \$? > $dir/rc" "exit 143"; cat; } > "$dir/body"
lock=0
"${PI_RESTART_CONSUL:-/usr/local/bin/consul}" lock -shell=false -timeout=20m -name="$(hostname) $what" pi-restart \
  /bin/bash "$dir/body" || lock=$?
rc=$(cat "$dir/rc" 2> /dev/null || echo none)
[ "$rc" = 0 ] || { echo "pi-restart-locked $what: the script's exit $rc inside the lock (none: never ran), consul lock's $lock" >&2; exit 1; }
