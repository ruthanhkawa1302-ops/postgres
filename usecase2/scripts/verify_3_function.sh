#!/usr/bin/env bash
# verify_3_function.sh - Do all the functions and views still run? One SQL calls every
# function and view of the database and prints a checksum of each result.
set -euo pipefail
DB="${DB_NAME:-shopdb}"

sudo -u postgres psql -d "$DB" -x -v ON_ERROR_STOP=1 <<'SQL'
SELECT shop.fn_customer_order_total(1)                                      AS order_total_c1,
       (SELECT md5(string_agg(r::text, '|')) FROM shop.fn_top_products(10) r)          AS top_products,
       (SELECT md5(string_agg(r::text, '|')) FROM shop.fn_review_rating_summary(1) r)  AS rating_summary,
       (SELECT md5(string_agg(r::text, '|')) FROM shop.fn_monthly_revenue(2024) r)     AS monthly_revenue,
       (SELECT md5(string_agg(shop.fn_review_excerpt(review_id), '|' ORDER BY review_id))
          FROM shop.product_reviews)                                                   AS review_excerpt,
       (SELECT count(*) FROM shop.v_product_sales)                                     AS view_product_sales,
       (SELECT count(*) FROM shop.v_review_votes_summary)                              AS view_votes_summary,
       (SELECT count(*) FROM shop.v_review_excerpt)                                    AS view_review_excerpt,
       (SELECT md5(string_agg(excerpt, '|' ORDER BY review_id)) FROM shop.v_review_excerpt) AS md5_view_excerpt,
       (SELECT count(*) FROM pg_proc WHERE pronamespace = 'shop'::regnamespace
                                       AND proname = 'sp_cancel_order')                AS procedure_exists;
SQL
