-- =============================================================================
-- 03_insert_data.sql
-- Generate English demo data for schema "shop" (~100 MB with the default scale = 0.03).
--
-- Run (default size, takes ~1 min depending on disk/CPU):
--   sudo -u postgres psql -d shopdb -f sql/03_insert_data.sql
-- Bigger data set (0.44 = ~1.5 GB):
--   sudo -u postgres psql -d shopdb -v scale=0.44 -f sql/03_insert_data.sql
--
-- Row counts at scale = 0.03 (default; 0.44 = ~1.5 GB, 1 = 500,000 customers, 3,800,000 orders, ~3.4 GB)
--   countries 30 | categories 30 | customers 15,000 | products 1,500
--   orders 114,000 | order_items ~342,000 | payments ~114,000
--
-- The script is re-runnable: it truncates all shop tables first.
-- Data is generated so that the indexes from 02_schema.sql are useful:
--   * order_date / paid_at grow with the id         -> BRIN + range scans
--   * product popularity is skewed (power law)      -> idx_order_items_product
--   * ~13% orders are PENDING/PAID/PROCESSING       -> partial idx_orders_status_open
--   * products.attributes JSONB (color, size...)    -> GIN jsonb_path_ops
--   * emails unique case-insensitive                -> uq_customers_email_lower
-- =============================================================================
\set ON_ERROR_STOP on
\timing on

\if :{?scale}
\else
  \set scale 0.03
\endif
\echo '>>> scale =' :scale

SET search_path = shop, public;
SET synchronous_commit = off;
SET work_mem = '256MB';
SET maintenance_work_mem = '1GB';
SELECT setseed(0.20240509);

-- Volumes (stored as custom GUCs so PL/pgSQL can read them)
SELECT set_config('datagen.n_customers', greatest(1000, round(500000  * :scale))::text, false),
       set_config('datagen.n_products',  greatest(1000, round(50000   * :scale))::text, false),
       set_config('datagen.n_orders',    greatest(5000, round(3800000 * :scale))::text, false),
       set_config('datagen.batch',       '250000', false);

SELECT current_setting('datagen.n_customers') AS customers,
       current_setting('datagen.n_products')  AS products,
       current_setting('datagen.n_orders')    AS orders;

-- =============================================================================
-- 0. Helper schema (dropped at the end)
-- =============================================================================
DROP SCHEMA IF EXISTS datagen CASCADE;
CREATE SCHEMA datagen;

CREATE FUNCTION datagen.pick(text[]) RETURNS text
LANGUAGE sql VOLATILE AS $$ SELECT $1[1 + floor(random() * cardinality($1))::int] $$;

CREATE FUNCTION datagen.first_names() RETURNS text[] LANGUAGE sql IMMUTABLE AS $$ SELECT ARRAY[
 'James','Mary','John','Patricia','Robert','Jennifer','Michael','Linda','William','Elizabeth',
 'David','Barbara','Richard','Susan','Joseph','Jessica','Thomas','Sarah','Charles','Karen',
 'Christopher','Nancy','Daniel','Lisa','Matthew','Betty','Anthony','Margaret','Mark','Sandra',
 'Oliver','Emma','Lucas','Sophia','Liam','Olivia','Noah','Ava','Ethan','Mia']::text[] $$;

CREATE FUNCTION datagen.last_names() RETURNS text[] LANGUAGE sql IMMUTABLE AS $$ SELECT ARRAY[
 'Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis','Rodriguez','Martinez',
 'Hernandez','Lopez','Gonzalez','Wilson','Anderson','Thomas','Taylor','Moore','Jackson','Martin',
 'Lee','Perez','Thompson','White','Harris','Sanchez','Clark','Ramirez','Lewis','Robinson',
 'Walker','Young','Allen','King','Wright','Scott','Torres','Nguyen','Hill','Flores']::text[] $$;

