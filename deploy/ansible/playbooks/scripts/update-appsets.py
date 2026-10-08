#!/usr/bin/env python3
"""Add an environment to ApplicationSets (data, apps, mesh). One generating from git directories
(clusters/production/schnappy-*-<chart> - production's since 2026-04-10) lists the environment by its own directories:
nothing to edit there. A list generator gets the environment's element; another shape is refused (editing it as a list
failed: KeyError 'list')."""
import fnmatch
import sys
import os
import yaml

cluster_dir = sys.argv[1]
env_name = sys.argv[2]
env_ns = sys.argv[3]
release_name = sys.argv[4]

pi_url = "https://git.pmon.dev"
appsets = {
    "data": f"{cluster_dir}/argocd/apps/schnappy-data-envs.yaml",
    "apps": f"{cluster_dir}/argocd/apps/schnappy-apps-envs.yaml",
    "mesh": f"{cluster_dir}/argocd/apps/schnappy-mesh-envs.yaml",
}

for chart, path in appsets.items():
    if os.path.exists(path):
        with open(path) as f:
            doc = yaml.safe_load(f)
        first = (doc["spec"].get("generators") or [{}])[0]
        dirs = [d.get("path", "") for d in (first.get("git") or {}).get("directories") or []]
        if any(fnmatch.fnmatch(f"clusters/production/{env_ns}-{chart}", d) for d in dirs):
            print(f"{path}: lists {env_ns}-{chart} by its directory - nothing to edit")
            continue
        if "list" not in first:
            sys.exit(f"REFUSED: {path}: its generator neither lists elements nor generates {env_ns}-{chart}'s directory")
        elements = first["list"]["elements"]
    else:
        doc = {
            "apiVersion": "argoproj.io/v1alpha1",
            "kind": "ApplicationSet",
            "metadata": {"name": f"schnappy-{chart}-envs", "namespace": "argocd"},
            "spec": {
                "generators": [{"list": {"elements": []}}],
                "template": {
                    "metadata": {
                        "name": f"schnappy-{{{{{chart}}}}}",
                        "namespace": "argocd",
                    },
                    "spec": {
                        "project": "default",
                        "sources": [
                            {
                                "repoURL": pi_url + "/schnappy/platform.git",
                                "targetRevision": "main",
                                "path": f"helm/schnappy-{chart}",
                                "helm": {
                                    "releaseName": "{{releaseName}}",
                                    "valueFiles": ["$values/{{valuesPath}}"],
                                },
                            },
                            {
                                "repoURL": pi_url + "/schnappy/infra.git",
                                "targetRevision": "main",
                                "ref": "values",
                            },
                        ],
                        "destination": {
                            "server": "https://kubernetes.default.svc",
                            "namespace": "{{namespace}}",
                        },
                        "syncPolicy": {
                            "automated": {"selfHeal": True, "prune": False},
                            "syncOptions": [
                                "CreateNamespace=true",
                                "RespectIgnoreDifferences=true",
                            ],
                        },
                    },
                },
            },
        }
        elements = doc["spec"]["generators"][0]["list"]["elements"]

    if not any(e["env"] == env_name for e in elements):
        elements.append(
            {
                "env": env_name,
                "namespace": env_ns,
                "releaseName": release_name,
                "valuesPath": f"clusters/production/{env_ns}-{chart}/values.yaml",
                "syncWave": "0",
            }
        )
    with open(path, "w") as f:
        yaml.dump(doc, f, default_flow_style=False, sort_keys=False)

print(f"Updated ApplicationSets for {env_name}")
