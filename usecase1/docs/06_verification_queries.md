# 06 – Kiểm tra trước và sau khi nâng minor version (16.2 → 16.3)

Mục tiêu: chứng minh sau khi patch thì version đúng, service chạy, dữ liệu không đổi, index không hỏng,
function / procedure / view / trigger vẫn chạy được và định nghĩa không bị thay đổi.

Cách làm: chạy cùng một bộ 7 lệnh hai lần (lệnh 7 là EXPLAIN ANALYZE chứng minh index được dùng), lần đầu trên 16.2 với `TAG=before`, lần hai trên 16.3 với
`TAG=after`. Mỗi lệnh ghi kết quả ra file `/tmp/verify_<TAG>_*.txt`, cuối cùng `diff` hai bộ file.

Bộ lệnh này cần đã chạy sql/02 → sql/05 (có extension `amcheck` và các object của sql/05).

Bốn expected result của UC01:

1. PostgreSQL chạy 16.3: lệnh 1.
2. Service active, client kết nối được: lệnh 1.
3. Database và dữ liệu truy cập bình thường: lệnh 2, 3, 4, 5.
4. Log không có lỗi nghiêm trọng sau patch: lệnh 6.

Quy trình:

```
[TRƯỚC]    TAG=before, chạy lệnh 1 → 6 trên 16.2
[NÂNG CẤP] làm theo mục "Nâng cấp" ở cuối file
[SAU]      TAG=after,  chạy lệnh 1 → 6 trên 16.3, rồi chạy mục "So sánh trước và sau"
```

Đặt biến này ở đầu mỗi phiên làm việc (đổi thành `after` khi chạy sau nâng cấp):

```bash
export TAG=before
```

## Lệnh 1 – Version, service, kết nối

```bash
{ sudo -u postgres psql -X -d shopdb -Atc "SELECT version(), pg_is_in_recovery();" \
  && systemctl is-active postgresql@16-main \
  && pg_isready -h localhost -p 5432 \
  && apt-mark showhold; } | tee /tmp/verify_${TAG}_version.txt
```

Trước nâng cấp: version 16.2, `pg_is_in_recovery` là `f`, service `active`, `accepting connections`,
`postgresql-16` và `postgresql-client-16` đang bị hold. Sau nâng cấp: version 16.3, các mục còn lại giữ nguyên
(hold được đặt lại sau khi cài). Dòng version là dòng duy nhất được phép khác giữa hai lần.

Thử từ máy khác: `psql "host=<SERVER_IP> port=5432 dbname=shopdb user=postgres" -c "SELECT 1;"`

## Lệnh 2 – Dữ liệu: số dòng và checksum của từng bảng

Mỗi bảng trong schema `shop` được đếm dòng và băm toàn bộ nội dung (md5 của md5 từng dòng, sắp xếp theo hash
nên không phụ thuộc thứ tự lưu). Câu lệnh đọc hết mọi bảng nên nếu heap hỏng thì báo lỗi ngay.

```bash
sudo -u postgres psql -X -d shopdb -v ON_ERROR_STOP=1 -At <<'SQL' | tee /tmp/verify_${TAG}_data.txt
SELECT format('%-18s rows=%-8s md5=%s', t.table_name,
       (xpath('/row/n/text()', x))[1], (xpath('/row/h/text()', x))[1])
FROM information_schema.tables t,
     LATERAL query_to_xml(format(
       'SELECT count(*) AS n, coalesce(md5(string_agg(md5(r::text), '''' ORDER BY md5(r::text))), '''') AS h FROM %I.%I r',
       t.table_schema, t.table_name), false, true, '') AS x
WHERE t.table_schema = 'shop' AND t.table_type = 'BASE TABLE'
ORDER BY t.table_name;

SELECT 'sum_orders='   || sum(total_amount) FROM shop.orders;
SELECT 'sum_items='    || sum(line_total)   FROM shop.order_items;
SELECT 'sum_payments=' || sum(amount)       FROM shop.payments;
SELECT 'mv_daily_sales rows=' || count(*)   FROM shop.mv_daily_sales;
SQL
```

