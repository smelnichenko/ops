#!/usr/bin/env python3
"""Add an environment to ApplicationSets (data, apps, mesh)."""
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
        elements = doc["spec"]["generators"][0]["list"]["elements"]
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
