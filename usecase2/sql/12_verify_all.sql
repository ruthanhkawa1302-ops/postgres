-- =============================================================================
-- 12_verify_all.sql
-- Plain SELECT / EXPLAIN ANALYZE only (no md5, no DO block). Run BEFORE and AFTER the upgrade
-- and compare the two outputs:
--
--   psql -X -d shopdb -f sql/12_verify_all.sql > /tmp/verify_before.txt 2>&1
--   (upgrade)
--   psql -X -d shopdb -f sql/12_verify_all.sql > /tmp/verify_after.txt  2>&1
--   diff /tmp/verify_before.txt /tmp/verify_after.txt
--
-- Sections: 1 data (one SELECT per table), 2 index (one EXPLAIN ANALYZE per index, 24),
--           3 function / procedure, 4 view, 5 structure.
-- EXPLAIN uses BUFFERS/COSTS/TIMING/SUMMARY OFF so the output has no time or cost numbers:
-- it shows the plan and the real row counts, which must be the same before and after.
-- Expected: identical files except the version line. On 15.16 the fn_review_excerpt and
-- v_review_excerpt statements fail with "invalid byte sequence for encoding UTF8".
-- =============================================================================
\echo '== 0. VERSION (only this part may differ)'
SELECT current_setting('server_version') AS server_version, current_setting('server_encoding') AS encoding;

-- =============================================================================
\echo '== 1. DATA: one SELECT per table'
-- =============================================================================
\echo '-- product_reviews'
SELECT count(*) AS rows, min(review_id) AS min_id, max(review_id) AS max_id, sum(rating) AS sum_rating,
       sum(length(body)) AS total_chars, sum(octet_length(body)) AS total_bytes
FROM shop.product_reviews;
\echo '-- customers'
SELECT count(*) AS rows, min(customer_id) AS min_id, max(customer_id) AS max_id,
       count(DISTINCT country) AS countries, min(created_at) AS first_created, max(created_at) AS last_created
FROM shop.customers;
\echo '-- products'
SELECT count(*) AS rows, min(product_id) AS min_id, max(product_id) AS max_id,
       sum(price) AS sum_price, sum(stock_qty) AS sum_stock, count(DISTINCT category) AS categories
FROM shop.products;
\echo '-- orders'
SELECT count(*) AS rows, min(order_id) AS min_id, max(order_id) AS max_id,
       sum(total_amount) AS sum_amount, count(*) FILTER (WHERE status = 'cancelled') AS cancelled,
       min(created_at) AS first_created, max(created_at) AS last_created
FROM shop.orders;
\echo '-- order_items'
SELECT count(*) AS rows, min(item_id) AS min_id, max(item_id) AS max_id,
       sum(quantity) AS sum_qty, sum(quantity * unit_price) AS sum_value
FROM shop.order_items;
\echo '-- payments'
SELECT count(*) AS rows, min(payment_id) AS min_id, max(payment_id) AS max_id,
       sum(amount) AS sum_amount, count(DISTINCT method) AS methods
FROM shop.payments;
\echo '-- inventory_movements'
SELECT count(*) AS rows, min(movement_id) AS min_id, max(movement_id) AS max_id,
       sum(delta) AS sum_delta, count(DISTINCT reason) AS reasons
FROM shop.inventory_movements;
\echo '-- review_votes'
SELECT count(*) AS rows, min(vote_id) AS min_id, max(vote_id) AS max_id,
       count(*) FILTER (WHERE is_helpful) AS helpful, count(DISTINCT review_id) AS reviews_voted
FROM shop.review_votes;

-- =============================================================================
\echo '== 2. INDEXES: one EXPLAIN ANALYZE per index (seq scan disabled to force the index)'
-- =============================================================================
SET enable_seqscan = off;

