#!/bin/bash
# The production rollout's ledger (scripts/upgrade-production.py): which phase of which step may run, given the
# events so far - each refusal against the real step files where it matters (their branch order and wave0 lines),
# the soak, and the own-change hash the merge compares with the full run's proof.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
python3 - <<'EOF'
import datetime
import importlib.machinery
import importlib.util
import sys

loader = importlib.machinery.SourceFileLoader("upgrade_production", "scripts/upgrade-production.py")
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("upgrade_production", loader))
loader.exec_module(m)

fails = 0
T0 = datetime.datetime(2026, 10, 6, 8, 0, tzinfo=datetime.timezone.utc)


def check(name, got, want):
    global fails
    ok = got == want
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f"\n  got  {got}\n  want {want}"))


def refused(name, got, words):
    """A refusal whose reason names `words`."""
    check(name, bool(got) and all(any(w in g for g in got) for w in words), True)


def ev(*lines):
    return [(T0 + datetime.timedelta(minutes=i), *l.split()[:2], l.split()[2:]) for i, l in enumerate(lines)]


names = m.step_names()
info = {n: m.step_info(n) for n in names}
done_upto = lambda last: [f"{n} done" for n in names[:names.index(last) + 1]]

# the real step files' facts the rules below lean on (a change to them should fail here, not in production)
check("47 merges infra, then platform", info["47-postgres-18"]["branches"], ["infra", "platform"])
check("54 merges platform, then infra", info["54-tempo-3"]["branches"], ["platform", "infra"])
check("47 backs up postgres first, soaks 60 min", (info["47-postgres-18"]["wave0"], info["47-postgres-18"]["soak"]),
      (["postgres"], 60))
i01 = info["01-argocd-root-retry"]
check("01 has no wave0 line, soaks 15 min", (i01["wave0"], i01["soak"]), ([], 15))
i37 = info["37-strimzi-conversion"]
check("37 has playbooks and leaves strimzi out of sync", (bool(i37["playbooks"]), i37["out_of_sync"]),
      (True, ["strimzi"]))

P = lambda step, phase, events, arg=None: m.problems(names, step, phase, events, info[step], arg)

# begin: every earlier step done; once
refused("begin 03 with 01 not done (00 and 02 are; 02 before the ledger)",
        P("03-istio-1.26", "begin", ev("00-gluster-boot done", "02-istio-chart-repo done")), ["01-argocd-root-retry"])
check("begin 01 with 00 and 02 done", P("01-argocd-root-retry", "begin",
                                        ev("00-gluster-boot done", "02-istio-chart-repo done")), [])
refused("begin 01 before 00", P("01-argocd-root-retry", "begin", ev("02-istio-chart-repo done")), ["00-gluster-boot"])
check("begin 00 first", P("00-gluster-boot", "begin", ev("02-istio-chart-repo done")), [])
check("begin 47 with 01..46 done", P("47-postgres-18", "begin", ev(*done_upto("46-postgres-18-test"))), [])
refused("begin 47 with 45 missing",
        P("47-postgres-18", "begin", ev(*[l for l in done_upto("46-postgres-18-test") if not l.startswith("45-")])),
        ["45-alertmanager-blackbox-ksm"])
refused("begin twice", P("01-argocd-root-retry", "begin", ev("01-argocd-root-retry begun")), ["begun already"])
refused("a done step refuses every phase", P("01-argocd-root-retry", "merge", ev("01-argocd-root-retry done"), "infra"),
        ["is done"])

# nothing before begin
for phase, arg in (("backup", "postgres"), ("merge", "infra"), ("playbooks", None), ("done", None), ("preview", None)):
    refused(f"{phase} before begin", P("47-postgres-18", phase, [], arg), ["not begun"])

S47 = "47-postgres-18"
b = [f"{S47} begun"]
# backup: only the step's own stores
check("backup postgres at 47", P(S47, "backup", ev(*b), "postgres"), [])
refused("backup kafka at 47", P(S47, "backup", ev(*b), "kafka"), ["backs up no kafka"])
# merge: after the backups, in the file's order
refused("merge 47 infra before its backup", P(S47, "merge", ev(*b), "infra"), ["not backed up yet: postgres"])
bb = b + [f"{S47} backup postgres"]
check("merge 47 infra after its backup", P(S47, "merge", ev(*bb), "infra"), [])
refused("merge 47 platform before infra settled", P(S47, "merge", ev(*bb), "platform"), ["merge infra first"])
refused("merge 47 platform with infra merged, not settled",
        P(S47, "merge", ev(*bb, f"{S47} merged infra abc"), "platform"), ["merge infra first"])
check("merge 47 infra again after merged, not settled (the settle resumes)",
      P(S47, "merge", ev(*bb, f"{S47} merged infra abc"), "infra"), [])
bs = bb + [f"{S47} merged infra abc", f"{S47} settled infra abc"]
check("merge 47 platform after infra settled", P(S47, "merge", ev(*bs), "platform"), [])
refused("merge 47 infra twice", P(S47, "merge", ev(*bs), "infra"), ["merged and settled already"])
refused("merge a repo the step has no branch for", P("01-argocd-root-retry", "merge", ev("01-argocd-root-retry begun"),
                                                     "platform"), ["no platform branch line"])
