#!/bin/bash
# setup-vault-pi.yml's first init, its shell and templates as the playbook holds them (the key directory moved to a
# temp one, vault a stub): the init's JSON lands on the Pi by the same command, root-only, whole (written aside, then
# moved) - an init that fails leaves no keys file; the unseal-keys and root-token files are made from that file.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import ansible, yaml' || { echo "vault-init: no python3 with ansible and yaml"; exit 2; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/vault" <<'STUB'
#!/bin/sh
# operator init: the keys (VAULT_FAIL=1 cuts it short); secrets/auth list: MOUNTED's paths; enable: logged to CALLS,
# failing with ENABLE_FAIL=1 (a standby, a sealed Vault)
case "$1 $2" in
  "operator init")
    [ "${3:-}" = -status ] && exit "${STATUS_RC:-2}"  # 2: not initialised
    [ "${VAULT_FAIL:-}" = 1 ] && { printf '{"unseal_keys_b64": ["k1",'; echo "Error: connection reset" >&2; exit 2; }
    echo '{"unseal_keys_b64": ["k1", "k2", "k3"], "root_token": "hvs.root"}' ;;
  "secrets list" | "auth list")
    printf '{'; for m in ${MOUNTED:-}; do printf '"%s": {"type": "x"}, ' "$m"; done; printf '"cubbyhole/": {}}\n' ;;
  "secrets enable" | "auth enable")
    echo "$*" >> "$CALLS"; [ "${ENABLE_FAIL:-}" != 1 ] || { echo "Error: 503 standby" >&2; exit 2; } ;;
esac
STUB
chmod +x "$W/bin/vault"
W=$W "$PY" - <<'PY'
import base64, json, os, stat, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render, condition
W = os.environ["W"]
tasks = {t.get("name"): t for p in yaml.safe_load(open("deploy/ansible/playbooks/setup-vault-pi.yml"))
         for t in p.get("tasks") or [] for t in [t] + (t.get("block") or [])}
fails = 0
def check(name, ok):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}")
init = tasks["Initialise Vault - its keys written on the Pi as it returns them"]
script = render(init["ansible.builtin.shell"],
                vault_unseal_shares=3, vault_unseal_threshold=2).replace("/etc/vault-unseal", os.path.join(W, "vu"))
check("the init skipped once its keys file exists (creates)", init["args"]["creates"] == "/etc/vault-unseal/init.json")
env = dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"])
aside = lambda: [f for f in os.listdir(os.path.join(W, "vu")) if f.startswith("init.json.")]
r = subprocess.run(["bash", "-c", script], env=dict(env, VAULT_FAIL="1"), capture_output=True, text=True)
check("an init that fails, Vault not initialised: no keys file, nothing left aside (no shares exist)",
      r.returncode != 0 and not os.path.exists(os.path.join(W, "vu", "init.json")) and aside() == [])
r = subprocess.run(["bash", "-c", script], env=dict(env, VAULT_FAIL="1", STATUS_RC="0"), capture_output=True, text=True)
check("an init that fails with Vault initialised: its output kept aside for a look (shares may be in it)",
      r.returncode != 0 and "look by hand" in r.stdout + r.stderr and len(aside()) == 1)
for f in aside():
    os.remove(os.path.join(W, "vu", f))
r = subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True)
path = os.path.join(W, "vu", "init.json")
check("the init's keys on the Pi, whole", r.returncode == 0 and json.load(open(path))["root_token"] == "hvs.root")
check("root-only: the file 0600, its directory 0700",
      stat.S_IMODE(os.stat(path).st_mode) == 0o600 and stat.S_IMODE(os.stat(os.path.dirname(path)).st_mode) == 0o700)
# the unseal-keys and root-token files made from it on the Pi - the shares never through the controller (a copy with
# content: is written to a file on the controller first) - root's alone, read-only
book = yaml.safe_load(open("deploy/ansible/playbooks/setup-vault-pi.yml"))
alltasks = [t for p in book for t in p.get("tasks") or [] for t in [t] + (t.get("block") or [])]
through = [t.get("name") for t in alltasks if ("ansible.builtin.copy" in t or "ansible.builtin.slurp" in t)
           and any(x in yaml.safe_dump(t) for x in ("init.json", "unseal_keys_b64", "root_token"))]
