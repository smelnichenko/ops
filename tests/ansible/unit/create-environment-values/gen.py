"""Render every values/manifest template that create-environment.yml writes with
ansible.builtin.copy, through Ansible itself (same templating as production), into
a scratch dir — so a broken template is caught here, not by Argo after the push.
The exact `content:` strings are taken from the parsed playbook; only the vars are
synthetic."""
import sys

import yaml

src, out, dest_dir = sys.argv[1], sys.argv[2], sys.argv[3]
play_src = yaml.safe_load(open(src))[0]


def flatten(items):
    for t in items:
        yield t
        for key in ("block", "rescue", "always"):
            if isinstance(t.get(key), list):
                yield from flatten(t[key])


all_tasks = list(flatten(play_src.get("tasks", []) + play_src.get("pre_tasks", [])))
copies = [t for t in all_tasks if isinstance(t.get("ansible.builtin.copy"), dict) and "content" in t["ansible.builtin.copy"]]
blocks = [t for t in all_tasks if isinstance(t.get("ansible.builtin.blockinfile"), dict) and "block" in t["ansible.builtin.blockinfile"]]
lines = [t for t in all_tasks if isinstance(t.get("ansible.builtin.lineinfile"), dict) and "line" in t["ansible.builtin.lineinfile"]]
if not copies:
    sys.exit("HARNESS: no ansible.builtin.copy tasks with content found")

play_vars = {k: v for k, v in play_src.get("vars", {}).items() if k != "vault_cli_env"}
play_vars.update({
    "env_name": "harness", "playbook_dir": "/nonexistent",
    "gen_db_password": "db-pass", "gen_valkey_password": "valkey-pass",
    "gen_minio_password": "minio-pass", "gen_kafka_cluster_id": "kafka-id",
})
tasks = []
for i, t in enumerate(copies):
    tasks.append({"name": f"Render: {t.get('name', i)}",
                  "ansible.builtin.copy": {"content": t["ansible.builtin.copy"]["content"], "dest": f"{dest_dir}/{i}.yaml"}})
# blockinfile blocks and lineinfile lines are YAML fragments: render them too
for j, t in enumerate(blocks):
    tasks.append({"name": f"Render block: {t.get('name', j)}",
                  "ansible.builtin.copy": {"content": t["ansible.builtin.blockinfile"]["block"], "dest": f"{dest_dir}/block-{j}.yaml"}})
for j, t in enumerate(lines):
    tasks.append({"name": f"Render line: {t.get('name', j)}",
                  "ansible.builtin.copy": {"content": t["ansible.builtin.lineinfile"]["line"] + "\n", "dest": f"{dest_dir}/line-{j}.txt"}})
tasks.append({"name": "The Namespace manifest carries an admitted environment label",
              "ansible.builtin.shell": "python3 -c \"import sys, yaml, glob; docs=[d for f in sorted(glob.glob('" + dest_dir + "/*.yaml')) for d in yaml.safe_load_all(open(f)) if isinstance(d, dict) and d.get('kind')=='Namespace']; assert docs, 'no Namespace rendered'; bad=[d['metadata']['name'] for d in docs if d['metadata'].get('labels',{}).get('environment') not in ('production','test')]; assert not bad, 'environment label not admitted by the default-deny: %s' % bad; print('namespace label ok for', [d['metadata']['name'] for d in docs])\"",
              "changed_when": False})
tasks.append({"name": "Every rendered template parses as YAML",
              "ansible.builtin.shell": "python3 -c \"import sys, yaml, glob; [list(yaml.safe_load_all(open(f))) for f in sorted(glob.glob('" + dest_dir + "/*.yaml'))]; print('parsed', len(glob.glob('" + dest_dir + "/*.yaml')), 'templates')\"",
              "changed_when": False})
yaml.safe_dump([{"name": "create-environment values templates render and parse", "hosts": "localhost",
                 "connection": "local", "gather_facts": False, "vars": play_vars, "tasks": tasks}],
               open(out, "w"), sort_keys=False, width=200)
print("templates:", len(copies), "copy +", len(blocks), "block +", len(lines), "line →", [t.get("name") for t in copies + blocks + lines])
