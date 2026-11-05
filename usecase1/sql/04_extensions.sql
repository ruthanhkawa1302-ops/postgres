CREATE EXTENSION IF NOT EXISTS pg_trgm;            -- fuzzy text search (similarity, ILIKE index)
CREATE EXTENSION IF NOT EXISTS citext;             -- case-insensitive text type
CREATE EXTENSION IF NOT EXISTS hstore;             -- key/value type (audit diff)
CREATE EXTENSION IF NOT EXISTS tablefunc;          -- crosstab() pivot
CREATE EXTENSION IF NOT EXISTS btree_gist;         -- scalar types in GiST (exclusion constraint)
CREATE EXTENSION IF NOT EXISTS pgcrypto;           -- digest(), crypt(), gen_random_bytes()

-- B. Monitoring / integrity
CREATE EXTENSION IF NOT EXISTS pg_stat_statements; -- query statistics (needs preload)
CREATE EXTENSION IF NOT EXISTS amcheck;            -- verify B-tree / heap integrity

-- Result
SELECT e.extname, e.extversion, n.nspname AS schema
FROM pg_extension e
JOIN pg_namespace n ON n.oid = e.extnamespace
ORDER BY e.extname;
