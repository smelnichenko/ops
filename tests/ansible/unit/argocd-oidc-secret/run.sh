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
from templar import condition, render  # noqa: E402
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
# (the post-install verification: the pre-check before it names the Secret too)
sso = [t for t in tasks[tasks.index(helm):] if "ansible.builtin.assert" in t
       and "argocd-oidc-keycloak" in str(t["ansible.builtin.assert"])]
check("single sign-on verified after the install", len(sso) == 1 and bool(sso) and tasks.index(sso[0]) > tasks.index(helm),
      True)
if sso:
    a = sso[0]["ansible.builtin.assert"]
    regs = [t.get("register") for t in tasks[tasks.index(helm):] if "kubernetes.core.k8s_info" in t
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
# and argocd-oidc-keycloak, where step 31 moved it: at steps 33 and 34 argocd-secret holds none - a stale secret in
# ops/.env passed the check and overwrote the one in use
oidc_now = next((t for t in tasks[:tasks.index(helm)] if (t.get("kubernetes.core.k8s_info") or {}).get("name")
                 == "argocd-oidc-keycloak"), None)
check("argocd-oidc-keycloak read before the check, no_log",
      (oidc_now is not None and pre != [] and tasks.index(oidc_now) < tasks.index(pre[0]), (oidc_now or {}).get("no_log")),
      (True, True))
if pre and now:
    def pre_ok(configured, in_use=None, there=True, oidc=None):
        sec = {"resources": [{"data": dict({"admin.password": "eA=="}, **({} if in_use is None else
                                           {"oidc.keycloak.clientSecret": base64.b64encode(in_use).decode()}))}]}
        osec = {"resources": [] if oidc is None else [{"data": {"clientSecret": base64.b64encode(oidc).decode()}}]}
        return condition(pre[0]["ansible.builtin.assert"]["that"], argocd_keycloak_client_secret=configured,
                         **{now["register"]: sec if there else {"resources": []},
                            (oidc_now or {}).get("register", "_none"): osec})
    check("argocd-oidc-keycloak holding the one this run writes: on; another: refused",
          [pre_ok("s3cret", oidc=b"s3cret"), pre_ok("stale", oidc=b"s3cret")], [True, False])
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
# and Keycloak takes it - before anything is written: the secret this run writes given to Keycloak's token endpoint for
# Argo CD's client (its clientID as the OIDC config names it) with no such user, and a secret it cannot take given the
# same way: the two answers must differ, the right one about the user or the grant (invalid_grant; unauthorized_client
# where direct grants are off - not "Invalid client"). Asked from the first Pi, its name checked to be this
# inventory's VIP there (the copy's kubeadm node resolves auth.pmon.dev to production's; production's Pis and ten
# resolve it to their VIP - read 2026-10-08): never another Keycloak asked
names = [t.get("name") for t in tasks]
first_write = tasks.index(writes[0]) if writes else 0
resolve = next((t for t in tasks if "getent ahostsv4" in str(t.get("ansible.builtin.command", ""))), None)
named = next((t for t in tasks if t.get("name") == "Keycloak's name there is this inventory's VIP"), None)
probes = [t for t in tasks if "/protocol/openid-connect/token" in str((t.get("ansible.builtin.uri") or {}).get("url"))]
taken = next((t for t in tasks if t.get("name") == "Keycloak takes the client secret this run writes"), None)
cfg_client = re.search(r"clientID: ([\w-]+)", str(tasks))
pi = "{{ groups['pis'] | first }}"
check("its name read on the first Pi, then the two probes from it, then the judgement - all before the first write",
      (resolve is not None and named is not None and len(probes) == 2 and taken is not None
       and tasks.index(resolve) < tasks.index(named) < tasks.index(probes[0]) < tasks.index(probes[1])
       < tasks.index(taken) < first_write,
       [t.get("delegate_to") for t in [resolve or {}] + probes]), (True, [pi, pi, pi]))
if named:
    rreg = (resolve or {}).get("register", "_r")
    vip_ok = lambda line, vip: condition(named["ansible.builtin.assert"]["that"],  # noqa: E731
                                         **{rreg: {"stdout_lines": [line] if line else [], "stdout": line}},
                                         keepalived_vip=vip, keycloak_host="auth.pmon.dev")
    check("its name there this inventory's VIP: on; production's from the copy, none: refused",
          [vip_ok("192.168.56.50   STREAM auth.pmon.dev", "192.168.56.50"),
           vip_ok("192.168.11.5    STREAM auth.pmon.dev", "192.168.56.50"), vip_ok("", "192.168.56.50")],
          [True, False, False])
bodies = [(t["ansible.builtin.uri"].get("body") or {}) for t in probes]
check("both probes for Argo CD's client, no such user; one with the secret this run writes, the other not; no_log, no "
      "redirect, read in a preview too",
      ([b.get("client_id") == (cfg_client.group(1) if cfg_client else None) for b in bodies],
       sorted("argocd_keycloak_client_secret" in str(b.get("client_secret")) for b in bodies),
       [(t.get("no_log"), t["ansible.builtin.uri"].get("follow_redirects"), t.get("check_mode")) for t in probes]),
      ([True, True], [False, True], [(True, "none", False)] * 2))
if taken and len(probes) == 2:
    right = next(t for t in probes if "argocd_keycloak_client_secret" in str(t["ansible.builtin.uri"]["body"]))
    wrong = next(t for t in probes if t is not right)
    summary = next((t for t in tasks if "ansible.builtin.set_fact" in t and right["register"] in str(t)), None)
    def judged(w, r):
        ans = lambda status, err, desc: {"status": status, "json": {"error": err, "error_description": desc}} \
            if err is not None else {"status": status}  # noqa: E731
        regs = {wrong["register"]: ans(*w), right["register"]: ans(*r)}
        facts = {k: {kk: render(vv, **regs) for kk, vv in v.items()} if isinstance(v, dict) else render(v, **regs)
                 for k, v in (summary or {}).get("ansible.builtin.set_fact", {}).items()}
        return condition(taken["ansible.builtin.assert"]["that"], **regs, **facts)
    WRONG = (401, "unauthorized_client", "Invalid client or Invalid client credentials")
    check("judged against the wrong secret's answer: direct grants off (400 unauthorized_client), a user refused "
          "(invalid_grant): taken; the same answer as the wrong one, invalid_client, 'Invalid client', not JSON, "
          "invalid_request: refused",
          [judged(WRONG, (400, "unauthorized_client", "Client not allowed for direct access grants")),
           judged((401, "invalid_client", "Invalid client credentials"), (401, "invalid_grant", "Invalid user credentials")),
           judged(WRONG, WRONG), judged(WRONG, (401, "invalid_client", "Invalid client credentials")),
           judged((400, "x", "y"), (401, "unauthorized_client", "Invalid client or Invalid client credentials")),
           judged(WRONG, (401, None, None)), judged(WRONG, (400, "invalid_request", "Missing parameter"))],
          [True, True, False, False, False, False, False])
    check("the answers said (status, error), the secret not", ("_sso_answers" in str(taken["ansible.builtin.assert"]
                                                               .get("fail_msg")), summary is not None and
                                                               summary.get("no_log") is not True), (True, True))
check("no probe after the install any more", [n for n in names[tasks.index(helm):] if "Keycloak takes" in str(n)], [])
print("argocd-oidc-secret: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