\echo '-- product_reviews_pkey'
EXPLAIN (ANALYZE) SELECT review_id, product_id, rating FROM shop.product_reviews WHERE review_id BETWEEN 10 AND 500;
\echo '-- idx_product_reviews_product'
EXPLAIN (ANALYZE) SELECT review_id, product_id, rating FROM shop.product_reviews WHERE product_id = 10;
\echo '-- customers_pkey'
EXPLAIN (ANALYZE) SELECT * FROM shop.customers WHERE customer_id BETWEEN 100 AND 900;
\echo '-- uq_customers_email_lower'
EXPLAIN (ANALYZE) SELECT * FROM shop.customers WHERE lower(email) = 'user500@example.com';
\echo '-- idx_customers_country'
EXPLAIN (ANALYZE) SELECT * FROM shop.customers WHERE country = 'VN';
\echo '-- products_pkey'
EXPLAIN (ANALYZE) SELECT * FROM shop.products WHERE product_id BETWEEN 50 AND 400;
\echo '-- products_sku_key'
EXPLAIN (ANALYZE) SELECT * FROM shop.products WHERE sku = 'SKU-000100';
\echo '-- idx_products_attributes_gin'
EXPLAIN (ANALYZE) SELECT * FROM shop.products WHERE attributes @> '{"color":"red"}';
\echo '-- idx_products_category_hash'
EXPLAIN (ANALYZE) SELECT * FROM shop.products WHERE category = 'audio';
\echo '-- orders_pkey'
EXPLAIN (ANALYZE) SELECT * FROM shop.orders WHERE order_id BETWEEN 1000 AND 3000;
\echo '-- idx_orders_customer_created'
EXPLAIN (ANALYZE) SELECT * FROM shop.orders WHERE customer_id = 77 ORDER BY created_at DESC;
\echo '-- idx_orders_open (partial)'
EXPLAIN (ANALYZE) SELECT * FROM shop.orders WHERE status IN ('new','paid') AND created_at < timestamptz '2024-06-10';
\echo '-- idx_orders_created_brin'
EXPLAIN (ANALYZE) SELECT * FROM shop.orders WHERE created_at BETWEEN timestamptz '2024-07-01' AND timestamptz '2024-07-03';
\echo '-- order_items_pkey'
EXPLAIN (ANALYZE) SELECT * FROM shop.order_items WHERE item_id BETWEEN 5000 AND 9000;
\echo '-- idx_order_items_order (covering)'
EXPLAIN (ANALYZE) SELECT order_id, product_id, quantity, unit_price FROM shop.order_items WHERE order_id BETWEEN 1234 AND 1300;
\echo '-- idx_order_items_product'
EXPLAIN (ANALYZE) SELECT * FROM shop.order_items WHERE product_id = 55;
\echo '-- payments_pkey'
EXPLAIN (ANALYZE) SELECT * FROM shop.payments WHERE payment_id BETWEEN 100 AND 2000;
\echo '-- idx_payments_order'
EXPLAIN (ANALYZE) SELECT * FROM shop.payments WHERE order_id BETWEEN 1234 AND 1300;
\echo '-- inventory_movements_pkey'
EXPLAIN (ANALYZE) SELECT * FROM shop.inventory_movements WHERE movement_id BETWEEN 100 AND 3000;
\echo '-- idx_inventory_product_created'
EXPLAIN (ANALYZE) SELECT * FROM shop.inventory_movements WHERE product_id = 17 ORDER BY created_at;
\echo '-- idx_inventory_meta_gin'
EXPLAIN (ANALYZE) SELECT * FROM shop.inventory_movements WHERE meta @> '{"warehouse":"WH3"}';
\echo '-- review_votes_pkey'
EXPLAIN (ANALYZE) SELECT * FROM shop.review_votes WHERE vote_id BETWEEN 100 AND 3000;
\echo '-- review_votes_review_id_customer_id_key'
EXPLAIN (ANALYZE) SELECT * FROM shop.review_votes WHERE review_id = 5 AND customer_id = 3;
\echo '-- idx_review_votes_review (partial)'
EXPLAIN (ANALYZE) SELECT * FROM shop.review_votes WHERE review_id = 5 AND is_helpful;

