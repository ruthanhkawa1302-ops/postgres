#!/usr/bin/env bash
# verify_2_index.sh - Do the indexes need a rebuild? One SQL: amcheck on every B-tree index
# in schema shop (raises an error if one is corrupt) + count of invalid indexes.
# amcheck is a contrib module shipped with postgresql-15; the script creates the extension
# if it is not there yet (it is harmless and can be dropped afterwards).
set -euo pipefail
DB="${DB_NAME:-shopdb}"

sudo -u postgres psql -d "$DB" -v ON_ERROR_STOP=1 -q -c 'CREATE EXTENSION IF NOT EXISTS amcheck;'

sudo -u postgres psql -d "$DB" -x -v ON_ERROR_STOP=1 <<'SQL'
SELECT (SELECT count(*) FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'shop')                                     AS total_indexes,
       (SELECT count(*) FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'shop' AND NOT i.indisvalid)                AS invalid_indexes,
       (SELECT count(*) FROM (
          SELECT bt_index_check(c.oid, true)
            FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN pg_am am ON am.oid = c.relam
           WHERE n.nspname = 'shop' AND am.amname = 'btree' AND i.indisvalid) t) AS btree_checked_ok;
SQL
