# Plan 120 — the automated upgrade cycle

Status: **BUILDING** (operator 2026-11-14: "start building plan 120 meanwhile", "ensure renovate works with
vagrant") - the review answered 2026-11-14 (below); plan 119's wave 1 done by hand (2026-11-14); rollout step 1 (the
lookup) run - its findings fixed below, three questions open. 2026-11-15: one manual task, Kafka's operator first
(decisions below); review rounds two to eight done - the applying runner waits for its first clean shadow proof.

**Built 2026-11-14 (ops upgrade/wave-1 branch, each with its harness):**
- Renovate: `renovate/upgrade-cycle.json` (the shared preset - units, groups, one minor at a time for Kubernetes/
  Cilium/Istio, ClickHouse's and Forgejo's lines held, majors labelled, 3 days' release age; validated by
  renovate-config-validator 44.198.3), `renovate.json` in ops (infra and platform: their `upgrade-cycle/renovate`
  branches), `.woodpecker/renovate.yaml` (cron, image pinned, lookup mode - gone 2026-11-15 for `task upgrade`), 15 ops
  version vars annotated.
- Its proof on the copy: `scripts/copy-unit.sh` / `task test:copy:unit UNIT=<it> [PLAN=true]` (the unit's branches,
  test:copy:change, each ops part's playbook from the branch's values; an unknown value refused).
