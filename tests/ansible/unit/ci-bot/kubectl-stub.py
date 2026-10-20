"""kubectl on ten for the ci-bot harness: answers the two reads the retire play makes - the ExternalSecret's Ready
condition, a key of the Secret (base64, as the API holds it) - from a state file; every call logged (its verb and kind,
never a value); anything but those reads refused (exit 98).
argv: <state file> <log file> <kubectl's own arguments...>. State: {"ready": "True", "secret": {key: value}}.
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
jp = next((x.split("=", 1)[1] for x in args if x.startswith("jsonpath=")), "")
if args[:3] == ["get", "externalsecret", "woodpecker-ci-secrets-es"] and ns == "woodpecker" and "Ready" in jp:
    print(st["ready"], end="")
elif args[:3] == ["get", "secret", "woodpecker-ci-secrets"] and ns == "woodpecker" and jp.startswith("{.data."):
    key = jp[len("{.data."):-1]
    print(base64.b64encode(st["secret"].get(key, "").encode()).decode(), end="")
else:
    sys.exit(98)
