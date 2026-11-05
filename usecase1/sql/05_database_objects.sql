-- =============================================================================
-- 05_database_objects.sql
-- Database objects built on top of the loaded data + extensions.
-- Goal: VARIETY, not quantity - a few objects of every kind:
--   extension index, sequence, composite type, custom aggregate, new tables
--   (hstore audit, btree_gist exclusion + citext, geometric point + GiST),
--   materialized view, views, functions, procedures, triggers, event trigger,
--   roles / grants / row level security, extended statistics.
--
-- Run (after 02, 03, 04):
--   sudo -u postgres psql -d shopdb -f sql/05_database_objects.sql
--
-- Re-runnable: objects are dropped / replaced before being created.
-- Only contrib extensions (sql/04_extensions.sql) are required.
-- =============================================================================
\set ON_ERROR_STOP on
\timing on

SET search_path = shop, public;
SET maintenance_work_mem = '1GB';
SET work_mem = '256MB';

-- -----------------------------------------------------------------------------
-- 0. Cleanup for re-run
-- -----------------------------------------------------------------------------
DROP EVENT TRIGGER IF EXISTS evt_ddl_audit;
DROP MATERIALIZED VIEW IF EXISTS shop.mv_daily_sales CASCADE;
DROP VIEW IF EXISTS shop.v_order_summary, shop.v_customers_masked, shop.v_active_products CASCADE;
DROP TABLE IF EXISTS shop.audit_log, shop.promotions, shop.warehouses CASCADE;
DROP TYPE IF EXISTS shop.order_line_input CASCADE;
DROP SEQUENCE IF EXISTS shop.order_number_seq;

-- =============================================================================
-- 1. Extension-based index on an existing table
-- =============================================================================
-- pg_trgm: fuzzy / ILIKE '%...%' search on product names
CREATE INDEX IF NOT EXISTS idx_products_name_trgm
    ON shop.products USING gin (product_name gin_trgm_ops);

-- =============================================================================
-- 2. Sequence, composite type, custom aggregate
-- =============================================================================
CREATE SEQUENCE shop.order_number_seq AS bigint;
SELECT setval('shop.order_number_seq', (SELECT coalesce(max(order_id), 0) + 1 FROM shop.orders), false);

CREATE TYPE shop.order_line_input AS (product_id bigint, quantity integer);

-- weighted_avg(value, weight), e.g. weighted_avg(unit_price, quantity)
CREATE OR REPLACE FUNCTION shop.wavg_sfunc(state numeric[], val numeric, weight numeric)
RETURNS numeric[] LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE WHEN val IS NULL OR weight IS NULL THEN state
                ELSE ARRAY[state[1] + val * weight, state[2] + weight] END
$$;
CREATE OR REPLACE FUNCTION shop.wavg_ffunc(state numeric[])
RETURNS numeric LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE WHEN state[2] = 0 THEN NULL ELSE round(state[1] / state[2], 4) END
$$;
CREATE OR REPLACE AGGREGATE shop.weighted_avg(numeric, numeric) (
    SFUNC = shop.wavg_sfunc, STYPE = numeric[], FINALFUNC = shop.wavg_ffunc, INITCOND = '{0,0}'
);

-- =============================================================================
-- 3. New tables / columns
-- =============================================================================
-- 3.1 Audit trail: row changes (hstore diff) + DDL commands (event trigger)
CREATE TABLE shop.audit_log (
    audit_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name     text NOT NULL,
    operation      text NOT NULL CHECK (operation IN ('UPDATE', 'DELETE', 'DDL')),
    row_pk         text,
    changed_fields hstore,                      -- hstore: only the columns that changed
    detail         jsonb,                       -- old row (DELETE) or DDL info
    changed_by     text NOT NULL DEFAULT session_user,
    changed_at     timestamptz NOT NULL DEFAULT now()
);

