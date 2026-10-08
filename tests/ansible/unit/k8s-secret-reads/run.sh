#!/bin/bash
# A Kubernetes Secret's data never in Ansible's output: every task that reads one (k8s_info of kind Secret, registered),
# writes one (k8s of kind Secret - its arguments hold the data) or prints one (kubectl get secret with an output other
# than its name) is no_log. Ansible prints a task's result at -v and on a failure: the Velero credentials' wait printed
# their S3 keys, a Keycloak diagnosis the Secret's whole data, a CI diagnosis the registry's credentials. A
# read that prints only what is public - a certificate, a listing of keys - is named below with its reason, and each
# one named must still be such a task (none left behind).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import re
import sys
sys.path.insert(0, "tests/ansible/unit")
from plays import actions, files, load, tasks  # noqa: E402
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
# what prints only what is public: (file, task) - why, and what its script must hold so (continuations joined): a read
# of the whole data, a credential back on curl's command line or in the script - put back unseen otherwise
def norm(x):
    """Continuations joined, comment lines out (their words are no command)."""
    return "\n".join(l for l in re.sub(r"\\\n\s*", " ", x).splitlines() if not l.lstrip().startswith("#"))
def reads(x):
    """The lines of a script that read a Secret as the lint reads one (CLI, below): every spelling, not one."""
    return [line for line in norm(x).splitlines() if CLI.search(line)]
PUBLIC = {
    ("tests/ansible/upgrade/production-state.yml",
     "The Vagrant wildcard is production's Let's Encrypt certificate, valid for at least another day"):
        ("the certificate (tls.crt) alone",
         lambda x, t: bool(reads(x)) and all(re.findall(r"jsonpath='([^']*)'", line) == [r"{.data.tls\.crt}"]
                                             for line in reads(x))),
    ("tests/ansible/test-keycloak.yml", "DIAG events + describe + eso + secret"):
        ("the Secret's key names alone",
         lambda x, t: all(re.search(r"-o json\s*\|\s*python3 -c '[^']*sorted\(json\.load\(sys\.stdin\)\.get\(\"data\"", line)
                          for line in reads(x))),
    ("tests/ansible/test-cicd.yml", "DIAG pod pull failure"):
        ("the registry hosts of its credentials alone - its token on no command line, in no script, in no "
         "environment (Ansible puts that on the module's command line, and prints it at -vvv, no_log or not)",
         lambda x, t: all(re.search(r"base64 -d\s*\|\s*python3 -c '[^']*sorted\(json\.load\(sys\.stdin\)\.get\(\"auths\"", line)
                          for line in reads(x))
         and "registry_token" not in str(t) and not re.search(r"curl [^\n]*(-u |--user|-sv|-v )", norm(x))),
}
# kubectl get of a Secret printing more than its name: the resource where it stands among get's flags (-n x secret),
# quoted, by kind/name, in a list (configmap,secret), its output (-o/--output other than name, a --template) before or
# after it; the API read straight (get --raw, curl) at a secrets path
# the API's own path to Secrets (a uri task's url)
API = re.compile(r"/api/v1/(?:namespaces/[^/\s]+/)?secrets\b")
RES = r"['\"]?(?:[\w.-]+,)*secrets?(?:\.v1)?(?:,[\w.-]+)*['\"]?(?:/\S+)?(?=[\s'\"]|$)"
OUT = r"(?:(?:-o|--output)[ =]*['\"]?(?!name\b)\w|--template\b)"
CLI = re.compile(rf"\bget\b(?:\s+-{{1,2}}[\w-]+(?:[ =][^\s-]\S*)?)*\s+{RES}[^\n|;&]*?{OUT}"
                 rf"|\bget\b[^\n|;&]*?{OUT}[^\n|;&]*?\s{RES}"
                 r"|\bget\s+--raw[ =]+['\"]?/api/v1/\S*/secrets\b|\bcurl\b[^\n]*?/api/v1/\S*/secrets\b")
# the forms it reads, each alone: a Secret's data printed - named; its name alone, another kind - not
FORMS = ["kubectl get secret x -o json", "kubectl get -n ns secret x -o yaml", "kubectl -n ns get secret x -ojsonpath='{.data}'",
         "kubectl get -o yaml secret x", "kubectl get 'secret' x -o json", "kubectl get secret/x -o json",
         "kubectl get configmap,secret -n x -o yaml", "kubectl get secret.v1 x --template '{{.data}}'",
         "kubectl get --raw /api/v1/namespaces/x/secrets/y", "curl -sf https://k:6443/api/v1/namespaces/x/secrets/y",
         "kubectl get secrets -n x -o=json"]
QUIET = ["kubectl get secret x -o name", "kubectl get secrets -n x", "kubectl get configmap x -o yaml",
         "kubectl get pods -o yaml | grep secret", "kubectl get -n x secret x -o name", "kubectl get secretstores -o yaml"]
