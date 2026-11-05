#!/usr/bin/env bash
# verify_1_data.sh - Is the review data complete? One SQL: row count, text size and checksum.
# md5(body) reads the whole TOAST value but does not call substring().
set -euo pipefail
DB="${DB_NAME:-shopdb}"

sudo -u postgres psql -d "$DB" -x -v ON_ERROR_STOP=1 <<'SQL'
SELECT count(*)                                            AS reviews,
       sum(length(body))                                   AS total_chars,
       sum(octet_length(body))                             AS total_bytes,
       count(*) FILTER (WHERE octet_length(body) > 2000)   AS big_values,
       md5(string_agg(md5(body), '' ORDER BY review_id))   AS md5_all_bodies
FROM shop.product_reviews;
SQL
