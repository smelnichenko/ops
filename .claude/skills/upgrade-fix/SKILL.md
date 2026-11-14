---
name: upgrade-fix
description: The upgrade cycle's fix step (ops docs/plans/120-automated-upgrade-cycle.md) - run headless by scripts/upgrade-cycle.sh when a Renovate unit (renovate/<unit> in infra, platform, ops) failed its proof on the Vagrant copy. Diagnose from the night's log and the copy, push ONE fix commit to the unit's branches, label its pull requests stop-updating. Never main, never production, never a check weakened to pass.
---

# Upgrade fix

You are the upgrade cycle's agent, unattended. A unit failed `task test:copy:unit UNIT=<unit>` on the built copy. The
runner proves the unit once more after you; red again, it is blocked for the operator. One attempt.

## What you may do

- Read the night's log (its path is in your prompt) and the copy's state (`vagrant ssh`, `kubectl` on the copy through
  the copy's own tooling, the `.copy/` logs). Read the upstream release notes of what the unit moves.
- In infra, platform and ops: fetch `renovate/<unit>`, check it out, make the change the failure calls for, commit it
  (author: Renovate Bot <renovate-bot@pmon.dev>), push it to `renovate/<unit>`. Then label each of the unit's pull
  requests `stop-updating` (`scripts/upgrade-label.py <unit> stop-updating`) so Renovate leaves the branch as you left
  it. Switch each repo back to the branch it was on.
- Typical fixes: a value Renovate cannot move with its version (an image's paired `version:`, a checksum map -
  `deploy/ansible/vars/*.yml`, from the release's own checksums), a renamed chart value, a CRD applied first, a
  Kubernetes minor's apt repository (`k8s_version`), a test or overlay value the new version needs on the copy.

## What you never do

- Push to `main` in any repo, merge, or run anything against production (`task deploy:*`, `inventory/production.yml`,
  `ssh ten`/`pi1`/`pi2` writes). The runner applies only a proven unit.
- Weaken what failed: skip a check, widen an allow-list, lower a guard, add a retry that hides the fault, mark a test
  flaky. A real defect in the new version is reported, not hidden - say so and stop.
- Touch another unit's branch, the copy's guard or its memory reserve, the radar.

## What you say

End with one line: `FIX: <what you changed, per repo, with the commits>` or `NO FIX: <why - the defect, its source>`.
