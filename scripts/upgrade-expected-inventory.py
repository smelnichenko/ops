#!/usr/bin/env python3
"""upgrade-expected-inventory.py - what the Vagrant copy must run after an upgrade step, and which refs make it.

A step is a file tests/ansible/upgrade/steps/NN-<name>.txt listing its inventory changes:

    # what the step upgrades and why
    <inventory line before> => <inventory line after>
    + <inventory line the step adds>
    - <inventory line the step removes>
    playbook <ops playbook> <arguments>       (a host-side change: run against the Vagrant inventory)
    argo-out-of-sync <app>                    (the step leaves this Argo app OutOfSync on purpose - its automated
                                               sync off while the step changes what its chart would put back)
    backup-check                              (the step changes Velero or its store: the runner takes a Velero backup
                                               after it - production's schedule, every pod volume; ~8 min)
    scylla-backup-check                       (the step changes Scylla Manager, ScyllaDB or the agents: the runner
                                               runs each production cluster's backup task after it, DONE with a fresh
                                               snapshot, and refuses a failed backup or repair task)
    barman-check                              (the step changes CNPG or Postgres: the runner checks WAL archiving and
                                               takes a CNPG barman base backup of Postgres after it)
    barman-after-merge                        (with barman-check: that base backup as soon as the step's merges settled,
                                               before its preview and playbook lines - production's merge takes it so;
                                               a new PostgreSQL major has no point to recover to until it exists)
    restore-check                             (the step changes CNPG, Postgres or their store: the runner recovers a
                                               copy of Postgres from a fresh backup and its WAL after it)
    sweeper-check                             (the step changes the stale PR env sweeper: the runner runs it against the
                                               copy's Vault after it - tests/ansible/upgrade/sweeper-check.yml)
    cert-renew                                (the step changes cert-manager: the runner renews every Certificate
                                               after it and wants each Ready at a higher revision)
    tempo-flush <infra|platform>              (the step replaces Tempo's major, which does not replay the old one's WAL:
                                               production's merge flushes Tempo right before merging that repo; the
                                               runner flushes before the step's push and wants a trace it pushed
                                               before the flush back after the step)
    restarts-control-plane                    (the step's own change restarts the control plane - a kubeadm upgrade:
                                               the controllers holding a leader lease restart with the API server, so
                                               the settle after it records their restarts without judging them)
    restore-undo <serverName> <image>         (the step's undo: the runner recovers that server's latest backup with
                                               that image into a side cluster after it - the seeded rows must be there;
                                               the image with its tag, CNPG reads the major from it: name:tag[@digest])
    branch <infra|platform>                   (the step's change is the branch upgrade/NN-<name> in that repo)
    clickhouse-compat <version>               (from this step on ClickHouse runs with that compatibility setting;
                                               before the first such line it has none)
    clickhouse-users <user>,<user>            (from this step on ClickHouse has exactly these users, by name; before
                                               the first such line: default,schnappy)
    wave0 <store>                             (a one-way step: that store (upgrade-backup.yml's store=) is backed up
                                               before the step changes anything, and the backup rehearsed)
    soak <minutes>                            (production waits this long between the step's first green check and
                                               the next step - scripts/upgrade-production.py; default 15)
    helm-diff <old> <new>                     (an Argo CD upgrade moving its Helm: every application rendered with both
                                               the same before the full run boots - scripts/argo-helm-diff.py)
    settle <minutes>                          (production waits this long for Argo to settle after each of the step's
                                               merges - scripts/upgrade-production.py; default 30)
    default <file>: <line> => <line>          (a playbook default the step moves - scripts/upgrade-defaults.py)
    test-image <name> <tag>                   (a test environment step: production's done wants the test environment
                                               (not in the copy) running that image)
    scrape-pool-gone <pool>                   (a Prometheus scrape pool the step removes on purpose: the metrics check
                                               excuses it from then on)
    base <arguments>                          (setup-kubeadm's arguments for a copy built after this step: what the
                                               step changed on ten that the playbook's defaults do not install - a full
                                               run from a later step, the targets build)

and a branch upgrade/NN-<name> in ../infra and/or ../platform carrying the change itself, each branch stacked on the
previous step's branch in the same repo (merged to main in this order at the production rollout).

Inventory: production's (tests/ansible/upgrade/prod-inventory.txt) with the changes of every step up to and including
the given one applied, in order. A change whose "before" line is not there at that point aborts: the step file is
stale, and applying it anyway would check nothing.

Playbooks (--playbooks): the playbook lines of the given step only. Unlike the refs they are not replayed: a Helm
install is not an "at least" operation, so replaying the Cilium 1.19.8 step after the Cilium 1.20 one would downgrade
Cilium.
The steps run in order - a skipped one fails the next inventory check, its versions missing. A version a playbook
line sets with -e becomes the playbook's default at the production rollout, not before.

Out-of-sync apps (--out-of-sync): the given step's argo-out-of-sync apps, comma-separated (empty for most steps).
After the step's playbooks the settle check lets them be OutOfSync - still Healthy, on the pushed commit; the next
step's own settle wants them Synced again.

Refs (--refs): for each repo, its highest upgrade/NN-* branch with NN up to the step's, else main - so a step that
changes only infra still mirrors platform with every earlier platform step. Aborts if a step branch does not contain
the previous one or changes nothing on it, or if the branches up to the step are not exactly the ones their step files
declare (branch lines): a missing or empty branch fell back to the previous step's, and the step went green without
its change.

Usage: scripts/upgrade-expected-inventory.py <step, e.g. 20-apt-cacher-ng>           (prints the inventory)
       scripts/upgrade-expected-inventory.py --refs <step>                (prints "<infra-ref> <platform-ref>")
       scripts/upgrade-expected-inventory.py --playbooks <step>           (prints "<playbook> <arguments>" lines)
       scripts/upgrade-expected-inventory.py --out-of-sync <step>                   (prints "<app>,<app>" or nothing)
       scripts/upgrade-expected-inventory.py --backup-check <step>                  (prints "yes" or "no")
       scripts/upgrade-expected-inventory.py --scylla-backup-check <step>           (prints "yes" or "no")
       scripts/upgrade-expected-inventory.py --barman-check <step>                  (prints "yes" or "no")
       scripts/upgrade-expected-inventory.py --barman-after-merge <step>            (prints "yes" or "no")
       scripts/upgrade-expected-inventory.py --restore-check <step>                 (prints "yes" or "no")
       scripts/upgrade-expected-inventory.py --sweeper-check <step>                 (prints "yes" or "no")
       scripts/upgrade-expected-inventory.py --cert-renew <step>                    (prints "yes" or "no")
       scripts/upgrade-expected-inventory.py --restarts-control-plane <step>        (prints "yes" or "no")
       scripts/upgrade-expected-inventory.py --tempo-flush <step>             (prints the repo before which, or nothing)
       scripts/upgrade-expected-inventory.py --restore-undo <step>        (prints "<serverName> <image>" or nothing)
       scripts/upgrade-expected-inventory.py --clickhouse-compat <step>             (prints the version or nothing)
       scripts/upgrade-expected-inventory.py --clickhouse-users <step>              (prints the users, comma-separated)
       scripts/upgrade-expected-inventory.py --wave0 <step>               (prints its wave0 stores, space-separated)
       scripts/upgrade-expected-inventory.py --pg-major <step>    (the PostgreSQL major it moves to, or nothing)
       scripts/upgrade-expected-inventory.py --base-args <step>  (every step's base arguments up to it, in order)
       scripts/upgrade-expected-inventory.py --before <step>     (the step before it, or nothing for the first)
       scripts/upgrade-expected-inventory.py --scrape-pools-gone <step>  (the pools the steps up to it removed, ',')
"""
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from typing import Optional

OPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UPGRADE = os.path.join(OPS, "tests", "ansible", "upgrade")
STEPS = os.path.join(UPGRADE, "steps")
# an inventory line naming an image: "image <name> <tag>"
IMAGE_LINE = "image "


WAVE0_STORES = ("postgres", "clickhouse", "grafana", "kafka", "gateway", "scylla", "etcd")
# the checks the runner makes after a step, a line each - --backup-check and the like print "yes" or "no" for them
FLAG_LINES = ("backup-check", "scylla-backup-check", "barman-check", "barman-after-merge", "restore-check",
              "sweeper-check", "cert-renew", "restarts-control-plane")
# the collectors that are sets - the rest are lists, in the file's order
SET_COLLECTORS = ("flags", "branches")


@dataclass
class Collectors:
    """What parse() collects from a step file's lines besides its inventory changes - each only when given."""
    playbooks: Optional[list] = None
    out_of_sync: Optional[list] = None
    flags: Optional[set] = None
    branches: Optional[set] = None
    compat: Optional[list] = None
    undo: Optional[list] = None
    users: Optional[list] = None
    wave0: Optional[list] = None
    soak: Optional[list] = None
    settle: Optional[list] = None
    tempo_flush: Optional[list] = None
    base: Optional[list] = None
    pools_gone: Optional[list] = None
    test_images: Optional[list] = None

    def add(self, kind, value):
        into = getattr(self, kind)
        if into is None:
            return
        if kind in SET_COLLECTORS:
            into.add(value)
        else:
            into.append(value)


