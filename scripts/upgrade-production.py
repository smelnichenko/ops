#!/usr/bin/env python3
"""upgrade-production.py - the upgrade steps on production: one step at a time, in order, each phase only after the
phases it needs. A ledger on ten (ConfigMap kube-system/upgrade-ledger, one line per event) is checked and written by
every phase; the Taskfile's deploy:upgrade:* tasks call this. The procedure: docs/plans/100-cluster-upgrade.md,
"Production, step by step".

Per step N (tests/ansible/upgrade/steps/N.txt), in this order:
  begin      every earlier step done; ten's inventory as the done steps leave it and Argo settled on main   -> begun
  backup     each of the step's wave0 stores into the Pi store (upgrade-backup.yml)                -> backup <store>
  preview    the step's playbook lines in check mode, with diffs                                        -> previewed
  merge      each branch line in the file's order: the branch's own change exactly as the full run proved it, the
             state between two merges one the full run proved (upgrade-merge-order.py), merged and pushed
             (upgrade-merge-step.sh); then Argo settled on the pushed commits        -> merged <repo>, settled <repo>
  playbooks  the step's playbook lines against production                                               -> playbooks
  defaults   the step's default lines (scripts/upgrade-defaults.py) committed to ops main and pushed: a playbook
             run from now on installs what production runs                                             -> defaults
  done       ten's inventory as step N leaves it and Argo settled (after a step that changes cert-manager - its
             cert-renew line - first a throwaway certificate issued through production's ACME solver: acme-check.yml;
             after one that changes CNPG, PostgreSQL or their store - barman-check - a fresh base backup:
             postgres-base-backup.yml).
             The first green call records checked; a call at
             least the step's soak later (its soak line; else 60 minutes after a wave0 step, 15 otherwise) that is
             green again with no container restarted since records done. A red call after checked records
             check-failed: the soak starts again from the next green call.
A phase that fails records nothing. Step 02 (the Istio chart repository) went to production on 2026-10-03, before
the ledger: init records it done.

The proof (record-proof, run by test:upgrade:full after each green step; proof-start at the run's start): each repo's
branch SHA and own change (its changed lines and files against the repo's ref at the step before), the ops commit the
run ran from - refused if deploy/, scripts/, tests/ or Taskfile.yml differ from it. Production's merge wants the same
own change and every step up to N proven by one run; its phases want deploy/ and the step file as that run had them.

Usage: scripts/upgrade-production.py init | status
       scripts/upgrade-production.py begin|preview|playbooks|defaults|done <step>
       scripts/upgrade-production.py backup <step> <store>
       scripts/upgrade-production.py merge <step> <infra|platform>
       scripts/upgrade-production.py check <step>              (read-only: as `done` checks, nothing recorded)
       scripts/upgrade-production.py proof-start
       scripts/upgrade-production.py record-proof <step> <infra sha> <platform sha>
"""
import datetime
import hashlib
import importlib.machinery
import importlib.util
import json
import os
import re
import shlex
import subprocess
import sys

OPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEN = "sm@192.168.11.2"
PIS = ("sm@192.168.11.4", "sm@192.168.11.6")
LEDGER_NAMESPACE, LEDGER_NAME = "kube-system", "upgrade-ledger"
REPOS = ("infra", "platform")
URLS = {"infra": "https://git.pmon.dev/schnappy/infra.git", "platform": "https://git.pmon.dev/schnappy/platform.git"}
# production's test environment: not in the Vagrant copy, moved apart from production by its own steps - its images
# are listed, not compared
TEST_NAMESPACES = "schnappy-test"
SOAK_MINUTES, SOAK_MINUTES_WAVE0 = 15, 60
# preview environments come and go (an Argo app per pull request): never part of the app set a step must keep
PREVIEW_APPS = "^pr-[0-9]+-"
# on ten, sm's: each done step's restart counts, so a pod restarting in two steps running fails the second
RESTART_HISTORY = "$HOME/.upgrade-restart-history.json"
PROVEN = os.path.join(OPS, ".upgrade", "proven")
PROVEN_PATHS = ("deploy", "scripts", "tests", "Taskfile.yml")
BEFORE_LEDGER = "02-istio-chart-repo"


