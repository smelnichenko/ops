#!/bin/bash
# scripts/upgrade-notice.sh - the upgrade cycle's notices, posted to Alertmanager's API as UpgradeCycle alerts (JSON on
# stdin through ssh; the same post was proven against Alertmanager v0.34.1 itself, 2026-11-15): ssh stubbed, recording
# its host, the remote command and what it was given - each kind's severity and lifetime from now, a label of each
# notice's own, the summary and the details whole (quotes, $, backticks, newlines - amtool refused a '"'), the details'
# last 3000 bytes (one cut inside a character: replaced); a one-way failure a page: recorded, mailed straight out too
# (no key - said), resolved (ended now, its record gone), posted again with a week's end; a veto mailed straight out
# too; the direct mail as notice.sh hands it over (a copy beside a recording mail script) and upgrade-mail.py's main()
# with its SMTP replaced - each way it fails said; Alertmanager unreachable: a notice fails, a page's record stays, a
# page or veto mailed is through; refused: a kind, a unit, no summary, a resolve without a page, usages it lacks.
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
printf '%s' "$*" > "$W/ssh.cmd"
cat >> "$W/posts"
echo >> "$W/posts"
STUB
chmod +x "$W/bin"/*
W=$W python3 - <<'PYCHECK'
import datetime, json, os, re, shutil, subprocess, sys
W = os.environ["W"]
PAGES = os.path.join(W, "pages")
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
ENV = {**os.environ, "PATH": os.path.join(W, "bin") + ":" + os.environ["PATH"], "W": W, "UPGRADE_PAGES": PAGES}
ENV.pop("UPGRADE_NOTICE_DRY", None); ENV.pop("RESEND_API_KEY", None)
def run(*args, **env):
    for f in ("posts", "ssh.host", "ssh.cmd"):
        if os.path.exists(os.path.join(W, f)):
            os.remove(os.path.join(W, f))
    r = subprocess.run(["bash", "scripts/upgrade-notice.sh", *args], capture_output=True, text=True, env={**ENV, **env})
    p = os.path.join(W, "posts")
    posts = [json.loads(x) for x in open(p).read().split("\n") if x.strip()] if os.path.exists(p) else []
    return r.returncode, r.stdout, posts
def at(s):
    return datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
def hours_from_now(s):
    return round((at(s) - datetime.datetime.now(datetime.timezone.utc)).total_seconds() / 3600)
REMOTE = ("kubectl -n schnappy-infra exec -i deploy/schnappy-alertmanager -c alertmanager -- wget -T 20 -qO- --header "
          "'Content-Type: application/json' --post-file=/dev/stdin http://localhost:9093/api/v2/alerts")
details = os.path.join(W, "details.txt")
TEXT = "proof: green\nit's \"quoted\", $HOME stays $HOME, `no` command\n  indented line"
open(details, "w").write(TEXT)
SUMMARY = "wave patches applied: cert-manager v1.21.3 & 8 more ($5 \"worth\")"
rc, out, posts = run("applied", "wave-patches", SUMMARY, details)
a = posts[0][0] if posts else {}
check("applied: one alert posted through ten to Alertmanager's API (its pod's wget, the JSON on stdin)",
      (rc, len(posts), open(os.path.join(W, "ssh.host")).read().strip(), open(os.path.join(W, "ssh.cmd")).read()),
      (0, 1, "ten", REMOTE))
check("applied: its labels - UpgradeCycle, the kind, the unit, info, a notice of its own",
      ({k: v for k, v in a.get("labels", {}).items() if k != "notice"}, bool(re.fullmatch(r"\d{8}T\d{6}Z-\d+", a.get("labels", {}).get("notice", "")))),
      ({"alertname": "UpgradeCycle", "kind": "applied", "unit": "wave-patches", "severity": "info"}, True))
check("the summary and the details whole (quotes, $, backticks, newlines)",
      (a.get("annotations", {}).get("summary"), a.get("annotations", {}).get("description")), (SUMMARY, TEXT))
check("it starts now and lasts an hour (no start sent, the mail said it started at its end)",
      (hours_from_now(a["startsAt"]), hours_from_now(a["endsAt"])), (0, 1))
rc2, _, posts2 = run("applied", "wave-patches", SUMMARY, details)
check("a second notice of a kind for a unit: a notice label of its own (one label set the same was deduplicated)",
      posts2[0][0]["labels"]["notice"] != a["labels"]["notice"], True)
rc, out, posts = run("veto", "postgres-19", "PostgreSQL 19 applies in 24 h unless vetoed")
check("veto: warning, lasts the 24 h notice - posted, but no direct mail (no key): not sent (exit 1 - no clock without "
      "the mail that carries its evidence whole)", (rc, posts[0][0]["labels"]["severity"], hours_from_now(posts[0][0]["endsAt"]),
      "NOT SENT: no RESEND_API_KEY" in out), (1, "warning", 24, True))
rc, out, posts = run("blocked", "istio", "red after its fix")
check("blocked: warning, an hour, no page recorded", (rc, posts[0][0]["labels"]["severity"], hours_from_now(posts[0][0]["endsAt"]),
                                                     os.path.exists(PAGES)), (0, "warning", 1, False))
open(details, "w").write("head-" + "x" * 5000 + "-the failure")
rc, out, posts = run("applied", "u", "s", details)
d = posts[0][0]["annotations"]["description"]
check("the details' last 3000 bytes (a log's end is where it failed)", (len(d), d.endswith("-the failure"), "head-" in d),
      (3000, True, False))
values = os.path.join(W, "values.yaml")
open(values, "w").write("alertmanager:\n  enabled: true\n  alertEmailTo: admin@example.org\n")
rc, out, posts = run("one-way-failed", "scylla-2026.3", "the upgrade failed, restore steps inside", UPGRADE_NOTICE_INFRA_VALUES=values)
page = os.path.join(PAGES, "scylla-2026.3.json")
rec = json.load(open(page)) if os.path.exists(page) else [{}]
check("one-way-failed: a page - critical, a week, posted, recorded as posted; mailed straight out too (no key: said)",
      (rc, posts[0][0]["labels"]["severity"], hours_from_now(posts[0][0]["endsAt"]), rec[0].get("labels") == posts[0][0]["labels"],
       "POSTED" in out, "NOT SENT: no RESEND_API_KEY" in out),
      (0, "critical", 168, True, True, True))
rc, out, _ = run("open")
check("open: the open pages' units", (rc, out.split()), (0, ["scylla-2026.3"]))
aged = json.load(open(page)); aged[0]["endsAt"] = "2026-01-01T00:00:00Z"; json.dump(aged, open(page, "w"))
rc, out, posts = run("repost")
check("repost: every open page posted again, the same labels, its end a week from now - the record too (aged first)",
      (rc, len(posts), posts[0][0]["labels"] == rec[0]["labels"], hours_from_now(posts[0][0]["endsAt"]),
       json.load(open(page))[0]["endsAt"] == posts[0][0]["endsAt"]), (0, 1, True, 168, True))
open(os.path.join(W, "ssh.fail"), "w").write("")
rc, out, posts = run("repost")
check("repost, Alertmanager unreachable: said, exit 1, the record kept", (rc, "NOT REPOSTED" in out, os.path.exists(page)),
      (1, True, True))
rc, out, posts = run("resolve", "scylla-2026.3")
check("resolve, Alertmanager unreachable: not resolved, the record kept (exit 1)", (rc, os.path.exists(page)), (1, True))
os.remove(os.path.join(W, "ssh.fail"))
rc, out, posts = run("resolve", "scylla-2026.3")
check("resolve: the page's own labels ended now, its record gone",
      (rc, posts[0][0]["labels"] == rec[0]["labels"], hours_from_now(posts[0][0]["endsAt"]), os.path.exists(page),
       run("open")[1].strip()), (0, True, 0, False, ""))
check("resolve without an open page: refused", run("resolve", "scylla-2026.3")[0], 1)
open(os.path.join(W, "ssh.fail"), "w").write("")
rc, out, posts = run("blocked", "istio", "s")
check("Alertmanager unreachable, a notice: not posted, said (exit 1)", (rc, "NOT POSTED" in out), (1, True))
rc, out, posts = run("one-way-failed", "u1", "s", UPGRADE_NOTICE_INFRA_VALUES=values)
check("Alertmanager unreachable, a page, no key for the direct mail: neither went (exit 1) - its record written all the "
      "same (the runner refuses while it is open)",
      (rc, "not reached" in out, "NOT SENT: no RESEND_API_KEY" in out, os.path.exists(os.path.join(PAGES, "u1.json"))),
      (1, True, True, True))
open(values, "w").write("alertmanager:\n  enabled: true\n")
rc, out, posts = run("one-way-failed", "u2", "s", RESEND_API_KEY="k", UPGRADE_NOTICE_INFRA_VALUES=values)
check("a page with no admin address to mail: not sent, said - no mail to a guess",
      (rc, "NOT SENT: no admin address" in out), (1, True))
os.remove(os.path.join(W, "ssh.fail"))
rc, out, posts = run("one-way-failed", "u3", "s", UPGRADE_NOTICE_DRY="1")
check("dry run: what would be posted and mailed said, nothing sent or recorded",
      (rc, "DRY: ssh ten kubectl" in out, "would mail" in out, posts, os.path.exists(os.path.join(PAGES, "u3.json"))),
      (0, True, True, [], False))
# the direct mail as it goes out - scripts/upgrade-mail.py against an SMTP that records, never the network
probe = subprocess.run([sys.executable, "-I", "-c", r"""
import json, sys
sys.path.insert(0, "scripts")
import importlib.util
spec = importlib.util.spec_from_file_location("um", "scripts/upgrade-mail.py"); um = importlib.util.module_from_spec(spec)
spec.loader.exec_module(um)
calls = []
class S:
    def __init__(self, host, port, timeout): calls.append(["connect", host, port, timeout])
    def __enter__(self): return self
    def __exit__(self, *a): calls.append(["quit"])
    def starttls(self, context): calls.append(["starttls", context is not None])
    def login(self, user, key): calls.append(["login", user, key])
    def send_message(self, m): calls.append(["send", m["From"], m["To"], m["Subject"], m.get_content()])
um.send("admin@example.org", "[UpgradeCycle] one-way-failed: k - it broke", "it broke\n\nrestore steps", "the-key", smtp=S)
print(json.dumps(calls))
"""], capture_output=True, text=True)
check("the direct mail: Resend's SMTP on 587, STARTTLS before the login (user resend, the key), from alerts@pmon.dev "
      "to the admin, the subject and body whole",
      json.loads(probe.stdout or "[]"),
      [["connect", "smtp.resend.com", 587, 30], ["starttls", True], ["login", "resend", "the-key"],
       ["send", "alerts@pmon.dev", "admin@example.org", "[UpgradeCycle] one-way-failed: k - it broke", "it broke\n\nrestore steps\n"],
       ["quit"]])
r = subprocess.run([sys.executable, "-I", "scripts/upgrade-mail.py"], capture_output=True, text=True,
                   env={"PATH": os.environ["PATH"], "TO": "a@b.c", "SUBJECT": "s", "BODY": "b"})
check("the direct mail without its key: not sent, said (exit 1)", (r.returncode, "NOT SENT" in r.stdout), (1, True))
# the direct mail's main() as the page calls it: Resend's SMTP replaced (smtplib.SMTP), each way it fails said (exit 1),
# a body whose end was cut inside a character mailed all the same
def mail_main(env, smtp_class):
    code = r"""
import importlib.util, json, os, smtplib, sys
spec = importlib.util.spec_from_file_location("um", "scripts/upgrade-mail.py"); um = importlib.util.module_from_spec(spec)
spec.loader.exec_module(um)
sent = []
class Ok:
    def __init__(self, *a, **k): pass
    def __enter__(self): return self
    def __exit__(self, *a): pass
    def starttls(self, context): pass
    def login(self, u, k): pass
    def send_message(self, m): sent.append([m["Subject"], m.get_content()])
class AuthFails(Ok):
    def login(self, u, k): raise smtplib.SMTPAuthenticationError(535, b"bad key")
class Refused(Ok):
    def __init__(self, *a, **k): raise ConnectionRefusedError("refused")
class Odd(Ok):
    def send_message(self, m): raise ValueError("something else")
smtplib.SMTP = {"ok": Ok, "auth": AuthFails, "refused": Refused, "odd": Odd}[sys.argv[1]]
rc = um.main()
print(json.dumps({"rc": rc, "sent": sent}))
"""
    r = subprocess.run([sys.executable, "-I", "-c", code, smtp_class], capture_output=True, env={"PATH": os.environ["PATH"], **env})
    lines = r.stdout.decode("utf-8", "replace").strip().split("\n")
    return lines[:-1], (json.loads(lines[-1]) if lines and lines[-1].startswith("{") else {"rc": None, "err": r.stderr[-300:]})
MAILENV = {"TO": "a@b.c", "SUBJECT": "[UpgradeCycle] one-way-failed: u - s", "BODY": "s\n\nthe log", "RESEND_API_KEY": "k"}
said, res = mail_main(MAILENV, "ok")
check("the direct mail's main(): mailed (exit 0), said", (res.get("rc"), said, res.get("sent")),
      (0, ["MAILED directly"], [["[UpgradeCycle] one-way-failed: u - s", "s\n\nthe log\n"]]))
for kind, why in (("auth", "the key refused (SMTPAuthenticationError)"), ("refused", "the connection refused"),
                  ("odd", "any other error")):
    said, res = mail_main(MAILENV, kind)
    check(f"  {why}: not sent, said (exit 1) - never a traceback", (res.get("rc"), said[:1] and said[0][:9]), (1, "NOT SENT:"))
cut = "s\n\n" + "x" * 10 + "\u00e9"
env = {**MAILENV, "BODY": cut}
env_bytes = {k: v.encode() for k, v in env.items()}
env_bytes["BODY"] = env_bytes["BODY"][:-1]  # the last character cut inside its two bytes (tail -c 3000)
said, res = mail_main({k: os.fsdecode(v) for k, v in env_bytes.items()}, "ok")
check("  a body cut inside a character: mailed all the same, the byte replaced", (res.get("rc"), (res.get("sent") or [[0, ""]])[0][1][-3:]),
      (0, "x\ufffd\n"))
# the notice's direct mail as upgrade-notice.sh hands it over (a copy of it beside a recording mail script): the admin
# address, the subject and body whole, the key passed on - a page and a veto mailed, other kinds not; a page mailed
# with Alertmanager unreachable: exit 0 (it reached the operator)
C = os.path.join(W, "copy")
os.makedirs(os.path.join(C, "scripts"))
shutil.copy("scripts/upgrade-notice.sh", os.path.join(C, "scripts"))
open(os.path.join(C, "scripts/upgrade-mail.py"), "w").write("""import json, os, sys
open(os.environ["MAILS"], "a").write(json.dumps({k: os.environ.get(k) for k in ("TO", "SUBJECT", "BODY", "RESEND_API_KEY")}) + "\\n")
sys.exit(int(os.environ.get("MAIL_RC", "0")))
""")
MAILS = os.path.join(W, "mails")
def via_copy(*args, **env):
    if os.path.exists(MAILS):
        os.remove(MAILS)
    r = subprocess.run(["bash", os.path.join(C, "scripts/upgrade-notice.sh"), *args], capture_output=True, text=True,
                       env={**ENV, "MAILS": MAILS, "RESEND_API_KEY": "the-key", "UPGRADE_NOTICE_INFRA_VALUES": values, **env})
    return r.returncode, r.stdout, [json.loads(x) for x in open(MAILS)] if os.path.exists(MAILS) else []
open(values, "w").write("alertmanager:\n  enabled: true\n  alertEmailTo: admin@example.org\n")
open(details, "w").write("restore: step one")
rc, out, mails = via_copy("one-way-failed", "u4", "it broke", details)
check("a page's direct mail: to the admin, '[UpgradeCycle] <kind>: <unit> - <summary>', the summary then the details, "
      "the key passed on", (rc, mails),
      (0, [{"TO": "admin@example.org", "SUBJECT": "[UpgradeCycle] one-way-failed: u4 - it broke",
            "BODY": "it broke\n\nrestore: step one", "RESEND_API_KEY": "the-key"}]))
rc, out, mails = via_copy("veto", "pg-19.x", "applies in 24 h")
check("a veto: mailed straight out too", (rc, [m["SUBJECT"] for m in mails]), (0, ["[UpgradeCycle] veto: pg-19.x - applies in 24 h"]))
big = os.path.join(W, "fix.diff")
open(big, "w").write("=== the agent's fix - files:\n clusters/a.yaml | 2 +-\n" + "".join(f"+line {i}\n" for i in range(800)) + "the very end\n")
rc, out, mails = via_copy("veto", "istio", "applies in 24 h", big)
d = posts_last = None
check("a veto with a long diff: the direct mail carries it WHOLE (every line, its start and its end)",
      (rc, len(mails), mails[0]["BODY"].endswith(open(big).read().rstrip("\n")) if mails else None), (0, 1, True))
rc, out, posts = run("veto", "istio", "s", big, RESEND_API_KEY="k", UPGRADE_NOTICE_INFRA_VALUES=values)
desc = posts[0][0]["annotations"]["description"] if posts else ""
check("  Alertmanager's annotation: its start (the files changed) and its end, the cut said",
      (desc.startswith("=== the agent's fix - files:"), desc.rstrip().endswith("the very end"), "[... the whole in the direct mail ...]" in desc,
       len(desc) < 3100), (True, True, True, True))
open(big, "w").write("x" * 103000)
if os.path.exists(os.path.join(W, "posts")):
    os.remove(os.path.join(W, "posts"))
rc, out, mails = via_copy("veto", "istio", "s", big)
check("a veto whose details are over a mail's 100 KB: not sent, no mail, NOTHING posted (an alert promising 24 h with no "
      "evidence misleads), exit 1", (rc, mails, "over a mail's 100 KB" in out, os.path.exists(os.path.join(W, "posts"))), (1, [], True, False))
# the edges: 3000 bytes whole in Alertmanager's annotation, 3001 cut; 102400 mailed, 102401 not
for size, cut, mailed in ((3000, False, True), (3001, True, True), (102400, True, True), (102401, None, False)):
    open(big, "w").write("y" * (size - 1) + "\n")
    rc, out, posts = run("veto", "istio", "s", big, RESEND_API_KEY="k", UPGRADE_NOTICE_INFRA_VALUES=values)
    desc = posts[0][0]["annotations"]["description"] if posts else None
    _, _, mails = via_copy("veto", "istio", "s", big)
    check(f"  a veto's details of {size} bytes: {'cut' if cut else 'whole' if cut is False else 'not posted'} in Alertmanager, "
          f"{'mailed' if mailed else 'not mailed'}",
          (None if desc is None else "[... the whole in the direct mail ...]" in desc, bool(mails)), (cut, mailed))
open(os.path.join(W, "ssh.fail"), "w").write("")
rc, out, mails = via_copy("veto", "istio", "s")
check("a veto, Alertmanager unreachable, the direct mail sent: exit 0 (the mail is what it needs)", (rc, len(mails)), (0, 1))
os.remove(os.path.join(W, "ssh.fail"))
rc, out, mails = via_copy("applied", "u", "s")
check("an applied notice: Alertmanager's alone (no direct mail)", (rc, mails), (0, []))
open(os.path.join(W, "ssh.fail"), "w").write("")
rc, out, mails = via_copy("one-way-failed", "u5", "s")
check("a page, Alertmanager unreachable, the direct mail sent: exit 0 (it reached the operator)", (rc, len(mails)), (0, 1))
rc, out, mails = via_copy("veto", "pg-19.x", "s", MAIL_RC="1")
check("a veto, neither Alertmanager nor the mail: exit 1 (no clock may start)", (rc, len(mails)), (1, 1))
os.remove(os.path.join(W, "ssh.fail"))
open(details, "wb").write("\u00e9".encode() + b"y" * 2999)  # its last 3000 bytes start inside the character
rc, out, posts = run("applied", "u", "s", details)
check("details whose last 3000 bytes cut a character: posted, the byte replaced (never a lost notice)",
      (rc, posts[0][0]["annotations"]["description"][:1] if posts else None), (0, "\ufffd"))
for args in (("nope", "u", "s"), ("applied", "Bad/Unit", "s"), ("applied", "u", ""), ("applied", "u", "s", "/nonexistent"),
             ("resolve",), ("resolve", "Bad/Unit"), ("repost", "x"), ("open", "x"), ()):
    check(f"refused: {args}", run(*args)[0], 2)
print("upgrade-notice: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
