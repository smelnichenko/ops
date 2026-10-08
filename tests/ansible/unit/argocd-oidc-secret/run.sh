#!/bin/bash
# setup-argocd.yml: Argo CD's Helm install carries no secret, so it is not no_log - its preview (--check --diff, steps
# 31/33/34) and a failure's message are seen. The Keycloak client secret Argo CD's OIDC config names ($<secret>:<key>)
# is in a Secret of its own, written before the install by one no_log task, labelled app.kubernetes.io/part-of=argocd
# (Argo CD resolves references only in Secrets so labelled), its key the one referenced. After the install single
# sign-on is verified as the server reads it - argocd-cm's OIDC config naming that Secret and key, the Secret holding a
# value: production's earlier shape named a key in argocd-secret, which the install drops (step 31 moves it there).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import base64, re, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition  # noqa: E402
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
# single sign-on verified after the install, as the server reads it
sso = [t for t in tasks if "ansible.builtin.assert" in t and "argocd-oidc-keycloak" in str(t["ansible.builtin.assert"])]
check("single sign-on verified after the install", len(sso) == 1 and bool(sso) and tasks.index(sso[0]) > tasks.index(helm),
      True)
if sso:
    a = sso[0]["ansible.builtin.assert"]
    regs = [t.get("register") for t in tasks if "kubernetes.core.k8s_info" in t
            and t["kubernetes.core.k8s_info"].get("name") in ("argocd-cm", "argocd-oidc-keycloak")]
    cm_reg, sec_reg = regs if len(regs) == 2 else ("_cm", "_sec")
    def sso_ok(ref, value=b"s3cret", label="argocd", there=True):
        cm = {"resources": [{"data": {"oidc.config": f"name: Keycloak\nissuer: https://auth\nclientID: argocd\n"
                                                    f"clientSecret: {ref}\n"}}]}
        sec = {"resources": [{"data": {"clientSecret": base64.b64encode(value).decode()},
                              "metadata": {"labels": {"app.kubernetes.io/part-of": label}}}] if there else []}
        return condition(a["that"], **{cm_reg: cm, sec_reg: sec})
    check("as this run writes it: configured; production's old reference (argocd-secret), the Secret gone or empty, "
          "unlabelled: not",
          [sso_ok("$argocd-oidc-keycloak:clientSecret"), sso_ok("$argocd-secret:oidc.keycloak.clientSecret"),
           sso_ok("$argocd-oidc-keycloak:clientSecret", there=False), sso_ok("$argocd-oidc-keycloak:clientSecret", b""),
           sso_ok("$argocd-oidc-keycloak:clientSecret", label="")], [True, False, False, False, False])
    check("checked only with Keycloak on, not in a preview (which wrote no Secret)",
          [condition(sso[0].get("when", True), keycloak_enabled=k, ansible_check_mode=c)
           for k, c in ((True, False), (False, False), (True, True))], [True, False, False])
# before the Secret is written and the install runs: the client secret this run writes is set, and is the one Argo CD
# signs in with now while argocd-secret holds it (production's earlier shape) - empty or another, single sign-on broke,
# found only after the Helm upgrade had switched to it (review 7)
pre = [t for t in tasks if "ansible.builtin.assert" in t and "argocd_keycloak_client_secret" in str(t["ansible.builtin.assert"])]
now = next((t for t in tasks if (t.get("kubernetes.core.k8s_info") or {}).get("name") == "argocd-secret"), None)
check("the client secret checked before its Secret is written and before the install, argocd-secret read before",
      len(pre) == 1 and now is not None and bool(writes) and tasks.index(now) < tasks.index(pre[0]) < tasks.index(writes[0])
      < tasks.index(helm), True)
check("argocd-secret's read no_log (it holds the secrets)", (now or {}).get("no_log"), True)
if pre and now:
    def pre_ok(configured, in_use=None, there=True):
        sec = {"resources": [{"data": dict({"admin.password": "eA=="}, **({} if in_use is None else
                                           {"oidc.keycloak.clientSecret": base64.b64encode(in_use).decode()}))}]}
        return condition(pre[0]["ansible.builtin.assert"]["that"], argocd_keycloak_client_secret=configured,
                         **{now["register"]: sec if there else {"resources": []}})
    check("set and the one in use: on; set, none in use (moved already, or a new install): on; empty, or another than "
          "the one in use: refused",
          [pre_ok("s3cret", b"s3cret"), pre_ok("s3cret"), pre_ok("s3cret", there=False), pre_ok(""),
           pre_ok("other", b"s3cret")], [True, True, True, False, False])
    check("checked with Keycloak on, in a preview too (a read: the preview refuses what the run would)",
          [condition(pre[0].get("when", True), keycloak_enabled=k, ansible_check_mode=c)
           for k, c in ((True, False), (True, True), (False, False))], [True, True, False])
# the Vagrant copy runs them: step 31 and 33 rehearsed with the checks production's run makes
inv = yaml.safe_load(open("deploy/ansible/inventory/vagrant.yml"))
flat_vars = {k: v for g in inv.values() for k, v in ((g or {}).get("vars") or {}).items()}
check("the Vagrant copy checks single sign-on as production does (argocd_keycloak_enabled not off)",
      flat_vars.get("argocd_keycloak_enabled", True), True)
print("argocd-oidc-secret: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
