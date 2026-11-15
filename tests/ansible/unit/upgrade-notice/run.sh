#!/bin/bash
# scripts/upgrade-notice.sh - the upgrade cycle's notices, posted to Alertmanager's API as UpgradeCycle alerts (JSON on
# stdin through ssh; the same post was proven against Alertmanager v0.34.1 itself, 2026-11-15): ssh stubbed, recording
# its host, the remote command and what it was given - each kind's severity and lifetime from now, a label of each
# notice's own, the summary and the details whole (quotes, $, backticks, newlines - amtool refused a '"'), the details'
# last 3000 bytes; a one-way failure a page: recorded, mailed straight out too (no key - said), resolved (ended now,
# its record gone), posted again with a week's end; Alertmanager unreachable: a notice fails, a page's record stays;
# refused: a kind, a unit, no summary, a resolve without a page, usages it lacks.
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
import datetime, json, os, re, subprocess, sys
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
REMOTE = ("kubectl -n schnappy-infra exec -i deploy/schnappy-alertmanager -c alertmanager -- wget -qO- --header "
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
check("veto: warning, lasts the 24 h notice", (rc, posts[0][0]["labels"]["severity"], hours_from_now(posts[0][0]["endsAt"])),
      (0, "warning", 24))
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
rc, out, posts = run("repost")
check("repost: every open page posted again, the same labels, its end a week from now - the record too",
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
for args in (("nope", "u", "s"), ("applied", "Bad/Unit", "s"), ("applied", "u", ""), ("applied", "u", "s", "/nonexistent"),
             ("resolve",), ("resolve", "Bad/Unit"), ("repost", "x"), ("open", "x"), ()):
    check(f"refused: {args}", run(*args)[0], 2)
print("upgrade-notice: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
