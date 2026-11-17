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
