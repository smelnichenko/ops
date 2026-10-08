#!/usr/bin/env python3
"""upgrade-production.py - the upgrade steps on production: one step at a time, in order, each phase only after the
phases it needs. A ledger on ten (ConfigMap kube-system/upgrade-ledger, one line per event) is checked and written by
every phase; the Taskfile's deploy:upgrade:* tasks call this, and `task deploy:upgrade:status` names the next phase.

Per step N (tests/ansible/upgrade/steps/N.txt), in this order:
  begin      every earlier step done; ten's inventory as the done steps leave it and Argo settled on main   -> begun
  backup     each of the step's wave0 stores into the Pi store (upgrade-backup.yml)                -> backup <store>
  merge      each branch line in the file's order: the branch's own change exactly as the full run proved it, the
             state between two merges one the full run proved (upgrade-merge-order.py), the change shown and
             confirmed, the step's public images pulled on ten at each merge (upgrade-prepull.yml), merged and
             pushed
             (upgrade-merge-step.sh); then Argo settled on the pushed commits        -> merged <repo>, settled <repo>
             a barman-after-merge step's merge that makes its new PostgreSQL major live (or its last): then,
             asked first, a base backup on it (postgres-base-backup.yml)                              -> base-backup
  preview    the step's playbook lines in check mode, with diffs, on the cluster the merges left        -> previewed
  playbooks  the step's playbook lines against production                                               -> playbooks
  defaults   the step's default lines (scripts/upgrade-defaults.py) committed to ops main and pushed: a playbook
             run from now on installs what production runs                                             -> defaults
  done       ten's inventory as step N leaves it and Argo settled (after a step that changes cert-manager - its
             cert-renew line - first a throwaway certificate issued through production's ACME solver: acme-check.yml;
             a barman-check step whose merge took no base backup - declined or failed there - takes it here).
             The first green call records checked as it ends (and when it began); a call at
             least the step's soak later (its soak line; else 60 minutes after a wave0 step, 15 otherwise) that is
             green again with no container restarted since the first began records done. A red call after checked records
             check-failed: the soak starts again from the next green call.
A phase that fails records nothing of its own. Every phase claims the step first - start <phase> <host:pid>, written
against the same read of the ledger that cleared it, so a second run of any phase of the step refuses until the first
records its end (passed or failed, Ctrl-C included); a run killed outright leaves its start open: release <step>
closes it, once nothing runs. Step 02 (the Istio chart repository) went to production on 2026-10-03, before the
ledger: init records it done.

The proof (record-proof, run by test:upgrade:full once the next step's deciding settle has judged the step's restarts
too - the last step's after a final settle at production's values; proof-start at the run's start): each repo's
branch SHA and own change (its changed lines and files against the repo's ref at the step before), the ops commit the
run ran from - refused if deploy/, scripts/, tests/ or Taskfile.yml differ from it. Production's merge wants the same
own change and every step up to N proven by one run; its phases want the same tree (deploy/, scripts/, tests/,
Taskfile.yml, Vagrantfile) as that run had it, but for the committed steps' playbook defaults.

Usage: scripts/upgrade-production.py init | status
       scripts/upgrade-production.py release <step>         (a phase's open start closed - only when nothing runs)
       scripts/upgrade-production.py begin|preview|playbooks|defaults|done <step>
       scripts/upgrade-production.py backup <step> <store>
       scripts/upgrade-production.py merge <step> <infra|platform>
       scripts/upgrade-production.py check <step>              (read-only: as `done` checks, nothing recorded)
       scripts/upgrade-production.py proof-start
       scripts/upgrade-production.py record-proof <step> <infra sha> <platform sha>
       scripts/upgrade-production.py prepull-images <step>   (the images the merge pre-pulls, by the branches' pins:
                                                             the Vagrant step runs the pre-pull with them)
       scripts/upgrade-production.py settle-values           (production's settle as argo-settled.yml's -e: the full
                                                             run's final settle takes them)
"""
import base64
import datetime
import hashlib
import importlib.machinery
import importlib.util
import json
import os
import re
import secrets
import shlex
import subprocess
import socket
import sys
import tempfile
import termios
import urllib.error
import urllib.request

import yaml

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
SETTLE_MINUTES = 30
# production's settle: green held SETTLE_STABLE polls SETTLE_POLL s apart, no container restarted in the last
# SETTLE_QUIET s (CrashLoopBackOff's longest back-off) - the full run's final settle takes the same (settle-values)
SETTLE_POLL, SETTLE_STABLE, SETTLE_QUIET = 10, 4, 300
# preview environments come and go (an Argo app per pull request): never part of the app set a step must keep
PREVIEW_APPS = r"^pr-\d+-"
PREVIEW_NAMESPACES = r"^schnappy-pr-\d+$"  # ...and their pods
# on ten, sm's: each done step's restart counts, so a pod restarting in two steps running fails the second
RESTART_HISTORY = "$HOME/.upgrade-restart-history.json"
WORK = os.path.join(OPS, ".upgrade")  # the runs' own files, git-ignored
PROVEN = os.path.join(WORK, "proven")
INVENTORY = os.path.join(OPS, "scripts", "upgrade-expected-inventory.py")
ORIGIN_MAIN = "origin/main"
BRANCH = "upgrade/"  # + step: a step's branch in infra and platform
MERGED_TAG = "upgrade-merged/"  # + step: the tag a production merge leaves (scripts/upgrade-merge-step.sh)
PROVEN_PATHS = ("deploy", "scripts", "tests", "Taskfile.yml", "Vagrantfile")
# the app images the full run ran: production's values with these tags over them (the Vagrant overlay)
APP_VALUES = "clusters/production/schnappy-production-apps/values.yaml"
APP_OVERLAY = os.path.join("tests", "ansible", "upgrade", "vagrant-overlay", "infra", APP_VALUES.replace(
    "values.yaml", "values.vagrant.yaml"))
BEFORE_LEDGER = "02-istio-chart-repo"


def _load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, path)
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, loader))
    loader.exec_module(module)
    return module


inv = _load("upgrade_expected_inventory", INVENTORY)
dflt = _load("upgrade_defaults", os.path.join(OPS, "scripts", "upgrade-defaults.py"))


def proof_path(step):
    return os.path.join(PROVEN, step + ".json")


def step_names():
    return sorted(f[:-4] for f in os.listdir(inv.STEPS) if f.endswith(".txt"))


