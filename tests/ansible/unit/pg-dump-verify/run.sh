#!/bin/bash
# tests/ansible/upgrade/files/pg-dump-verify.py on a small pg_dumpall (two databases, a table whose quoted name has a
# space, one with a quote in it) and a stub psql answering each table's count from a file: the counts as in the dump
# pass; a table short of a row fails naming it - the spaced and quoted names too, which the reader once skipped
# without a word; a COPY line it cannot read fails instead of being skipped; a database missing fails.
set -u
H=$(cd "$(dirname "$0")" && pwd)
V=$(cd "$H/../../upgrade/files" && pwd)/pg-dump-verify.py
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cat > "$W/psql" <<'STUB'
#!/usr/bin/env python3
# psql -qAt -d <db> -F <sep> -c "select '<t>', count(*) from <t> union all ...": each table's count from $COUNTS
import json, os, re, sys
a = sys.argv[1:]
db, query = a[a.index("-d") + 1], a[a.index("-c") + 1]
counts = json.load(open(os.environ["COUNTS"]))
if db not in counts:
    sys.exit(f'psql: error: database "{db}" does not exist')
for t in re.findall(r"select '((?:[^']|'')*)', count\(\*\) from ", query):
    t = t.replace("''", "'")
    if t not in counts[db]:
        sys.exit(f"ERROR:  relation {t} does not exist")
    print(f"{t}\t{counts[db][t]}")
STUB
chmod +x "$W/psql"
dump() {  # dump <name> <extra COPY line, verbatim>: the dump, gzipped
  { printf '%s\n' '\connect app' 'COPY public.users (id, name) FROM stdin;' '1	a' '2	b' '\.' \
      'COPY public."audit log" (id) FROM stdin;' '1' '2' '3' '\.' \
      "COPY \"Odd\".\"it's \"\"x\"\"\" (\"a b\") FROM stdin;" '1' '\.' \
      'COPY public.empty  FROM stdin;' '\.' \
      '\connect "dbname='"'"'other db'"'"'"' 'COPY public.t (x) FROM stdin;' '7' '\.'
    [ -z "$2" ] || printf '%s\n' "$2" '1' '\.'; } | gzip > "$W/$1.sql.gz"
}
counts() {  # counts <variant>: the cluster's counts, as in the dump but for the variant
  python3 - "$1" > "$W/counts.json" <<'PY'
import json, sys
c = {"app": {"public.users": 2, 'public."audit log"': 3, '"Odd"."it\'s ""x"""': 1, "public.empty": 0},
     "other db": {"public.t": 1}}
v = sys.argv[1]
if v == "spaced-short":
    c["app"]['public."audit log"'] = 2
if v == "quoted-gone":
    del c["app"]['"Odd"."it\'s ""x"""']
if v == "db-gone":
    del c["other db"]
json.dump(c, sys.stdout)
PY
}
fails=0
expect() {  # expect <pass|fail> <name> <pattern> <dump>
  out=$(COUNTS="$W/counts.json" python3 "$V" "$W/$4.sql.gz" "$W/psql" 2>&1); rc=$?
  if { [ "$1" = pass ] && [ $rc = 0 ]; } || { [ "$1" = fail ] && [ $rc != 0 ]; }; then
    if grep -qF -- "$3" <<< "$out"; then echo "PASS $2"; return; fi
  fi
  echo "FAIL $2 (rc $rc): $out"; fails=$((fails + 1))
}
dump plain ""
counts as-dumped
expect pass "every table as in the dump" "2 databases, 5 tables, 7 rows" plain
counts spaced-short
expect fail "the spaced name short of a row" 'app.public."audit log": 2 rows, the dump has 3' plain
counts quoted-gone
expect fail "the quoted name not in the cluster" "relation \"Odd\".\"it's \"\"x\"\"\" does not exist" plain
counts db-gone
expect fail "a database missing" 'other db: psql: error: database "other db" does not exist' plain
dump unreadable 'COPY public."unterminated (x) FROM stdin;'
counts as-dumped
expect fail "a COPY line it cannot read" "a COPY line this cannot read" unreadable
# a dump with no table (an empty pg_dumpall, a truncated one) proves nothing; a COPY before any \connect is no
# pg_dumpall (its database unknown)
printf '%s\n' '\connect app' '-- nothing else' | gzip > "$W/notable.sql.gz"
counts as-dumped
expect fail "a dump with no table: fails" "no table in the dump" notable
printf '%s\n' 'COPY public.t (x) FROM stdin;' '1' '\.' | gzip > "$W/noconnect.sql.gz"
expect fail "a COPY before any \connect: fails" "a COPY before any" noconnect
echo "pg-dump-verify: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
