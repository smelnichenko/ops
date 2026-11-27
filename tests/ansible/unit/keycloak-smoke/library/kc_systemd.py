"""ansible.builtin.systemd's stand-in: keycloak's unit on this Pi - started runs the version its link names"""
from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.kc_pi import event, read, write

RUNNING, HTTP, UNIT = "running", "http", "active"  # this Pi's state files: the version(s) running, its answer, its unit
m = AnsibleModule(argument_spec={"name": {}, "state": {}}, supports_check_mode=True)
state = m.params["state"]
if state == "stopped":
    event("stopped")
    write(RUNNING, "")
    write(HTTP, "000")
    write(UNIT, "inactive")
elif state == "started":
    event("started")
    if not read(RUNNING):
        write(RUNNING, read("link"))
        write(HTTP, "200")
        write(UNIT, "active")
elif state:
    m.fail_json(msg=f"kc_systemd: state {state} not stood in for")
m.exit_json(changed=bool(state), status={"ActiveState": read(UNIT, "inactive")})
