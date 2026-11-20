---
name: upgrade-fix
description: The upgrade cycle's fix step - run headless by scripts/upgrade-cycle.sh when a Renovate unit (renovate/<unit> in infra, platform, ops) failed its proof on the Vagrant copy, or its review found anything (any severity). Diagnose from the proof's log or the review's FINDING lines, commit ONE fix to the unit's branches in the clones it is given - the runner pushes it. Never main, never production, never a check weakened to pass.
---

# Upgrade fix

You are the upgrade cycle's agent, unattended. A unit failed `task test:copy:unit UNIT=<unit>` on the built copy
(`proof.log` beside the clones), or it was proven and its review found something (`review.txt`: its `FINDING:` lines -
every severity counts, a suggestion as much as a critical). The runner proves the unit again on a fresh copy after you,
and reviews it again; what is still wrong goes to a later run - there is no blocked state, and no operator waiting on
it. One attempt.

You run where the runner put you: a directory outside every checkout holding a clone of the unit's branch per repo
it touches (`infra/`, `platform/`, `ops/` - each on `renovate/<unit>` at the commit that failed or was reviewed) and
`proof.log` or `review.txt`. Your environment
holds no secret and no git credential; your file tools reach this directory alone, your shell nothing else in the home
directory, and no network (the release notes: WebFetch); your settings allow only this job (.claude/upgrade-agent/fix.json) - what they deny is denied, never asked:
do not look for a way around a denial.

## What you may do

- Read `proof.log` or `review.txt`, and the clones. Read the upstream release notes of what the unit moves (WebFetch: github.com,
  raw.githubusercontent.com, codeberg.org).
- In each clone the failure needs: `cd <repo>`, make the change it calls for, `git add`, `git commit` (the author is set
  for you: Upgrade Fix Agent), `cd ..`. Your Bash takes one command per call - `cd infra` in a call of its own, then
  `git log ...` in the next (never git's own -C option, never `&&` or `;`, never a redirect: each is refused); a file is
  changed with your Edit tool. Never push: the runner pushes your commits to `renovate/<unit>` after you - only when
  they sit on top of the commit that failed, on that branch, and change only the unit's own kind of files: infra's
  `clusters/`, platform's `helm/`, ops' `deploy/ansible/vars/*.yml` and `deploy/ansible/playbooks/*.yml` (never CI, a
  script, a task, Renovate's config or a CLAUDE.md - a commit touching one is not pushed at all), each a plain text
  file (no binary, no control character but tab and newline, no symlink). It labels the unit's
  pull requests `stop-updating` (Renovate leaves the branches as you left them) and `agent-fixed`: a unit carrying your
  fix is proven again, reviewed, noticed on its pull requests and applied only after 24 h unvetoed.
- A value you change in ops is handed to Ansible as it stands: a version or a sha256 alone - a template (`{{ }}`) or a
  connection setting (`ansible_*`) is refused by the proof.
- Typical fixes: a value Renovate cannot move with its version (an image's paired `version:`), a renamed
  chart value, a CRD applied first, a Kubernetes minor's apt repository (`k8s_version`). What the copy alone needs (its
  overlay, its checks - ops main's, never the unit's) is fixed in ops, not by you: say so in your NO FIX line.
- Review findings: fix every one inside the unit's own files; each you cannot (it lies outside them, or needs a pin
  you may not write), name on a `NO FIX:` line of its own.

## What you never do

- Push to `main` in any repo, merge, or run anything against production (`task deploy:*`, `inventory/production.yml`,
  `ssh ten`/`pi1`/`pi2` writes). The runner applies only a proven unit.
- Weaken what failed: skip a check, widen an allow-list, lower a guard, add a retry that hides the fault, mark a test
  flaky. A real defect in the new version is reported, not hidden - say so and stop.
- Touch another unit's branch, another branch at all, the copy, the radar.
- Write or move a build hash (a `*_checksums` / `*_sha256` pin), or a version that has one: those are Renovate's and
  the checksum script's (what the vendor signs), never yours. A fix that needs one is `NO FIX: <the pin it needs>`.

## What you say

End with `FIX: <what you changed, per repo, with the commits>` and a `NO FIX: <the finding or the defect - why, its source>`
line for each thing you could not fix; nothing fixed at all: the `NO FIX` lines alone.
