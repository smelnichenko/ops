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
# the client secret judged before anything is written - the namespace, Forgejo's token and Argo CD's repo credentials
# among them (made, rotated, a token deleted, then single sign-on refused); only reads and checks before it
names = [t.get("name") for t in tasks]
judge = names.index("The client secret this run writes - set, and the one in use") \
    if "The client secret this run writes - set, and the one in use" in names else len(names)
READS = ("k8s_info", "assert", "fail", "set_fact", "debug", "command", "shell")
writes = [t.get("name") for t in tasks[:judge]
          if not any(k.split(".")[-1] in READS for k in t)
          and not any(k.split(".")[-1] == "uri" and str(t[k].get("method", "GET")).upper() == "GET" for k in t)
          or (any(k.split(".")[-1] in ("command", "shell") for k in t) and t.get("changed_when") is not False)]
check("the client secret judged before anything is written (only reads and checks before it)", writes, [])
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
# found only after the Helm upgrade had switched to it
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
# the Vagrant copy runs them: step 31 and 33 rehearsed with the checks production's run makes - its value as Ansible
# gives it to every host setup-argocd runs on (a host var or a child group's turned it off unseen)
from ansible.inventory.manager import InventoryManager  # noqa: E402
from ansible.parsing.dataloader import DataLoader  # noqa: E402
from ansible.vars.manager import VariableManager  # noqa: E402
loader = DataLoader()
im = InventoryManager(loader=loader, sources=["deploy/ansible/inventory/vagrant.yml"])
vm = VariableManager(loader=loader, inventory=im)
hosts = im.get_hosts(play["hosts"])
check("the Vagrant copy checks single sign-on as production does (argocd_keycloak_enabled not off on its hosts)",
      (bool(hosts), [vm.get_vars(host=h, include_hostvars=False).get("argocd_keycloak_enabled", True) for h in hosts]),
      (True, [True] * len(hosts)))
# and Keycloak takes it: the secret this run wrote given to Keycloak's token endpoint for Argo CD's client (its clientID
# as the OIDC config names it) with no such user - a right secret answered about the user or the grant, a wrong one
# invalid_client; refused then. A value merely there passed a secret Keycloak refuses (single sign-on broken, unseen)
names = [t.get("name") for t in tasks]
probe = next((t for t in tasks if t.get("name") == "Keycloak takes Argo CD's client secret"), None)
taken = next((t for t in tasks if t.get("name") == "Keycloak takes Argo CD's client secret - not refused"), None)
cfg_client = re.search(r"clientID: ([\w-]+)", str(tasks))
u = (probe or {}).get("ansible.builtin.uri") or {}
check("Keycloak asked for Argo CD's client with the secret this run wrote, after the install; no_log, no redirect",
      (probe is not None and names.index(probe["name"]) > names.index("Single sign-on configured - the OIDC config's client "
                                                                      "secret where it points"),
       str(u.get("url", "")).endswith("/realms/schnappy/protocol/openid-connect/token"),
       (u.get("body") or {}).get("client_id") == (cfg_client.group(1) if cfg_client else None),
       "argocd_keycloak_client_secret" in str((u.get("body") or {}).get("client_secret")),
       (probe or {}).get("no_log"), u.get("follow_redirects")),
      (True, True, True, True, True, "none"))
reg = (probe or {}).get("register", "_x")
that = ((taken or {}).get("ansible.builtin.assert") or {}).get("that") or ["false"]
judged = lambda err: all(condition(c, **{reg: {"status": 401, "json": {"error": err}}}) for c in that)  # noqa: E731
check("its answer judged: invalid_client refused; invalid_grant, unauthorized_client taken",
      [judged(e) for e in ("invalid_client", "invalid_grant", "unauthorized_client")], [False, True, True])
print("argocd-oidc-secret: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
