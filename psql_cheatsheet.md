# Cheat sheet psql

Các lệnh hay dùng khi làm việc với PostgreSQL bằng psql. Ví dụ dùng database `shopdb`, schema `shop` của project này, đổi tên cho phù hợp khi dùng ở nơi khác.

Có hai loại lệnh: lệnh bắt đầu bằng dấu `\` là meta-command của psql (không cần dấu `;`), còn lại là SQL thường (phải kết thúc bằng `;`).

## 1. Kết nối

```bash
psql -U postgres                          # kết nối vào DB mặc định
psql -U postgres -d shopdb                # chọn database
psql -h 127.0.0.1 -p 5432 -U postgres -d shopdb
psql "postgresql://postgres@127.0.0.1:5432/shopdb"
sudo -u postgres psql                     # chạy bằng user hệ điều hành postgres (Ubuntu)

psql -d shopdb -c "select version();"     # chạy 1 câu rồi thoát
psql -d shopdb -f file.sql                # chạy file SQL
psql -d shopdb -v scale=0.03 -f 03_insert_data.sql   # truyền biến vào file
psql -d shopdb -At -c "select 1"          # -A không căn cột, -t bỏ header: dễ dùng trong script
```

Trong psql:

```
\c shopdb            -- đổi sang database khác
\conninfo            -- xem đang kết nối vào đâu, bằng user nào
\q                   -- thoát
\?                   -- danh sách meta-command
\h CREATE INDEX      -- cú pháp của 1 câu SQL
```

## 2. Liệt kê các thành phần trong database

```
\l                   -- danh sách database
\l+                  -- kèm dung lượng, tablespace
\dn                  -- danh sách schema
\dn+                 -- kèm quyền và mô tả
\dt                  -- bảng trong search_path
\dt shop.*           -- bảng trong schema shop
\dt *.*              -- bảng trong mọi schema (kể cả hệ thống)
\dt+ shop.*          -- kèm dung lượng
\dv shop.*           -- view
\dm shop.*           -- materialized view
\ds shop.*           -- sequence
\di shop.*           -- index
\dE shop.*           -- foreign table
\dT shop.*           -- kiểu dữ liệu (enum, composite)
\dD shop.*           -- domain
\dx                  -- extension đã cài
\dx+ pg_trgm         -- object thuộc một extension
\dy                  -- event trigger
\du                  -- role / user
\dg                  -- group (role)
\db                  -- tablespace
\dp shop.*           -- quyền trên bảng (privileges)
\ddp                 -- default privileges
\dRp                 -- publication (replication)
\dRs                 -- subscription
```

Thêm `+` sau lệnh để xem chi tiết hơn (ví dụ `\dt+`, `\di+`, `\df+`).

Đổi schema mặc định để khỏi gõ `shop.` mỗi lần:

```sql
SET search_path = shop, public;
SHOW search_path;
```

## 3. Cấu trúc bảng

```
\d shop.orders       -- cột, kiểu, index, FK, trigger của bảng
\d+ shop.orders      -- thêm storage, mô tả, stats target
\d shop.v_order_summary    -- định nghĩa view
```

Liệt kê cột bằng SQL:

```sql
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'shop' AND table_name = 'orders'
ORDER BY ordinal_position;
```

Liệt kê khóa ngoại:

```sql
SELECT conrelid::regclass AS bang,
       conname,
       pg_get_constraintdef(oid) AS dinh_nghia