def step_info(name):
    playbooks, wave0, soak, settle, out_of_sync, flags, tempo_flush = [], [], [], [], [], set(), []
    inv.parse(os.path.join(inv.STEPS, name + ".txt"), playbooks=playbooks, wave0=wave0, soak=soak, settle=settle,
              out_of_sync=out_of_sync, flags=flags, tempo_flush=tempo_flush)
    default_soak = SOAK_MINUTES_WAVE0 if wave0 else SOAK_MINUTES
    return {"branches": inv.branch_order(name), "playbooks": playbooks, "wave0": wave0, "out_of_sync": out_of_sync,
            "soak": soak[-1] if soak else default_soak,
            "settle": settle[-1] if settle else SETTLE_MINUTES,
            "defaults": bool(dflt.default_lines(name)), "acme": "cert-renew" in flags,
            "base_backup": "barman-check" in flags, "base_backup_after_merge": "barman-after-merge" in flags,
            "restarts_expected": "restarts-control-plane" in flags,
            "tempo_flush": tempo_flush}


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
    started = open_start(mine)
    if started:
        return [f"{step}: {' '.join(started[1])} started at {started[0]:%Y-%m-%d %H:%M} UTC and has not ended - if "
                f"nothing runs it any more: task deploy:upgrade:release STEP={step}"]
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
    # the preview after the merges: a step's playbooks read the cluster the merge leaves (istiod at the target, ...)
    if phase == "preview":
        return out + ([] if info["playbooks"] else [f"{step} has no playbook lines"])
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


def open_start(mine):
    """The step's last phase start (time, its arguments - its token, host:pid:nonce, last) that no end of its own
    followed, else None. An end carries the token of the start it closes: a released run's late end leaves a later
    claim open (one with no token, an older ledger's, closes whatever start is open).

    `mine`: (time, event, args)."""
    started = None
    for at, e, a in mine:
        if e == "start":
            started = (at, a)
        elif e == "end" and started and (len(a) < 3 or a[2] == started[1][-1]):
            started = None
    return started


def checked_since(events, step):
    """Where the deciding check judges restarts from: the first green check's start (its since=, read before it ran -
    a restart as it ran counts), or, for one recorded before the two were apart, its own time; None when no soak."""
    since = None
    for at, s, e, args in events:
        if s == step and e == "checked":
            since = next((datetime.datetime.fromisoformat(a[6:].replace("Z", "+00:00")) for a in args
                          if a.startswith("since=")), at)
        elif s == step and e == "check-failed":
            since = None
    return since


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


