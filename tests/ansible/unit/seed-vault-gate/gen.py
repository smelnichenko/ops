"""Build localhost plays that reuse the EXACT expressions of
deploy/ansible/playbooks/seed-vault-secrets.yml — one call site, the playbook
file itself — so these harnesses cannot drift from what ships:

  gate.yml     the masi-key tasks: exact `when` strings, exact `data:` map, the exact
               play-level `masi_api_key` definition and the exact summary task. The
               Vault write becomes a set_fact rendering the real data map.
  resolve.yml  the generatable-secret machinery: the exact `failed_when` of the
               existing-secret read, evaluated against the module's REAL messages,
               and the exact index + resolve tasks driven by fake read results.
  oracle.yml   the exact read task run through the REAL vault_kv2_get module against
               fakevault.py (200 / 404 / 403 / 503 / connection refused): the
               tolerance must admit only the missing path.
"""
import copy
import json
import sys

import yaml

src, out_dir, vault_port = sys.argv[1], sys.argv[2], sys.argv[3]
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
summary = dict(find("secrets seeded"))
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
summary["register"] = "summary_result"
src_vars = play_src.get("vars", {})
carried = {k: src_vars[k] for k in ("vault_prefix", "masi_api_key") if k in src_vars}
dump("gate.yml", {
    "name": "gate harness for seed-vault-secrets masi tasks",
    "hosts": "localhost", "connection": "local", "gather_facts": False,
    "vars": carried,
    "tasks": [
        stand_in, notice, summary,
        {"name": "Verdict", "ansible.builtin.assert": {
            "that": [
                "(write_result is not skipped) == (expect_write | bool)",
                "(notice_result is skipped) == (expect_write | bool)",
                "('ai-masi seeded' in summary_result.msg) == (expect_write | bool)",
                "not (expect_write | bool) or (masi_written.api_key == expect_key)",
            ],
            "fail_msg": "write ran={{ write_result is not skipped }} notice ran={{ notice_result is not skipped }} summary={{ summary_result.msg | regex_replace('.*(ai-masi[^.]*).*', '\\\\1') }} written={{ (masi_written | default({})).api_key | default('') }} expected write={{ expect_write }} key={{ expect_key | default('') }}",
            "success_msg": "write ran={{ write_result is not skipped }} notice ran={{ notice_result is not skipped }} summary agrees (expected write={{ expect_write }})",
        }},
    ],
})
print("gate:    when(write) =", json.dumps(write_when), "| when(notice) =", json.dumps(notice.get("when")))

# ---- resolve.yml ---------------------------------------------------------------
read_task = find("read existing generatable secrets")
read_failed_when = read_task.get("failed_when")
if isinstance(read_failed_when, list) and len(read_failed_when) == 1:
    read_failed_when = read_failed_when[0]
index_task = dict(find("index existing generatable secrets"))
resolve_task = dict(find("resolve generatable secret values"))
for t in (index_task, resolve_task):
    t.pop("no_log", None)
# Real messages of community.hashi_vault 7.1.0 vault_kv2_get on ansible-core 2.20
failed_when_cases = [
    {"result": {"failed": True, "msg": "Invalid or missing path ['schnappy/fresh'] with secret version 'latest'. Check the path or secret version."},
     "expected": False, "label": "missing path is tolerated"},
    {"result": {"failed": True, "msg": "Forbidden: Permission Denied to path ['schnappy/forbidden']."},
     "expected": True, "label": "forbidden aborts"},
    {"result": {"failed": True, "msg": "Task failed: Module failed: Vault is sealed, on get http://127.0.0.1:8200/v1/secret/data/schnappy/sealed"},
     "expected": True, "label": "sealed aborts"},
    {"result": {"failed": True, "msg": "Task failed: Module failed: HTTPConnectionPool(host='127.0.0.1', port=8201): Max retries exceeded"},
     "expected": True, "label": "connection refused aborts"},
    {"result": {"failed": False, "secret": {"password": "x"}}, "expected": False, "label": "successful read passes"},
]
fw_tasks = []
if not isinstance(read_failed_when, str):
    # None (Ansible default: any failure aborts, so a first run dies on the 404) or a bare
    # boolean (`false` swallows every failure and lets an outage rotate passwords).
    fw_tasks.append({"name": "Verdict on read failed_when", "ansible.builtin.fail": {
        "msg": f"the existing-secret read needs a failed_when EXPRESSION that tolerates only a missing path; got {read_failed_when!r}"}})
