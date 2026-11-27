"""ansible.builtin.stat's stand-in: a path in one of this Pi's Keycloak installs"""
import os

from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.kc_pi import install

m = AnsibleModule(argument_spec={"path": {}}, supports_check_mode=True)
path = install(m.params["path"])
m.exit_json(changed=False, stat={"exists": os.path.exists(path), "isdir": os.path.isdir(path)})
