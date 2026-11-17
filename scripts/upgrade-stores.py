#!/usr/bin/env python3
"""upgrade-stores.py - what a unit's one-way change needs before production, from scripts/upgrade-stores.json.

Usage: scripts/upgrade-stores.py <unit> <labels, comma-separated>
Prints, and exits 0:
  none                       not one-way (no one-way label, its name no store's)
  store <name> <minutes>     then a line per backup the runner runs before the merge, or command that takes it:
  backup <task and args>
  taken-by <task>            the unit's own production command takes the backup (the runner wants it in the plan)
  missing <store>: <why>     a part of the store with no backup yet (one line each) - the unit is blocked
  unknown <why>              labelled one-way, its name no store's - blocked (a new kind of store is decided in the table)
Exit 1: the table not read, or not as described (the runner blocks the unit - fails closed).
Env: UPGRADE_STORES_TABLE (another table - its harness's)
"""
import json
import os
import re
import sys

TABLE = os.environ.get("UPGRADE_STORES_TABLE") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "upgrade-stores.json")


def main(argv):
    if len(argv) != 3:
        sys.exit("usage: upgrade-stores.py <unit> <labels>")
    unit, labels = argv[1], set(filter(None, argv[2].split(",")))
    try:
        stores = json.load(open(TABLE, encoding="utf-8"))["stores"]
        for s in stores:
            if not (isinstance(s["store"], str) and isinstance(s["units"], str) and isinstance(s["packages"], list)
                    and s["packages"] and isinstance(s["backups"], list) and isinstance(s["missing"], list)
                    and isinstance(s["taken_by"], list) and isinstance(s["minutes"], int) and s["minutes"] >= 0
                    and (s["backups"] or s["missing"] or s["taken_by"])):
                raise ValueError(f"{s.get('store')}: store, units, packages, backups, taken_by, minutes and missing - "
                                 "backups, taken_by or missing not empty")
            re.compile(s["units"])
    except (OSError, ValueError, KeyError, TypeError, re.error) as e:
        sys.exit(f"the table {TABLE} not read: {e}")
    named = [s for s in stores if re.search(s["units"], unit)]
    if not named:
        if "one-way" in labels:
            print("unknown a one-way unit of no store scripts/upgrade-stores.json names - its store, backups or missing parts, decided there")
        else:
            print("none")
        return
    if len(named) > 1:
        sys.exit(f"{unit}: named by more than one store ({', '.join(s['store'] for s in named)})")
    s = named[0]
    if s["missing"]:
        for why in s["missing"]:
            print(f"missing {s['store']}: {why}")
        return
    print(f"store {s['store']} {s['minutes']}")
    for b in s["backups"]:
        print(f"backup {b}")
    for c in s["taken_by"]:
        print(f"taken-by {c}")


if __name__ == "__main__":
    main(sys.argv)
