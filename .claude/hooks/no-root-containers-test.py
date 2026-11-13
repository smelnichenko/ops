#!/usr/bin/env python3
"""Tests for no-root-containers.py: every shape below was either used on aqua or is one spelling away from it.

2026-11-13: Claude removed root-owned files from its scratch folder with
`docker run --rm --user 0 -v <scratchpad>:/s <image> sh -c 'find /s ... -exec rm -rf {} +'` - root on the host through
the docker group, unasked. Those files were root's because earlier containers ran with a bind mount and no --user.

Run: python3 no-root-containers-test.py
"""
import importlib.util
import json
import pathlib
import subprocess
import sys

HOOK = pathlib.Path(__file__).with_name("no-root-containers.py")
spec = importlib.util.spec_from_file_location("nrc", HOOK)
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)

DENY = [
    ("the exact command of 2026-11-13",
     "docker run --rm --user 0 -v /home/sm/scratch/pad:/s eclipse-temurin:25.0.4_7-jdk sh -c 'find /s -mindepth 1 -exec rm -rf {} +'"),
    ("-u 0", "docker run -u 0 alpine true"),
    ("--user=root", "docker run --user=root alpine true"),
    ("root with a group", "docker run -u root:root alpine true"),
    ("uid 0 with a group", "docker run --user 0:0 alpine true"),
    ("the short flag glued to its value", "docker run -u0 alpine true"),
    ("--privileged", "docker run --privileged alpine true"),
    ("a capability that is root", "docker run --cap-add=SYS_ADMIN alpine true"),
    ("every capability", "docker run --cap-add ALL alpine true"),
    ("the host's process namespace", "docker run --pid=host alpine true"),
    ("the host's user namespace", "docker run --userns host alpine true"),
    ("the docker socket is root even as me",
     'docker run --user "$(id -u):$(id -g)" -v /var/run/docker.sock:/var/run/docker.sock docker:cli ps'),
    ("exec as root", "docker exec -u 0 radar-postgres-1 sh"),
    ("exec as root, long", "docker exec --user root some-container id"),
    ("exec privileged", "docker exec --privileged some-container id"),
    ("podman too", "podman run --user 0 alpine true"),
    ("docker container run", "docker container run -u 0 alpine true"),
    ("compose run as root", "docker compose run --user root svc true"),
    ("a bind mount with no --user: the files it writes are root's",
     "docker run --rm -v /home/sm/src/site:/w node:24 npm ci"),
    ("$PWD bind mount", 'docker run --rm -v "$PWD":/w node:24 npm ci'),
    ("--volume=", "docker run --volume=/tmp/x:/x alpine touch /x/y"),
    ("-v glued", "docker run -v/tmp/x:/x alpine touch /x/y"),
    ("a relative bind", "docker run -v ./ctx:/c alpine ls /c"),
    ("a home bind", "docker run -v ~/x:/x alpine ls /x"),
    ("--mount type=bind", "docker run --mount type=bind,src=/tmp/x,dst=/x alpine ls /x"),
    ("--mount, bind not first", "docker run --mount src=/tmp/x,target=/x,type=bind alpine ls"),
    ("a bind read-only still reads as root", "docker run -v /etc:/e:ro alpine cat /e/shadow"),
    ("create with a bind", "docker create -v /a:/b alpine"),
    ("compose run with a bind and no user", "docker compose run -v /a:/b svc true"),
    ("buried in a chain", "cd /tmp && docker run -u 0 alpine true; echo done"),
    ("after a pipe", "true | docker run -v /a:/b alpine true"),
    ("under sudo", "sudo docker run -v /a:/b alpine true"),
    ("inside sh -c", "bash -c 'docker run -u 0 alpine true'"),
    ("inside sh -lc", "sh -lc \"docker run --privileged alpine true\""),
    ("an absolute docker path", "/usr/bin/docker run -u 0 alpine true"),
    ("root after a non-root user: the last one wins", "docker run --user 1000 -u 0 alpine true"),
    ("unparseable quoting, root flag in it", "docker run -u 0 alpine sh -c 'echo \"unbalanced"),
]

