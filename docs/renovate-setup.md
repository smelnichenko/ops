# Renovate (automated dependency-update PRs)

Two Renovates use the `renovate-bot` account:

- **The upgrade cycle's** - infra, platform and ops (docs/plans/120-automated-upgrade-cycle.md): `task upgrade`, started
  by hand on the workstation (operator 2026-11-15: Renovate and the runner one task, run locally, no CI cron) -
  `scripts/upgrade-renovate.sh` runs the pinned `renovate/renovate` image in docker with the bot's token
  (`.env` `RENOVATE_TOKEN`, by name) and the shared preset `renovate/upgrade-cycle.json` (each repo's `renovate.json`
  extends it), then `scripts/upgrade-cycle.sh` proves one unit on the Vagrant copy and applies it. `task upgrade
  LOOKUP=true` reads only. Its Woodpecker pipeline (`.woodpecker/renovate.yaml` in ops) is gone.
- **monitor's and masi's** - `task renovate:apps`, by hand on the workstation (operator 2026-11-16):
  `scripts/upgrade-renovate.sh --apps` - the same image and bot (`.env` `RENOVATE_TOKEN`), each repo's own
  `renovate.json`, dependency PRs on `schnappy/monitor` and `schnappy/masi`; `LOOKUP=true` reads only. Their weekly
  Woodpecker cron and pipeline (`.woodpecker/renovate.yaml`) are gone, and with them the token `woodpecker-ci-secrets`
  carried (`renovate_token`, `renovate_github_token`): it was renovate-bot's, which can push to infra, platform and ops,
  and every pipeline can mount that secret. No second bot.

What follows is the history of the cron pipeline (retired 2026-11-16).

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
   mint a PAT scoped `read:user` + `write:repository` + `write:issue` +
   `read:organization` (Renovate calls `/user` at init, opens PRs + the
   dependency-dashboard issue, and autodiscovers the org) and put its value in
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

## Fan-out (after monitor is proven) - superseded

Superseded by the upgrade cycle (top): infra, platform and ops extend `local>schnappy/ops//renovate/upgrade-cycle`, run
by `task upgrade`. The plan below is kept as it was.

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

- [scripts/upgrade-renovate.sh](../scripts/upgrade-renovate.sh) and `task upgrade` - the upgrade cycle's Renovate.
- [renovate/upgrade-cycle.json](../renovate/upgrade-cycle.json) - its shared preset (infra, platform, ops extend it).
- [monitor/renovate.json](../../monitor/renovate.json) — repo policy (self-contained for the first rollout; later `extends` the shared preset).
- [monitor/.woodpecker/renovate.yaml](../../monitor/.woodpecker/renovate.yaml) — the cron runner.