- The run: `scripts/upgrade-cycle.sh` (`--dry`, `--preflight`; `--shadow` - task upgrade SHADOW=true), `upgrade-units.py` (the pick),
  `upgrade-label.py` (labels, comments, merges - whole or not at all), `upgrade-verify.sh`, `upgrade-record.sh`,
  `upgrade-notice.sh` (platform's `upgrade-cycle/notices` branch routes the UpgradeCycle alert), the agent's
  `.claude/skills/upgrade-fix`.
**Done since:** the renovate-bot reset (operator: "reset renovate-bot with forgejo_admin yourself"), its PAT in
ops/.env RENOVATE_TOKEN, write access to infra/platform/ops (operator: "grant it").
**Built 2026-11-15:** `task upgrade` (`scripts/upgrade-renovate.sh`: the pinned image in docker, the bot's token by
name, the allowed command from its file, no bind mount; a run that logs an error or reads a repository short stops
before the runner; harness `upgrade-renovate`) - `LOOKUP=true` alone: the real run is refused until the runner's open
items below are done (its first real run's review, 2026-11-15, found them - the runner had never run).
**The runner's open items - DONE 2026-11-15 (each with its harness; the first real run's review found them):** the
headless agents (fix, review) run with a clean environment (`env -i` HOME PATH: none of ops/.env, the account's login
rather than the API key), settings of their own (`.claude/upgrade-agent/fix.json`, `review.json`, `--permission-mode
dontAsk --permission-prompts none` - what they do not allow is denied, never asked; smoke-tested: a push and kubectl
denied; both `--restricted` since the rounds below), in clones of the unit's branches (outside every checkout since
round two: `../.upgrade-cycle-work`); the runner labels stop-updating itself. The gates before anything (and `--preflight` before
Renovate): the backup windows from the real schedules (00:50-04:00 daily: the mirror at 04:00 local, CNPG 01:30,
Velero 02:00, the Pis' backups 02:40, ScyllaDB and Sunday's Velero 03:00; Sundays 04:00-05:00 ScyllaDB's repair;
05:20-05:50 the Pis' restore check), no open page (posted again), ops on main clean and origin's, the memory free
(refused at once), no apply recorded today. The heads read before the proof and after it, the merge pinned to them
(`--merge --expect`, Forgejo's head_commit_id); the plan read or the unit blocked; `task deploy:etcd:backup` (a Job
of its own name, waited for) checked; the window read again before the apply (refused when near - never waited out);
the pull checked. Units
and notices only the bot's (author, head repository). Notices: a JSON post to Alertmanager's API (proven against
v0.34.1: quotes, $, newlines intact), a start, a label each, the log's tail; pages recorded, mailed straight out too,
`resolve`/`repost`/`open`; verify skips the cycle's own page. Platform: the notices' route ahead of the critical one,
their own subject, the inhibit rule by unit, CI running amtool and Alertmanager itself on the config.
**Second review round (2026-11-15) - done:** the fix agent `--restricted` with its Bash sandboxed (bubblewrap: the
credentials unreadable, no network but the checksum script's vendors), committing only - the runner checks its commits
(on the unit's branch, on top of the proven head) and pushes them as the bot; no copy access for it (`vagrant ssh`
passes options to ssh); clones outside every checkout; plain git (`git -C` never matches a wildcard rule) - each proven
with Claude Code's CLI 2.1.308. The runner's own lock; the gates again right before the merge (hours later), with the
local infra/platform mains, production's live Alertmanager route and production's health; the plan's production
commands mapped before the merge (node_exporter's added); held (veto, upgrade-blocked, the kill switch) read again; a
journal of the apply (`.upgrade-cycle/inflight`) and a signal trap after the merge; a partial merge exit 3 - paged and
the cycle paused (the dashboard's upgrades-paused); bases pinned (main moved since the proof refuses the merge); ops
brought by fetch and fast-forward (a pull followed the operator's pull.rebase and refused on the copy's inventory
record); the etcd snapshot right before kubeadm (before the merge since round four); the copy destroyed after the
review; a copy that does not build ends the run without blaming the unit; the veto mail before its comment; the record
committing only its paths.
**Rounds three and four (2026-11-15) - done:** what the agent writes is held off the workstation and production until
proven, reviewed and noticed: its Bash sandbox reads nothing of the home directory but the clones (`denyRead ~`,
`allowRead` the clones; `.git`'s hooks and config unwritable - each proven with the CLI), its checksum script the
runner's copy (`.trusted/`, outside what it may edit); the runner fetches its commits into a repository of its own,
keeps them only inside the unit's own files (infra's `clusters/`, platform's `helm/`, ops' Ansible vars and playbooks -
never CI, scripts, tasks, Renovate's config or a CLAUDE.md) and pushes from there to Forgejo's URL; a unit it fixed is
labelled `agent-fixed` and waits for a 24 h notice with its diff, as a major does (the latest notice starts the 24 h).
The copy hands Ansible only versions and hashes from a unit's branch (a template or an `ansible_*` setting refused - it
runs on the workstation) and hands it Argo CD's and node_exporter's new values (it proved main's before); a changed
task in setup-kubeadm refused. The review `--restricted` (no instructions from the clones), the reviewers' own agents
handed to it, every pass named (correctness, security, architecture, reliability, tests) or no verdict; labelled
only on CRITICAL (a review or fix that did not finish is retried, not blocked). CD's app promotions on infra's main
(the two app-tag files, Woodpecker's author: ~16 a day) no longer refuse a proof or a merge
(`scripts/cd-promotions.json`). The gates: Alertmanager's loaded config probed, critical alerts in the one look before
an apply, a journal with no page paged by the next run, the start's span the proof's time and the apply's (270 min).
The apply: the etcd snapshot (`scripts/etcd-backup-now.sh`, the Job's own conditions - it retries a pod) before the
merge; a refused merge leaves no journal; an unknown merge answer (read again for 2 min) pages; ops fast-forwarded after
every merge; Argo settled on the merge's commits before the commands and in the verify (Argo polls; preview apps
aside; one thing wrong for 5 looks in a row fails the hold); a closed terminal stops nothing after the journal; no step
holds the run's lock; Renovate refuses to run beside a runner. Notices: a veto mailed straight out too; the kill switch
fails closed (no dashboard issue: not read) and a pause makes the issue where none is open; platform's CI Alertmanager
image moved with the chart's (one Renovate branch).
**Round five (2026-11-15) - done:** an agent's fix is judged in every repo before any of it is pushed (half a fix,
unlabelled, would have applied with no notice later), the unit labelled agent-fixed before the first push, plain files
alone (no symlink or submodule - the copy's mirror refuses them too); the fix kept on record (`.upgrade-cycle/fixes/`)
and mailed whole with its notice whichever run gives it (over 100 KB: no notice, no clock); the trusted checksum copy
read-only and `git --output` denied; copy-unit refuses task changes in setup-argocd and setup-host-hardening too and
checks every setup-kubeadm value. A notice holds only for the diff it announced (`diff=<hash>` on its comment,
`upgrade-label.py --diff-hash`: changed lines, no context) - a newer release noticed again; notices are comments that
start as one. The kill switch read on all three repos' dashboards (Renovate's title exactly, the bot's issue). Liveness:
Renovate opens three pull requests a repo at most, in the cycle's order (prConcurrentLimit, prPriority); green waits an
hour for a running CI and labels a red one; a unit behind main is never read as its defect (stop-updating units
brought up to date by Forgejo); a failure with no verdict counts a try, the third blocks; CD's file editable by a unit in
other lines (k6's image: Forgejo's mergeable judges). The apply: a 5xx on a merge is not a refusal (read again, its head
on main counts as merged); any merge exit but Forgejo's refusal pages; ops' main must hold the gate's and the unit's
merge alone; the journal holds the etcd snapshot's name and the pull requests merged, and one ending verified is a
record to push, not a page; verify compares each app against its spec, says a stalled one, leaves preview environments'
pods and alerts out, wants two clean looks when it waits for Argo and a streak of 10 in the hold; the spans 210 (the
apply's own waits) and 330 at the start; the etcd check reads the pod that succeeded.
**Round six (2026-11-15) - done:** a notice is bound to the heads it announced (`heads=` on its comment): an apply run
checks with git that each head proven now descends from the announced one with nothing but main's commits merged in -
else noticed again (the diff hash it replaces could not see a carriage return, a binary or a rename). The agent has no
checksum script and no network for its shell (a relative path to the "trusted" copy ran a script the agent made);
its files must be plain text (no NUL, no control character but tab and newline); the record of its fix starts again
for a new instance of a unit's name, is removed on apply, and over 100 KB blocks the unit (an oversize veto is refused
before Alertmanager is posted to). Renovate rebases a branch only on a conflict and has no cap (the cap split units
across repos); the runner brings the picked unit onto main by Forgejo's update in every repo (ops too), waits for the
new heads; a red CI is a try; tries are counted per unit (heads move with every update) and reset by a notice, a
shadow proof or an apply; ops' main must still be the gate's right before the merge; the test path pages unless every
complaint is placed in the test environment; issue comments are read in one request (Forgejo takes no pages there - a
loop with no end at 50); verify keys its hold's streak on the subject (the app, the pod's owner, the alert) and keeps
an empty Helm `values` out of the spec comparison; the etcd check tries each pod that succeeded; the seed playbook maps
monitor's and masi's `renovate_token` to a bot of their own (`RENOVATE_APPS_TOKEN`), never the cycle's.
**Round seven (2026-11-15) - done:** the agent commits as an author of its own (Upgrade Fix Agent,
upgrade-fix@pmon.dev): Renovate takes a branch whose commits carry its own e-mail for unmodified and rebases over
them. Its files are UTF-8 with no control, format, separator, private or unassigned character but tab and newline (a
NEL or U+2028 is a line break to YAML and none to git or a diff; a bidi override or a zero-width character hides what
the mail shows), no merge commit of its own, and its commit subjects reach the record escaped. A notice holds only when
nothing since it but main's - no commit of its own outside main, each merge's tree exactly the one git's own merge
of its parents makes (an evil merge, a side branch merged in: noticed again; proven with real git). The notice's mail is a summary
of what the unit changes - each repo's stat, its commits, the review's passes and verdict, the diff; 100 KB in all, the
diff cut first (a fix's: its record whole) - and stop-updating is labelled before it (a newer release pushed by Renovate would void the notice:
a loop). Tries are counted for the unit's pull requests (a new instance of the name starts at none); a CI still
running after an hour, git or Forgejo not read, main moving while the CI ran: said, no try. The runner updates the
branches first and then waits for their CI (a CI run on a stale head was wasted), and never takes Forgejo's empty answer
for a head. A unit without Renovate's labels is never applied (its kind not known). The test path skips verify's own
headers and places only `schnappy-test` and `schnappy-test-<x>` in the test environment (not `schnappy-testing`).
Verify names a pod's owner by Kubernetes' name alphabet and counts a subject once a look; Renovate's debug record is
read strictly (its base64 validated, its labels a list); the etcd check reads each pod that succeeded until one says
OK; the seed playbook's harness checks monitor's and masi's token is empty, never the cycle's, without
`RENOVATE_APPS_TOKEN`.
**Round eight (2026-11-15) - done:** a notice holds by what the merge makes: the announced head an ancestor of the head
now, and `git merge-tree origin/main <head now>` the very tree `git merge-tree origin/main <announced>` makes - the
checks it replaces (no commit of its own outside main, each merge's tree git's merge of its first two parents) let an
octopus merge through whose third parent was main and whose tree dropped main's work (proven with real git: the merge
reverted a hardening, no new notice; older than round seven). The agent's added lines are printable ASCII and tab (a
no-break space indenting a key made it another key, the same in the mail; a look-alike letter the same) - lines it
keeps stay as they were; the character classes of round seven gave way to it (every one they refused is outside it); its tree is pushed as one commit of the runner's on the proven head (its commits - a step in
between with a CI file and a symlink, its words, its author - never reach Forgejo; fetched with fsck). A head with no
CI status at all after an hour is a try (no pipeline started - it never comes by itself; the label script's exit 5),
one still running on the same heads a run later a try; each checkout's branch must be the head its pull request names
after the fetch and after the proof (Forgejo's record may lag); the notice's summary reads those heads, says where it
was cut, and git failing on it stops the notice; tries keyed by the run's first read. Tests: the notice's summary
asserted whole, the second fetch failing alone, the test path's count reset, verify's subjects with look-alike tails
kept whole, the CI waiter's Postgres query read through a fake ssh (and against production's site pipeline 222 when
asked, CI_WAIT_LIVE=1); Sonar's two (an unused name, a nested conditional) fixed.
**The first real run:** `task upgrade RUNNER=false` - Renovate's branches and pull requests made, nothing applied; their
labels read (the shadow week checked them). Then `task upgrade SHADOW=true` proves and reviews a unit on the copy,
applying nothing - the cycle's first proof; until it ends clean (the runner's own record,
`.upgrade-cycle/shadow-proven`) the applying runner is refused, by the task and by the runner itself.
**The first shadow run (2026-11-16 05:52 UTC) proved nothing:** preflight passed, Renovate made 35 units (five of the
test environment), and the pick named `test-observability` - in a shadow run a test unit is a comment (no copy), and a
test unit is picked whenever one is open, so every shadow run stopped there. Fixed: a shadow run's pick
(`upgrade-units.py pick --shadow`) leaves the test environment's units out - the production units in their order, a
twin still waiting for its test unit (on production's units: `prove wave-patches patch`).
**Not yet:** a GitHub read token, or the six GitHub-sourced annotations moved to registries (RENOVATE_GITHUB_TOKEN in ops/.env is empty - ''; the 401 seen 2026-11-14 was the two quote characters sent as a token), `deploy:seed-secrets` for the bot's token (the operator's OK), Nexus
annotated, a one-way change's store backups beyond etcd (Postgres, ScyllaDB, ...: blocked). Strimzi's Kafka version
(`strimzi.kafkaVersion`, production's and the test environment's data values) is not annotated yet - a design point
first: the test environment's unit merges before its production twin, but the Strimzi operator is one, shared, and
comes with the production unit - a Kafka the operator does not support yet (4.3.2 needs Strimzi 1.3) would land in
the test environment first. The plain Kafka StatefulSet's image (apache/kafka) is left out: off in both, no pod runs it.
Argo CD in the cycle (2026-11-14): its chart default a value of its own (`argocd_chart_default`, annotated - the
lookup: argo-cd 10.9.7 -> 10.18.0 on renovate/argocd), its unit proven on the copy by setup-argocd.yml (the chart
default or an image pin moved; any other change refused) and applied by `task --yes deploy:argocd`.
The test environment's units (2026-11-14, decided in "What wave 1 by hand taught the cycle"): the lookup put test
files into five units (observability, k6 2.x, curl - platform's schnappy-test chart; both ScyllaDB lines - infra's
schnappy-test-data), and the copy's mirror refuses those: each would have failed its proof. The preset sends the test
environment's files to `renovate/test-<unit>` (additionalBranchPrefix; the lookup: test-observability,
test-grafana-k6-2.x, test-curlimages-curl-8.x, test-scylladb-2026.2/2026.3 - their production twins carry no test file).
upgrade-units.py picks an open test unit first (`test <unit> <kind>`, in its twins' order) and holds a production unit
while its test unit is open (blocked or vetoed too); upgrade-cycle.sh's `test` action: the one-way check, merged, the
cluster settled (upgrade-verify), recorded, reported - no copy, no review; red after the merge: blocked, not paged.

**Rollout step 1 - the lookup, 2026-11-14** (Renovate 44.198.3, `local` platform, `RENOVATE_DRY_RUN=lookup`, each
repo's branch exported to a scratch git directory under ops/.copy with the preset as its renovate.json - a `local>`
preset does not resolve on the local platform; read-only: the repos untouched, the registries read). Its units
reproduce plan 119's wave 2 table - Istio 1.32 (with its cni chart), External Secrets 2.15, kube-prometheus-stack
92/93 (two majors, one at a time), Strimzi 1.3.1 + the Scylla operator and Manager 1.23 (data-operators), Grafana
13.3.1 / k6 1.8.2 / kube-prometheus-stack 91.9 (observability), Fluent Bit 5.2, Centrifugo 6.10.3,
versitygw 1.11, SonarQube 26.10 - and the patch wave (Istio 1.31.4, ClickHouse 26.8.37, Grafana 13.2.6, etcd 3.6.16,
Kafka 4.2.2, ...). What it found, fixed in the preset and the runner (harness cases, each mechanism broken and caught):
- The unit names were not the runner's: Renovate prefixes a group's slug (`renovate/patch-wave-patches`,
  `renovate/minor-1.32-istio`), and its own monorepo group took Istio's cni (`renovate/istio-monorepo`). Now each
  group's branch topic is set whole: `wave-patches`, `istio-<X.Y>`, `kubernetes-<X.Y>`, `cilium-<X.Y>`,
  `scylladb-<X.Y>`; Renovate's groupings off (`group:monorepos`, `group:recommended`). upgrade-units.py orders a
  family's minors by number (istio-1.9 before istio-1.10), kubernetes and cilium families after istio.
- One-way units would have gone through: the runner judged them by names Renovate does not give (its Postgres major is
  `postgres-18.x`, Grafana's `grafana-grafana-13.x`; ScyllaDB 2026.1 -> 2026.3, one-way, sat in data-operators as a
  minor). Now the preset labels them `one-way` (Postgres, ScyllaDB release lines, Kafka, Strimzi, ClickHouse, Grafana,
  Vault, Consul majors) and the runner blocks on the label - the names a second net, its labels unread: nothing applied.
- Releases without a release time (Docker Hub, quay.io, ghcr.io, registry.k8s.io) stayed pending for good under the
  3 days' age (`timestamp-required`): Postgres 18, Grafana 13, Keycloak 26.8 and most of the patches never got a
  branch. `minimumReleaseAgeBehaviour: timestamp-optional` - the age holds where a time is given; the copy's proof and
  the review are the gate.
- Left out: kagent (disabled in production), the retired in-cluster Vault's values (no Argo app reads them), the etcd
  image's minors and majors (etcdctl follows kubeadm's etcd); kubectl images (alpine/k8s) move with the kubernetes
  family. `registryUrlTemplate` gone (an empty URL for each annotation without one: a warning each).
- Open, for the operator: (1) DONE 2026-11-15 (operator: option B): the six deps Renovate skipped without a GitHub
  token (Caddy, Consul, Vault, Keycloak on the Pis, Kubernetes, Gateway API) now read registries (Docker Hub, quay,
  registry.k8s.io) and Gateway API's git tags, versioning=semver - the lookup resolves all six with no token (Caddy
  2.10.0 -> 2.10.2/2.11.8, Consul 1.20.6 -> 1.22.7/2.1.0, Vault 1.21.4 -> 2.2.2, Kubernetes 1.36.6 -> 1.37.2,
  Gateway API 1.5.1 -> 1.6.3/1.7.0, Keycloak 26.5.7 -> 26.8.2). Build-hash verification follows. (2) DONE 2026-11-15 (operator: "a bug left from previous upgrade,
  fix it"): platform's chart defaults that infra overrides were behind production (Grafana 12.4.2, Mimir 2.17.8, Tempo
  2.7.2, Keycloak 26.5.6) - aligned with production (platform 9f967a16; production's render byte-identical), so no
  unit opens for versions nothing runs.
  (3) the labels themselves are seen only on the first real run (the local platform opens no PRs): the shadow week
  checks them.

## Decisions (operator, 2026-11-13)

- An agent runs the whole cycle: find the upgrades, prepare them as git changes, prove them on the Vagrant copy, apply
  them to production - **minors and majors, the node and the Pis included**.
- **Patches and minors apply directly** after a green proof, a notification after each.
- **Majors: a veto notice first** - what, the proof's results, when it applies - **24 h** to say no; applied if nothing
  is heard.
- Delivery through Argo CD: one infra and one platform branch per unit, as plan 119; what Argo cannot carry (node,
  Cilium, Argo CD itself, Gateway API CRDs, the Pis) through ops version vars and their `deploy:*` tasks.
- Vault needs no new access: each Pi unseals its own Vault already; `deploy:vault:upgrade` runs as by hand.

## Decisions (operator, 2026-11-15)

- **One task, started by hand, run locally - `task upgrade`** ("it should be started by hand by a single task with
  renovate, since they work in tandem, run locally"): Renovate on the workstation (docker, its image pinned, the
  shared preset, `renovate/allowed-commands.json`), then the runner. No systemd timer, no Woodpecker cron -
  `.woodpecker/renovate.yaml` and ops' `renovate` cron go. The copy runs on the workstation; the operator stops the
  radar for a run.
- **No shadow** ("no shadow mode, deploy once it works in vagrant tests"): rollout step 2 dropped - the task runs the
  runner for real: a unit proven on the copy and reviewed clean is applied (a major after its 24 h notice: one run gives
  the notice, a later one applies it). `--shadow` stays a flag of the script, never the task's default.
- **Kafka: the operator first** ("operator first!"): Strimzi's operator - one, shared by production's and the test
  environment's Kafka - a unit of its own, proven on the copy against production's Kafka; a Kafka version
  (`strimzi.kafkaVersion`, each environment's, annotated then) becomes a unit only once the operator supporting it is
  live - the test environment first, production after (4.3.2 needs Strimzi 1.3: test-first alone broke the test env).

## Parts

**1. Renovate CLI - finds the upgrades, opens the PRs** (chosen over Updatecli, Dependabot, Argo CD Image Updater,
Flux image automation, Keel, Kargo: the only one with native Forgejo, every version source here, and grouping;
comparison 2026-11-13). Runs on the workstation as `task upgrade`'s first half (docker, the image pinned exactly - a
Woodpecker cron until 2026-11-15), against
`schnappy/infra`, `schnappy/platform`, `schnappy/ops`; the existing `renovate-bot` account and secrets
(docs/renovate-setup.md). Shared preset:
- `automerge: false` (the cycle merges, not Renovate), `dependencyDashboardApproval: false`, `minimumReleaseAge: 3 days`,
  `separateMinorPatch: true`, `separateMajorMinor: true`; first-party images (`git.pmon.dev/*`) off.
- Units, as branch names shared across the repos (one `test:copy:change` per unit): `renovate/wave-patches`; minor
  groups `istio` (the three Argo apps + ops `istio_version` + Gateway API), `observability`, `data-operators` (Strimzi
  + Kafka, Scylla), `argocd`, `pi-services`; each major its own branch.
- Custom managers: annotated Ansible vars (`# renovate: datasource=... depName=...` above each version var - Cilium,
  cert-manager, chart versions, Kubernetes via registry.k8s.io, containerd.io via Docker's apt repo, Keycloak via
  quay, Caddy, Vault and Consul via Docker Hub, Gateway API and Helm via git tags, node_exporter via Docker Hub,
  Patroni via PyPI, Forgejo via forgejo-releases); CNPG `imageName: tag@sha256:digest`; a post-upgrade script
  (`scripts/renovate-checksums.py`, the only allowed command) that rewrites the pinned build hashes - part 4.
- Not seen by Renovate, covered beside it: Debian host packages (an `apt_info.py` node_exporter textfile collector on
  ten and the Pis + an alert, and an apt-upgrade playbook the cycle runs as a unit), the Pis' drift from their pins
  (`task test:copy:inventory`), `argocd_image_pins` (by hand), deprecated APIs before a Kubernetes minor (Pluto on the
  rendered charts, in CI).

**2. The upgrade runner - proves and applies** (on the workstation: the copy needs ~25 GB and libvirt; nowhere else).
`task upgrade`, started by the operator after Renovate's run (outside the backup windows - the runner's list, from the
real schedules: it refuses a run a window would meet, at its start and again before the merge), runs a deterministic
driver,
`scripts/upgrade-cycle.sh`; no CI agent on the
workstation (a Woodpecker agent there would give any pipeline a shell on it). Each run, one unit:
1. **Pick**: the next open Renovate unit in order - wave-patches, then minor groups, then one major whose 24 h notice
   has run out unvetoed. Paused when an `upgrades-paused` label is on ops' dashboard issue (the kill switch).