# ssh giving up on a dead connection (a minute without an answer to its keep-alives), and a bound on a remote command
# that never answers: either hung a phase for ever
SSH = ["ssh", "-o", "ConnectTimeout=20", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=4"]
REMOTE_TIMEOUT = 900  # s: a read, a write, an inventory (the settle and Tempo's flush pass their own)


def remote(host, command, stdin=None, timeout=None, capture=True):
    """`command` run on `host` (one string, as ssh passes it), `stdin` given."""
    timeout = timeout or REMOTE_TIMEOUT
    try:
        return run([*SSH, host, command], input=stdin, capture_output=capture, timeout=timeout)
    except subprocess.TimeoutExpired:
        sys.exit(f"on {host}: {command.split()[0]}...: no answer in {timeout} s - it may have run all the same")


def ten(command, stdin=None, check=True):
    out = remote(TEN, command, stdin)
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


def ten_now():
    """ten's clock, UTC, as the ledger writes times: the pods' restart times are its."""
    at = ten("date -u +%Y-%m-%dT%H:%M:%SZ").stdout.strip()
    if not re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", at):
        sys.exit(f"ten's clock answered {at!r}")
    return at


def ten_clock():
    """ten_now() as a time."""
    return datetime.datetime.strptime(ten_now(), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)


def claim_problems(step, obj):
    """This run's claim on the step (`obj`: the ledger read), if it holds one, closed meanwhile - released by hand
    while the run was alive, maybe claimed by another phase since."""
    token = next((t for s, _, t in CLAIMED if s == step), None)
    if not token:
        return []
    started = open_start([(at, e, a) for at, s, e, a in parse_events(obj.get("data", {}).get("events", ""))
                          if s == step])
    if started and started[1][-1] == token:
        return []
    return [f"this run's claim on {step} was closed meanwhile (deploy:upgrade:release?)"]


def record(step, event, *args, obj=None, at=None):
    """Append one event - kubectl replace with the read resourceVersion (`obj`'s, when given: the read a decision was
    made on): a concurrent change refuses. `at`: the event's time (now, by this machine's clock, without)."""
    obj = obj if obj is not None else read_ledger()[0]
    # a run whose claim on the step was closed meanwhile (released by hand, the run alive) records nothing more: its
    # events would land in whatever claimed the step after
    lost = claim_problems(step, obj)
    if lost:
        sys.exit(f"REFUSED: {lost[0]} - {event} not recorded")
    at = at or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    line = " ".join((at, step, event, *args))
    obj.setdefault("data", {})["events"] = (obj["data"].get("events", "").rstrip("\n") + "\n" + line).lstrip("\n")
    out = ten("kubectl replace -f -", stdin=json.dumps(obj), check=False)
    if out.returncode and ("Conflict" in out.stderr or "has been modified" in out.stderr):
        sys.exit(f"REFUSED: the ledger changed since it was read (another phase at work?): {out.stderr.strip()}")
    if out.returncode:
        # the connection gone after the server took it: the event may stand (a start then waits for its release)
        sys.exit("the ledger write failed - it may have been made all the same (task deploy:upgrade:status): "
                 f"{out.stderr.strip()}")
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

def excluded_namespaces():
    """The namespaces the inventory leaves out: the test environment's, and the preview environments open now
    (schnappy-pr-<N>) - no step's, they come and go with their pull requests."""
    names = [n.split("/", 1)[-1] for n in ten("kubectl get namespaces -o name").stdout.split()]
    return " ".join([TEST_NAMESPACES, *(n for n in names if re.search(PREVIEW_NAMESPACES, n))])


def inventory_check(applied):
    """ten's and the Pis' inventory (the test environment and open preview environments left out, the test
    environment listed apart) against production's with the given steps applied."""
    os.makedirs(WORK, exist_ok=True)
    # this run's own files (a check beside a phase must not diff the other one's), removed after it
    files = [tempfile.mkstemp(prefix=p, suffix=".txt", dir=WORK) for p in ("prod-expected.", "prod-inventory-now.")]
    for fd, _ in files:
        os.close(fd)
    expected, now = (path for _, path in files)
    try:
        with open(expected, "w") as f:
            f.write("\n".join(sorted(inv.expected(applied))) + "\n")
        script = open(os.path.join(OPS, "scripts", "version-inventory.sh")).read()
        lines = ten(f"INVENTORY_EXCLUDE_NAMESPACES={shlex.quote(excluded_namespaces())} bash -s", stdin=script).stdout
        pi_script = open(os.path.join(OPS, "scripts", "version-inventory-pi.sh")).read()
        for pi in PIS:
            out = remote(pi, "sudo -n bash -s", pi_script)
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
    finally:
        for path in (expected, now):
            os.remove(path)


def main_revisions():
    revs = {}
    for repo in REPOS:
        d = os.path.join(OPS, "..", repo)
        run(["git", "-C", d, "fetch", "-q", "origin", "main"], check=True)
        revs[URLS[repo]] = run(["git", "-C", d, "rev-parse", ORIGIN_MAIN], capture_output=True,
                               check=True).stdout.strip()
    return revs


def settled(minutes, allow_out_of_sync, apps=None, restart_step=None, restarts_expected=False, restarted_since=None):
    """argo-settled.py on ten, with ten's own kubeconfig: every app Synced (or allowed) and Healthy on main's commits,
    every pod ready, held for SETTLE_STABLE polls, no container restarted in the last SETTLE_QUIET seconds nor at or after
    `restarted_since`; with `apps`, exactly those apps (preview environments aside); with `restart_step`, no pod
    restarting in this step and the done one before it - unless `restarts_expected` (the step restarts the control
    plane: recorded, not judged). (green, main's revisions, the apps it saw - preview environments left out). Red with
    main moved meanwhile (a CD push to infra main during the wait: every app then reports another commit) says so: it
    proves nothing about the step."""
    revs = main_revisions()
    script = open(os.path.join(inv.UPGRADE, "files", "argo-settled.py")).read()
    cmd = (f"MIRROR_REVISIONS={shlex.quote(json.dumps(revs))} python3 - --kubeconfig \"$HOME/.kube/config\" "
           f"--minutes {minutes} --poll {SETTLE_POLL} --stable-polls {SETTLE_STABLE} --restart-quiet {SETTLE_QUIET} "
           f"--allow-out-of-sync {shlex.quote(','.join(allow_out_of_sync))} --print-apps "
           f"--allow-extra-apps {shlex.quote(PREVIEW_APPS)} --ignore-namespaces {shlex.quote(PREVIEW_NAMESPACES)}")
    if apps:
        cmd += f" --expect-apps {shlex.quote(','.join(apps))}"
    if restarted_since is not None:
        cmd += f" --restarted-since {restarted_since:%Y-%m-%dT%H:%M:%SZ}"
    if restart_step:
        cmd += f" --restart-history {RESTART_HISTORY} --step {shlex.quote(restart_step)}"
        if restarts_expected:
            cmd += " --restarts-expected"
    print(f"Argo on ten, on infra {revs[URLS['infra']][:10]} / platform {revs[URLS['platform']][:10]}:", flush=True)
    out = remote(TEN, cmd, script, timeout=minutes * 60 + 600)
    print(out.stdout + out.stderr, end="")
    seen = next((l[5:].split(",") for l in reversed(out.stdout.splitlines()) if l.startswith("APPS ")), [])
    if out.returncode and main_revisions() != revs:
        sys.exit("INCONCLUSIVE: main moved during the wait (a CD push?) - Argo was judged against the old commits; "
                 "nothing recorded - run it again (and keep CD off infra main during the rollout)")
    return out.returncode == 0, revs, [a for a in seen if not re.search(PREVIEW_APPS, a)]


def step_apps(events, step):
    """The app set the step's begin recorded."""
    found = [a for _, s, e, a in events if s == step and e == "apps"]
    if not found:
        sys.exit(f"REFUSED: {step} recorded no app set at its begin")
    return found[-1][0].split(",")


# ---- the proof (the full run) ---------------------------------------------------------------------------------------

def own_change(repo_dir, base, tip):
    """sha256 of a branch's own change: every changed line with its file, a mode or a binary file's new content too,
    no line numbers - the same change rebased onto a moved main hashes the same."""
    return own_hash(run(["git", "-C", repo_dir, "diff", "-U0", "--binary", base, tip], capture_output=True,
                        check=True).stdout)


def own_hash(diff):
    """own_change's hash of a `git diff -U0 --binary`: every line but the hunks' positions (@@) and the files' blob
    names (index ...), which a moved main changes for the same change - the file headers, modes, renames, the changed
    lines and a binary file's patch all count."""
    h = hashlib.sha256()
    for line in diff.splitlines():
        if line.startswith("@@"):
            line = "@@"
        elif line.startswith("index "):
            continue
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
        json.dump({"ops": head, "run": started, "branches": branch_shas()}, f)
    print(f"PROOF: run {started} of ops {head[:10]}")


def branch_shas():
    """Every step branch (upgrade/*) of infra and platform, its commit - proof-start records them for the run."""
    out = {}
    for repo in REPOS:
        refs = run(["git", "-C", os.path.join(OPS, "..", repo), "for-each-ref",
                    "--format=%(refname:short) %(objectname)", "refs/heads/upgrade/"], capture_output=True,
                   check=True).stdout
        out[repo] = dict(line.split() for line in refs.splitlines())
    return out


def branch_moves(recorded):
    """The step branches moved, made or deleted since `recorded` (branch_shas()'s), named."""
    now = branch_shas()
    return [f"{repo} {b}: {recorded.get(repo, {}).get(b, 'none')[:10]} -> {now[repo].get(b, 'none')[:10]}"
            for repo in REPOS for b in sorted(set(recorded.get(repo, {})) | set(now[repo]))
            if recorded.get(repo, {}).get(b) != now[repo].get(b)]


PIN_RESULT = os.path.join(WORK, "clickhouse-pin.json")


def pin_problems(step, platform_sha, ops_sha, path=None):
    """A step that moves ClickHouse's image (its abort line goes back while the compatibility pin holds) is proven only
    with that pin proven for it: tests/clickhouse-pin of the run's ops commit, on the same platform commit and the same
    two images, its result in .upgrade/clickhouse-pin.json - the full run starts it beside the build."""
    lines = [l.split() for l in open(os.path.join(inv.STEPS, step + ".txt"))
             if l.startswith("image clickhouse/clickhouse-server ")]
    if not lines:
        return []
    want = {"platform": platform_sha, "images": [lines[0][2], lines[0][6]], "ops": ops_sha}
    path = path or PIN_RESULT
    try:
        got = json.load(open(path)).get(step.split("-")[0])
    except (OSError, ValueError):
        got = None
    if got is None:
        return [f"{step} moves ClickHouse's image, and its rollback pin has no passing result ({path}; "
                "tests/clickhouse-pin/run.sh, its log .upgrade/clickhouse-pin.log)"]
    if {k: got.get(k) for k in want} != want:
        return [f"{step}'s rollback pin was proven for {got}, not this step's {want}"]
    return []


def record_proof(step, infra_sha, platform_sha):
    run_info = json.load(open(os.path.join(PROVEN, "run.json")))
    changed = ops_unchanged_since(run_info["ops"], PROVEN_PATHS)
    if changed:
        sys.exit(f"REFUSED: the ops tree changed during the run ({', '.join(changed)}) - the run proves nothing")
    # every step branch as the run started: one rewritten meanwhile (a restack in the repos the run reads) mixed the
    # states its steps proved
    if "branches" not in run_info:
        sys.exit("REFUSED: the run's run.json records no step branches - a run started before proof-start did; again")
    moved = branch_moves(run_info["branches"])
    if moved:
        sys.exit(f"REFUSED: step branches moved during the run ({'; '.join(moved)}) - the run proves nothing")
    names = step_names()
    refs = dict(zip(REPOS, run([INVENTORY, "--refs", step],
                               capture_output=True, check=True).stdout.split()))
    shas = {"infra": infra_sha, "platform": platform_sha}
    prev = dict(zip(REPOS, run([INVENTORY, "--refs",
                                names[names.index(step) - 1]], capture_output=True, check=True).stdout.split())) \
        if names.index(step) else dict.fromkeys(REPOS, "main")
    ran = step_digests(step)
    moved = {f"{full_name(n)}:{t}" for n, t in step_images(step)}
    proof = {"step": step, "run": run_info["run"], "ops": run_info["ops"], "repos": {}, "floating": floating_digests(),
             "digests": {k: d for k, d in sorted(ran.items()) if k in moved}}
    for repo in REPOS:
        now_sha = run(["git", "-C", os.path.join(OPS, "..", repo), "rev-parse", refs[repo]], capture_output=True,
                      check=True).stdout.strip()
        if now_sha != shas[repo]:
            sys.exit(f"REFUSED: {repo} {refs[repo]} moved during the step ({shas[repo][:10]} -> {now_sha[:10]})")
        if repo in step_info(step)["branches"]:
            proof["repos"][repo] = {"sha": now_sha, "own": own_change(os.path.join(OPS, "..", repo), prev[repo],
                                                                      refs[repo])}
    pin = pin_problems(step, shas["platform"], run_info["ops"])
    if pin:
        sys.exit("REFUSED: " + "; ".join(pin))
    with open(proof_path(step), "w") as f:
        json.dump(proof, f, indent=1)
    print(f"PROOF: {step} " + " ".join(f"{r}={p['sha'][:10]}" for r, p in proof["repos"].items()))


def floating_digests():
    """The floating-tag images the run copied from ten, by digest (scripts/vagrant-preload-floating.sh)."""
    path = os.path.join(WORK, "floating-digests.txt")
    if not os.path.exists(path):
        sys.exit("REFUSED: no .upgrade/floating-digests.txt - the run's build copies ten's floating-tag images")
    return dict(l.split() for l in open(path) if l.strip())


def step_images(step):
    """The images the step moves to (its `image ... => image <name> <tag>` and `+ image` lines), (name, tag) as
    written."""
    out = []
    for line in open(os.path.join(inv.STEPS, step + ".txt")):
        m = re.fullmatch(r"(?:image \S+ \S+ => |\+ )image (\S+) (\S+)", line.strip())
        if m:
            out.append((m[1], m[2]))
    return out


def step_digests(step):
    """The digests the full run's copy ran right after `step` - its pods' specs, each image pinned by digest there
    (scripts/vagrant-image-digests.sh into .upgrade/step-digests/<step>.txt): {"<name as containerd names it>:<tag>":
    digest}. A chart that pins in two keys (tag: 3.12.1@sha256:...) composes the full reference only there."""
    path = os.path.join(WORK, "step-digests", step + ".txt")
    if not os.path.exists(path):
        sys.exit(f"REFUSED: no {path} - the run records the digests its copy ran after each step")
    return {f"{full_name(n)}:{t}": d for n, t, d in (l.split() for l in open(path) if l.strip())}


def proven_digest(step, name, tag):
    """The digest the full run's copy ran name:tag with after `step` (its proof), or None."""
    try:
        proof = json.load(open(proof_path(step)))
    except (OSError, ValueError):
        return None
    return proof.get("digests", {}).get(f"{full_name(name)}:{tag}")


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


def unproven_changes(proof_ops, defaulted_steps):
    """The paths the proof covers (PROVEN_PATHS: the playbooks, every step file, the scripts and data that judge a
    step green) changed since the run's ops commit, beyond the default lines of `defaulted_steps` - a ValueError when
    those do not apply to it. Only the playbooks moved: an edited inventory, allow-list or judge proves nothing."""
    read = lambda p: run(["git", "-C", OPS, "show", f"{proof_ops}:{p}"], capture_output=True, check=True).stdout
    # a run proven after some steps' defaults were committed has them already: only the later ones apply on top
    have = {l.strip() for l in read(dflt.COMMITTED).splitlines() if l.strip() and not l.startswith("#")}
    expected = dflt.applied(read, [s for s in defaulted_steps if s not in have])
    return [p for p in ops_unchanged_since(proof_ops, PROVEN_PATHS)
            if not (p in expected and open(os.path.join(OPS, p)).read() == expected[p])]


def app_tag_problems():
    """The app tags the full run ran (the overlay's, over production's values) against infra main's: the proof covers
    production's apps only when they are the same."""
    tag = lambda values, key: (((values or {}).get(key) or {}).get("image") or {}).get("tag")
    overlay = yaml.safe_load(open(os.path.join(OPS, APP_OVERLAY)))
    infra = os.path.join(OPS, "..", "infra")
    run(["git", "-C", infra, "fetch", "-q", "origin", "main"], check=True)
    production = yaml.safe_load(run(["git", "-C", infra, "show", f"origin/main:{APP_VALUES}"], capture_output=True,
                                    check=True).stdout)
    return [f"{key}: production runs {tag(production, key)}, the full run ran {tag(overlay, key)} - promote it first, "
            "or drop the overlay's tag and prove again" for key in overlay
            if tag(overlay, key) is not None and str(tag(production, key)) != str(tag(overlay, key))]


def proof_inventory(names, step, merged, partly=False):
    """Production's inventory the floating-image check reads: as the done steps leave it - or, once the step's merges
    settled (`merged`), as the step leaves it: an image the step replaced may be gone then (the kubelet collects it).
    Between a two-repo step's merges (`partly`), what both leave in use: one the first merge replaced may be gone
    already, one the second brings is not pulled yet."""
    i = names.index(step)
    if partly:
        after = set(inv.expected(names[:i + 1]))
        return [line for line in inv.expected(names[:i]) if line in after]
    return inv.expected(names[:i + (1 if merged else 0)])


def proof_problems(step, names, repo=None, defaulted_steps=(), merged=False, partly=False, tip=None):
    """What the full run's proof says against running `step` (and merging `repo`) now. The ops tree may differ from
    the run's commit only by the default lines of `defaulted_steps`. `merged`: the step's merges settled; `partly`:
    some of them (a two-repo step between its merges)."""
    path = proof_path(step)
    if not os.path.exists(path):
        return [f"{step} has no proof from a full run (.upgrade/proven/{step}.json)"]
    proof = json.load(open(path))
    out = []
    for earlier in names[:names.index(step)]:
        p = proof_path(earlier)
        if not os.path.exists(p) or json.load(open(p))["run"] != proof["run"]:
            out.append(f"{earlier} was not proven by the same full run as {step} ({proof['run']})")
            break
    if not proof.get("floating"):
        out.append(f"{step}'s proof records no floating-tag images")
    else:
        out += floating_problems(proof["floating"], proof_inventory(names, step, merged, partly))
    out += app_tag_problems()
    try:
        changed = unproven_changes(proof["ops"], defaulted_steps)
    except ValueError as e:
        return out + [f"the committed steps' default lines do not apply to the run's ops commit: {e}"]
    if changed:
        out.append(f"changed since the full run proved {step} (ops {proof['ops'][:10]}), beyond the committed "
                   f"steps' playbook defaults: {', '.join(changed)}")
    if repo:
        d = os.path.join(OPS, "..", repo)
        # the commit the merge pushes (`tip`, read once by merge()), else the branch as it is now
        branch = tip or BRANCH + step
        run(["git", "-C", d, "fetch", "-q", "origin", "main"], check=True)
        base = merged_base(d, step)
        pushed = None if base else pushed_base(d, step, tip)
        if base:
            # merged already (an interrupted run pushed, then did not record): the change it brought, base..tag
            if run(["git", "-C", d, "merge-base", "--is-ancestor", MERGED_TAG + step, ORIGIN_MAIN]).returncode:
                out.append(f"{repo} upgrade-merged/{step} is not in origin/main")
            elif own_change(d, base, MERGED_TAG + step) != proof["repos"][repo]["own"]:
                out.append(f"{repo} upgrade-merged/{step} brought a change other than the one the full run proved")
        elif pushed is not None:
            # pushed by a run cut short before its tag: the change against the main it went onto (against origin's
            # main, the branch itself now, it was empty - refused on every retry)
            if not pushed:
                out.append(f"{repo} upgrade/{step} is in origin's main with no {MERGED_TAG}{step}, and its main before "
                           "is unknown")
            elif own_change(d, pushed, branch) != proof["repos"][repo]["own"]:
                out.append(f"{repo} {branch}, pushed with no tag, brought a change other than the one the full run "
                           "proved")
        elif run(["git", "-C", d, "merge-base", "--is-ancestor", ORIGIN_MAIN, branch]).returncode:
            out.append(f"{repo} {branch} does not contain origin/main - restack it "
                       f"(scripts/upgrade-restack-in-place.sh ../{repo})")
        elif own_change(d, ORIGIN_MAIN, branch) != proof["repos"][repo]["own"]:
            out.append(f"{repo} {branch} on origin/main is not the change the full run proved")
    return out


def image_pins(step, name, tag):
    """The digests the step's branches pin <name>:<tag> to - `<name>:<tag>@sha256:<digest>` in any file of each repo's
    upgrade/<step> (its merged tag once the branch is gone), the name as written or as containerd lists it."""
    found = set()
    for repo in step_info(step)["branches"]:
        d = os.path.join(OPS, "..", repo)
        ref = next((r for r in (BRANCH + step, MERGED_TAG + step)
                    if run(["git", "-C", d, "rev-parse", "-q", "--verify", r + "^{commit}"],
                           capture_output=True).returncode == 0), None)
        if ref is None:
            sys.exit(f"{repo} has neither upgrade/{step} nor {MERGED_TAG}{step} - its image pins unread")
        for n in {name, full_name(name)}:
            pattern = f"{n}:{tag}@sha256:".replace(".", "\\.") + "[0-9a-f]{64}"
            r = run(["git", "-C", d, "grep", "-h", "-o", "-E", "-e", pattern, ref], capture_output=True)
            if r.returncode not in (0, 1):  # 1: no match
                sys.exit(f"{repo}: git grep for {n}:{tag}'s pin failed: {r.stderr.strip()}")
            found |= set(re.findall(r"@(sha256:[0-9a-f]{64})", r.stdout or ""))
    return found


def prepull_images(step, proven=True):
    """The public images the step moves to (its `image ... => image <name> <tag>` and `+ image` lines), as containerd
    names them (one image under its short and its docker.io name pulled once), each with the digest the step's
    branches pin its tag to, or the full run's copy ran it with (a chart that pins in two keys) - the reference
    production runs (the tag alone may name another build by then) - production's own registry left out
    (registry_problems checks those are there). proven=False: the branches' pins only (the Vagrant step, before its
    proof)."""
    out, seen = [], set()
    for name, tag in step_images(step):
        if name.startswith("git.pmon.dev/") or (full_name(name), tag) in seen:
            continue
        seen.add((full_name(name), tag))
        # pinned in its branch as name:tag@digest, or composed so by its chart only (the digest the full run ran)
        pins = image_pins(step, name, tag) | ({proven_digest(step, name, tag) if proven else None} - {None})
        if len(pins) > 1:
            sys.exit(f"{name}:{tag} is pinned to {len(pins)} digests in the step's branches and the full run's copy "
                     f"({', '.join(sorted(pins))}) - which one production runs is unclear")
        out.append(f"{full_name(name)}:{tag}" + "".join(f"@{p}" for p in pins))
    return out


def registry_problems(step, status=None):
    """The step's new images from production's own registry (git.pmon.dev/schnappy), each there before the merge: the
    full run never pulls them (the copy preloads them; production's registry is beyond its fence), so a missing tag
    would first show as production's pod failing to pull - after a Recreate rollout removed the old one."""
    own, out = r"git\.pmon\.dev/schnappy/", []
    for line in open(os.path.join(inv.STEPS, step + ".txt")):
        m = re.fullmatch(rf"image {own}(\S+) \S+ => image {own}\1 (\S+)", line.strip())
        if m:
            code = (status or package_status)(m[1], m[2])
            if code != 200:
                out.append(f"git.pmon.dev/schnappy/{m[1]}:{m[2]} is not in the registry (Forgejo's package API: "
                           f"{code})")
    return out


def package_status(name, version):
    """Forgejo's answer for a container package version of schnappy (200: there), read with git's credentials."""
    cred = run(["git", "credential", "fill"], input="protocol=https\nhost=git.pmon.dev\n\n", capture_output=True,
               check=True).stdout
    fields = dict(l.split("=", 1) for l in cred.splitlines() if "=" in l)
    request = urllib.request.Request(f"https://git.pmon.dev/api/v1/packages/schnappy/container/{name}/{version}")
    request.add_header("Authorization", "Basic " + base64.b64encode(
        f"{fields['username']}:{fields['password']}".encode()).decode())
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status
    except urllib.error.HTTPError as e:
        return e.code


def merged_base(repo_dir, step):
    """The main a merged step went onto (its upgrade-merged/<step> tag's "base <sha>"), or None when not merged."""
    tag = run(["git", "-C", repo_dir, "tag", "-l", "--format=%(contents:subject)", MERGED_TAG + step],
              capture_output=True, check=True).stdout.strip()
    if not tag:
        return None
    if not tag.startswith("base "):
        sys.exit(f"{repo_dir}: upgrade-merged/{step} carries no base ({tag!r})")
    return tag.split()[1]


def pushed_base(repo_dir, step, tip=None):
    """None unless upgrade/<step>'s commit (`tip`, else the branch's) is in origin's main with no upgrade-merged/<step>
    tag (a run cut short after its push - CD may have pushed on top since); then the main it went onto as
    scripts/upgrade-merge-step.sh's take-up finds it - local main if not moved yet, else where it was before the
    fast-forward - or "" when that is unknown."""
    git = lambda *a: run(["git", "-C", repo_dir, *a], capture_output=True)
    if git("rev-parse", "-q", "--verify", f"refs/tags/{MERGED_TAG}{step}").returncode == 0:
        return None
    tip = tip or git("rev-parse", BRANCH + step).stdout.strip()
    if not tip or git("merge-base", "--is-ancestor", tip, ORIGIN_MAIN).returncode:
        return None
    main = git("rev-parse", "main").stdout.strip()
    base = main if main != tip else git("rev-parse", "main@{1}").stdout.strip()
    ok = base and base != tip and git("merge-base", "--is-ancestor", base, tip).returncode == 0
    return base if ok else ""


# ---- the phases -----------------------------------------------------------------------------------------------------

def confirm(question):
    """The operator's yes on the terminal, as the Taskfile's prompts ask it; no terminal is a no. Unbuffered binary: a
    text "r+" needs a seekable file and a terminal is none - it raised, and every question read as a no. What was typed
    before the question is discarded: input typed ahead is no answer to it."""
    try:
        with open("/dev/tty", "rb+", buffering=0) as tty:
            termios.tcflush(tty.fileno(), termios.TCIFLUSH)
            tty.write(f"{question} [y/N] ".encode())
            return tty.readline().decode(errors="replace").strip().lower() in ("y", "yes")
    except OSError:
        return False


def refuse(lines):
    if lines:
        sys.exit("REFUSED:\n" + "\n".join("  " + l for l in lines))


CLAIMED = []  # (step, phase, token) this process claimed (its start recorded): main() records its end


def ledger_for(step, phase, arg=None):
    """The phase's checks, then its claim on the step - start, written against the read the checks were made on."""
    names = step_names()
    obj, events = read_ledger()
    info = step_info(step) if step in names else None
    refuse(problems(names, step, phase, events, info, arg))
    token = f"{socket.gethostname()}:{os.getpid()}:{secrets.token_hex(4)}"
    record(step, "start", phase, *([arg] if arg else []), token, obj=obj)
    CLAIMED.append((step, phase, token))
    return names, events, info


def release(step):
    """A phase's open start closed by hand: its run was killed and cannot record its end."""
    obj, events = read_ledger()
    started = open_start([(at, e, a) for at, s, e, a in events if s == step])
    if not started:
        sys.exit(f"{step} has no open start")
    token = started[1][-1]
    host, pid = (token.split(":") + ["", ""])[:2]
    if host == socket.gethostname() and pid.isdigit() and os.path.exists(f"/proc/{pid}/cmdline") \
            and "upgrade-production" in open(f"/proc/{pid}/cmdline").read():
        sys.exit(f"REFUSED: the run that started {step}'s {started[1][0]} (pid {pid}) is alive here - stop it first")
    refuse([] if confirm(f"Nothing runs {step}'s {' '.join(started[1])} (started {started[0]:%Y-%m-%d %H:%M} UTC) "
                         "any more - close it?") else ["not confirmed"])
    record(step, "end", started[1][0], "released", token, obj=obj)


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
    ok_settled, _, seen = settled(15, last_done_out_of_sync(events),
                                  before[-1][0].split(",") if before else None)
    refuse([] if ok and ok_settled and seen else ["production is not as the done steps leave it (above)"])
    # the app set first: a begin cut short between the two writes runs again (not begun), it is not stranded
    record(step, "apps", ",".join(seen))
    record(step, "begun")


def backup(step, store):
    names, events, _ = ledger_for(step, "backup", store)
    refuse(proof_problems(step, names, defaulted_steps=defaulted(events)))
    refuse([] if ansible("playbooks/upgrade-backup.yml", "-e", f"store={store}") else [f"the {store} backup failed"])
    record(step, "backup", store)


def preview(step):
    names, events, _ = ledger_for(step, "preview")
    refuse(proof_problems(step, names, defaulted_steps=defaulted(events), merged=True))
    script = os.path.join(OPS, "scripts", "upgrade-step-playbooks.sh")
    refuse([] if run([script, "--production", "--check", step]).returncode == 0 else ["the preview failed"])
    record(step, "previewed")


def merge(step, repo):
    names, events, _ = ledger_for(step, "merge", repo)
    merged = any(s == step and e == "merged" and a[:1] == [repo] for _, s, e, a in events)
    partly = any(s == step and e == "merged" for _, s, e, _ in events)  # the step's other repo merged already
    if not merged:
        d = os.path.join(OPS, "..", repo)
        # the branch's commit, read once before its checks: the one the proof is checked against, shown, pulled for and
        # pushed - a restack between the checks and the push (another shell) no longer pushes a commit nothing checked
        tip = run(["git", "-C", d, "rev-parse", "-q", "--verify", f"{BRANCH}{step}^{{commit}}"],
                  capture_output=True).stdout.strip() or None
        refuse(proof_problems(step, names, repo, defaulted(events), partly=partly, tip=tip) + registry_problems(step))
    apps = step_apps(events, step)  # before any push: a step without its app set must not merge
    if not merged:
        if merged_base(d, step):
            # pushed and tagged by an earlier run that stopped before recording it: recorded now, not merged again
            print(f"{repo}: {step} was merged already (upgrade-merged/{step}) - recording it")
        elif pushed_base(d, step, tip):
            # pushed by an earlier run cut short before its tag (its change checked above): tagged, recorded - nothing
            # asked or pushed again
            print(f"{repo}: {step} was pushed already (no {MERGED_TAG}{step} yet) - tagging it, recording it")
            refuse([] if run([os.path.join(OPS, "scripts", "upgrade-merge-step.sh"), step, repo, "take-up"])
                   .returncode == 0 else [f"the {repo} take-up failed (above)"])
        else:
            # checked and shown against production's main: a local main behind origin's (CD pushed meanwhile) showed
            # CD's commits as the step's and refused only after the yes, the pre-pull and Tempo's flush
            local, origin = (run(["git", "-C", d, "rev-parse", r], capture_output=True, check=True).stdout.strip()
                             for r in ("main", ORIGIN_MAIN))
            refuse([] if local == origin else [f"{repo}'s main is not origin/main - git -C ../{repo} pull --ff-only "
                                               "(on main), then merge again"])
            # the state between a two-repo step's merges: checked before its first merge (the second one ends it)
            if not partly:
                order = run([os.path.join(OPS, "scripts", "upgrade-merge-order.py"), step])
                refuse([] if order.returncode == 0 else ["the state between this step's merges was never proven "
                                                         "(above)"])
            # what goes to production, shown before the yes: a step without playbook lines (PostgreSQL 18, a Scylla
            # major, Kafka) has no preview, its one-way change starts when Argo syncs this push
            print(f"{repo}: what the merge puts on production's main (upgrade/{step}):", flush=True)
            for args in (["log", "--oneline"], ["diff", "--stat"], ["diff"]):
                run(["git", "-C", d, "--no-pager", *args, f"{ORIGIN_MAIN}..{tip}"])
            refuse([] if confirm(f"Merge {repo} upgrade/{step} - the change above - into PRODUCTION's main?")
                   else ["not confirmed - nothing merged, nothing recorded"])
            # the step's public images pulled on ten first, at each of its merges (the first's may be collected by the
            # second, or be the second repo's) - a tag missing upstream stops the step with nothing more live, and its
            # rollout does not wait on a pull while the old pod is gone (a Recreate deployment, a single replica)
            images = prepull_images(step)
            if images:
                refuse([] if ansible("playbooks/upgrade-prepull.yml", "-e", "images=" + ",".join(images))
                       else ["the step's images did not pull on ten (above) - nothing merged"])
            # a step that replaces Tempo's major: what Tempo still holds in its WAL flushed to the store first (the
            # next major does not replay it) - proven by a marker trace found in the store; on ten, with its kubectl
            if repo in step_info(step)["tempo_flush"]:
                with open(os.path.join(OPS, "scripts", "tempo-flush.py")) as script:
                    # (its own waits bounded: held 30 x 2 s, stored 60 x 10 s, each query 30 s at most)
                    flushed = remote(TEN, "python3 -", script.read(), timeout=3600, capture=False).returncode == 0
                refuse([] if flushed
                       else ["Tempo's flush did not complete (above) - nothing merged"])
            # the claim read again right before the push: released by hand during the yes, the pre-pull or the flush
            # (the run looked dead), the change would go live under no claim - the next record refuses only after it
            refuse([f"{p} - nothing merged" for p in claim_problems(step, read_ledger()[0])])
            refuse([] if run([os.path.join(OPS, "scripts", "upgrade-merge-step.sh"), step, repo, tip]).returncode == 0
                   else [f"the {repo} merge failed (above)"])
        sha = run(["git", "-C", d, "rev-parse", MERGED_TAG + step + "^{commit}"], capture_output=True,
                  check=True).stdout.strip()
        record(step, "merged", repo, sha)
    # nothing out of sync after a merge (as the Vagrant run's first wait): a step's argo-out-of-sync apps are allowed
    # only after its playbooks
    info = step_info(step)
    ok, revs, _ = settled(info["settle"], [], apps)
    refuse([] if ok else [f"Argo did not settle on the {repo} merge - the step stops here (its abort line)"])
    record(step, "settled", repo, revs[URLS[repo]])
    # a barman-after-merge step (PostgreSQL 18): its base backup as soon as the merge that makes the new major live
    # settled (47's infra merge; its platform merge renders nothing new) - until one exists the new major has no point
    # to recover to (PostgreSQL 17's backups do not replay into 18), and the operator's pause between the merges or a
    # failed second settle would leave it so. At the step's last merge whatever runs; once. Declined or failed here,
    # done's first call takes it.
    if info["base_backup_after_merge"] and not any(s == step and e == "base-backup" for _, s, e, _ in events) \
            and (repo == info["branches"][-1] or cluster_runs(postgres_target(step))):
        if not confirm(f"Step {step}'s merges settled: take PRODUCTION's Postgres base backup now "
                       "(postgres-base-backup.yml)?"):
            print("no base backup now - deploy:upgrade:done takes it at its first call")
        elif ansible("playbooks/postgres-base-backup.yml", "-e", f"pg_major={inv.pg_major(step)}"):
            record(step, "base-backup")
        else:
            print("the base backup failed (above) - deploy:upgrade:done takes it again at its first call")


def postgres_target(step):
    """The PostgreSQL image a barman-after-merge step moves production's cluster to (its image line), name:tag."""
    for line in open(os.path.join(inv.STEPS, step + ".txt")):
        m = re.fullmatch(r"image \S+ \S+ => image (\S+/postgresql) (\S+)", line.strip())
        if m:
            return f"{m[1]}:{m[2]}"
    sys.exit(f"{step}: barman-after-merge with no PostgreSQL image line - which merge makes it live is unknown")


def cluster_runs(image):
    """Whether production's Postgres cluster runs `image` (name:tag, its digest aside) - CNPG's status."""
    now = ten("kubectl -n schnappy-production get clusters.postgresql.cnpg.io schnappy-production-postgres "
              "-o jsonpath={.status.image}").stdout.strip()
    return now == image or now.startswith(image + "@")


def playbooks(step):
    names, events, _ = ledger_for(step, "playbooks")
    refuse(proof_problems(step, names, defaulted_steps=defaulted(events), merged=True))
    script = os.path.join(OPS, "scripts", "upgrade-step-playbooks.sh")
    refuse([] if run([script, "--production", step]).returncode == 0 else ["the playbook lines failed (above)"])
    record(step, "playbooks")


CHECK_MINUTES = 15


def defaults(step):
    """The step's default lines into ops main, committed and pushed - nothing else may be in the commit. A run cut
    short after its commit (the push failed) or after its push (the ledger not written) is taken up where it stopped:
    the commit, found by its message as the last to touch the committed-steps record, pushed if it is not yet."""
    names, events, _ = ledger_for(step, "defaults")
    git = lambda *a: run(["git", "-C", OPS, *a], capture_output=True, check=True).stdout.strip()
    message = f"upgrade {step}: its playbook defaults (in production)"
    run(["git", "-C", OPS, "fetch", "-q", "origin", "main"], check=True)
    branch, dirty = git("rev-parse", "--abbrev-ref", "HEAD"), git("status", "--porcelain")
    refuse(([] if branch == "main" else ["ops is not on main"])
           + ([f"ops has uncommitted changes:\n{dirty}"] if dirty else []))
    last = git("log", "-1", "--format=%H %s", "--", dflt.COMMITTED).split(" ", 1)
    if len(last) == 2 and last[1] == message:
        sha = last[0]
        refuse(proof_problems(step, names, defaulted_steps=defaulted(events) + [step], merged=True)
               + ([] if git("rev-parse", "HEAD") == sha else [f"ops main is past the step's commit {sha[:10]}"]))
        if run(["git", "-C", OPS, "merge-base", "--is-ancestor", sha, ORIGIN_MAIN]).returncode:
            refuse([] if git("rev-parse", f"{sha}^") == git("rev-parse", ORIGIN_MAIN)
                   else [f"the step's commit {sha[:10]} is not on origin/main's head"])
            run(["git", "-C", OPS, "push", "-q", "origin", "main"], check=True)
        print(f"{step}: its defaults committed already ({sha[:10]}) - recorded")
        record(step, "defaults", sha)
        return
    refuse(proof_problems(step, names, defaulted_steps=defaulted(events), merged=True)
           + ([] if git("rev-parse", "HEAD") == git("rev-parse", ORIGIN_MAIN) else ["ops is not at origin/main"]))
    refuse([] if run([os.path.join(OPS, "scripts", "upgrade-defaults.py"), "--apply", step]).returncode == 0
           else ["the default lines did not apply (above)"])
    paths = sorted({p for p, _, _ in dflt.default_lines(step)} | {dflt.COMMITTED})
    run(["git", "-C", OPS, "commit", "-q", "-m", message, "--", *paths], check=True)
    run(["git", "-C", OPS, "push", "-q", "origin", "main"], check=True)
    record(step, "defaults", git("rev-parse", "HEAD"))


def check(step, since=None, deciding=False):
    """ten as the done steps and this one leave it, Argo settled, the step's app set kept. With `since` (a time - the
    first green check's): no container restarted at or after it, however long ago that was. `deciding` (the call that
    ends a step): the restart history judged and recorded."""
    if step not in step_names():
        sys.exit(f"REFUSED: no step {step}")
    _, events = read_ledger()
    ok = inventory_check(sorted(set(applied_steps(events)) | {step}))
    apps = step_apps(events, step) if any(s == step and e == "apps" for _, s, e, _ in events) else None
    info = step_info(step)
    ok_settled, _, _ = settled(CHECK_MINUTES, info["out_of_sync"], apps, step if deciding else None,
                               info["restarts_expected"], since)
    return ok and ok_settled


def done(step):
    names, events, info = ledger_for(step, "done")
    # what it checks and what its first call runs (an ACME issuance, a base backup) must be what the full run proved
    refuse(proof_problems(step, names, defaulted_steps=defaulted(events), merged=True))
    # by ten's clock, the one the first green check was recorded by: this machine's, ahead, would end the soak early
    checked, left = soak_state(events, step, info["soak"], ten_clock())
    if checked is not None and left > 0:
        refuse([f"soaking: {info['soak']} minutes from the first green check at {checked:%H:%M} UTC - "
                f"{left / 60:.0f} left"])
    # the first check of a cert-renew or barman-check step changes production: the operator's yes first (a base backup
    # its merge took already is not taken again)
    base_backup = info["base_backup"] and not any(s == step and e == "base-backup" for _, s, e, _ in events)
    changes = (["a throwaway certificate through production's ACME solver (acme-check.yml)"] if info["acme"] else []) \
        + (["a Postgres base backup (postgres-base-backup.yml)"] if base_backup else [])
    if checked is None and changes:
        refuse([] if confirm(f"Step {step}'s first check changes PRODUCTION: {'; '.join(changes)} - run it?")
               else ["not confirmed - nothing run, nothing recorded"])
    if checked is None and info["acme"]:
        refuse([] if ansible("playbooks/acme-check.yml") else ["ACME issuance through production's solver failed"])
    if checked is None and base_backup:
        refuse([] if ansible("playbooks/postgres-base-backup.yml", "-e", f"pg_major={inv.pg_major(step)}")
               else ["no fresh Postgres base backup (above)"])
        # recorded: a red check later starts the soak again, and its next first call does not take another
        record(step, "base-backup")
    # where the restarts are judged from, read before the first check by ten's clock (the restarts' times are its):
    # this machine's, after the check, let a restart as the check ran, or within the clocks' skew, slip past the
    # deciding check
    started = ten_now() if checked is None else None
    # after the soak: no container may have restarted since the first green check began
    green = check(step, (checked_since(events, step) or checked) if checked is not None else None,
                  deciding=checked is not None)
    if checked is None:
        refuse([] if green else ["not green - nothing recorded (fix, or the step's abort line)"])
        # the soak from now, ten's time after the check (it ran up to CHECK_MINUTES - timed from its start, the soak ran
        # short by it); the restarts from its start
        record(step, "checked", f"since={started}", at=ten_now())
        print(f"the soak runs {info['soak']} minutes - deploy:upgrade:done again after it")
        return
    if not green:
        record(step, "check-failed")
        refuse(["red after the soak began (a restart since the first green check counts) - the soak starts again "
                "from the next green check"])
    record(step, "done")


def phases(info):
    """A step's phases in their order: (phase, its argument, the ledger mark that ends it)."""
    out = [("begin", None, ("begun", None)), *(("backup", s, ("backup", s)) for s in info["wave0"])]
    out += [("merge", r, ("settled", r)) for r in info["branches"]]
    out += [("preview", None, ("previewed", None))] if info["playbooks"] else []
    out += [("playbooks", None, ("playbooks", None))] if info["playbooks"] else []
    out += [("defaults", None, ("defaults", None))] if info["defaults"] else []
    return out + [("done", None, ("done", None))]


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
    have = {(e, a[0] if a and e in ("backup", "settled") else None) for _, s, e, a in events if s == pending}
    for phase, arg, mark in phases(info):
        if mark not in have:
            p = problems(names, pending, phase, events, info, arg)
            print(f"next: {pending} {phase}{' ' + arg if arg else ''}" + (f" - {'; '.join(p)}" if p else ""))
            if phase == "done":
                checked, left = soak_state(events, pending, info["soak"], ten_clock())
                if checked is not None:
                    print(f"  soaking since {checked:%H:%M} UTC, {left / 60:.0f} of {info['soak']} minutes left")
            break


def main():
    a = sys.argv[1:]
    actions = {("init", 0): init, ("status", 0): status, ("proof-start", 0): proof_start, ("release", 1): release,
               ("begin", 1): begin, ("preview", 1): preview, ("playbooks", 1): playbooks, ("done", 1): done,
               ("defaults", 1): defaults,
               ("backup", 2): backup, ("merge", 2): merge, ("record-proof", 3): record_proof,
               ("prepull-images", 1): lambda step: print(",".join(prepull_images(step, proven=False))),
               ("settle-values", 0): lambda: print(f"-e restart_quiet={SETTLE_QUIET} -e stable_polls={SETTLE_STABLE} "
                                                   f"-e poll_seconds={SETTLE_POLL}")}
    if a[:1] == ["check"] and len(a) == 2:
        sys.exit(0 if check(a[1]) else 1)
    fn = actions.get((a[0] if a else "", len(a) - 1))
    if fn is None:
        sys.exit(__doc__)
    if a[0] == "merge" and a[2] not in REPOS:
        sys.exit("merge <step> <infra|platform>")
    result, reason = "failed", None
    try:
        fn(*a[1:])
        result = "passed"
    except SystemExit as e:
        result = "passed" if e.code in (None, 0) else "failed"
        reason = e.code if isinstance(e.code, str) else None
        raise
    finally:
        # an end that cannot be written fails the run, whatever the phase's result (the next start then refuses on the
        # open claim); a claim released meanwhile has its end written already
        for step, phase, token in CLAIMED:
            obj = read_ledger()[0]
            lost = claim_problems(step, obj)
            if lost:
                print(f"{lost[0]} - its end not recorded")
                continue
            try:
                record(step, "end", phase, result, token, obj=obj)
            except SystemExit:
                if reason:  # the write's failure becomes the exit: the phase's own reason said first
                    print(reason, file=sys.stderr)
                raise


if __name__ == "__main__":
    main()
