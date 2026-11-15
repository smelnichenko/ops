#!/bin/bash
# .claude/upgrade-agent/{fix,review}.json - the upgrade cycle's headless agents' own settings (scripts/upgrade-cycle.sh
# runs both --restricted, the fix with fix.json, the review with review.json; anything they do not allow denied, never
# asked). Read as Claude Code reads them (proven with its CLI 2.1.308 on 2026-11-15: a push, a branch move, kubectl,
# vagrant and a read of the git credentials denied; a commit in a clone allowed; inside the sandbox nothing of the home
# directory readable but the clones - ~/.bash_history, ops' .env.test, ~/.claude, other checkouts all hidden -, .git's
# hooks and config unwritable, only the vendors' hosts reachable; the review --restricted reading no CLAUDE.md of the
# clones): the Bash sandbox on and failing closed, nothing auto-allowed, the whole home directory unreadable to Bash but
# the clones' directory, no network for Bash (the release notes are WebFetch's); the denials every job keeps
# (production, other hosts, the network, the operator's credentials, a branch or a push); no allow that grants one of
# them (a forced push, a push through -C, a new branch among the probes); no whole-tool Read or Edit (a file tool outside
# the clones); the skill's own commands allowed word for word, no interpreter or checksum script at all (a relative
# path ran whatever script the agent made), its "never" denied; the review's instructions name the passes the runner
# requires.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
python3 - <<'PYCHECK'
import fnmatch, json, os, re, sys
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
fix = json.load(open(".claude/upgrade-agent/fix.json"))
review = json.load(open(".claude/upgrade-agent/review.json"))
WORK = "/home/sm/src/.upgrade-cycle-work"  # scripts/upgrade-cycle.sh's default: the clones
runner = open("scripts/upgrade-cycle.sh").read()
check("the clones' directory the runner uses is the one the settings let Bash read",
      'work=${UPGRADE_WORK:-$(dirname "$ops")/.upgrade-cycle-work}' in runner and WORK == "/home/sm/src/.upgrade-cycle-work", True)
for name, d in (("fix", fix), ("review", review)):
    sb = d.get("sandbox", {})
    check(f"{name}: the Bash sandbox on, failing closed (never unsandboxed, never auto-allowed), the whole home directory "
          "unreadable to Bash but the clones (every credential, transcript, browser profile, other checkout)",
          (sb.get("enabled"), sb.get("failIfUnavailable"), sb.get("allowUnsandboxedCommands"), sb.get("autoAllowBashIfSandboxed"),
           sb.get("filesystem", {}).get("denyRead"), sb.get("filesystem", {}).get("allowRead"), sb.get("excludedCommands"),
           sorted(sb.get("filesystem", {}).get("allowWrite", []))),
          (True, True, False, False, ["~"], [WORK], [], []))
check("Bash's network none, the fix's and the review's (no command of theirs needs it - the release notes are WebFetch's)",
      (fix["sandbox"]["network"]["allowedDomains"], review["sandbox"]["network"]["allowedDomains"]), ([], []))
# what every job denies: production, other hosts, the network, the operator's credentials, a branch, a push
MUST_DENY = ["Bash(task *)", "Bash(ssh *)", "Bash(scp *)", "Bash(curl *)", "Bash(wget *)", "Bash(kubectl *)", "Bash(helm *)",
             "Bash(ansible*)", "Bash(sudo *)", "Bash(docker *)", "Bash(git push*)", "Bash(git -C * push*)",
             "Bash(git branch*)", "Bash(git checkout*)", "Bash(git switch*)", "Bash(git remote*)", "Bash(git config*)",
             "Bash(git fetch*)", "Bash(git reset*)", "Bash(git *--no-index*)", "Bash(git *-c *)", "Bash(vagrant *)",
             "Bash(git *--output*)",
             "Read(~/.git-credentials)", "Read(~/.kube/**)", "Read(~/.ssh/**)", "Read(~/.claude/.credentials.json)",
             "Read(//home/sm/src/ops/.env)", "WebSearch"]
