#!/bin/bash
# scripts/upgrade-notice.sh - the upgrade cycle's notices, posted to Alertmanager as UpgradeCycle alerts: ssh stubbed
# (it runs the remote command against a kubectl stub that records every argument), so what reaches amtool is checked
# as amtool would get it - each kind's severity and lifetime, the summary and the details whole through ssh's quoting
# (spaces, quotes, $, newlines), the details cut at 3000 bytes; Alertmanager unreachable: a one-way failure goes
# straight out (a dry run says so; no key - not sent, said), any other kind fails; refused: a kind, a unit, no summary.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin"
cat > "$W/bin/ssh" <<'STUB'
#!/bin/bash
[ ! -e "$W/ssh.fail" ] || exit 255
host=""; while [ $# -gt 0 ]; do case "$1" in -o) shift 2 ;; -*) shift ;; *) host=$1; shift; break ;; esac; done
echo "$host" > "$W/ssh.host"
PATH="$W/bin:$PATH" bash -c "$*"
STUB
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/bash
: > "$W/argv"; for a in "$@"; do printf '%s\0' "$a" >> "$W/argv"; done
STUB
chmod +x "$W/bin"/*
W=$W python3 - <<'PYCHECK'
import datetime, os, subprocess, sys
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
ENV = {**os.environ, "PATH": os.path.join(W, "bin") + ":" + os.environ["PATH"], "W": W}
ENV.pop("UPGRADE_NOTICE_DRY", None); ENV.pop("RESEND_API_KEY", None)
def run(*args, **env):
    for f in ("argv", "ssh.host"):
        if os.path.exists(os.path.join(W, f)):
            os.remove(os.path.join(W, f))
    r = subprocess.run(["bash", "scripts/upgrade-notice.sh", *args], capture_output=True, text=True, env={**ENV, **env})
    argv = open(os.path.join(W, "argv")).read().split("\0")[:-1] if os.path.exists(os.path.join(W, "argv")) else []
    return r.returncode, r.stdout, argv
def arg(argv, prefix):
    return next((a[len(prefix):] for a in argv if a.startswith(prefix)), None)
def hours_left(argv):
    end = datetime.datetime.strptime(arg(argv, "--end="), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    return round((end - datetime.datetime.now(datetime.timezone.utc)).total_seconds() / 3600)
details = os.path.join(W, "details.txt")
TEXT = "proof: green\nit's \"quoted\", $HOME stays $HOME, `no` command\n  indented line"
open(details, "w").write(TEXT)
SUMMARY = "wave patches applied: cert-manager v1.21.3 & 8 more ($5 \"worth\")"
rc, out, argv = run("applied", "wave-patches", SUMMARY, details)
check("applied: posted through ten, Alertmanager's pod, amtool alert add",
      (rc, open(os.path.join(W, "ssh.host")).read().strip(), argv[:8]),
      (0, "ten", ["-n", "schnappy-infra", "exec", "deploy/schnappy-alertmanager", "-c", "alertmanager", "--", "amtool"]))
check("applied: its labels - UpgradeCycle, the kind, the unit, info",
      [a for a in argv if "=" in a and not a.startswith("--")],
      ["alertname=UpgradeCycle", "kind=applied", "unit=wave-patches", "severity=info"])
check("the summary whole through ssh's quoting", arg(argv, "--annotation=summary="), SUMMARY)
check("the details whole (quotes, $, backticks, newlines)", arg(argv, "--annotation=description="), TEXT)
check("applied lasts an hour; Alertmanager on its own pod's port", (hours_left(argv), arg(argv, "--alertmanager.url=")),
      (1, "http://localhost:9093"))
rc, out, argv = run("veto", "postgres-19", "PostgreSQL 19 applies in 24 h unless vetoed")
check("veto: warning, lasts the 24 h notice", (rc, arg(argv, "severity="), hours_left(argv)), (0, "warning", 24))
rc, out, argv = run("blocked", "istio", "red after its fix")
check("blocked: warning, an hour", (rc, arg(argv, "severity="), hours_left(argv)), (0, "warning", 1))
rc, out, argv = run("one-way-failed", "scylla-2026.3", "the upgrade failed, restore steps inside")
check("one-way-failed: critical, a week (the critical route repeats it until resolved)",
      (rc, arg(argv, "severity="), hours_left(argv)), (0, "critical", 168))
open(details, "w").write("x" * 5000)
rc, out, argv = run("applied", "u", "s", details)
check("the details cut at 3000 bytes", len(arg(argv, "--annotation=description=")), 3000)
open(os.path.join(W, "ssh.fail"), "w").write("")
rc, out, argv = run("one-way-failed", "u", "s", UPGRADE_NOTICE_DRY="1")
check("dry run: what would be posted said, nothing sent", (rc, out.startswith("DRY: ssh ten kubectl"), argv), (0, True, []))
rc, out, argv = run("one-way-failed", "u", "s")
check("Alertmanager unreachable, a one-way failure: straight out - no key, not sent, said (exit 1)",
      (rc, "not reached" in out, "NOT SENT: no RESEND_API_KEY" in out), (1, True, True))
values = os.path.join(W, "values.yaml")
open(values, "w").write("alertmanager:\n  enabled: true\n")
rc, out, argv = run("one-way-failed", "u", "s", RESEND_API_KEY="k", UPGRADE_NOTICE_INFRA_VALUES=values)
check("a one-way failure with no admin address to mail: not sent, said (exit 1) - no mail to a guess",
      (rc, "NOT SENT: no admin address" in out), (1, True))
rc, out, argv = run("one-way-failed", "u", "s", RESEND_API_KEY="k", UPGRADE_NOTICE_INFRA_VALUES=os.path.join(W, "none.yaml"))
check("the values file not there (no infra beside ops): not sent, said", (rc, "NOT SENT: no admin address" in out), (1, True))
rc, out, argv = run("blocked", "u", "s")
check("Alertmanager unreachable, any other kind: failed, no direct mail", (rc, "MAILED" in out or "NOT SENT" in out), (1, False))
os.remove(os.path.join(W, "ssh.fail"))
for args, what in ((("noticed", "u", "s"), "a kind it does not know"), (("applied", "Bad/Unit", "s"), "no unit's name"),
                   (("applied", "u", ""), "no summary"), (("applied", "u", "s", "/nope"), "a details file not readable")):
    rc, out, argv = run(*args)
    check(f"refused: {what}", (rc, out.startswith("REFUSED"), argv), (2, True, []))
print("upgrade-notice: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
