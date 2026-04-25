# Plan 067: Ephemeral per-PR environments

## TL;DR

On every open PR in `schnappy/monitor` (or any of the four service repos +
`schnappy/site`), spin up a self-contained instance of the schnappy app at
`pr-<N>.preview.pmon.dev` so reviewers can click through actual UI changes
against real backend services. On PR close/merge, the entire namespace is
GC'd by Argo CD.

The goal is "click the link in the PR description, see the change live"
without anyone having to know about Helm, kubectl, or Argo CD.

## Context

Today reviewing a frontend or backend change requires the reviewer to:
1. Pull the branch.
2. `task dev` locally.
3. Wait for the local stack to come up (~3 min on a fresh dev box).
4. Test the change.

That's high friction, and the local stack diverges from the cluster's
configuration in subtle ways (different gateway, different keycloak
realm, no Istio sidecar). PR reviews trend toward "the diff looks fine,
LGTM" because actually running the change is too expensive.

Ephemeral envs collapse the loop: Woodpecker builds the PR's images,
pushes them to Pi Forgejo registry under a tag like `pr-N-<sha>`, Argo
CD's ApplicationSet sees the new PR via Forgejo's API, instantiates a
namespaced Helm release, and a wildcard cert-manager certificate covers
the new subdomain. Total time from `git push` to clickable URL: target
**< 4 min**.

## Architecture

### Trigger: Argo CD ApplicationSet (PullRequest generator)

```yaml
# infra/clusters/production/argocd/apps/schnappy-pr-envs.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: schnappy-pr-envs
  namespace: argocd
spec:
  goTemplate: true
  generators:
    - pullRequest:
        gitea:
          owner: schnappy
          repo: monitor    # we'll add a generator block per repo (5 total)
          api: https://git.pmon.dev
          tokenRef: { secretName: forgejo-readonly-token, key: token }
        requeueAfterSeconds: 60
        labels: ["preview"]   # only PRs labelled "preview" get an env
  template:
    metadata:
      name: 'pr-{{.number}}-monitor'
    spec:
      project: schnappy
      source:
        repoURL: https://git.pmon.dev/schnappy/platform.git
        targetRevision: main
        path: helm/schnappy
        helm:
          releaseName: 'pr-{{.number}}'
          values: |
            namespace: schnappy-pr-{{.number}}
            previewMode: true
            app:
              image:
                repository: git.pmon.dev/schnappy/monitor
                tag: 'pr-{{.number}}-{{.head_short_sha}}'
            site:
              image:
                repository: git.pmon.dev/schnappy/site
                tag: 'pr-{{.number}}-{{.head_short_sha}}'
              dnsResolver: "10.43.0.10"
            ingress:
              host: 'pr-{{.number}}.preview.pmon.dev'
            postgres:
              ephemeral: true
            valkey:
              # plan 064: Valkey CR managed by valkey-operator
              # ephemeral mode = single replica, no PVC
              ephemeral: true
            kafka:
              # share the prod cluster, prefix topics
              shared: true
              topicPrefix: 'pr-{{.number}}-'
            keycloak:
              # share dev realm; auto-register a "preview-pr-{{.number}}" client
              realm: dev
              clientId: 'preview-pr-{{.number}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: 'schnappy-pr-{{.number}}'
      syncPolicy:
        automated: { prune: true, selfHeal: true }
        syncOptions: [CreateNamespace=true]
```

Argo CD's ApplicationSet PullRequest generator polls Forgejo every 60s,
creates an Application per open PR, and *deletes* the Application when the
PR closes — which cascades to namespace cleanup via `prune: true`.

**Why opt-in via the `preview` label** (not every PR): not every PR needs a
preview (chore PRs, doc-only PRs, dependency bumps). Adding a `preview`
label is a one-click decision the author/reviewer makes.

### Build: Woodpecker pipeline addition

Each of the five repos (`monitor`, `chat`, `admin`, `chess`, `site`) gets a
new `.woodpecker/pr.yaml`:

```yaml
when:
  - event: pull_request

steps:
  - name: build-and-push-pr
    image: gcr.io/kaniko-project/executor:debug
    commands:
      - PR_TAG="pr-${CI_COMMIT_PULL_REQUEST}-$(echo $CI_COMMIT_SHA | cut -c1-7)"
      - /kaniko/executor
          --context .
          --dockerfile Dockerfile
          --destination git.pmon.dev/schnappy/monitor:${PR_TAG}
          --skip-tls-verify-registry=git.pmon.dev
          --insecure-registry=nexus.pmon.dev:8082
          --registry-mirror=nexus.pmon.dev:8082
          --cache=true
          --cache-repo=git.pmon.dev/schnappy/monitor/cache
    backend_options:
      kubernetes:
        secrets:
          - name: woodpecker-ci-secrets
            key: registry_token
            target: { env: REGISTRY_TOKEN }
```

No `update-infra` step needed — Argo CD's ApplicationSet templates the tag
from the PR's head SHA, so it picks up the new image automatically on the
next reconcile.

### Routing: Istio HTTPRoute per PR

