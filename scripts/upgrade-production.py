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
       scripts/upgrade-production.py abort <step>           (the step undone by its abort line, its merges reverted:
                                                             recorded aborted - it starts again from its begin)
       scripts/upgrade-production.py begin|preview|playbooks|defaults|done <step>
       scripts/upgrade-production.py backup <step> <store>
       scripts/upgrade-production.py merge <step> <infra|platform>
       scripts/upgrade-production.py check <step>              (read-only: as `done` checks, nothing recorded)
       scripts/upgrade-production.py resume-from [<step>]    (the step a full run starts from: production's first not
                                                             done, read-only - or the one given)
       scripts/upgrade-production.py proof-start [<step>]   (the run's record; its start, the first step by default)
       scripts/upgrade-production.py proof-complete         (the run's proofs marked complete: its last act)
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
import signal
import subprocess
import socket
import sys
import tempfile
import termios
import traceback
import urllib.error
import urllib.request

import yaml

OPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEN = "sm@192.168.11.2"
# the ledger's times, ten's clock's and this machine's alike: UTC to the second
TIME_FORMAT = "%Y-%m-%dT%H:%M:%SZ"
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
# what may land on infra's or platform's main after a full run without it proving it again: what renders nothing for
# production - CD's deploys of the test environment, CI's own files, docs, a chart's unit tests (a merged step's own
# commits aside)
MAIN_UNRENDERED = (r"^clusters/production/schnappy-test-apps/values\.yaml$", r"^\.woodpecker/", r"\.md$",
                   r"^helm/[^/]+/tests/")


def _load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, path)
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, loader))
    loader.exec_module(module)
    return module


inv = _load("upgrade_expected_inventory", INVENTORY)
dflt = _load("upgrade_defaults", os.path.join(OPS, "scripts", "upgrade-defaults.py"))


def ansible_now():
    """The Ansible installed here: ansible-core, the ansible package, the pinned collections' versions."""
    av = _load("ansible_versions", os.path.join(OPS, "scripts", "ansible-versions.py"))
    return av.versions(os.path.join(OPS, "deploy", "ansible"))


def ansible_pinned():
    """The Ansible requirements.txt and requirements.yml pin."""
    av = _load("ansible_versions", os.path.join(OPS, "scripts", "ansible-versions.py"))
    return av.pinned(os.path.join(OPS, "deploy", "ansible"))


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
            "scylla_backup": "scylla-backup-check" in flags,
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


def current(events):
    """The ledger's events as they count: a step aborted (deploy:upgrade:abort - its abort line done, its merges
    reverted) starts again from its begin, its events up to that abort no longer counted (the ledger keeps them)."""
    last = {s: i for i, (_, s, e, _) in enumerate(events) if e == "aborted"}
    return [ev for i, ev in enumerate(events) if i > last.get(ev[1], -1)]


# the most a wave0 backup and a preview may age before the one-way change they stand for goes live (a merge, the
# playbooks): an older backup misses that much data on a restore, an older preview read another cluster
FRESH_HOURS = 6


def problems(names, step, phase, events, info, arg=None, now=None):
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
    if phase == "abort":
        return []
    backed = {a[0] for _, e, a in mine if e == "backup"}
    settled = {a[0] for _, e, a in mine if e == "settled"}
    now = now or datetime.datetime.now(datetime.timezone.utc)
    last = lambda kind, a0=None: max((at for at, e, a in mine if e == kind and (a0 is None or a[:1] == [a0])), default=None)
    stale = lambda at, what: [f"{what} taken {(now - at).total_seconds() / 3600:.1f} h ago - more than {FRESH_HOURS} h "
                              "before the change: take it again"] if at and now - at > datetime.timedelta(hours=FRESH_HOURS) else []
    stale_backups = [p for s_ in info["wave0"] for p in stale(last("backup", s_), f"the {s_} backup")]
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
            + ([f"{arg} is merged and settled already"] if arg in settled else []) + stale_backups
    unsettled = [r for r in info["branches"] if r not in settled]
    out += [f"not merged and settled yet: {', '.join(unsettled)} (deploy:upgrade:merge)"] if unsettled else []
    # the preview after the merges: a step's playbooks read the cluster the merge leaves (istiod at the target, ...)
    if phase == "preview":
        return out + ([] if info["playbooks"] else [f"{step} has no playbook lines"])
    if phase == "playbooks":
        if not info["playbooks"]:
            return out + [f"{step} has no playbook lines"]
        return out + (["not previewed (deploy:upgrade:preview)"] if "previewed" not in kinds else []) \
            + (["its playbook lines ran already"] if "playbooks" in kinds else []) \
            + stale_backups + stale(last("previewed"), "the preview")
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


def resume_from(events, names=None):
    """The first step production has not done: where a full run starts, its copy built as the steps before it left
    production (`events`: the ledger's, None for no ledger - nothing done). Every step done: nothing to run."""
    names = names or step_names()
    finished = set(applied_steps(events or []))
    left = [n for n in names if n not in finished]
    if not left:
        sys.exit("every step is done in production - no full run to start")
    return left[0]


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


