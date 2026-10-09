#!/bin/bash
# deploy/ansible/playbooks/tasks/apt-key-pinned.yml on localhost, keys made here: the pinned key installed (dearmored
# when asked), another key refused with the keyring untouched, a file with the pinned key and another appended refused;
# and every apt repository key the playbooks fetch goes through it, pinned.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
[ -x "$AP" ] || { echo "apt-key-pinned: no ansible-playbook"; exit 2; }
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
export GNUPGHOME=$W/gnupg
mkdir -m 0700 "$GNUPGHOME"
for k in pinned other; do
  gpg --batch --quiet --passphrase '' --quick-gen-key "$k <$k@test.invalid>" ed25519 sign never 2> /dev/null
  gpg --batch --armor --export "$k@test.invalid" > "$W/$k.asc"
done
fpr() { gpg --batch --with-colons --list-keys "$1@test.invalid" | awk -F: '$1 == "fpr" {print $10; exit}'; }
PIN=$(fpr pinned)
cat "$W/pinned.asc" "$W/other.asc" > "$W/both.asc"
fails=0
check() {  # name got want
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi
}
play() {  # play <key file> <dearmor> -> rc; the keyring at $W/keyring
  cat > "$W/play.yml" <<YAML
- hosts: localhost
  gather_facts: false
  tasks:
    - ansible.builtin.include_tasks: $PWD/deploy/ansible/playbooks/tasks/apt-key-pinned.yml
      vars:
        apt_key_url: file://$1
        apt_key_fingerprint: $PIN
        apt_key_dest: $W/keyring
        apt_key_dearmor: $2
YAML
  env -u GNUPGHOME "$AP" -i localhost, -c local "$W/play.yml" > "$W/out" 2>&1
}
rm -f "$W/keyring"; play "$W/pinned.asc" false
check "the pinned key: installed as fetched" "$? $(cmp -s "$W/pinned.asc" "$W/keyring" && echo same)" "0 same"
rm -f "$W/keyring"; play "$W/pinned.asc" true
check "  dearmored when asked (a .gpg keyring)" "$? $(file -b "$W/keyring" | grep -c 'PGP\|GPG\|OpenPGP')" "0 1"
echo keep > "$W/keyring"; play "$W/other.asc" false
check "another key: refused, said, the keyring untouched" "$? $(grep -c 'REFUSED' "$W/out") $(cat "$W/keyring")" "2 1 keep"
echo keep > "$W/keyring"; play "$W/both.asc" false
check "the pinned key with another appended: refused, the keyring untouched" "$? $(cat "$W/keyring")" "2 keep"
# every key the playbooks fetch for apt goes through the pinned task, with a 40-hex pin
python3 - <<'PY_APT_SITES'
import glob, re, sys, yaml
def walk(ts):
    for t in ts or []:
        if isinstance(t, dict):
            yield t
            for k in ("block", "rescue", "always", "tasks"):
                yield from walk(t.get(k))
bad, pinned = [], 0
for f in glob.glob("deploy/ansible/playbooks/*.yml"):
    plays = yaml.safe_load(open(f)) or []
    for pl in plays:
        pv = pl.get("vars") or {}
        for t in walk(pl.get("tasks")):
            if "block" in t:
                continue  # its tasks are walked themselves
            text = yaml.safe_dump(t)
            if re.search(r"Release\.key|download\.docker\.com/linux/\w+/gpg", text) and "apt-key-pinned.yml" not in text:
                bad.append(f"{f}: {t.get('name')}")
            if "apt-key-pinned.yml" in str(t.get("ansible.builtin.include_tasks", "")):
                v = t.get("vars") or {}
                fp = v.get("apt_key_fingerprint", "")
                fp = pv.get(fp.strip("{} "), fp) if fp.startswith("{{") else fp
                pinned += bool(re.fullmatch(r"[0-9A-F]{40}", str(fp)))
print("PASS every apt key fetched through the pinned task" if not bad else "FAIL keys fetched unpinned: " + "; ".join(bad))
print(("PASS" if pinned >= 4 else "FAIL") + f" the pinned includes carry a 40-hex fingerprint ({pinned})")
sys.exit(1 if bad or pinned < 4 else 0)
PY_APT_SITES
[ $? = 0 ] || fails=$((fails + 1))
echo "apt-key-pinned: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