Không in dung lượng database vào file này vì dung lượng có thể lệch nhẹ sau restart. Xem riêng bằng
`sudo -u postgres psql -Atc "SELECT pg_size_pretty(pg_database_size('shopdb'))"`.

## Lệnh 3 – Index còn hợp lệ

Gồm bốn phần: không có index invalid, định nghĩa index không đổi, `pg_amcheck` kiểm tra cấu trúc B-tree và
heap, và so sánh kết quả đi bằng index với đi bằng seq scan cho các loại index mà amcheck 16 không kiểm tra
(GIN, BRIN, Hash).

Phần 1 và 2, ghi ra file:

```bash
sudo -u postgres psql -X -d shopdb -v ON_ERROR_STOP=1 -At <<'SQL' | tee /tmp/verify_${TAG}_index.txt
SELECT 'indexes total=' || count(*)
       || ' invalid=' || count(*) FILTER (WHERE NOT i.indisvalid OR NOT i.indisready OR NOT i.indislive)
FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
WHERE c.relnamespace = 'shop'::regnamespace;

SELECT indexname || ' :: ' || indexdef
FROM pg_indexes WHERE schemaname = 'shop' ORDER BY indexname;
SQL
```

Kết quả đúng: dòng đầu là `indexes total=27 invalid=0`, các dòng sau là định nghĩa 27 index.

Phần 3, kiểm tra cấu trúc B-tree (kèm đối chiếu với heap) và heap của schema `shop`:

```bash
sudo -u postgres /usr/lib/postgresql/16/bin/pg_amcheck -d shopdb -s shop --heapallindexed --parent-check \
  && echo "AMCHECK OK"
```

In `AMCHECK OK` là đạt. Nếu có lỗi, `pg_amcheck` in tên index hoặc bảng hỏng và thoát với mã khác 0.

Phần 4, index không phải B-tree: đếm hai lần, một lần ép dùng index, một lần ép seq scan, hai số phải bằng nhau.

```bash
sudo -u postgres psql -X -d shopdb -v ON_ERROR_STOP=1 <<'SQL' 2>&1 | tee /tmp/verify_${TAG}_index_scan.txt
DO $$
DECLARE
  t record; via_index bigint; via_seq bigint;
BEGIN
  FOR t IN SELECT * FROM (VALUES
    ('idx_products_attributes_gin', 'shop.products',
     'attributes @> (SELECT attributes FROM shop.products WHERE product_id = 1)'),
    ('idx_products_name_trgm', 'shop.products',
     $q$product_name ILIKE '%' || (SELECT substr(product_name, 1, 4) FROM shop.products WHERE product_id = 1) || '%'$q$),
    ('idx_payments_txn_ref_hash', 'shop.payments',
     'transaction_ref = (SELECT max(transaction_ref) FROM shop.payments)'),
    ('idx_payments_paid_at_brin', 'shop.payments',
     'paid_at >= (SELECT min(paid_at) + (max(paid_at) - min(paid_at)) / 2 FROM shop.payments)')
  ) v(idx, tbl, cond)
  LOOP
    PERFORM set_config('enable_seqscan', 'off', true);
    EXECUTE format('SELECT count(*) FROM %s WHERE %s', t.tbl, t.cond) INTO via_index;
    PERFORM set_config('enable_seqscan', 'on', true);
    PERFORM set_config('enable_indexscan', 'off', true);
    PERFORM set_config('enable_bitmapscan', 'off', true);
    EXECUTE format('SELECT count(*) FROM %s WHERE %s', t.tbl, t.cond) INTO via_seq;
    PERFORM set_config('enable_indexscan', 'on', true);
    PERFORM set_config('enable_bitmapscan', 'on', true);
    IF via_index <> via_seq THEN
      RAISE EXCEPTION 'INDEX MISMATCH %: index=% seq=%', t.idx, via_index, via_seq;
    END IF;
    RAISE NOTICE 'OK % : % rows', t.idx, via_index;
  END LOOP;
END $$;
SQL
```