def read_ledger(missing_ok=False):
    """The ledger (its object, its events) - (None, None) for none when `missing_ok`."""
    out = ten(f"kubectl -n {LEDGER_NAMESPACE} get configmap {LEDGER_NAME} -o json", check=False)
    if out.returncode:
        if "NotFound" in out.stderr:
            if missing_ok:
                return None, None
            sys.exit("no ledger on ten - task deploy:upgrade:ledger-init")
        sys.exit(f"reading the ledger: {out.stderr.strip()}")
    obj = json.loads(out.stdout)
    return obj, parse_events(obj.get("data", {}).get("events", ""))


def ten_now():
    """ten's clock, UTC, as the ledger writes times: the pods' restart times are its."""
    at = ten(f"date -u +{TIME_FORMAT}").stdout.strip()
    if not re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", at):
        sys.exit(f"ten's clock answered {at!r}")
    return at


def ten_clock():
    """ten_now() as a time."""
    return datetime.datetime.strptime(ten_now(), TIME_FORMAT).replace(tzinfo=datetime.timezone.utc)


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


class Interrupted(BaseException):
    """A signal while the phase's work ran on ten or the Pis (host_work): that work may still run there - Ansible's
    tasks go over pipelined ssh, which signals no remote command, and a detached copy runs on by design. main() leaves
    the phase's start open: the next phase refuses until nothing runs there and the start is released."""


def host_work(cmd, **kw):
    """A phase's work on ten or the Pis (ansible-playbook, the step's playbook lines, the merge script), run to its own
    end: a Ctrl-C or a TERM does not kill it mid-way - subprocess KILLed ansible-playbook a quarter second after one,
    its remote tasks running on. A Ctrl-C reaches it with this process (the terminal's process group: ansible-playbook
    ends its own run); the signal is kept, and once it ended the phase ends Interrupted."""
    got = []
    kept = {s: signal.signal(s, lambda n, _f: got.append(n)) for s in (signal.SIGINT, signal.SIGTERM)}
    try:
        out = subprocess.run(cmd, text=True, **kw)
    finally:
        for s, h in kept.items():
            signal.signal(s, h)
    if got:
        raise Interrupted(signal.Signals(got[0]).name)
    return out


class LedgerConflict(Exception):
    """A ledger write kubectl refused on a Conflict: the ledger changed since its read, nothing written. main() ends
    the run with its message."""


def record(step, event, *args, obj=None, at=None):
    """Append one event - kubectl replace with the read resourceVersion (`obj`'s, when given: the read a decision was
    made on): a concurrent change refuses. `at`: the event's time (now, by this machine's clock, without)."""
    obj = obj if obj is not None else read_ledger()[0]
    # a run whose claim on the step was closed meanwhile (released by hand, the run alive) records nothing more: its
    # events would land in whatever claimed the step after
    lost = claim_problems(step, obj)
    if lost:
        sys.exit(f"REFUSED: {lost[0]} - {event} not recorded")
    at = at or datetime.datetime.now(datetime.timezone.utc).strftime(TIME_FORMAT)
    line = " ".join((at, step, event, *args))
    obj.setdefault("data", {})["events"] = (obj["data"].get("events", "").rstrip("\n") + "\n" + line).lstrip("\n")
    out = ten("kubectl replace -f -", stdin=json.dumps(obj), check=False)
    if out.returncode and ("Conflict" in out.stderr or "has been modified" in out.stderr):
        raise LedgerConflict(f"REFUSED: the ledger changed since it was read (another phase at work?): "
                             f"{out.stderr.strip()}")
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
        fetch_main(d)
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
        cmd += f" --restarted-since {restarted_since.strftime(TIME_FORMAT)}"
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
    """own_change's hash of a `git diff -U0 --binary`: every line but the hunks' positions (@@'s numbers) and the
    files' blob names (index ...), which a moved main changes for the same change - the file headers, modes, renames,
    each hunk's section heading (git's function context: the same lines under another YAML key are another change),
    the changed lines and a binary file's patch all count."""
    h = hashlib.sha256()
    for line in diff.splitlines():
        if line.startswith("@@"):
            line = "@@" + line.split("@@", 2)[2] if line.count("@@") >= 2 else "@@"
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


def proof_start(from_step=None):
    """The run's record (run.json): the ops commit, its start, every step branch, and the step it starts from - the
    first step production has not done (resume-from): its copy is built as the steps before it left production, and
    those count by production's ledger, not by this run. The tree's committed playbook defaults must then be exactly
    those steps' (production commits a step's before its done): the copy builds from them."""
    names = step_names()
    from_step = from_step or names[0]
    if from_step not in names:
        sys.exit(f"REFUSED: no step {from_step}")
    dirty = run(["git", "-C", OPS, "status", "--porcelain", "--", *PROVEN_PATHS], capture_output=True,
                check=True).stdout
    if dirty.strip():
        sys.exit("REFUSED: the ops tree is not committed - a full run proves a commit:\n" + dirty)
    read = lambda p: open(os.path.join(OPS, p)).read()
    with_lines = [s for s in names if dflt.default_lines(s)]
    try:
        left = dflt.pending(read)
    except ValueError as e:
        sys.exit(f"REFUSED: {e}")
    committed = [s for s in with_lines if s not in left]
    before = [s for s in with_lines if names.index(s) < names.index(from_step)]
    if committed != before:
        sys.exit(f"REFUSED: a run from {from_step} builds production as the steps before it left it - their playbook "
                 f"defaults committed ({', '.join(before) or 'none'}), the tree has {', '.join(committed) or 'none'}")
    # the Ansible it runs on: the pinned set installed (deploy:install), recorded - production's phases run on the same
    installed = ansible_now()
    if installed != ansible_pinned():
        sys.exit(f"REFUSED: the Ansible installed is not the pinned one ({installed}) - task deploy:install")
    # the main each repo's mirror takes (local main): production's, as the run starts - recorded, production's main
    # judged against it at every phase
    mains = {}
    for repo in REPOS:
        d = os.path.join(OPS, "..", repo)
        fetch_main(d)
        local, origin = (run(["git", "-C", d, "rev-parse", r], capture_output=True, check=True).stdout.strip()
                         for r in ("main", ORIGIN_MAIN))
        if local != origin:
            sys.exit(f"REFUSED: {repo}'s main is not origin/main - the run mirrors local main, production runs "
                     f"origin's (git -C ../{repo} pull --ff-only, or push)")
        mains[repo] = local
    head = run(["git", "-C", OPS, "rev-parse", "HEAD"], capture_output=True, check=True).stdout.strip()
    os.makedirs(PROVEN, exist_ok=True)
    started = datetime.datetime.now(datetime.timezone.utc).strftime(TIME_FORMAT)
    write_json(os.path.join(PROVEN, "run.json"), {"ops": head, "run": started, "from": from_step, "main": mains,
                                                  "ansible": installed, "branches": branch_shas()})
    print(f"PROOF: run {started} of ops {head[:10]} from {from_step}")


