#!/usr/bin/env bash
# verify_3_function.sh - Do the functions still run? One SQL calls the main functions,
# aggregate and view, and prints a checksum of each result.
set -euo pipefail
DB="${DB_NAME:-shopdb}"

sudo -u postgres psql -d "$DB" -x -v ON_ERROR_STOP=1 <<'SQL'
SELECT shop.fn_customer_lifetime_value(1)                                   AS lifetime_value,
       (SELECT md5(shop.fn_get_order_details(1)::text))                     AS order_details,
       (SELECT md5(string_agg(r::text, '|')) FROM shop.fn_search_products(
          (SELECT product_name FROM shop.products WHERE product_id = 1), 10) r) AS search_products,
       (SELECT md5(string_agg(r::text, '|')) FROM shop.fn_similar_products(1, 10) r) AS similar_products,
       (SELECT md5(string_agg(r::text, '|')) FROM shop.fn_monthly_sales_pivot(
          (SELECT extract(year FROM min(order_date))::int FROM shop.orders)) r)     AS monthly_pivot,
       (SELECT md5(string_agg(r::text, '|')) FROM shop.fn_nearest_warehouses(10.8, 106.7, 3) r) AS nearest_wh,
       (SELECT shop.weighted_avg(unit_price, stock_qty) FROM shop.products)  AS weighted_avg,
       (SELECT count(*) FROM shop.v_order_summary)                          AS view_rows;
SQL