2. **Prove**: the copy lock; `test:copy:build` (from main = production), `test:copy:change` with the unit's infra and
   platform branches, `test:copy:playbook` for each ops part the unit moves (Kubernetes → upgrade-kubeadm.yml, a Pi
   service → its upgrade playbook, Cilium → its playbook, Argo CD → setup-argocd.yml, node_exporter →
   setup-host-hardening.yml; containerd not yet - refused); every check. Then the unit's diff gets a review (the
   review agent, its passes named). A shadow run's result goes on the PRs.
3. **Fix**: a failed proof calls the Claude agent (headless, a skill of its own) to diagnose and commit a fix in clones
   of the unit's branches; the runner checks and pushes it (labelled `stop-updating` so Renovate leaves them, and
   `agent-fixed`), then proves again - once. Still red: labelled `upgrade-blocked`, reported, the next unit next run.
   Green: reviewed, then a 24 h notice with the fix's diff - applied by a later run, unvetoed.
4. **Gate**: patches and minors go on. A major, or a unit carrying the agent's fix, gets its notice (the mail first,
   then the PR comment that starts the clock) and waits 24 h; a `veto` label stops it for good (read again right before
   the merge).
5. **Back up** before any one-way change (below), before the merge: today etcd before Kubernetes (its restore covered
   by production's own daily restore checks, not by the copy); the others blocked until theirs exist.
6. **Apply**: merge the infra/platform PRs (the bot through Forgejo's API, never an admin account), Argo syncs; the ops
   part merged and its PRODUCTION task run non-interactively (`task --yes deploy:...`), the Pis one at a time, the
   VIP's last.
7. **Verify** (`scripts/upgrade-verify.sh`): every Argo app Synced and Healthy within 30 min, every pod ready, then an
   hour with no critical alert (the cycle's own page aside). Red: paged, the cycle paused - never undone blind (a revert
   PR is the operator's; `check:production:data` and a Velero backup are not run by the cycle yet).
8. **Record**: the run committed to ops (`docs/upgrades/<date>-<unit>.md`, its paths alone) and sent as a
   notification; `task test:copy:inventory` read again so the next copy is built to the new production.

**3. One-way changes and their backups.** One-way: Kubernetes (kubeadm does not downgrade, patches included),
containerd, database majors and format changes (Postgres majors, ScyllaDB release lines, ClickHouse compatibility,
Kafka metadata, Strimzi CRD conversions), Vault/Consul majors (storage), Forgejo majors (migrations), Grafana majors.
Each takes its stores' backup first: Postgres (a CNPG base backup - `deploy:postgres:base-backup`), ScyllaDB (Scylla
Manager - `check:production:scylla-backup`), Kafka, ClickHouse, Grafana, OpenSearch (none in the cycle yet: plan 100's
Wave 0 backups - `upgrade-backup.yml` and its rehearsal, in git history before plan 117 - come back as the pre-change
backup, each store's restore proven on the copy), etcd (`task deploy:etcd:backup`, taken before a Kubernetes unit's
merge), the Pis (Consul snapshot, Forgejo's own pg_dump, Patroni's base backup - their upgrade playbooks take them).

**4. Build hashes, verified (operator 2026-11-15: "yes" - with option B's lookups).** A version Renovate moves takes
its pinned hashes with it, each read from what the vendor signs - never from the file it guards:
- **The writer**: Renovate's post-upgrade task, once a branch on every ops update (`scripts/renovate-checksums.py
  --changed`, the one command `renovate/allowed-commands.json` allows - `task upgrade` reads that file) rewrites the pins of each version the branch moved. The upgrade-fix skill moves a pin only with `--changed --base origin/main` on the unit's
  branch, never writing a hash itself.
- **The gates**: `scripts/copy-unit.sh`, before a unit's proof, checks the branch's moved pins against main's keys
  (`--check --changed --base main --ref renovate/<unit>`) and refuses a unit that changes the keys, the checker or the
  allowed command; ops CI (`build-hashes`, `scripts/ci-build-hashes.sh`) checks each pin a change moves - every pin
  when the checker or the keys change - on pull requests and pushes to main alike.
- **Signed by the vendor**, the signature checked by gpg in a keyring holding the vendor's key alone, its primary
  fingerprint pinned (`renovate/keys/keys.json`, each key file and fingerprint from the vendor's own page): HashiCorp's
  SHA256SUMS + `.sig` (Vault - C874 011F 0AB4 0511 0D02 1055 3436 5D94 72D7 468F); Helm's `.sha256sum` + its `.asc`
  (its KEYS, the expired key left out); Forgejo's `.xz` + `.xz.asc` (EB114F5E6C0DC2BCDD183550A4B61A2DC5923710) -
  decompressed as it is hashed, a third of the binary's download - its `.sha256` naming the binary and agreeing (a
  signature binds bytes, not a version: an older signed artifact under a new name is refused).
- **TLS alone** (the vendor signs nothing - each pin's comment says so): node_exporter's sha256sums.txt, Nexus's
  `.sha256`, versitygw's checksums.txt (a map per version: a new version adds its entry, every entry verified),
  PyTorch's cpu index (the wheels' `#sha256=`); a redirect off https refused. Caddy is built from source (xcaddy; Go's
  checksum database checks every module).
- **Keys age**: each run warns when a vendor's newest signing key expires within 60 days; `--refresh-keys` takes a
  vendor's key file again from its url only while every pinned primary is still in it (Forgejo's current signer, its
  2027-06-09 subkey; its 2027-01-10 subkey signs no release).
- **Moved by Renovate**: Vault, Forgejo, node_exporter (prom/node-exporter - copy-unit proves it with production's
  setup-host-hardening.yml); by hand, verified all the same: Helm (a task's var behind `creates:` - no host would
  take a new one, nothing proves it), Nexus (its download names are no registry's tags), versitygw (a set_fact's
  default), the PyTorch wheels (kept in step with target-scorer's requirements). scripts/pi-versions.py reads the
  copy's Vault and Forgejo pins through the same script.
Step 1 DONE 2026-11-15 (seven pins, every one ok against the vendors; harnesses `renovate-checksums` - each playbook
downloading the artifact the script hashes - `copy-unit`, `pi-versions`; full review and a simplify pass - their
findings fixed). Rollout: the first real Renovate run's Vault or Forgejo branch shows its
hashes rewritten and no artifact failure (postUpgradeTasks never run in lookup mode). Step 2, pins added where there
were none - Consul's zip (HashiCorp's signed SHA256SUMS), Keycloak's tarball (its `.asc`), Gateway API's manifest,
Patroni's requirements (`pip --require-hashes`) - each playbook's download `checksum:`-checked, proven on the copy. A
post-upgrade task runs with the bot's Forgejo token and the GitHub token in its environment: Patroni's hashes come from
PyPI's JSON digests, never `pip download` or `pip-compile` (an sdist's setup.py would run with them); Keycloak's
tarball is hashed, never unpacked.

