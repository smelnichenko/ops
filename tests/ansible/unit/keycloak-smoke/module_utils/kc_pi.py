"""A stand-in Pi's state for the keycloak-smoke harness: its files under $KCS/<host>, its installs under
$KCS/installs/<host>, every change it makes one line in $KCS/events.log (time, Pi, what)."""
import fcntl
import os
import time

OPT = "/opt/keycloak-"


def _pi():
    return os.environ["KC_HOST"]


def _run():
    return os.environ["KCS"]


def _state(name):
    return os.path.join(_run(), _pi(), name)


def event(what):
    with open(os.path.join(_run(), "events.log"), "a") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.write(f"{time.time():.3f} {_pi()} {what}\n")


def read(name, default=""):
    try:
        with open(_state(name)) as f:
            return f.read().strip()
    except OSError:
        return default


def write(name, value):
    with open(_state(name), "w") as f:
        f.write(value)


def install(path):
    """/opt/keycloak-<version>[/<file>] on this Pi"""
    if not path.startswith(OPT):
        raise ValueError(f"not a Keycloak install: {path}")
    return os.path.join(_run(), "installs", _pi(), path[len(OPT):])