check("the first init's keys never read to the controller or written from it", through == [])
persist = next((t for t in alltasks if "unseal-keys" in str(t.get("ansible.builtin.shell", ""))
                and "init.json" in str(t.get("ansible.builtin.shell", ""))), None)
check("unseal-keys and root-token written on the Pi from its keys file", persist is not None)
if persist:
    sh = persist["ansible.builtin.shell"]
    r = subprocess.run(["bash", "-c", (sh if isinstance(sh, str) else sh["cmd"]).replace("/etc/vault-unseal",
                        os.path.join(W, "vu"))], env=env, capture_output=True, text=True)
    k, t = os.path.join(W, "vu", "unseal-keys"), os.path.join(W, "vu", "root-token")
    check("unseal-keys made from it, one share a line", r.returncode == 0 and open(k).read() == "k1\nk2\nk3\n")
    check("root-token made from it", open(t).read() == "hvs.root")
    check("both root-only, read-only (0400)", all(stat.S_IMODE(os.stat(f).st_mode) == 0o400 for f in (k, t)))
    os.remove(k); os.remove(t)
# pi2's copy of the shares: on a shell's stdin (pipelined, in memory), written there root-only - never a file on the
# controller
dist = next((t for t in alltasks if t.get("name", "").startswith("The unseal keys on pi2")), None)
check("pi2's shares given on stdin", dist is not None and "_unseal_keys" in str((dist.get("args") or {}).get("stdin", "")))
# pi2's play reads them itself, from pi1 (a slurp delegated there): a run limited to pi2 skipped pi1's plays, and a
# read of hostvars['pi1'] failed it
pi2_play = next((p for p in book if dist in (p.get("tasks") or [])), {})
own = next((t for t in pi2_play.get("tasks") or [] if "ansible.builtin.slurp" in t
            and t["ansible.builtin.slurp"].get("src") == "/etc/vault-unseal/unseal-keys"), None)
check("pi2's play reads the shares from pi1 itself, out of the log; no read of pi1's results",
      own is not None and own.get("delegate_to") == "pi1" and own.get("no_log") is True
      and own.get("register") in str((dist.get("args") or {}).get("stdin", ""))
      and pi2_play["tasks"].index(own) < pi2_play["tasks"].index(dist)
      and "hostvars['pi1']" not in yaml.safe_dump(pi2_play, width=10000))
# root's alone, read-only - also where its content matched already (the shares not sent)
mode = next((t for t in pi2_play.get("tasks") or [] if (t.get("ansible.builtin.file") or {}).get("path")
             == "/etc/vault-unseal/unseal-keys"), None)
check("pi2's unseal-keys root's alone, read-only, sent or not",
      mode is not None and (mode["ansible.builtin.file"].get("owner"), mode["ansible.builtin.file"].get("group"),
                            str(mode["ansible.builtin.file"].get("mode"))) == ("root", "root", "0400"))
if mode:
    probe_reg = next((t.get("register") for t in pi2_play["tasks"] if t.get("name", "").startswith("Hash of")), "_x")
    check("enforced on a run whatever was found, on a preview where the file was found (a first install's has none)",
          [condition(mode.get("when", True), ansible_check_mode=cm, **{probe_reg: {"rc": rc}})
           for cm, rc in ((False, 0), (False, 1), (True, 0), (True, 1))] == [True, True, True, False])