else:
    fw_tasks.append({"name": "Evaluate the exact read failed_when against the module's real messages",
                     "ansible.builtin.set_fact": {"fw_results": "{{ (fw_results | default([])) + [ ((" + read_failed_when.strip() + ") | bool) ] }}"},
                     "vars": {"_existing_secrets": "{{ item.result }}"},
                     "loop": failed_when_cases, "loop_control": {"label": "{{ item.label }}"}})
    fw_tasks.append({"name": "Verdict on read failed_when", "ansible.builtin.assert": {
        "that": ["fw_results[idx] == item.expected"],
        "fail_msg": "failed_when for '{{ item.label }}' evaluated {{ fw_results[idx] }}, expected {{ item.expected }}",
        "success_msg": "failed_when: {{ item.label }}"},
        "loop": failed_when_cases, "loop_control": {"index_var": "idx", "label": "{{ item.label }}"}})
generatable = [
    {"path": "keep", "static": {"database": "keep", "username": "keep"}, "secrets": ["password"]},
    {"path": "fresh", "static": {"database": "fresh", "username": "fresh"}, "secrets": ["password"]},
    {"path": "both-missing", "static": {}, "secrets": ["a", "b"]},
    {"path": "partial", "static": {}, "secrets": ["kept", "added"]},
]
fake_results = [  # same order as generatable, the shape the real module returns
    {"failed": False, "secret": {"database": "keep", "username": "keep", "password": "KEEP-ME-32-CHARS-EXISTING-VALUE!"}},
    {"failed": True, "msg": "Invalid or missing path ['schnappy/fresh'] with secret version 'latest'. Check the path or secret version."},
    {"failed": True, "msg": "Invalid or missing path ['schnappy/both-missing'] with secret version 'latest'. Check the path or secret version."},
    {"failed": False, "secret": {"kept": "KEPT-VALUE-STAYS-EXACTLY-AS-IS-01"}},
]
dump("resolve.yml", {
    "name": "resolve harness for seed-vault-secrets generatable secrets",
    "hosts": "localhost", "connection": "local", "gather_facts": False,
    "vars": {"generatable_secrets": generatable, "_existing_secrets": {"results": fake_results}},
    "tasks": fw_tasks + [index_task, resolve_task,
        {"name": "Verdict on resolve", "ansible.builtin.assert": {
            "that": [
                "resolved_secrets.keep.password == 'KEEP-ME-32-CHARS-EXISTING-VALUE!'",
                "resolved_secrets.keep.database == 'keep' and resolved_secrets.keep.username == 'keep'",
                "resolved_secrets.fresh.password | length == 32",
                "resolved_secrets.fresh.database == 'fresh'",
                "resolved_secrets['both-missing'].a | length == 32 and resolved_secrets['both-missing'].b | length == 32",
                "resolved_secrets['both-missing'].a != resolved_secrets['both-missing'].b",
                "resolved_secrets.partial.kept == 'KEPT-VALUE-STAYS-EXACTLY-AS-IS-01'",
                "resolved_secrets.partial.added | length == 32",
            ],
            "fail_msg": "resolve: {{ resolved_secrets | default({}) | to_json }}",
            "success_msg": "resolve: existing fields reused, missing ones generated (32 chars, distinct per field), static fields kept",
        }},
    ],
})
print("resolve: failed_when =", json.dumps(read_failed_when))

# ---- oracle.yml ------------------------------------------------------------------
def real_read(url, paths):
    t = copy.deepcopy(read_task)
    m = t["community.hashi_vault.vault_kv2_get"]
    m["url"] = url
    m["token"] = "dummy"
    t.pop("no_log", None)
    t["ignore_errors"] = True  # every item's outcome stays visible; the verdict is failed_when_result per item
    t["loop"] = "{{ " + json.dumps([{"path": p} for p in paths]) + " }}"
    return t

reach = real_read(f"http://127.0.0.1:{vault_port}", ["keep", "fresh", "forbidden", "sealed"])
reach["register"] = "_existing_secrets"
refused = real_read("http://127.0.0.1:1", ["refused"])
refused["register"] = "_refused"
dump("oracle.yml", {
    "name": "oracle: the real vault_kv2_get through the shipped read task against a fake Vault",
    "hosts": "localhost", "connection": "local", "gather_facts": False,
    "vars": {"vault_prefix": "schnappy", "vault_token_value": "dummy"},
    "tasks": [reach, refused,
        {"name": "Verdict on oracle", "ansible.builtin.assert": {
            "that": [
                "_existing_secrets.results | map(attribute='failed_when_result') | list == [false, false, true, true]",
                "_existing_secrets.results[0].secret.password == 'KEEP-REAL'",
                "_refused.results[0].failed_when_result | bool",
            ],
            "fail_msg": "oracle: keep/fresh/forbidden/sealed failed_when_result={{ _existing_secrets.results | map(attribute='failed_when_result') | list }} refused={{ _refused.results[0].failed_when_result }}",
            "success_msg": "oracle: 200 read, 404 tolerated, 403/503/refused abort — with the real module",
        }},
    ],
})
print("oracle:  fake Vault on port", vault_port)
