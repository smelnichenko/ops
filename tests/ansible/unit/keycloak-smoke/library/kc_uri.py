"""ansible.builtin.uri's stand-in: this Pi's /realms/master answer"""
from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.kc_pi import read

m = AnsibleModule(argument_spec={"url": {}, "status_code": {"type": "raw"}, "timeout": {"type": "int"},
                                 "follow_redirects": {}}, supports_check_mode=True)
code = int(read("http", "0") or 0)
if code == 200:
    m.exit_json(changed=False, status=200)
m.fail_json(msg=f"Status code was {code}", status=code or -1)
