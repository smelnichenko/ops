"""kubectl on ten for the ci-bot harness: answers the reads setup-ci-bot makes there - an ExternalSecret's Ready (one by
name, or every forgejo-registry-es across namespaces), a key of the Secret woodpecker/woodpecker-ci-secrets, every
namespace's Secret forgejo-registry (its .dockerconfigjson, base64 as the API holds it) - from a state file; every call
logged (its verb, kind and namespace - "*" for all - never a value); anything else refused (exit 98), and every call
refused (exit 1, as kubectl says a connection refused) while the state says "down".
argv: <state file> <log file> <kubectl's own arguments...>.
State: {"down": false, "ready": {"<ns>/<es>": "True"}, "secret": {key: value}, "pull": {ns: password}}.
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
every = "-A" in args
args = [a for a in args if a != "-A"]
sel = None
if "--field-selector" in args:
    i = args.index("--field-selector")
    sel, args = args[i + 1], args[:i] + args[i + 2:]
with open(log_file, "a") as f:
    f.write(" ".join(args[:2]) + f" -n {'*' if every else ns}\n")
st = json.load(open(state_file))
if st.get("down"):
    sys.exit("The connection to the server 192.168.11.2:6443 was refused - did you specify the right host or port?")
jp = next((x.split("=", 1)[1] for x in args if x.startswith("jsonpath=")), "")
b64 = lambda s: base64.b64encode(s.encode()).decode()  # noqa: E731
cfg = lambda p: b64(json.dumps({"auths": {"git.pmon.dev": {"username": "woodpecker-ci", "password": p}}}))  # noqa
if args[:3] == ["get", "externalsecret", "woodpecker-ci-secrets-es"] and ns == "woodpecker" and "Ready" in jp:
    print(f"woodpecker/woodpecker-ci-secrets-es={st['ready'].get('woodpecker/woodpecker-ci-secrets-es', '')}", end="")
elif args[:2] == ["get", "externalsecret"] and every and sel == "metadata.name=forgejo-registry-es" and "Ready" in jp:
    for k, v in sorted(st["ready"].items()):
        if k.endswith("/forgejo-registry-es"):
            print(f"{k}={v}")
elif args[:3] == ["get", "secret", "woodpecker-ci-secrets"] and ns == "woodpecker" and jp.startswith("{.data."):
    print(b64(st["secret"].get(jp[len("{.data."):-1], "")), end="")
elif args[:2] == ["get", "secret"] and every and sel == "metadata.name=forgejo-registry" and "dockerconfigjson" in jp:
    for n, p in sorted(st["pull"].items()):
        print(f"{n} {cfg(p)}")
else:
    sys.exit(98)