CREATE FUNCTION datagen.email_domains() RETURNS text[] LANGUAGE sql IMMUTABLE AS $$ SELECT ARRAY[
 'gmail.com','yahoo.com','outlook.com','hotmail.com','icloud.com','proton.me','mail.com','example.org']::text[] $$;

CREATE FUNCTION datagen.brands() RETURNS text[] LANGUAGE sql IMMUTABLE AS $$ SELECT ARRAY[
 'Acme','Northwind','Contoso','Fabrikam','Globex','Initech','Umbrella','Stark','Wayne','Hooli',
 'BlueRiver','RedPeak','GreenLeaf','SilverLine','IronForge','UrbanNest','PureLife','SwiftGear','BrightHome','NovaTech']::text[] $$;

CREATE FUNCTION datagen.adjectives() RETURNS text[] LANGUAGE sql IMMUTABLE AS $$ SELECT ARRAY[
 'Premium','Classic','Ultra','Smart','Compact','Portable','Deluxe','Eco','Pro','Essential',
 'Advanced','Lightweight','Wireless','Vintage','Modern','Ergonomic','Waterproof','Foldable','Travel','Outdoor']::text[] $$;

CREATE FUNCTION datagen.colors() RETURNS text[] LANGUAGE sql IMMUTABLE AS $$ SELECT ARRAY[
 'Black','White','Silver','Red','Blue','Green','Grey','Navy','Beige','Pink']::text[] $$;

CREATE FUNCTION datagen.materials() RETURNS text[] LANGUAGE sql IMMUTABLE AS $$ SELECT ARRAY[
 'Plastic','Aluminum','Stainless Steel','Cotton','Leather','Wood','Glass','Polyester']::text[] $$;

CREATE FUNCTION datagen.sizes() RETURNS text[] LANGUAGE sql IMMUTABLE AS $$ SELECT ARRAY[
 'XS','S','M','L','XL','XXL','One Size']::text[] $$;

CREATE FUNCTION datagen.desc_phrases() RETURNS text[] LANGUAGE sql IMMUTABLE AS $$ SELECT ARRAY[
 'Designed for everyday use with a focus on durability and comfort.',
 'Built with high quality materials that stand the test of time.',
 'A perfect choice for home, office or travel.',
 'Easy to clean, easy to store and easy to love.',
 'Backed by a hassle-free warranty and friendly customer support.',
 'Its sleek design fits perfectly into any modern lifestyle.',
 'Lightweight yet sturdy, it is ideal for people on the move.',
 'Tested by experts and loved by thousands of happy customers.']::text[] $$;

-- Cities used for customers
CREATE TABLE datagen.cities (city_id int PRIMARY KEY, country_code char(2), city text);
INSERT INTO datagen.cities VALUES
 ( 1,'US','New York'),( 2,'US','Los Angeles'),( 3,'US','Chicago'),( 4,'CA','Toronto'),( 5,'CA','Vancouver'),
 ( 6,'MX','Mexico City'),( 7,'BR','Sao Paulo'),( 8,'AR','Buenos Aires'),( 9,'GB','London'),(10,'GB','Manchester'),
 (11,'DE','Berlin'),(12,'DE','Munich'),(13,'FR','Paris'),(14,'ES','Madrid'),(15,'IT','Milan'),
 (16,'NL','Amsterdam'),(17,'SE','Stockholm'),(18,'PL','Warsaw'),(19,'IE','Dublin'),(20,'CH','Zurich'),
 (21,'JP','Tokyo'),(22,'JP','Osaka'),(23,'KR','Seoul'),(24,'CN','Shanghai'),(25,'IN','Mumbai'),
 (26,'SG','Singapore'),(27,'VN','Ho Chi Minh City'),(28,'VN','Hanoi'),(29,'TH','Bangkok'),(30,'ID','Jakarta'),
 (31,'MY','Kuala Lumpur'),(32,'PH','Manila'),(33,'AU','Sydney'),(34,'AU','Melbourne'),(35,'NZ','Auckland'),
 (36,'ZA','Cape Town'),(37,'AE','Dubai'),(38,'EG','Cairo');