check("a uri task reading the API's Secrets path: read as one; its ConfigMaps' not",
      [bool(API.search(u)) for u in ("https://k:6443/api/v1/namespaces/x/secrets/y", "https://k:6443/api/v1/secrets",
                                     "https://k:6443/api/v1/namespaces/x/configmaps/y")], [True, True, False])
check("each way a Secret's data is printed read as one; its name alone, another kind not",
      ([f for f in FORMS if not CLI.search(f)], [f for f in QUIET if CLI.search(f)]), ([], []))
found, public_seen, printed = [], set(), []
MSG = ("assert", "fail", "debug")
for f in files():
    ts = list(tasks(load(f)))
    secret_regs = set()
    for t in ts:
        for mod, val in actions(t):
            m = str(mod).split(".")[-1]
            kind = ""
            if isinstance(val, dict):
                d = val.get("definition")
                docs = d if isinstance(d, list) else [d]
                kinds = [str(val.get("kind") or "")] + [str(x.get("kind", "")) for x in docs if isinstance(x, dict)]
                if isinstance(d, str) and re.search(r"^kind:\s*Secret\s*$", d, re.M):
                    kinds.append("Secret")
                kind = "secret" if any(k.lower() == "secret" for k in kinds) else ""
            what = None
            if m == "k8s_info" and kind.lower() == "secret" and t.get("register"):
                what = "reads a Secret"
            elif m == "k8s" and kind.lower() == "secret":
                what = "writes a Secret"
            elif m in ("shell", "command") and CLI.search(re.sub(r"\\\n\s*", " ", str(
                    val.get("cmd", val.get("argv", val)) if isinstance(val, dict) else val))):
                what = "prints a Secret"
            elif m == "uri" and isinstance(val, dict) and API.search(str(val.get("url", ""))) and t.get("register"):
                what = "reads a Secret through the API"
            if what is None:
                continue
            key = (f, t.get("name"))
            if key in PUBLIC:
                public_seen.add(key)
                if not PUBLIC[key][1](str(val.get("cmd", val) if isinstance(val, dict) else val), t):
                    found.append((f, t.get("name"), "named public, prints more: " + PUBLIC[key][0], None))
                continue
            found.append((f, t.get("name"), what, t.get("no_log")))
            if what != "writes a Secret" and t.get("register"):
                secret_regs.add(t["register"])
    # what such a read registered is printed by no message: an assert's fail_msg, a fail's, a debug's - no_log hid the
    # task's own output, the message printed the value (test-eso's said the Secret's API_KEY on a mismatch)
    for t in ts:
        for mod, val in actions(t):
            if str(mod).split(".")[-1] in MSG and isinstance(val, dict):
                msg = " ".join(str(val.get(k, "")) for k in ("fail_msg", "msg", "success_msg", "var"))
                for r in secret_regs:
                    for j in re.findall(r"\{\{(.*?)\}\}", msg, re.S) + ([msg] if "var" in val else []):
                        if re.search(r"\b" + re.escape(r) + r"(\.(stdout|stdout_lines|json|resources|content)\b|\s*(\||$))",
                                     j.strip()):
                            printed.append(f"{f}: {t.get('name')}: {r}")
check("no message prints what a Secret's read registered", sorted(set(printed)), [])
# each named-public read held to its reason on every line that reads a Secret as the lint reads one - a read spelt
# otherwise (flags before the resource) added beside it passed the predicates' own filter
public_texts = {}
for f in files():
    for t in tasks(load(f)):
        for mod, val in actions(t):
            if (f, t.get("name")) in PUBLIC:
                public_texts[(f, t.get("name"))] = (str(val.get("cmd", val) if isinstance(val, dict) else val), t)
EXTRA = "\nkubectl get -n x -o yaml secret y"
check("each public read with a whole Secret read added beside it (flags before the resource): no longer public",
      sorted(k[1] for k, (x, t) in public_texts.items() if PUBLIC[k][1](x + EXTRA, t)), [])
bad = [x for x in found if x[3] is not True]
check("every task reading, writing or printing a Secret's data is no_log", len(bad), 0)
for f, n, w, _ in bad:
    print(f"    {f}: {n} - {w}, not no_log")
check("the reads named public, each still a task that reads a Secret (none left behind)",
      sorted(set(PUBLIC) - public_seen), [])
check("the tasks found: the lint sees Argo CD's client secret, the Velero credentials, the CNPG owner secret",
      sorted(n for f, n, w, _ in found if n in ("The Secret its client secret is in", "Wait for Velero credentials secret",
                                                  "Is the CNPG owner secret there already")),
      ["Is the CNPG owner secret there already", "The Secret its client secret is in",
       "Wait for Velero credentials secret"])
print("k8s-secret-reads: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
