"""upgrade-report.py <report.json>: Renovate's report of a lookup (RENOVATE_REPORT_TYPE=file) as what an upgrade would bring -
per repository, ONE line per dependency - every tag it has now (files that disagree listed together) -> the newest tag
offered (any other noted) - and a rebuild of the same tag (a digest update: same tag, new image) said as such. Then
every dependency pinned at more than one version across the repositories (operator 2026-11-21: "we should not have
different versions for different modules") - whether or not an update is offered. Renovate's notes once, at the end. Read by
scripts/upgrade-renovate.sh --lookup (task upgrade:check, upgrade:apps:check). Exit 1 when the report is missing or
not Renovate's."""
import json
import re
import signal
import sys

signal.signal(signal.SIGPIPE, signal.SIG_DFL)   # piped into head: quiet
REBUILD = {"digest", "pinDigest"}


def tag(x, which):
    """the tag as written in the file (17-alpine), not Renovate's normalised version (17)"""
    return x.get(f"{which}Value") or x.get(f"{which}Version") or "?"


def order(u):
    v = u.get("newVersion") or u.get("newValue") or ""
    # its numbers alone (1.31.9-alpine above 1.31-alpine: a tag's suffix is no part of its version), the tag a tiebreak
    return [int(p) for p in re.findall(r"\d+", v)], v


def ups_of(r):
    """(dep, current tag, update) for each update found: a lookup's are under each dependency; a full run's under the
    branches it built"""
    out = []
    for b in r.get("branches") or []:
        for u in b.get("upgrades") or []:
            out.append((u.get("depName", "?"), tag(u, "current"), u, u.get("packageFile") or ""))
    if out:
        return out
    for files in (r.get("packageFiles") or {}).values():
        for f in files:
            for d in f.get("deps") or []:
                for u in d.get("updates") or []:
                    out.append((d.get("depName", "?"), tag(d, "current"), u, f.get("packageFile") or ""))
    return out


try:
    report = json.load(open(sys.argv[1]))
    repos = report["repositories"]
except (OSError, ValueError, KeyError, IndexError) as e:
    print(f"no Renovate report to read ({e})", file=sys.stderr)
    sys.exit(1)
total = 0
notes = set()
for repo, r in sorted(repos.items()):
    deps = {}
    for dep, cur, u, where in ups_of(r):
        e = deps.setdefault(dep, {"currents": set(), "targets": {}, "rebuild": {}, "files": set()})
        e["currents"].add(cur)
        if u.get("updateType") in REBUILD:
            e["rebuild"][cur] = (u.get("newDigest") or "")[7:14]
        else:
            e["targets"][tag(u, "new")] = u
        e["files"].add(where)
    if not deps:
        print(f"{repo}: nothing to update")
    else:
        total += len(deps)
        print(f"{repo}: {len(deps)} to update")
        for dep, e in sorted(deps.items()):
            files = sorted(f for f in e["files"] if f)
            where = f"  [{files[0]}" + (f" +{len(files) - 1}" if len(files) > 1 else "") + "]" if files else ""
            cur = ", ".join(sorted(e["currents"], key=lambda v: order({"newVersion": v})))
            rebuilt = sorted(e["rebuild"])
            rebuild = f"same tag, new image (digest {', '.join(e['rebuild'][c] for c in rebuilt)})" if rebuilt else ""
            if e["targets"]:
                ts = sorted(e["targets"].values(), key=order)
                newest = ts[-1]
                also = [tag(t, "new") for t in ts[:-1]] + [f"{c} rebuilt" for c in rebuilt]
                kind = newest.get("updateType") or ""
                print(f"  {dep}: {cur} -> {tag(newest, 'new')} ({kind}" + (f", also offered: {', '.join(also)}" if also else "") + f"){where}")
            else:
                print(f"  {dep}: {cur} - {rebuild}{where}")
    for pr in (r.get("problems") or []) + (report.get("problems") or []):
        notes.add(re.sub(r"\s*See debug logs.*$", "", pr.get("msg") or pr.get("message") or str(pr)))
print(f"{total} to update in all" if total else "nothing to update anywhere")
# one version everywhere: each dependency's pins across every repository and file (Renovate's view, an update or not)
pins = {}
for repo, r in sorted(repos.items()):
    for files in (r.get("packageFiles") or {}).values():
        for f in files:
            for d in f.get("deps") or []:
                name, v = d.get("packageName") or d.get("depName"), d.get("currentVersion") or d.get("currentValue")
                if d.get("skipReason") or not name or not v:
                    continue
                pins.setdefault(name, {}).setdefault(v.lstrip("v"), set()).add(f"{repo.split('/')[-1]}:{f.get('packageFile', '?')}")
drift = {n: vs for n, vs in pins.items() if len(vs) > 1}
if drift:
    print(f"DIFFERENT VERSIONS of one dependency: {len(drift)}")
    for name, vs in sorted(drift.items()):
        print(f"  {name}: pinned at " + "; ".join(f"{v} [{', '.join(sorted(w))}]" for v, w in sorted(vs.items(), key=lambda kv: order({"newVersion": kv[0]}))))
else:
    print("one version of each dependency everywhere")
for n in sorted(notes):
    print(f"note (Renovate): {n}")