def _load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, path)
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, loader))
    loader.exec_module(module)
    return module


inv = _load("upgrade_expected_inventory", os.path.join(OPS, "scripts", "upgrade-expected-inventory.py"))
dflt = _load("upgrade_defaults", os.path.join(OPS, "scripts", "upgrade-defaults.py"))


def step_names():
    return sorted(f[:-4] for f in os.listdir(inv.STEPS) if f.endswith(".txt"))


def step_info(name):
    playbooks, wave0, soak, out_of_sync, flags = [], [], [], [], set()
    inv.parse(os.path.join(inv.STEPS, name + ".txt"), playbooks=playbooks, wave0=wave0, soak=soak,
              out_of_sync=out_of_sync, flags=flags)
    return {"branches": inv.branch_order(name), "playbooks": playbooks, "wave0": wave0, "out_of_sync": out_of_sync,
            "soak": soak[-1] if soak else SOAK_MINUTES_WAVE0 if wave0 else SOAK_MINUTES,
            "defaults": bool(dflt.default_lines(name)), "acme": "cert-renew" in flags,
            "base_backup": "barman-check" in flags}


# ---- the ledger: rules (pure) ---------------------------------------------------------------------------------------

def parse_events(text):
    """[(time, step, event, [args])] from the ledger's lines."""
    out = []
    for line in text.splitlines():
        if line.strip():
            at, step, event, *args = line.split()
            out.append((datetime.datetime.fromisoformat(at.replace("Z", "+00:00")), step, event, args))
    return out


def problems(names, step, phase, events, info, arg=None):
    """What stands between `step` and `phase` - empty when the phase may run."""
    if step not in names:
        return [f"no step {step}"]
    mine = [(at, e, a) for at, s, e, a in events if s == step]
    kinds = [e for _, e, _ in mine]
    if "done" in kinds:
        return [f"{step} is done"]
    if phase == "begin":
        missing = [n for n in names[:names.index(step)] if (n, "done") not in {(s, e) for _, s, e, _ in events}]
        return ([f"earlier steps not done: {', '.join(missing)}"] if missing else []) \
            + ([f"{step} has begun already"] if "begun" in kinds else [])
    if "begun" not in kinds:
        return [f"{step} has not begun (deploy:upgrade:begin)"]
    backed = {a[0] for _, e, a in mine if e == "backup"}
    settled = {a[0] for _, e, a in mine if e == "settled"}
    if phase == "backup":
        return [] if arg in info["wave0"] else \
            [f"{step} backs up no {arg} (its wave0 stores: {', '.join(info['wave0']) or 'none'})"]
    if phase == "preview":
        return [] if info["playbooks"] else [f"{step} has no playbook lines"]
    out = [f"not backed up yet: {', '.join(s for s in info['wave0'] if s not in backed)} (deploy:upgrade:backup)"] \
        if any(s not in backed for s in info["wave0"]) else []
    if phase == "merge":
        if arg not in info["branches"]:
            return out + [f"{step} has no {arg} branch line"]
        first = [r for r in info["branches"][:info["branches"].index(arg)] if r not in settled]
        return out + ([f"merge {', '.join(first)} first (the step file's order)"] if first else []) \
            + ([f"{arg} is merged and settled already"] if arg in settled else [])
    unsettled = [r for r in info["branches"] if r not in settled]
    out += [f"not merged and settled yet: {', '.join(unsettled)} (deploy:upgrade:merge)"] if unsettled else []
    if phase == "playbooks":
        if not info["playbooks"]:
            return out + [f"{step} has no playbook lines"]
        return out + (["not previewed (deploy:upgrade:preview)"] if "previewed" not in kinds else []) \
            + (["its playbook lines ran already"] if "playbooks" in kinds else [])
    played = ["its playbook lines have not run (deploy:upgrade:playbooks)"] \
        if info["playbooks"] and "playbooks" not in kinds else []
    if phase == "defaults":
        if not info["defaults"]:
            return out + [f"{step} has no default lines"]
        return out + played + (["its defaults are committed already"] if "defaults" in kinds else [])
    if phase == "done":
        return out + played + (["its playbook defaults are not committed (deploy:upgrade:defaults)"]
                               if info["defaults"] and "defaults" not in kinds else [])
    raise ValueError(phase)