Mỗi index in một dòng `NOTICE:  OK <tên index> : <n> rows`. Có `INDEX MISMATCH` nghĩa là index trả sai kết quả,
khi đó chạy `REINDEX INDEX CONCURRENTLY shop.<tên index>;`.

## Lệnh 4 – Function, procedure, view, trigger còn hợp lệ

Phần 1: danh sách object và hash định nghĩa. Nếu patch làm đổi hay mất object thì `diff` sẽ thấy.

```bash
sudo -u postgres psql -X -d shopdb -v ON_ERROR_STOP=1 -At <<'SQL' | tee /tmp/verify_${TAG}_objects.txt
SELECT 'routine ' || p.oid::regprocedure::text || ' kind=' || p.prokind || ' md5=' || md5(p.prosrc)
FROM pg_proc p WHERE p.pronamespace = 'shop'::regnamespace ORDER BY 1;

SELECT 'view ' || c.relkind || ' ' || c.oid::regclass::text || ' md5=' || md5(pg_get_viewdef(c.oid, true))
FROM pg_class c WHERE c.relnamespace = 'shop'::regnamespace AND c.relkind IN ('v', 'm') ORDER BY 1;

SELECT 'trigger ' || tgrelid::regclass::text || ' ' || tgname || ' enabled=' || tgenabled
       || ' md5=' || md5(pg_get_triggerdef(oid))
FROM pg_trigger WHERE NOT tgisinternal ORDER BY 1;

SELECT 'event_trigger ' || evtname || ' ' || evtevent || ' enabled=' || evtenabled
FROM pg_event_trigger ORDER BY 1;

SELECT 'type ' || t.typname || ' kind=' || t.typtype
FROM pg_type t WHERE t.typnamespace = 'shop'::regnamespace AND t.typtype IN ('e', 'c', 'd')
  AND (t.typtype <> 'c' OR EXISTS (SELECT 1 FROM pg_class c WHERE c.oid = t.typrelid AND c.relkind = 'c'))
ORDER BY 1;
SQL
```

Phần 2: gọi thật từng function, view và materialized view rồi băm kết quả. Giá trị băm phải giống nhau
trước và sau patch.

```bash
sudo -u postgres psql -X -d shopdb -v ON_ERROR_STOP=1 -At <<'SQL' | tee /tmp/verify_${TAG}_calls.txt
SELECT 'fn_customer_lifetime_value(1)  ' || shop.fn_customer_lifetime_value(1);
SELECT 'fn_get_order_details(1000)     ' || md5(shop.fn_get_order_details(1000)::text);
SELECT 'fn_search_products             ' || coalesce(md5(string_agg(t::text, '|' ORDER BY t::text)), 'EMPTY')
FROM shop.fn_search_products('phone', 10) t;
SELECT 'fn_monthly_sales_pivot         ' || coalesce(md5(string_agg(t::text, '|' ORDER BY t::text)), 'EMPTY')
FROM shop.fn_monthly_sales_pivot((SELECT extract(year FROM max(sales_date))::int FROM shop.mv_daily_sales)) t;
SELECT 'fn_similar_products(1)         ' || coalesce(md5(string_agg(t::text, '|' ORDER BY t::text)), 'EMPTY')
FROM shop.fn_similar_products(1, 5) t;
SELECT 'fn_nearest_warehouses          ' || coalesce(md5(string_agg(t::text, '|' ORDER BY t::text)), 'EMPTY')
FROM shop.fn_nearest_warehouses(10.8, 106.7, 3) t;
SELECT 'weighted_avg                   ' || shop.weighted_avg(unit_price, stock_qty) FROM shop.products WHERE stock_qty > 0;

SELECT 'v_order_summary rows=' || count(*)           FROM shop.v_order_summary;
SELECT 'v_customers_masked rows=' || count(*)        FROM shop.v_customers_masked;
SELECT 'v_active_products rows=' || count(*)         FROM shop.v_active_products;
SELECT 'mv_daily_sales md5=' || md5(string_agg(m::text, '|' ORDER BY m::text)) FROM shop.mv_daily_sales m;
SQL
```

