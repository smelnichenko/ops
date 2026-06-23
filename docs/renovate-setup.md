# Renovate (automated dependency-update PRs)

Renovate runs as a Woodpecker **cron** pipeline against the self-hosted Forgejo
(`platform=forgejo`), modelled on the proven `depcheck-nightly` pipeline. Repo
policy lives in each repo's `renovate.json`; the runner lives in
`.woodpecker/renovate.yaml`. Rolled out to **monitor** first, then fanned out.

## Setup

The bot's PAT reaches CI the same way `infra_repo_token` does — its value lives in
the localhost `.env`, `seed-vault-secrets.yml` writes it to Vault
(`secret/schnappy/woodpecker-ci`), and the `woodpecker-ci-secrets-es`
ExternalSecret (`infra/clusters/production/cluster-config/`) surfaces it into the
`woodpecker-ci-secrets` k8s Secret that the pipeline reads. The Secret is
**ESO-managed**, so writing keys directly with `kubectl`/Ansible is futile —
always go through Vault + the ExternalSecret.

1. **Bot account (one-time, manual via forgejo_admin)** — create a `renovate-bot`
   Forgejo user (email `renovate-bot@pmon.dev`, `RENOVATE_BOT_PASSWORD` from the
   localhost `.env`) and grant it **write** on `schnappy/monitor`. As the bot,
   mint a PAT scoped `write:repository` + `read:organization` and put its value in
   `.env` as `RENOVATE_TOKEN` (never `infra_pat` — Renovate authors as the bot,
   not the infra account). *Done: the user exists and the token is in `.env`.*
2. **GitHub read token (optional)** — set `RENOVATE_GITHUB_TOKEN` in `.env` to a
   github.com **read-only, no-scope** PAT for changelog/release-note lookups and
   to dodge github.com rate-limiting (no write). Safe to leave empty for the first
   run (Renovate just runs without it).
3. **Seed + surface** — `seed-vault-secrets.yml` carries `renovate_token` +
   `renovate_github_token` into Vault and the ExternalSecret maps both into
   `woodpecker-ci-secrets`. Apply with `task deploy:seed-secrets` (Vault write) +
   ArgoCD sync of `cluster-config`; ESO then refreshes the Secret.
4. **Cron** — in the Woodpecker UI/API, add a cron named `renovate` on the
   `monitor` repo, schedule `0 4 * * 1` (Mon 04:00), branch `main` — exactly how
   `depcheck-nightly` was created.

## First run + verification (monitor only)

- Trigger the `renovate` cron once manually. Renovate opens an **onboarding PR**
  ("Configure Renovate") plus a few dependency PRs against `schnappy/monitor`.
- Confirm each dependency PR triggers `ci.yaml` (`./gradlew check`) and Forgejo
  shows the status check; confirm **automerge** fires for a patch/digest PR once
  green.
- Confirm `git.pmon.dev/schnappy/*` images are **not** proposed (first-party
  images are promoted via `task promote:prod`, never Renovate — see the
  `packageRules` `enabled:false` in `renovate.json`).
- Tune `prConcurrentLimit` / schedule from the first run's PR volume.

## Fan-out (after monitor is proven)

- Add the same `.woodpecker/renovate.yaml` is **not** needed per-repo. Instead
  switch to ONE central runner: a single `renovate.yaml` cron (in `ops` or a
  dedicated `renovate-config` repo) with `RENOVATE_AUTODISCOVER=true` and
  `RENOVATE_AUTODISCOVER_FILTER=schnappy/*`, so the bot iterates every repo in
  one scheduled run — simpler than 10 separate Woodpecker crons. Give the bot
  account write access to the other repos.
- Drop a 2-line `renovate.json` (`{ "extends": ["local>schnappy/renovate-config"] }`)
  into each repo (admin, chat, chess, site, platform, infra, ops,
  keycloak-theme) once a shared `schnappy/renovate-config` preset repo exists,
  so policy is defined once.
- Managers in play across repos: gradle / gradle-wrapper (Java services), npm
  (site/Vite), dockerfile, helmv3 (platform charts), and a custom regex manager
  for `.woodpecker/*.yaml` `image:` lines. Pin the currently-floating pipeline
  images (`alpine/helm:latest`, the `renovate/renovate` runner) to explicit tags
  so the docker/regex managers can track and bump them.

## Files

- [monitor/renovate.json](../../monitor/renovate.json) — repo policy (self-contained for the first rollout; later `extends` the shared preset).
- [monitor/.woodpecker/renovate.yaml](../../monitor/.woodpecker/renovate.yaml) — the cron runner.