def soak_state(events, step, soak_minutes, now):
    """(checked at, seconds left) - checked at is None when the soak has not started (no checked since the last
    check-failed)."""
    checked = None
    for at, s, e, _ in events:
        if s == step and e == "checked":
            checked = at
        elif s == step and e == "check-failed":
            checked = None
    if checked is None:
        return None, None
    return checked, max(0.0, soak_minutes * 60 - (now - checked).total_seconds())


def applied_steps(events):
    return sorted({s for _, s, e, _ in events if e == "done"})


# ---- the ledger on ten ----------------------------------------------------------------------------------------------

def run(cmd, **kw):
    return subprocess.run(cmd, text=True, **kw)


def ten(command, stdin=None, check=True):
    out = run(["ssh", TEN, command], input=stdin, capture_output=True)
    if check and out.returncode:
        sys.exit(f"on ten: {command}: rc {out.returncode}: {out.stderr.strip()}")
    return out


def read_ledger():
    out = ten(f"kubectl -n {LEDGER_NAMESPACE} get configmap {LEDGER_NAME} -o json", check=False)
    if out.returncode:
        if "NotFound" in out.stderr:
            sys.exit("no ledger on ten - task deploy:upgrade:ledger-init")
        sys.exit(f"reading the ledger: {out.stderr.strip()}")
    obj = json.loads(out.stdout)
    return obj, parse_events(obj.get("data", {}).get("events", ""))


def record(step, event, *args):
    """Append one event - kubectl replace with the read resourceVersion: a concurrent change refuses."""
    obj, _ = read_ledger()
    at = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    line = " ".join((at, step, event, *args))
    obj.setdefault("data", {})["events"] = (obj["data"].get("events", "").rstrip("\n") + "\n" + line).lstrip("\n")
    ten("kubectl replace -f -", stdin=json.dumps(obj))
    print(f"LEDGER: {line}")


def init():
    if ten(f"kubectl -n {LEDGER_NAMESPACE} get configmap {LEDGER_NAME}", check=False).returncode == 0:
        sys.exit("the ledger exists already")
    obj = {"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": LEDGER_NAME, "namespace": LEDGER_NAMESPACE},
           "data": {"events": ""}}
    ten("kubectl create -f -", stdin=json.dumps(obj))
    record(BEFORE_LEDGER, "begun", "in-production-since-2026-10-03")
    record(BEFORE_LEDGER, "done", "in-production-since-2026-10-03")


# ---- checks against ten -------------------------------------------------------------------------------------------

def inventory_check(applied):
    """ten's and the Pis' inventory (the test environment left out, listed apart) against production's with the
    given steps applied."""
    os.makedirs(os.path.join(OPS, ".upgrade"), exist_ok=True)
    expected = os.path.join(OPS, ".upgrade", "prod-expected.txt")
    now = os.path.join(OPS, ".upgrade", "prod-inventory-now.txt")
    with open(expected, "w") as f:
        f.write("\n".join(sorted(inv.expected(applied))) + "\n")
    script = open(os.path.join(OPS, "scripts", "version-inventory.sh")).read()
    lines = ten(f"INVENTORY_EXCLUDE_NAMESPACES={shlex.quote(TEST_NAMESPACES)} bash -s", stdin=script).stdout
    pi_script = open(os.path.join(OPS, "scripts", "version-inventory-pi.sh")).read()
    for pi in PIS:
        out = run(["ssh", pi, "sudo -n bash -s"], input=pi_script, capture_output=True)
        if out.returncode:
            sys.exit(f"inventory of {pi}: {out.stderr.strip()}")
        lines += out.stdout
    with open(now, "w") as f:
        f.write(lines.replace("\r", ""))
    apart = ten(f"INVENTORY_ONLY_NAMESPACES={shlex.quote(TEST_NAMESPACES)} bash -s", stdin=script).stdout
    print(f"the test environment ({TEST_NAMESPACES}) - listed, not compared:")
    print("\n".join("  " + l for l in apart.splitlines() if l.startswith(("image ", "helm ", "kafka-metadata "))))
    return run([os.path.join(OPS, "scripts", "inventory-diff.sh"), expected, now,
                os.path.join(inv.UPGRADE, "prod-transient.txt")]).returncode == 0


