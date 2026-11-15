#!/bin/bash
# .claude/upgrade-agent/{fix,review}.json - the upgrade cycle's headless agents' own settings (scripts/upgrade-cycle.sh
# runs the fix --restricted with fix.json, the review with review.json; anything they do not allow denied, never asked).
# Read as Claude Code reads them (proven with its CLI 2.1.308 on 2026-11-15: a push, a branch move, kubectl, vagrant and
# a read of the git credentials denied; a commit in a clone allowed): the Bash sandbox on and failing closed, nothing
# auto-allowed, the credentials unreadable to Bash, no network but the checksum script's vendors (the review none); the
# denials every job keeps (production, other hosts, the network, the operator's credentials, a branch or a push); no
# allow that grants one of them; no whole-tool Read or Edit (a file tool outside the clones); the skill's own commands
# allowed word for word, its "never" denied.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
python3 - <<'PYCHECK'
import fnmatch, json, re, sys
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
fix = json.load(open(".claude/upgrade-agent/fix.json"))
review = json.load(open(".claude/upgrade-agent/review.json"))
CREDS = {"~/.git-credentials", "~/.kube", "~/.ssh", "~/.claude/.credentials.json", "~/.config", "~/.netrc", "~/.docker",
         "/home/sm/src/ops/.env", "/home/sm/src/ops/deploy/ansible/vars/sealed-secrets-key-backup.yaml"}
for name, d in (("fix", fix), ("review", review)):
    sb = d.get("sandbox", {})
    check(f"{name}: the Bash sandbox on, failing closed (never unsandboxed, never auto-allowed), the credentials "
          "unreadable to Bash",
          (sb.get("enabled"), sb.get("failIfUnavailable"), sb.get("allowUnsandboxedCommands"), sb.get("autoAllowBashIfSandboxed"),
           sorted(CREDS - set(sb.get("filesystem", {}).get("denyRead", []))), sb.get("excludedCommands")),
          (True, True, False, False, [], []))
check("fix: Bash's network the checksum script's vendors alone; the review's none",
      (sorted(fix["sandbox"]["network"]["allowedDomains"]), review["sandbox"]["network"]["allowedDomains"]),
      (sorted(["code.forgejo.org", "download.pytorch.org", "download.sonatype.com", "get.helm.sh", "github.com",
               "objects.githubusercontent.com", "release-assets.githubusercontent.com", "releases.hashicorp.com"]), []))
# what every job denies: production, other hosts, the network, the operator's credentials, a branch, a push
MUST_DENY = ["Bash(task *)", "Bash(ssh *)", "Bash(scp *)", "Bash(curl *)", "Bash(wget *)", "Bash(kubectl *)", "Bash(helm *)",
             "Bash(ansible*)", "Bash(sudo *)", "Bash(docker *)", "Bash(git push*)", "Bash(git -C * push*)",
             "Bash(git branch*)", "Bash(git checkout*)", "Bash(git switch*)", "Bash(git remote*)", "Bash(git config*)",
             "Bash(git fetch*)", "Bash(git reset*)", "Bash(git *--no-index*)", "Bash(git *-c *)", "Bash(vagrant *)",
             "Read(~/.git-credentials)", "Read(~/.kube/**)", "Read(~/.ssh/**)", "Read(~/.claude/.credentials.json)",
             "Read(//home/sm/src/ops/.env)", "WebSearch"]
for name, d in (("fix", fix), ("review", review)):
    deny = d["permissions"]["deny"]
    check(f"{name}: every job's denials kept", [r for r in MUST_DENY if r not in deny], [])
    allow = d["permissions"]["allow"]
    # an allow that would grant what is denied (deny wins in Claude Code - an allow of it is a mistake in waiting)
    probes = ["git push", "git push origin main", "task --yes deploy:argocd", "ssh ten true", "kubectl get secret -A",
              "curl https://evil", "vagrant ssh pi1", "git branch -m main", "git checkout main", "cat ~/.git-credentials"]
    granted = [p for p in probes for r in allow if r.startswith("Bash(") and fnmatch.fnmatchcase(p, r[5:-1])]
    check(f"{name}: no allow grants a push, a deploy, ssh, kubectl, curl, vagrant, a branch move or a credential read",
          granted, [])
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
sys.exit(1 if fails else 0)
PYCHECK
rc=$?
[ "$rc" = 0 ] && echo "upgrade-agent-settings: ALL-PASS" || echo "upgrade-agent-settings: FAILED"
exit "$rc"
