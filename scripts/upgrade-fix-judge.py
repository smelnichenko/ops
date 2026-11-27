"""upgrade-fix-judge.py <repository> <proven> <tip> <path> - the upgrade cycle's judge of one file of the fix agent's
commit (scripts/upgrade-cycle.sh's plain_fix, in the runner's own repository of the fix). What the agent writes is steered
by upstream release notes no human read, so it is judged on the parsed YAML, every scalar as written - and narrowly: three
reviews of this change (2026-11-21) each found another edit a looser judge let through (an image to another registry, a
hub, mTLS, a root app's prune, a duplicate key moving ScyllaDB's release line, a dropped backup, a retention 168h -> 1h,
a chart range 1.x, a downgrade, an IP, a value renamed into an env var's key).

Allowed, and nothing else:
  - every line it adds printable ASCII and tab; no duplicate key; no more aliases than the file had; a bounded size;
  - the documents kept (as many, each its kind);
  - a value moved in its place from a version to a newer one of the same shape (two numbers or more, or one and a flavour
    like 17-alpine; the same separators and flavour; never a range like 1.x, never an IPv4 address); an image reference
    whose name stays and whose tag so moves - a digest-pinned image never (its digest is Renovate's);
  - a value renamed beside itself (the same parent, the same value) - never in a free-form map (env, labels, annotations,
    data, args...), never to a key that is ALL_CAPS or holds '/' or '.', never in ops' files;
  - in an Argo CD document its source's targetRevision and Helm values alone;
  - never anything under a security path or in a document of a security kind; never a value dropped;
  - a one-way store's version only in that store's own unit (FIX_STORE, from stop_if_one_way): its image's name, an Argo
    source's chart or repository, a path naming it (scyllaOperator is scylla's), or a value equal to its image's tag.
Exit 0 allowed; 1 refused, the reason on stderr (any exception is a refusal too). Env: FIX_STORE, FIX_STORES_TABLE."""
import collections
import json
import os
import re
import subprocess
import sys

import yaml

NUM = re.compile(r"\d+", re.ASCII)
VERSION = re.compile(r"v?(?P<nums>\d+(?:[._+-]\d+)*)(?P<flavour>-[A-Za-z][A-Za-z0-9.-]*)?", re.ASCII)
IPV4 = re.compile(r"\d{1,3}(\.\d{1,3}){3}", re.ASCII)
IMAGE = re.compile(r"(?P<name>[a-z0-9][a-z0-9._/-]*(?::\d+/[a-z0-9._/-]+)?)(?::(?P<tag>[A-Za-z0-9._-]+))?(?P<digest>@sha256:[0-9a-f]{64})?", re.ASCII)
SECURE = re.compile(r"securitycontext|runas|fsgroup|supplementalgroups|capabilit|seccomp|apparmor|selinux|readonlyrootfilesystem"
                    r"|privileged|allowprivilegeescalation|hostnetwork|hostpid|hostipc|hostpath|hostport|networkpolic"
                    r"|peerauthentication|authorizationpolic|mtls|rbac|^rules$|serviceaccount|clusterrole|rolebinding"
                    r"|automountserviceaccounttoken|^hub$|^registry$|^repository$|^repourl$|imagepullsecrets|podsecurity")
FREEFORM = {"env", "extraenv", "extraenvvars", "envfrom", "labels", "annotations", "podlabels", "podannotations",
            "commonlabels", "commonannotations", "data", "stringdata", "config", "args", "command", "extraargs",
            "nodeselector", "tolerations", "affinity"}
SECURE_KINDS = {"Role", "ClusterRole", "RoleBinding", "ClusterRoleBinding", "ServiceAccount", "NetworkPolicy",
                "CiliumNetworkPolicy", "CiliumClusterwideNetworkPolicy", "PeerAuthentication", "AuthorizationPolicy",
                "PodSecurityPolicy", "ValidatingWebhookConfiguration", "MutatingWebhookConfiguration", "Namespace"}
ARGO_KINDS = {"Application", "ApplicationSet", "AppProject"}
MAX_LEAVES = 200_000
GENERIC = {"operator", "server", "cluster", "helm", "chart"}  # words of a store's unit names that name no store alone


