"""Build a localhost play that reuses the EXACT `when` strings, the EXACT `data:`
map and the EXACT play-level `masi_api_key` definition of the masi tasks in
deploy/ansible/playbooks/seed-vault-secrets.yml. One call site — the playbook
file itself — so this harness cannot drift from what ships. The Vault write is
replaced by a set_fact that renders the real data map; the skip notice is
copied verbatim so its message template renders too."""
import json
import sys

import yaml

src, dst = sys.argv[1], sys.argv[2]
play_src = yaml.safe_load(open(src))[0]
tasks = play_src["tasks"]


def find(sub):
    """Substring match so a task rename does not blind the harness."""
    hits = [t for t in tasks if sub in (t.get("name") or "").lower()]
    if len(hits) != 1:
        sys.exit(f"HARNESS: expected exactly one task matching {sub!r}, found {len(hits)}")
    return hits[0]


write_task = find("seed masi ai secret")
notice = dict(find("masi ai secret not seeded"))
write_when = write_task.get("when")  # None if the gate was removed
data = write_task["community.hashi_vault.vault_kv2_write"]["data"]
stand_in = {
    "name": write_task["name"],
    "ansible.builtin.set_fact": {"masi_written": data},
    "no_log": True,
    "register": "write_result",
}
if write_when is not None:
    stand_in["when"] = write_when
notice["register"] = "notice_result"

# Carry the play-level variables the tasks reference (the single call site for
# the env lookup lives there), never a retyped copy.
src_vars = play_src.get("vars", {})
carried = {k: src_vars[k] for k in ("vault_prefix", "masi_api_key") if k in src_vars}

play = [{
    "name": "gate harness for seed-vault-secrets masi tasks",
    "hosts": "localhost",
    "connection": "local",
    "gather_facts": False,
    "vars": carried,
    "tasks": [
        stand_in,
        notice,
        {
            "name": "Verdict",
            "ansible.builtin.assert": {
                "that": [
                    "(write_result is not skipped) == (expect_write | bool)",
                    "(notice_result is skipped) == (expect_write | bool)",
                    "not (expect_write | bool) or (masi_written.api_key | trim | length > 0)",
                ],
                "fail_msg": "write ran={{ write_result is not skipped }} notice ran={{ notice_result is not skipped }} expected write={{ expect_write }}",
                "success_msg": "write ran={{ write_result is not skipped }} notice ran={{ notice_result is not skipped }} (expected write={{ expect_write }})",
            },
        },
    ],
}]
yaml.safe_dump(play, open(dst, "w"), sort_keys=False, width=200)
print("extracted when(write) =", json.dumps(write_when))
print("extracted when(notice)=", json.dumps(notice.get("when")))
print("extracted vars        =", json.dumps(carried))
