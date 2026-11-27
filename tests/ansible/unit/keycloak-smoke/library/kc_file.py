"""ansible.builtin.file's stand-in: /opt/keycloak moved (a link), or an install's owner set"""
from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.kc_pi import OPT, event, write

m = AnsibleModule(argument_spec={"path": {}, "src": {}, "dest": {}, "state": {}, "force": {"type": "bool"},
                                 "owner": {}, "group": {}, "recurse": {"type": "bool"}}, supports_check_mode=True)
p = m.params
if p["state"] == "link":
    if p["dest"] != "/opt/keycloak" or not (p["src"] or "").startswith(OPT):
        m.fail_json(msg=f"kc_file: a link {p['dest']} -> {p['src']} not stood in for")
    version = p["src"][len(OPT):]
    event(f"link {version} force={p['force']}")
    write("link", version)
else:
    event(f"chown {p['owner']}:{p['group']} recurse={p['recurse']} {p['path']}")
m.exit_json(changed=True)