def main_revisions():
    revs = {}
    for repo in REPOS:
        d = os.path.join(OPS, "..", repo)
        run(["git", "-C", d, "fetch", "-q", "origin", "main"], check=True)
        revs[URLS[repo]] = run(["git", "-C", d, "rev-parse", "origin/main"], capture_output=True,
                               check=True).stdout.strip()
    return revs


def settled(minutes, stable, quiet, allow_out_of_sync, apps=None, restart_step=None):
    """argo-settled.py on ten, with ten's own kubeconfig: every app Synced (or allowed) and Healthy on main's commits,
    every pod ready, held for `stable` polls, no container restarted in the last `quiet` seconds; with `apps`, exactly
    those apps (preview environments aside); with `restart_step`, no pod restarting in this step and the done one
    before it. (green, main's revisions, the apps it saw - preview environments left out)."""
    revs = main_revisions()
    script = open(os.path.join(inv.UPGRADE, "files", "argo-settled.py")).read()
    cmd = (f"MIRROR_REVISIONS={shlex.quote(json.dumps(revs))} python3 - --kubeconfig \"$HOME/.kube/config\" "
           f"--minutes {minutes} --poll 10 --stable-polls {stable} --restart-quiet {int(quiet)} "
           f"--allow-out-of-sync {shlex.quote(','.join(allow_out_of_sync))} --print-apps "
           f"--allow-extra-apps {shlex.quote(PREVIEW_APPS)}")
    if apps:
        cmd += f" --expect-apps {shlex.quote(','.join(apps))}"
    if restart_step:
        cmd += f" --restart-history {RESTART_HISTORY} --step {shlex.quote(restart_step)}"
    print(f"Argo on ten, on infra {revs[URLS['infra']][:10]} / platform {revs[URLS['platform']][:10]}:", flush=True)
    out = run(["ssh", TEN, cmd], input=script, capture_output=True)
    print(out.stdout + out.stderr, end="")
    seen = next((l[5:].split(",") for l in reversed(out.stdout.splitlines()) if l.startswith("APPS ")), [])
    return out.returncode == 0, revs, [a for a in seen if not re.search(PREVIEW_APPS, a)]


def step_apps(events, step):
    """The app set the step's begin recorded."""
    found = [a for _, s, e, a in events if s == step and e == "apps"]
    if not found:
        sys.exit(f"REFUSED: {step} recorded no app set at its begin")
    return found[-1][0].split(",")


# ---- the proof (the full run) ---------------------------------------------------------------------------------------

def own_change(repo_dir, base, tip):
    """sha256 of a branch's own change: every changed line with its file, no line numbers - the same change rebased
    onto a moved main hashes the same."""
    return own_hash(run(["git", "-C", repo_dir, "diff", "-U0", base, tip], capture_output=True, check=True).stdout)


def own_hash(diff):
    """own_change's hash of a `git diff -U0`: the file headers and the changed lines, not the hunk positions."""
    h, in_hunk = hashlib.sha256(), False
    for line in diff.splitlines():
        if line.startswith("diff --git"):
            in_hunk = False
            h.update(line.encode() + b"\n")
        elif line.startswith("@@"):
            in_hunk = True
        elif in_hunk and line[:1] in ("+", "-"):
            h.update(line.encode() + b"\n")
    return h.hexdigest()