-- =============================================================================
-- 1. Clean previous data
-- =============================================================================
TRUNCATE shop.payments, shop.order_items, shop.orders, shop.products,
         shop.customers, shop.categories, shop.countries
RESTART IDENTITY CASCADE;

-- =============================================================================
-- 2. Reference data
-- =============================================================================
INSERT INTO shop.countries (country_code, country_name, region, currency_code, tax_rate) VALUES
 ('US','United States','North America','USD',0.0725), ('CA','Canada','North America','CAD',0.1300),
 ('MX','Mexico','North America','MXN',0.1600),        ('BR','Brazil','South America','BRL',0.1700),
 ('AR','Argentina','South America','ARS',0.2100),     ('GB','United Kingdom','Europe','GBP',0.2000),
 ('DE','Germany','Europe','EUR',0.1900),              ('FR','France','Europe','EUR',0.2000),
 ('ES','Spain','Europe','EUR',0.2100),                ('IT','Italy','Europe','EUR',0.2200),
 ('NL','Netherlands','Europe','EUR',0.2100),          ('SE','Sweden','Europe','SEK',0.2500),
 ('PL','Poland','Europe','PLN',0.2300),               ('IE','Ireland','Europe','EUR',0.2300),
 ('CH','Switzerland','Europe','CHF',0.0810),          ('JP','Japan','Asia','JPY',0.1000),
 ('KR','South Korea','Asia','KRW',0.1000),            ('CN','China','Asia','CNY',0.1300),
 ('IN','India','Asia','INR',0.1800),                  ('SG','Singapore','Asia','SGD',0.0900),
 ('VN','Vietnam','Asia','VND',0.1000),                ('TH','Thailand','Asia','THB',0.0700),
 ('ID','Indonesia','Asia','IDR',0.1100),              ('MY','Malaysia','Asia','MYR',0.0800),
 ('PH','Philippines','Asia','PHP',0.1200),            ('AU','Australia','Oceania','AUD',0.1000),
 ('NZ','New Zealand','Oceania','NZD',0.1500),         ('ZA','South Africa','Africa','ZAR',0.1500),
 ('AE','United Arab Emirates','Middle East','AED',0.0500), ('EG','Egypt','Africa','EGP',0.1400);

-- 5 root categories (id 1..5) + 25 leaf categories (id 6..30)
INSERT INTO shop.categories (category_name, slug)
SELECT name, lower(regexp_replace(name, '[^A-Za-z0-9]+', '-', 'g'))
FROM unnest(ARRAY['Electronics','Home & Kitchen','Fashion','Sports & Outdoors','Office Supplies'])
     WITH ORDINALITY AS t(name, ord)
ORDER BY ord;

CREATE TABLE datagen.leaf (leaf_no int PRIMARY KEY, parent_id int, category_name text, noun text);
INSERT INTO datagen.leaf VALUES
 ( 1,1,'Smartphones','Smartphone'),( 2,1,'Laptops','Laptop'),( 3,1,'Headphones','Headphones'),( 4,1,'Cameras','Camera'),( 5,1,'Smartwatches','Smartwatch'),
 ( 6,2,'Cookware','Frying Pan'),( 7,2,'Furniture','Chair'),( 8,2,'Bedding','Pillow'),( 9,2,'Lighting','Desk Lamp'),(10,2,'Small Appliances','Blender'),
 (11,3,'Men Clothing','Jacket'),(12,3,'Women Clothing','Dress'),(13,3,'Shoes','Sneakers'),(14,3,'Bags','Backpack'),(15,3,'Accessories','Sunglasses'),
 (16,4,'Fitness','Yoga Mat'),(17,4,'Camping','Tent'),(18,4,'Cycling','Bike Helmet'),(19,4,'Team Sports','Football'),(20,4,'Water Sports','Swim Goggles'),
 (21,5,'Writing Instruments','Fountain Pen'),(22,5,'Paper Products','Notebook'),(23,5,'Desk Organizers','Desk Organizer'),(24,5,'Printers & Ink','Ink Cartridge'),(25,5,'Office Furniture','Standing Desk');

