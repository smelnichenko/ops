"""ansible.builtin.systemd's stand-in: keycloak's unit on this Pi (Restart=always, as setup-pi-services.yml installs it).
Started runs the version its link names; a Pi marked wont-start crash-loops instead - its unit activating, its JVM up on
that install, never serving (never "failed": systemd restarts it for ever). Started on a running unit changes nothing."""
from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.kc_pi import event, read, write

RUNNING, HTTP, UNIT = "running", "http", "active"  # this Pi's state files: the version(s) running, its answer, its unit
m = AnsibleModule(argument_spec={"name": {}, "state": {}}, supports_check_mode=True)
state, unit = m.params["state"], m.params["name"]
if unit != "keycloak":
    m.fail_json(msg=f"kc_systemd: unit {unit} not stood in for")
if state == "stopped":
    event("stopped")
    write(RUNNING, "")
    write(HTTP, "000")
    write(UNIT, "inactive")
elif state == "started":
    event("started")
    if read("wont-start"):
        write(RUNNING, read("link"))
        write(UNIT, "activating")
    elif not read(RUNNING):
        write(RUNNING, read("link"))
        write(HTTP, "200")
        write(UNIT, "active")
elif state:
    m.fail_json(msg=f"kc_systemd: state {state} not stood in for")
m.exit_json(changed=bool(state), status={"ActiveState": read(UNIT, "inactive")})
