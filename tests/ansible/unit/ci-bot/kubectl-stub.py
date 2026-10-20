"""kubectl on ten for the ci-bot harness: answers the reads setup-ci-bot makes there - an ExternalSecret's Ready
condition (woodpecker-ci-secrets-es, forgejo-registry-es), a key of the Secret woodpecker-ci-secrets, the
.dockerconfigjson of the Secret forgejo-registry (base64, as the API holds them) - from a state file; every call logged
(its verb and kind, never a value); anything else refused (exit 98), and every call refused (exit 1, as kubectl says a
connection refused) while the state says "down".
argv: <state file> <log file> <kubectl's own arguments...>.
State: {"down": false, "ready": {es: "True"}, "secret": {key: value}, "pull": {"username": u, "password": p}}.
"""
import base64
import json
import sys

state_file, log_file, args = sys.argv[1], sys.argv[2], sys.argv[3:]
if "--kubeconfig" in args:
    i = args.index("--kubeconfig")
    args = args[:i] + args[i + 2:]
ns = None
if "-n" in args:
    i = args.index("-n")
    ns, args = args[i + 1], args[:i] + args[i + 2:]
with open(log_file, "a") as f:
    f.write(" ".join(args[:2]) + f" -n {ns}\n")
st = json.load(open(state_file))
if st.get("down"):
    sys.exit("The connection to the server 192.168.11.2:6443 was refused - did you specify the right host or port?")
jp = next((x.split("=", 1)[1] for x in args if x.startswith("jsonpath=")), "")
b64 = lambda s: base64.b64encode(s.encode()).decode()  # noqa: E731
if args[:2] == ["get", "externalsecret"] and ns == "woodpecker" and "Ready" in jp and len(args) > 2:
    print(st["ready"].get(args[2], ""), end="")
elif args[:3] == ["get", "secret", "woodpecker-ci-secrets"] and ns == "woodpecker" and jp.startswith("{.data."):
    print(b64(st["secret"].get(jp[len("{.data."):-1], "")), end="")
elif args[:3] == ["get", "secret", "forgejo-registry"] and ns == "woodpecker" and jp == "{.data.\\.dockerconfigjson}":
    print(b64(json.dumps({"auths": {"git.pmon.dev": st["pull"]}})), end="")
else:
    sys.exit(98)