def refuse(why):
    sys.exit(f"{PATH}: {why}")


class Strict(yaml.BaseLoader):
    """every scalar as written (no base-60 9100 == 2:31:40, no 1.10 == 1.1), a duplicate key refused (the last one wins
    for Helm while a line-reading check reads the first)"""


def _mapping(loader, node, deep=False):
    out = {}
    for k_node, v_node in node.value:
        k = loader.construct_object(k_node, deep=deep)
        if not isinstance(k, str):
            refuse("a key that is no string")
        if k in out:
            refuse(f"a duplicate key {k!r} (Helm takes the last, a line-reading check the first)")
        out[k] = loader.construct_object(v_node, deep=deep)
    return out


Strict.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _mapping)


def blob(rev):
    r = subprocess.run(["git", "-C", REPO, "cat-file", "blob", f"{rev}:{PATH}"], capture_output=True, stdin=subprocess.DEVNULL)
    return r.stdout if r.returncode == 0 else None


def plain_lines(old, new):
    kept = collections.Counter(old.split("\n"))
    for line in new.split("\n"):
        if kept[line] > 0:
            kept[line] -= 1
        elif any(c != "\t" and not " " <= c <= "~" for c in line):
            refuse("a control or non-ASCII character in a line it adds")


def marks(text):
    """(aliases, explicit tags) - YAML that expands what it holds, or a value a tag makes another thing (Ansible's !vault
    is encrypted content; the judge reads every scalar as written and would see the version alone)"""
    try:
        events = list(yaml.parse(text))
    except yaml.YAMLError as e:
        refuse(f"not plain YAML ({str(e).splitlines()[0][:80]})")
    tags = sum(1 for e in events if getattr(e, "tag", None) is not None and not (isinstance(e, yaml.ScalarEvent) and e.implicit[0])
               and not isinstance(e, (yaml.DocumentStartEvent, yaml.DocumentEndEvent)))
    return sum(isinstance(e, yaml.AliasEvent) for e in events), tags


def docs(text):
    try:
        return list(yaml.load_all(text, Loader=Strict))
    except yaml.YAMLError as e:
        refuse(f"not plain YAML ({str(e).splitlines()[0][:80]})")


def helm_values(path, k, v):
    """an Argo source's helm.values - a YAML string - read as YAML"""
    if path[-1:] != ("helm",) or k != "values" or not isinstance(v, str):
        return v
    try:
        return yaml.load(v, Loader=Strict)
    except yaml.YAMLError:
        refuse("an Argo CD source's helm.values that is no YAML")


def leaves(node, path=(), out=None):
    """{path: value} of every scalar (an empty map or list a value of its own)"""
    out = {} if out is None else out
    if len(out) > MAX_LEAVES:
        refuse(f"over {MAX_LEAVES} values (an alias expanded beyond any values file)")
    if isinstance(node, dict):
        items = [(k, helm_values(path, k, v)) for k, v in node.items()]
    elif isinstance(node, list):
        items = list(enumerate(node))
    else:
        out[path] = node
        return out
    for k, v in items:
        leaves(v, path + (k,), out)
    if not items:
        out[path] = "{}" if isinstance(node, dict) else "[]"
    return out


def words(part):
    """a key's words - scyllaOperator, scylla-operator, scylla_operator all name scylla"""
    return re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", part).replace("-", " ").replace("_", " ").replace(".", " ").lower().split()


def secure(path):
    return any(isinstance(p, str) and SECURE.search(p.lower()) for p in path)


def version_move(old, new):
    """a newer version of the same shape: the same separators and flavour, two numbers or more (or one and a flavour),
    never a range, never an IPv4 address, never older"""
    if not (isinstance(old, str) and isinstance(new, str)):
        return False
    a, b = VERSION.fullmatch(old), VERSION.fullmatch(new)
    if not (a and b) or IPV4.fullmatch(old) or IPV4.fullmatch(new):
        return False
    shape = NUM.sub("N", a["nums"])
    if shape != NUM.sub("N", b["nums"]) or a["flavour"] != b["flavour"]:
        return False
    if shape == "N" and not a["flavour"]:
        return False  # a bare number is a count, a mode, a retention - no version
    return [int(x) for x in NUM.findall(b["nums"])] > [int(x) for x in NUM.findall(a["nums"])]


