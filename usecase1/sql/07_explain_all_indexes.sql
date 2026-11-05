-- =============================================================================
-- 07_explain_all_indexes.sql
-- Mỗi index trong schema shop (27 index) có 1 câu EXPLAIN ANALYZE.
-- Trong plan phải thấy đúng tên index ghi ở dòng "-- Index:" phía trên câu lệnh
-- (Index Scan / Index Only Scan / Bitmap Index Scan using <tên index>).
--
-- Chạy:  sudo -u postgres psql -X -d shopdb -f sql/07_explain_all_indexes.sql
-- Chạy trên 16.2 (trước) và 16.3 (sau), plan phải dùng cùng index như nhau.
--
-- Các câu chỉ đọc dữ liệu, không ghi gì. Bảng nhỏ (products, warehouses, ...) planner
-- có thể chọn seq scan vì rẻ hơn, nên file tắt seq scan để buộc dùng index nếu index dùng được.
-- =============================================================================

\set ON_ERROR_STOP on
\pset pager off

VACUUM (ANALYZE);          -- thống kê mới + visibility map (cho Index Only Scan)
SET enable_seqscan = off;

-- -----------------------------------------------------------------------------
-- audit_log
-- -----------------------------------------------------------------------------
\echo '>>> 01 audit_log_pkey'
-- Index: audit_log_pkey
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM shop.audit_log WHERE audit_id = 1;

-- -----------------------------------------------------------------------------
-- categories, countries
-- -----------------------------------------------------------------------------
\echo '>>> 02 categories_pkey'
-- Index: categories_pkey
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM shop.categories WHERE category_id = 1;

\echo '>>> 03 countries_pkey'
-- Index: countries_pkey
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM shop.countries
WHERE country_code = (SELECT min(country_code) FROM shop.countries);

-- -----------------------------------------------------------------------------
-- customers
-- -----------------------------------------------------------------------------
\echo '>>> 04 customers_pkey'
-- Index: customers_pkey
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM shop.customers WHERE customer_id = 100;

\echo '>>> 05 uq_customers_email_lower  (unique expression index)'
-- Index: uq_customers_email_lower
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM shop.customers
WHERE lower(email) = (SELECT lower(email) FROM shop.customers WHERE customer_id = 1);

-- -----------------------------------------------------------------------------
-- products
-- -----------------------------------------------------------------------------
\echo '>>> 06 products_pkey'
-- Index: products_pkey
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM shop.products WHERE product_id = 10;

\echo '>>> 07 products_sku_key'
-- Index: products_sku_key
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM shop.products
WHERE sku = (SELECT sku FROM shop.products WHERE product_id = 1);

\echo '>>> 08 idx_products_category_price  (composite B-tree)'
-- Index: idx_products_category_price
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM shop.products WHERE category_id = 5 AND unit_price BETWEEN 10 AND 50;

\echo '>>> 09 idx_products_attributes_gin  (GIN jsonb_path_ops)'
-- Index: idx_products_attributes_gin
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM shop.products
WHERE attributes @> (SELECT attributes FROM shop.products WHERE product_id = 1);

\echo '>>> 10 idx_products_name_trgm  (GIN pg_trgm)'
-- Index: idx_products_name_trgm
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM shop.products WHERE product_name ILIKE '%phone%';

-- -----------------------------------------------------------------------------
-- orders
-- -----------------------------------------------------------------------------
\echo '>>> 11 orders_pkey'
-- Index: orders_pkey
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM shop.orders WHERE order_id = 1000;

\echo '>>> 12 orders_order_number_key'
-- Index: orders_order_number_key
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM shop.orders
WHERE order_number = (SELECT order_number FROM shop.orders WHERE order_id = 1000);

\echo '>>> 13 idx_orders_customer_date  (covering INCLUDE -> Index Only Scan)'
-- Index: idx_orders_customer_date
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_status, total_amount
FROM shop.orders WHERE customer_id = 100 ORDER BY order_date DESC;

\echo '>>> 14 idx_orders_status_open  (partial index)'
-- Index: idx_orders_status_open
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM shop.orders WHERE order_status = 'PENDING' ORDER BY order_date LIMIT 10;

-- -----------------------------------------------------------------------------
-- order_items
-- -----------------------------------------------------------------------------
\echo '>>> 15 order_items_pkey'
-- Index: order_items_pkey
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM shop.order_items WHERE order_item_id = 1000;

\echo '>>> 16 uq_order_items_order_line  (unique composite)'
-- Index: uq_order_items_order_line
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM shop.order_items WHERE order_id = 1000 AND line_no = 1;

\echo '>>> 17 idx_order_items_product'
-- Index: idx_order_items_product
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM shop.order_items WHERE product_id = 10;

-- -----------------------------------------------------------------------------
-- payments
-- -----------------------------------------------------------------------------
\echo '>>> 18 payments_pkey'
-- Index: payments_pkey
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM shop.payments WHERE payment_id = 1000;

\echo '>>> 19 idx_payments_order'
-- Index: idx_payments_order
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM shop.payments WHERE order_id = 1000;

\echo '>>> 20 idx_payments_paid_at_brin  (BRIN)'
-- Index: idx_payments_paid_at_brin
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM shop.payments
WHERE paid_at >= (SELECT max(paid_at) - interval '1 day' FROM shop.payments);

\echo '>>> 21 idx_payments_txn_ref_hash  (Hash)'
-- Index: idx_payments_txn_ref_hash
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM shop.payments
WHERE transaction_ref = (SELECT max(transaction_ref) FROM shop.payments);

-- -----------------------------------------------------------------------------
-- promotions
-- -----------------------------------------------------------------------------
\echo '>>> 22 promotions_pkey'
-- Index: promotions_pkey
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM shop.promotions WHERE promotion_id = 1;

\echo '>>> 23 promotions_promo_code_key  (unique citext)'
-- Index: promotions_promo_code_key
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM shop.promotions WHERE promo_code = 'summer10';

\echo '>>> 24 ex_promotions_no_overlap  (exclusion constraint, GiST btree_gist)'
-- Index: ex_promotions_no_overlap
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM shop.promotions
WHERE product_id = 5
  AND valid_during && tstzrange(now() - interval '1 year', now() + interval '1 year');

-- -----------------------------------------------------------------------------
-- warehouses
-- -----------------------------------------------------------------------------
\echo '>>> 25 warehouses_pkey'
-- Index: warehouses_pkey
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM shop.warehouses WHERE warehouse_id = 1;

\echo '>>> 26 idx_warehouses_location  (GiST point, KNN)'
-- Index: idx_warehouses_location
EXPLAIN (ANALYZE, BUFFERS)
SELECT warehouse_code FROM shop.warehouses ORDER BY location <-> point(106.7, 10.8) LIMIT 3;

-- -----------------------------------------------------------------------------
-- materialized view
-- -----------------------------------------------------------------------------
\echo '>>> 27 uq_mv_daily_sales  (unique index on materialized view)'
-- Index: uq_mv_daily_sales
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM shop.mv_daily_sales
WHERE sales_date = (SELECT max(sales_date) FROM shop.mv_daily_sales)
  AND sales_channel = 'WEB';

RESET enable_seqscan;
\echo '>>> Xong: 27 câu EXPLAIN ANALYZE'