INSERT INTO shop.categories (parent_category_id, category_name, slug)
SELECT parent_id, category_name, lower(regexp_replace(category_name, '[^A-Za-z0-9]+', '-', 'g'))
FROM datagen.leaf ORDER BY leaf_no;

-- =============================================================================
-- 3. Customers
-- =============================================================================
\echo '>>> customers'
INSERT INTO shop.customers (customer_id, first_name, last_name, email, phone, gender, date_of_birth,
                            country_code, city, loyalty_tier, is_active, created_at)
SELECT g.id, g.fn, g.ln,
       lower(g.fn || '.' || g.ln || g.id || '@' || g.dom),
       '+' || (1 + g.id % 98) || '-' || lpad((g.id * 7919 % 10000000)::text, 7, '0'),
       (ARRAY['M','F','O'])[1 + (g.id % 3)::int],
       DATE '1950-01-01' + (random() * 20000)::int,
       c.country_code, c.city,
       CASE WHEN g.r < 0.55 THEN 'BRONZE' WHEN g.r < 0.85 THEN 'SILVER' WHEN g.r < 0.97 THEN 'GOLD' ELSE 'PLATINUM' END,
       random() > 0.03,
       timestamptz '2020-01-01' + interval '2190 days' * (g.id::float8 / current_setting('datagen.n_customers')::bigint)
FROM (
    SELECT id,
           datagen.pick(datagen.first_names())   AS fn,
           datagen.pick(datagen.last_names())    AS ln,
           datagen.pick(datagen.email_domains()) AS dom,
           1 + floor(random() * 38)::int         AS city_id,
           random()                              AS r
    FROM generate_series(1, current_setting('datagen.n_customers')::bigint) AS id
) g
JOIN datagen.cities c ON c.city_id = g.city_id;

SELECT setval(pg_get_serial_sequence('shop.customers', 'customer_id'), (SELECT max(customer_id) FROM shop.customers));

-- =============================================================================
-- 4. Products
-- =============================================================================
\echo '>>> products'
INSERT INTO shop.products (product_id, sku, product_name, description, category_id, brand,
                           unit_price, unit_cost, stock_qty, attributes, is_active, created_at, updated_at)
SELECT g.id,
       'SKU-' || lpad(g.id::text, 8, '0'),
       g.brand || ' ' || g.adj || ' ' || l.noun || ' ' || chr(65 + (g.id % 26)::int) || (100 + g.id % 900),
       g.adj || ' ' || lower(l.noun) || ' by ' || g.brand || '. '
         || datagen.pick(datagen.desc_phrases()) || ' ' || datagen.pick(datagen.desc_phrases()),
       5 + l.leaf_no,                                      -- leaf category id
       g.brand,
       g.price,
       round(g.price * (0.40 + random() * 0.40)::numeric, 2),
       CASE WHEN random() < 0.05 THEN 0 ELSE 10 + floor(random() * 990)::int END,
       jsonb_build_object(
           'color',           datagen.pick(datagen.colors()),
           'material',        datagen.pick(datagen.materials()),
           'size',            datagen.pick(datagen.sizes()),
           'warranty_months', (ARRAY[0, 6, 12, 24])[1 + (g.id % 4)::int]),
       random() > 0.05,
       g.created_at, g.created_at
FROM (
    SELECT id,
           datagen.pick(datagen.brands())     AS brand,
           datagen.pick(datagen.adjectives()) AS adj,
           1 + floor(random() * 25)::int      AS leaf_no,
           round((4.99 + power(random(), 3) * 1995)::numeric, 2) AS price,
           timestamptz '2020-01-01' + interval '1800 days' * (id::float8 / current_setting('datagen.n_products')::bigint) AS created_at
    FROM generate_series(1, current_setting('datagen.n_products')::bigint) AS id
) g
JOIN datagen.leaf l ON l.leaf_no = g.leaf_no;