The chart (`helm/schnappy/templates/preview-httproute.yaml`, gated on
`previewMode: true`) emits an HTTPRoute matching
`hostnames: [pr-N.preview.pmon.dev]` and attached to the existing prod
gateway. One new wildcard cert covers all of them:

```yaml
# infra/clusters/production/cert-manager/preview-wildcard.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: preview-pmon-dev-wildcard
  namespace: istio-system
spec:
  secretName: preview-pmon-dev-tls
  issuerRef: { name: letsencrypt-prod, kind: ClusterIssuer }
  dnsNames: ["*.preview.pmon.dev"]
  # DNS-01 via existing Porkbun webhook
```

DNS: a wildcard `*.preview.pmon.dev` A record pointing at `ten`'s public IP
(one record covers all PRs).

### Per-PR data tier

Three options per data backend, each with different cost/isolation
trade-offs:

| Backend | Default | Why |
|---|---|---|
| **Postgres** | ephemeral CNPG `Cluster` (1 instance, 100 MiB PVC, deleted on namespace drop) | Real schema migrations + Liquibase actually run. Each PR gets a clean DB. |
| **Valkey** | ephemeral `Valkey` CR (operator-managed, 1 replica, no PVC) | Cache is throwaway by definition; per-PR is cheap. |
| **Kafka** | shared prod cluster, topic prefix `pr-N-` | Per-PR Strimzi cluster is too heavy (~1 GB RAM each); prefixing topics is sufficient isolation. Cleanup hook deletes prefixed topics. |
| **Scylla** | shared prod cluster, keyspace prefix `pr_N_` | Same reasoning as Kafka. |
| **MinIO** | shared prod, per-PR bucket `pr-N` | Cheap, nice and isolated. Cleanup hook deletes the bucket. |
| **Keycloak** | shared dev realm, per-PR OIDC client `preview-pr-N` | Each PR can register/login users without polluting prod realm. |

### Resource budget

Per-PR env (with ephemeral postgres + valkey, shared kafka/scylla/keycloak):

| Component | Request | Limit |
|---|---|---|
| postgres (CNPG, single) | 250m / 256 MiB | 500m / 512 MiB |
| valkey (operator, single) | 50m / 64 MiB | 200m / 256 MiB |
| monitor (app) | 200m / 512 MiB | 1000m / 1.5 GiB |
| site (nginx) | 50m / 32 MiB | 200m / 128 MiB |
| chat | 200m / 384 MiB | 500m / 768 MiB |
| chess | 200m / 384 MiB | 500m / 768 MiB |
| admin | 100m / 256 MiB | 300m / 512 MiB |
| **Per-PR total** | **~1.0 CPU / ~1.9 GiB** | **~3.2 CPU / ~4.4 GiB** |

`ten` has 96 GB RAM and 32 cores after recent upgrade, so headroom for
**~30 concurrent PR envs** before resource pressure (more if some PRs
disable services they're not testing via per-PR Helm value overrides
posted as PR labels).

### Cleanup policy

1. **PR closed/merged** → ApplicationSet drops the Application →
   `syncPolicy.automated.prune: true` deletes the Helm release →
   namespace + all per-PR resources (CNPG cluster, Valkey CR, MinIO
   bucket, Keycloak client, Kafka topics) GC'd.
2. **Stale-env timer** (separate CronJob in `argocd` ns) — daily, lists
   Applications matching `^pr-\d+-`, queries Forgejo for PR state, force-
   prunes any whose PR has been closed > 24 h or whose head SHA hasn't
   changed in > 7 days (idle stale envs).
3. **Manual override** — removing the `preview` label closes the env
   immediately on next requeue.

### Data backend cleanup hooks (per-PR)

The chart includes a Helm `pre-delete` hook job (only emitted when
`previewMode: true`):

```yaml
{{- if .Values.previewMode }}
apiVersion: batch/v1
kind: Job
metadata:
  name: 'preview-cleanup-{{ .Release.Name }}'
  annotations:
    "helm.sh/hook": pre-delete
    "helm.sh/hook-delete-policy": hook-succeeded
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: cleanup
          image: bitnami/kubectl:1.34
          command:
            - sh
            - -c
            - |
              # Delete prefixed Kafka topics
              kubectl get kafkatopics -n schnappy-production \
                -l 'app.kubernetes.io/instance=pr-{{ .Release.Name }}' \
                -o name | xargs -r kubectl delete -n schnappy-production
              # Delete MinIO bucket
              mc rb --force prod/{{ .Release.Name }}/ || true
              # Delete Keycloak client
              kc delete clients/{{ .Release.Name }} || true
{{- end }}
```

## Scope (this plan only)

1. Add `pullRequest` generator support to Argo CD (already supported in
   Argo CD ≥ 2.7 — verify our version).
2. Wildcard `*.preview.pmon.dev` Certificate via cert-manager + DNS record.
3. New chart template `preview-httproute.yaml` (gated on `previewMode`).
4. New chart values block: `previewMode`, `valkey.ephemeral`,
   `postgres.ephemeral`, `kafka.topicPrefix`, `keycloak.clientId`.
