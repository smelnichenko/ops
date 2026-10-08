#!/bin/bash
# setup-argocd.yml: Argo CD's Helm install carries no secret, so it is not no_log - its preview (--check --diff, steps
# 31/33/34) and a failure's message are seen. The Keycloak client secret Argo CD's OIDC config names ($<secret>:<key>)
# is in a Secret of its own, written before the install by one no_log task, labelled app.kubernetes.io/part-of=argocd
# (Argo CD resolves references only in Secrets so labelled), its key the one referenced.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import re, sys
import yaml
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
play = yaml.safe_load(open("deploy/ansible/playbooks/setup-argocd.yml"))[0]
tasks = play["tasks"]
helm = next(t for t in tasks if t.get("name") == "Deploy Argo CD")
values = helm["kubernetes.core.helm"]["values"]
check("the Helm install not no_log (its preview and its failures seen)", helm.get("no_log", False), False)
check("its values carry no secret (no configs.secret.extra)", "extra" in (values.get("configs", {}).get("secret") or {}),
      False)
ref = re.search(r"clientSecret: \$([\w-]+):([\w.-]+)", values["configs"]["cm"]["oidc.config"])
check("the OIDC config names its client secret by reference", ref is not None, True)
if ref:
    name, key = ref.groups()
    writes = [t for t in tasks if (t.get("kubernetes.core.k8s") or {}).get("definition", {}).get("kind") == "Secret"
              and t["kubernetes.core.k8s"]["definition"]["metadata"]["name"] == name]
    check(f"the Secret {name} written by one task, before the install", (len(writes), bool(writes) and
          tasks.index(writes[0]) < tasks.index(helm)), (1, True))
    if writes:
        d = writes[0]["kubernetes.core.k8s"]["definition"]
        check("labelled part-of argocd (Argo CD resolves only such Secrets), in Argo CD's namespace, the key referenced",
              (d["metadata"].get("labels", {}).get("app.kubernetes.io/part-of"), d["metadata"].get("namespace"),
               key in (d.get("stringData") or d.get("data") or {})),
              ("argocd", "{{ argocd_namespace }}", True))
        check("that task no_log (its definition holds the secret)", writes[0].get("no_log"), True)
print("argocd-oidc-secret: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
