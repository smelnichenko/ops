"""upgrade-report.py <report.json>: Renovate's report of a lookup (RENOVATE_REPORT_TYPE=file) as what an upgrade run would do -
per repository, each branch it would open or update (one per unit, its pull request's title) and each dependency in it,
current -> new. Read by scripts/upgrade-renovate.sh --lookup (task upgrade:check, upgrade:apps:check). Exit 1 when the
report is missing or not Renovate's."""
import json
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


def found(r):
    """(branch, title, dep, current, new, kind, file) for each update: a lookup has no branches yet - each dependency's
    updates name the branch they would go to; a full run's branches carry them"""
    out = []
    for b in r.get("branches") or []:
        for u in b.get("upgrades") or []:
            out.append((b.get("branchName", "?"), b.get("prTitle") or "", u.get("depName", "?"), ver(u, "current"), ver(u, "new"),
                        u.get("updateType") or "", u.get("packageFile") or ""))
    if out:
        return out
    for files in (r.get("packageFiles") or {}).values():
        for f in files:
            for d in f.get("deps") or []:
                for u in d.get("updates") or []:
                    out.append((u.get("branchName", "?"), "", d.get("depName", "?"), ver(d, "current"), ver(u, "new"),
                                u.get("updateType") or "", f.get("packageFile") or ""))
    return out


for repo, r in sorted(repos.items()):
    ups = found(r)
    if not ups:
        print(f"{repo}: nothing to update")
    else:
        byb = {}
        for u in ups:
            byb.setdefault(u[0], []).append(u)
        total += len(ups)
        print(f"{repo}: {len(ups)} update(s) in {len(byb)} branch(es)")
        for name in sorted(byb):
            title = byb[name][0][1]
            print(f"  {name}" + (f"  - {title}" if title else ""))
            seen = {}
            for u in byb[name]:
                seen[u[2:]] = seen.get(u[2:], 0) + 1
            for (dep, cur, nxt, kind, where), n in sorted(seen.items()):
                print(f"    {dep}: {cur} -> {nxt}" + (f" ({kind})" if kind else "") + (f"  [{where}" + (f", {n} places" if n > 1 else "") + "]" if where else ""))
    for msg in sorted({pr.get("msg") or pr.get("message") or str(pr) for pr in r.get("problems") or []}):
        print(f"  note: {msg}")
for msg in sorted({pr.get("msg") or pr.get("message") or str(pr) for pr in report.get("problems") or []}):
    print(f"note: {msg}")
print(f"{total} update(s) in all" if total else "nothing to update anywhere")
