# Cloud migration estimate — schnappy cluster

Written 2026-08-18. Live artifact version (same content, richer tables):
https://claude.ai/code/artifact/cc76ab63-19b8-4ace-a31d-3c4881314a02

**Status: target is AWS (eu-north-1, Stockholm).** The estimate was first produced for GCP
(europe-north1) and fully verified; the target then pivoted to AWS the same day. The GCP result
is kept below as the verified comparator. The AWS-specific sections are marked **[PENDING]**
where the analysis is still running — this doc gets updated when it lands, per the
always-update-docs rule.

Everything here is grounded in live measurements of the cluster taken 2026-08-18, and all GCP
prices were researched from official pricing pages the same day, then adversarially recomputed
(verdict: minor errors; corrected figures are what's quoted). Prices are point-in-time —
re-verify before committing spend.

---

## Measured baseline (what actually has to move)

Single-node kubeadm v1.34.6 on `ten` (i9-10900K, 62 GiB RAM, 2x 1TB NVMe):

| Metric | Value |
|---|---|
| Actual usage | **~1.3 cores, 34 GiB RAM** — memory-bound |
| Requests | 17.3 vCPU (86%), ~34 GiB — **13x inflated vs CPU usage** |
| Workloads | 94 pods, 67 deployments, 9 statefulsets, 5 daemonsets, 20 namespaces |
| PVCs | 783 Gi provisioned (thin, local-path); real data well under 269 GB total |
| Internet traffic | ~8.7 GB/day in, ~7.8 GB/day out ≈ 250 GB/mo egress |
| Stateful set | Scylla x2, Kafka x2 (Strimzi), CNPG PG (prod HA), ClickHouse, ES, SonarQube |

Not in the cluster, on the Pi HA pair: Forgejo (git + container registry), Keycloak (all
logins), Vault (ESO source), versitygw backup store, Nexus, Caddy, Consul.
Stays home permanently: radar + all SDR hardware + pi4 receiver. **End state is hybrid by
construction.**

Scopes: **(a)** cluster-only to cloud, Pis stay home over WireGuard; **(b)** full platform
moves, only SDR/radar stays home.

## The three facts that shape everything (platform-independent)

1. **Right-size requests first, at home, in Git.** Node count follows requests, not usage.
   On GCP this was worth ~$571/mo on-demand (~$6,900/yr) for a few days of zero-risk YAML work.
   Same lever applies to AWS. This pays even if the migration never happens.
2. **Scope (a) does not deliver home-ISP independence.** Keycloak stays home and every app
   authenticates through it — a home outage still breaks all new logins to cloud apps. Either
   pull the ~free Keycloak move forward (+2–3 pd) or accept it.
3. **monitor's page fetches will originate from cloud NAT IPs**, which bot-scoring
   (Cloudflare/Akamai) widely challenges — the core product can silently degrade after cutover.
   Validate top monitored sites from a cloud IP early; fallback is a home fetch-proxy over
   WireGuard. AWS IP ranges are, if anything, more aggressively scored than GCP's.

## Verified GCP result (the comparator)

Architecture: GKE Standard zonal (Autopilot technically blocked: privileged DaemonSets +
self-managed Istio), 2x e2-highmem-4 + Spot e2-standard-4 for test/CI, passthrough NLB
(WebSockets safe; never the HTTP LB), WireGuard hub VM, Artifact Registry + GCS from day one so
images/backups never cross the home uplink.

| Scenario | On-demand | 1-yr commit | Verdict |
|---|---|---|---|
| S0 kubeadm on one GCE VM | $368 | $261 | price floor; forfeits managed control plane |
| **S1 GKE Standard, right-sized (corrected)** | **$462–500** | **$349–389** | recommended shape |
| S1 honoring today's inflated requests | $1,000 | $676 | the right-sizing argument |
| S2 = S1 + full platform (scope b) | $449+corr | $331+corr | only +$20–34 over S1 |
| S3 GKE Autopilot | — | $355 | rejected regardless of price |

Steady state ~**$330–400/mo (€305–370)** with the Standard-tier egress trim; first 1–2 months
on-demand ~$445–500 until sizing is validated, then buy the commit.

Effort: **~44 person-days** (38–50), ten phases, 3–3.5 months focused / 5–6 at evenings pace,
hard calendar floor 9–10 weeks from soak gates (right-sizing soak 1 wk, pathfinder soak 1 wk,
decommission observation 2 wk, 30 days steady state before buying commits).

Phases: 0 decisions/bootstrap 2.5 pd · 1 right-size requests 4 pd+soak · 2 IaC bootstrap 5 pd ·
3 GitOps+registry re-point 4 pd · 4 platform layer 8 pd · 5 test+prod pathfinders 5 pd+soak ·
6 stateful serialized 7 pd · 7 backup/DR rework 3.5 pd · 8 decommission home cluster 2.5 pd+2 wk ·
9 soak/tuning/commit 2.5 pd. (+~3 pd of additions found in review: Woodpecker *server* cutover,
home public-ingress re-plumb before decommission, monitor egress-IP validation.)

## AWS target — confirmed so far

From the completed stateful/storage analysis (verified against the same measured baseline):

- **gp3 dissolves GCP's hardest decision.** Flat 3,000 IOPS / 125 MB/s baseline per volume —
  the e2-vs-N4/Hyperdisk dilemma (±$40–70/mo on GCP) does not exist on AWS. All PVCs on gp3;
  nothing needs io2 or provisioned IOPS.
- **Swap only the object-storage layer to native S3**: Mimir, Tempo, barman, Velero,
  Scylla-Manager. barman-cloud is S3-native — the proven CNPG DR drill carries over with a
  bucket swap.
- **CNPG catch relevant even without migrating**: in-tree `barmanObjectStore` is deprecated
  (removal planned CNPG 1.30) — adopt the Barman Cloud CNPG-I plugin during the move.
- **Reject all managed data services at this scale**: Keyspaces is not drop-in for Scylla, MSK's
  2-broker minimum dwarfs 2x10Gi Strimzi, RDS/Aurora loses to the CNPG setup already run well,
  AMP/AMG breaks GitOps Grafana.
- **Retire before moving, never migrate**: Elasticsearch, OpenObserve, apt-cache, in-cluster
  s3gw. Data moves by restore-from-backup (the rehearsed drill), not disk copy.
- **Pin the stateful node group to one AZ** (EBS is AZ-scoped; statefuls are single-replica) —
  zonal risk parity with the GKE plan, stated plainly.

Known structural deltas vs GCP (directionally certain, numbers pending):

| Delta | Direction |
|---|---|
| EKS fee $73/mo, no free-tier waiver (GKE zonal was free) | AWS worse |
| Egress: 100 GB/mo free + ~$0.09/GB after (vs $30/mo GCP Premium line) | AWS better |
| gp3 baseline IOPS (no storage dilemma, no IOPS padding) | AWS better |
| Graviton (r7g) option ~20% cheaper compute; amd64→arm64 image rebuild effort attached | AWS opportunity |
| NAT Gateway ~$50+/mo at our ~500 GB/mo vs ~$4 NAT instance — must choose deliberately | AWS trap |
| Public IPv4 now billed ~$3.65/mo each, including attached | AWS worse (small) |
| Savings Plans percentages/flexibility differ from GCP CUDs | different math |
| CNI decision: VPC CNI + policy agent vs self-managed Cilium (47 NetworkPolicies must keep working) | AWS decision |

## AWS target — [PENDING]

Blocked on a usage-limit reset (2026-08-18 16:10); auto-resume armed. To be filled in:

- Compute mapping: instance types/counts, Graviton-vs-x86 recommendation with rebuild effort,
  CNI recommendation, pod-density check (94 pods on 2 nodes), Karpenter verdict
- Full S0–S3 cost tables for eu-north-1 with researched prices + sources, adversarially verified
- AWS-vs-GCP delta table with final numbers
- Effort plan re-estimated for AWS (expect roughly GCP's ~44 pd ± a few: EKS IaC glue and
  IRSA/access-entries typically add; S3-native backup tooling subtracts)

## Decisions to settle before the first dollar

| # | Decision | Notes |
|---|---|---|
| D1 | CNI: VPC CNI + policy agent vs Cilium-on-EKS | Istio works on both; 2 existing CNPs dissolve either way |
| D2 | Graviton from day one vs x86-first | rebuild effort vs ~20% compute saving — pending numbers |
| D3 | Egress path: NAT instance vs NAT Gateway | ~$4 vs ~$50+/mo at our volume; reliability tradeoff |
| D4 | Scope (a) vs (b), Keycloak-forward option | (a) alone doesn't protect logins |
| D5 | Retire ES/OpenObserve/apt-cache/s3gw pre-move | deletes the largest PVC migration |
| D6 | Secrets: SSM Parameter Store (free) vs Secrets Manager vs Vault-on-EC2 | ESO supports all three |
| D7 | Savings Plan type + timing | only after ~30 days of steady billing data |

## Why-move sanity check

Today's cluster runs on ~€15–25/mo of electricity, and the i9 stays powered for the radar/SDR
estate regardless — actual electricity savings ≈ 0. Cloud at ~$350–400/mo is a **12–25× spend
increase** buying: managed control plane, hardware durability, rolling upgrades, and freedom
from the single NVMe/host failure domain. It does not buy login availability (Keycloak), and a
zonal cluster is still a single-zone failure domain. Decide with eyes open.
