"""kubectl on ten for the argocd-reader harness, from a state file: the reads setup-argocd-reader makes there (argocd's
ExternalSecrets' Ready, a key of an argocd Secret or of another namespace's - kagent's, argocd's repository credentials
by their label, the Applications), its one write (--tags retire: the last-applied annotation off forgejo-repo-creds),
and setup-argocd's (a merge patch of forgejo-repo-creds from stdin). Every call logged (its verb, kind and namespace,
never a value); anything else refused (exit 98), every call refused (exit 1) while "down".
argv: <state file> <log file> <kubectl's own arguments...>.
State: {"down": false, "ready": {es: "True"}, "secrets": {name: {key: value}}, "labels": {secret: secret-type},
        "other": {namespace: {name: {key: value}}}, "annotations": {secret: [key]}, "apps": [Application],
        "annotate_fault": null | "notfound" (the Secret gone) | "forbidden"}.
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
SELECTOR = "argocd.argoproj.io/secret-type in (repository,repo-creds)"
if ns != "argocd":
    # another namespace's Secret, one key: a namespace missing answers as kubectl does (the Secret not found)
    if args[:2] != ["get", "secret"] or len(args) < 3 or not jp.startswith("{.data."):
        sys.exit(98)
    sec = st.get("other", {}).get(ns, {}).get(args[2])
    if sec is None:
        sys.exit(f'Error from server (NotFound): secrets "{args[2]}" not found')
    print(base64.b64encode(sec.get(jp[len("{.data."):-1], "").encode()).decode(), end="")
    sys.exit(0)
if args[:2] == ["get", "externalsecret"] and len(args) == 4 and "Ready" in jp:
    for k, v in sorted(st["ready"].items()):
        print(f"{k}={v}")
elif args[:2] == ["get", "applications"] and args[2:] == ["-o", "json"]:
    print(json.dumps({"items": st.get("apps", [])}))
elif args[:2] == ["get", "secret"] and args[2:] == ["-l", SELECTOR, "-o", "json"]:
    print(json.dumps({"items": [
        {"metadata": {"name": n, "labels": {"argocd.argoproj.io/secret-type": t}},
         "data": {k: base64.b64encode(v.encode()).decode() for k, v in st["secrets"].get(n, {}).items()}}
        for n, t in sorted(st.get("labels", {}).items()) if t in ("repository", "repo-creds") and n in st["secrets"]]}))
elif args[:2] == ["get", "secret"] and len(args) > 2 and jp.startswith("{.data."):
    sec = st["secrets"].get(args[2])
    if sec is None:
        sys.exit(f'Error from server (NotFound): secrets "{args[2]}" not found')
    print(base64.b64encode(sec.get(jp[len("{.data."):-1], "").encode()).decode(), end="")
elif args[:3] == ["annotate", "secret", "forgejo-repo-creds"] and args[3:] == [
        "kubectl.kubernetes.io/last-applied-configuration-"]:
    if st.get("annotate_fault") == "notfound" or "forgejo-repo-creds" not in st["secrets"]:
        sys.exit('Error from server (NotFound): secrets "forgejo-repo-creds" not found')
    if st.get("annotate_fault") == "forbidden":
        sys.exit('Error from server (Forbidden): secrets "forgejo-repo-creds" is forbidden')
    have = st.setdefault("annotations", {}).setdefault("forgejo-repo-creds", [])
    if "kubectl.kubernetes.io/last-applied-configuration" in have:
        have.remove("kubectl.kubernetes.io/last-applied-configuration")
        json.dump(st, open(state_file, "w"))
    print("secret/forgejo-repo-creds annotated")
elif args[:3] == ["patch", "secret", "forgejo-repo-creds"] and args[3:] == ["--type", "merge", "--patch-file",
                                                                         "/dev/stdin"]:
    patch = json.load(sys.stdin)
    st["secrets"].setdefault("forgejo-repo-creds", {}).update(patch["stringData"])
    json.dump(st, open(state_file, "w"))
    print("secret/forgejo-repo-creds patched")
else:
    sys.exit(98)