-- 3.2 Promotions: citext code + btree_gist exclusion (no overlapping periods per product)
CREATE TABLE shop.promotions (
    promotion_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    promo_code    citext NOT NULL UNIQUE,                         -- 'SUMMER10' = 'summer10'
    product_id    bigint NOT NULL REFERENCES shop.products (product_id) ON DELETE CASCADE,
    discount_pct  numeric(5,2) NOT NULL CHECK (discount_pct > 0 AND discount_pct < 100),
    valid_during  tstzrange NOT NULL,
    CONSTRAINT ex_promotions_no_overlap
        EXCLUDE USING gist (product_id WITH =, valid_during WITH &&)
);

-- 3.3 Warehouses with a built-in geometric point (x = longitude, y = latitude) + GiST index
CREATE TABLE shop.warehouses (
    warehouse_id   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    warehouse_code varchar(10)  NOT NULL,
    city           varchar(100) NOT NULL,
    country_code   char(2) NOT NULL REFERENCES shop.countries (country_code),
    location       point NOT NULL
);
CREATE INDEX idx_warehouses_location ON shop.warehouses USING gist (location);

-- =============================================================================
-- 4. Data for the new objects
-- =============================================================================
-- 2 non-overlapping promotions for each of the first 5,000 products
INSERT INTO shop.promotions (promo_code, product_id, discount_pct, valid_during)
SELECT 'PROMO' || p.product_id || CASE n WHEN 1 THEN 'A' ELSE 'B' END,
       p.product_id,
       (5 * (1 + (p.product_id + n) % 6))::numeric,
       tstzrange(timestamptz '2026-01-01' + (n - 1) * interval '30 days',
                 timestamptz '2026-01-01' + (n - 1) * interval '30 days' + interval '14 days', '[)')
FROM shop.products p
CROSS JOIN generate_series(1, 2) AS n
WHERE p.product_id <= 5000;

INSERT INTO shop.warehouses (warehouse_code, city, country_code, location) VALUES
 ('WH-NYC', 'New York',         'US', point( -74.0060,  40.7128)),
 ('WH-LAX', 'Los Angeles',      'US', point(-118.2437,  34.0522)),
 ('WH-LON', 'London',           'GB', point(  -0.1278,  51.5074)),
 ('WH-BER', 'Berlin',           'DE', point(  13.4050,  52.5200)),
 ('WH-TYO', 'Tokyo',            'JP', point( 139.6503,  35.6762)),
 ('WH-SIN', 'Singapore',        'SG', point( 103.8198,   1.3521)),
 ('WH-SGN', 'Ho Chi Minh City', 'VN', point( 106.6297,  10.8231)),
 ('WH-HAN', 'Hanoi',            'VN', point( 105.8342,  21.0278)),
 ('WH-SYD', 'Sydney',           'AU', point( 151.2093, -33.8688));

-- =============================================================================
-- 5. Materialized view (reporting)
-- =============================================================================
\echo '>>> materialized view'
CREATE MATERIALIZED VIEW shop.mv_daily_sales AS
SELECT (o.order_date AT TIME ZONE 'UTC')::date AS sales_date,
       o.sales_channel,
       count(*)                       AS orders_count,
       sum(o.total_amount)            AS revenue,
       round(avg(o.total_amount), 2)  AS avg_order_value,
       count(DISTINCT o.customer_id)  AS unique_customers
FROM shop.orders o
WHERE o.order_status <> 'CANCELLED'
GROUP BY 1, 2;
CREATE UNIQUE INDEX uq_mv_daily_sales ON shop.mv_daily_sales (sales_date, sales_channel);   -- needed for REFRESH CONCURRENTLY

-- =============================================================================
-- 6. Functions
-- =============================================================================
-- 6.1 Customer lifetime value (PL/pgSQL, raises an error for unknown customer)
CREATE OR REPLACE FUNCTION shop.fn_customer_lifetime_value(p_customer_id bigint)
RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_total numeric;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM shop.customers WHERE customer_id = p_customer_id) THEN
        RAISE EXCEPTION 'Customer % does not exist', p_customer_id USING ERRCODE = 'no_data_found';
    END IF;

    SELECT coalesce(sum(total_amount), 0) INTO v_total
    FROM shop.orders
    WHERE customer_id = p_customer_id
      AND order_status NOT IN ('CANCELLED', 'RETURNED');

    RETURN v_total;
END;
$$;

