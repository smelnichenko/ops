# Plan 128 - CI steps run as non-root

Status: IN PROGRESS 2026-11-20 (operator: "CI run as a root?! you are kidding me", "use user namespaces for all CI pods").

- DONE: every CI pod in a user namespace of its own (infra 8f395019: the agent's WOODPECKER_BACKEND_K8S_USER_NAMESPACES;
  infra pipeline 1121 green with its pods on hostUsers: false) - a container's root is no longer ten's root.
- DONE: step 1 - the ansible-lint image's collections readable by any user and a uid-1000 user (ansible-lint d11e437);
  argocd-reader, ci-bot and git-mirror ALL-PASS as uid 1000, ops' whole suite green as uid 1000 with nothing excused.
- DONE: step 2 for ops (its pipeline non-root, the ci-nonroot harness), platform, infra, radar, game-scp, monitor,
  target-scorer, keycloak-theme, sonar-scanner, hyperfoil. site: its pull request (non-root, ci-deploy) in CI.
- DONE: `git.pmon.dev/schnappy/ci-tools` - the tools steps used to apk/apt-install as root (git, python3 + PyYAML,
  helm, ...), user 1000 - and its `ci-deploy`, the one copy of every app's update-infra / promote-prod.
- IN PR (ci-tools PR 3): ci-deploy never backwards - judged in the pipeline's checkout plus the app's main fetched into
  it (a re-run of an older pipeline holds only its own history): an environment already containing the commit is left
  alone, a diverged or unjudgeable one refused; `:latest` moved only forward, to the digest its smoke test ran.
- DONE: monitor on ONE Gradle home for every app, `/cache/gradle/shared`, each Gradle step holding a kernel flock on
  `/cache/gradle-shared.flock` (cancelled pods die 20 s after their step; their Gradle must not share the caches
  unlocked). The per-PR homes (51 GB) deleted, the cache volume owned by 1000.
- LEFT: masi, admin, chat, chess and radio-scheduler (each still root, per-build Gradle homes) the same way as monitor;
  ops' CI on ci-tools with production's own Ansible (`.woodpecker/ansible-setup.sh`, branch ci/ci-tools), then the
  ansible-lint image retired and its repo archived; game-scp's godot-ci step (below); step 3; step 4.

## The problem

Every Woodpecker step runs as uid 0 inside its container. Woodpecker's Kubernetes backend (v3.20.1, infra
`clusters/production/woodpecker/values.yaml`) gives step pods no security context, and most step images set no user
(our own `git.pmon.dev/schnappy/ansible-lint` among them). The pods are not privileged and this is not root on the
node, but root in a container is one kernel bug from the node, and a step that is root can write anything in its
container and workspace. ops' unit suite even depends on it: argocd-reader, ci-bot and git-mirror pass only as root.

## The goal

Every step and service container runs as a non-root uid by default. The exceptions, root inside their own user
namespace only, unprivileged, no added capabilities, each named in its pipeline: Kaniko (uid 0 to build an image), and
until it has an image of its own, game-scp's godot-ci export step (its export templates live in /root and it apt-installs
libfontconfig1 at run time - to go: an image FROM godot-ci with the font baked in and the templates in a uid-1000 home).

## What runs today (2026-11-20, every repo's `.woodpecker/*.yaml` on main)

| Image | Steps | Non-root as it is? |
|---|---|---|
| woodpeckerci/plugin-git | 13 | needs a writable HOME |
| gcr.io/kaniko-project/executor | 12 | no - the exception |
| alpine, debian:13-slim, python:3.13 slim | 9 | yes, HOME set |
| postgres:17-alpine (service) | 6 | its own uid 70, PGDATA writable |
| eclipse-temurin:25 (Gradle) | 5 | its own user ubuntu (1000); the shared Gradle home under its flock |
| valkey:8.1-alpine (service) | 4 | its own uid 999 |
| schnappy/sonar-scanner | 4 | to check |
| node:22 / node:24, playwright, browserless | 5 | node's own uid 1000; playwright as ubuntu 1000 (the workspace's owner - pwuser 1001 cannot write node_modules) |
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
3. **The default flipped last**: the agent's `WOODPECKER_BACKEND_K8S_SECCTX_NONROOT: "true"` AND
   `WOODPECKER_BACKEND_K8S_USER_NAMESPACES_OVERRIDE_SECCTX_NONROOT: "true"`, every Kaniko (and godot-ci) step keeping
   its explicit `runAsUser: 0`, `runAsNonRoot: false`. The second is not optional: Woodpecker v3.20.1 (pod.go) uses a
   step's own runAsNonRoot only when no agent-level setting exists, or in a user namespace with the override - without
   it a Kaniko pod gets runAsNonRoot: true with runAsUser 0, the kubelet refuses the container (CreateContainerConfigError)
   and every deploy stops. Proved on a Kaniko run (ci-tools' CD, or apt-cache by hand) before it is called done.
   Flipped last so a step missed in step 2 fails loudly instead of staying root. Woodpecker honours `runAsUser: 0` at
   all only because user namespaces are on - turning them off would silently drop those lines.
   Also here: `WOODPECKER_BACKEND_K8S_PERMISSION_INIT_IMAGE` - a non-root clone adds an init container that is
   `busybox:stable-musl` from Docker Hub, pulled for every pipeline; an image of ours instead.
4. **A check that keeps it**: each repo's CI runs a step asserting `id -u` is not 0, and ops' unit suite fails on a
   pipeline step without a security context, or with `runAsUser: 0` on any image but the named exceptions (Kaniko,
   godot-ci).

## User namespaces

Woodpecker's agent puts every pod in a user namespace of its own (hostUsers: false), so even a step that is
root inside its container - Kaniko's - maps to an unprivileged uid on ten. With that, the Kaniko exception in step 3
is root inside its namespace only. ten has what it needs: containerd 2.3.6, Linux 6.12 (idmapped mounts on ext4),
Kubernetes 1.36.6.

## Proof

Each step is CI configuration (list item 1 of the proof-matched-to-risk rule): its own pipeline run is the proof. The
agent's environment change in infra is the CI system's own configuration; its proof is every repo's next pipeline,
watched until each is green, with the change reverted at once if one goes red for a reason the plan did not fix.
