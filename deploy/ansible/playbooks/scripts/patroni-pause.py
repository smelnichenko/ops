#!/usr/bin/env python3
"""patroni-pause.py - Patroni's cluster paused around a run's work and resumed after it, the one way setup-consul,
setup-patroni and upgrade-patroni do it (ansible.builtin.script, root, on a Pi with Patroni installed - running or not:
it reads and writes through Consul, as patronictl does).

  check                 exit 1 when the cluster is paused already - someone's maintenance, or a run cut short (a
                        Ctrl-C skips Ansible's always:), named by its marker
  pause <run>           a marker naming the run, check-and-set (one only: a marker there refuses before any pause),
                        then the pause; "MARKER <index>" once the config and every member show it paused. A failure
                        after the marker (a DCS unread after the request among them) undoes what this run's pause may
                        have done, then deletes the marker
  resume <run>          this run's marker read, by its index (the "MARKER <index>" line of its pause's output, in
                        PAUSED_OUT: ansible.builtin.script runs under ssh -tt, its lines end CR LF) - a marker not its
                        own, or none, means the pause is not its own: refused, nothing resumed - then the resume,
                        proven the same way, and only then the marker deleted, check-and-set: a resume not proven
                        keeps the marker as it was, so a retry of the same task resumes

patronictl's exit proves nothing: Patroni 4.1 exits 0 after "Failed: pause cluster management status code=...", after
"... didn't recognized pause state", and prints "Success" with a member still unpaused (ctl.py toggle_pause and
wait_until_pause_is_applied, read on pi1). What proves it is the DCS: the config's pause and each member's own, what
patronictl waits on.
"""
import datetime
import json
import os
import re
import secrets
import subprocess
import sys
import time

CONFIG = os.environ.get("PATRONI_CONFIG", "/etc/patroni/patroni.yml")
KEY = "ansible/patroni-paused-by"
RUNS = ("setup-consul", "setup-patroni", "upgrade-patroni")
# the shape a run writes (an older run's had no nonce): only that is echoed - Consul has no ACLs
MARKER = re.compile(r"(%s) \d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ( [0-9a-f]{8})?" % "|".join(RUNS))
# each member writes its state into the DCS on its loop (loop_wait 10 s): the time for all of them to show it
WAIT = float(os.environ.get("PATRONI_PAUSE_WAIT", "40"))
POLL = float(os.environ.get("PATRONI_PAUSE_POLL", "2"))
CLEAN_UP = (f"patronictl list; if no run is running, patronictl resume and consul kv delete {KEY}")


class Unread(Exception):
    """The DCS not read: nothing can be proven."""

    def __init__(self, msg, advice=CLEAN_UP):
        super().__init__(msg)
        self.advice = advice


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def ctl(*args):
    return run("patronictl", "-c", CONFIG, *args)


def prefix():
    import yaml  # Patroni's own dependency: there wherever patronictl is
    with open(CONFIG) as f:
        conf = yaml.safe_load(f)
    return "%s/%s" % ((conf.get("namespace") or "/service/").strip("/"), conf["scope"])


def state(pre):
    """The config's pause and each member's, as the DCS holds them."""
    c = run("consul", "kv", "get", f"{pre}/config")
    m = run("consul", "kv", "get", "-recurse", f"{pre}/members/")
    if c.returncode or m.returncode:
        raise Unread(f"the DCS not read ({pre}): {(c.stderr + m.stderr).strip()}")
    members = {}
    for line in m.stdout.splitlines():
        key, _, value = line.partition(":")
        members[key.rsplit("/", 1)[-1]] = json.loads(value).get("pause") is True
    if not members:
        raise Unread(f"no Patroni member in the DCS ({pre}/members/): Patroni runs on no Pi",
                     "start it (systemctl start patroni on each Pi), then run this again")
    return json.loads(c.stdout).get("pause") is True, members


def said(paused, members):
    return ", ".join([f"config {'paused' if paused else 'not paused'}"]
                     + [f"{n} {'paused' if p else 'not paused'}" for n, p in sorted(members.items())])


def settled(pre, want):
    """Until the config and every member show `want` - WAIT seconds at most: (whether they did, what they showed)."""
    end = time.monotonic() + WAIT
    while True:
        paused, members = state(pre)
        if paused == want and all(p == want for p in members.values()):
            return True, said(paused, members)
        if time.monotonic() >= end:
            return False, said(paused, members)
        time.sleep(POLL)


def unpaused(pre):
    """Resumed, whatever is paused - proven: (whether it is, what it says)."""
    paused, members = state(pre)
    if not paused and not any(members.values()):
        return True, said(paused, members)
    out = ctl("resume", "--wait") if paused else None  # a member alone still paused catches up on its loop
    ok, shown = settled(pre, False)
    return ok, shown + ("" if out is None else f" (patronictl: {(out.stdout + out.stderr).strip()!r})")


def marker(who):
    at = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return f"{who} {at} {secrets.token_hex(4)}"


def read_marker():
    """The marker's (value, ModifyIndex) - (None, None) when there is none."""
    got = run("consul", "kv", "get", "-detailed", KEY)
    if got.returncode:
        if "No key exists" in got.stderr:
            return None, None
        raise Unread(f"the pause marker not read: {got.stderr.strip()}")
    fields = {}
    for line in got.stdout.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2:
            fields[parts[0]] = parts[1]
    return fields.get("Value"), fields.get("ModifyIndex")


