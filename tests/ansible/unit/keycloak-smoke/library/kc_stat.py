"""ansible.builtin.stat's stand-in: a path in one of this Pi's Keycloak installs (no isdir for a path not there, as stat)"""
import os

from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.kc_pi import install

m = AnsibleModule(argument_spec={"path": {}}, supports_check_mode=True)
path = install(m.params["path"])
there = os.path.exists(path)
m.exit_json(changed=False, stat={"exists": True, "isdir": os.path.isdir(path)} if there else {"exists": False})
