"""Build localhost plays that reuse the EXACT expressions of
deploy/ansible/playbooks/seed-vault-secrets.yml — one call site, the playbook
file itself — so this harness cannot drift from what ships:

  gate.yml     the masi-key tasks: exact `when` strings, exact `data:` map and the
               exact play-level `masi_api_key` definition. The Vault write becomes
               a set_fact rendering the real data map; the notice is copied verbatim.
  resolve.yml  the generatable-secret machinery: the exact `failed_when` of the
               existing-secret read (only a missing path may be tolerated) and the
               exact `set_fact` expression that reuses an existing password or
               generates a fresh one, driven by fake read results.
"""
import json
import sys

import yaml

src, out_dir = sys.argv[1], sys.argv[2]
play_src = yaml.safe_load(open(src))[0]
tasks = play_src["tasks"]


def find(sub):
    """Substring match so a task rename does not blind the harness."""
    hits = [t for t in tasks if sub in (t.get("name") or "").lower()]
    if len(hits) != 1:
        sys.exit(f"HARNESS: expected exactly one task matching {sub!r}, found {len(hits)}")
    return hits[0]


def dump(name, play):
    yaml.safe_dump([play], open(f"{out_dir}/{name}", "w"), sort_keys=False, width=200)


# ---- gate.yml -----------------------------------------------------------------
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
src_vars = play_src.get("vars", {})
carried = {k: src_vars[k] for k in ("vault_prefix", "masi_api_key") if k in src_vars}
dump("gate.yml", {
    "name": "gate harness for seed-vault-secrets masi tasks",
    "hosts": "localhost", "connection": "local", "gather_facts": False,
    "vars": carried,
    "tasks": [
        stand_in, notice,
        {"name": "Verdict", "ansible.builtin.assert": {
            "that": [
                "(write_result is not skipped) == (expect_write | bool)",
                "(notice_result is skipped) == (expect_write | bool)",
                "not (expect_write | bool) or (masi_written.api_key | trim | length > 0)",
            ],
            "fail_msg": "write ran={{ write_result is not skipped }} notice ran={{ notice_result is not skipped }} expected write={{ expect_write }}",
            "success_msg": "write ran={{ write_result is not skipped }} notice ran={{ notice_result is not skipped }} (expected write={{ expect_write }})",
        }},
    ],
})
print("gate:    when(write) =", json.dumps(write_when), "| when(notice) =", json.dumps(notice.get("when")))

# ---- resolve.yml ---------------------------------------------------------------
read_task = find("read existing generatable secrets")
read_failed_when = read_task.get("failed_when")  # None => Ansible default (fail on failed)
resolve_task = find("resolve generatable secret values")
resolve_expr = resolve_task["ansible.builtin.set_fact"]["resolved_secrets"]
resolve_loop = resolve_task["loop"]
fake_results = [
    {"secret": {"database": "keep", "username": "keep", "password": "KEEP-ME-32-CHARS-EXISTING-VALUE!"}},
    {"failed": True, "msg": "Invalid or missing path: schnappy/fresh"},
]
failed_when_cases = [
    {"result": {"failed": True, "msg": "Invalid or missing path"}, "expected": False, "label": "missing path is tolerated"},
    {"result": {"failed": True, "msg": "MODULE FAILURE: connection refused"}, "expected": True, "label": "outage aborts"},
    {"result": {"failed": True, "msg": "Forbidden: permission denied"}, "expected": True, "label": "forbidden aborts"},
    {"result": {"failed": False, "secret": {"password": "x"}}, "expected": False, "label": "successful read passes"},
]
fw_tasks = []
if not isinstance(read_failed_when, str):
    # None (Ansible default: any failure aborts, so a first run dies on the 404) or a bare
    # boolean (`false` swallows every failure and lets an outage rotate passwords).
    fw_tasks.append({"name": "Verdict on read failed_when", "ansible.builtin.fail": {
        "msg": f"the existing-secret read needs a failed_when EXPRESSION that tolerates only a missing path; got {read_failed_when!r}"}})
else:
    fw_tasks.append({"name": "Evaluate the exact read failed_when against fake results",
                     "ansible.builtin.set_fact": {"fw_results": "{{ (fw_results | default([])) + [ ((" + read_failed_when.strip() + ") | bool) ] }}"},
                     "vars": {"_existing_secrets": "{{ item.result }}"},
                     "loop": failed_when_cases, "loop_control": {"label": "{{ item.label }}"}})
    fw_tasks.append({"name": "Verdict on read failed_when", "ansible.builtin.assert": {
        "that": ["fw_results[idx] == item.expected"],
        "fail_msg": "failed_when for '{{ item.label }}' evaluated {{ fw_results[idx] }}, expected {{ item.expected }}",
        "success_msg": "failed_when: {{ item.label }}"},
        "loop": failed_when_cases, "loop_control": {"index_var": "idx", "label": "{{ item.label }}"}})
dump("resolve.yml", {
    "name": "resolve harness for seed-vault-secrets generatable secrets",
    "hosts": "localhost", "connection": "local", "gather_facts": False,
    "vars": {
        "generatable_secrets": [
            {"path": "keep", "static": {"database": "keep", "username": "keep"}, "secrets": ["password"]},
            {"path": "fresh", "static": {"database": "fresh", "username": "fresh"}, "secrets": ["password"]},
        ],
        "_existing_secrets": {"results": fake_results},
    },
    "tasks": fw_tasks + [
        {"name": resolve_task["name"], "ansible.builtin.set_fact": {"resolved_secrets": resolve_expr},
         "loop": resolve_loop, "loop_control": {"label": "{{ item.0.path }}"}},
        {"name": "Verdict on resolve", "ansible.builtin.assert": {
            "that": [
                "resolved_secrets.keep.password == 'KEEP-ME-32-CHARS-EXISTING-VALUE!'",
                "resolved_secrets.keep.database == 'keep' and resolved_secrets.keep.username == 'keep'",
                "resolved_secrets.fresh.password | length == 32",
                "resolved_secrets.fresh.password != resolved_secrets.keep.password",
                "resolved_secrets.fresh.database == 'fresh'",
            ],
            "fail_msg": "resolve: keep.password={{ resolved_secrets.keep.password | default('?') }} fresh.password length={{ resolved_secrets.fresh.password | default('') | length }}",
            "success_msg": "resolve: existing password reused, missing one generated (32 chars), static fields kept",
        }},
    ],
})
print("resolve: failed_when =", json.dumps(read_failed_when))
