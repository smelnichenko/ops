-- the application role owning its database and everything in it - psql variables: app (the role and its database's
-- name), pw (its password as a SCRAM verifier: no password reaches the server, nor its log when a statement fails);
-- run again: nothing to give, the verifier set again
SELECT format('CREATE ROLE %I LOGIN', :'app') WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'app') \gexec
SELECT format('ALTER ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD %L', :'app', :'pw') \gexec
SELECT format('ALTER DATABASE %I OWNER TO %I', :'app', :'app') \gexec
\connect :app
-- schemas first, then tables (an identity or a serial column's sequence goes with its table, an index with it), then
-- whatever is left
SELECT format('ALTER SCHEMA %I OWNER TO %I', nspname, :'app')
  FROM pg_namespace WHERE nspname NOT IN ('pg_catalog', 'information_schema', 'public') AND nspname !~ '^pg_'
   AND nspowner <> (SELECT oid FROM pg_roles WHERE rolname = :'app') \gexec
SELECT format('ALTER %s %s OWNER TO %I',
              CASE c.relkind WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'f' THEN 'FOREIGN TABLE'
                             WHEN 'c' THEN 'TYPE' ELSE 'TABLE' END,
              c.oid::regclass, :'app')
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND n.nspname !~ '^pg_toast'
   AND c.relkind IN ('r', 'p', 'v', 'm', 'f', 'c') AND c.relowner <> (SELECT oid FROM pg_roles WHERE rolname = :'app')
 ORDER BY c.relkind \gexec
SELECT format('ALTER SEQUENCE %s OWNER TO %I', c.oid::regclass, :'app')
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND c.relkind = 'S'
   AND c.relowner <> (SELECT oid FROM pg_roles WHERE rolname = :'app') \gexec
SELECT format('ALTER ROUTINE %s OWNER TO %I', p.oid::regprocedure, :'app')
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
   AND p.proowner <> (SELECT oid FROM pg_roles WHERE rolname = :'app') \gexec
-- an enum, a domain, a range (its multirange goes with it; an array type with its element; a composite type above)
SELECT format('ALTER TYPE %s OWNER TO %I', t.oid::regtype, :'app')
  FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
 WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND n.nspname !~ '^pg_toast'
   AND t.typtype IN ('e', 'd', 'r') AND t.typowner <> (SELECT oid FROM pg_roles WHERE rolname = :'app') \gexec
-- anything left to another role - a relation, a function, a type, a schema, the database itself: the run fails
SELECT (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND n.nspname !~ '^pg_toast'
           AND c.relowner <> r.oid)
     + (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND p.proowner <> r.oid)
     + (SELECT count(*) FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
         WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND n.nspname !~ '^pg_toast'
           AND t.typtype IN ('e', 'd', 'r', 'm') AND t.typowner <> r.oid)
     + (SELECT count(*) FROM pg_namespace
         WHERE nspname NOT IN ('pg_catalog', 'information_schema', 'public') AND nspname !~ '^pg_' AND nspowner <> r.oid)
     + (SELECT count(*) FROM pg_database WHERE datname = current_database() AND datdba <> r.oid)
       AS left_to_others
  FROM pg_roles r WHERE r.rolname = :'app' \gset
SELECT :left_to_others > 0 AS some_left \gset
\if :some_left
  \echo NOT ALL OWNED: :left_to_others object(s) of another role
  SELECT 1/0;
\endif