def delete_marker(idx):
    """This run's marker deleted, check-and-set (Consul deletes a missing key 'successfully': read first)."""
    value, now = read_marker()
    if value is None:
        return "this run's pause marker is gone already (deleted by hand?)"
    if now != idx:
        return f"the pause marker is not this run's any more ({value!r})"
    d = run("consul", "kv", "delete", "-cas", f"-modify-index={idx}", KEY)
    return None if d.returncode == 0 else f"its marker not deleted: {d.stderr.strip()}"


def check(pre):
    paused, members = state(pre)
    if not paused and not any(members.values()):
        print(f"NOT PAUSED: {said(paused, members)}")
        return 0
    by, _ = read_marker()
    msg = f"REFUSED: the cluster is paused ({said(paused, members)}) - finish that first (patronictl resume)"
    if by and MARKER.fullmatch(by):
        msg += (f" - paused by {by}: if that run is no longer running (a Ctrl-C skips its resume), check patronictl"
                f" list, then patronictl resume and consul kv delete {KEY}")
    elif by:
        msg += f" - a pause marker of another shape is there (consul kv get {KEY})"
    print(msg)
    return 1


def pause(pre, who):
    value = marker(who)
    put = run("consul", "kv", "put", "-cas", "-modify-index=0", KEY, value)
    if put.returncode:
        print(f"REFUSED: a Patroni pause marker is there already, or none could be put ({put.stderr.strip()}) - another"
              f" run pausing, or one cut short: {CLEAN_UP}")
        return 1
    # read back: its index, and that it is this run's (the nonce) - nothing can have changed it unseen in between. A read
    # failing (Consul's leader moving) is read again; one never read leaves the marker, named, nothing paused
    for attempt in range(3):
        try:
            got, idx = read_marker()
            break
        except Unread as e:
            if attempt == 2:
                print(f"REFUSED: the pause marker this run put ({value!r}) not read back ({e}) - nothing paused; once"
                      f" Consul answers, delete it if it still names this run: consul kv delete {KEY}")
                return 1
            time.sleep(POLL)
    if got != value or not (idx or "").isdigit():
        print(f"REFUSED: the pause marker read back is not the one this run put ({got!r}, index {idx!r}) - nothing"
              f" paused: {CLEAN_UP}")
        return 1
    out = ctl("pause", "--wait")
    text = (out.stdout + out.stderr).strip()
    ok, shown = False, ""
    if out.returncode == 0 and "Success: cluster management is paused" in out.stdout:
        try:
            ok, shown = settled(pre, True)
        except Unread as e:  # the request may have landed: undone below, as any pause not proven
            shown = f"nothing ({e})"
    if ok:
        print(f"PAUSED: {shown}")
        print(f"MARKER {idx}")
        return 0
    print(f"PAUSE FAILED: patronictl said {text!r}" + (f" - the DCS shows {shown}" if shown else ""))
    if out.returncode and "already paused" in text:
        # paused by someone between the check and this pause: theirs - left as it is, this run's marker gone
        problem = delete_marker(idx)
        print("the cluster was paused by someone else meanwhile - left as it is" + (f"; {problem}" if problem else ""))
        return 1
    # this run's request may have landed (in part): undone before its marker goes - kept, naming this run, otherwise
    ok, shown = unpaused(pre)
    if not ok:
        print(f"STILL PAUSED after this run's resume ({shown}) - its marker kept: {CLEAN_UP}")
        return 1
    problem = delete_marker(idx)
    print(f"undone: {shown}" + (f"; {problem}" if problem else ""))
    return 1


def resume(pre, idx):
    if not idx.isdigit():
        print(f"REFUSED: this run's pause marker index is {idx!r} - its pause said no MARKER; the cluster may be"
              f" paused: {CLEAN_UP}")
        return 1
    # read, not deleted, first: a resume not proven (a DCS unread among them - main's) keeps the marker as it is, its
    # index the one the pause said, and the task's retry resumes; only this run deletes a marker by its index
    value, now = read_marker()
    if value is None:
        # gone and nothing paused: done - an earlier try of this task resumed and cleared it, or a person did
        paused, members = state(pre)
        if not paused and not any(members.values()):
            print(f"NOTHING TO RESUME: its marker gone, {said(paused, members)}")
            return 0
    problem = None
    if value is None:
        problem = "this run's pause marker is gone already (deleted by hand?)"
    elif now != idx:
        problem = f"the pause marker is not this run's any more ({value!r})"
    if problem:
        print(f"REFUSED: {problem} - the pause is not this run's: left as it is ({CLEAN_UP})")
        return 1
    ok, shown = unpaused(pre)
    if not ok:
        print(f"STILL PAUSED after the resume ({shown}) - its marker kept, naming this run: {CLEAN_UP}")
        return 1
    problem = delete_marker(idx)
    if problem:
        print(f"RESUMED: {shown} - but {problem}: the next run's pause refuses until it is gone (consul kv delete {KEY})")
        return 1
    print(f"RESUMED: {shown}")
    return 0


def main(argv):
    if argv[:1] == ["check"] and len(argv) == 1:
        act = lambda pre: check(pre)  # noqa: E731
    elif argv[:1] == ["pause"] and len(argv) == 2 and argv[1] in RUNS:
        act = lambda pre: pause(pre, argv[1])  # noqa: E731
    elif argv[:1] == ["resume"] and len(argv) == 2 and argv[1] in RUNS:
        idx = re.search(r"^MARKER (.*?)\r?$", os.environ.get("PAUSED_OUT", ""), re.M)
        act = lambda pre: resume(pre, idx.group(1) if idx else "")  # noqa: E731
    else:
        sys.exit(__doc__)
    try:
        return act(prefix())
    except Unread as e:
        print(f"REFUSED: {e} - nothing proven: {e.advice}")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
