# Plan 073: Integrate kagent (cloud-native agentic AIOps)

## Status (2026-06-23)

**APPROVED + build started — gated on a read-only RBAC override (see Chart
reconnaissance).** Decisions signed off: **read-only** RBAC, Anthropic egress
accepted, build Phase 1. Deep chart recon (v0.9.9) is done and surfaced a blocker:
the chart hardcodes **cluster-admin** for its tools server with no read-only toggle,
so the read-only requirement needs a manifest patch (designed below) before any
deploy. GitOps manifests not yet authored. The deploy is a security-sensitive prod
change and must be done as a careful, unhurried step — not rushed.

## TL;DR

Deploy [kagent](https://kagent.dev) into the cluster as a GitOps-managed app so we
get an in-cluster agentic assistant that already speaks our stack — its built-in
MCP toolsets cover Kubernetes, Istio, Helm, Argo, Prometheus, Grafana and Cilium,
all of which we run. Agents, model config and tools are Kubernetes CRDs, so they
live in git and reconcile through Argo CD exactly like everything else.

- Model: **Anthropic Claude** (we already hold `ANTHROPIC_API_KEY` in Vault for the
  monitor AI feature) via a `ModelConfig` CRD, key delivered by ESO.
- Runs in its own `kagent` namespace, in the Istio sidecar mesh (STRICT mTLS).
- UI/API exposed at `kagent.pmon.dev` **behind Keycloak SSO** — never unauthenticated.
- **Phase 1 is read-only/advisory**: the agents' ServiceAccount gets cluster-wide
  *read* RBAC only. Write/mutation is a deliberate later phase with guardrails.

## Context

We run a real distributed platform (Istio, Argo CD, Prometheus/Mimir, Grafana,
Cilium, CNPG, Strimzi, Scylla, Vault) on a single kubeadm node plus a Pi HA pair.
Day-to-day oper/ debugging means hopping between `kubectl`, `istioctl`, Argo, and
Grafana. kagent packages those as agent tools and runs the reasoning in-cluster.

Why kagent specifically:
- **GitOps-native.** `Agent`, `ModelConfig`, `RemoteMCPServer` are CRDs — versioned,
  PR-reviewed, Argo-reconciled. No snowflake state. Fits our app-of-apps model.
- **Stack match.** Built-in toolsets for k8s/Istio/Helm/Argo/Prometheus/Grafana/
  Cilium — the exact components we operate. Minimal glue.
- **Open protocols.** MCP + A2A + OpenAI-compatible endpoints; no lock-in. We can
  later point it at our own MCP servers (e.g. ClickHouse logs, Forgejo, Woodpecker).
- **Anthropic first-class.** We already use Claude and already seed `ANTHROPIC_API_KEY`
  to Vault; reuse it.

Components kagent deploys (v0.9.9): a Go **controller** (operator + API server), a
Python/Go **engine** (runs agents on ADK), a Next.js **UI**, and the **CLI**
(`kagent`). Persistence is SQLite by default, or PostgreSQL + `pgvector` when agent
*memory* is enabled.

## Design

### Topology

```
kagent namespace (istio-injection=enabled, PeerAuth STRICT)
├── kagent-controller   (operator + REST/A2A API)        ModelConfig/Agent CRDs
├── kagent-engine       (ADK runtime; calls Anthropic)   egress → api.anthropic.com
├── kagent-ui           (Next.js console)                ← gateway ← Keycloak
└── tool calls → in-cluster: kube-apiserver (RO SA), Prometheus, Grafana,
                  istiod, argocd-server, Cilium (Hubble)
```

### Install (GitOps, not `kagent install`)

Two upstream OCI Helm charts, pinned, driven by Argo CD — not the CLI installer:

```
oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds   # CRDs, synced first (sync-wave -1)
oci://ghcr.io/kagent-dev/kagent/helm/kagent        # controller/engine/ui, version 0.9.9
```

New files in **infra**:
- `clusters/production/argocd/apps/kagent.yaml` — two Argo `Application`s (crds, then
  main) with a sync-wave so CRDs land first; `prune:false`, automated sync.
- `clusters/production/kagent/values.yaml` — Helm values (see below).
- `clusters/production/cluster-config/kagent-secrets.yaml` — `ExternalSecret`
  `kagent-anthropic` ← Vault `secret/schnappy/anthropic` key `ANTHROPIC_API_KEY`.
- `clusters/production/kagent/resources/` — our own `ModelConfig` + `Agent` CRs +
  RBAC + NetworkPolicies + Gateway/VirtualService + AuthorizationPolicy (a tiny
  wrapper chart or raw manifests Argo applies).

Helm values (sketch — install with the provider key OFF; we own the ModelConfig):
```yaml
# values.yaml
providers:
  default: anthropic
controller:
  resources: { requests: {cpu: 50m, memory: 128Mi}, limits: {memory: 256Mi} }
ui:
  resources: { requests: {cpu: 25m, memory: 128Mi}, limits: {memory: 256Mi} }
# agents installed via our own CRs (Helm 'minimal' equivalent), not the demo profile
```

### Anthropic model (key via ESO, not inline)

Secret arrives from Vault through ESO (the doc's `kubectl create secret` is replaced
by an `ExternalSecret`):
```yaml
# kagent-anthropic (synced by ESO) → key ANTHROPIC_API_KEY
apiVersion: kagent.dev/v1alpha2
kind: ModelConfig
metadata: { name: claude-sonnet, namespace: kagent }
spec:
  provider: Anthropic
  model: claude-sonnet-4-6        # current model, not the doc's claude-3-sonnet
  apiKeySecret: kagent-anthropic
  apiKeySecretKey: ANTHROPIC_API_KEY
  anthropic: {}
```
Add a second `ModelConfig` `claude-haiku` (`claude-haiku-4-5-20251001`) for cheap,
high-volume tool agents; reserve `claude-opus-4-8` for a deep-reasoning agent if
needed. Per-agent `modelConfig` overrides pick the tier.

### Agents (Phase 1 set — read-only/advisory)

Enable the platform-relevant built-in agents, each pinned to a `ModelConfig` and the
read-only SA:
- **k8s-agent** — explain pod/deploy/event state, triage CrashLoops, read logs.
- **istio-agent** — mesh config, mTLS/PeerAuth, AuthorizationPolicy reasoning.
- **prometheus-agent** / **grafana-agent** — query metrics, explain alerts (ties to
  our 43 runbook annotations).
- **argo-agent** — sync status / health / drift (read-only; no sync/rollback).
- **cilium-agent** — Hubble flow / NetworkPolicy reasoning.
- **helm-agent** — release inventory/diff (read-only).

### Auth & exposure

- UI/API at `kagent.pmon.dev`: `Gateway` + `VirtualService` on the existing
  `schnappy-infra-gateway`, TLS via the `*.pmon.dev` DNS-01 cert, **JWT-gated by the
  same Keycloak `RequestAuthentication`/AuthorizationPolicy** the other UIs use. No
  anonymous access to an agent console.
- East-west: PeerAuthentication STRICT; AuthorizationPolicy allowing only the gateway
  SA → UI, and only kagent SAs → controller/engine.

### Security model (the crux)

The agents can *touch the whole cluster*. Least privilege:
- **Phase 1: read-only.** A `kagent-tools` SA bound to a custom **read-only**
  ClusterRole (get/list/watch; no create/update/delete/exec). Advisory only.
- **No secret reads.** Exclude `secrets` from the ClusterRole (agents must not exfil
  Vault-fed creds via the LLM).
- **Egress locked down.** NetworkPolicy: engine → `api.anthropic.com` (443) only for
  internet; tool egress to in-cluster Prometheus/Grafana/istiod/argocd/kube-apiserver;
  default-deny otherwise. (Sending cluster state to Anthropic is inherent to the LLM
  call — call that out to stakeholders.)
- **Write access is a later, gated phase** (see Out of scope): scoped Roles,
  human-in-the-loop approval, audit. Not in Phase 1.

### Decisions (need sign-off)

1. **RBAC scope** — start **read-only** (recommended) vs allow scoped writes day one.
2. **Memory store** — SQLite/ephemeral (simpler) vs CNPG `pgvector` DB (persistent
   agent memory). Recommend **start SQLite**, add a small CNPG db only if memory matters.
3. **Agent set** — the Phase-1 list above vs a minimal k8s-only start.
4. **Data egress** — confirm it's acceptable that prompts/cluster snippets go to the
   Anthropic API (same trust as our existing Claude usage, but now agent-driven).

## Chart reconnaissance (v0.9.9 — 2026-06-23)

`helm show values` + `helm template` of `oci://ghcr.io/kagent-dev/kagent/helm/kagent`
v0.9.9 corrected several assumptions in the original Design:

**Footprint is ~7 base pods + one pod per Agent**, not 3. Rendered Deployments:
`kagent-controller`, `kagent-ui`, `kagent-tools` (the MCP tool executor),
`kagent-grafana-mcp`, `kagent-kmcp-controller-manager`, `kagent-querydoc`, and a
**bundled `kagent-postgresql`** (pgvector; hardcoded `kagent`/`kagent` creds — the
chart itself says "switch to an external database for production"). Plus a pod per
enabled Agent. On the CPU-request-over-committed single node this needs sizing +
trimming optional components (`grafana-mcp`, `querydoc`, `kmcp` when unused) and
likely pointing the DB at our CNPG instead of the bundled one.

**SECURITY — the tools server is cluster-admin by default, with no toggle.** The
`kagent-tools` subchart renders `kagent-tools-cluster-admin-role`
(`apiGroups:["*"] resources:["*"] verbs:["*"]`) bound to the `kagent-tools` SA. The
MCP tool server runs the actual `kubectl`/k8s calls under that SA, so out of the box
agents can do **anything** — read every Secret, delete workloads. **CORRECTION (2026-06-24, full-review):** v0.9.9's `kagent-tools` subchart DOES
expose a native read-only toggle — the earlier "no rbac flag" claim was wrong for the
pinned version. `charts/kagent-tools/values.yaml` has `rbac.readOnly` ("deploys a
read-only ClusterRole (get,list,watch) instead of cluster-admin"; the role is renamed
`-read-role`), `rbac.allowSecrets` (default false → Secrets excluded), and
`rbac.additionalRules`. So read-only is a **3-line values change, not a manifest
patch**:
```yaml
kagent-tools:
  rbac:
    readOnly: true        # get/list/watch ClusterRole, no cluster-admin
    allowSecrets: false   # Secrets excluded
    additionalRules:      # the CRD reads the agents need
      - apiGroups: [networking.istio.io, security.istio.io, cilium.io,
                    gateway.networking.k8s.io, argoproj.io, monitoring.coreos.com,
                    postgresql.cnpg.io, kafka.strimzi.io, velero.io]
        resources: ["*"]
        verbs: [get, list, watch]
```
This means the deploy should use the **platform-native multi-source Helm** Argo app
(like `apps/cert-manager.yaml`/`apps/prometheus.yaml`) — NOT the kustomize-with-helm
overlay — dropping the ~350-line patch AND the cluster-wide `--enable-helm` repo-server
change entirely. The first-authored manifests used the patch approach; switching to
the native toggle is the top follow-up (see the build status below).

**Default agents include write-capable ones.** All enabled by default: `k8s-agent`,
`istio-agent`, `promql-agent`, `observability-agent`, `helm-agent`,
`cilium-policy-agent`, `cilium-debug-agent` (read-leaning) **plus the mutating**
`argo-rollouts-agent`, `cilium-manager-agent`, `kgateway-agent`. Phase-1 disables the
mutating three via `--set <agent>.enabled=false`.

**SSO is an in-chart oauth2-proxy, not native UI auth.** `controller.auth.mode`
defaults to `unsecure` (trusts an `X-User-Id` header / falls back to
`admin@kagent.dev`). The chart bundles an `oauth2-proxy` subchart (`enabled:false`)
and a `trusted-proxy` mode: set `oauth2-proxy.enabled=true`,
`controller.auth.mode=trusted-proxy`, point oauth2-proxy at Keycloak
(`OIDC_ISSUER_URL=https://auth.pmon.dev/realms/schnappy`,
`OIDC_REDIRECT_URL=https://kagent.pmon.dev/oauth2/callback`,
`UPSTREAM_URL=http://kagent-ui:8080`), and route the gateway at the oauth2-proxy
service. Requires a **new Keycloak client** (`kagent-ui`, confidential, redirect
`https://kagent.pmon.dev/oauth2/callback`) whose client-id/secret + a cookie-secret
land in a Secret via ESO/Vault. Until that's wired, access via `kubectl port-forward`
only — never publish the UI unauthenticated.

**Confirmed wiring (conventions sweep):**
- Anthropic key already in Vault `secret/data/schnappy/ai` property `api_key` (seeded
  by `seed-vault-secrets.yml`) → ESO → `kagent-anthropic` key `ANTHROPIC_API_KEY`.
- ClusterSecretStore `vault-backend`. Argo apps auto-discovered from
  `clusters/production/argocd/apps/`; multi-source `$values` pattern; syncPolicy
  `automated{selfHeal,prune}` + `CreateNamespace=true` + `ServerSideApply=true`;
  sync-wave for CRDs-first.
- Ingress: gateway `schnappy-infra-gateway` in `schnappy-infra`, section `https`, TLS
  `pmon-dev-wildcard-tls`; Gateway-API `HTTPRoute` placed in the `kagent` ns (attaches
  cross-ns since the gateway allows routes `from: All`).
- Namespace label `istio.io/rev: default` for sidecar injection; `PeerAuthentication`
  STRICT per the platform pattern; egress NetworkPolicy must allow `0.0.0.0/0` minus
  RFC1918 on :443 for the Anthropic API (mirrors the monitor app's external-HTTPS rule).

## Implementation steps

1. **Vault/ESO**: confirm `secret/schnappy/anthropic` holds `ANTHROPIC_API_KEY` (add
   to `seed-vault-secrets.yml` if missing — it's already passed to `deploy:seed-secrets`);
   add the `kagent-anthropic` `ExternalSecret`.
2. **Charts**: add the two Argo `Application`s (kagent-crds wave -1, kagent wave 0) +
   `clusters/production/kagent/values.yaml`. Render-check with `helm template`.
3. **Namespace + mesh**: `kagent` ns with `istio-injection=enabled`, PeerAuth STRICT,
   NetworkPolicies (default-deny + the egress allows above), Pod Security baseline.
4. **Model + RBAC + agents**: apply `ModelConfig` (claude-sonnet/haiku), the read-only
   `kagent-tools` SA + ClusterRole(Binding), and the Phase-1 `Agent` CRs.
5. **Ingress + SSO**: Gateway/VirtualService for `kagent.pmon.dev` + the Keycloak
   RequestAuthentication/AuthorizationPolicy; DNS `kagent.pmon.dev` (Porkbun, wildcard
   already covers TLS).
6. **Verify**: pods Ready; UI loads behind SSO (anon = 403); ask k8s-agent to describe
   a known pod and istio-agent to explain a PeerAuthentication; confirm NetworkPolicy
   blocks non-allowed egress; confirm the SA cannot read secrets or mutate (RBAC
   `kubectl auth can-i` matrix).
7. **Docs/memory**: record in `ops/CLAUDE.md` + a memory note; mark this plan DONE.

## Risks & tradeoffs

- **Blast radius of cluster access.** Mitigated by read-only RBAC + secret exclusion +
  egress lockdown in Phase 1. Write access is explicitly deferred.
- **Data leaves the cluster.** Cluster state in prompts goes to Anthropic — same trust
  boundary as our existing Claude use, but broader. Decision #4 makes it explicit.
- **Single-node resource pressure.** The node is CPU-*request* over-committed; size
  kagent small (requests ~125m total) and watch the rolling-update surge.
- **Project velocity.** kagent is pre-1.0 (v0.9.9); CRD `v1alpha2` may churn. Pin the
  chart version; treat upgrades as reviewed PRs (and a future Renovate target).
- **UI auth.** An unauthenticated agent console would be a serious hole — SSO-gating is
  non-negotiable and gated in step 5 before any public DNS.

## Rollback

Pure GitOps: delete the two Argo `Application`s (or revert the infra commit); Argo
removes the workloads. CRDs are retained by default (`kagent-crds` `prune:false`) so
in-flight `Agent`/`ModelConfig` objects aren't yanked mid-reconcile; delete the CRDs
chart last if a full teardown is wanted. No data migration to unwind in Phase 1
(SQLite/ephemeral). Vault key and ESO secret are inert if the namespace is gone.

## Out of scope (future phases)

- **Write/remediation access** — scoped Roles (e.g. restart a Deployment, sync an Argo
  app) behind human-in-the-loop approval + audit logging. Separate plan.
- **Custom MCP servers** — expose our own tools (ClickHouse logs, Forgejo, Woodpecker,
  the monitor API) as `RemoteMCPServer`s so agents can reason over our data plane.
- **A2A workflows** — multi-agent incident-response chains (alert → triage → propose fix).
- **Persistent memory** — CNPG `pgvector` store if agents need long-term recall.
- **Tie-in to alerting** — Alertmanager → kagent agent as a first-responder enrichment
  step (drafts a runbook-grounded diagnosis on a firing alert).