def ops_unchanged_since(commit, paths):
    """Paths changed (or untracked) in the ops tree since the commit."""
    changed = run(["git", "-C", OPS, "diff", "--name-only", commit, "--", *paths], capture_output=True,
                  check=True).stdout.split()
    untracked = run(["git", "-C", OPS, "ls-files", "--others", "--exclude-standard", "--", *paths],
                    capture_output=True, check=True).stdout.split()
    return changed + untracked


def proof_start():
    dirty = run(["git", "-C", OPS, "status", "--porcelain", "--", *PROVEN_PATHS], capture_output=True,
                check=True).stdout
    if dirty.strip():
        sys.exit("REFUSED: the ops tree is not committed - a full run proves a commit:\n" + dirty)
    head = run(["git", "-C", OPS, "rev-parse", "HEAD"], capture_output=True, check=True).stdout.strip()
    os.makedirs(PROVEN, exist_ok=True)
    started = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with open(os.path.join(PROVEN, "run.json"), "w") as f:
        json.dump({"ops": head, "run": started}, f)
    print(f"PROOF: run {started} of ops {head[:10]}")


def record_proof(step, infra_sha, platform_sha):
    run_info = json.load(open(os.path.join(PROVEN, "run.json")))
    changed = ops_unchanged_since(run_info["ops"], PROVEN_PATHS)
    if changed:
        sys.exit(f"REFUSED: the ops tree changed during the run ({', '.join(changed)}) - the run proves nothing")
    names = step_names()
    refs = dict(zip(REPOS, run([os.path.join(OPS, "scripts", "upgrade-expected-inventory.py"), "--refs", step],
                               capture_output=True, check=True).stdout.split()))
    shas = {"infra": infra_sha, "platform": platform_sha}
    prev = dict(zip(REPOS, run([os.path.join(OPS, "scripts", "upgrade-expected-inventory.py"), "--refs",
                                names[names.index(step) - 1]], capture_output=True, check=True).stdout.split())) \
        if names.index(step) else {r: "main" for r in REPOS}
    proof = {"step": step, "run": run_info["run"], "ops": run_info["ops"], "repos": {}, "floating": floating_digests()}
    for repo in REPOS:
        now_sha = run(["git", "-C", os.path.join(OPS, "..", repo), "rev-parse", refs[repo]], capture_output=True,
                      check=True).stdout.strip()
        if now_sha != shas[repo]:
            sys.exit(f"REFUSED: {repo} {refs[repo]} moved during the step ({shas[repo][:10]} -> {now_sha[:10]})")
        if repo in step_info(step)["branches"]:
            proof["repos"][repo] = {"sha": now_sha, "own": own_change(os.path.join(OPS, "..", repo), prev[repo],
                                                                      refs[repo])}
    with open(os.path.join(PROVEN, step + ".json"), "w") as f:
        json.dump(proof, f, indent=1)
    print(f"PROOF: {step} " + " ".join(f"{r}={p['sha'][:10]}" for r, p in proof["repos"].items()))


def floating_digests():
    """The floating-tag images the run copied from ten, by digest (scripts/vagrant-preload-floating.sh)."""
    path = os.path.join(OPS, ".upgrade", "floating-digests.txt")
    if not os.path.exists(path):
        sys.exit("REFUSED: no .upgrade/floating-digests.txt - the run's build copies ten's floating-tag images")
    return dict(l.split() for l in open(path) if l.strip())


def full_name(name):
    """An image name as containerd lists it (docker.io/library/... for a short one) - as the preload names them."""
    first = name.split("/")[0]
    if "." in first or ":" in first:
        return name
    return "docker.io/" + ("library/" + name if "/" not in name else name)


def floating_problems(proven, inventory):
    """Floating-tag images still in use (in `inventory`) whose tag on ten now names another build than the full run
    ran. One no step uses any more may be gone (the kubelet collects unused images)."""
    in_use = {full_name(l.split()[1]) + ":" + l.split()[2] for l in inventory if l.startswith("image ")}
    listing = ten("sudo -n ctr -n k8s.io images ls").stdout.splitlines()[1:]
    now = {l.split()[0]: l.split()[2] for l in listing if len(l.split()) > 2}
    return [f"{img}: ten's tag is {now.get(img, 'gone')}, the full run ran {digest}"
            for img, digest in sorted(proven.items()) if img in in_use and now.get(img) != digest]