if dist:
    sh = dist["ansible.builtin.shell"]
    r = subprocess.run(["bash", "-c", (sh if isinstance(sh, str) else sh["cmd"]).replace("/etc/vault-unseal",
                        os.path.join(W, "vu"))], input="k1\nk2\nk3\n", env=env, capture_output=True, text=True)
    k = os.path.join(W, "vu", "unseal-keys")
    check("pi2's unseal-keys as pi1's, 0400", r.returncode == 0 and open(k).read() == "k1\nk2\nk3\n"
          and stat.S_IMODE(os.stat(k).st_mode) == 0o400)
    check("its stdin as given (no newline added)", (dist.get("args") or {}).get("stdin_add_newline") is False)
    # stdin is in memory only while modules are piped (pipelining): without it Ansible writes the module, its stdin
    # included, to a temp file on the controller first - asserted in the play, as the run's own config has it (a
    # config file, ANSIBLE_* or a host var may turn it off)
    play = next(p for p in book if dist in (p.get("tasks") or []))
    gate = next((t for t in play["tasks"][:play["tasks"].index(dist)] if "ansible.builtin.assert" in t
                 and "pipelining" in str(t["ansible.builtin.assert"].get("that"))), None)
    check("pipelining asserted in pi2's play before the shares go", gate is not None)
    if gate:
        cfg = os.path.abspath("deploy/ansible/ansible.cfg")
        def piped(env=None, **hv):
            # the plugin loader as the CLI starts it (a lookup by its full name needs the collection loader)
            code = ("import json, sys; sys.path.insert(0, 'tests/ansible/unit'); from templar import condition; "
                    "from ansible.plugins.loader import init_plugin_loader; init_plugin_loader(); "
                    "print(condition(json.loads(sys.argv[1]), **json.loads(sys.argv[2])))")
            # the task's own vars, as Ansible gives the assert them
            r = subprocess.run([sys.executable, "-c", code, json.dumps(gate["ansible.builtin.assert"]["that"]),
                                json.dumps({**(gate.get("vars") or {}), **hv})], capture_output=True, text=True,
                               env={"HOME": os.environ["HOME"], "PATH": os.environ["PATH"], "ANSIBLE_CONFIG": cfg,
                                    "PYTHONDONTWRITEBYTECODE": "1", **(env or {})})
            return r.stdout.strip() or r.stderr.strip()[-200:]
        got = [piped(), piped({"ANSIBLE_PIPELINING": "False"}), piped(ansible_pipelining=False),
               piped(ansible_ssh_pipelining=False)]
        check("pipelining: on as ansible.cfg has it; off by ANSIBLE_PIPELINING, ansible_pipelining or "
              f"ansible_ssh_pipelining (got {got})", got == ["True", "False", "False", "False"])
        # Ansible pipelines only with neither kept remote files nor a become plugin that cannot (su) - each turns it off
        # (ConnectionBase.is_pipelining_enabled)
        got = [piped({"ANSIBLE_KEEP_REMOTE_FILES": "True"}), piped(ansible_become_method="su"),
               piped({"ANSIBLE_BECOME_METHOD": "su"}), piped(ansible_become_method="sudo")]
        check(f"kept remote files or become by su: refused; sudo passes (got {got})",
              got == ["False", "False", "False", "True"])
        check("no play or task of it sets its own become_method (the assert reads the run's, not a keyword's)",
              not any("become_method" in x for x in [play, *play["tasks"]]))
    # the shares go to the host pi2 is - its host key checked: one answering in its place (its file absent) would get
    # them all; asserted as the run has it, ssh's own arguments included
    keys = next((t for t in play["tasks"][:play["tasks"].index(dist)] if "ansible.builtin.assert" in t
                 and "host_key_checking" in str(t["ansible.builtin.assert"].get("that"))), None)
    check("host key checking asserted in pi2's play before the shares go", keys is not None)
    if keys and gate:
        gate = keys
        got = [piped(), piped({"ANSIBLE_HOST_KEY_CHECKING": "False"}), piped(ansible_host_key_checking=False),
               piped(ansible_ssh_host_key_checking=False),
               piped(ansible_ssh_common_args="-o StrictHostKeyChecking=no"),
               piped({"ANSIBLE_SSH_ARGS": "-C -o ControlMaster=auto -o UserKnownHostsFile=/dev/null"}),
               piped(ansible_ssh_extra_args="-o StrictHostKeyChecking=accept-new"),
               piped(ansible_ssh_common_args="-o StrictHostKeyChecking\tno"),
               piped(ansible_ssh_common_args="-o StrictHostKeyChecking='no'"),
               piped(ansible_ssh_extra_args="-F/home/x/ssh_config")]
        check(f"host keys: checked as ansible.cfg has it; off by the environment, a host var or ssh's arguments - a tab, "
              f"quotes, -F with no space among them (got {got})", got == ["True"] + ["False"] * 9)
        got = piped(ansible_ssh_extra_args="-f -N")
        check(f"ssh's -f (its background flag) no other config (got {got})", got == "True")
        # the Vagrant copy's VMs, rebuilt each run with new keys, check none - said by its inventory alone (the
        # assert failed its build: my defect, 2026-10-08)
        got = [piped(ansible_ssh_common_args="-o StrictHostKeyChecking=no", host_keys_unchecked_rebuilt_vms=True,
                     hostvars={"pi2": {"ansible_host": a}}) for a in ("192.168.56.21", "192.168.11.6")]
        check(f"the Vagrant copy's rebuilt VMs, said by its inventory: passes for a pi2 on the Vagrant network - not for "
              f"one elsewhere (a production inventory saying it) (got {got})", got == ["True", "False"])
    ino = os.stat(k).st_ino
    r = subprocess.run(["bash", "-c", (sh if isinstance(sh, str) else sh["cmd"]).replace("/etc/vault-unseal",
                        os.path.join(W, "vu"))], input="k1\nk2\nk3\n", env=env, capture_output=True, text=True)
    check("the same shares again: not rewritten", r.returncode == 0 and "written" not in r.stdout
          and os.stat(k).st_ino == ino)
    # sent only when pi2's differ: its file's hash read first (a host that is not pi2 gets nothing it lacks)
    probe = next((t for t in alltasks if t.get("name", "").startswith("Hash of the unseal keys pi2 holds")), None)
    check("pi2's keys read by their hash before any are sent",
          probe is not None and alltasks.index(probe) < alltasks.index(dist) and probe.get("check_mode") is False)
    if probe:
        psh = probe["ansible.builtin.shell"] if "ansible.builtin.shell" in probe else probe["ansible.builtin.command"]
        psh = (psh if isinstance(psh, str) else psh["cmd"]).replace("/etc/vault-unseal", os.path.join(W, "vu"))
        reg = probe["register"]
        shares = {"content": base64.b64encode(b"k1\nk2\nk3\n").decode()}
        def sent():
            r = subprocess.run(["bash", "-c", psh], env=env, capture_output=True, text=True)
            res = {"rc": r.returncode, "stdout": r.stdout, "stderr": r.stderr}
            return (condition(probe.get("failed_when", f"{reg}.rc != 0"), **{reg: res}),
                    condition(dist.get("when", True), **{reg: res, own["register"] if own else "_unseal_keys": shares}))
        check("pi2 holding the same shares: nothing sent", sent() == (False, False))
        os.remove(k)
        open(k, "w").write("k1\nk2\nOLD\n")
        check("pi2 holding others: sent", sent() == (False, True))
        os.remove(k)
        check("pi2 holding none: sent", sent() == (False, True))
        # its file unreadable another way (a directory in its place - EISDIR; EACCES alike): the probe fails, nothing
        # sent - only a missing file is a host holding none
        os.mkdir(k)
        got = sent()
        os.rmdir(k)
        check(f"pi2's file not readable for another reason (a directory there): the probe fails (got {got})",
              got[0] is True)
    else:
        os.remove(k)