Nếu thông báo `ERROR` thì function nào đó đã hỏng (ví dụ thiếu extension hoặc đổi hành vi). Kết quả
`EMPTY` ở trước và sau đều giống nhau thì vẫn coi là khớp, nhưng nên đổi từ khóa tìm kiếm cho có dữ liệu.

Phần 3: chạy thử hai procedure trong một khối có rollback, nên không để lại dữ liệu.
Trigger `trg_orders_updated_at` và `trg_orders_audit` cũng chạy trong lúc này.

```bash
sudo -u postgres psql -X -d shopdb -v ON_ERROR_STOP=1 <<'SQL' 2>&1 | tee /tmp/verify_${TAG}_procs.txt
DO $$
DECLARE
  v_pid bigint; v_oid bigint; v_audit_before bigint; v_audit_after bigint;
BEGIN
  SELECT count(*) INTO v_audit_before FROM shop.audit_log;
  BEGIN
    SELECT product_id INTO v_pid FROM shop.products WHERE is_active AND stock_qty >= 1 ORDER BY product_id LIMIT 1;
    CALL shop.sp_place_order(1, ARRAY[ROW(v_pid, 1)::shop.order_line_input], v_oid);
    CALL shop.sp_update_order_status(v_oid, 'PAID');
    PERFORM 1 FROM shop.orders WHERE order_id = v_oid AND order_status = 'PAID';
    IF NOT FOUND THEN RAISE EXCEPTION 'order not updated'; END IF;
    RAISE EXCEPTION 'ROLLBACK_TEST';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'ROLLBACK_TEST' THEN RAISE; END IF;
  END;
  SELECT count(*) INTO v_audit_after FROM shop.audit_log;
  IF v_audit_before <> v_audit_after THEN RAISE EXCEPTION 'rollback did not clean up'; END IF;
  RAISE NOTICE 'PROCEDURES OK (sp_place_order, sp_update_order_status, triggers), da rollback';
END $$;
SQL
```

Sequence `order_number_seq` vẫn tăng thêm 1 vì sequence không rollback; việc này không ảnh hưởng gì.

## Lệnh 5 – Constraint, extension, sequence, quyền

```bash
sudo -u postgres psql -X -d shopdb -v ON_ERROR_STOP=1 -At <<'SQL' | tee /tmp/verify_${TAG}_meta.txt
SELECT 'constraint ' || conrelid::regclass::text || ' ' || conname || ' type=' || contype
       || ' validated=' || convalidated || ' :: ' || pg_get_constraintdef(oid)
FROM pg_constraint WHERE connamespace = 'shop'::regnamespace ORDER BY 1;

SELECT 'extension ' || extname || ' ' || extversion FROM pg_extension ORDER BY extname;

SELECT 'sequence ' || sequencename || ' increment=' || increment_by FROM pg_sequences
WHERE schemaname = 'shop' ORDER BY sequencename;

SELECT 'role ' || rolname || ' login=' || rolcanlogin || ' super=' || rolsuper FROM pg_roles
WHERE rolname !~ '^pg_' ORDER BY rolname;

SELECT 'grant ' || grantee || ' ' || table_name || ' ' || privilege_type
FROM information_schema.role_table_grants WHERE table_schema = 'shop' ORDER BY 1;

SELECT 'rls ' || relname || ' enabled=' || relrowsecurity FROM pg_class
WHERE relnamespace = 'shop'::regnamespace AND relkind = 'r' AND relrowsecurity ORDER BY 1;

SELECT 'policy ' || tablename || ' ' || policyname || ' ' || cmd FROM pg_policies
WHERE schemaname = 'shop' ORDER BY 1;

SELECT 'ext_stats ' || stxname FROM pg_statistic_ext WHERE stxnamespace = 'shop'::regnamespace ORDER BY 1;

SET ROLE demo_analyst;
SELECT 'pg_stats_ext rows visible to demo_analyst=' || count(*) FROM pg_stats_ext WHERE schemaname = 'shop';
RESET ROLE;
SQL
```

