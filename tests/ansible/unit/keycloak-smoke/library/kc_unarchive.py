"""ansible.builtin.unarchive's stand-in: the install extracted whole - skipped when `creates` is there, whole or not"""
import os

from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.kc_pi import event, install

m = AnsibleModule(argument_spec={"src": {}, "dest": {}, "remote_src": {"type": "bool"}, "creates": {}},
                  supports_check_mode=True)
target = install(m.params["creates"])
if os.path.exists(target):
    m.exit_json(changed=False)
event("unarchive")
for part in ("bin/kc.sh", "lib/quarkus-run.jar"):
    os.makedirs(os.path.dirname(os.path.join(target, part)), exist_ok=True)
    open(os.path.join(target, part), "w").close()
m.exit_json(changed=True)
