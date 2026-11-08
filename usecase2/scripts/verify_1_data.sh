#!/usr/bin/env bash
# verify_1_data.sh - Is the data complete? One SQL: row count, sums and a checksum of every table.
# Run before and after the upgrade and compare the two outputs.
set -euo pipefail
DB="${DB_NAME:-shopdb}"

sudo -u postgres psql -d "$DB" -x -v ON_ERROR_STOP=1 <<'SQL'
SELECT (SELECT count(*) FROM shop.product_reviews)       AS reviews,
       (SELECT sum(length(body)) FROM shop.product_reviews)       AS review_chars,
       (SELECT sum(octet_length(body)) FROM shop.product_reviews) AS review_bytes,
       (SELECT md5(string_agg(md5(body), '' ORDER BY review_id))
          FROM shop.product_reviews)                     AS md5_review_bodies,
       (SELECT count(*) FROM shop.customers)             AS customers,
       (SELECT count(*) FROM shop.products)              AS products,
       (SELECT count(*) FROM shop.orders)                AS orders,
       (SELECT count(*) FROM shop.order_items)           AS order_items,
       (SELECT count(*) FROM shop.payments)              AS payments,
       (SELECT count(*) FROM shop.inventory_movements)   AS inventory_movements,
       (SELECT count(*) FROM shop.review_votes)          AS review_votes,
       (SELECT sum(total_amount) FROM shop.orders)       AS sum_orders,
       (SELECT sum(quantity * unit_price) FROM shop.order_items) AS sum_items,
       (SELECT sum(amount) FROM shop.payments)           AS sum_payments,
       (SELECT md5(string_agg(c::text, '|' ORDER BY customer_id))
          FROM shop.customers c WHERE customer_id <= 1000) AS md5_customers,
       (SELECT md5(string_agg(o::text, '|' ORDER BY order_id))
          FROM shop.orders o WHERE order_id <= 5000)     AS md5_orders;
SQL