def proof_complete():
    """The run's proofs marked complete - test:upgrade:full's last act, after every step and the backups restored at
    its end: a run that failed there, or stopped at a step, leaves its proofs unmarked, and production refuses them."""
    path = os.path.join(PROVEN, "run.json")
    if not os.path.exists(path):
        sys.exit("REFUSED: no run started (proof-start) - nothing to mark complete")
    run_id = json.load(open(path))["run"]
    marked = []
    for name in sorted(os.listdir(PROVEN)):
        if not name.endswith(".json") or name == "run.json":
            continue
        proof = json.load(open(os.path.join(PROVEN, name)))
        if proof.get("run") == run_id:
            write_json(os.path.join(PROVEN, name), dict(proof, complete=True), indent=1)
            marked.append(proof["step"])
    print(f"PROOF: run {run_id} complete - {len(marked)} steps: {', '.join(marked) or 'none'}")


def branch_shas():
    """Every step branch (upgrade/*) of infra and platform, its commit - proof-start records them for the run."""
    out = {}
    for repo in REPOS:
        refs = run(["git", "-C", os.path.join(OPS, "..", repo), "for-each-ref",
                    "--format=%(refname:short) %(objectname)", "refs/heads/upgrade/"], capture_output=True,
                   check=True).stdout
        out[repo] = dict(map(str.split, refs.splitlines()))
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


def fetch_main(d):
    """origin's main and the merged steps' tags (scripts/upgrade-merge-step.sh pushes each): a clone that never ran a
    merge - another controller's - knows what production merged."""
    run(["git", "-C", d, "fetch", "-q", "origin", "main", "refs/tags/upgrade-merged/*:refs/tags/upgrade-merged/*"],
        check=True)