ALLOW = [
    ("a bind mount as me", 'docker run --rm --user "$(id -u):$(id -g)" -v /home/sm/x:/x alpine ls /x'),
    ("a bind mount as a numeric non-root uid", "docker run --user 1000:1000 -v /a:/b alpine true"),
    ("no mount, the image's user", "docker run --rm alpine true"),
    ("a named volume is not a host path", "docker run -v pgdata:/var/lib/postgresql/data postgres:17"),
    ("an anonymous volume", "docker run -v /data alpine true"),
    ("--mount of a volume", "docker run --mount type=volume,src=v,dst=/d alpine true"),
    ("tmpfs", "docker run --tmpfs /t alpine true"),
    ("exec as the container's user", "docker exec radar-postgres-1 psql -U postgres -c 'select 1'"),
    ("exec as a named user", "docker exec -u postgres radar-postgres-1 psql"),
    ("-u after the image is the container command's", "docker run --rm alpine id -u 0"),
    ("-v after the image is the container command's", "docker run --rm alpine ls -v /etc:/x"),
    ("a capability that is not root", "docker run --cap-add NET_BIND_SERVICE alpine true"),
    ("podman keep-id", "podman run --userns=keep-id -v /a:/b alpine true"),
    ("build", "docker build -t x ."),
    ("listing", "docker images --format '{{.ID}}'"),
    ("removing images", "docker rmi a249h2-c1:latest"),
    ("logs", "docker logs radar-postgres-1"),
    ("ps", "docker ps -a"),
    ("no docker at all", "ls -la /home/sm"),
    ("a commit message that only mentions it", 'git commit -m "never: docker run --user 0 -v /x:/s"'),
    ("grep for it", "grep -rn 'docker run -u 0' docs/"),
    ("echo of it", "echo 'docker run --privileged'"),
    ("docker in a word", "ls dockerfiles && cat Dockerfile"),
]


def run_hook(command):
    """The hook as Claude Code runs it: the payload on stdin, the decision on stdout."""
    r = subprocess.run([sys.executable, str(HOOK)], input=json.dumps({"tool_name": "Bash", "tool_input": {"command": command}}),
                       capture_output=True, text=True, timeout=20)
    if r.returncode != 0:
        return "error", r.stderr
    if not r.stdout.strip():
        return "allow", ""
    out = json.loads(r.stdout)["hookSpecificOutput"]
    return out["permissionDecision"], out["permissionDecisionReason"]


def main():
    fails = 0
    for name, command in DENY:
        decision, reason = run_hook(command)
        if decision != "deny" or "--user" not in reason:
            fails += 1
            print(f"FAIL deny  {name}: {decision} {reason[:120]!r}\n     {command}")
    for name, command in ALLOW:
        decision, reason = run_hook(command)
        if decision != "allow":
            fails += 1
            print(f"FAIL allow {name}: {decision} {reason[:120]!r}\n     {command}")
    # not Bash, or no command: nothing to judge
    r = subprocess.run([sys.executable, str(HOOK)], input=json.dumps({"tool_name": "Read", "tool_input": {"file_path": "/x"}}),
                       capture_output=True, text=True, timeout=20)
    if r.returncode != 0 or r.stdout.strip():
        fails += 1
        print(f"FAIL another tool: rc {r.returncode} {r.stdout!r}")
    # a payload it cannot read fails closed
    r = subprocess.run([sys.executable, str(HOOK)], input="not json docker run -u 0", capture_output=True, text=True, timeout=20)
    if '"deny"' not in r.stdout:
        fails += 1
        print(f"FAIL unreadable payload: rc {r.returncode} {r.stdout!r} {r.stderr[:200]!r}")
    total = len(DENY) + len(ALLOW) + 2
    print(f"no-root-containers: {total - fails}/{total} passed")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
