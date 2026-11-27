"""ansible.builtin.get_url's stand-in: the tarball fetched - whether a sha256 came with it"""
import re

from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.kc_pi import event

m = AnsibleModule(argument_spec={"url": {}, "dest": {}, "checksum": {}, "mode": {}, "timeout": {"type": "int"}},
                  supports_check_mode=True)
sha = re.fullmatch(r"sha256:[\da-f]{64}", m.params["checksum"] or "")
event(f"get_url {'sha256' if sha else 'unchecked'} {m.params['url']}")
m.exit_json(changed=True)
