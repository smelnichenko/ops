"""ansible.builtin.uri's stand-in: this Pi's /realms/master answer - any other URL is not stood in for"""
from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.kc_pi import read

m = AnsibleModule(argument_spec={"url": {}, "status_code": {"type": "raw"}, "timeout": {"type": "int"},
                                 "follow_redirects": {}}, supports_check_mode=True)
url = m.params["url"]
if url != "http://127.0.0.1:8080/realms/master":
    m.fail_json(msg=f"kc_uri: {url} not stood in for")
code = int(read("http", "0") or 0)
if code == 200:
    m.exit_json(changed=False, status=200)
m.fail_json(msg=f"Status code was {code}", status=code or -1)