def defaulted(events):
    """The steps whose default lines production committed, in step order."""
    return sorted({s for _, s, e, _ in events if e == "defaults"})


def proof_problems(step, names, repo=None, defaulted_steps=()):
    """What the full run's proof says against running `step` (and merging `repo`) now. deploy/ may differ from the
    run's ops commit only by the default lines of `defaulted_steps`."""
    path = os.path.join(PROVEN, step + ".json")
    if not os.path.exists(path):
        return [f"{step} has no proof from a full run (.upgrade/proven/{step}.json)"]
    proof = json.load(open(path))
    out = []
    for earlier in names[:names.index(step)]:
        p = os.path.join(PROVEN, earlier + ".json")
        if not os.path.exists(p) or json.load(open(p))["run"] != proof["run"]:
            out.append(f"{earlier} was not proven by the same full run as {step} ({proof['run']})")
            break
    if not proof.get("floating"):
        out.append(f"{step}'s proof records no floating-tag images")
    else:
        out += floating_problems(proof["floating"], inv.expected(names[:names.index(step)]))
    changed = ops_unchanged_since(proof["ops"], ("deploy", os.path.join("tests", "ansible", "upgrade", "steps",
                                                                        step + ".txt")))
    try:
        expected = dflt.applied(lambda p: run(["git", "-C", OPS, "show", f"{proof['ops']}:{p}"], capture_output=True,
                                              check=True).stdout, list(defaulted_steps))
    except ValueError as e:
        return out + [f"the committed steps' default lines do not apply to the run's ops commit: {e}"]
    changed = [p for p in changed if not (p in expected and open(os.path.join(OPS, p)).read() == expected[p])]
    if changed:
        out.append(f"changed since the full run proved {step} (ops {proof['ops'][:10]}), beyond the committed "
                   f"steps' playbook defaults: {', '.join(changed)}")
    if repo:
        d = os.path.join(OPS, "..", repo)
        branch = "upgrade/" + step
        run(["git", "-C", d, "fetch", "-q", "origin", "main"], check=True)
        if run(["git", "-C", d, "merge-base", "--is-ancestor", "origin/main", branch]).returncode:
            out.append(f"{repo} {branch} does not contain origin/main - restack it "
                       f"(scripts/upgrade-restack-in-place.sh ../{repo})")
        elif own_change(d, "origin/main", branch) != proof["repos"][repo]["own"]:
            out.append(f"{repo} {branch} on origin/main is not the change the full run proved")
    return out


# ---- the phases -----------------------------------------------------------------------------------------------------

def refuse(lines):
    if lines:
        sys.exit("REFUSED:\n" + "\n".join("  " + l for l in lines))


def ledger_for(step, phase, arg=None):
    names = step_names()
    _, events = read_ledger()
    info = step_info(step) if step in names else None
    refuse(problems(names, step, phase, events, info, arg))
    return names, events, info


def ansible(*args):
    return run(["venv/bin/ansible-playbook", "-i", "inventory/production.yml", *args],
               cwd=os.path.join(OPS, "deploy", "ansible"), stdin=subprocess.DEVNULL).returncode == 0


def last_done_out_of_sync(events):
    done = applied_steps(events)
    return step_info(done[-1])["out_of_sync"] if done and done[-1] != BEFORE_LEDGER else []


def begin(step):
    names, events, _ = ledger_for(step, "begin")
    refuse(proof_problems(step, names, defaulted_steps=defaulted(events)))
    ok = inventory_check(applied_steps(events))
    # the app set the step must keep: the previous step's (a done step's apps), or, for the first, what runs now
    before = [a for _, s, e, a in events if e == "apps" and s != step]
    ok_settled, _, seen = settled(15, 4, 300, last_done_out_of_sync(events),
                                  before[-1][0].split(",") if before else None)
    refuse([] if ok and ok_settled and seen else ["production is not as the done steps leave it (above)"])
    record(step, "begun")
    record(step, "apps", ",".join(seen))


