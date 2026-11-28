#!/usr/bin/env python3
"""The production Argo apps a unit's apply must sync: those whose chart runs a moved image in an Argo hook.

A hook (a template annotated argocd.argoproj.io/hook - k6's PostSync smoke test and its curl, the data chart's init
Jobs, SonarQube's setup Job) is out of Argo's diff, so an apply that moves only a hook's image never runs it: production
met the new version at the next unrelated sync, a failure failing that deploy (the observability review, 2026-11-25).
The runner keyed its sync on k6 alone; curl, aws-cli and postgres ride hooks too (the wave-patches review, 2026-11-28).

Each chart under the platform checkout's helm/ is read: its hook templates' images - a literal reference, or one from
its values (`image: {{ .Values.a.b }}`, a "repo:tag" string or a {repository: ...} map) - by package (the name without
tag or digest, as the unit's moves list them). A chart whose hooks run a moved package names its production app.

Usage: scripts/upgrade-hook-apps.py <unit-moves file> <platform checkout>
       prints each app to sync, one a line (each once, sorted); nothing when none. exit 2, said: a chart with a hook that
       HOOK_APPS does not name (a hook the runner would never sync - fails closed), or a hook's image that is not read
"""
import glob
import os
import re
import sys

import yaml

# every platform chart that runs a hook -> the production Argo app that renders it
HOOK_APPS = {
    "helm/schnappy": "schnappy-production-apps",
    "helm/schnappy-data": "schnappy-production-data",
    "helm/schnappy-sonarqube": "schnappy-sonarqube",
}
HOOK = "argocd.argoproj.io/hook"
IMAGE = re.compile(r"^\s*image:\s*(\S.*?)\s*$", re.M)
VALUES_REF = re.compile(r"\{\{-?\s*\.Values\.([\w.]+)\s*-?\}\}")


def package(ref):
    """An image reference's package: without its digest and its tag (a registry's port is no tag)."""
    ref = ref.strip().strip("\"'").split("@", 1)[0]
    name, sep, tag = ref.rpartition(":")
    return name if sep and "/" not in tag else ref


def value(values, path):
    """A values path's image: a string, or a map's repository; None where it is not there."""
    v = values
    for k in path.split("."):
        if not isinstance(v, dict) or k not in v:
            return None
        v = v[k]
    if isinstance(v, dict):
        v = v.get("repository")
    return v if isinstance(v, str) and v else None


def hook_packages(chart):
    """The packages the chart's hook templates run."""
    try:
        values = yaml.safe_load(open(os.path.join(chart, "values.yaml"))) or {}
    except FileNotFoundError:
        values = {}
    out = set()
    for path in sorted(glob.glob(os.path.join(chart, "templates", "*.yaml"))):
        text = open(path).read()
        if HOOK not in text:
            continue
        for m in IMAGE.finditer(text):
            ref = m.group(1)
            r = VALUES_REF.fullmatch(ref.strip("\"'"))
            if r:
                ref = value(values, r.group(1))
                if ref is None:
                    raise LookupError(f"{path}: its image {m.group(1)} - .Values.{r.group(1)} not in its values")
            elif "{{" in ref:
                raise LookupError(f"{path}: its image {ref} - not read")
            out.add(package(ref))
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: upgrade-hook-apps.py <unit-moves file> <platform checkout>")
    moves_file, platform = sys.argv[1:]
    try:
        moves = {line.split()[0] for line in open(moves_file) if line.strip()}
    except FileNotFoundError:
        moves = set()
    if not os.path.isdir(os.path.join(platform, "helm")):
        print(f"REFUSED: {platform}: no platform checkout (no helm/)")
        sys.exit(2)
    apps = set()
    for chart in sorted(glob.glob(os.path.join(platform, "helm", "*"))):
        rel = os.path.relpath(chart, platform)
        try:
            runs = hook_packages(chart)
        except (OSError, LookupError, yaml.YAMLError) as e:
            print(f"REFUSED: {e}")
            sys.exit(2)
        if not runs:
            continue
        if rel not in HOOK_APPS:
            print(f"REFUSED: {rel} runs a hook ({', '.join(sorted(runs))}) and HOOK_APPS names no production app for it")
            sys.exit(2)
        if runs & moves:
            apps.add(HOOK_APPS[rel])
    print("\n".join(sorted(apps)))


if __name__ == "__main__":
    main()
