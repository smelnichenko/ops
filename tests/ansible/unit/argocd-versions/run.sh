#!/bin/bash
# The Argo CD each step installs (a step's playbook line setup-argocd.yml -e argocd_version=<chart>): its image line
# what setup-argocd.yml puts on that chart - its argocd_image_pins entry, else the chart's own version (the step's helm
# line's) - and never below the release that fixed the advisories of its minor: GHSA-9v9p-x54c-58gc, -fw5c-w8rc-j7fx,
# -m3vr-7329-44ww, -fmxq-cgp8-87wp (critical: the repo-server running commands, reading files; hooks past AppProject)
# and -4439-h7jw-5cjj (the login's rate limit), fixed in v3.3.15, v3.4.10 and v3.5.4 (2026-10-06). Argo CD holds
# cluster-admin.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import os, re, sys
import yaml
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


FIXED = {"3.3": (3, 3, 15), "3.4": (3, 4, 10), "3.5": (3, 5, 4)}
play = yaml.safe_load(open("deploy/ansible/playbooks/setup-argocd.yml"))[0]
pins = play["vars"]["argocd_image_pins"]
steps = sorted(f[:-4] for f in os.listdir("tests/ansible/upgrade/steps") if f.endswith(".txt"))
seen = []
for s in steps:
    text = open(f"tests/ansible/upgrade/steps/{s}.txt").read()
    chart = re.search(r"(?m)^playbook setup-argocd\.yml .*-e argocd_version=(\S+)", text)
    if not chart:
        continue
    helm = re.search(r"(?m)^helm argocd/argocd \S+ \S+ => helm argocd/argocd argo-cd-(\S+) (v\S+)$", text)
    image = re.search(r"(?m)^image quay\.io/argoproj/argocd \S+ => image quay\.io/argoproj/argocd (v\S+)$", text)
    installs = pins.get(chart[1]) or (helm[2] if helm and helm[1] == chart[1] else None)
    version = tuple(int(x) for x in image[1][1:].split(".")) if image else None
    seen.append(s)
    check(f"{s}: its image line what setup-argocd puts on chart {chart[1]}", image[1] if image else None, installs)
    check(f"{s}: v{'.'.join(map(str, version)) if version else '?'} at least its minor's fixed release",
          version is not None and version >= FIXED.get(f"{version[0]}.{version[1]}", (0,)), True)
check("the Argo CD steps found", seen, ["31-argocd", "33-argocd-3.4", "34-argocd-3.5"])
# its chart's own NetworkPolicies off (chart 10 creates them by default, argocd-server's ingress [{}] - every pod of
# every namespace, the metrics ports too): ten's own policies for argocd stand alone, as before chart 10 (rendered:
# 9.5.11 none, 10.2.2 and 10.9.x four)
deploy = next(t for t in play["tasks"] if t.get("name") == "Deploy Argo CD")
values = deploy["kubernetes.core.helm"]["values"]
check("the chart's own NetworkPolicies off", ((values.get("global") or {}).get("networkPolicy") or {}).get("create"),
      False)
print("argocd-versions: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
