#!/usr/bin/env python3
"""pg-dump-verify.py - a pg_dumpall replayed into a cluster: every table of every database holds the rows the dump has.

Reads the gzipped dump (its \\connect lines name the database, each COPY ... FROM stdin block's data lines up to \\. are
its table's rows), then counts each table in the cluster through the psql command given (it gets -d <database> -c
<query> appended, and must print unaligned tuples: psql -qAt). Prints the totals; exit 1 naming every table whose
count differs, and every database missing.

Usage: pg-dump-verify.py <dump.sql.gz> <psql command...>
"""
import gzip
import re
import subprocess
import sys

CONNECT = re.compile(r'^\\connect (?:-reuse-previous=on )?(?:"dbname=\'(?P<q>[^\']+)\'"|(?P<p>\S+))\s*$')
COPY = re.compile(r"^COPY (?P<table>\S+) \(.*\) FROM stdin;$")


def dump_counts(path):
    counts, db, table = {}, None, None
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if table is not None:
                if line == "\\.":
                    table = None
                else:
                    counts[db][table] += 1
                continue
            m = CONNECT.match(line)
            if m:
                db = m.group("q") or m.group("p")
                counts.setdefault(db, {})
                continue
            m = COPY.match(line)
            if m and db is not None:
                table = m.group("table")
                counts[db][table] = 0
    return counts


def cluster_counts(psql, db, tables):
    query = " union all ".join(f"select '{t.replace(chr(39), chr(39) * 2)}', count(*) from {t}" for t in tables)
    out = subprocess.run(psql + ["-d", db, "-F", "\t", "-c", query], capture_output=True, text=True)
    if out.returncode != 0:
        return None, out.stderr.strip()
    return {t: int(n) for t, n in (l.split("\t") for l in out.stdout.splitlines() if l)}, ""


def main():
    path, psql = sys.argv[1], sys.argv[2:]
    want = dump_counts(path)
    bad, tables, rows = [], 0, 0
    for db, counts in sorted(want.items()):
        if not counts:
            continue
        got, err = cluster_counts(psql, db, sorted(counts))
        if got is None:
            bad.append(f"{db}: {err}")
            continue
        for t, n in sorted(counts.items()):
            tables += 1
            rows += n
            if got.get(t) != n:
                bad.append(f"{db}.{t}: {got.get(t)} rows, the dump has {n}")
    if bad or not tables:
        print("\n".join(bad) or "no table in the dump")
        sys.exit(1)
    print(f"{len([d for d in want if want[d]])} databases, {tables} tables, {rows} rows - every table as in the dump")


if __name__ == "__main__":
    main()