def backup(step, store):
    names, events, _ = ledger_for(step, "backup", store)
    refuse(proof_problems(step, names, defaulted_steps=defaulted(events)))
    refuse([] if ansible("playbooks/upgrade-backup.yml", "-e", f"store={store}") else [f"the {store} backup failed"])
    record(step, "backup", store)


def preview(step):
    ledger_for(step, "preview")
    script = os.path.join(OPS, "scripts", "upgrade-step-playbooks.sh")
    refuse([] if run([script, "--production", "--check", step]).returncode == 0 else ["the preview failed"])
    record(step, "previewed")


def merge(step, repo):
    names, events, _ = ledger_for(step, "merge", repo)
    merged = any(s == step and e == "merged" and a[:1] == [repo] for _, s, e, a in events)
    if not merged:
        refuse(proof_problems(step, names, repo, defaulted(events)))
        order = run([os.path.join(OPS, "scripts", "upgrade-merge-order.py"), step])
        refuse([] if order.returncode == 0 else ["the state between this step's merges was never proven (above)"])
        refuse([] if run([os.path.join(OPS, "scripts", "upgrade-merge-step.sh"), step, repo]).returncode == 0
               else [f"the {repo} merge failed (above)"])
        sha = run(["git", "-C", os.path.join(OPS, "..", repo), "rev-parse", "main"], capture_output=True,
                  check=True).stdout.strip()
        record(step, "merged", repo, sha)
    # nothing out of sync after a merge (as the Vagrant run's first wait): a step's argo-out-of-sync apps are allowed
    # only after its playbooks
    ok, revs, _ = settled(30, 4, 300, [], step_apps(events, step))
    refuse([] if ok else [f"Argo did not settle on the {repo} merge - the step stops here (its abort line)"])
    record(step, "settled", repo, revs[URLS[repo]])


def playbooks(step):
    names, events, _ = ledger_for(step, "playbooks")
    refuse(proof_problems(step, names, defaulted_steps=defaulted(events)))
    script = os.path.join(OPS, "scripts", "upgrade-step-playbooks.sh")
    refuse([] if run([script, "--production", step]).returncode == 0 else ["the playbook lines failed (above)"])
    record(step, "playbooks")


CHECK_MINUTES = 15