# an ssh retry overlapping a first invocation still running: each writes its own file aside - the other's output (the
# only copy of the shares) never truncated
os.remove(path)
other = os.path.join(W, "vu", "init.json.part")
open(other, "w").write("THE OTHER RUN'S SHARES")
r = subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True)
check("an overlapping init: the other's output untouched",
      os.path.exists(other) and open(other).read() == "THE OTHER RUN'S SHARES")
os.path.exists(other) and os.remove(other)
os.path.exists(path) and os.remove(path)
r = subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True)
# a run cut short between the init and its move (Vault initialised - the init is not run again): its output promoted,
# never left stranded aside; one that is not whole refuses
promote = tasks["A first init's output left aside promoted (a run cut short before its move)"]
pscript = promote["ansible.builtin.shell"].replace("/etc/vault-unseal", os.path.join(W, "vu"))
os.remove(path)
open(os.path.join(W, "vu", "init.json.ab12Cd"), "w").write('{"unseal_keys_b64": ["k1"], "root_token": "hvs.root"}')
r = subprocess.run(["bash", "-c", pscript], env=env, capture_output=True, text=True)
check("an init's output left aside: promoted", r.returncode == 0 and os.path.exists(path)
      and not os.path.exists(os.path.join(W, "vu", "init.json.ab12Cd")))