FROM pg_constraint
WHERE contype = 'f' AND connamespace = 'shop'::regnamespace
ORDER BY 1, 2;
```

Liệt kê mọi constraint (PK, FK, UNIQUE, CHECK, EXCLUDE) của một bảng:

```sql
SELECT conname, contype, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'shop.orders'::regclass;
```

## 4. Index

```
\di shop.*                 -- danh sách index
\di+ shop.*                -- kèm dung lượng
\d shop.orders             -- index của một bảng (nằm cuối output)
```

Index kèm câu lệnh tạo:

```sql
SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'shop'
ORDER BY tablename, indexname;
```

Dung lượng từng index:

```sql
SELECT c.relname AS index_name,
       t.relname AS table_name,
       am.amname AS loai,
       pg_size_pretty(pg_relation_size(c.oid)) AS size
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
JOIN pg_class t ON t.oid = i.indrelid
JOIN pg_am am ON am.oid = c.relam
WHERE t.relnamespace = 'shop'::regnamespace
ORDER BY pg_relation_size(c.oid) DESC;
```

Index chưa từng được dùng (từ lần reset stats gần nhất):

```sql
SELECT relname AS bang, indexrelname AS index, idx_scan,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE schemaname = 'shop' AND idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;
```

Index bị hỏng hoặc chưa valid (sau CREATE INDEX CONCURRENTLY lỗi):

```sql
SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;
```

## 5. Function, procedure, trigger

```
\df shop.*                 -- function, procedure, aggregate
\df+ shop.fn_search_products   -- kèm ngôn ngữ, volatility, owner
\sf shop.fn_search_products    -- in nguyên định nghĩa function
\sf+ shop.fn_search_products    -- kèm số dòng
\da shop.*                 -- aggregate
\do                        -- operator
```

Phân loại theo kiểu:

```sql
SELECT p.proname,
       CASE p.prokind WHEN 'f' THEN 'function'
                      WHEN 'p' THEN 'procedure'
                      WHEN 'a' THEN 'aggregate'
                      WHEN 'w' THEN 'window' END AS loai,
       l.lanname AS ngon_ngu,
       pg_get_function_arguments(p.oid) AS tham_so
FROM pg_proc p
JOIN pg_language l ON l.oid = p.prolang
WHERE p.pronamespace = 'shop'::regnamespace
ORDER BY loai, p.proname;
```

Trigger:

```sql
SELECT tgrelid::regclass AS bang, tgname, pg_get_triggerdef(oid) AS dinh_nghia
FROM pg_trigger
WHERE NOT tgisinternal
ORDER BY 1, 2;

SELECT evtname, evtevent, evtfoid::regproc FROM pg_event_trigger;   -- event trigger
```

Định nghĩa view:

```sql
SELECT pg_get_viewdef('shop.v_order_summary'::regclass, true);
```

## 6. Dung lượng dữ liệu

Dung lượng cả database:

```sql
SELECT pg_size_pretty(pg_database_size('shopdb'));
```

Tất cả database:

```sql
SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size
FROM pg_database
ORDER BY pg_database_size(datname) DESC;
```

Từng bảng: tách riêng dữ liệu, index và tổng:

```sql
SELECT c.relname AS bang,
       pg_size_pretty(pg_table_size(c.oid))          AS data_va_toast,
       pg_size_pretty(pg_indexes_size(c.oid))        AS index,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS tong
FROM pg_class c
WHERE c.relnamespace = 'shop'::regnamespace
  AND c.relkind IN ('r', 'm')            -- r = bảng, m = materialized view
ORDER BY pg_total_relation_size(c.oid) DESC;
```

Dung lượng theo schema:

```sql
SELECT n.nspname,
       pg_size_pretty(sum(pg_total_relation_size(c.oid))) AS size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'm')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
GROUP BY n.nspname
ORDER BY sum(pg_total_relation_size(c.oid)) DESC;
```

Một object cụ thể:

```sql
SELECT pg_size_pretty(pg_total_relation_size('shop.orders'));   -- bảng + index + toast
SELECT pg_size_pretty(pg_relation_size('shop.orders'));         -- chỉ phần heap
SELECT pg_size_pretty(pg_relation_size('shop.idx_orders_customer_id'));   -- 1 index
```

Số dòng ước tính (nhanh, không quét bảng) so với đếm thật (chậm nhưng chính xác):

```sql
SELECT relname, n_live_tup, n_dead_tup, last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'shop'
ORDER BY n_live_tup DESC;

