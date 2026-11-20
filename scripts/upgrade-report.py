"""upgrade-report.py <report.json>: Renovate's report of a lookup (RENOVATE_REPORT_TYPE=file) as what an upgrade would bring -
per repository, one line per dependency: its version now -> the newest it would go to (other targets offered noted). Read by scripts/upgrade-renovate.sh --lookup (task upgrade:check, upgrade:apps:check). Exit 1 when the
report is missing or not Renovate's."""
import json
import re
import signal
import sys

signal.signal(signal.SIGPIPE, signal.SIG_DFL)   # piped into head: quiet


def ver(u, which):
    return u.get(f"{which}Version") or u.get(f"{which}Value") or u.get(f"{which}Digest", "")[:19] or "?"


try:
    report = json.load(open(sys.argv[1]))
    repos = report["repositories"]
except (OSError, ValueError, KeyError, IndexError) as e:
    print(f"no Renovate report to read ({e})", file=sys.stderr)
    sys.exit(1)
total = 0


def ups_of(r):
    """(dep, current, new, kind, file) for each update found: a lookup's are under each dependency; a full run's under
    the branches it built"""
    out = []
    for b in r.get("branches") or []:
        for u in b.get("upgrades") or []:
            out.append((u.get("depName", "?"), ver(u, "current"), ver(u, "new"), u.get("updateType") or "", u.get("packageFile") or ""))
    if out:
        return out
    for files in (r.get("packageFiles") or {}).values():
        for f in files:
            for d in f.get("deps") or []:
                for u in d.get("updates") or []:
                    out.append((d.get("depName", "?"), ver(d, "current"), ver(u, "new"), u.get("updateType") or "", f.get("packageFile") or ""))
    return out


def key(v):
    return [int(x) if x.isdigit() else x for x in re.split(r"[.\-+]", v.lstrip("v"))]


for repo, r in sorted(repos.items()):
    deps = {}
    for dep, cur, new, kind, where in ups_of(r):
        e = deps.setdefault((dep, cur), {"targets": {}, "files": set()})
        e["targets"][new] = kind
        e["files"].add(where)
    if not deps:
        print(f"{repo}: nothing to update")
    else:
        total += len(deps)
        print(f"{repo}: {len(deps)} to update")
        for (dep, cur), e in sorted(deps.items()):
            targets = sorted(e["targets"], key=lambda v: (key(v), v))
            newest = targets[-1]
            also = f", also offered: {', '.join(targets[:-1])}" if len(targets) > 1 else ""
            files = sorted(f for f in e["files"] if f)
            where = f"  [{files[0]}" + (f" +{len(files) - 1}" if len(files) > 1 else "") + "]" if files else ""
            print(f"  {dep}: {cur} -> {newest} ({e['targets'][newest]}{also}){where}")
    for msg in sorted({pr.get("msg") or pr.get("message") or str(pr) for pr in r.get("problems") or []}):
        print(f"  note: {msg}")
for msg in sorted({pr.get("msg") or pr.get("message") or str(pr) for pr in report.get("problems") or []}):
    print(f"note: {msg}")
print(f"{total} to update in all" if total else "nothing to update anywhere")
