#!/bin/bash
# The Argo CD setup-argocd.yml installs by default is production's (tests/ansible/copy/prod-inventory.txt, read from
# production): its chart, and the image it puts on that chart - its argocd_image_pins entry, else the chart's own
# version (production's helm line's) - so a rebuild (DR, the Vagrant copy) runs what production runs; and that image
# never below the release that fixed the advisories of its minor: GHSA-9v9p-x54c-58gc, -fw5c-w8rc-j7fx,
# -m3vr-7329-44ww, -fmxq-cgp8-87wp (critical: the repo-server running commands, reading files; hooks past AppProject)
# and -4439-h7jw-5cjj (the login's rate limit), fixed in v3.3.15, v3.4.10 and v3.5.4 (2026-10-06). Argo CD holds
# cluster-admin.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import re, sys
import yaml
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


FIXED = {"3.3": (3, 3, 15), "3.4": (3, 4, 10), "3.5": (3, 5, 4)}
play = yaml.safe_load(open("deploy/ansible/playbooks/setup-argocd.yml"))[0]
pins = play["vars"]["argocd_image_pins"]
default = re.search(r"default\('([^']+)'\)", play["vars"]["argocd_chart_version"])[1]
inventory = open("tests/ansible/copy/prod-inventory.txt").read()
helm = re.search(r"(?m)^helm argocd/argocd argo-cd-(\S+) (v\S+)$", inventory)
image = re.search(r"(?m)^image quay\.io/argoproj/argocd (v\S+)$", inventory)
check("production's Argo CD read from its inventory (helm and image lines)", bool(helm and image), True)
if helm and image:
    check("setup-argocd's default chart is production's", default, helm[1])
    check(f"the image setup-argocd puts on chart {default} is production's", pins.get(default) or helm[2], image[1])
    version = tuple(int(x) for x in image[1][1:].split("."))
    check(f"production's {image[1]} at least its minor's fixed release",
          version >= FIXED.get(f"{version[0]}.{version[1]}", (0,)), True)
# a pin is a security floor for a chart that ships an older image: every pin at least its minor's fixed release
for chart, tag in pins.items():
    v = tuple(int(x) for x in tag[1:].split("."))
    check(f"the pin for chart {chart} ({tag}) at least its minor's fixed release", v >= FIXED.get(f"{v[0]}.{v[1]}", (0,)), True)
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
