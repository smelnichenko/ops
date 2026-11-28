#!/bin/bash
# scripts/vagrant-gitops-mirror.py's left_out: what only the apps the copy leaves out (INFRA_DROP's Application files)
# render - their sources' paths in infra or platform and their $values files, less what an app the copy keeps renders too
# (the preview environments' ApplicationSet renders platform's helm/schnappy, as production's apps do) - and a change's
# files there: said "PROVEN IN PRODUCTION ALONE" and written to .copy/left-out.txt for the runner to hand to the review
# (the wave-patches review, 2026-11-28: Woodpecker's Postgres digest and SonarQube's images read as proven on the copy).
# Against an infra and a platform repository of its own, each with origin/main and a change's branch.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
exec "$PY" - "$PWD" <<'PY_LEFT_OUT'
import importlib.machinery, importlib.util, os, subprocess, sys, tempfile
ops = sys.argv[1]
L = importlib.machinery.SourceFileLoader("mirror", os.path.join(ops, "scripts", "vagrant-gitops-mirror.py"))
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("mirror", L))
L.exec_module(m)
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f"\n    got:  {got!r}\n    want: {want!r}"))
W = tempfile.mkdtemp()
def repo(name, files, change):
    """a repository with origin/main holding files, and the branch 'change' adding change's files on it"""
    d = os.path.join(W, name)
    g = lambda *a: subprocess.run(["git", "-C", d, *a], check=True, capture_output=True)
    os.makedirs(d)
    g("init", "-q", "-b", "main")
    for f, body in files.items():
        os.makedirs(os.path.dirname(os.path.join(d, f)) or d, exist_ok=True)
        open(os.path.join(d, f), "w").write(body)
    g("add", "-A"); g("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "main")
    g("update-ref", "refs/remotes/origin/main", "HEAD")
    g("checkout", "-q", "-b", "change")
    for f, body in change.items():
        os.makedirs(os.path.dirname(os.path.join(d, f)), exist_ok=True)
        open(os.path.join(d, f), "w").write(body)
    g("add", "-A"); g("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "change")
    g("checkout", "-q", "main")
    return d
APPS = "clusters/production/argocd/apps/"
I = "https://git.pmon.dev/schnappy/infra.git"
P = "https://git.pmon.dev/schnappy/platform.git"
infra_files = {
    # left out: Woodpecker (its manifests and its $values file), SonarQube (platform's chart, its values), the previews
    APPS + "woodpecker.yaml": f"""kind: Application
spec:
  sources:
    - repoURL: ghcr.io/woodpecker-ci/helm
      helm: {{valueFiles: [$values/clusters/production/woodpecker/values.yaml]}}
    - {{repoURL: {I}, ref: values}}
    - {{repoURL: {I}, path: clusters/production/woodpecker/manifests}}
""",
    APPS + "schnappy-sonarqube.yaml": f"""kind: Application
spec:
  sources:
    - repoURL: {P}
      path: helm/schnappy-sonarqube
      helm: {{valueFiles: [$values/clusters/production/schnappy-sonarqube/values.yaml]}}
    - {{repoURL: {I}, ref: values}}
""",
    APPS + "schnappy-pr-envs.yaml": f"""kind: ApplicationSet
spec:
  template:
    spec:
      source: {{repoURL: {P}, path: helm/schnappy}}
""",
    # kept: production's apps (the same chart the previews render), its data
    APPS + "schnappy-apps-envs.yaml": f"""kind: ApplicationSet
spec:
  template:
    spec:
      sources:
        - {{repoURL: {P}, path: helm/schnappy, helm: {{valueFiles: ["$values/clusters/production/schnappy-{{{{.env}}}}-apps/values.yaml"]}}}}
        - {{repoURL: {I}, ref: values}}
""",
    APPS + "schnappy-data.yaml": f"""kind: Application
spec:
  source: {{repoURL: {I}, path: clusters/production/schnappy-production-data}}
""",
    "clusters/production/woodpecker/manifests/postgres.yaml": "image: postgres@sha256:old\n",
}
infra = repo("infra", infra_files, {
    "clusters/production/woodpecker/manifests/postgres.yaml": "image: postgres@sha256:new\n",
    "clusters/production/woodpecker/values.yaml": "agent: {}\n",
    "clusters/production/schnappy-production-data/notes.yaml": "x: 1\n",
    "clusters/production/woodpecker-notes.md": "a sibling, not under the path\n",
})
platform = repo("platform", {"helm/schnappy/values.yaml": "a: 1\n", "helm/schnappy-sonarqube/values.yaml": "b: 1\n"}, {
    "helm/schnappy/values.yaml": "a: 2\n",
    "helm/schnappy-sonarqube/templates/setup.yaml": "image: curlimages/curl:8.23.0\n",
})
saved = m.INFRA_DROP
m.INFRA_DROP = [APPS + "woodpecker.yaml", APPS + "schnappy-sonarqube.yaml", APPS + "schnappy-pr-envs.yaml"]
paths = m.left_out_paths(infra, "change")
check("what only the left-out apps render: their sources' paths and $values files - not helm/schnappy (production's apps "
      "render it too), not a kept app's path, not a chart from a registry",
      sorted(paths), [("infra", "clusters/production/schnappy-sonarqube/values.yaml"), ("infra", "clusters/production/woodpecker/manifests"),
                      ("infra", "clusters/production/woodpecker/values.yaml"), ("platform", "helm/schnappy-sonarqube")])
check("a change's files there, each repo's: Woodpecker's manifest and values, SonarQube's template - never a kept app's file, "
      "a sibling named alike, or a file of the chart the copy runs",
      (m.left_out("infra", infra, "change", paths), m.left_out("platform", platform, "change", paths)),
      (["infra/clusters/production/woodpecker/manifests/postgres.yaml", "infra/clusters/production/woodpecker/values.yaml"],
       ["platform/helm/schnappy-sonarqube/templates/setup.yaml"]))
check("  main (no change mirrored): none", (m.left_out("infra", infra, "main", paths), m.left_out("platform", platform, "main", paths)), ([], []))
# main(): both refs judged, the list written (and said) before anything is pushed
class Stop(Exception):
    pass
def api(*a, **k):
    raise Stop()
m.api = api
m.WORK = os.path.join(W, "work")
def mirror(infra_ref, platform_ref):
    sys.argv = ["mirror", "--forgejo", "192.168.56.20:3000", "--infra", infra, "--platform", platform,
                "--infra-ref", infra_ref, "--platform-ref", platform_ref]
    from io import StringIO
    out, real = StringIO(), sys.stdout
    sys.stdout = out
    try:
        m.main()
    except Stop:
        pass
    finally:
        sys.stdout = real
    return out.getvalue().splitlines(), open(os.path.join(m.WORK, "left-out.txt")).read().splitlines()
said, written = mirror("change", "change")
check("main(): each file said PROVEN IN PRODUCTION ALONE, and written to .copy/left-out.txt, before the first push",
      ([l.split(": ", 1)[1] for l in said if l.startswith("PROVEN IN PRODUCTION ALONE")], written),
      (["infra/clusters/production/woodpecker/manifests/postgres.yaml", "infra/clusters/production/woodpecker/values.yaml",
        "platform/helm/schnappy-sonarqube/templates/setup.yaml"],) * 2)
check("  main at both: the list written empty (a later read never takes an earlier change's)", mirror("main", "main")[1], [])
m.INFRA_DROP = saved
check("INFRA_DROP's own Application files are what left_out reads (the copy's list, not a copy of it)",
      all(d.startswith(APPS) or d.startswith("clusters/production/schnappy-test") for d in m.INFRA_DROP), True)
print("mirror-left-out: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_LEFT_OUT