def write_json(path, obj, **kw):
    """The file whole or not at all: written beside it, then moved over it - a stop or a full disk mid-write left a
    truncated proof in place (production's merge then read no JSON)."""
    fd, part = tempfile.mkstemp(dir=os.path.dirname(path), prefix="." + os.path.basename(path) + ".")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(obj, f, **kw)
        os.chmod(part, 0o644)
        os.replace(part, path)
    except BaseException:
        os.unlink(part)
        raise


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
    proof = {"step": step, "run": run_info["run"], "from": run_info.get("from", names[0]), "ops": run_info["ops"],
             "main": run_info.get("main"), "ansible": run_info.get("ansible"),
             "repos": {}, "floating": floating_digests(),
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
    write_json(proof_path(step), proof, indent=1)
    print(f"PROOF: {step} " + " ".join(f"{r}={p['sha'][:10]}" for r, p in proof["repos"].items()))


def floating_digests():
    """The floating-tag images the run copied from ten, by digest (scripts/vagrant-preload-floating.sh)."""
    path = os.path.join(WORK, "floating-digests.txt")
    if not os.path.exists(path):
        sys.exit("REFUSED: no .upgrade/floating-digests.txt - the run's build copies ten's floating-tag images")
    with open(path) as f:
        return dict(map(str.split, filter(str.strip, f)))


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
    out = {}
    for n, t, d in (l.split() for l in open(path) if l.strip()):
        key = f"{full_name(n)}:{t}"
        if out.get(key, d) != d:  # two builds of one tag running: which one production would run is unclear
            sys.exit(f"REFUSED: the copy ran {key} as two builds after {step} ({out[key][:19]}..., {d[:19]}...)")
        out[key] = d
    return out


def running_digest_problems(step, pods=None):
    """The step's images as production runs them - each container's imageID - against the builds the full run's copy
    ran them with (its proof's digests): another build under the same tag (rebuilt upstream, pulled by tag at a
    rollout) is named. `pods`: kubectl's get pods -A -o json (read on ten without)."""
    try:
        proven = json.load(open(proof_path(step))).get("digests") or {}
    except (OSError, ValueError):
        return [f"{step}'s proof not read - its images' builds not judged"]
    if not proven:
        return []
    if pods is None:
        pods = json.loads(ten("kubectl get pods -A -o json --request-timeout=60s").stdout)
    out = set()
    for o in pods.get("items", []):
        status = o.get("status") or {}
        running = {s.get("name"): s.get("imageID") or "" for s in status.get("containerStatuses", [])
                   + status.get("initContainerStatuses", [])}
        for c in o["spec"].get("containers", []) + o["spec"].get("initContainers", []):
            ref = c["image"].split("@")[0]
            name, tag = ref.rsplit(":", 1) if ":" in ref.split("/")[-1] else (ref, "latest")
            want = proven.get(f"{full_name(name)}:{tag}")
            got = running.get(c.get("name"), "").partition("@")[2]
            if want and got and got != want:
                out.add(f"{name}:{tag} runs {got[:19]}..., the full run ran {want[:19]}... "
                        f"({o['metadata']['namespace']}/{o['metadata']['name']})")
    return sorted(out)


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
    fetch_main(infra)
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


def main_problems(proof):
    """Production's main against the one the full run mirrored (the proof's): every commit since it a merged step's own
    (in an upgrade-merged tag) or one that renders nothing for production (MAIN_UNRENDERED) - anything else runs a base
    no full run rendered: refused, named, a new run (from where production stands) proves it."""
    if not proof.get("main"):
        return ["the full run recorded no main it mirrored - prove again"]
    out = []
    for repo in REPOS:
        d = os.path.join(OPS, "..", repo)
        git = lambda *a: run(["git", "-C", d, *a], capture_output=True, check=True).stdout
        fetch_main(d)
        base = proof["main"].get(repo)
        if not base or run(["git", "-C", d, "merge-base", "--is-ancestor", base, ORIGIN_MAIN]).returncode:
            out.append(f"{repo}: origin/main does not contain the main the full run mirrored ({(base or 'none')[:10]})")
            continue
        tags = git("for-each-ref", "--format=%(refname)", "refs/tags/" + MERGED_TAG).split()
        stepwise = set(git("rev-list", *tags, "^" + base).split()) if tags else set()
        for commit in git("rev-list", "--reverse", f"{base}..{ORIGIN_MAIN}").split():
            if commit in stepwise:
                continue
            files = git("diff-tree", "--no-commit-id", "--name-only", "-r", commit).split()
            rendered = [p for p in files if not any(re.search(r, p) for r in MAIN_UNRENDERED)]
            if rendered:
                subject = git("log", "-1", "--format=%s", commit).strip()
                out.append(f"{repo}: {commit[:10]} '{subject}' on origin/main since the full run changes "
                           f"{', '.join(rendered)} - production would run what no run rendered: prove again")
    return out


def proof_problems(step, names, repo=None, defaulted_steps=(), merged=False, partly=False, tip=None, done=()):
    """What the full run's proof says against running `step` (and merging `repo`) now. The ops tree may differ from
    the run's commit only by the default lines of `defaulted_steps`. `merged`: the step's merges settled; `partly`:
    some of them (a two-repo step between its merges). `done`: the steps production's ledger has done - a step before
    the run's start counts by it (the run built its copy as those left production), the rest by the same run."""
    path = proof_path(step)
    if not os.path.exists(path):
        return [f"{step} has no proof from a full run (.upgrade/proven/{step}.json)"]
    proof = json.load(open(path))
    out = []
    if not proof.get("complete"):
        out.append(f"the full run that proved {step} ({proof.get('run')}) did not complete - every step, then the "
                   "backups restored at its end (proof-complete)")
    start = proof.get("from", names[0])
    for earlier in names[:names.index(step)]:
        if start in names and names.index(earlier) < names.index(start):
            if earlier not in done:
                out.append(f"{earlier} is not done in production - the full run that proved {step} started at "
                           f"{start}, built as production after the steps before it")
                break
            continue
        p = proof_path(earlier)
        if not os.path.exists(p) or json.load(open(p))["run"] != proof["run"]:
            out.append(f"{earlier} was not proven by the same full run as {step} ({proof['run']})")
            break
    if not proof.get("floating"):
        out.append(f"{step}'s proof records no floating-tag images")
    else:
        out += floating_problems(proof["floating"], proof_inventory(names, step, merged, partly))
    out += app_tag_problems()
    out += main_problems(proof)
    # the Ansible production's phases run on: the one the run ran
    if proof.get("ansible") != ansible_now():
        out.append(f"the Ansible installed ({ansible_now()}) is not the one the full run ran "
                   f"({proof.get('ansible')}) - task deploy:install at the run's pins")
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
        fetch_main(d)
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
    fields = {}
    for line in cred.splitlines():
        key, sep, value = line.partition("=")
        if sep:
            fields[key] = value
    request = urllib.request.Request(f"https://git.pmon.dev/api/v1/packages/schnappy/container/{name}/{version}")
    # off any redirect: urllib keeps an ordinary header on one, to whatever host it names
    request.add_unredirected_header("Authorization", "Basic " + base64.b64encode(
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


def merged_live_problems(step, repos):
    """The step's merges as they went live, still on origin/main: each file a merge changed as its upgrade-merged tag
    has it. A merge reverted by its abort line left the step's later phases running on a cluster without its GitOps
    half (a re-run of merge recorded it settled); a later change to those files is refused too, named."""
    out = []
    for repo in repos:
        d = os.path.join(OPS, "..", repo)
        base = merged_base(d, step)
        if base is None:
            continue
        fetch_main(d)
        files = run(["git", "-C", d, "diff", "--name-only", base, MERGED_TAG + step], capture_output=True,
                    check=True).stdout.split()
        changed = run(["git", "-C", d, "diff", "--name-only", MERGED_TAG + step, ORIGIN_MAIN, "--", *files],
                      capture_output=True, check=True).stdout.split() if files else []
        if changed:
            out.append(f"{repo}: the step's merge is not on origin/main as it went live ({', '.join(changed)}) - "
                       f"reverted by its abort line? then task deploy:upgrade:abort STEP={step}")
    return out


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
    before the question is discarded: input typed ahead is no answer to it. SIGTTIN and SIGTTOU ignored meanwhile: moved
    to the background after the check (Ctrl-Z, bg), the read stopped it there, its claim held - ignored, the read fails
    (EIO): a no"""
    kept = {s: signal.signal(s, signal.SIG_IGN) for s in (signal.SIGTTIN, signal.SIGTTOU)}
    try:
        with open("/dev/tty", "rb+", buffering=0) as tty:
            # asked only from the terminal's foreground: from its background the flush stopped this process (SIGTTOU)
            # at the question, its claim on the step held - a no, said
            if os.tcgetpgrp(tty.fileno()) != os.getpgrp():
                print(f"{question} - not asked: this runs in its terminal's background (a no)", file=sys.stderr)
                return False
            termios.tcflush(tty.fileno(), termios.TCIFLUSH)
            tty.write(f"{question} [y/N] ".encode())
            return tty.readline().decode(errors="replace").strip().lower() in ("y", "yes")
    except (OSError, termios.error):  # termios.error is no OSError
        return False
    finally:
        for sig, handler in kept.items():
            signal.signal(sig, handler)


def refuse(lines):
    if lines:
        sys.exit("REFUSED:\n" + "\n".join("  " + l for l in lines))


CLAIMED = []  # (step, phase, token) this process claimed (its start recorded): main() records its end


def ledger_for(step, phase, arg=None):
    """The phase's checks, then its claim on the step - start, written against the read the checks were made on."""
    names = step_names()
    obj, events = read_ledger()
    events = current(events)
    info = step_info(step) if step in names else None
    refuse(problems(names, step, phase, events, info, arg))
    token = claim_token()
    record(step, "start", phase, *([arg] if arg else []), token, obj=obj)
    CLAIMED.append((step, phase, token))
    return names, events, info


def claim_token():
    """A claim's token: host:pid:nonce:process group - its end closes only its own start, and release refuses while a
    process of its group (an ansible-playbook or merge script of a run killed outright) is alive on its host."""
    return f"{socket.gethostname()}:{os.getpid()}:{secrets.token_hex(4)}:{os.getpgrp()}"


def group_alive(pgid):
    """Whether a process of process group `pgid` is alive here."""
    for d in os.listdir("/proc"):
        if d.isdigit():
            try:
                stat = open(f"/proc/{d}/stat").read()
            except OSError:
                continue
            if stat[stat.rindex(")") + 2:].split()[2] == str(pgid):
                return True
    return False


def release(step):
    """A phase's open start closed by hand: its run was killed and cannot record its end."""
    obj, events = read_ledger()
    started = open_start([(at, e, a) for at, s, e, a in events if s == step])
    if not started:
        sys.exit(f"{step} has no open start")
    token = started[1][-1]
    host, pid, _, pgid = (token.split(":") + ["", "", "", ""])[:4]
    if host == socket.gethostname() and pid.isdigit() and os.path.exists(f"/proc/{pid}/cmdline") \
            and "upgrade-production" in open(f"/proc/{pid}/cmdline").read():
        sys.exit(f"REFUSED: the run that started {step}'s {started[1][0]} (pid {pid}) is alive here - stop it first")
    # the run killed outright: its ansible-playbook or merge script, in its process group, may live on
    if host == socket.gethostname() and pgid.isdigit() and group_alive(pgid):
        sys.exit(f"REFUSED: a process of the run that started {step}'s {started[1][0]} (process group {pgid}) is alive "
                 "here - its ansible-playbook or merge script; let it end first")
    refuse([] if confirm(f"Nothing runs {step}'s {' '.join(started[1])} (started {started[0]:%Y-%m-%d %H:%M} UTC) "
                         "any more - here, and on ten and the Pis (pgrep -af 'ansible|AnsiballZ|kubeadm|upgrade' there "
                         "finds none of it) - close it?") else ["not confirmed"])
    record(step, "end", started[1][0], "released", token, obj=obj)


def abort(step):
    """The step undone by its abort line, recorded: each of its merges reverted on origin/main (checked - its files as
    before the merge), its defaults commit reverted, the operator's word that its host-side half is undone. Its merged
    tags set aside (upgrade-aborted/<step>-<time>): the step starts again from its begin - a fixed branch, a new proof,
    a fresh Wave 0 backup."""
    names, events, info = ledger_for(step, "abort")
    out = []
    for repo in info["branches"]:
        d = os.path.join(OPS, "..", repo)
        base = merged_base(d, step)
        if base is None:
            continue
        fetch_main(d)
        files = run(["git", "-C", d, "diff", "--name-only", base, MERGED_TAG + step], capture_output=True,
                    check=True).stdout.split()
        if not merged_live_problems(step, [repo]):
            out.append(f"{repo}: its merge is still live on origin/main - revert it first (its abort line)")
        elif run(["git", "-C", d, "diff", "--quiet", base, ORIGIN_MAIN, "--", *files]).returncode:
            out.append(f"{repo}: {', '.join(files)} on origin/main are neither as the merge left them nor as before it "
                       "- see what changed")
    if any(e == "defaults" for _, s, e, _ in events if s == step) and \
            step in open(os.path.join(OPS, dflt.COMMITTED)).read().split():
        out.append("its playbook defaults are committed - revert that commit on ops main first")
    refuse(out)
    refuse([] if confirm(f"{step}: its merges reverted (checked), its host-side changes undone by its abort line - "
                         "record it aborted? It then starts again from its begin.") else ["not confirmed"])
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    for repo in info["branches"]:
        d = os.path.join(OPS, "..", repo)
        if merged_base(d, step) is not None:
            run(["git", "-C", d, "tag", "-m", f"aborted {stamp}", f"upgrade-aborted/{step}-{stamp}",
                 MERGED_TAG + step], check=True)
            run(["git", "-C", d, "tag", "-d", MERGED_TAG + step], check=True, capture_output=True)
    record(step, "aborted")


def ansible(*args):
    return host_work(["venv/bin/ansible-playbook", "-i", "inventory/production.yml", *args],
                     cwd=os.path.join(OPS, "deploy", "ansible"), stdin=subprocess.DEVNULL).returncode == 0


def last_done_out_of_sync(events):
    done = applied_steps(events)
    return step_info(done[-1])["out_of_sync"] if done and done[-1] != BEFORE_LEDGER else []


def vault_login_problems():
    """Production's External Secrets logging into Vault the way the copy proves every step on: without the old reviewer
    token (a non-expiring token of its own account in Vault's config) - task deploy:vault-eso deletes it once the
    login without it is proven."""
    out = ten("kubectl -n external-secrets get secret vault-token-reviewer --ignore-not-found -o name", check=False)
    if out.returncode:
        return [f"production's Vault login not read: {out.stderr.strip()}"]
    if out.stdout.strip():
        return ["production's External Secrets still logs into Vault with the old reviewer token "
                "(external-secrets/vault-token-reviewer) - the copy proves every step without it: task deploy:vault-eso "
                "first"]
    return []


def begin(step):
    names, events, _ = ledger_for(step, "begin")
    refuse(proof_problems(step, names, defaulted_steps=defaulted(events), done=applied_steps(events))
           + vault_login_problems())
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
    refuse(proof_problems(step, names, defaulted_steps=defaulted(events), done=applied_steps(events)))
    # asked here, not only by the Taskfile's prompt (task -y skips that; this script runs alone too)
    refuse([] if confirm(f"Back up {store} on PRODUCTION into the Pi store for {step}"
                         + (" - Kafka is down while its volume is copied" if store == "kafka" else "") + "?")
           else ["not confirmed"])
    refuse([] if ansible("playbooks/upgrade-backup.yml", "-e", f"store={store}") else [f"the {store} backup failed"])
    record(step, "backup", store)


def preview(step):
    names, events, info = ledger_for(step, "preview")
    refuse(proof_problems(step, names, defaulted_steps=defaulted(events), merged=True,
                          done=applied_steps(events)) + merged_live_problems(step, info["branches"]))
    script = os.path.join(OPS, "scripts", "upgrade-step-playbooks.sh")
    refuse([] if host_work([script, "--production", "--check", step]).returncode == 0 else ["the preview failed"])
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
        refuse(proof_problems(step, names, repo, defaulted(events), partly=partly, tip=tip,
                              done=applied_steps(events)) + registry_problems(step))
    apps = step_apps(events, step)  # before any push: a step without its app set must not merge
    if not merged:
        if merged_base(d, step):
            # pushed and tagged by an earlier run that stopped before recording it: recorded now, not merged again
            print(f"{repo}: {step} was merged already (upgrade-merged/{step}) - recording it")
        elif pushed_base(d, step, tip):
            # pushed by an earlier run cut short before its tag (its change checked above): tagged, recorded - nothing
            # asked or pushed again
            print(f"{repo}: {step} was pushed already (no {MERGED_TAG}{step} yet) - tagging it, recording it")
            refuse([] if host_work([os.path.join(OPS, "scripts", "upgrade-merge-step.sh"), step, repo, "take-up", tip])
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
            merge_step = [os.path.join(OPS, "scripts", "upgrade-merge-step.sh"), step, repo, tip]
            refuse([] if host_work(merge_step).returncode == 0 else [f"the {repo} merge failed (above)"])
        sha = run(["git", "-C", d, "rev-parse", MERGED_TAG + step + "^{commit}"], capture_output=True,
                  check=True).stdout.strip()
        record(step, "merged", repo, sha)
    # nothing out of sync after a merge (as the Vagrant run's first wait): a step's argo-out-of-sync apps are allowed
    # only after its playbooks
    info = step_info(step)
    refuse(merged_live_problems(step, [repo]))
    ok, revs, _ = settled(info["settle"], [], apps)
    refuse([] if ok else [f"Argo did not settle on the {repo} merge - the step stops here. An app's ComparisonError "
                          "above is a render error (the chart or its values, or a cached one hard-refreshed already): "
                          "fix the step's branch and merge again, not its abort line; otherwise its abort line"])
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
    """The PostgreSQL image a barman-after-merge step moves production's cluster to (its CNPG image line, as
    pg_major reads it), name:tag."""
    image = inv.pg_image(step)
    if image is None:
        sys.exit(f"{step}: barman-after-merge with no PostgreSQL image line - which merge makes it live is unknown")
    return f"{image[0]}:{image[1]}"


def cluster_runs(image):
    """Whether production's Postgres cluster runs `image` (name:tag, its digest aside) - CNPG's status."""
    now = ten("kubectl -n schnappy-production get clusters.postgresql.cnpg.io schnappy-production-postgres "
              "-o jsonpath={.status.image}").stdout.strip()
    return now == image or now.startswith(image + "@")


def playbooks(step):
    names, events, info = ledger_for(step, "playbooks")
    refuse(proof_problems(step, names, defaulted_steps=defaulted(events), merged=True,
                          done=applied_steps(events)) + merged_live_problems(step, info["branches"]))
    print(f"{step}'s playbook lines, against PRODUCTION (ten, the Pis):")
    for line in info["playbooks"]:
        print(f"  {line}")
    refuse([] if confirm(f"Run {step}'s playbook lines against PRODUCTION?") else ["not confirmed"])
    # a step with no branch line (Cilium, kubeadm, Argo CD by its playbook) pulls its images here, as a merge pulls a
    # merged step's: by the digests the full run ran, before anything restarts on them
    images = prepull_images(step) if not info["branches"] else []
    if images:
        refuse([] if ansible("playbooks/upgrade-prepull.yml", "-e", "images=" + ",".join(images))
               else ["the step's images did not pull on ten (above) - its playbook lines not run"])
    script = os.path.join(OPS, "scripts", "upgrade-step-playbooks.sh")
    refuse([] if host_work([script, "--production", step]).returncode == 0 else ["the playbook lines failed (above)"])
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
        # past it with later commits: fine once it is pushed (the proof check judges what changed since); not pushed,
        # its push would carry them unasked
        pushed = run(["git", "-C", OPS, "merge-base", "--is-ancestor", sha, ORIGIN_MAIN]).returncode == 0
        refuse(proof_problems(step, names, defaulted_steps=defaulted(events) + [step], merged=True,
                                 done=applied_steps(events))
               + ([] if git("rev-parse", "HEAD") == sha or pushed else [f"ops main is past the step's commit {sha[:10]}"]))
        if run(["git", "-C", OPS, "merge-base", "--is-ancestor", sha, ORIGIN_MAIN]).returncode:
            refuse([] if git("rev-parse", f"{sha}^") == git("rev-parse", ORIGIN_MAIN)
                   else [f"the step's commit {sha[:10]} is not on origin/main's head"])
            print(git("show", "--stat", "--format=%h %s", sha))
            refuse([] if confirm(f"Push {step}'s defaults commit {sha[:10]} to ops main?") else ["not confirmed"])
            run(["git", "-C", OPS, "push", "-q", "origin", "main"], check=True)
        print(f"{step}: its defaults committed already ({sha[:10]}) - recorded")
        record(step, "defaults", sha)
        return
    refuse(proof_problems(step, names, defaulted_steps=defaulted(events), merged=True, done=applied_steps(events))
           + merged_live_problems(step, step_info(step)["branches"])
           + ([] if git("rev-parse", "HEAD") == git("rev-parse", ORIGIN_MAIN) else ["ops is not at origin/main"]))
    refuse([] if run([os.path.join(OPS, "scripts", "upgrade-defaults.py"), "--apply", step]).returncode == 0
           else ["the default lines did not apply (above)"])
    paths = sorted({p for p, _, _ in dflt.default_lines(step)} | {dflt.COMMITTED})
    # shown and asked here, before anything is committed: declined, the tree as it was
    print(git("diff", "--", *paths))
    if not confirm(f"Commit {step}'s playbook defaults (above) to ops main and push them?"):
        run(["git", "-C", OPS, "checkout", "--", *paths], check=True)
        refuse(["not confirmed"])
    run(["git", "-C", OPS, "commit", "-q", "-m", message, "--", *paths], check=True)
    run(["git", "-C", OPS, "push", "-q", "origin", "main"], check=True)
    record(step, "defaults", git("rev-parse", "HEAD"))


def check(step, since=None, deciding=False):
    """ten as the done steps and this one leave it, Argo settled, the step's app set kept. With `since` (a time - the
    first green check's): no container restarted at or after it, however long ago that was. `deciding` (the call that
    ends a step): the restart history judged and recorded."""
    if step not in step_names():
        sys.exit(f"REFUSED: no step {step}")
    events = current(read_ledger()[1])
    ok = inventory_check(sorted(set(applied_steps(events)) | {step}))
    apps = step_apps(events, step) if any(s == step and e == "apps" for _, s, e, _ in events) else None
    info = step_info(step)
    ok_settled, _, _ = settled(CHECK_MINUTES, info["out_of_sync"], apps, step if deciding else None,
                               info["restarts_expected"], since)
    # the builds production runs for the step's images: the ones the full run ran
    builds = running_digest_problems(step)
    for p in builds:
        print(f"IMAGE: {p}")
    # the data paths, read only: metrics, logs, datasources, the stores, no critical alert (the full run reads the same)
    data = ansible("playbooks/production-data-check.yml")
    return ok and ok_settled and not builds and data


def done(step):
    names, events, info = ledger_for(step, "done")
    # what it checks and what its first call runs (an ACME issuance, a base backup) must be what the full run proved
    refuse(proof_problems(step, names, defaulted_steps=defaulted(events), merged=True,
                          done=applied_steps(events)) + merged_live_problems(step, info["branches"]))
    # by ten's clock, the one the first green check was recorded by: this machine's, ahead, would end the soak early
    checked, left = soak_state(events, step, info["soak"], ten_clock())
    if checked is not None and left > 0:
        refuse([f"soaking: {info['soak']} minutes from the first green check at {checked:%H:%M} UTC - "
                f"{left / 60:.0f} left"])
    # the first check of a cert-renew, barman-check or scylla-backup-check step changes production: the operator's yes
    # first (a base backup its merge took already is not taken again, nor a Scylla backup the step ran already)
    base_backup = info["base_backup"] and not any(s == step and e == "base-backup" for _, s, e, _ in events)
    scylla_backup = info["scylla_backup"] and not any(s == step and e == "scylla-backup" for _, s, e, _ in events)
    changes = (["a throwaway certificate through production's ACME solver (acme-check.yml)"] if info["acme"] else []) \
        + (["a Postgres base backup (postgres-base-backup.yml)"] if base_backup else []) \
        + (["a Scylla Manager backup of each production cluster (scylla-backup-check.yml)"] if scylla_backup else [])
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
    if checked is None and scylla_backup:
        refuse([] if ansible("playbooks/scylla-backup-check.yml")
               else ["Scylla Manager did not back up (above) - its abort line, or fix and run done again"])
        record(step, "scylla-backup")
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
    events = current(events)
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
    actions = {("init", 0): init, ("status", 0): status, ("proof-start", 0): proof_start,
               ("proof-start", 1): proof_start, ("proof-complete", 0): proof_complete, ("release", 1): release,
               ("abort", 1): abort,
               ("begin", 1): begin, ("preview", 1): preview, ("playbooks", 1): playbooks, ("done", 1): done,
               ("defaults", 1): defaults,
               ("backup", 2): backup, ("merge", 2): merge, ("record-proof", 3): record_proof,
               ("prepull-images", 1): lambda step: print(",".join(prepull_images(step, proven=False))),
               ("settle-values", 0): lambda: print(f"-e restart_quiet={SETTLE_QUIET} -e stable_polls={SETTLE_STABLE} "
                                                   f"-e poll_seconds={SETTLE_POLL}")}
    if a[:1] == ["check"] and len(a) == 2:
        sys.exit(0 if check(a[1]) else 1)
    if a[:1] == ["resume-from"] and len(a) <= 2:
        # the step a full run starts from: given (a rehearsal, or a run proving the start again), else production's
        # first not done - read-only, the ledger on ten (none yet: the first step)
        if len(a) == 2:
            if a[1] not in step_names():
                sys.exit(f"no step {a[1]}")
            print(a[1])
        else:
            print(resume_from(read_ledger(missing_ok=True)[1]))
        return
    fn = actions.get((a[0] if a else "", len(a) - 1))
    if fn is None:
        sys.exit(__doc__)
    if a[0] == "merge" and a[2] not in REPOS:
        sys.exit("merge <step> <infra|platform>")
    result, reason, left_open = "failed", None, False
    try:
        fn(*a[1:])
        result = "passed"
    except Interrupted as e:  # its work may run on there: the start stays open, said so
        left_open = True
        steps = ", ".join(sorted({s for s, _, _ in CLAIMED})) or "the step"
        print(f"INTERRUPTED ({e}) while the phase's work ran on ten or the Pis: that work may still run there - its "
              f"start left open; once nothing of it runs there: task deploy:upgrade:release STEP={steps}")
        raise SystemExit(130) from None
    except LedgerConflict as e:  # a write refused: the run ends with its message, as a refusal does
        reason = str(e)
        raise SystemExit(reason) from None
    except SystemExit as e:
        result = "passed" if e.code in (None, 0) else "failed"
        reason = e.code if isinstance(e.code, str) else None
        raise
    except BaseException:  # a defect, a Ctrl-C: its traceback kept - an end that cannot be written replaces it
        reason = traceback.format_exc().rstrip()
        raise
    finally:
        # an end that cannot be written fails the run, whatever the phase's result (the next start then refuses on the
        # open claim); a claim released meanwhile has its end written already
        for step, phase, token in ([] if left_open else CLAIMED):
            # a write refused on a Conflict (the ledger changed since its read - this run's own late write that
            # committed, another phase's record) made nothing: read again, the claim checked, written again - three
            # times at most. One that may have been made (its connection gone) is not written twice
            for attempt in range(3):
                try:
                    obj = read_ledger()[0]
                    lost = claim_problems(step, obj)
                    if lost:
                        print(f"{lost[0]} - its end not recorded")
                        break
                    record(step, "end", phase, result, token, obj=obj)
                    break
                except LedgerConflict as e:
                    if attempt < 2:
                        continue
                    if reason:
                        print(reason, file=sys.stderr)
                    raise SystemExit(str(e)) from None
                except BaseException:  # the read's or the write's failure (an exit, or an exception - a ledger's
                    # answer not JSON) becomes the run's end: the phase's own reason first
                    if reason:
                        print(reason, file=sys.stderr)
                    raise


if __name__ == "__main__":
    main()
