# Plan 128 - CI steps run as non-root

Status: IN PROGRESS 2026-11-20 (operator: "CI run as a root?! you are kidding me", "use user namespaces for all CI pods").

- DONE: every CI pod in a user namespace of its own (infra 8f395019: the agent's WOODPECKER_BACKEND_K8S_USER_NAMESPACES;
  infra pipeline 1121 green with its pods on hostUsers: false) - a container's root is no longer ten's root.
- DONE: step 1 - the ansible-lint image's collections readable by any user and a uid-1000 user (ansible-lint d11e437);
  argocd-reader, ci-bot and git-mirror ALL-PASS as uid 1000, ops' whole suite green as uid 1000 with nothing excused.
- step 2 for ops: its pipeline non-root and the ci-nonroot harness that keeps it.

## The problem

Every Woodpecker step runs as uid 0 inside its container. Woodpecker's Kubernetes backend (v3.20.1, infra
`clusters/production/woodpecker/values.yaml`) gives step pods no security context, and most step images set no user
(our own `git.pmon.dev/schnappy/ansible-lint` among them). The pods are not privileged and this is not root on the
node, but root in a container is one kernel bug from the node, and a step that is root can write anything in its
container and workspace. ops' unit suite even depends on it: argocd-reader, ci-bot and git-mirror pass only as root.

## The goal

Every step and service container runs as a non-root uid by default. The one exception is Kaniko (it needs uid 0 inside
its own container to build an image); it stays unprivileged with no added capabilities, and is named as the exception
in each pipeline.

## What runs today (2026-11-20, every repo's `.woodpecker/*.yaml` on main)

| Image | Steps | Non-root as it is? |
|---|---|---|
| woodpeckerci/plugin-git | 13 | needs a writable HOME |
| gcr.io/kaniko-project/executor | 12 | no - the exception |
| alpine, debian:13-slim, python:3.13 slim | 9 | yes, HOME set |
| postgres:17-alpine (service) | 6 | its own uid 70, PGDATA writable |
| eclipse-temurin:25 (Gradle) | 5 | GRADLE_USER_HOME in the workspace |
| valkey:8.1-alpine (service) | 4 | its own uid 999 |
| schnappy/sonar-scanner | 4 | to check |
| node:22 / node:24, playwright, browserless | 5 | node's own uid 1000; playwright's pwuser |
| prometheus, alertmanager | 3 | already nobody (65534) |
| ansible-lint (ours) | 1 file, 5 steps | yes, once the three harnesses pass non-root |
| clickhouse-server (service) | 1 | its own uid 101 |
| kubeconform, alpine/helm, alpine/k8s, rclone, godot-ci | 5 | to check |

## Steps

1. **ops' three root-only harnesses** (argocd-reader, ci-bot, git-mirror) fixed to pass as any user - their cause
   found first, never a skip.
2. **One repo at a time, per step**: each step gets `backend_options.kubernetes.securityContext` with `runAsNonRoot:
   true` and a uid (1000, or the image's own user for services), HOME or caches moved into the workspace where a step
   writes them. ops first (its own CI is the proof), then platform, infra, the apps. Each repo's CI green on the change
   is its proof.
3. **The default flipped last**: the agent's `WOODPECKER_BACKEND_K8S_SECCTX_NONROOT: "true"`, every Kaniko step
   overriding it explicitly (`runAsUser: 0`, `runAsNonRoot: false`). Flipped last so a step missed in step 2 fails
   loudly instead of staying root.
4. **A check that keeps it**: each repo's CI runs a step asserting `id -u` is not 0, and ops' unit suite fails on a
   pipeline step without a security context unless it is a Kaniko step.

## User namespaces

Woodpecker's agent puts every pod in a user namespace of its own (hostUsers: false), so even a step that is
root inside its container - Kaniko's - maps to an unprivileged uid on ten. With that, the Kaniko exception in step 3
is root inside its namespace only. ten has what it needs: containerd 2.3.6, Linux 6.12 (idmapped mounts on ext4),
Kubernetes 1.36.6.

## Proof

Each step is CI configuration (list item 1 of the proof-matched-to-risk rule): its own pipeline run is the proof. The
agent's environment change in infra is the CI system's own configuration; its proof is every repo's next pipeline,
watched until each is green, with the change reverted at once if one goes red for a reason the plan did not fix.
