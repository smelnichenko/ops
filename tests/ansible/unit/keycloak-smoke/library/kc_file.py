"""ansible.builtin.file's stand-in: /opt/keycloak moved (a link), or an install's owner set"""
from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.kc_pi import OPT, event, write

ARGS = ("path", "src", "dest", "state", "owner", "group")
m = AnsibleModule(argument_spec={**{a: {} for a in ARGS}, "force": {"type": "bool"}, "recurse": {"type": "bool"}},
                  supports_check_mode=True)
path, src, dest, state, owner, group = (m.params[a] for a in ARGS)
if state == "link":
    if dest != "/opt/keycloak" or not (src or "").startswith(OPT):
        m.fail_json(msg=f"kc_file: a link {dest} -> {src} not stood in for")
    version = src[len(OPT):]
    event(f"link {version} force={m.params['force']}")
    write("link", version)
else:
    event(f"chown {owner}:{group} recurse={m.params['recurse']} {path}")
m.exit_json(changed=True)
