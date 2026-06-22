# Renovate (automated dependency-update PRs)

Renovate runs as a Woodpecker **cron** pipeline against the self-hosted Forgejo
(`platform=forgejo`), modelled on the proven `depcheck-nightly` pipeline. Repo
policy lives in each repo's `renovate.json`; the runner lives in
`.woodpecker/renovate.yaml`. Rolled out to **monitor** first, then fanned out.

## One-time setup (manual — needs Forgejo admin + Woodpecker access)

1. **Bot account** — create a Forgejo user `renovate-bot` (set full name + a
   real email, e.g. `renovate-bot@pmon.dev`). Give it **write** access to
   `schnappy/monitor` to start.
2. **Bot PAT** — as `renovate-bot`, mint a Personal Access Token scoped to
   `repository` (read+write) and `read:organization`. Add it to the existing
   `woodpecker-ci-secrets` secret under a **new** key `renovate_token` (do NOT
   overload `infra_pat` — Renovate must author commits/PRs as the bot, not as
   the infra account).
3. **GitHub read token** — mint a github.com **read-only**, no-scope PAT and add
   it under key `renovate_github_token`. Renovate uses it only for changelog /
   release-note lookups and to avoid github.com rate-limiting; it grants no
   write access.
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