@dataclass
class _StepFile:
    """A step file as parse() reads it: the line at hand (`where`), the inventory changes, the check lines and the
    restore-undo images seen so far."""
    collect: Collectors
    where: str = ""
    changes: list = field(default_factory=list)
    seen: set = field(default_factory=set)
    undos: list = field(default_factory=list)


def _flag(step, line):
    step.seen.add(line)
    step.collect.add("flags", line)


def _restore_undo(step, line):
    image = line.split()[2]
    # CNPG reads the major from the tag and refuses an image without one ("Can't use just the image sha as we
    # can't detect upgrades"): a pinned digest goes after the tag
    if ":" not in image.split("@")[0].rsplit("/", 1)[-1]:
        sys.exit(f"{step.where}: restore-undo image {image} has no tag - CNPG refuses it; name:tag@sha256:<digest>")
    step.undos.append((image, step.where))
    step.collect.add("undo", line[len("restore-undo "):])


def _moved(step, line):
    before, after = (x.strip() for x in line.split(" => "))
    step.changes.append((before, after, step.where))


def _added(step, line):
    step.changes.append((None, line[2:].strip(), step.where))


def _removed(step, line):
    step.changes.append((line[2:].strip(), None, step.where))


def _collect(kind, value):
    """A line that only feeds the `kind` collector, with value(line)."""
    return lambda step, line: step.collect.add(kind, value(line))


def _second(line):
    return line.split()[1]


def _rest(prefix, strip=False):
    """The line after `prefix` (stripped)."""
    return lambda line: line[len(prefix):].strip() if strip else line[len(prefix):]


def _fullmatch(pattern, flags=0):
    return lambda line: re.fullmatch(pattern, line, flags) is not None


def _starts(prefix):
    return lambda line: line.startswith(prefix)