-- 6.2 Full order document as JSONB (SQL function)
CREATE OR REPLACE FUNCTION shop.fn_get_order_details(p_order_id bigint)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'order',    to_jsonb(o) - 'customer_id',
        'customer', jsonb_build_object('customer_id', c.customer_id,
                                       'name', c.first_name || ' ' || c.last_name,
                                       'email', c.email, 'tier', c.loyalty_tier),
        'items',    (SELECT jsonb_agg(jsonb_build_object('line_no', i.line_no, 'sku', p.sku,
                                                         'product', p.product_name, 'quantity', i.quantity,
                                                         'unit_price', i.unit_price, 'line_total', i.line_total)
                                      ORDER BY i.line_no)
                     FROM shop.order_items i JOIN shop.products p ON p.product_id = i.product_id
                     WHERE i.order_id = o.order_id),
        'payments', (SELECT jsonb_agg(to_jsonb(pm) - 'order_id' ORDER BY pm.paid_at)
                     FROM shop.payments pm WHERE pm.order_id = o.order_id))
    FROM shop.orders o
    JOIN shop.customers c ON c.customer_id = o.customer_id
    WHERE o.order_id = p_order_id
$$;

-- 6.3 Fuzzy product search (pg_trgm)
CREATE OR REPLACE FUNCTION shop.fn_search_products(p_query text, p_limit int DEFAULT 20)
RETURNS TABLE (product_id bigint, sku text, product_name text, unit_price numeric, score real)
LANGUAGE sql STABLE SET search_path = shop, public AS $$
    SELECT p.product_id, p.sku::text, p.product_name::text, p.unit_price::numeric,
           similarity(p.product_name, p_query) AS score
    FROM shop.products p
    WHERE p.product_name % p_query
       OR p.product_name ILIKE '%' || p_query || '%'
    ORDER BY score DESC, p.product_id
    LIMIT p_limit
$$;

-- 6.4 Monthly revenue pivot per sales channel (tablefunc crosstab)
CREATE OR REPLACE FUNCTION shop.fn_monthly_sales_pivot(p_year int)
RETURNS TABLE (sales_month int, web numeric, mobile numeric, store numeric, partner numeric)
LANGUAGE sql STABLE AS $$
    SELECT *
    FROM public.crosstab(
        format($q$
            SELECT extract(month FROM sales_date)::int, sales_channel, sum(revenue)
            FROM shop.mv_daily_sales
            WHERE sales_date >= make_date(%1$s, 1, 1) AND sales_date < make_date(%1$s + 1, 1, 1)
            GROUP BY 1, 2 ORDER BY 1, 2 $q$, p_year),
        $c$ VALUES ('WEB'), ('MOBILE'), ('STORE'), ('PARTNER') $c$
    ) AS ct(sales_month int, web numeric, mobile numeric, store numeric, partner numeric)
$$;

-- 6.5 Similar products: same category, ranked by product name similarity (pg_trgm)
CREATE OR REPLACE FUNCTION shop.fn_similar_products(p_product_id bigint, p_limit int DEFAULT 10)
RETURNS TABLE (product_id bigint, product_name text, category_id int, score real)
LANGUAGE plpgsql STABLE SET search_path = shop, public AS $$
DECLARE
    v_name     text;
    v_category int;
BEGIN
    SELECT p.product_name, p.category_id INTO v_name, v_category
    FROM shop.products p WHERE p.product_id = p_product_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product % does not exist', p_product_id;
    END IF;

    RETURN QUERY
    SELECT p.product_id, p.product_name::text, p.category_id, similarity(p.product_name, v_name)
    FROM shop.products p
    WHERE p.category_id = v_category
      AND p.product_id <> p_product_id
    ORDER BY 4 DESC, p.product_id
    LIMIT p_limit;
END;
$$;