SELECT count(*) FROM shop.orders;
```

Dung lượng thư mục data và WAL:

```sql
SHOW data_directory;
SELECT pg_size_pretty(sum(size)) FROM pg_ls_waldir();
```

Dung lượng cột (kiểm tra cột lớn như jsonb, text):

```sql
SELECT pg_size_pretty(sum(pg_column_size(attributes))) FROM shop.products;
```

## 7. Version, cấu hình, trạng thái server

```sql
SELECT version();
SHOW server_version;
SHOW data_directory;
SHOW config_file;
SHOW hba_file;
SELECT pg_postmaster_start_time();            -- server chạy từ lúc nào
SELECT pg_is_in_recovery();                   -- false = primary / standalone
SELECT current_database(), current_user, inet_server_addr(), inet_server_port();
```

Xem tham số:

```sql
SHOW shared_buffers;
SHOW ALL;
SELECT name, setting, unit, source, pending_restart
FROM pg_settings
WHERE name IN ('shared_buffers', 'work_mem', 'max_connections', 'wal_level', 'shared_preload_libraries');

-- tham số nào đã bị đổi khỏi mặc định
SELECT name, setting, source, sourcefile
FROM pg_settings
WHERE source NOT IN ('default', 'override');
```

Sau khi sửa `postgresql.conf` hoặc `ALTER SYSTEM`:

```sql
ALTER SYSTEM SET work_mem = '16MB';
SELECT pg_reload_conf();                      -- áp dụng tham số không cần restart
```

Tham số có `pending_restart = t` thì phải restart service mới có hiệu lực.

Extension có sẵn và đã cài:

```sql
SELECT name, default_version, installed_version FROM pg_available_extensions ORDER BY name;
SELECT extname, extversion FROM pg_extension;
```

## 8. Kết nối và truy vấn đang chạy

```sql
-- ai đang kết nối
SELECT pid, usename, datname, client_addr, state, now() - query_start AS chay_duoc, left(query, 80) AS query
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
ORDER BY query_start;

-- số kết nối theo trạng thái
SELECT state, count(*) FROM pg_stat_activity GROUP BY state;

-- query chạy lâu hơn 1 phút
SELECT pid, now() - query_start AS thoi_gian, query
FROM pg_stat_activity
WHERE state = 'active' AND now() - query_start > interval '1 minute';

-- hủy query (nhẹ) / ngắt kết nối (mạnh)
SELECT pg_cancel_backend(12345);
SELECT pg_terminate_backend(12345);
```

Lock đang chờ:

```sql
SELECT pid, pg_blocking_pids(pid) AS bi_chan_boi, state, left(query, 80)
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;
```

Query tốn nhiều thời gian nhất (cần extension `pg_stat_statements`):

```sql
SELECT calls, round(total_exec_time::numeric, 1) AS tong_ms,
       round(mean_exec_time::numeric, 2) AS tb_ms, left(query, 80) AS query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

## 9. Role và quyền

```
\du                  -- danh sách role
\du+                 -- kèm mô tả
\dp shop.orders      -- quyền trên bảng
\drds                -- cấu hình riêng cho role / database
```

```sql
SELECT rolname, rolsuper, rolcreatedb, rolcanlogin FROM pg_roles ORDER BY 1;

-- quyền của user với 1 bảng
SELECT has_table_privilege('shop_readonly', 'shop.orders', 'SELECT');

-- bảng có bật row level security
SELECT relname, relrowsecurity, relforcerowsecurity
FROM pg_class
WHERE relnamespace = 'shop'::regnamespace AND relkind = 'r';

SELECT schemaname, tablename, policyname, cmd, qual FROM pg_policies;   -- policy RLS
```

## 10. Bảo trì: vacuum, analyze, bloat

```sql
VACUUM (VERBOSE, ANALYZE) shop.orders;
ANALYZE;                                  -- cập nhật thống kê cho toàn database
REINDEX TABLE CONCURRENTLY shop.orders;   -- build lại index không khóa bảng
REFRESH MATERIALIZED VIEW CONCURRENTLY shop.mv_daily_sales;
CHECKPOINT;
```

Bảng có nhiều dòng chết (dead tuple), nên vacuum:

```sql
SELECT relname, n_dead_tup, n_live_tup,
       round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 1) AS ty_le_chet,
       last_autovacuum
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 10;
```

