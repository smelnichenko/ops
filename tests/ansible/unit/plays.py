"""The repo's Ansible files read as Ansible reads them, for the harnesses that judge a class of tasks (every shell task,
every module's arguments, every secret on a command line or in the log): one walk - a harness's own missed a play's
pre_tasks, post_tasks or handlers - and a task's keywords from Ansible's own classes, not a list kept by hand.

    sys.path.insert(0, "tests/ansible/unit"); from plays import files, load, plays, tasks, actions, KEYWORDS
    for f in files(): for t in tasks(load(f)): for module, value in actions(t): ...
"""
import glob

import yaml
from ansible.playbook.handler import Handler
from ansible.playbook.task import Task

# a task's keywords - every other key is its action (local_action names one; with_<lookup> is a loop)
KEYWORDS = frozenset(Task.fattributes) | frozenset(Handler.fattributes) | {"block", "rescue", "always", "local_action"}
SECTIONS = ("pre_tasks", "tasks", "post_tasks", "handlers")


def files(*roots):
    """Every .yml file under the roots (default deploy/ansible and tests/ansible), a virtualenv's aside."""
    roots = roots or ("deploy/ansible", "tests/ansible")
    return sorted(f for r in roots for f in glob.glob(f"{r}/**/*.yml", recursive=True) if "/venv/" not in f)


def load(path):
    """The file's YAML - one Ansible cannot read fails the harness here, never skipped unseen."""
    with open(path) as f:
        return yaml.safe_load(f)


IMPORT_PLAYBOOK = ("import_playbook", "ansible.builtin.import_playbook", "ansible.legacy.import_playbook")


def is_play(node):
    """A play, or an import of a playbook (by any of its names - 31 files use the full one)."""
    return isinstance(node, dict) and ("hosts" in node or any(k in node for k in IMPORT_PLAYBOOK))


def plays(doc):
    """A playbook's plays (their keywords - vars, environment - apply to every task of them)."""
    return [x for x in doc if is_play(x)] if isinstance(doc, list) else []


def tasks(doc):
    """Every task of a playbook (each play's pre_tasks, tasks, post_tasks and handlers) or of a task file (a list of
    tasks), each block's own (block, rescue, always) after the block - nothing of a vars file or an inventory (a
    mapping, no list)."""
    if not isinstance(doc, list):
        return
    for x in doc:
        if is_play(x):
            for k in SECTIONS:
                yield from _tasks(x.get(k))
        elif isinstance(x, dict):
            yield from _tasks([x])


def _tasks(items):
    for t in items or []:
        if isinstance(t, dict):
            yield t
            for k in ("block", "rescue", "always"):
                yield from _tasks(t.get(k))


def actions(task):
    """The task's actions as written: [(module, value)] - one for a task, none for a block; more is a mistake (a
    keyword misspelt reads as a second action)."""
    for key in ("local_action", "action"):  # the action named by a keyword: a mapping with its module, or free form
        if isinstance(task.get(key), dict):
            return [(task[key].get("module"), task[key])]
        if key in task:
            words = str(task[key]).split(None, 1)
            return [(words[0], words[1] if len(words) > 1 else "")]
    return [(k, v) for k, v in task.items() if k not in KEYWORDS and not str(k).startswith("with_")]