-- 6.6 Nearest warehouses to a GPS point (haversine great-circle distance on point(lon, lat))
CREATE OR REPLACE FUNCTION shop.fn_nearest_warehouses(p_lat double precision, p_lon double precision, p_limit int DEFAULT 3)
RETURNS TABLE (warehouse_code text, city text, distance_km numeric)
LANGUAGE sql STABLE AS $$
    SELECT w.warehouse_code::text, w.city::text,
           round((2 * 6371 * asin(sqrt(
                 sin(radians(w.location[1] - p_lat) / 2) ^ 2
               + cos(radians(p_lat)) * cos(radians(w.location[1]))
                 * sin(radians(w.location[0] - p_lon) / 2) ^ 2)))::numeric, 1) AS distance_km
    FROM shop.warehouses w
    ORDER BY distance_km
    LIMIT p_limit
$$;

-- =============================================================================
-- 7. Triggers
-- =============================================================================
-- 7.1 Maintain orders.updated_at
CREATE OR REPLACE FUNCTION shop.trg_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_orders_updated_at
    BEFORE UPDATE ON shop.orders
    FOR EACH ROW EXECUTE FUNCTION shop.trg_set_updated_at();

-- 7.2 Generic row audit with hstore diff. TG_ARGV[0] = primary key column
CREATE OR REPLACE FUNCTION shop.trg_audit_row()
RETURNS trigger LANGUAGE plpgsql SET search_path = shop, public AS $$
DECLARE
    v_diff hstore;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        v_diff := (hstore(NEW) - hstore(OLD)) - ARRAY['updated_at'];
        IF v_diff = ''::hstore THEN
            RETURN NULL;                         -- nothing relevant changed
        END IF;
        INSERT INTO shop.audit_log (table_name, operation, row_pk, changed_fields)
        VALUES (TG_TABLE_NAME, TG_OP, hstore(OLD) -> TG_ARGV[0], v_diff);
    ELSE
        INSERT INTO shop.audit_log (table_name, operation, row_pk, detail)
        VALUES (TG_TABLE_NAME, TG_OP, hstore(OLD) -> TG_ARGV[0], to_jsonb(OLD));
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE TRIGGER trg_orders_audit
    AFTER UPDATE OR DELETE ON shop.orders
    FOR EACH ROW EXECUTE FUNCTION shop.trg_audit_row('order_id');
CREATE OR REPLACE TRIGGER trg_products_audit
    AFTER UPDATE OF unit_price, unit_cost, is_active OR DELETE ON shop.products
    FOR EACH ROW EXECUTE FUNCTION shop.trg_audit_row('product_id');