5. New `.woodpecker/pr.yaml` in each of 5 service/site repos.
6. Argo CD `ApplicationSet` resource committed to
   `infra/clusters/production/argocd/apps/schnappy-pr-envs.yaml`.
7. Stale-env CronJob in `argocd` namespace.
8. Pre-delete hook for shared-resource cleanup (Kafka topics, MinIO
   bucket, Keycloak client).
9. README in `infra/clusters/production/argocd/apps/` explaining how to
   opt a PR in (add `preview` label).

## Vagrant tests are the merge gate (non-negotiable)

Before merging any of the 7 repos involved:

1. **`task test:pr-envs`** (new) — synthetic PR-like flow against vagrant
   cluster: create a fake "PR-99" Application via direct kubectl, verify
   namespace, ephemeral postgres + valkey come up, deployment Ready,
   `curl https://pr-99.preview.vagrant.test:30443` returns 200.
2. **`task test:argocd`** (existing) — must still pass; we're adding an
   ApplicationSet, not breaking existing Applications.
3. **`task test:cicd`** (existing) — must still pass; the Pi Forgejo
   registry path is reused for PR images.
4. **Cleanup test inside `test:pr-envs`** — kubectl delete the
   Application, verify namespace + all per-PR resources are pruned within
   60s.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Forking 5 repos' CI to add `pr.yaml` is repetitive | Templated via copy-paste of one (`monitor`); diff is just image name. Acceptable one-time cost. |
| Per-PR ephemeral Postgres delays env-ready by ~45s | Acceptable; clean-DB-per-PR is the whole point. |
| Shared Kafka/Scylla mean a buggy PR can break prod consumers | Topic/keyspace prefix isolates payload data. Schema changes (KafkaTopic CRs) are still per-PR; operator owns lifecycle. |
| 30+ concurrent envs eat RAM | Stale-env CronJob caps at 7 days; Helm hook prunes on close; resource quotas in the ApplicationSet template force per-env caps. |
| Wildcard TLS cert covers `*.preview.pmon.dev` — one bad PR can serve content under that name | Same risk as any subdomain; accepted. CSP headers in the site's nginx config remain locked down. |
| Forgejo readonly token in argocd ns leaks PR list | Read-only, scoped to public PR data. Stored in Vault → ESO → Argo CD ns. |
| Ephemeral CNPG `Cluster` deletion races with Argo CD Application deletion | CNPG operator's finalizer handles ordering; pre-delete hook timeout = 120s. |

## Verification

1. Open a draft PR in `schnappy/site`, add `preview` label.
2. Within 60s of Woodpecker push, image `git.pmon.dev/schnappy/site:pr-N-<sha>` exists in Forgejo registry.
3. Within 90s after that, Argo CD shows new Application `pr-N-site`.
4. Within 4 min of original push, `https://pr-N.preview.pmon.dev` returns 200 with the PR's site changes visible.
5. Close the PR. Within 5 min, `https://pr-N.preview.pmon.dev` returns NXDOMAIN/503 (namespace gone).
6. `kubectl get applicationsets schnappy-pr-envs -n argocd -o jsonpath='{.status}'` shows zero Application children.

## Out of scope

- **Per-PR Keycloak realm** — too heavy; share dev realm with per-PR client.
- **Per-PR public access auth** — PRs are public via the wildcard cert; relying on obscurity + low traffic. If we ever need to gate, add OAuth proxy in front.
- **PR comment with the URL** — would be nice but requires Woodpecker → Forgejo API write; defer.
- **Multi-cluster preview envs** (e.g. dedicated preview cluster) — current `ten` capacity is sufficient.

## Execution order

1. **Save this plan** as `ops/docs/plans/067-ephemeral-pr-envs.md` (done).
2. Verify Argo CD version supports `pullRequest.gitea` generator (>= 2.8).
3. **`platform`**: add `previewMode`, `postgres.ephemeral`, `valkey.ephemeral`, `kafka.topicPrefix` values + the `preview-httproute.yaml` template + `preview-cleanup` Job hook.
4. **`infra`**: commit the wildcard Certificate + the ApplicationSet manifest + stale-env CronJob.
5. **`monitor`, `chat`, `admin`, `chess`, `site`**: add `.woodpecker/pr.yaml` (5 small files).
6. **`ops`**: write `tests/ansible/test-pr-envs.yml` synthetic test + add to `Taskfile.yml` as `task test:pr-envs`.
7. Vagrant test + sync.
8. Open one real PR with `preview` label, verify the URL works, close it, verify cleanup.

## Dependency on other plans

- **Plan 064 (Valkey)** — must merge first. The chart changes here assume `valkey.ephemeral` value exists; that's only meaningful once valkey-operator is the source for cache.
- **Plan 065 (ClickHouse logs)** — independent. Can ship in parallel.
- **Plan 066 (Centrifugo)** — independent (per-PR realtime channel naming would need a topic prefix similar to Kafka, but that's a 066 concern).