Cần kiểm tra: mọi dòng `constraint` có `validated=t`; extension đủ 8 + `plpgsql`; không mất role, quyền, policy.

Dòng cuối (`pg_stats_ext rows visible to demo_analyst`) là thay đổi có chủ đích của 16.3: sau khi chạy
`fix-CVE-2024-4317.sql` giá trị chuyển từ `1` sang `0`, vì user thường không còn đọc được thống kê mở rộng
của bảng mình không có quyền. Chi tiết ở docs/07. Đây là dòng duy nhất trong file này được phép khác.

## Lệnh 6 – Log không có lỗi nghiêm trọng

```bash
grep -E "PANIC|FATAL|ERROR|could not|corrupt|invalid page" /var/log/postgresql/postgresql-16-main.log | tail -n 30 \
  | tee /tmp/verify_${TAG}_log.txt
```

Không in ra dòng nào là log sạch. Lưu ý: nếu đã chạy lệnh 4 thì các lỗi do chủ ý (`ROLLBACK_TEST` nằm trong khối
EXCEPTION nên không ghi vào log) sẽ không xuất hiện; còn lỗi đăng nhập sai mật khẩu của người khác thì có thể có,
bỏ qua nếu không liên quan. Sau nâng cấp chỉ cần để ý các dòng mới hơn thời điểm restart. Tìm thời điểm đó bằng:

```bash
grep "ready to accept connections" /var/log/postgresql/postgresql-16-main.log | tail -n 2
```

## Lệnh 7 – Chứng minh index được dùng (EXPLAIN ANALYZE)

Lệnh 3 chứng minh index không hỏng. Lệnh này chứng minh planner dùng được từng index để trả kết quả.
Chạy ở cả hai phiên bản, kết quả phải là `PASS` hết. Không cần diff vì thời gian chạy mỗi lần một khác.

Bước 1: cập nhật thống kê và visibility map (cần để có `Index Only Scan`).

```bash
sudo -u postgres psql -X -d shopdb -c "VACUUM (ANALYZE)"
```

Bước 2: chạy `EXPLAIN (ANALYZE)` cho 21 câu SELECT, mỗi câu nhắm vào một index. Bảng nhỏ như `products`,
`warehouses` thì planner thường chọn seq scan vì rẻ hơn, nên vòng lặp đặt `enable_seqscan=off` để buộc planner
chọn index nếu có thể dùng. Câu nào không dùng đúng index thì in `FAIL` cùng plan.