-- =============================================================================
-- 8. Procedures
-- =============================================================================
-- 8.1 Place a new order: check + decrement stock, insert header and lines, compute totals
CREATE OR REPLACE PROCEDURE shop.sp_place_order(
    p_customer_id bigint,
    p_items       shop.order_line_input[],
    INOUT p_order_id bigint DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_item  shop.order_line_input;
    v_line  smallint := 0;
    v_price numeric;
BEGIN
    IF p_items IS NULL OR cardinality(p_items) = 0 THEN
        RAISE EXCEPTION 'Order must contain at least one item';
    END IF;

    INSERT INTO shop.orders (order_number, customer_id, order_status, sales_channel)
    VALUES ('ORD-' || lpad(nextval('shop.order_number_seq')::text, 10, '0'), p_customer_id, 'PENDING', 'WEB')
    RETURNING order_id INTO p_order_id;

    FOREACH v_item IN ARRAY p_items LOOP
        v_line := v_line + 1;

        UPDATE shop.products
           SET stock_qty = stock_qty - v_item.quantity
         WHERE product_id = v_item.product_id
           AND is_active
           AND stock_qty >= v_item.quantity
        RETURNING unit_price INTO v_price;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product % is inactive or out of stock', v_item.product_id;
        END IF;

        INSERT INTO shop.order_items (order_id, line_no, product_id, quantity, unit_price, line_total)
        VALUES (p_order_id, v_line, v_item.product_id, v_item.quantity, v_price, v_item.quantity * v_price);
    END LOOP;

    UPDATE shop.orders o
       SET subtotal     = s.net,
           tax_amount   = round(s.net * 0.08, 2),
           shipping_fee = CASE WHEN s.net >= 100 THEN 0 ELSE 4.99 END,
           total_amount = s.net + round(s.net * 0.08, 2) + CASE WHEN s.net >= 100 THEN 0 ELSE 4.99 END
      FROM (SELECT sum(line_total) AS net FROM shop.order_items WHERE order_id = p_order_id) s
     WHERE o.order_id = p_order_id;

    RAISE NOTICE 'Order % created for customer %', p_order_id, p_customer_id;
END;
$$;

-- 8.2 Change order status with a state machine check (change is audited by trigger)
CREATE OR REPLACE PROCEDURE shop.sp_update_order_status(p_order_id bigint, p_new_status shop.order_status)
LANGUAGE plpgsql AS $$
DECLARE
    v_current shop.order_status;
BEGIN
    SELECT order_status INTO v_current FROM shop.orders WHERE order_id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order % not found', p_order_id;
    END IF;

    IF NOT (   (v_current = 'PENDING'    AND p_new_status IN ('PAID', 'CANCELLED'))
            OR (v_current = 'PAID'       AND p_new_status IN ('PROCESSING', 'CANCELLED'))
            OR (v_current = 'PROCESSING' AND p_new_status IN ('SHIPPED', 'CANCELLED'))
            OR (v_current = 'SHIPPED'    AND p_new_status =  'DELIVERED')
            OR (v_current = 'DELIVERED'  AND p_new_status =  'RETURNED')) THEN
        RAISE EXCEPTION 'Invalid status transition % -> % for order %', v_current, p_new_status, p_order_id;
    END IF;

    UPDATE shop.orders SET order_status = p_new_status WHERE order_id = p_order_id;
END;
$$;

-- =============================================================================
-- 9. Views
-- =============================================================================
-- 9.1 Join view: order + customer + item count + last payment status
CREATE VIEW shop.v_order_summary AS
SELECT o.order_id, o.order_number, o.order_date, o.order_status, o.sales_channel, o.total_amount,
       c.customer_id, c.first_name || ' ' || c.last_name AS customer_name, c.country_code,
       (SELECT count(*) FROM shop.order_items i WHERE i.order_id = o.order_id) AS item_count,
       lp.payment_status AS last_payment_status
FROM shop.orders o
JOIN shop.customers c ON c.customer_id = o.customer_id
LEFT JOIN LATERAL (SELECT p.payment_status FROM shop.payments p
                   WHERE p.order_id = o.order_id ORDER BY p.paid_at DESC LIMIT 1) lp ON true;

-- 9.2 Masked PII for analysts (pgcrypto digest)
CREATE VIEW shop.v_customers_masked AS
SELECT customer_id,
       regexp_replace(email, '^(.)[^@]*(@.*)$', '\1***\2')            AS email_masked,
       encode(public.digest(lower(email), 'sha256'), 'hex')           AS email_sha256,
       left(phone, 4) || '*******'                                     AS phone_masked,
       country_code, city, loyalty_tier
FROM shop.customers;

-- 9.3 Updatable view WITH CHECK OPTION
CREATE VIEW shop.v_active_products AS
SELECT product_id, sku, product_name, category_id, brand, unit_price, unit_cost, stock_qty, is_active
FROM shop.products
WHERE is_active
WITH CASCADED CHECK OPTION;

-- =============================================================================
-- 10. Extended statistics (city depends on country)
-- =============================================================================
CREATE STATISTICS IF NOT EXISTS shop.st_customers_country_city (dependencies, ndistinct, mcv)
    ON country_code, city FROM shop.customers;

-- =============================================================================
-- 11. Roles, grants, row level security
-- =============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'shop_readonly') THEN CREATE ROLE shop_readonly NOLOGIN; END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'shop_portal')   THEN CREATE ROLE shop_portal   NOLOGIN; END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'demo_analyst')  THEN
        CREATE ROLE demo_analyst LOGIN PASSWORD 'Analyst@123' IN ROLE shop_readonly;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA shop TO shop_readonly, shop_portal;
GRANT SELECT ON ALL TABLES IN SCHEMA shop TO shop_readonly;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA shop TO shop_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA shop GRANT SELECT ON TABLES TO shop_readonly;
REVOKE SELECT ON shop.audit_log FROM shop_readonly;
GRANT SELECT ON shop.orders TO shop_portal;