RESET enable_seqscan;

-- =============================================================================
\echo '== 3. FUNCTIONS / PROCEDURE: normal calls'
-- =============================================================================
\echo '-- fn_customer_order_total'
SELECT shop.fn_customer_order_total(1) AS customer_1, shop.fn_customer_order_total(77) AS customer_77, shop.fn_customer_order_total(9999) AS no_such_customer;
\echo '-- fn_top_products'
SELECT * FROM shop.fn_top_products(10);
\echo '-- fn_review_rating_summary'
SELECT * FROM shop.fn_review_rating_summary(1);
SELECT * FROM shop.fn_review_rating_summary(500);
\echo '-- fn_monthly_revenue'
SELECT * FROM shop.fn_monthly_revenue(2024);
SELECT * FROM shop.fn_monthly_revenue(2025);
\echo '-- fn_review_excerpt (single reviews; review 1 and every 30th from 19 are the ones hit by the 15.16 bug)'
SELECT shop.fn_review_excerpt(1) AS review_1, shop.fn_review_excerpt(2) AS review_2, shop.fn_review_excerpt(2, 100) AS review_2_long;
SELECT shop.fn_review_excerpt(19) AS review_19, shop.fn_review_excerpt(20) AS review_20;
\echo '-- fn_review_excerpt over ALL reviews (fails as a whole if any row fails)'
SELECT count(*) AS excerpts, sum(length(shop.fn_review_excerpt(review_id))) AS total_chars FROM shop.product_reviews;
\echo '-- sp_cancel_order: a procedure changes data, so only check that it exists'
SELECT p.oid::regprocedure AS routine, p.prokind AS kind FROM pg_proc p WHERE p.pronamespace = 'shop'::regnamespace ORDER BY 1::text;

-- =============================================================================
\echo '== 4. VIEWS'
-- =============================================================================
\echo '-- v_product_sales'
SELECT count(*) AS rows, sum(lines) AS lines, sum(units) AS units FROM shop.v_product_sales;
SELECT * FROM shop.v_product_sales ORDER BY product_id LIMIT 5;
\echo '-- v_review_votes_summary'
SELECT count(*) AS rows, sum(votes) AS votes, sum(helpful) AS helpful FROM shop.v_review_votes_summary;
SELECT * FROM shop.v_review_votes_summary ORDER BY review_id LIMIT 5;
\echo '-- v_review_excerpt (fails on 15.16)'
SELECT count(*) AS rows, sum(length(excerpt)) AS total_chars FROM shop.v_review_excerpt;
SELECT * FROM shop.v_review_excerpt ORDER BY review_id LIMIT 5;

-- =============================================================================
\echo '== 5. STRUCTURE'
-- =============================================================================
\echo '-- objects per type (r table, i index, v view, S sequence)'
SELECT relkind, count(*) FROM pg_class WHERE relnamespace = 'shop'::regnamespace GROUP BY relkind ORDER BY relkind;
\echo '-- all indexes: must all be valid and ready'
SELECT i.indexrelid::regclass AS index, i.indisvalid AS valid, i.indisready AS ready, pg_get_indexdef(i.indexrelid) AS definition
FROM pg_index i JOIN pg_class c ON c.oid = i.indrelid
WHERE c.relnamespace = 'shop'::regnamespace ORDER BY 1::text;
\echo '-- constraints'
SELECT conrelid::regclass AS table_name, conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint WHERE connamespace = 'shop'::regnamespace ORDER BY 1::text, 2;
\echo '-- sequences'
SELECT sequencename, last_value FROM pg_sequences WHERE schemaname = 'shop' ORDER BY 1;
\echo '-- extensions'
SELECT extname FROM pg_extension ORDER BY 1;