# a step file's lines by kind, in the order a line is tried - the first kind it matches takes it; None: a line another
# script reads
STEP_LINES = (
    (_starts("playbook "), _collect("playbooks", _rest("playbook ", strip=True))),
    (lambda line: line in FLAG_LINES, _flag),
    (_fullmatch(r"restore-undo [a-z0-9-]+ \S+"), _restore_undo),
    (_fullmatch(r"clickhouse-users [a-z0-9_]+(,[a-z0-9_]+)*"), _collect("users", _second)),
    (_fullmatch(r"clickhouse-compat \d+\.\d+"), _collect("compat", _second)),
    (lambda line: line in ("branch infra", "branch platform"), _collect("branches", _rest("branch "))),
    (_fullmatch(r"wave0 (" + "|".join(WAVE0_STORES) + ")"), _collect("wave0", _second)),
    (_fullmatch(r"soak [1-9]\d*"), _collect("soak", lambda line: int(_second(line)))),
    (_fullmatch(r"helm-diff \d+\.\d+\.\d+ \d+\.\d+\.\d+"), None),  # scripts/argo-helm-diff.py
    (_fullmatch(r"settle [1-9]\d*"), _collect("settle", lambda line: int(_second(line)))),
    (_starts("default "), None),  # scripts/upgrade-defaults.py
    (_fullmatch(r"test-image [\w/.:-]+ [\w.-]+", re.ASCII), _collect("test_images", _rest("test-image "))),
    (_fullmatch(r"scrape-pool-gone [\w/.:-]+", re.ASCII), _collect("pools_gone", _second)),
    # (?a:\w) is [A-Za-z0-9_] - ASCII for the name alone, \S stays Unicode
    (_fullmatch(r"base( -e [A-Za-z_](?a:\w)*=\S+)+"), _collect("base", _rest("base "))),
    (_fullmatch(r"tempo-flush (infra|platform)"), _collect("tempo_flush", _second)),
    (_starts("argo-out-of-sync "), _collect("out_of_sync", _rest("argo-out-of-sync ", strip=True))),
    (lambda line: " => " in line, _moved),
    (_starts("+ "), _added),
    (_starts("- "), _removed),
)


def _read_line(step, line):
    for matches, take in STEP_LINES:
        if matches(line):
            if take:
                take(step, line)
            return
    sys.exit(f"{step.where}: not a step line: {line}")


def _check_step(path, step):
    if "barman-after-merge" in step.seen and "barman-check" not in step.seen:
        sys.exit(f"{os.path.basename(path)}: barman-after-merge without barman-check")
    # the undo recovers the old major with the image the step starts from - not the one it moves to, nor another
    starts = {before for before, _, _ in step.changes if before}
    for image, where in step.undos:
        name, tag = image.split("@")[0].rsplit(":", 1)
        if f"{IMAGE_LINE}{name} {tag}" not in starts:
            sys.exit(f"{where}: restore-undo image {name}:{tag} is not the image the step starts from "
                     f"(no 'image {name} {tag} =>' line)")


def parse(path, collect=None, **collectors):
    """The step file's inventory changes, [(before, after, where)] (None: a line added or removed); its other lines
    into `collect` - a Collectors, or its fields by keyword."""
    if collect is None:
        collect = Collectors(**collectors)
    elif collectors:
        raise TypeError("parse(): a Collectors or its fields by keyword, not both")
    step = _StepFile(collect)
    for n, raw in enumerate(open(path), 1):
        line = raw.strip()
        step.where = f"{os.path.basename(path)}:{n}"
        if line and not line.startswith("#"):
            _read_line(step, line)
    _check_step(path, step)
    return step.changes


def step_file(name):
    return os.path.join(STEPS, name + ".txt")


def collected(kind, names):
    """The `kind` collector (Collectors' field) filled from these steps' files, in order."""
    collect = Collectors(**{kind: set() if kind in SET_COLLECTORS else []})
    for name in names:
        parse(step_file(name), collect)
    return getattr(collect, kind)


