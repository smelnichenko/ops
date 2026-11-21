"""upgrade-report.py <report.json>: Renovate's report of a lookup (RENOVATE_REPORT_TYPE=file) as what an upgrade would bring -
per repository, ONE line per dependency - every tag it has now (files that disagree listed together) -> the newest tag
offered (any other noted) - and a rebuild of the same tag (a digest update: same tag, new image) said as such. A tag's
flavours (25.0.4_7-jdk and -jre, one version) each paired with its own target on that line. Then every dependency
pinned at more than one version across the repositories - its version without the flavour (operator 2026-11-21: "we
should not have different versions for different modules") - whether or not an update is offered. Renovate's notes
once, at the end. Read by scripts/upgrade-renovate.sh --lookup (task upgrade:check, upgrade:apps:check). Exit 1 when
the report is missing or not Renovate's."""
import json
import re
import signal
import sys

signal.signal(signal.SIGPIPE, signal.SIG_DFL)   # piped into head: quiet
REBUILD = {"digest", "pinDigest"}
VERSION = re.compile(r"v?(\d+(?:[._+]\d+)*)")


def tag(x, which):
    """the tag as written in the file (17-alpine), not Renovate's normalised version (17)"""
    return x.get(f"{which}Value") or x.get(f"{which}Version") or "?"


def numbers(v):
    # its numbers alone (1.31.9-alpine above 1.31-alpine: a tag's suffix is no part of its version), the tag a tiebreak
    return [int(p) for p in re.findall(r"\d+", v)], v


def order(u):
    return numbers(u.get("newVersion") or u.get("newValue") or "")


def flavour(t):
    """what a tag adds to its version (-jdk, -alpine) - tags of one flavour share a line's targets"""
    m = VERSION.match(t)
    return t[m.end():] if m else t


def version_of(v):
    """the version a pin names, as written: its numbers alone (^1.58.2 -> 1.58.2, 25.0.4_7-jdk -> 25.0.4_7)"""
    m = re.search(r"\d+(?:[._+]\d+)*", v)
    return m.group(0) if m else v


def apart(a, b):
    """two pins of one dependency that disagree - neither the other's line (25 and 25.0.4 agree: one names the line the
    other is in)"""
    x, y = numbers(a)[0], numbers(b)[0]
    n = min(len(x), len(y))
    return x[:n] != y[:n]


def package_files(r):
    return [f for files in (r.get("packageFiles") or {}).values() for f in files]


def branch_updates(r):
    return [(u.get("depName", "?"), tag(u, "current"), u, u.get("packageFile") or "")
            for b in r.get("branches") or [] for u in b.get("upgrades") or []]


def lookup_updates(r):
    return [(d.get("depName", "?"), tag(d, "current"), u, f.get("packageFile") or "")
            for f in package_files(r) for d in f.get("deps") or [] for u in d.get("updates") or []]


def ups_of(r):
    """(dep, current tag, update, file) for each update found: a full run's under the branches it built, a lookup's
    under each dependency"""
    return branch_updates(r) or lookup_updates(r)


def collect(r):
    """{dep: {flavour: {currents, targets, rebuild}}, files per dep}"""
    deps, files = {}, {}
    for dep, cur, u, where in ups_of(r):
        e = deps.setdefault(dep, {}).setdefault(flavour(cur), {"currents": set(), "targets": {}, "rebuild": {}})
        e["currents"].add(cur)
        if u.get("updateType") in REBUILD:
            e["rebuild"][cur] = (u.get("newDigest") or "")[7:14]
        else:
            e["targets"][tag(u, "new")] = u
        if where:
            files.setdefault(dep, set()).add(where)
    return deps, files


def where_of(files):
    if not files:
        return ""
    more = f" +{len(files) - 1}" if len(files) > 1 else ""
    return f"  [{files[0]}{more}]"


def segment(e):
    """one flavour's part of a line: its tags now -> the newest (kind, the others offered), or its rebuild"""
    cur = ", ".join(sorted(e["currents"], key=numbers))
    rebuilt = sorted(e["rebuild"])
    if not e["targets"]:
        return f"{cur} - same tag, new image (digest {', '.join(e['rebuild'][c] for c in rebuilt)})"
    ts = sorted(e["targets"].values(), key=order)
    also = [tag(t, "new") for t in ts[:-1]] + [f"{c} rebuilt" for c in rebuilt]
    extra = f", also offered: {', '.join(also)}" if also else ""
    return f"{cur} -> {tag(ts[-1], 'new')} ({ts[-1].get('updateType') or ''}{extra})"


def show_repo(repo, r):
    deps, files = collect(r)
    if not deps:
        print(f"{repo}: nothing to update")
        return 0
    print(f"{repo}: {len(deps)} to update")
    for dep, flavours in sorted(deps.items()):
        line = "; ".join(segment(e) for _, e in sorted(flavours.items()))
        print(f"  {dep}: {line}{where_of(sorted(files.get(dep, ())))}")
    return len(deps)


def pins_of(repos):
    """each dependency's pins across every repository and file (Renovate's view, an update or not): {name: {version:
    {tags}, ...}, where}"""
    pins = {}
    for repo, r in sorted(repos.items()):
        for f in package_files(r):
            for d in f.get("deps") or []:
                # what each pin resolves to (mise's `java = "25"` -> 25.0.5+8: within the line 25, no drift - apart())
                name, v = d.get("packageName") or d.get("depName"), d.get("currentVersion") or d.get("currentValue")
                if d.get("skipReason") or not name or not v:
                    continue
                at = pins.setdefault(name, {}).setdefault(version_of(v), {"tags": set(), "where": set()})
                at["tags"].add(d.get("currentValue") or v)
                at["where"].add(f"{repo.split('/')[-1]}:{f.get('packageFile', '?')}")
    return pins


def show_drift(repos):
    drift = {n: vs for n, vs in pins_of(repos).items() if any(apart(a, b) for a in vs for b in vs)}
    if not drift:
        print("one version of each dependency everywhere")
        return
    print(f"DIFFERENT VERSIONS of one dependency: {len(drift)}")
    for name, vs in sorted(drift.items()):
        at = [f"{', '.join(sorted(p['tags']))} [{', '.join(sorted(p['where']))}]" for _, p in sorted(vs.items(), key=lambda kv: numbers(kv[0]))]
        print(f"  {name}: pinned at " + "; ".join(at))


def notes_of(report):
    notes = set()
    for r in report["repositories"].values():
        for pr in (r.get("problems") or []) + (report.get("problems") or []):
            msg = pr.get("msg") or pr.get("message") or str(pr)
            notes.add(msg.split("See debug logs")[0].rstrip())
    return notes


def main(path):
    try:
        report = json.load(open(path))
        repos = report["repositories"]
    except (OSError, ValueError, KeyError) as e:
        print(f"no Renovate report to read ({e})", file=sys.stderr)
        return 1
    total = sum(show_repo(repo, r) for repo, r in sorted(repos.items()))
    print(f"{total} to update in all" if total else "nothing to update anywhere")
    show_drift(repos)
    for n in sorted(notes_of(report)):
        print(f"note (Renovate): {n}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: upgrade-report.py <report.json>", file=sys.stderr)
        sys.exit(1)
    sys.exit(main(sys.argv[1]))
