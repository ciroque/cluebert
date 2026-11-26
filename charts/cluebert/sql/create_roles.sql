-- Creates Cluebert's database and the two roles that use it, so neither the
-- app nor people browsing the data connect as `postgres`.
--
--   clueberth_rw  The app. Owns the database and its `public` schema, so the
--                 migrate Job can create and change tables, and the app can
--                 read and write rows.
--   clueberth_r   Read-only, for people and tools (psql, dashboards, backup
--                 checks). It can read every table in `public`, including
--                 tables created by later migrations, and change nothing.
--                 The app never uses it.
--
-- Run it as a superuser (`postgres`) with psql 15 or later. The passwords
-- are read from the environment, so they are never on the command line or
-- in this file:
--
--   export CLUEBERTH_RW_PASSWORD=...   # required
--   export CLUEBERTH_R_PASSWORD=...    # required
--   export CLUEBERTH_DB_NAME=...       # optional, default "cluebert"
--
--   psql -h "$DB_HOST" -U postgres -d postgres -X -f charts/cluebert/sql/create_roles.sql
--
-- It is safe to run again. Each run sets both passwords to the values in the
-- environment, so rotating a password is: change it, re-run this, then
-- `helm upgrade` with the new rw password. It also takes ownership of
-- anything in the database's `public` schema that `postgres` or another role
-- created, such as tables migrated before this script was run.
--
-- The passwords are sent to the server in CREATE/ALTER ROLE statements, so
-- they appear in the server log if it logs DDL (log_statement = 'ddl' or
-- 'all'). Postgres stores them as SCRAM hashes.

\set ON_ERROR_STOP on

\set rw_password ''
\set r_password ''
\set dbname cluebert
\getenv rw_password CLUEBERTH_RW_PASSWORD
\getenv r_password CLUEBERTH_R_PASSWORD
\getenv dbname CLUEBERTH_DB_NAME

SELECT :'rw_password' = '' AS rw_missing, :'r_password' = '' AS r_missing \gset
\if :rw_missing
  DO $$ BEGIN RAISE EXCEPTION 'CLUEBERTH_RW_PASSWORD is not set. Nothing was changed.'; END $$;
\endif
\if :r_missing
  DO $$ BEGIN RAISE EXCEPTION 'CLUEBERTH_R_PASSWORD is not set. Nothing was changed.'; END $$;
\endif

-- Roles. Created without a password, then given one, so a re-run updates it.

SELECT 'CREATE ROLE clueberth_rw'
 WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'clueberth_rw') \gexec
SELECT 'CREATE ROLE clueberth_r'
 WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'clueberth_r') \gexec

SELECT format(
  'ALTER ROLE clueberth_rw LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD %L',
  :'rw_password') \gexec
SELECT format(
  'ALTER ROLE clueberth_r LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD %L',
  :'r_password') \gexec

-- The database, owned by the app's role. Only these two roles may connect.

SELECT format('CREATE DATABASE %I OWNER clueberth_rw', :'dbname')
 WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'dbname') \gexec

ALTER DATABASE :"dbname" OWNER TO clueberth_rw;
REVOKE ALL ON DATABASE :"dbname" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"dbname" TO clueberth_r;

\connect :"dbname"
\set ON_ERROR_STOP on

-- The schema the migrations create tables in.

ALTER SCHEMA public OWNER TO clueberth_rw;
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- Anything already in `public` that another role owns becomes the app's.
-- Sequences that belong to a table column (Ecto's bigserial ids) move with
-- their table and can't be changed on their own.

DO $$
DECLARE
  object record;
BEGIN
  FOR object IN
    SELECT c.oid::regclass AS name,
           CASE c.relkind
             WHEN 'S' THEN 'SEQUENCE'
             WHEN 'v' THEN 'VIEW'
             WHEN 'm' THEN 'MATERIALIZED VIEW'
             ELSE 'TABLE'
           END AS kind
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relkind IN ('r', 'p', 'v', 'm', 'S')
       AND pg_get_userbyid(c.relowner) <> 'clueberth_rw'
       AND NOT (c.relkind = 'S' AND EXISTS (
             SELECT FROM pg_depend d
              WHERE d.classid = 'pg_class'::regclass
                AND d.objid = c.oid
                AND d.deptype IN ('a', 'i')))
  LOOP
    EXECUTE format('ALTER %s %s OWNER TO clueberth_rw', object.kind, object.name);
  END LOOP;
END
$$;

-- Read-only access: every existing table and sequence, and, through default
-- privileges, every one clueberth_rw creates from now on.

GRANT USAGE ON SCHEMA public TO clueberth_r;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO clueberth_r;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO clueberth_r;

ALTER DEFAULT PRIVILEGES FOR ROLE clueberth_rw IN SCHEMA public
  GRANT SELECT ON TABLES TO clueberth_r;
ALTER DEFAULT PRIVILEGES FOR ROLE clueberth_rw IN SCHEMA public
  GRANT SELECT ON SEQUENCES TO clueberth_r;

\echo
\echo 'Done. Database ':dbname' is owned by clueberth_rw; clueberth_r can read it.'
