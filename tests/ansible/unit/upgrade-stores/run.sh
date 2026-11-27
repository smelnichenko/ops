#!/bin/bash
# scripts/upgrade-stores.py - what a one-way unit's store needs, from its table - against the real table (each store's
# real unit names; a test unit's twin; a unit of no store) and tables that are not as described: a store with neither
# backups, taken_by nor missing, a list that is none, a key missing, a bad regex, two stores naming one unit - each exit
# 1, said, never a traceback and never a guess (the runner blocks the unit on it).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
exec python3 - "$W" <<'PY_STORES'
import json, os, subprocess, sys
W = sys.argv[1]
REAL = json.load(open("scripts/upgrade-stores.json"))
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
def run(unit, labels, table=None):
    env = dict(os.environ)
    if table is not None:
        path = os.path.join(W, "table.json")
        open(path, "w").write(table if isinstance(table, str) else json.dumps(table))
        env["UPGRADE_STORES_TABLE"] = path
    r = subprocess.run([sys.executable, "-I", "scripts/upgrade-stores.py", unit, labels], capture_output=True, text=True, env=env)
    return r.returncode, r.stdout.split("\n")[0].split(" ")[0], ("Traceback" in r.stderr)
check("each store's real unit names: its own store's answer (missing, store) - none unknown",
      sorted({(s["store"], run(e, "one-way")[1]) for s in REAL["stores"] for e in s["examples"]}),
      sorted({(s["store"], "missing" if s["missing"] else "store") for s in REAL["stores"]}))
check("Keycloak's units (minor and major): missing - its way back not yet rehearsed (a one-way gate clears only then)",
      [run(u, "one-way")[1] for u in ("keycloak-26.8", "quay.io-keycloak-keycloak-27.x")], ["missing", "missing"])
# Keycloak's dump is its own production command's (plan 122: upgrade-keycloak.yml dumps before anything stops) - a
# literal, not read from the table: the runner wants deploy:keycloak:upgrade in the unit's plan
check("  its store taken by deploy:keycloak:upgrade (the playbook that dumps it)",
      next(s for s in REAL["stores"] if s["store"] == "keycloak")["taken_by"], ["deploy:keycloak:upgrade"])
# Vault's and Consul's own commands take their snapshots, but the way back from them has never run (by hand, the
# playbooks' headers say): blocked until a way-back check passes on the copy - a literal, as Keycloak's
check("Vault's and Consul's majors: missing - their way backs not yet rehearsed; their commands still the ones taking the snapshot",
      ([run(u, "major,one-way")[1] for u in ("hashicorp-vault-2.x", "hashicorp-consul-2.x")],
       [next(s for s in REAL["stores"] if s["store"] == x)["taken_by"] for x in ("vault", "consul")]),
      (["missing", "missing"], [["deploy:vault:upgrade"], ["deploy:consul:upgrade"]]))
# Postgres' store is the CNPG image alone (2026-11-21): the plain postgres image in infra and platform is the init-users
# Job's psql client - its major, postgres-19.x, is an ordinary unit; the databases' image a store's as before
check("postgres-19.x (the init-users Job's psql client) a unit of no store; the CNPG image's major Postgres' store",
      (run("postgres-19.x", "major,upgrade-cycle")[:2], run("ghcr.io-cloudnative-pg-postgresql-19.x", "major,one-way,upgrade-cycle")[:2]),
      ((0, "none"), (0, "store")))
check("a unit of no store, unlabelled: none; labelled one-way: unknown (blocked - its store decided in the table)",
      (run("wave-patches", "upgrade-cycle")[:2], run("data-operators", "one-way,upgrade-cycle")[:2]), ((0, "none"), (0, "unknown")))
store = {"store": "x", "units": "(^|-)x-[0-9]+\\.x$", "packages": ["x"], "backups": ["deploy:x"], "missing": [], "taken_by": [],
         "examples": ["x-1.x"]}
check("a store backed up whole: store <name>, then each backup",
      subprocess.run([sys.executable, "-I", "scripts/upgrade-stores.py", "x-1.x", "one-way"], capture_output=True, text=True,
                     env={**os.environ, "UPGRADE_STORES_TABLE": (open(os.path.join(W, "ok.json"), "w").write(json.dumps({"stores": [store]})) and os.path.join(W, "ok.json"))}).stdout,
      "store x\nbackup deploy:x\n")
for table, why in (({"stores": [{**store, "backups": [], "missing": [], "taken_by": []}]}, "a store with neither backups, taken_by nor missing"),
                   ({"stores": [{**store, "backups": "deploy:x"}]}, "backups no list"),
                   ({"stores": [{k: v for k, v in store.items() if k != "packages"}]}, "a key missing (packages)"),
                   ({"stores": [{**store, "units": "(x"}]}, "a bad regex"),
                   ({"stores": [store, {**store, "store": "y"}]}, "two stores naming one unit"),
                   ("{not json", "not JSON")):
    rc, first, tb = run("x-1.x", "one-way", table)
    check(f"a table not as described ({why}): exit 1, nothing printed, never a traceback", (rc, first, tb), (1, "", False))
print("upgrade-stores: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_STORES
