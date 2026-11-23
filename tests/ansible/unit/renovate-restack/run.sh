#!/bin/bash
# scripts/renovate-restack.py - a conflicting Renovate PR re-made on main - against a local bare origin and a throwaway
# Forgejo API (the PR's head read there): its replacement made on main's file again and its branch force-pushed with its
# own message, as Renovate Bot - the old line itself, or (moved on main: the app wave's minor merged first) the line
# that is the old one but for its version, a neighbour of another name left alone; a line the PR changes three times
# (one image on three CI services) changed on main the three times. Refused, the branch as it was: main holding it
# another number of times, a line added (not one-for-one), another account's or a closed PR, the branch moved since the
# PR was read, no bot token.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'kill "$(cat "$W/pid" 2> /dev/null)" 2> /dev/null; rm -rf "$W"' EXIT
cat > "$W/server.py" <<'SERVER'
import http.server, json, os, sys, urllib.parse
W = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        fx = json.load(open(os.path.join(W, "fixture.json")))
        data = fx.get(urllib.parse.urlparse(self.path).path.removeprefix("/api/v1"))
        body = json.dumps(data if data is not None else {"message": "not found"}).encode()
        self.send_response(200 if data is not None else 404); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(W, "port.tmp"), "w").write(str(s.server_port)); os.rename(os.path.join(W, "port.tmp"), os.path.join(W, "port"))
