#!/bin/bash
# ops CI's Ansible is production's own: built as `task deploy:install` builds it - deploy/ansible/venv from
# requirements.txt, the collections from requirements.yml into the project's path (ansible.cfg collections_path) - plus
# ansible-lint and hvac (the Vault modules' client), held to the same pins as constraints. Then checked as pinned
# (scripts/ansible-versions.py --check): CI tests the very Ansible every deploy runs. (Until 2026-11-20 CI used an image
# of its own whose Ansible had drifted from production's: ansible-core 2.21.5 against 2.20.3.)
set -euo pipefail
cd "$(dirname "$0")/../deploy/ansible"
python3 -m venv venv
venv/bin/pip install -q --no-cache-dir -r requirements.txt
venv/bin/pip install -q --no-cache-dir -c requirements.txt ansible-lint hvac
venv/bin/ansible-galaxy collection install -r requirements.yml -p collections --force > /dev/null
venv/bin/python3 ../../scripts/ansible-versions.py --check