os.remove(path)
open(os.path.join(W, "vu", "init.json.ef34Gh"), "w").write('{"unseal_keys_b64": ["k1",')
r = subprocess.run(["bash", "-c", pscript], env=env, capture_output=True, text=True)
check("one cut short in its writing: refused, kept for a look", r.returncode != 0 and "not whole" in r.stdout + r.stderr
      and os.path.exists(os.path.join(W, "vu", "init.json.ef34Gh")))
os.remove(os.path.join(W, "vu", "init.json.ef34Gh"))
# an empty file aside beside a whole keys file: a run cut short between its mktemp and an init that never initialised
# Vault (an init that did would have made this run's fail) - removed, the run goes on (it stopped every good run after
# for a look by hand); with no keys file it may be shares lost - refused, kept
open(path, "w").write('{"unseal_keys_b64": ["k1"], "root_token": "hvs.root"}')
open(os.path.join(W, "vu", "init.json.Ij56Kl"), "w").close()
r = subprocess.run(["bash", "-c", pscript], env=env, capture_output=True, text=True)
check("an empty one beside a whole keys file: removed, the run goes on", r.returncode == 0
      and not os.path.exists(os.path.join(W, "vu", "init.json.Ij56Kl")) and os.path.exists(path))
os.remove(path)
open(os.path.join(W, "vu", "init.json.Ij56Kl"), "w").close()
r = subprocess.run(["bash", "-c", pscript], env=env, capture_output=True, text=True)
check("an empty one, no keys file: refused, kept for a look", r.returncode != 0
      and os.path.exists(os.path.join(W, "vu", "init.json.Ij56Kl")))
os.remove(os.path.join(W, "vu", "init.json.Ij56Kl"))
# the bootstrap's engines: enabled when missing, left when there, a failure a failure (it read "already-enabled", the
# keys file was removed and KV v2 never enabled)
open(os.path.join(W, "vu", "root-token"), "w").write("hvs.root")
calls = os.path.join(W, "calls")
for name, path_, enable in (("Enable KV v2", "secret/", "secrets enable -path=secret kv-v2"),
                            ("Enable Kubernetes auth", "kubernetes/", "auth enable kubernetes")):
    sh = tasks[name]["ansible.builtin.shell"].replace("/etc/vault-unseal", os.path.join(W, "vu"))
    for mounted, fail, want_rc, want_call in (("", "", 0, enable), (path_, "", 0, ""), ("", "1", 1, enable)):
        open(calls, "w").close()
        r = subprocess.run(["bash", "-c", sh], env=dict(env, MOUNTED=mounted, ENABLE_FAIL=fail, CALLS=calls),
                           capture_output=True, text=True)
        got = (min(r.returncode, 1), open(calls).read().strip())
        check(f"{name}: " + ("there already - left" if mounted else "failing - fails" if fail else "missing - enabled"),
              got == (want_rc, want_call))
# the bootstrap waits for this Vault to be the active one (an unsealed standby refuses writes), and the shares are on
# disk before the init's file - their only other copy - goes
block = next(t for p in yaml.safe_load(open("deploy/ansible/playbooks/setup-vault-pi.yml"))
             for t in p.get("tasks") or [] if t.get("name", "").startswith("Bootstrap KV + ESO + k8s-auth"))["block"]
until = block[0].get("until", "false")
check("the bootstrap first waits for sys/health to say active (200) - not a standby (429), not sealed (503)",
      "sys/health" in str(block[0])
      and [condition(until, **{block[0]["register"]: {"status": c}}) for c in (200, 429, 503)] == [True, False, False])
names = [t["name"] for t in block]
removal = names.index("The first init done - its keys file removed (the shares are in unseal-keys and root-token)")
check("the shares synced to disk before the keys file goes", "ansible.builtin.command" in block[removal - 1]
      and block[removal - 1]["ansible.builtin.command"].startswith("sync "))
print("vault-init: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
