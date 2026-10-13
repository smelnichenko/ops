#!/usr/bin/env python3
"""upgrade-rules.py - what judges an upgrade step proven and green, read by the rollout's controller
(scripts/upgrade-production.py) and the full run: the proof's paths, Argo's settle, the check's window, the
environments left out, what may land on main unproven. Proven itself (in PROVEN_PATHS): the controller, left out of the
proof so its own fixes ship during a rollout, cannot change these unproven."""

# production's test environment: not in the Vagrant copy, moved apart from production by its own steps - its images
# are listed, not compared
TEST_NAMESPACES = "schnappy-test"
# Argo's settle after a merge, a step's settle line aside: longer than the longest hook a merge can start and its
# rollout - init-users (schnappy-data's Sync hook) may take its whole deadline in a major's restarts: 2095 s (~35 min)
# with production's 5 databases (platform cnpg-init-users.yaml, derived from them); 30 min called a hook still within
# its bound failed (the reviews, 2026-10-12)
SETTLE_MINUTES = 40
# production's settle: green held SETTLE_STABLE polls SETTLE_POLL s apart, no container restarted in the last
# SETTLE_QUIET s (CrashLoopBackOff's longest back-off) - the full run's final settle takes the same (settle-values)
SETTLE_POLL, SETTLE_STABLE, SETTLE_QUIET = 10, 4, 300
# preview environments come and go (an Argo app per pull request): never part of the app set a step must keep
PREVIEW_APPS = r"^pr-\d+-"
PREVIEW_NAMESPACES = r"^schnappy-pr-\d+$"  # ...and their pods
# the proof's paths (git pathspecs): what a full run proves and production's phases then want unchanged. Two parts
# are left out: the unit tests (they test the scripts; no step runs them) and the rollout's controller
# (scripts/upgrade-production.py: its ledger, soak, prompts and phase order run on production only - every phase
# refuses while it differs from ops main, and its unit tests hold it). This file is proven: what judges a step proven
# and green does not change unproven.
PROVEN_PATHS = ("deploy", "scripts", "tests", ":(exclude)tests/ansible/unit", ":(exclude)scripts/upgrade-production.py",
                "Taskfile.yml", "Vagrantfile")
# what may land on infra's or platform's main after a full run without it proving it again: what renders nothing for
# production - CD's deploys of the test environment, CI's own files, docs, a chart's unit tests (a merged step's own
# commits aside)
MAIN_UNRENDERED = (r"^clusters/production/schnappy-test-apps/values\.yaml$", r"^\.woodpecker/", r"\.md$",
                   r"^helm/[^/]+/tests/")
# a check's own settle: how long a begin or done waits for Argo to hold green
CHECK_MINUTES = 15