```bash
while IFS='|' read -r idx sql; do
  plan=$(sudo -u postgres env PGOPTIONS='-c enable_seqscan=off' \
    psql -X -d shopdb -At -c "EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF) $sql" </dev/null)
  if echo "$plan" | grep -q "$idx"; then echo "PASS  $idx"; else echo "FAIL  $idx"; echo "$plan"; fi
done <<'EOF' | tee /tmp/verify_${TAG}_explain.txt
orders_pkey|SELECT * FROM shop.orders WHERE order_id = 1000
orders_order_number_key|SELECT * FROM shop.orders WHERE order_number = (SELECT order_number FROM shop.orders WHERE order_id = 1000)
idx_orders_customer_date|SELECT order_status, total_amount FROM shop.orders WHERE customer_id = 100 ORDER BY order_date DESC
idx_orders_status_open|SELECT * FROM shop.orders WHERE order_status = 'PENDING' ORDER BY order_date LIMIT 10
uq_order_items_order_line|SELECT * FROM shop.order_items WHERE order_id = 1000 AND line_no = 1
idx_order_items_product|SELECT * FROM shop.order_items WHERE product_id = 10
idx_payments_order|SELECT * FROM shop.payments WHERE order_id = 1000
idx_payments_paid_at_brin|SELECT count(*) FROM shop.payments WHERE paid_at >= (SELECT max(paid_at) - interval '1 day' FROM shop.payments)
idx_payments_txn_ref_hash|SELECT * FROM shop.payments WHERE transaction_ref = (SELECT max(transaction_ref) FROM shop.payments)
customers_pkey|SELECT * FROM shop.customers WHERE customer_id = 100
uq_customers_email_lower|SELECT * FROM shop.customers WHERE lower(email) = (SELECT lower(email) FROM shop.customers WHERE customer_id = 1)
products_pkey|SELECT * FROM shop.products WHERE product_id = 10
products_sku_key|SELECT * FROM shop.products WHERE sku = (SELECT sku FROM shop.products WHERE product_id = 1)
idx_products_category_price|SELECT * FROM shop.products WHERE category_id = 5 AND unit_price BETWEEN 10 AND 50
idx_products_attributes_gin|SELECT count(*) FROM shop.products WHERE attributes @> (SELECT attributes FROM shop.products WHERE product_id = 1)
idx_products_name_trgm|SELECT * FROM shop.products WHERE product_name ILIKE '%phone%'
promotions_promo_code_key|SELECT * FROM shop.promotions WHERE promo_code = 'summer10'
ex_promotions_no_overlap|SELECT * FROM shop.promotions WHERE product_id = 5 AND valid_during && tstzrange(now() - interval '1 year', now() + interval '1 year')
idx_warehouses_location|SELECT warehouse_code FROM shop.warehouses ORDER BY location <-> point(106.7, 10.8) LIMIT 3
uq_mv_daily_sales|SELECT * FROM shop.mv_daily_sales WHERE sales_date = (SELECT max(sales_date) FROM shop.mv_daily_sales) AND sales_channel = 'WEB'
audit_log_pkey|SELECT * FROM shop.audit_log WHERE audit_id = 1
EOF
```

Kết quả đạt: tất cả dòng là `PASS`. Kiểm tra nhanh:

```bash
grep -c '^PASS' /tmp/verify_${TAG}_explain.txt; grep '^FAIL' /tmp/verify_${TAG}_explain.txt || echo "NO FAIL"
```

Nếu `audit_log` chưa có dòng nào (chưa có thay đổi nào qua trigger) thì dòng cuối vẫn dùng index nhưng trả về 0 dòng,
vẫn là `PASS`.

Bước 3: xem tận mắt một plan đầy đủ và so với khi không có index. Plan tự nhiên (không ép gì):

```bash
sudo -u postgres psql -X -d shopdb <<'SQL'
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_status, total_amount
FROM shop.orders WHERE customer_id = 100 ORDER BY order_date DESC;
SQL
```

Cần thấy `Index Only Scan using idx_orders_customer_date on orders`, `Heap Fetches: 0` (nhờ cột `INCLUDE` và VACUUM
ở bước 1), `Buffers: shared hit=` chỉ vài block và `Execution Time` tính bằng phần nghìn giây.

Cùng câu đó khi tắt index để thấy index giúp được bao nhiêu:

```bash
sudo -u postgres psql -X -d shopdb <<'SQL'
SET enable_indexscan = off; SET enable_indexonlyscan = off; SET enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_status, total_amount
FROM shop.orders WHERE customer_id = 100 ORDER BY order_date DESC;
SQL
```

Lần này plan là `Seq Scan on orders`, đọc toàn bộ bảng: số `Buffers` lớn hơn hàng trăm lần và thời gian lâu hơn rõ rệt.
Điều này chứng minh chính index làm câu truy vấn nhanh, không phải do dữ liệu nằm sẵn trong cache.

