# Nexus over HTTPS: every CI build through Caddy, the plain ports closed to pipelines

Status: DECIDED (operator 2026-11-21: "there is not so much traffic, I prefer https"; the Docker mirror on its own name,
router record added the same day), not started.

## Why

Every pipeline reaches the Pis' Nexus over plain HTTP: Maven, npm and PyPI at `http://192.168.11.5:8081` (Vault's
`nexus_url`, `nexus_npm_registry`), the Gradle wrapper at `http://nexus.pmon.dev:8081`, and Kaniko's Docker mirror at
`nexus.pmon.dev:8082` with `--insecure-registry`. Nothing verifies what comes back: a host on the LAN answering for
192.168.11.5 hands every build its dependencies and base images. Caddy on both Pis already terminates TLS for Nexus with
the `*.pmon.dev` wildcard; the builds just never used it.

## Production now (read live, 2026-11-21)

- `nexus.pmon.dev` and `nexus-docker.pmon.dev` resolve to the VIP 192.168.11.5 from the router, ten, pi1 and pi2 (the
  second since the operator's router record, 2026-11-21; it resolved to ten's gateway before, though Caddy has had its
  site since the dual-Pi move). The VIP is on pi2; Nexus runs only on the VIP holder.
- `https://nexus.pmon.dev/repository/maven-public/`: 200. `https://nexus-docker.pmon.dev/v2/`: 401 with
  `Bearer realm="https://nexus-docker.pmon.dev/v2/token"`; an anonymous token, then `library/alpine:3.20`'s manifest: 200.
- Load: a cold masi dependency resolve (991 requests, 572 MB) took 35 s over HTTPS and 32 s over HTTP. Caddy spent
  about 2 CPU-seconds on pi2, and Nexus 5 CPU-seconds either way. Cached CI builds ask far less.
- The `woodpecker-pipeline` NetworkPolicy (infra `cluster-config/woodpecker-networkpolicies.yaml`) already lets pipeline
  pods reach 192.168.11.5:443 (their clone from git.pmon.dev), so no policy change is needed to move.

| live repo | Kaniko mirror (cd.yaml) | `NEXUS_URL` / npm | Gradle wrapper | other |
|---|---|---|---|---|
| admin, chat, chess, monitor | yes | Maven (`allowInsecureProtocol`) | http | - |
| masi | yes | Maven | http | face models: `http://nexus.pmon.dev:8081/repository/models/...` in build.gradle |
| site | yes | npm (`nexus_npm_registry`) | - | - |
| platform | yes (`apt-cache.yaml`) | - | - | - |
| ansible-lint, ci-tools, hyperfoil, keycloak-theme, sonar-scanner | yes | - | - | - |
| radio-scheduler, leetcode | - | Maven | http | - |
| radar | - | optional (`radar_nexus_url`, empty: Maven Central) | http | - |
| target-scorer | - | PyPI (`PIP_TRUSTED_HOST` to accept http) | - | - |
| infra | - | the ExternalSecret mapping | - | - |
| ops | - | the Vault seed, the legacy setup-woodpecker secret, CLAUDE.md, ci-bot test | - | - |

## Steps

Ordered so that nothing goes red midway: the URLs move before anything that only works with them. One push per repo
per round (the CI queue); the app repos through one PR at a time, the GitOps repos to main.

1. **Pilot, one repo (chess).** A PR whose ci.yaml sets `NEXUS_URL: https://nexus.pmon.dev` in place of the secret.
   Its CI is the proof that a pipeline pod resolves, connects and verifies through Caddy. The PR is closed, not merged.
   Watch pi2's Caddy and Nexus CPU over the run.
2. **The Vault values** (ops). `seed-vault-secrets.yml` sets `nexus_url: https://nexus.pmon.dev` and
   `nexus_npm_registry: https://nexus.pmon.dev/repository/npm-public/`, as does setup-woodpecker.yml's legacy copy.
   CLAUDE.md and the ci-bot unit test follow. Run the seed; External Secrets refreshes `woodpecker-ci-secrets`. Proof:
   the next pipeline of each kind is green (a Gradle app, site's npm, target-scorer's PyPI). `allowInsecureProtocol` is
   harmless over HTTPS, so nothing breaks before step 3. Way back: seed the old values.
3. **Per repo, one change each.**
   - Kaniko: `--registry-mirror=nexus-docker.pmon.dev`, without `--insecure-registry` (12 repos).
   - Gradle wrapper: `distributionUrl=https\://nexus.pmon.dev/repository/gradle-distributions/...` (8 repos). The
     pinned `distributionSha256Sum` stays: it is the same file.
   - `allowInsecureProtocol` removed from build.gradle (8 repos, radar's backend included).
   - masi's face-model URL to https.
   - target-scorer: `PIP_TRUSTED_HOST` removed.
   - Each repo's proof is its own CI and CD: an image built through the HTTPS mirror, its wrapper fetched over HTTPS.
4. **Renovate**. The wrapper's checksum task (ops `renovate/apps.json`, monitor-9a's) must keep the `https\://` URL a
   bump writes; checked on the first wrapper bump after step 3, or by a dry run before it.
5. **Close the plain ports to pipelines** (infra). Once no repo names 8081/8082 and a day of Nexus's request log shows
   none from ten (192.168.11.2) on those ports, drop 8081 and 8082 from `woodpecker-pipeline`'s egress to the VIP.
   NetworkPolicy changes are not on the closed list: a copy run first. The ports stay open on the LAN for the
   workstation and radar's optional mirror; that is not this plan.
6. **Docs.** ops CLAUDE.md's Nexus section and the vagrant inventory's `pi_served_names` comment (true for
   `nexus-docker` only since 2026-11-21).

## Not in scope

- Nexus's own HTTP listeners on the Pis: the workstation and radar still reach 8081 directly.
- Image digest pins: already decided separately (Renovate `pinDigests` for the app Dockerfiles, live 2026-11-21).

## Done when

Every live repo's pipelines fetch from Nexus over HTTPS only; `git grep` for `:8081`, `:8082`, `insecure-registry`,
`allowInsecureProtocol` and `PIP_TRUSTED_HOST` finds nothing in any live repo; the pipeline NetworkPolicy has no
8081/8082; a week of green builds after.
