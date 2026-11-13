#!/usr/bin/env python3
"""PreToolUse (Bash): no root container, and no container writing host files as root.

The docker group is root on aqua (rootful daemon, socket root:docker 660, sm in the group). 2026-11-13 Claude deleted
root-owned files with `docker run --user 0 -v <dir>:/s ... rm -rf`, unasked; those files were root's because earlier
containers had run with a bind mount and no --user. Refused here, every time:
- docker/podman run, create, exec (also `container run`, `compose run|exec`) as uid 0 or root, --privileged, a root
  capability (--cap-add ALL/SYS_ADMIN/...), the host's pid or user namespace;
- a mount of the docker socket;
- run/create/compose run with a host bind mount (-v SRC:DST with a path, --mount type=bind) without --user set to a
  non-root user.
A container on a bind mount runs as the operator's user: --user "$(id -u):$(id -g)". Anything that needs root is the
operator's call, outside Claude.

Tests: no-root-containers-test.py
"""
import json
import os
import re
import shlex
import sys

RUNTIMES = {"docker", "podman"}
SHELLS = {"sh", "bash", "zsh", "dash", "ash", "ksh"}
SEPARATORS = {";", "&&", "||", "|", "&", "(", ")", "|&"}
ROOT_CAPS = {"ALL", "SYS_ADMIN", "SYS_MODULE", "SYS_PTRACE", "SYS_RAWIO", "DAC_OVERRIDE", "DAC_READ_SEARCH", "SETUID",
             "SETGID", "CHOWN", "FOWNER"}
# the options of `docker run|create` that take a value (docker run --help, 2026-11-13); every other option is a flag
RUN_VALUED = set("""--add-host --annotation --attach --blkio-weight --blkio-weight-device --cap-add --cap-drop
--cgroup-parent --cgroupns --cidfile --cpu-period --cpu-quota --cpu-rt-period --cpu-rt-runtime --cpu-shares --cpus
--cpuset-cpus --cpuset-mems --detach-keys --device --device-cgroup-rule --device-read-bps --device-read-iops
--device-write-bps --device-write-iops --dns --dns-option --dns-search --domainname --entrypoint --env --env-file --expose
--group-add --health-cmd --health-interval --health-retries --health-start-interval --health-start-period --health-timeout
--hostname --ip --ip6 --ipc --isolation --label --label-file --link --link-local-ip --log-driver --log-opt --mac-address
--memory --memory-reservation --memory-swap --memory-swappiness --mount --name --network --net --network-alias
--oom-score-adj --pid --pids-limit --platform --publish --pull --restart --runtime --security-opt --shm-size --stop-signal
--stop-timeout --storage-opt --sysctl --tmpfs --ulimit --umask --user --userns --uts --volume --volume-driver
--volumes-from --workdir --env-from-file --index -a -c -e -h -l -m -p -u -v -w""".split())
USER_OPTS = {"-u", "--user"}
VOLUME_OPTS = {"-v", "--volume"}

ADVICE = ('A container on a host path runs as the operator\'s user: add --user "$(id -u):$(id -g)" (the docker group '
          "is root on this machine). A root or privileged container, a docker socket mount, or root over host files is "
          "the operator's call: do not work around this; ask the operator, naming the exact command.")


def deny(why):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                             "permissionDecisionReason": f"Blocked: {why}. {ADVICE}"}}))
    sys.exit(0)


def is_root_user(value):
    v = value.strip().strip("'\"")
    return v in ("0", "root") or v.startswith(("0:", "root:"))


def bind_source(spec):
    """The host path a -v value binds, or None for a named or anonymous volume."""
    parts = spec.split(":")
    if len(parts) < 2:
        return None
    src = parts[0]
    return src if src and ("/" in src or src[0] in ".~$") else None