-- RLS: shop_readonly sees every order, a portal session only its own customer's orders
--      (SET app.customer_id = '42'). Table owner / superuser are not affected.
ALTER TABLE shop.orders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS p_orders_readonly ON shop.orders;
DROP POLICY IF EXISTS p_orders_portal   ON shop.orders;
CREATE POLICY p_orders_readonly ON shop.orders
    FOR SELECT TO shop_readonly USING (true);
CREATE POLICY p_orders_portal ON shop.orders
    FOR SELECT TO shop_portal
    USING (customer_id = nullif(current_setting('app.customer_id', true), '')::bigint);

-- =============================================================================
-- 12. Event trigger: log every DDL command into shop.audit_log
-- =============================================================================
CREATE OR REPLACE FUNCTION shop.trg_log_ddl()
RETURNS event_trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, shop AS $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
        INSERT INTO shop.audit_log (table_name, operation, detail)
        VALUES (coalesce(r.object_identity, '-'), 'DDL',
                jsonb_build_object('command_tag', r.command_tag, 'object_type', r.object_type));
    END LOOP;
END;
$$;

CREATE EVENT TRIGGER evt_ddl_audit ON ddl_command_end
    EXECUTE FUNCTION shop.trg_log_ddl();

-- =============================================================================
-- 13. Comments, statistics, summary
-- =============================================================================
COMMENT ON TABLE shop.audit_log  IS 'Row changes (hstore diff, by trg_audit_row) and DDL commands (by evt_ddl_audit)';
COMMENT ON TABLE shop.promotions IS 'Product promotions; citext code, btree_gist exclusion prevents overlapping periods';
COMMENT ON TABLE shop.warehouses IS 'Warehouses; location = point(longitude, latitude) with GiST index';
COMMENT ON MATERIALIZED VIEW shop.mv_daily_sales IS 'Daily revenue per sales channel (REFRESH MATERIALIZED VIEW CONCURRENTLY)';
COMMENT ON FUNCTION shop.fn_search_products(text, int) IS 'Fuzzy product search - pg_trgm';
COMMENT ON PROCEDURE shop.sp_place_order(bigint, shop.order_line_input[], bigint) IS 'Create an order, decrement stock, compute totals';

ANALYZE shop.customers, shop.products, shop.promotions;

\echo '>>> Objects in schema shop'
SELECT 'table' AS object_type, count(*) FROM pg_tables WHERE schemaname = 'shop'
UNION ALL SELECT 'index',             count(*) FROM pg_indexes WHERE schemaname = 'shop'
UNION ALL SELECT 'view',              count(*) FROM pg_views WHERE schemaname = 'shop'
UNION ALL SELECT 'materialized view', count(*) FROM pg_matviews WHERE schemaname = 'shop'
UNION ALL SELECT 'function',          count(*) FROM pg_proc WHERE pronamespace = 'shop'::regnamespace AND prokind = 'f'
UNION ALL SELECT 'procedure',         count(*) FROM pg_proc WHERE pronamespace = 'shop'::regnamespace AND prokind = 'p'
UNION ALL SELECT 'aggregate',         count(*) FROM pg_proc WHERE pronamespace = 'shop'::regnamespace AND prokind = 'a'
UNION ALL SELECT 'trigger',           count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
                                      WHERE c.relnamespace = 'shop'::regnamespace AND NOT t.tgisinternal
UNION ALL SELECT 'sequence',          count(*) FROM pg_sequences WHERE schemaname = 'shop'
UNION ALL SELECT 'type (enum/domain/composite)', count(*) FROM pg_type t
                                      WHERE t.typnamespace = 'shop'::regnamespace AND t.typtype IN ('e', 'd')
                                         OR (t.typnamespace = 'shop'::regnamespace AND t.typtype = 'c'
                                             AND EXISTS (SELECT 1 FROM pg_class c WHERE c.oid = t.typrelid AND c.relkind = 'c'))
UNION ALL SELECT 'policy',            count(*) FROM pg_policies WHERE schemaname = 'shop'
UNION ALL SELECT 'extension',         count(*) FROM pg_extension WHERE extname <> 'plpgsql';

SELECT pg_size_pretty(pg_database_size(current_database())) AS database_size;
