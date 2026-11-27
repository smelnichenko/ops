"""ansible.builtin.unarchive's stand-in: the install extracted whole over whatever is there - skipped when `creates` (the
mark the next task writes once an extract ended) is there"""
import os

from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.kc_pi import event, install

m = AnsibleModule(argument_spec={"src": {}, "dest": {}, "remote_src": {"type": "bool"}, "creates": {}},
                  supports_check_mode=True)
mark = install(m.params["creates"])
if os.path.exists(mark):
    m.exit_json(changed=False)
event("unarchive")
root = os.path.dirname(mark) if os.path.basename(mark).startswith(".") else mark
for part in ("bin/kc.sh", "lib/quarkus-run.jar"):
    os.makedirs(os.path.dirname(os.path.join(root, part)), exist_ok=True)
    open(os.path.join(root, part), "w").close()
m.exit_json(changed=True)
