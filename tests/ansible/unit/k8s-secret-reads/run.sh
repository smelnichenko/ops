#!/bin/bash
# A Kubernetes Secret's data never in Ansible's output: every task that reads one (k8s_info of kind Secret, registered),
# writes one (k8s of kind Secret - its arguments hold the data) or prints one (kubectl get secret with an output other
# than its name) is no_log. Ansible prints a task's result at -v and on a failure: the Velero credentials' wait printed
# their S3 keys, a Keycloak diagnosis the Secret's whole data, a CI diagnosis the registry's credentials (review 7). A
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
# what prints only what is public: (file, task) - why
PUBLIC = {
    ("tests/ansible/upgrade/production-state.yml",
     "The Vagrant wildcard is production's Let's Encrypt certificate, valid for at least another day"):
        "the certificate (tls.crt) alone",
    ("tests/ansible/test-keycloak.yml", "DIAG events + describe + eso + secret"): "the Secret's key names alone",
    ("tests/ansible/test-cicd.yml", "DIAG pod pull failure"): "the registry hosts of its credentials alone",
}
CLI = re.compile(r"\bget\s+secrets?\b[^\n|;&]*?(-o|--output)[ =]*(?!name\b)\S")
found, public_seen = [], set()
for f in files():
    for t in tasks(load(f)):
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
            if what is None:
                continue
            key = (f, t.get("name"))
            if key in PUBLIC:
                public_seen.add(key)
                continue
            found.append((f, t.get("name"), what, t.get("no_log")))
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