Bước 4: bộ đếm của PostgreSQL xác nhận index đã được dùng. Cột `idx_scan` của các index trong bước 2 phải lớn hơn 0:

```bash
sudo -u postgres psql -X -d shopdb -c "
SELECT relname AS table_name, indexrelname AS index_name, idx_scan, idx_tup_read
FROM pg_stat_user_indexes
WHERE schemaname = 'shop'
ORDER BY idx_scan DESC, indexrelname;"
```

Index vẫn có `idx_scan = 0` là index chưa có câu nào chạm tới (ví dụ các index của khóa ngoại ít dùng), không có nghĩa là hỏng.
Bộ đếm này giữ qua restart bình thường nhưng bị xóa sau khi server crash hoặc `pg_stat_reset()`.

## So sánh trước và sau

Chạy sau khi đã làm xong lệnh 1 → 6 với cả `TAG=before` và `TAG=after`:

```bash
for part in data index objects calls meta; do
  if diff -q /tmp/verify_before_$part.txt /tmp/verify_after_$part.txt >/dev/null; then
    echo "SAME   $part"
  else
    echo "DIFF   $part"; diff /tmp/verify_before_$part.txt /tmp/verify_after_$part.txt
  fi
done
```

Kết quả đạt:

```
SAME   data
SAME   index
SAME   objects
SAME   calls
DIFF   meta      (chỉ khác đúng dòng pg_stats_ext rows visible to demo_analyst=1 -> 0)
```

`version` khác ở dòng version (16.2 → 16.3) là đúng. `index_scan` và `procs` không cần diff, chỉ cần không có
`ERROR` / `INDEX MISMATCH` trong file `after`:

```bash
grep -E "ERROR|MISMATCH" /tmp/verify_after_index_scan.txt /tmp/verify_after_procs.txt || echo "NO ERROR"
```

## Nâng cấp 16.2 → 16.3 (in-place, apt)

```bash
# 0) Backup (khuyến nghị)
sudo -u postgres pg_dumpall --globals-only > /tmp/globals_before_16.3.sql
sudo -u postgres pg_dump -Fc -d shopdb -f /tmp/shopdb_before_16.3.dump

# 1) Xem version có trong repo archive
apt-cache madison postgresql-16 | grep -E "16\.(2|3)-"

# 2) Gỡ hold và cài 16.3 (lấy chuỗi version đúng từ bước 1, thường là 16.3-1.pgdg24.04+1)
NEW=16.3-1.pgdg24.04+1
sudo apt-mark unhold postgresql-16 postgresql-client-16
sudo apt-get install -y postgresql-16=$NEW postgresql-client-16=$NEW     # package tự restart cluster
sudo apt-mark hold postgresql-16 postgresql-client-16
```

Bản 16.3 cần thêm một bước riêng cho CVE-2024-4317: cluster cũ phải chạy script sửa trong mọi database,
kể cả `template0` và `template1`.

```bash
FIX=/usr/share/postgresql/16/fix-CVE-2024-4317.sql
sudo -u postgres psql -c "ALTER DATABASE template0 WITH ALLOW_CONNECTIONS true;"
for db in $(sudo -u postgres psql -Atc "SELECT datname FROM pg_database"); do
  echo "== $db"; sudo -u postgres psql -d "$db" -v ON_ERROR_STOP=1 -f $FIX
done
sudo -u postgres psql -c "ALTER DATABASE template0 WITH ALLOW_CONNECTIONS false;"
```

Sau đó đặt `export TAG=after` và chạy lại lệnh 1 → 6, rồi mục "So sánh trước và sau".

Rollback nếu cần (minor version dùng chung định dạng dữ liệu nên hạ ngược được):

```bash
sudo apt-mark unhold postgresql-16 postgresql-client-16
sudo apt-get install -y --allow-downgrades postgresql-16=16.2-2.pgdg24.04+1 postgresql-client-16=16.2-2.pgdg24.04+1
sudo apt-mark hold postgresql-16 postgresql-client-16
```