def image_moved(old, new):
    """the same image, its tag moved to a newer version - a digest-pinned one never (the digest is Renovate's)"""
    if not (isinstance(old, str) and isinstance(new, str)):
        return False
    a, b = IMAGE.fullmatch(old), IMAGE.fullmatch(new)
    return bool(a and b and a["name"] == b["name"] and not a["digest"] and not b["digest"] and a["tag"] and b["tag"]
                and version_move(a["tag"], b["tag"]))


def stores():
    try:
        table = json.load(open(os.environ.get("FIX_STORES_TABLE", "")))["stores"]
    except (OSError, ValueError, KeyError) as e:
        refuse(f"the one-way stores' table not read ({e})")
    out = []
    for s in table:
        pats = [re.compile(p[1:-1]) if p.startswith("/") and p.endswith("/") and len(p) > 2 else re.compile(r"(^|/)" + re.escape(p) + "$")
                for p in s.get("packages", [])]
        # its names: the store's own and those its units' pattern names (scylla|scylladb, kafka|strimzi|...)
        names = {s["store"]} | {w for w in re.findall(r"[a-z][a-z0-9]*", s.get("units", "")) if len(w) > 2} - GENERIC
        out.append((s["store"], pats, names))
    return out


def store_named(table, image_name):
    """the one-way store an image is, by its name - or None"""
    return next((name for name, pats, _ in table if any(x.search(image_name) for x in pats)), None)


def store_tags(lo, table):
    """{tag: store} of the store images the document runs - a value equal to one is that store's version too"""
    tags = {}
    for p, v in lo.items():
        if not isinstance(v, str):
            continue
        m = IMAGE.fullmatch(v)
        if m and m["tag"] and store_named(table, m["name"]):
            tags[m["tag"]] = store_named(table, m["name"])
        tag = lo.get(p[:-1] + ("tag",)) if p[-1:] == ("repository",) else None
        if tag and store_named(table, v):
            tags[tag] = store_named(table, v)
    return tags


def store_of(path, old, new, doc, lo, table):
    for name, pats, names in table:
        for v in (old, new):
            m = IMAGE.fullmatch(v) if isinstance(v, str) else None
            if m and any(x.search(m["name"]) for x in pats):
                return name
        if any(w in names for p in path if isinstance(p, str) for w in words(p)):
            return name
        src = argo_source(path, doc)
        if src and any(x.search(str(src.get(k, ""))) for x in pats for k in ("chart", "repoURL")):
            return name
    return store_tags(lo, table).get(old)


def argo_source(path, doc):
    """the Argo source a path is in (spec.source, or spec.sources[i]) - its sibling chart and repoURL"""
    try:
        if path[:2] == ("spec", "source"):
            return doc["spec"]["source"]
        if path[:2] == ("spec", "sources") and isinstance(path[2], int):
            return doc["spec"]["sources"][path[2]]
    except (KeyError, IndexError, TypeError):
        return None
    return None


def argo_ok(path):
    """an Argo CD document's part the agent may touch: a source's targetRevision, its Helm values"""
    i = next((n for n, p in enumerate(path) if p in ("source", "sources")), None)
    if i is None:
        return False
    rest = [p for p in path[i + 1:] if not isinstance(p, int)]
    return rest[:1] == ["targetRevision"] or rest[:1] == ["helm"] and rest[1:2] in (["values"], ["valuesObject"], ["parameters"])


def rename_ok(r, p):
    parent = p[:-1]
    key = p[-1]
    if r[:-1] != parent or not isinstance(key, str):
        return False  # beside itself alone: a value moved to another parent could land anywhere
    if any(isinstance(x, str) and x.lower() in FREEFORM for x in parent):
        return False  # env, labels, data...: their keys are data, any one the agent picks would mean something
    if key.upper() == key and any(c.isalpha() for c in key) or "/" in key or "." in key:
        return False
    return not PATH.startswith("deploy/ansible/")  # ops: versions alone (a play's any_errors_fatal renamed ignore_errors)


