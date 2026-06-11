---
name: full-review
description: Unified review for schnappy repos — runs the built-in code-review and security-review skills, the code-architecture-reviewer agent, and a SonarQube server-state check over one scope, then merges everything into a single deduplicated report. Use when the user asks for a full/complete/thorough review of changes, a PR, or a plan doc.
argument-hint: "[low|medium|high|xhigh|max|ultra] [PR# | commit | files... | plan-doc] [--no-simplify]"
---

# Full review

Run up to three independent review passes over one scope, then merge them into a single report. Do not start fixing anything — the deliverable is the merged review.

## 1. Establish scope

Parse `$ARGUMENTS`:
- An effort level (`low|medium|high|xhigh|max|ultra`) applies to the code-review pass. Default: `medium`.
- A PR number, commit SHA, file paths, or a plan-doc path narrows the scope. Default: pending changes on the current branch (working tree + commits ahead of main); if the tree is clean and nothing is ahead, the `HEAD` commit.
- A plan/design doc (e.g. `ops/docs/plans/*`): run only the architecture pass — the other two need code diffs.
- `ultra` launches the billed cloud review — pass it through only when the user typed it themselves.

## 2. Run the passes

Run these as parallel tool calls in one message where possible; all three get the same scope description.

1. **Correctness & quality** — invoke the built-in `code-review` skill (Skill tool) with the effort level and target (PR number, commit, or files).
2. **Security** — invoke the built-in `security-review` skill. It only works on pending changes on the current branch; when the scope is a PR, an already-pushed commit, or a plan doc, skip it and say so in the report rather than running it against the wrong diff.
3. **Architecture & house rules** — spawn the `code-architecture-reviewer` agent (Agent tool) with the scope. Tell it generic correctness and security are covered by other passes, so it should weight its architecture/infra dimensions, environment fit, and house-rules checklist. Its profile lives in `ops/.claude/agents/code-architecture-reviewer.md`.
4. **SonarQube (server state)** — query the SQ Web API at `https://sonar.pmon.dev` with `SONARQUBE_TOKEN` from `/home/sm/src/ops/.env` (basic auth, token as username, empty password). Project key comes from `sonar-project.properties` in the repo root, falling back to `schnappy-<repo>`. Fetch `/api/qualitygates/project_status?projectKey=…` and `/api/issues/search?components=…&resolved=false`, then filter issues to the scoped files. Do not run a local scanner. SQ reflects the last CI-analyzed commit: when reviewing unpushed changes, say so and treat line numbers as approximate; a failing quality gate is always worth reporting regardless of scope.

When the user asked to review a PR (the built-in `/review` use case), give the PR reference to passes 1 and 3; pass 3 can fetch the diff with git.

If a built-in skill is unavailable in the current session (headless runs may not have the bundled skills), perform that pass inline yourself with the same criteria and note the substitution in the report.

## 3. Merge

- Deduplicate: when two passes flag the same issue, keep the most specific writeup and note the corroboration — corroborated findings are higher-confidence.
- Single report ordered Critical / Warning / Suggestion. Each finding: `file:line`, what's wrong, why it matters here, concrete fix, and which pass found it.
- Conflicting verdicts between passes: investigate yourself and resolve to one verdict; never print both.
- End with a **Verified** section (what was checked and found clean) and a one-line note of which passes ran and which were skipped (with the reason).

## 4. Simplify (automatic)

When the scope is local pending changes, finish by invoking the built-in `simplify` skill to apply quality cleanups (reuse, dead code, altitude, efficiency — it edits the working tree; it does not hunt bugs), then summarize what it changed under the report. Skip it — with a note saying why — when the user passed `--no-simplify`, when the scope is a PR, pushed commit, or plan doc (no local tree to clean up), or while Critical findings remain unaddressed: fix-worthy bugs come first, and simplifying code that's about to be rewritten is wasted motion.