# playbooks: after every merge settled and the preview
refused("playbooks 47 before platform settled", P(S47, "playbooks", ev(*bs, f"{S47} previewed"), None), ["platform"])
ball = bs + [f"{S47} merged platform def", f"{S47} settled platform def"]
refused("playbooks 47 without the preview", P(S47, "playbooks", ev(*ball)), ["not previewed"])
check("playbooks 47 after the preview", P(S47, "playbooks", ev(*ball, f"{S47} previewed")), [])
# the preview: after every merge settled (its playbooks read the cluster the merges leave)
refused("preview 47 before its merges", P(S47, "preview", ev(*bb)), ["not merged and settled yet"])
refused("preview 47 with only infra settled", P(S47, "preview", ev(*bs)), ["platform"])
check("preview 47 after both merges settled", P(S47, "preview", ev(*ball)), [])
# the order `deploy:upgrade:status` names the next phase in: step 47's pinned, every step's preview after its merges
check("47's phases in order", [(p, a) for p, a, _ in m.phases(info[S47])],
      [("begin", None), ("backup", "postgres"), ("merge", "infra"), ("merge", "platform"), ("preview", None),
       ("playbooks", None), ("done", None)])
order = {n: [p for p, _, _ in m.phases(info[n])] for n in names}
check("every step's preview after its merges",
      [n for n, o in order.items() if "preview" in o and "merge" in o
       and o.index("preview") < max(i for i, p in enumerate(o) if p == "merge")], [])
refused("playbooks 47 twice", P(S47, "playbooks", ev(*ball, f"{S47} previewed", f"{S47} playbooks")), ["ran already"])
refused("playbooks at a step without playbook lines", P("54-tempo-3", "playbooks", ev("54-tempo-3 begun")),
        ["no playbook lines"])
# done: after the playbook lines
refused("done 47 before its playbook lines", P(S47, "done", ev(*ball, f"{S47} previewed")),
        ["playbook lines have not run"])
check("done 47 after them", P(S47, "done", ev(*ball, f"{S47} previewed", f"{S47} playbooks")), [])
refused("done 01 before its merge", P("01-argocd-root-retry", "done", ev("01-argocd-root-retry begun")),
        ["not merged and settled yet: infra"])

# defaults: after the playbook lines, before done - only a step with default lines
S42 = "42-kubernetes-1.35"
check("42 moves playbook defaults; 47 none", (info[S42]["defaults"], info[S47]["defaults"]), (True, False))
d42 = [f"{S42} begun", f"{S42} backup etcd", f"{S42} merged infra a", f"{S42} settled infra a", f"{S42} previewed"] \
    if "etcd" in info[S42]["wave0"] else [f"{S42} begun", f"{S42} merged infra a", f"{S42} settled infra a",
                                          f"{S42} previewed"]
refused("defaults 42 before its playbook lines", P(S42, "defaults", ev(*d42)), ["playbook lines have not run"])
check("defaults 42 after them", P(S42, "defaults", ev(*d42, f"{S42} playbooks")), [])
refused("done 42 without its defaults", P(S42, "done", ev(*d42, f"{S42} playbooks")), ["defaults are not committed"])
check("done 42 with them", P(S42, "done", ev(*d42, f"{S42} playbooks", f"{S42} defaults abc")), [])
refused("defaults twice", P(S42, "defaults", ev(*d42, f"{S42} playbooks", f"{S42} defaults abc")),
        ["committed already"])
refused("defaults at a step without default lines", P(S47, "defaults", ev(*ball, f"{S47} previewed",
                                                                        f"{S47} playbooks")), ["no default lines"])

# the soak
e = ev(f"{S47} checked")
check("soak: 60 min from checked, 10 min in", m.soak_state(e, S47, 60, T0 + datetime.timedelta(minutes=10))[1], 3000.0)
check("soak: over after 60 min", m.soak_state(e, S47, 60, T0 + datetime.timedelta(minutes=61))[1], 0.0)
check("soak: a check-failed starts it again", m.soak_state(ev(f"{S47} checked", f"{S47} check-failed"), S47, 60, T0),
      (None, None))
check("soak: the latest checked after a failure",
      m.soak_state(ev(f"{S47} checked", f"{S47} check-failed", f"{S47} checked"), S47, 60,
                   T0 + datetime.timedelta(minutes=2))[0], T0 + datetime.timedelta(minutes=2))
check("ledger lines parse", m.parse_events("2026-10-06T08:00:00Z 47-postgres-18 merged infra abc\n"),
      [(T0, "47-postgres-18", "merged", ["infra", "abc"])])

# the own-change hash: the same change rebased (other line numbers) is the same; another change, file or line is not
D = lambda path, at, lines: (f"diff --git a/{path} b/{path}\nindex 1..2 100644\n--- a/{path}\n+++ b/{path}\n"
                             f"@@ -{at} +{at} @@\n" + "".join(l + "\n" for l in lines))
base = m.own_hash(D("values.yaml", 10, ["-  image: a:1", "+  image: a:2"]))
check("own: the same change at another line",
      m.own_hash(D("values.yaml", 42, ["-  image: a:1", "+  image: a:2"])), base)
check("own: another value differs", m.own_hash(D("values.yaml", 10, ["-  image: a:1", "+  image: a:3"])) != base, True)
check("own: another file differs", m.own_hash(D("other.yaml", 10, ["-  image: a:1", "+  image: a:2"])) != base, True)
check("own: a line more differs",
      m.own_hash(D("values.yaml", 10, ["-  image: a:1", "+  image: a:2", "+  pull: Always"])) != base, True)

# image names as containerd lists them, so the inventory's floating tags meet the preload's digests
check("full name: a library image", m.full_name("postgres"), "docker.io/library/postgres")
check("full name: a Docker Hub image", m.full_name("valkey/valkey"), "docker.io/valkey/valkey")
check("full name: a registry's", m.full_name("ghcr.io/cloudnative-pg/postgresql"), "ghcr.io/cloudnative-pg/postgresql")
check("full name: a registry with a port", m.full_name("localhost:5000/x"), "localhost:5000/x")

print("upgrade-ledger: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
EOF
