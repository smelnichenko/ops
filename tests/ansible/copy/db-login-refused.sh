#!/bin/bash
# On the Vagrant copy (task test:copy:check): a database login that does not work is refused before Forgejo's config or
# Keycloak's secrets are touched - setup-pi-services.yml run narrow (--tags forgejo-config, --tags keycloak-db-url) with
# a wrong password for each, the refusal read in its output, each Pi's app.ini and secrets.env the same after as before,
# both services still serving on both Pis.
set -uo pipefail
cd "$(dirname "$0")/../../../deploy/ansible" || exit 1
inv=inventory/vagrant.yml
sums() {  # each Pi's two files, hashed (a line a Pi, sorted)
  venv/bin/ansible pis -i "$inv" -b -o -m ansible.builtin.command \
    -a 'sha256sum /var/lib/forgejo/custom/conf/app.ini /etc/keycloak/secrets.env' 2>&1 | sed 's/ | CHANGED | rc=0 >>/:/' | sort
}
serving() {  # each Pi's Forgejo and Keycloak answering
  venv/bin/ansible pis -i "$inv" -o -m ansible.builtin.uri -a 'url=http://127.0.0.1:3000/api/healthz' > /dev/null 2>&1 \
    && venv/bin/ansible pis -i "$inv" -o -m ansible.builtin.uri -a 'url=http://127.0.0.1:8080/realms/master' > /dev/null 2>&1
}
before=$(sums)
fails=0
refused() {  # refused <tag> <variable> <what the output must show>
  local out rc
  out=$(env -i HOME="$HOME" PATH="$PATH" venv/bin/ansible-playbook -i "$inv" ../../tests/ansible/vagrant-only-play.yml \
          playbooks/setup-pi-services.yml --tags "$1" -e "$2=nottherolepassword1" 2>&1); rc=$?
  if [ "$rc" != 0 ] && grep -qF "$3" <<< "$out"; then
    echo "PASS $1 with a wrong $2: refused ($3)"
  else
    echo "FAIL $1 with a wrong $2: rc=$rc, '$3' $(grep -qF "$3" <<< "$out" && echo shown || echo 'not shown')"
    tail -n 20 <<< "$out" | sed 's/^/    /'
    fails=$((fails + 1))
  fi
}
refused forgejo-config forgejo_db_password "REFUSED: Forgejo's role cannot log into its database"
refused keycloak-db-url keycloak_db_password "TASK [The secrets file's login works for Keycloak's role and database]"
after=$(sums)
if [ -n "$before" ] && [ "$before" = "$after" ]; then echo "PASS each Pi's app.ini and secrets.env as they were"
else echo "FAIL the files changed:"; diff <(echo "$before") <(echo "$after") | sed 's/^/    /'; fails=$((fails + 1)); fi
if serving; then echo "PASS Forgejo and Keycloak serving on both Pis"; else echo "FAIL a service not serving after the refusals"; fails=$((fails + 1)); fi
echo "db-login-refused: $([ $fails -eq 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails -eq 0 ]