Kiểm tra tính toàn vẹn index B-tree (extension `amcheck`):

```sql
SELECT bt_index_check('shop.orders_pkey'::regclass);
```

## 11. Phân tích query

```sql
EXPLAIN SELECT * FROM shop.orders WHERE customer_id = 100;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM shop.orders WHERE customer_id = 100;
```

`EXPLAIN ANALYZE` chạy thật câu lệnh. Với INSERT / UPDATE / DELETE thì bọc trong transaction rồi rollback:

```sql
BEGIN;
EXPLAIN ANALYZE UPDATE shop.orders SET status = 'cancelled' WHERE order_id = 1;
ROLLBACK;
```

## 12. Cài đặt hiển thị và tiện ích trong psql

```
\x                   -- bật/tắt hiển thị dọc (mỗi cột 1 dòng), hợp với bảng nhiều cột
\x auto              -- tự chọn dọc/ngang theo độ rộng
\timing              -- hiện thời gian chạy mỗi câu lệnh
\pset pager off      -- tắt pager (less)
\pset null '(null)'  -- hiển thị NULL rõ ràng
\pset format csv     -- đổi định dạng output (aligned, csv, html, ...)
\echo text           -- in một dòng chữ
\! ls -l             -- chạy lệnh shell
\i file.sql          -- chạy file SQL
\ir file.sql         -- chạy file, đường dẫn tính từ file hiện tại
\o out.txt           -- ghi kết quả vào file (gọi \o lần nữa để tắt)
\g out.txt           -- chạy câu vừa gõ và ghi vào file
\gset                -- gán kết quả vào biến psql
\watch 5             -- chạy lại câu lệnh trước mỗi 5 giây
\e                   -- mở editor để sửa câu lệnh
\s                   -- lịch sử lệnh
\set                 -- xem các biến
```

Ví dụ `\gset` và `\watch`:

```sql
SELECT count(*) AS so_don FROM shop.orders \gset
\echo :so_don

SELECT now(), count(*) FROM pg_stat_activity \watch 2
```

Xuất bảng ra CSV:

```
\copy (SELECT * FROM shop.countries) TO 'countries.csv' CSV HEADER
\copy shop.countries FROM 'countries.csv' CSV HEADER
```

`\copy` chạy phía client nên đọc/ghi file ở máy đang chạy psql, không cần quyền superuser.

Có thể đặt thói quen riêng trong `~/.psqlrc`:

```
\set QUIET 1
\timing on
\x auto
\pset null '(null)'
\set QUIET 0
```

## 13. Backup và restore (chạy ngoài psql)

```bash
pg_dump -U postgres -Fc shopdb > shopdb.dump        # 1 database, định dạng custom
pg_dump -U postgres -s shopdb > schema_only.sql     # chỉ cấu trúc
pg_dump -U postgres -a shopdb > data_only.sql       # chỉ dữ liệu
pg_dumpall -U postgres --globals-only > globals.sql # role, tablespace

pg_restore -U postgres -d shopdb --clean --if-exists shopdb.dump
pg_restore -l shopdb.dump                           # liệt kê nội dung file dump

createdb -U postgres shopdb
dropdb -U postgres shopdb
```

## 14. Service trên Ubuntu

```bash
sudo systemctl status postgresql
sudo systemctl restart postgresql
sudo pg_lsclusters                                  # danh sách cluster, version, port, trạng thái
sudo tail -n 100 /var/log/postgresql/postgresql-16-main.log
dpkg -l | grep postgresql                           # các package đã cài
apt-cache madison postgresql-16                     # các version có thể cài
```

## 15. Bản tóm tắt nhanh

```
\l   database          \dn  schema           \dt  bảng
\dv  view              \dm  materialized view \di  index
\df  function          \ds  sequence         \dT  kiểu dữ liệu
\dx  extension         \du  role             \dp  quyền
\d tên    cấu trúc     \sf tên  mã function   \x   bật/tắt hiển thị dọc
\c db     đổi database \timing  đo thời gian  \q    thoát
```
