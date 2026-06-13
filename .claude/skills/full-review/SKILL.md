---
name: full-review
description: Unified review for schnappy repos — runs the built-in code-review and security-review skills, the code-architecture-reviewer agent, and a SonarQube server-state check over one scope, then merges everything into a single deduplicated report and auto-fixes every actionable issue it found, in-diff and pre-existing alike (the rest are listed as Remaining). Runs end-to-end without confirmation prompts. Use when the user asks for a full/complete/thorough review of changes, a PR, or a plan doc.
argument-hint: "[low|medium|high|xhigh|max|ultra] [PR# | commit | files... | plan-doc] [--no-simplify]"
---

# Full review

Run up to four independent passes over one scope, merge them into a single report, then apply the automatic follow-ups (steps 4–5) without pausing for confirmation — no AskUserQuestion, no "should I proceed?". The only thing that still requires the user's own keystroke is `ultra` (billed cloud review). Step 4 defines what gets fixed automatically and what lands under **Remaining**.

## 1. Establish scope

Parse `$ARGUMENTS`:
- An effort level (`low|medium|high|xhigh|max|ultra`) applies to the code-review pass. Default: `medium`.
- A PR number, commit SHA, file paths, or a plan-doc path narrows the scope. Default: pending changes on the current branch (working tree + commits ahead of main); if the tree is clean and nothing is ahead, the `HEAD` commit.
- A plan/design doc (e.g. `ops/docs/plans/*`): run only the architecture pass — the other two need code diffs.
- `ultra` launches the billed cloud review — pass it through only when the user typed it themselves.

## 2. Run the passes

Run these as parallel tool calls in one message where possible; all four get the same scope description.

1. **Correctness & quality** — invoke the built-in `code-review` skill (Skill tool) with the effort level and target (PR number, commit, or files).
2. **Security** — invoke the built-in `security-review` skill. It only works on pending changes on the current branch; when the scope is a PR, an already-pushed commit, or a plan doc, skip it and say so in the report rather than running it against the wrong diff.
3. **Architecture & house rules** — spawn the `code-architecture-reviewer` agent (Agent tool) with the scope. Tell it generic correctness and security are covered by other passes, so it should weight its architecture/infra dimensions, environment fit, and house-rules checklist. Its profile lives in `ops/.claude/agents/code-architecture-reviewer.md`.
4. **SonarQube (server state)** — run the bundled helper from the repo root: `bash <this skill's base directory>/sonar.sh [projectKey]`. It resolves the project key from `sonar-project.properties` (falling back to `schnappy-<repo dir>`), reads `SONARQUBE_TOKEN` from `/home/sm/src/ops/.env`, and prints the quality-gate status and unresolved issues as JSON (capped at 500 issues, the API max — check `paging.total` and say so when it exceeds the page). Filter issues to the scoped files. Do not run a local scanner, and do not query the API with ad-hoc curl — the helper is permission-allowlisted so it runs without prompting. SQ reflects the last CI-analyzed commit: when reviewing unpushed changes, say so and treat line numbers as approximate; a failing quality gate is always worth reporting regardless of scope.

When the user asked to review a PR (the built-in `/review` use case), give the PR reference to passes 1 and 3; pass 3 can fetch the diff with git.

If a built-in skill is unavailable in the current session (headless runs may not have the bundled skills), perform that pass inline yourself with the same criteria and note the substitution in the report.

## 3. Merge

- Deduplicate: when two passes flag the same issue, keep the most specific writeup and note the corroboration — corroborated findings are higher-confidence.
- Single report ordered Critical / Warning / Suggestion. Each finding: `file:line`, what's wrong, why it matters here, concrete fix, and which pass found it.
- Conflicting verdicts between passes: investigate yourself and resolve to one verdict; never print both.
- End with a **Verified** section (what was checked and found clean) and a one-line note of which passes ran and which were skipped (with the reason).

## 4. Fix issues (automatic)

After the report, fix the issues it surfaced — both findings on the diff under review and pre-existing problems flagged by any pass: bugs, stale docs, broken CI paths, references to retired services, open SonarQube issues with a mechanical remediation (rule quick-fixes such as unused-variable renames). Apply each fix minimally in the working tree without asking for confirmation, even when it lands in a sibling schnappy repo. Do not commit and do not run tests. Out of bounds — list under **Remaining** instead of fixing: anything needing a product decision, new tests (e.g. a failing coverage gate), schema or API changes, or touching live hosts. Summarize every file changed under the report.

## 5. Simplify (automatic)

When the scope is local pending changes, finish by invoking the built-in `simplify` skill to apply quality cleanups (reuse, dead code, altitude, efficiency — it edits the working tree; it does not hunt bugs), then summarize what it changed under the report. Skip it — with a note saying why — when the user passed `--no-simplify`, when the scope is a PR, pushed commit, or plan doc (no local tree to clean up), or while Critical findings remain unaddressed: fix-worthy bugs come first, and simplifying code that's about to be rewritten is wasted motion.