def mount_bind_source(spec):
    kv = dict(p.split("=", 1) if "=" in p else (p, "") for p in spec.split(","))
    if kv.get("type", "volume") != "bind":
        return None
    return kv.get("src") or kv.get("source") or "?"


def judge(words, start):
    """The invocation at words[start] (docker or podman): a reason to refuse it, or None."""
    i = start + 1
    sub = []
    while i < len(words) and words[i] in ("container", "compose", "run", "create", "exec") and len(sub) < 2:
        sub.append(words[i])
        i += 1
        if sub[-1] in ("run", "create", "exec"):
            break
    if not sub or sub[-1] not in ("run", "create", "exec"):
        return None
    action = sub[-1]
    users, binds = [], []
    while i < len(words):
        w = words[i]
        if w in SEPARATORS:
            break
        if not w.startswith("-") or w == "-":
            break  # the image (run/create) or the container (exec): what follows is the container's own command
        name, eq, value = w.partition("=")
        glued = None
        if not eq and len(w) > 2 and w[1] != "-" and w[:2] in ("-u", "-v", "-e", "-w", "-p", "-l", "-m", "-h", "-a", "-c"):
            name, value, glued = w[:2], w[2:], True
        takes_value = name in RUN_VALUED
        if takes_value and not eq and not glued:
            i += 1
            value = words[i] if i < len(words) else ""
        if name in USER_OPTS:
            users.append(value)
            if is_root_user(value):
                return f"`{' '.join(words[start:start + len(sub) + 1])}` as root ({name} {value})"
        elif name == "--privileged":
            return f"a --privileged container ({action})"
        elif name == "--cap-add" and value.upper().removeprefix("CAP_") in ROOT_CAPS:
            return f"a container given the root capability {value}"
        elif name in ("--pid", "--userns") and value == "host":
            return f"a container in the host's {name[2:]} namespace"
        elif name == "--userns" and value.startswith("keep-id"):
            users.append("keep-id")  # podman: the container's user is the operator's own
        elif name in VOLUME_OPTS:
            src = bind_source(value)
            if src:
                binds.append(src)
        elif name == "--mount":
            src = mount_bind_source(value)
            if src:
                binds.append(src)
        i += 1
    if any("docker.sock" in b for b in binds):
        return "a mount of the docker socket (root over the host from inside the container)"
    if binds and action in ("run", "create") and (not users or is_root_user(users[-1])):
        return f"a container writing the host path {binds[0]} as root (a bind mount without --user)"
    return None


def scan(command, depth=0):
    if depth > 3 or not re.search(r"\b(docker|podman)\b", command):
        return None
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        words = list(lexer)
    except ValueError:
        if re.search(r"\b(docker|podman)\b[^;&|]*\b(run|create|exec)\b", command):
            return "a docker command that could not be read (its quoting does not close)"
        return None
    for i, w in enumerate(words):
        if os.path.basename(w) in RUNTIMES:
            why = judge(words, i)
            if why:
                return why
        # a command handed to a shell (sh -c '...', bash -lc "...") or to eval is read too
        prev = words[i - 1] if i else ""
        shell_arg = re.fullmatch(r"-[a-z]*c[a-z]*", prev) and i >= 2 and any(
            os.path.basename(x) in SHELLS for x in words[max(0, i - 3):i - 1])
        if (shell_arg or prev == "eval") and re.search(r"\b(docker|podman)\b", w):
            why = scan(w, depth + 1)
            if why:
                return why
    return None


def main():
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw)
    except ValueError:
        deny("a hook payload that could not be read")
    if payload.get("tool_name") != "Bash":
        return
    try:
        why = scan(payload.get("tool_input", {}).get("command", "") or "")
    except Exception as e:  # a guard fails closed, but only on what it guards
        if re.search(r"\b(docker|podman)\b", str(payload)):
            deny(f"a docker command this guard could not judge ({type(e).__name__})")
        return
    if why:
        deny(why)


if __name__ == "__main__":
    main()