SELECT setval(pg_get_serial_sequence('shop.products', 'product_id'), (SELECT max(product_id) FROM shop.products));

-- =============================================================================
-- 5. Orders, order_items, payments (batched, 1 COMMIT per batch)
-- =============================================================================
CREATE PROCEDURE datagen.load_orders()
LANGUAGE plpgsql AS $proc$
DECLARE
    v_total  bigint := current_setting('datagen.n_orders')::bigint;
    v_batch  bigint := current_setting('datagen.batch')::bigint;
    v_ncust  bigint := current_setting('datagen.n_customers')::bigint;
    v_nprod  bigint := current_setting('datagen.n_products')::bigint;
    v_start  timestamptz := timestamptz '2021-01-01 00:00:00+00';
    v_span   interval    := timestamptz '2025-12-31 23:00:00+00' - timestamptz '2021-01-01 00:00:00+00';
    lo       bigint := 1;
    hi       bigint;
    t0       timestamptz;
BEGIN
    WHILE lo <= v_total LOOP
        hi := least(lo + v_batch - 1, v_total);
        t0 := clock_timestamp();

        -- order lines of this batch (1..5 lines per order, avg 3)
        CREATE TEMP TABLE tmp_items ON COMMIT DROP AS
        SELECT x.order_id, x.line_no, x.product_id, x.quantity, p.unit_price::numeric AS unit_price, x.discount_pct,
               round(x.quantity * p.unit_price * (1 - x.discount_pct / 100), 2) AS line_total
        FROM (
            SELECT o.id AS order_id,
                   l.line_no::smallint AS line_no,
                   1 + floor(v_nprod * power(random(), 2))::bigint AS product_id,      -- skewed popularity
                   1 + floor(random() * 3)::int AS quantity,
                   CASE WHEN random() < 0.20 THEN 5 * (1 + floor(random() * 4)) ELSE 0 END::numeric(5,2) AS discount_pct
            FROM generate_series(lo, hi) AS o(id)
            CROSS JOIN LATERAL generate_series(1, 1 + (hashint8(o.id) & 2147483647) % 5) AS l(line_no)
        ) x
        JOIN shop.products p ON p.product_id = x.product_id;

        -- order headers, totals computed from the lines
        INSERT INTO shop.orders (order_id, order_number, customer_id, order_status, sales_channel, order_date,
                                 subtotal, discount_amount, tax_amount, shipping_fee, total_amount,
                                 currency_code, updated_at)
        SELECT b.order_id,
               'ORD-' || lpad(b.order_id::text, 10, '0'),
               b.customer_id,
               CASE WHEN b.r < 0.70 THEN 'DELIVERED' WHEN b.r < 0.78 THEN 'SHIPPED'
                    WHEN b.r < 0.84 THEN 'CANCELLED' WHEN b.r < 0.87 THEN 'RETURNED'
                    WHEN b.r < 0.92 THEN 'PAID'      WHEN b.r < 0.96 THEN 'PROCESSING'
                    ELSE 'PENDING' END::shop.order_status,
               (ARRAY['WEB','WEB','WEB','MOBILE','MOBILE','STORE','PARTNER'])[1 + (b.order_id % 7)::int],
               b.order_date,
               t.gross,
               t.gross - t.net,
               round(t.net * 0.08, 2),
               CASE WHEN t.net >= 100 THEN 0 ELSE 4.99 END,
               t.net + round(t.net * 0.08, 2) + CASE WHEN t.net >= 100 THEN 0 ELSE 4.99 END,
               'USD',
               b.order_date + random() * interval '10 days'
        FROM (
            SELECT o.id AS order_id,
                   1 + floor(random() * v_ncust)::bigint AS customer_id,
                   v_start + v_span * (o.id::float8 / v_total) + random() * interval '3 hours' AS order_date,
                   random() AS r
            FROM generate_series(lo, hi) AS o(id)
        ) b
        JOIN (SELECT order_id, sum(quantity * unit_price) AS gross, sum(line_total) AS net
              FROM tmp_items GROUP BY order_id) t USING (order_id)
        ORDER BY b.order_id;

        INSERT INTO shop.order_items (order_id, line_no, product_id, quantity, unit_price, discount_pct, line_total)
        SELECT order_id, line_no, product_id, quantity, unit_price, discount_pct, line_total
        FROM tmp_items
        ORDER BY order_id, line_no;

        -- payments: one per non-pending order + a failed attempt for 4% of orders
        INSERT INTO shop.payments (order_id, payment_method, payment_status, amount, transaction_ref, paid_at)
        SELECT o.order_id, v.method, v.status, o.total_amount, v.ref, v.paid_at
        FROM shop.orders o
        CROSS JOIN LATERAL (
            SELECT (ARRAY['CREDIT_CARD','CREDIT_CARD','DEBIT_CARD','PAYPAL','BANK_TRANSFER','CASH_ON_DELIVERY'])[1 + (o.order_id % 6)::int] AS method,
                   'FAILED' AS status,
                   'TXN-' || o.order_id || '-0' AS ref,
                   o.order_date + interval '1 minute' AS paid_at
            WHERE o.order_id % 25 = 0
            UNION ALL
            SELECT (ARRAY['CREDIT_CARD','CREDIT_CARD','DEBIT_CARD','PAYPAL','BANK_TRANSFER','CASH_ON_DELIVERY'])[1 + ((o.order_id + 3) % 6)::int],
                   CASE WHEN o.order_status IN ('CANCELLED', 'RETURNED') THEN 'REFUNDED' ELSE 'CAPTURED' END,
                   'TXN-' || o.order_id || '-1',
                   o.order_date + interval '5 minutes'
            WHERE o.order_status <> 'PENDING'
        ) v
        WHERE o.order_id BETWEEN lo AND hi
        ORDER BY o.order_id;

        COMMIT;
        RAISE NOTICE 'orders % - % / % loaded in %', lo, hi, v_total, clock_timestamp() - t0;
        lo := hi + 1;
    END LOOP;