def defaults(step):
    """The step's default lines into ops main, committed and pushed - nothing else may be in the commit."""
    names, events, _ = ledger_for(step, "defaults")
    refuse(proof_problems(step, names, defaulted_steps=defaulted(events)))
    run(["git", "-C", OPS, "fetch", "-q", "origin", "main"], check=True)
    head = run(["git", "-C", OPS, "rev-parse", "HEAD", "origin/main"], capture_output=True, check=True).stdout.split()
    branch = run(["git", "-C", OPS, "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, check=True).stdout
    dirty = run(["git", "-C", OPS, "status", "--porcelain"], capture_output=True, check=True).stdout
    refuse(([] if branch.strip() == "main" and head[0] == head[1] else ["ops is not on main at origin/main"])
           + ([f"ops has uncommitted changes:\n{dirty}"] if dirty.strip() else []))
    refuse([] if run([os.path.join(OPS, "scripts", "upgrade-defaults.py"), "--apply", step]).returncode == 0
           else ["the default lines did not apply (above)"])
    paths = sorted({p for p, _, _ in dflt.default_lines(step)})
    run(["git", "-C", OPS, "commit", "-q", "-m", f"upgrade {step}: its playbook defaults (in production)", "--",
         *paths], check=True)
    run(["git", "-C", OPS, "push", "-q", "origin", "main"], check=True)
    sha = run(["git", "-C", OPS, "rev-parse", "HEAD"], capture_output=True, check=True).stdout.strip()
    record(step, "defaults", sha)


def check(step, since=None, deciding=False):
    """ten as the done steps and this one leave it, Argo settled, the step's app set kept. With `since` (seconds): no
    container restarted in that long - the restart window covers the whole wait, so a restart inside it cannot age out
    while it polls. `deciding` (the call that ends a step): the restart history judged and recorded."""
    _, events = read_ledger()
    ok = inventory_check(sorted(set(applied_steps(events)) | {step}))
    quiet = 300 if since is None else since + CHECK_MINUTES * 60 + 60
    apps = step_apps(events, step) if any(s == step and e == "apps" for _, s, e, _ in events) else None
    ok_settled, _, _ = settled(CHECK_MINUTES, 4, quiet, step_info(step)["out_of_sync"], apps,
                               step if deciding else None)
    return ok and ok_settled


def done(step):
    _, events, info = ledger_for(step, "done")
    now = datetime.datetime.now(datetime.timezone.utc)
    checked, left = soak_state(events, step, info["soak"], now)
    if checked is not None and left > 0:
        refuse([f"soaking: {info['soak']} minutes from the first green check at {checked:%H:%M} UTC - "
                f"{left / 60:.0f} left"])
    if checked is None and info["acme"]:
        refuse([] if ansible("playbooks/acme-check.yml") else ["ACME issuance through production's solver failed"])
    if checked is None and info["base_backup"]:
        refuse([] if ansible("playbooks/postgres-base-backup.yml") else ["no fresh Postgres base backup (above)"])
    # after the soak: no container may have restarted since the first green check
    green = check(step, None if checked is None else (now - checked).total_seconds(), deciding=checked is not None)
    if checked is None:
        refuse([] if green else ["not green - nothing recorded (fix, or the step's abort line)"])
        record(step, "checked")
        print(f"the soak runs {info['soak']} minutes - deploy:upgrade:done again after it")
        return
    if not green:
        record(step, "check-failed")
        refuse(["red after the soak began (a restart since the first green check counts) - the soak starts again "
                "from the next green check"])
    record(step, "done")


def status():
    names = step_names()
    _, events = read_ledger()
    for at, s, e, a in events:
        print(f"{at:%Y-%m-%d %H:%M} {s} {e} {' '.join(a)}")
    pending = next((n for n in names if n not in applied_steps(events)), None)
    if pending is None:
        print("every step done")
        return
    info = step_info(pending)
    have = {(e, a[0] if a else None) for _, s, e, a in events if s == pending}
    phases = [("begin", None, ("begun", None)), *(("backup", s, ("backup", s)) for s in info["wave0"])]
    phases += [("preview", None, ("previewed", None))] if info["playbooks"] else []
    phases += [("merge", r, ("settled", r)) for r in info["branches"]]
    phases += [("playbooks", None, ("playbooks", None))] if info["playbooks"] else []
    phases += [("defaults", None, ("defaults", None))] if info["defaults"] else []
    for phase, arg, mark in phases + [("done", None, ("done", None))]:
        if mark not in have:
            p = problems(names, pending, phase, events, info, arg)
            print(f"next: {pending} {phase}{' ' + arg if arg else ''}" + (f" - {'; '.join(p)}" if p else ""))
            if phase == "done":
                checked, left = soak_state(events, pending, info["soak"], datetime.datetime.now(datetime.timezone.utc))
                if checked is not None:
                    print(f"  soaking since {checked:%H:%M} UTC, {left / 60:.0f} of {info['soak']} minutes left")
            break


def main():
    a = sys.argv[1:]
    actions = {("init", 0): init, ("status", 0): status, ("proof-start", 0): proof_start,
               ("begin", 1): begin, ("preview", 1): preview, ("playbooks", 1): playbooks, ("done", 1): done,
               ("defaults", 1): defaults,
               ("backup", 2): backup, ("merge", 2): merge, ("record-proof", 3): record_proof}
    if a[:1] == ["check"] and len(a) == 2:
        sys.exit(0 if check(a[1]) else 1)
    fn = actions.get((a[0] if a else "", len(a) - 1))
    if fn is None:
        sys.exit(__doc__)
    if a[0] == "merge" and a[2] not in REPOS:
        sys.exit("merge <step> <infra|platform>")
    fn(*a[1:])


if __name__ == "__main__":
    main()