def marks_kept(old_text, new_text):
    (alias_old, tag_old), (alias_new, tag_new) = marks(old_text), marks(new_text)
    if alias_new > alias_old:
        refuse("an alias added (YAML that expands what it holds)")
    if tag_new > tag_old:
        refuse("an explicit tag added (!vault, !!binary: a value made another thing)")


def kind_of(d):
    return d.get("kind") if isinstance(d, dict) else None


def judge_changed(p, kind, lo, ln, doc, table, fix_store):
    """a value changed in its place: a newer version or the same image's newer tag, outside security and Argo paths,
    a store's in its own unit alone"""
    where = ".".join(map(str, p))
    if kind in ARGO_KINDS and not argo_ok(p):
        refuse(f"{where} changed in an Argo CD {kind} (its targetRevision and Helm values alone are the agent's)")
    if secure(p):
        refuse(f"{where} changed (a security path)")
    if not version_move(lo[p], ln[p]) and not image_moved(lo[p], ln[p]):
        refuse(f"{where}: {str(lo[p])[:60]!r} -> {str(ln[p])[:60]!r} - neither a newer version of its shape nor the same image's newer tag")
    s = store_of(p, lo[p], ln[p], doc, lo, table)
    if s and s != fix_store:
        refuse(f"{where} moves the one-way store {s}'s version in a unit that is not {s}'s")


def judge_added(p, kind, lo, ln, removed):
    """a value added: a rename of one gone beside it, outside security and Argo paths - the one it renames"""
    where = ".".join(map(str, p))
    match = next((r for r in removed if lo[r] == ln[p] and rename_ok(r, p)), None)
    if match is None:
        refuse(f"{where}: a new value ({str(ln[p])[:60]!r}) - the agent renames a value beside itself, never adds one")
    if secure(p) or secure(match):
        refuse(f"{where}: renamed into or out of a security path")
    if kind in ARGO_KINDS and not (argo_ok(p) and argo_ok(match)):
        refuse(f"{where}: renamed in an Argo CD {kind} outside its Helm values")
    return match


def judge_doc(o, n, table, fix_store):
    kind = kind_of(o)
    if kind_of(n) != kind:
        refuse(f"a document's kind changed ({kind} -> {kind_of(n)})")
    if o == n:
        return
    if kind in SECURE_KINDS:
        refuse(f"a {kind} changed (a security kind: never the agent's)")
    lo, ln = leaves(o), leaves(n)
    for p in lo.keys() & ln.keys():
        if lo[p] != ln[p]:
            judge_changed(p, kind, lo, ln, n, table, fix_store)
    removed = list(lo.keys() - ln.keys())
    for p in ln.keys() - lo.keys():
        removed.remove(judge_added(p, kind, lo, ln, removed))
    if removed:
        refuse(f"{'.'.join(map(str, removed[0]))} dropped - a value dropped is never the agent's (a backup, an alert, an injection turned off)")


def judge(old_text, new_text):
    marks_kept(old_text, new_text)
    old_docs, new_docs = docs(old_text), docs(new_text)
    if len(old_docs) != len(new_docs):
        refuse(f"{len(new_docs)} documents where there were {len(old_docs)} (a resource of its own)")
    table, fix_store = stores(), os.environ.get("FIX_STORE", "")
    for o, n in zip(old_docs, new_docs):
        judge_doc(o, n, table, fix_store)


if __name__ == "__main__":
    REPO, PROVEN, TIP, PATH = sys.argv[1:5]
    try:
        new_b, old_b = blob(TIP), blob(PROVEN)
        try:
            new_t = new_b.decode("utf-8")
        except (AttributeError, UnicodeDecodeError):  # not there (a deletion is refused before), or not UTF-8
            refuse("not UTF-8 text")
        old_t = (old_b or b"").decode("utf-8", "replace")
        plain_lines(old_t, new_t)
        judge(old_t, new_t)
    except SystemExit:
        raise
    except Exception as e:  # any failure of the judge refuses - never a pass by accident
        refuse(f"the judge failed ({type(e).__name__}: {str(e)[:80]})")