## Guardrails

One unit per run, one production apply per day (the runner refuses a second); the copy lock (one copy run at a time); production touched only
through Taskfile tasks and merges by the bot; no force-sync of root, no prune; a run that cannot finish (the
workstation off, the copy not building) changes nothing in production and says so; the kill switch above.

## Rollout of this plan

1. Renovate in lookup mode (`RENOVATE_DRY_RUN=lookup`) until its log reproduces plan 119's tables.
2. ~~Renovate opening PRs; the runner proving them, applying nothing, a week (shadow).~~ The week dropped 2026-11-15:
   `task upgrade` - Renovate's branches and PRs, then one unit proven and applied - after one clean shadow proof
   (`task upgrade SHADOW=true`) that the cycle runs end to end.
3. Patches and minors applied automatically.
4. Majors with the 24 h notice; the pre-change backups proven first.
Each step reviewed before the next.

## The operator's review (answered 2026-11-14)

1. **Notifications: e-mail to one address - the single admin's, sent as Alertmanager sends** (operator: "just to single
   admin email", "like alertmanager does"): the runner posts each notice to Alertmanager's API as an alert of its own
   (`alertname=UpgradeCycle`, its kind and unit as labels, the text as annotations), and Alertmanager's existing route
   and e-mail receiver deliver it - one mail path, one address (`alertEmailTo`), its silences. Never a list, a user, a
   channel. One exception: a one-way change's failure may have broken the cluster Alertmanager runs in - that page
   falls back to the same sender (Alertmanager's SMTP settings) to the same address directly. Sent only for what is
   acted on or was asked for: a major's veto notice (24 h), a unit blocked (red after its fix) or a one-way change's
   failure (page, with its backup and restore steps), and - asked 2026-11-13 - each patch/minor applied. A night with
   no unit sends nothing (the no-unattended-mail rule: no scheduled noise).
2. **The agent: the current Claude account** - the same Claude Code login the operator's sessions use, headless on the
   workstation. **The fix step (part 2, step 3) is required**: a red proof is diagnosed and fixed, then proven again;
   only a second red blocks the unit. Its permissions are set for this job explicitly: in an interactive session the
   auto mode refused `deploy:kubeadm:upgrade` (2026-11-14) - the runner runs the production tasks and the bot's merges
   itself; the agents' own settings (.claude/upgrade-agent/) deny every task, push and host.
3. **The workstation runs it; the operator stops the radar for it** ("I will stop radar again"): the copy needs ~24.6 GB
   of the 30 GB (VMs 22.5 GB + the guard's 2 GB start reserve), and on 2026-11-14 it fit only with radar-live.service
   stopped. The runner cannot stop it (a system unit, sudo asks a password): a run started with the radar up is refused
   at once (2026-11-15: started by hand - the operator is there; no wait, no mail), and the copy is destroyed as soon as
   the review is done - the radar may start while the apply goes on. (A polkit rule
   letting the runner stop and start radar-live itself would remove the step - the operator's call, not assumed.)
4. **No batches: one unit a run, one apply a day** (a wave can take a week).

## What wave 1 by hand taught the cycle (2026-11-14)

- A change to the test namespace cannot be proven on the copy (its mirror refuses what the overlay drops): the cycle
  splits it onto a branch of its own, merged first - the test environment its own proof (plan 100's order) - then the
  production unit.
- The Pis' Debian unit runs `deploy:pi-packages:upgrade -- -e pi_packages_turns=1` one night (the Pi without the VIP,
  its new kernel and bootloader soaking) and the second Pi the next; a preview (`-- --check`, fresh lists) goes in the
  proof's record.
- After each apply: `task test:copy:inventory` and the ops defaults that restate production (defaults-follow-production:
  cert_manager_version, k8s_package_version, cilium_version, ...) moved in the same ops commit - by hand on 2026-11-14,
  the next build's own inventory check failed otherwise.
- Before a Kubernetes apply, a fresh etcd snapshot (a Job from the etcd-backup CronJob) - upgrade-kubeadm takes none.
- The full review found real defects after a green copy run (Nexus double start, a failed run's reboot skipped): the
  review stays a gate, and its fixes are proven on the copy again before the apply.