def merged(repo, branch):
    """Whether production merged this step branch already: tagged upgrade-merged/<step> by scripts/upgrade-merge-step.sh
    (the tag, not "in main": an unmerged branch with no change of its own is in main too). The tag must be in main."""
    tag = "refs/tags/upgrade-merged/" + branch.split("/", 1)[1]
    if subprocess.run(["git", "-C", repo, "rev-parse", "-q", "--verify", tag], capture_output=True).returncode:
        return False
    if subprocess.run(["git", "-C", repo, "merge-base", "--is-ancestor", tag, "main"]).returncode:
        sys.exit(f"{repo}: {tag} is not in main - main was reset below a merged step")
    return True


def _step_branches(repo):
    """[(NN, branch)] of the repo's upgrade/NN-* branches, by number - a merged step's branch deleted after its merge
    counted by its tag."""
    out = subprocess.run(["git", "-C", repo, "for-each-ref", "--format=%(refname:short)", "refs/heads/upgrade/"],
                         capture_output=True, text=True, check=True).stdout.split()
    # a merged step whose branch was deleted after its merge is still there by its tag (merged() reads the tag)
    tags = subprocess.run(["git", "-C", repo, "for-each-ref", "--format=%(refname:short)", "refs/tags/upgrade-merged/"],
                          capture_output=True, text=True, check=True).stdout.split()
    out += [b for t in tags if (b := "upgrade/" + t.split("/", 1)[1]) not in out]
    return sorted((int(m.group(1)), b) for b in out if (m := re.fullmatch(r"upgrade/(\d\d)-.+", b)))


def _check_declared(repo_name, step_no, names, branches):
    """The branches up to the step are exactly those the step files declare for the repo, by step name."""
    declared = set()
    for name in names:
        if int(name[:2]) <= step_no:
            repos = set()
            parse(step_file(name), branches=repos)
            if repo_name in repos:
                declared.add("upgrade/" + name)
    present = {b for n, b in branches if n <= step_no}
    if declared != present:
        sys.exit(f"{repo_name}: step branches up to {step_no:02d} differ from the step files' branch lines - missing: "
                 f"{sorted(declared - present) or '-'}, undeclared: {sorted(present - declared) or '-'}")


def _stacked(repo, prev, b):
    """`b` stacks on `prev` and changes something on it - else exits."""
    if subprocess.run(["git", "-C", repo, "merge-base", "--is-ancestor", prev, b]).returncode != 0:
        sys.exit(f"{repo}: {b} does not contain {prev} - rebase it on the previous step's branch")
    # a branch pointing at its predecessor's commit stacks too, and carries no change: its step would go green
    # without it
    if not subprocess.run(["git", "-C", repo, "diff", "--quiet", prev, b]).returncode:
        sys.exit(f"{repo}: {b} changes nothing on {prev} - the step's change is missing")


def ref(repo, step_no, names):
    """The repo's highest upgrade/NN-* branch with NN <= step_no, checked to stack on the one before; else main. The
    branches up to the step must be exactly those the step files declare, by step name. Steps production merged already
    (scripts/upgrade-merge-step.sh tagged them) are in main: they come first, and the rest stack on main; a merged
    step's branch deleted after its merge counts by its tag."""
    branches = _step_branches(repo)
    _check_declared(os.path.basename(os.path.normpath(repo)), step_no, names, branches)
    numbers = [n for n, _ in branches]
    if len(numbers) != len(set(numbers)):
        sys.exit(f"{repo}: two upgrade branches share a number: {[b for _, b in branches]}")
    prev = "main"
    for n, b in branches:
        if n > step_no:
            break
        if merged(repo, b):
            if prev != "main":
                sys.exit(f"{repo}: {b} is merged, but {prev} before it is not - merged out of order")
            continue
        _stacked(repo, prev, b)
        prev = b
    return prev


def pg_image(step):
    """The PostgreSQL image the step moves the cluster to - its CNPG postgresql image line's new one (another
    registry's postgresql is no cluster of ours), (name, tag); None for none."""
    cnpg = re.escape("ghcr.io/cloudnative-pg/postgresql")
    for line in open(os.path.join(STEPS, step + ".txt")):
        m = re.fullmatch(rf"image {cnpg} \S+ => image ({cnpg}) (\S+)", line.strip())
        if m:
            return m[1], m[2]
    return None