END
$proc$;

\echo '>>> orders / order_items / payments'
CALL datagen.load_orders();

SELECT setval(pg_get_serial_sequence('shop.orders', 'order_id'), (SELECT max(order_id) FROM shop.orders));

-- =============================================================================
-- 6. Cleanup + statistics
-- =============================================================================
DROP SCHEMA datagen CASCADE;

\echo '>>> VACUUM ANALYZE (may take a few minutes)'
VACUUM (ANALYZE) shop.countries, shop.categories, shop.customers, shop.products,
                 shop.orders, shop.order_items, shop.payments;

\echo '>>> Row counts'
SELECT 'countries' AS table_name, count(*) FROM shop.countries
UNION ALL SELECT 'categories',  count(*) FROM shop.categories
UNION ALL SELECT 'customers',   count(*) FROM shop.customers
UNION ALL SELECT 'products',    count(*) FROM shop.products
UNION ALL SELECT 'orders',      count(*) FROM shop.orders
UNION ALL SELECT 'order_items', count(*) FROM shop.order_items
UNION ALL SELECT 'payments',    count(*) FROM shop.payments;

\echo '>>> Size'
SELECT pg_size_pretty(pg_database_size(current_database())) AS database_size;
SELECT c.relname,
       pg_size_pretty(pg_table_size(c.oid))   AS table_size,
       pg_size_pretty(pg_indexes_size(c.oid)) AS index_size,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'shop' AND c.relkind = 'r'
ORDER BY pg_total_relation_size(c.oid) DESC;
