"""ansible.builtin.systemd's stand-in: keycloak's unit on this Pi - started runs the version its link names"""
from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.kc_pi import event, read, write

m = AnsibleModule(argument_spec={"name": {}, "state": {}}, supports_check_mode=True)
state = m.params["state"]
if state == "stopped":
    event("stopped")
    write("running", "")
    write("http", "000")
    write("active", "inactive")
elif state == "started":
    event("started")
    if not read("running"):
        write("running", read("link"))
        write("http", "200")
        write("active", "active")
elif state:
    m.fail_json(msg=f"kc_systemd: state {state} not stood in for")
m.exit_json(changed=bool(state), status={"ActiveState": read("active", "inactive")})
