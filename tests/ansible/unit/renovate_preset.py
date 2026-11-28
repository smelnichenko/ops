"""The upgrade cycle's Renovate preset (renovate/upgrade-cycle.json) as the harnesses read it: which values its custom
regex managers read from a file, under Renovate's own rules - the file in ignorePaths read for nothing, a dependency a
rule turns off whole moved by nothing. One reading for every harness that asks "does Renovate move this?" (each had its
own, and they disagreed: one honoured ignorePaths, one the rules, one matched a made-up path). Run from the ops root."""
import fnmatch
import json
import re

PRESET = json.load(open("renovate/upgrade-cycle.json"))


def matches(pattern, value):
    """Renovate's pattern: /regex/ (a search, its flags after the last slash), else a glob or an exact name."""
    if pattern.startswith("/") and pattern.rindex("/") > 0:
        return re.search(pattern[1:pattern.rindex("/")], value) is not None
    return fnmatch.fnmatchcase(value, pattern)


def ignored(path):
    return any(fnmatch.fnmatch(path, g) for g in PRESET.get("ignorePaths", []))


def off(path, dep):
    """A rule turns the dependency off whole (no update type narrowing it): Renovate never moves it."""
    for r in PRESET["packageRules"]:
        if r.get("enabled") is False and not r.get("matchUpdateTypes"):
            files, names = r.get("matchFileNames"), (r.get("matchPackageNames") or []) + (r.get("matchDepNames") or [])
            if (files is None or any(fnmatch.fnmatch(path, g) for g in files)) and (not names or any(matches(n, dep) for n in names)):
                return True
    return False


def managers(path):
    return [m for m in PRESET["customManagers"] if any(matches(p, path) for p in m["managerFilePatterns"])]


def parent_key(text, line_start, indent):
    """The nearest line above line_start, less indented, that opens a map ('<key>:' alone): its key match, or None"""
    for line in reversed(text[:line_start].split("\n")):
        if line.strip() and len(line) - len(line.lstrip()) < indent:
            return re.match(r"\s*([A-Za-z0-9_]+):\s*$", line)
    return None


def reads(path, text=None):
    """Each value the preset's custom managers move in the file: {line, key, datasource, depName, currentValue,
    currentDigest} - line 0-based, key the YAML key on that line (or None). Nothing for an ignored file; a dependency
    turned off left out. The file is read only when a manager's pattern names it."""
    found = managers(path)
    if not found or ignored(path):
        return []
    if text is None:
        text = open(path, encoding="utf-8", errors="replace").read()
    out = []
    for m in found:
        for s in m["matchStrings"]:
            for g in re.finditer(s.replace("(?<", "(?P<"), text):
                d = g.groupdict()
                if off(path, d["depName"]):
                    continue
                start = g.start("currentValue")
                line = text[text.rfind("\n", 0, start) + 1:].split("\n", 1)[0]
                key = re.match(r"\s*([A-Za-z0-9_]+):", line)
                if key is None:  # an entry of a map (a quoted key: "18": ...) - the key of the map holding it
                    key = parent_key(text, text.rfind("\n", 0, start) + 1, len(line) - len(line.lstrip()))
                out.append({"line": text.count("\n", 0, start), "key": key.group(1) if key else None,
                            "datasource": d.get("datasource") or m.get("datasourceTemplate"), "depName": d["depName"],
                            "currentValue": d["currentValue"], "currentDigest": d.get("currentDigest")})
    return out


def manual(dep):
    """The dependency goes to a manual- unit (additionalBranchPrefix): the runner never picks it - the last rule naming
    it decides, as Renovate applies rules in order."""
    prefix = None
    for r in PRESET["packageRules"]:
        names = (r.get("matchPackageNames") or []) + (r.get("matchDepNames") or [])
        if names and any(matches(n, dep) for n in names) and "additionalBranchPrefix" in r:
            prefix = r["additionalBranchPrefix"]
    return prefix == "manual-"


def listed(value, patterns):
    """A rule's name list as Renovate's string-match reads it (dist/util/string-match.js, 44.198.3): a positive pattern
    must match if there is one, and every negated one (!pattern) must hold - a list of negations alone matches all
    else."""
    pos = [p for p in patterns if not p.startswith("!")]
    return (not pos or any(_hit(value, p) for p in pos)) and all(not _hit(value, p[1:]) for p in patterns if p.startswith("!"))


def _hit(value, pattern):
    if pattern == "*":
        return True
    if pattern.startswith("/") and pattern.rindex("/") > 0:
        return re.search(pattern[1:pattern.rindex("/")], value) is not None
    return fnmatch.fnmatchcase(value.lower(), pattern.lower())


def _applies(rule, pkg, kind, path, given):
    """The rule matches the update: its update types, its names (packages and deps), its files, and its repository,
    manager or datasource lists - each of those only when the update names one it lists."""
    names = rule.get("matchPackageNames", []) + rule.get("matchDepNames", [])
    return (("matchUpdateTypes" not in rule or kind in rule["matchUpdateTypes"])
            and (not names or listed(pkg, names))
            and ("matchFileNames" not in rule or any(fnmatch.fnmatch(path, g) for g in rule["matchFileNames"]))
            and not any(k in rule and (v is None or v not in rule[k]) for k, v in given.items()))


def resolved(pkg, kind=None, path="helm/schnappy/values.yaml", preset=None, repo=None, manager=None, datasource=None):
    """The settings an update ends with, as Renovate merges the rules: in order, a later one overriding, the group object
    merged key by key (so a group.branchTopic set earlier stays on a rule that names none). kind None: what Renovate
    reads before an update has a type (a rule with matchUpdateTypes left out). preset: another preset's dict
    (renovate/apps.json); a rule matching on the repository, the manager or the datasource applies only when the update
    names one it lists."""
    c = {"group": {}}
    given = {"matchRepositories": repo, "matchManagers": manager, "matchDatasources": datasource}
    for r in (rule for rule in (preset or PRESET)["packageRules"] if _applies(rule, pkg, kind, path, given)):
        c["group"].update(r.get("group", {}))
        c.update({k: v for k, v in r.items() if k != "group" and not k.startswith("match") and k != "description"})
    return c


def branch(pkg, kind, path="helm/schnappy/values.yaml", version="1.2.0", preset=None, **given):
    """The update's unit (its branch past renovate/): a group's topic, "own" for a branch of its own, None when off."""
    preset = preset or PRESET
    c = resolved(pkg, kind, path, preset, **given)
    if c.get("enabled") is False:
        return None
    if "groupName" not in c:
        return c.get("additionalBranchPrefix", "") + "own"
    major, minor = version.split(".")[:2]
    # no topic of its own: Renovate names it by the slug, prefixed for a major or a patch of a group (branchify:
    # major-[<newMajor>-]<slug>, patch-<slug> - renovate/patch-wave-patches before the topics were set, 2026-11-16)
    slug = c["groupSlug"]
    if kind == "major" and c.get("separateMajorMinor", preset.get("separateMajorMinor", True)):
        slug = ("major-%s-" % major if c.get("separateMultipleMajor", preset.get("separateMultipleMajor")) else "major-") + slug
    elif kind == "patch" and c.get("separateMinorPatch", preset.get("separateMinorPatch")):
        slug = "patch-" + slug
    topic = c["group"].get("branchTopic", slug).replace("{{{newMajor}}}", major).replace("{{{newMinor}}}", minor)
    return c.get("additionalBranchPrefix", "") + topic
