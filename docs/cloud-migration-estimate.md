# Cloud migration estimate — schnappy cluster

Written 2026-08-18 (AWS results added the same day). Live artifact version (richer tables):
https://claude.ai/code/artifact/cc76ab63-19b8-4ace-a31d-3c4881314a02

**Target: AWS, eu-north-1 (Stockholm).** The estimate was first produced and fully verified for
GCP (europe-north1), then the target pivoted to AWS; both analyses ran against the same live
cluster measurements from 2026-08-18 and both had every total adversarially recomputed. GCP is
kept below as the verified comparator. Prices are point-in-time — re-verify before committing
spend.

## Bottom line

| | AWS (target) | GCP (comparator) |
|---|---|---|
| Steady state, 1-yr commit | **~$441/mo scope (a) · ~$460/mo scope (b)** (≈ €380–400) | ~$349–389/mo |
| First months, on-demand | ~$540–562/mo | ~$462–500/mo |
| Cheaper family-locked commit | $416/mo (1-yr EC2 Instance SP, r7g/Stockholm lock) | — |
| Price floor (kubeadm on 1 VM, no managed CP) | $263/mo | $261/mo — statistical tie |
| Migration effort | **~50.5 pd (45–57), 3.5–4 months focused** | ~44 pd (38–50), 3–3.5 months |
| Hard calendar floor | 9–10 weeks (soak gates) — same | same |

**AWS lands $27–99/mo above GCP, and the whole gap is the $73/mo EKS control-plane fee** (GKE's
free zonal cluster zeroed that line). On everything else combined AWS is *cheaper*: egress
(100 GB/mo free, then $0.09/GB), gp3 storage (cheaper than pd-balanced AND a free 3,000-IOPS
floor per volume that dissolves GCP's hardest design dilemma), Graviton (~15% off the node
bill), and scope (b) is cheaper to add (+$17–21 vs +$20–34) because SSM Parameter Store is
genuinely free. A purely cost-led decision favors GCP by roughly one EKS fee; an
engineering-led one can honestly go either way.

Today's cluster runs on ~€15–25/mo of electricity and the i9 stays powered for radar
regardless — cloud is a **12–25× spend increase** buying a managed control plane, hardware
durability, and rolling upgrades. It is not a cost save.

## Measured baseline (what actually has to move)

Single-node kubeadm v1.34.6 on `ten` (i9-10900K, 62 GiB RAM, 2x 1TB NVMe):

| Metric | Value |
|---|---|
| Actual usage | **~1.3 cores, 34 GiB RAM** — memory-bound |
| Requests | 17.3 vCPU (86%), ~34 GiB — **13x inflated vs CPU usage** |
| Workloads | 94 pods, 67 deployments, 9 statefulsets, 5 daemonsets, 20 namespaces |
| PVCs | 783 Gi provisioned (thin); ~195 GiB real after planned retirements |
| Internet traffic | ~8.7 GB/day in, ~7.8 GB/day out ≈ 250 GB/mo egress |
| Stateful | Scylla x2, Kafka x2 (Strimzi), CNPG PG (prod HA), ClickHouse, ES, SonarQube |

Off-cluster on the Pi HA pair: Forgejo (git + registry), Keycloak (all logins), Vault (ESO
source), versitygw backup store, Nexus, Caddy, Consul. Stays home permanently: radar + all SDR
hardware + pi4. **End state is hybrid by construction.** All images are amd64 today.

## The three facts that shape everything (platform-independent, verified twice)

1. **Right-size requests first, at home, in Git.** Node count follows requests. On AWS the
   as-is sizing needs ~5 nodes (~$818/mo OD) vs 2 right-sized (~$540) — the lever is worth
   **~$278/mo OD (~$242 at commit)**. Zero migration risk; pays even if the migration never
   happens.
2. **Cluster-only scope does not protect logins.** Keycloak stays home and every app
   authenticates through it. This is why the recommendation below is scope (b) as the end
   state, phased through (a).
3. **monitor's page fetches will originate from one Stockholm EIP** — bot-scoring
   (Cloudflare/Akamai) challenges cloud IPs aggressively, and AWS ranges are the most-scored on
   the internet. The core product can silently degrade. **Validate top monitored sites from the
   actual EIP before committing to anything**; fallback is a home fetch-proxy over WireGuard.

## AWS result — recommended architecture