for name, d in (("fix", fix), ("review", review)):
    deny = d["permissions"]["deny"]
    check(f"{name}: every job's denials kept", [r for r in MUST_DENY if r not in deny], [])
    allow = d["permissions"]["allow"]
    # an allow that would grant what is denied (deny wins in Claude Code - an allow of it is a mistake in waiting)
    probes = ["git push", "git push origin main", "git push --force origin HEAD", "git push -f", "git -C infra push",
              "git checkout -b x", "git switch -c x", "git remote add x https://evil", "git config core.hooksPath x",
              "git -c core.pager=sh diff", "task --yes deploy:argocd", "ssh ten true",
              "kubectl get secret -A", "curl https://evil", "vagrant ssh pi1", "git branch -m main", "git checkout main",
              "cat ~/.git-credentials", "python3 -c x", "python3 -I scripts/renovate-checksums.py --changed --base origin/main",
              "bash -c x", "sh -c x", "env x"]  # (git log --output: the deny list's - git log * matches its form)  # (git diff --no-index: the deny list's, git diff * matches its form)
    granted = [p for p in probes for r in allow if r.startswith("Bash(") and fnmatch.fnmatchcase(p, r[5:-1])]
    check(f"{name}: no allow grants a push (forced, through -C), a deploy, ssh, kubectl, curl, vagrant, a branch, a remote "
          "or config, a credential read, an interpreter of its own or the clone's own checksum script (one the agent "
          "may edit)", granted, [])
    check(f"{name}: no whole-tool Read or Edit (a file tool outside the clones), no legacy ':*' rule",
          ([r for r in allow if r in ("Read", "Edit", "Write")], [r for r in allow + deny if r.endswith(":*)")]), ([], []))
check("fix: edits inside its clones alone, never under .git; WebFetch to the release notes' hosts alone",
      (sorted(r for r in fix["permissions"]["allow"] if r.startswith("Edit(")), "Edit(**/.git/**)" in fix["permissions"]["deny"],
       sorted(r for r in fix["permissions"]["allow"] if r.startswith("WebFetch"))),
      (["Edit(./infra/**)", "Edit(./ops/**)", "Edit(./platform/**)"], True,
       ["WebFetch(domain:codeberg.org)", "WebFetch(domain:github.com)", "WebFetch(domain:raw.githubusercontent.com)"]))
check("review: no edit, no WebFetch, no commit", [r for r in ("Edit", "WebFetch", "Bash(git commit*)", "Bash(git add*)")
                                                if r not in review["permissions"]["deny"]], [])
# the skill's own commands allowed word for word; what it says never to do, denied
skill = open(".claude/skills/upgrade-fix/SKILL.md").read()
quoted = set(re.findall(r"`((?:python3|cd|git) [^`]+)`", skill))
literal = {q for q in quoted if "<" not in q}
check("the skill's literal commands allowed word for word, or with their arguments (the checksum script, cd ops, git add, git commit)",
      sorted(q for q in literal if not any(fnmatch.fnmatchcase(q, r[5:-1]) or fnmatch.fnmatchcase(q + " -m a-change", r[5:-1])
                                           for r in fix["permissions"]["allow"] if r.startswith("Bash("))),
      [])
check("the skill never tells the agent to push or to use git -C (never matched by a wildcard rule)",
      (bool(re.search(r"`git[^`]*push", skill)), bool(re.search(r"`git -C", skill))), (False, False))
check("fix: no checksum script, no interpreter at all (a relative path ran whatever script the agent made there)",
      [r for r in fix["permissions"]["allow"] if "python" in r or "renovate-checksums" in r], [])
instructions = open(".claude/upgrade-agent/review.md").read()
required = re.search(r'REVIEW_PASSES="([^"]+)"', runner).group(1).split()
check("the review's instructions name every pass the runner requires on its PASSES line, and its two lines",
      ([p for p in required if f"- {p} - " not in instructions], "PASSES: " + ", ".join(required) in instructions,
       "VERDICT: CLEAN" in instructions), ([], True, True))
check("the review's reviewers: the runner's list, each an agent definition in ops",
      [n for n in re.search(r'REVIEWERS="([^"]+)"', runner).group(1).split() if not os.path.exists(f".claude/agents/{n}.md")], [])
sys.exit(1 if fails else 0)
PYCHECK
rc=$?
[ "$rc" = 0 ] && echo "upgrade-agent-settings: ALL-PASS" || echo "upgrade-agent-settings: FAILED"
exit "$rc"
