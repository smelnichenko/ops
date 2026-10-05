#!/usr/bin/env python3
"""production-cnpg-image.py - the PostgreSQL image production's CNPG Cluster runs: the schnappy-data chart rendered as
Argo CD renders it for production (platform's chart, infra's clusters/production/schnappy-production-data/values.yaml),
from git refs, no cluster. The DR drill's Postgres takes it, so the drill restores the major production runs.

Fails unless exactly one Cluster renders, with an image.

Usage: scripts/production-cnpg-image.py [--infra-ref main] [--platform-ref main]
"""
import argparse
import os
import subprocess
import sys
import tempfile

import yaml

OPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VALUES = "clusters/production/schnappy-production-data/values.yaml"
CHART = "helm/schnappy-data"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--infra-ref", default="main")
    ap.add_argument("--platform-ref", default="main")
    a = ap.parse_args()
    infra, platform = (os.path.join(OPS, "..", r) for r in ("infra", "platform"))
    with tempfile.TemporaryDirectory() as work:
        archive = subprocess.run(["git", "-C", platform, "archive", a.platform_ref, CHART], capture_output=True,
                                 check=True).stdout
        subprocess.run(["tar", "-x", "-C", work], input=archive, check=True)
        values = os.path.join(work, "values.yaml")
        with open(values, "w") as f:
            f.write(subprocess.run(["git", "-C", infra, "show", f"{a.infra_ref}:{VALUES}"], capture_output=True,
                                   text=True, check=True).stdout)
        out = subprocess.run(["helm", "template", "schnappy-production", os.path.join(work, CHART), "-n",
                              "schnappy-production", "-f", values], capture_output=True, text=True)
        if out.returncode:
            sys.exit(f"helm template: {out.stderr.strip()}")
    clusters = [d for d in yaml.safe_load_all(out.stdout)
                if d and d.get("kind") == "Cluster" and d.get("apiVersion", "").startswith("postgresql.cnpg.io/")]
    images = [c.get("spec", {}).get("imageName") for c in clusters]
    if len(images) != 1 or not images[0]:
        sys.exit(f"expected one CNPG Cluster with an image, rendered: {images}")
    print(images[0])


if __name__ == "__main__":
    main()