**EKS standard (k8s 1.34), eu-north-1, all-Graviton, VPC CNI + network-policy agent.**
Rejected: EKS Auto Mode, Fargate (can't run DaemonSets or EBS PVs, needs NET_ADMIN for Istio —
and still 1.4–2.3x the price), EC2+kubeadm (forfeits the managed control plane), Karpenter
(overkill at 3 nodes), Cilium-on-EKS (owning the CNI on managed nodes buys nothing here; the 2
existing CNPs are obsolete anyway — but the 47 standard NetworkPolicies need a full rehearsal
on the new engine: NP failures are silent drops).

- **Prod/platform:** 2x r7g.xlarge (4 vCPU/32 GiB arm64) on-demand managed node group,
  single-AZ pinned (EBS is AZ-scoped, statefuls are single-replica), private subnets, ~100 GiB
  gp3 roots. List r8g alongside r7g **only if** committing via Compute SP (a family-locked
  EC2 Instance SP must not mix families).
- **Test/CI:** 1x Spot arm64 node (m7g.xlarge primary, diversified list). Watch memory: 8 test
  deploys with sidecars + 2 Kaniko/Gradle agents is tight on 16 GiB — may need r7g (+$0–16/mo).
- **Graviton from day one:** all third-party images verified multi-arch; +1.5 pd for the
  in-house arm64 rebuild (Kaniko builds natively on the arm64 CI node) and a manifest-scan gate
  that must also cover `.woodpecker/*.yaml` pipeline images and the cert-manager Porkbun
  webhook, not just chart values. Saves ~$43–59/mo forever; payback 2–3 months.
- **Ingress:** NLB (TCP passthrough) via AWS LB Controller in front of istio-ingressgateway;
  TLS stays in-cluster, cert-manager DNS-01 Porkbun unchanged; WebSockets fine (350 s idle vs
  25 s Centrifugo pings). EIP binds via the eip-allocations annotation; public subnet needs the
  `kubernetes.io/role/elb` tag.
- **Egress:** fck-nat on t4g.nano (~$7.5/mo all-in) — the managed NAT Gateway would be
  **$56.58/mo** at our ~500 GB/mo (7.6x dearer). WireGuard hub on the same nano links home.
- **Storage:** everything on gp3 (free 3,000 IOPS/125 MB/s per volume — nothing needs io2);
  Mimir/Tempo/barman/Velero/Scylla-Manager -> native S3; barman-cloud is S3-native so the
  drilled CNPG DR carries over verbatim (adopt the Barman Cloud CNPG-I plugin — in-tree
  `barmanObjectStore` is deprecated, removal planned CNPG 1.30).
- **Secrets (scope b):** ESO -> SSM Parameter Store standard tier — actually free at 40–80
  params. Vault retires. (Secrets Manager only for the one ECR pull-through-cache credential.)
- **IAM:** EKS Pod Identity (install the pod-identity-agent add-on — it is not implicit) +
  access entries; zero long-lived keys. CloudWatch/Container Insights off; check GuardDuty/
  Config/Security Hub aren't silently enabled on the account.
- **Managed data services: all rejected at this scale** — Keyspaces isn't Scylla-compatible
  (no MVs/2i/UDF), MSK's practical minimum dwarfs 2x10Gi Strimzi, RDS/Aurora loses to drilled
  CNPG+barman, AMP/AMG breaks GitOps Grafana. Retire before moving: ES, OpenObserve,
  apt-cache, s3gw.

## Cost scenarios (verified; corrected numbers)

| Scenario | On-demand | 1-yr Compute SP | 1-yr EC2 ISP | Verdict |
|---|---|---|---|---|
| S0 kubeadm on one EC2 (r7g.2xlarge) | $386 | $294 | $263 | floor; keeps today's ops burden |
| **S1 EKS scope (a), Graviton, corrected** | **~$534** | **~$441** | **~$410** | recommended mechanics |
| S1 x86 variant (r6i) | $599 | $491 | $453 | Graviton saves $43–59/mo |
| S1 honoring inflated requests | ~$818 | — | — | the right-sizing argument |
| **S2 = S1 + full platform (b)** | **~$555** | **~$460** | **~$426** | recommended end state |
| S3 Fargate | $818–1,227 | — | — | rejected on hard blockers |

3-yr EC2 ISP would reach ~$350/mo — **do not sign a 3-yr lock before the bot-challenge
validation passes and a year of steady state**. Buy the 1-yr *no-upfront Compute SP* (keeps
instance flexibility; the $32/mo premium over the family-locked ISP is the price of an
experiment staying an experiment) after 1–3 months on-demand.

## Effort — ~50.5 pd scope (a), 58–60 pd to the scope (b) end state

