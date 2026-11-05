#!/usr/bin/env bash
# verify_1_data.sh - Is the data complete? One SQL: row counts, sums and a checksum.
set -euo pipefail
DB="${DB_NAME:-shopdb}"

sudo -u postgres psql -d "$DB" -x -v ON_ERROR_STOP=1 <<'SQL'
SELECT (SELECT count(*) FROM shop.customers)   AS customers,
       (SELECT count(*) FROM shop.products)    AS products,
       (SELECT count(*) FROM shop.orders)      AS orders,
       (SELECT count(*) FROM shop.order_items) AS order_items,
       (SELECT count(*) FROM shop.payments)    AS payments,
       (SELECT sum(total_amount) FROM shop.orders)    AS sum_orders,
       (SELECT sum(line_total)   FROM shop.order_items) AS sum_items,
       (SELECT md5(string_agg(c::text, '|' ORDER BY customer_id))
          FROM shop.customers c WHERE customer_id <= 1000) AS md5_customers;
SQL
