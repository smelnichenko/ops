"""kubectl on ten for the argocd-reader harness: answers the reads setup-argocd-reader makes there - argocd's
ExternalSecrets' Ready (name=Ready lines), a key of an argocd Secret (base64, as the API holds it) - from a state file;
every call logged (its verb, kind and namespace, never a value); anything else refused (exit 98), every call refused
(exit 1) while the state says "down".
argv: <state file> <log file> <kubectl's own arguments...>.
State: {"down": false, "ready": {es: "True"}, "secrets": {name: {key: value}}}.
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
if args[:2] == ["get", "externalsecret"] and ns == "argocd" and len(args) == 4 and "Ready" in jp:
    for k, v in sorted(st["ready"].items()):
        print(f"{k}={v}")
elif args[:2] == ["get", "secret"] and ns == "argocd" and len(args) > 2 and jp.startswith("{.data."):
    sec = st["secrets"].get(args[2])
    if sec is None:
        sys.exit(f'Error from server (NotFound): secrets "{args[2]}" not found')
    print(base64.b64encode(sec.get(jp[len("{.data."):-1], "").encode()).decode(), end="")
else:
    sys.exit(98)