def pg_major(step):
    """The PostgreSQL major the step moves the cluster to, "" for none - its base backup is taken on it: the old
    major's backups do not replay into the new one."""
    image = pg_image(step)
    major = re.match(r"\d+\b", image[1]) if image else None
    return major[0] if major else ""


def _up_to(step, names):
    return names[:names.index(step) + 1]


def _playbooks(step):
    playbooks = collected("playbooks", [step])
    return "\n".join(playbooks) if playbooks else None


def _flag_mode(flag):
    return lambda step, names: "yes" if flag in collected("flags", [step]) else "no"


def _first(kind):
    """The step's first `kind` line, "" for none."""
    return lambda step, names: next(iter(collected(kind, [step])), "")


def _before(step, names):
    i = names.index(step)
    return names[i - 1] if i else ""


def _refs(step, names):
    step_no = int(step[:2])
    return (f"{ref(os.path.join(OPS, '..', 'infra'), step_no, names)} "
            f"{ref(os.path.join(OPS, '..', 'platform'), step_no, names)}")


# each mode's output for the step (None: nothing printed)
MODES = {
    "--refs": _refs,
    "--playbooks": lambda step, names: _playbooks(step),
    "--out-of-sync": lambda step, names: ",".join(collected("out_of_sync", [step])),
    **{f"--{flag}": _flag_mode(flag) for flag in FLAG_LINES},
    "--tempo-flush": _first("tempo_flush"),
    "--clickhouse-compat": lambda step, names: next(reversed(collected("compat", _up_to(step, names))), ""),
    "--restore-undo": _first("undo"),
    "--clickhouse-users": lambda step, names: next(reversed(collected("users", _up_to(step, names))),
                                                   "default,schnappy"),
    "--wave0": lambda step, names: " ".join(collected("wave0", [step])),
    "--pg-major": lambda step, names: pg_major(step),
    "--base-args": lambda step, names: " ".join(collected("base", _up_to(step, names))),
    "--before": _before,
    "--scrape-pools-gone": lambda step, names: ",".join(collected("pools_gone", _up_to(step, names))),
}


def main():
    args = sys.argv[1:]
    mode = args[0] if args and args[0] in MODES else None
    if mode:
        args = args[1:]
    if len(args) != 1:
        sys.exit(__doc__)
    names = sorted(f[:-4] for f in os.listdir(STEPS) if f.endswith(".txt"))
    if args[0] not in names:
        sys.exit(f"no step {args[0]} (steps: {', '.join(names)})")
    if not mode:
        print("\n".join(sorted(expected(_up_to(args[0], names)))))
        return
    out = MODES[mode](args[0], names)
    if out is not None:
        print(out)


def _apply(inventory, before, after, where):
    """One change on the inventory - its "before" line must be there."""
    if before is not None:
        if before not in inventory:
            sys.exit(f"{where}: '{before}' is not in the inventory at this step - the step file is stale")
        inventory.discard(before)
    if after is not None:
        inventory.add(after)


def expected(applied):
    """Production's inventory with the changes of the given steps applied, in their order."""
    inventory = {l.rstrip("\n") for l in open(os.path.join(UPGRADE, "prod-inventory.txt")) if l.strip()}
    for name in sorted(applied):
        for before, after, where in parse(os.path.join(STEPS, name + ".txt")):
            _apply(inventory, before, after, where)
    return inventory


def branch_order(name):
    """The step's branch lines, in the file's order - the order production merges them in."""
    order = [l.split()[1] for l in open(os.path.join(STEPS, name + ".txt"))
             if l.strip() in ("branch infra", "branch platform")]
    if len(order) != len(set(order)):
        sys.exit(f"{name}: a repo's branch line twice")
    return order


if __name__ == "__main__":
    main()
