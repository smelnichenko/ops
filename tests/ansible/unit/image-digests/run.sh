#!/bin/bash
# scripts/vagrant-image-digests.sh run against an ssh stub answering the Vagrant copy's pods and CronJobs (JSON, with
# the \r a terminal adds): every image pinned by digest named once as "<name> <tag> <digest>" - a chart's two-key pin
# (tag: <tag>@sha256:...), a registry with a port (the tag split from the last path part, not at the first colon),
# init containers and CronJobs' containers too; an image by tag alone skipped. Each step's digests come from it, and
# production's pre-pull pulls by them: one dropped went back to a pull by tag.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
A=sha256:$(printf 'a%.0s' {1..64}) B=sha256:$(printf 'b%.0s' {1..64}) C=sha256:$(printf 'c%.0s' {1..64})
D=sha256:$(printf 'd%.0s' {1..64}) E=sha256:$(printf 'e%.0s' {1..64})
cat > "$W/pods.json" <<JSON
{"items": [
 {"kind": "Pod", "spec": {"containers": [{"image": "ghcr.io/x/app:1.2@$A"}, {"image": "nginx:1.27"}],
                          "initContainers": [{"image": "docker.io/library/busybox:1.37@$D"}]}},
 {"kind": "Pod", "spec": {"containers": [{"image": "registry.local:5000/team/b:2.0@$B"},
                                         {"image": "ghcr.io/x/app:1.2@$A"}]}},
 {"kind": "Pod", "spec": {"containers": [{"image": "registry.local:5000/team/c@$C"}]}},
 {"kind": "CronJob", "spec": {"jobTemplate": {"spec": {"template": {"spec": {
   "containers": [{"image": "quay.io/y/e:3@$E"}]}}}}}}
]}
JSON
cat > "$W/bin/ssh" <<STUB
#!/bin/bash
echo "\$*" >> "$W/ssh-args"
sed 's/\$/\r/' "$W/pods.json"
STUB
chmod +x "$W/bin/ssh"
out=$(PATH="$W/bin:$PATH" VAGRANT_SSH_CONFIG=/dev/null bash scripts/vagrant-image-digests.sh 2>&1); rc=$?
want="ghcr.io/x/app 1.2 $A
docker.io/library/busybox 1.37 $D
registry.local:5000/team/b 2.0 $B
registry.local:5000/team/c latest $C
quay.io/y/e 3 $E"
fails=0
if [ $rc = 0 ] && [ "$out" = "$want" ]; then echo "PASS every pinned image once: two-key pins, a registry's port, init containers, CronJobs; by tag alone skipped"
else echo "FAIL the digests (rc $rc):"; diff <(echo "$want") <(echo "$out") | head; fails=$((fails + 1)); fi
if grep -q "pods,cronjobs -A -o json" "$W/ssh-args"; then echo "PASS read from the Vagrant copy's pods and CronJobs"
else echo "FAIL its read: $(cat "$W/ssh-args")"; fails=$((fails + 1)); fi
# bounded, both ways it reaches the VM: the connection's keep-alives (a stalled VM ends it) and the API server's own
# request timeout - read after every step, it held the full run for good on a stall
if grep -q -- "--request-timeout=" "$W/ssh-args" && grep -q "ServerAliveInterval=" "$W/ssh-args"; then
  echo "PASS by ssh: keep-alives on the connection, a request timeout on kubectl"
else echo "FAIL by ssh, unbounded: $(cat "$W/ssh-args")"; fails=$((fails + 1)); fi
cat > "$W/bin/vagrant" <<STUB
#!/bin/bash
echo "\$*" >> "$W/vagrant-args"
sed 's/\$/\r/' "$W/pods.json"
STUB
chmod +x "$W/bin/vagrant"
out=$(PATH="$W/bin:$PATH" env -u VAGRANT_SSH_CONFIG bash scripts/vagrant-image-digests.sh 2>&1); rc=$?
if [ $rc = 0 ] && grep -q -- "--request-timeout=" "$W/vagrant-args" && grep -q -- "-- .*ServerAliveInterval=" "$W/vagrant-args"; then
  echo "PASS by vagrant ssh: the same digests, keep-alives handed to its ssh, a request timeout on kubectl"
else echo "FAIL by vagrant ssh (rc $rc): $(cat "$W/vagrant-args" 2> /dev/null)"; fails=$((fails + 1)); fi
echo "image-digests: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
