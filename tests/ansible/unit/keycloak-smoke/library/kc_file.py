"""ansible.builtin.file's stand-in: /opt/keycloak moved (a link), a mark touched in an install, or an install's owner
set - any other use is not stood in for"""
import os

from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.kc_pi import OPT, event, install, write

ARGS = ("path", "src", "dest", "state", "owner", "group", "mode", "modification_time", "access_time")
m = AnsibleModule(argument_spec={**{a: {} for a in ARGS}, "force": {"type": "bool"}, "recurse": {"type": "bool"}},
                  supports_check_mode=True)
path, src, dest, state, owner, group = (m.params[a] for a in ARGS[:6])
if state == "link":
    if dest != "/opt/keycloak" or not (src or "").startswith(OPT):
        m.fail_json(msg=f"kc_file: a link {dest} -> {src} not stood in for")
    version = src[len(OPT):]
    event(f"link {version} force={m.params['force']}")
    write("link", version)
elif state == "touch":
    open(install(path), "a").close()
    event(f"touch {os.path.basename(path)}")
elif state is None and owner:
    event(f"chown {owner}:{group} recurse={m.params['recurse']} {path}")
else:
    m.fail_json(msg=f"kc_file: state {state} on {path} not stood in for")
m.exit_json(changed=True)