Phases (deltas vs the GCP plan in parentheses): 0 decisions/bootstrap 2.5 · 1 right-size
requests 4 + 1 wk soak · 2 IaC bootstrap 6.5 (+1.5: EKS access entries, per-component IAM,
add-ons, LB Controller — GKE gives these turnkey) · 3 GitOps/ECR re-point + arm64 rebuild 5.5
(+1.5 elective Graviton) · 4 platform layer 9 (+1: full 47-NetworkPolicy rehearsal on the new
engine with positive/negative probes) · 5 test + prod pathfinders 7.5 + 1 wk soak (includes
Woodpecker server cutover + bot-challenge validation) · 6 stateful serialized 6.5 (−0.5:
barman is S3-native) · 7 backup/DR + off-account copy 3 · 8 decommission home cluster 3.5 +
2 wk observation (includes home-ingress re-plumb) · 9 soak/tuning/commit 2.5 + 30 d.

Focused ≈ 3.5–4 months; evenings pace ≈ 6 months; hard floor 9–10 weeks from soak gates either
way. Net ~+3 pd vs GCP like-for-like — the EKS IaC glue and the NetworkPolicy engine swap cost
more; S3-native tooling and the dissolved storage dilemma give a little back.

## New AWS-specific risks (beyond the three carry-over facts)

1. **NLB hairpin for in-VPC clients** — cloud pods calling cloud public vhosts (OIDC
   issuer/JWKS on auth.pmon.dev in scope (b), monitor watching its own sites) route out through
   fck-nat and back; client-IP preservation can break the return path. Mitigate with
   cloud-side split-horizon CoreDNS before scope (b) auth cutover.
2. **EKS requires subnets in >=2 AZs** even with all node groups pinned to one — the naive
   single-AZ VPC fails CreateCluster. Terraform must carry a second (empty) subnet.
3. **Backups share account+region with primaries** — a posture regression vs today's
   physically-separate Pi store. Add an off-account or pull-home copy (~$0–2/mo) in phase 7.
4. **Docker Hub anonymous limits funnel through one NAT EIP** — a mass re-pull (Spot
   replacement, node recycle) can hit the per-IP cap. ECR pull-through cache with
   authenticated upstream from day one, plus ECR lifecycle policies (the home registry
   accreted 396 images; without lifecycle rules the $2/mo ECR line quietly grows).

## Decisions to settle before the first dollar

| # | Decision | Recommendation |
|---|---|---|
| D1 | CNI | VPC CNI + network-policy agent (+ prefix delegation sequenced before workloads) |
| D2 | Graviton vs x86 | Graviton day one; +1.5 pd, −$43–59/mo forever |
| D3 | Egress path | fck-nat t4g.nano ($7.5) over NAT GW ($57); accept self-managed SPOF on egress |
| D4 | Scope | (b) end state, phased through (a); Keycloak+secrets pulled forward right after mechanics |
| D5 | Retirements pre-move | ES, OpenObserve, apt-cache, s3gw — deletes the largest PVC migration |
| D6 | Secrets | ESO -> SSM Parameter Store (free); Vault retires |
| D7 | Commitment | 1-yr no-upfront Compute SP, only after ~30 d steady billing + bot-challenge validation |

## Verified GCP comparator (condensed)

GKE Standard zonal, 2x e2-highmem-4 + Spot, passthrough NLB, WG hub, AR+GCS day one.
S1 corrected: $462–500 OD / **$349–389** 1-yr CUD (Standard-tier egress trim -> ~$330–360).
S0 floor $261. Scope (b) +$20–34. Autopilot rejected (privileged DaemonSets, Istio). Effort
~44 pd + ~3 pd review additions. GCP-only headache AWS doesn't have: the e2-vs-N4/Hyperdisk
storage dilemma (±$40–70/mo). GCP advantages AWS doesn't have: free zonal control plane, and
resource CUDs at 37% on the exact shapes used.

## Method

Cluster facts measured live 2026-08-18 (kubectl top, PVCs, service types, interface counters).
Prices researched the same day from official pricing pages (eu-north-1 / europe-north1). Each
cloud: 3 mapping analyses + 2 pricing researchers + scenario arithmetic + phased plan, then an
adversarial math check (all published totals re-added; corrections applied above) and a
completeness critic (17 findings per cloud; material ones folded in). Known unpriced residue:
single-digit $/mo (S3/GCS request ops, one Secrets Manager secret). FX: quote-date rates
(€1 ≈ $1.16 for the AWS figures, $1.087 for the earlier GCP figures).