s.serve_forever()
SERVER
python3 "$W/server.py" "$W" & echo $! > "$W/pid"
for _ in $(seq 50); do [ -e "$W/port" ] && break; sleep 0.1; done
[ -e "$W/port" ] || { echo "renovate-restack: the local server did not start"; exit 1; }
W=$W PORT=$(cat "$W/port") python3 - <<'PYCHECK'
import json, os, shutil, subprocess, sys
W, PORT = os.environ["W"], os.environ["PORT"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
ORIGIN = os.path.join(W, "git", "schnappy", "admin.git")
WORK = os.path.join(W, "work")
def g(*a, cwd=WORK):
    return subprocess.run(["git", "-c", "user.name=T", "-c", "user.email=t@t", *a], cwd=cwd, capture_output=True, text=True, check=True).stdout.strip()
def write(name, text):
    os.makedirs(os.path.dirname(os.path.join(WORK, name)) or WORK, exist_ok=True)
    open(os.path.join(WORK, name), "w").write(text)
GRADLE = "plugins {\n}\ndependencies {\n    implementation 'com.anthropic:anthropic-java:2.63.0'\n    implementation 'com.anthropic:other:2.63.0'\n}\n"
CD = "steps:\n  a:\n    image: postgres:17-alpine\n  b:\n    image: postgres:17-alpine\n  c:\n    image: postgres:17-alpine\n"
def repo(pr_changes, main_changes):
    """origin: main (GRADLE, CD) - the PR's branch from it with pr_changes - then main moved by main_changes; the PR's head"""
    for d in (os.path.join(W, "git"), WORK, os.path.join(W, "restack")):
        shutil.rmtree(d, ignore_errors=True)
    os.makedirs(ORIGIN)
    g("init", "-q", "--bare", "-b", "main", cwd=ORIGIN)
    os.makedirs(WORK)
    g("init", "-q", "-b", "main"); g("remote", "add", "origin", ORIGIN)
    write("build.gradle", GRADLE); write(".woodpecker/cd.yaml", CD)
    g("add", "-A"); g("commit", "-q", "-m", "base"); g("push", "-q", "origin", "main")
    g("checkout", "-q", "-b", "renovate/app-majors")
    for name, old, new in pr_changes:
        write(name, open(os.path.join(WORK, name)).read().replace(old, new))
    g("commit", "-q", "-am", "fix(deps): update app majors (major)"); g("push", "-q", "origin", "renovate/app-majors")
    head = g("rev-parse", "HEAD")
    g("checkout", "-q", "main")
    for name, old, new in main_changes:
        write(name, open(os.path.join(WORK, name)).read().replace(old, new))
    if main_changes:
        g("commit", "-q", "-am", "main moved"); g("push", "-q", "origin", "main")
    return head
def fixture(head, user="renovate-bot", state="open"):
    json.dump({"/repos/schnappy/admin/pulls/32": {"number": 32, "state": state, "user": {"login": user},
               "head": {"ref": "renovate/app-majors", "sha": head, "repo": {"full_name": "schnappy/admin"}}}},
              open(os.path.join(W, "fixture.json"), "w"))
REAL_GIT = shutil.which("git")
RACE = os.path.join(W, "racebin")
os.makedirs(RACE)
open(os.path.join(RACE, "git"), "w").write(
    "#!/bin/sh\n"  # the branch moved at origin by someone else between the restack's fetch and its push
    "case \" $* \" in *\" push \"*) %s --git-dir=%s update-ref refs/heads/renovate/app-majors \"$(%s --git-dir=%s rev-parse main)\";; esac\n"
    "exec %s \"$@\"\n" % (REAL_GIT, ORIGIN, REAL_GIT, ORIGIN, REAL_GIT))
os.chmod(os.path.join(RACE, "git"), 0o755)
def run(token="BOTTOKEN", race=False):
    e = {**os.environ, "RENOVATE_TOKEN": token, "PATH": (RACE + ":" if race else "") + os.environ["PATH"], "RESTACK_FORGEJO_URL": f"http://127.0.0.1:{PORT}/api/v1",
         "RESTACK_GIT_URL": "file://" + os.path.join(W, "git"), "RESTACK_DIR": os.path.join(W, "restack")}
    r = subprocess.run([sys.executable, "-I", "scripts/renovate-restack.py", "admin", "32"], capture_output=True, text=True, env=e, timeout=60)
    return r.returncode, r.stdout + r.stderr
def branch_file(name):
    return g("show", f"renovate/app-majors:{name}", cwd=ORIGIN)
def tip():
    return g("rev-parse", "renovate/app-majors", cwd=ORIGIN)
MAJOR = ("build.gradle", "anthropic-java:2.63.0", "anthropic-java:3.12.0")
head = repo([MAJOR], [(".woodpecker/cd.yaml", "steps:", "steps: # moved")])
fixture(head)
rc, out = run()
check("the old line on main as it was: re-made on main, force-pushed with its own message as Renovate Bot",
      (rc, "anthropic-java:3.12.0" in branch_file("build.gradle"), "steps: # moved" in branch_file(".woodpecker/cd.yaml"),
       g("log", "-1", "--format=%s|%an", "renovate/app-majors", cwd=ORIGIN), g("rev-parse", "renovate/app-majors~1", cwd=ORIGIN) == g("rev-parse", "main", cwd=ORIGIN)),
      (0, True, True, "fix(deps): update app majors (major)|Renovate Bot", True))
head = repo([MAJOR], [("build.gradle", "anthropic-java:2.63.0", "anthropic-java:2.71.0")])
fixture(head)
rc, out = run()
b = branch_file("build.gradle")
check("the line moved on main (the wave's minor first): the one that is it but for its version takes the major; its neighbour left",
      (rc, "anthropic-java:3.12.0" in b, "anthropic-java:2.71.0" in b, "com.anthropic:other:2.63.0" in b), (0, True, False, True))
head = repo([(".woodpecker/cd.yaml", "postgres:17-alpine", "postgres:19-alpine")], [("build.gradle", "plugins {", "plugins { // moved")])
fixture(head)
rc, out = run()
check("one image on three CI services: all three changed on main", (rc, branch_file(".woodpecker/cd.yaml").count("postgres:19-alpine")), (0, 3))
head = repo([(".woodpecker/cd.yaml", "postgres:17-alpine", "postgres:19-alpine")],
            [(".woodpecker/cd.yaml", "  c:\n    image: postgres:17-alpine\n", "")])
fixture(head)
rc, out = run()
check("main holding it twice, the PR changing it three times: refused, the branch as it was", (rc, "REFUSED" in out, tip()), (1, True, head))
head = repo([("build.gradle", "plugins {\n", "plugins {\n    id 'x' version '1.0.0'\n"), MAJOR], [("build.gradle", "plugins {", "plugins { // moved")])
fixture(head)
rc, out = run()
check("a line added (not one-for-one): refused, the branch as it was", (rc, "not a one-for-one" in out, tip()), (1, True, head))
head = repo([MAJOR], [("build.gradle", "anthropic-java:2.63.0", "anthropic-java:2.71.0")])
for name, kw in (("another account's PR", {"user": "mallory"}), ("a closed PR", {"state": "closed"})):
    fixture(head, **kw)
    rc, out = run()
    check(f"{name}: refused, the branch as it was", (rc, "is not an open Renovate PR" in out, tip()), (1, True, head))
fixture("f" * 40)
rc, out = run()
check("the branch moved since the PR was read: refused, the branch as it was", (rc, "moved since the PR was read" in out, tip()), (1, True, head))
fixture(head)
rc, out = run(race=True)
check("the branch moved at origin between the fetch and the push: the push refused (its lease), the other's commit kept",
      (rc, "REFUSED" in out, tip() == g("rev-parse", "main", cwd=ORIGIN)), (1, True, True))
head = repo([MAJOR], [("build.gradle", "anthropic-java:2.63.0", "anthropic-java:2.71.0"),
                      ("build.gradle", "    implementation 'com.anthropic:other:2.63.0'\n", "    implementation 'com.anthropic:anthropic-java:latest.release'\n")])
fixture(head)
rc, out = run()
check("the version wildcard a version alone: the moved line (2.71.0) takes the major, a non-version one (latest.release) left",
      (rc, "anthropic-java:3.12.0" in branch_file("build.gradle"), "anthropic-java:latest.release" in branch_file("build.gradle")), (0, True, True))
head = repo([MAJOR], [("build.gradle", "anthropic-java:2.63.0", "anthropic-java:2.71.0")])
fixture(head)
rc, out = run(token="")
check("no bot token: refused, nothing read or pushed", (rc, "RENOVATE_TOKEN is empty" in out, tip()), (1, True, head))
print("renovate-restack: ALL-PASS" if fails == 0 else f"renovate-restack: {fails} FAILED")
sys.exit(1 if fails else 0)
PYCHECK
