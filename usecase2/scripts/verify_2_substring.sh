#!/usr/bin/env bash
# verify_2_substring.sh - Does substring() still work on TOAST text with multi-byte characters?
# One DO block runs fn_review_excerpt() for every review and counts the failures.
# Expected: failed = 0 (15.6 and 15.17). On 15.16 the bug gives failed = 334.
set -euo pipefail
DB="${DB_NAME:-shopdb}"

sudo -u postgres psql -d "$DB" -v ON_ERROR_STOP=1 <<'SQL'
DO $$
DECLARE r bigint; ok int := 0; bad int := 0; first_bad bigint; first_err text;
BEGIN
  FOR r IN SELECT review_id FROM shop.product_reviews ORDER BY review_id LOOP
    BEGIN
      PERFORM shop.fn_review_excerpt(r);
      ok := ok + 1;
    EXCEPTION WHEN OTHERS THEN
      bad := bad + 1;
      IF first_bad IS NULL THEN first_bad := r; first_err := SQLERRM; END IF;
    END;
  END LOOP;
  RAISE NOTICE 'version=%  ok=%  failed=%  first_failed_review=%  error=%',
               current_setting('server_version'), ok, bad, first_bad, first_err;
END $$;
SQL
