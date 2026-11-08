# CLAUDE.md – Nhật ký & trạng thái project (đọc file này trước khi làm tiếp)

> File này ghi lại những gì đã làm, các quyết định đã chốt với người dùng và trạng thái hiện tại.
> **Mỗi khi hoàn thành yêu cầu mới, cập nhật mục 3 (trạng thái) và thêm 1 dòng vào mục 5 (lịch sử).**
> Người dùng giao tiếp bằng **tiếng Việt**, nên trả lời và viết docs bằng tiếng Việt. Code, comment SQL và dữ liệu dùng tiếng Anh.

## 1. Mục tiêu project

Yêu cầu gốc: `requirement/requirement.txt` + `requirement/usecase1.png` (UC01).

Dựng **1 server PostgreSQL standalone** (không replication / HA) trên **Ubuntu 24.04**, dùng để demo
**nâng cấp minor version 16.2 → 16.3** (in-place bằng apt). Expected result của UC01:
1. PostgreSQL chạy 16.3.
2. Service active, client bất kỳ kết nối được.
3. Database và dữ liệu truy cập bình thường.
4. Log không có lỗi nghiêm trọng chưa xử lý sau patch.

## 2. Các quyết định đã chốt với người dùng

| Chủ đề | Quyết định |
|---|---|
| Version | 16.2 → 16.3 (không phải 16.1 → 16.2). Cài `postgresql-16=16.2-2.pgdg24.04+1` từ `https://apt-archive.postgresql.org/pub/repos/apt noble-pgdg-archive main`, `apt-mark hold` |
| Kiến trúc | **Standalone**, 1 node. `wal_level = minimal`, `max_wal_senders = 0` |
| Dung lượng dữ liệu | **~100 MB** (7–8 GB → 3–4 GB → 2.4 GB → 1.5 GB → 100 MB). Mặc định `scale = 0.03` (ước tính theo 335 MB/0.1; 0.44 = ~1.5 GB, 1 = ~3.4 GB) |
| Số lượng object | **Đa dạng, không cần nhiều**: mỗi loại vài cái. Index giảm mạnh, **không dùng bảng partition** (đã bỏ pg_partman) |
| Dữ liệu | Tiếng Anh, sinh bằng SQL (`generate_series` + `random()` + `setseed`), phù hợp với index |
| Output | Script cài đặt (.sh), script SQL riêng cho từng bước, docs riêng cho schema / extension / object, file .md verify trước/sau upgrade |

## 3. Trạng thái hiện tại – UC01 (thư mục `usecase1/`)

Project chia 2 thư mục độc lập: `usecase1/` (16.2 → 16.3) và `usecase2/` (15.6 → 15.12 lỗi + rollback, xem mục 3b). Đường dẫn dưới đây tính từ `usecase1/`; README.md ở gốc chỉ là mục lục.

```
requirement/                      Yêu cầu gốc (không sửa, nằm ở gốc)
scripts/01_install_postgresql_16.2.sh   Cài 16.2 từ apt-archive, pin + hold, conf.d/00-demo.conf (standalone), pg_hba mở ALLOW_CIDR, tạo DB shopdb
scripts/04_install_extensions.sh        Không cài package; conf.d/10-extensions.conf (preload pg_stat_statements); restart; chạy sql/04
sql/02_schema.sql                 Schema shop: 7 bảng, 1 enum, 1 domain, 19 index (10 từ PK/UNIQUE + 9 tạo tay, mỗi loại 1 cái)
sql/03_insert_data.sql            Dữ liệu, tham số -v scale=<n> (mặc định 0.44), nạp theo lô 250k đơn, re-runnable (TRUNCATE)
sql/04_extensions.sql             CREATE EXTENSION 8 cái (chỉ contrib)
sql/05_database_objects.sql       Các object còn lại, re-runnable, chỉ cần extension contrib
docs/00_tong_hop_trien_khai.md    Doc cho team: gom script theo bước + giải thích ngắn, văn phong đơn giản (ít bảng/bold), không có verify
docs/02_schema.md                 ERD (mermaid), bảng, index, dữ liệu, dung lượng
docs/04_extensions.md             8 extension contrib: dùng làm gì, dùng ở đâu
docs/05_database_objects.md       Bảng tổng hợp số lượng (mục 0) + chi tiết từng object + extension → object
docs/06_verification_queries.md   Chỉ 3 lệnh verify trước/sau (version+service, dữ liệu count/sum/md5 + diff file, log) + quy trình upgrade (gồm fix CVE-2024-4317) + rollback. Không cần sql 04/05
docs/07_ban_minor_anh_huong.md    Phân tích 16.3–16.13: không bản nào làm hỏng object; 16.3 đổi pg_stats_ext (demo_analyst 1 -> 0 dòng sau fix CVE). Đã test phần "sau" trên PG18
README.md                         Thứ tự chạy + bảng tổng hợp
```

### Schema `shop` (sau khi chạy 02 → 05)

- **Bảng (10):** countries, categories (FK tự tham chiếu), customers, products (có `stock_qty`, `attributes jsonb`), orders, order_items, payments, audit_log, promotions, warehouses (`location point`).
- **Số dòng ở scale=0.03 (mặc định, ~100 MB, ước tính):** customers 15k, products 1.5k, orders 114k, order_items ~342k, payments ~114k, categories 30, countries 30, promotions 10k, warehouses 9. (scale=0.44 cho ~1.5 GB: 220k / 22k / 1.672M / ~5.02M / ~1.672M.)
- **Index (27):** B-tree FK, composite, covering INCLUDE, partial, unique expression `lower(email)`, GIN jsonb_path_ops, BRIN, Hash, trigram GIN, GiST trên `point`, exclusion GiST (btree_gist), unique trên citext, unique của MV, các PK.
- **Extension (8, đều contrib):** pg_trgm, citext, hstore, tablefunc, btree_gist, pgcrypto, pg_stat_statements, amcheck. **Đã bỏ postgis, vector, pg_cron** (xung đột `Breaks: postgresql-16-jit-llvm (< 19)` với 16.2 bị hold).
- **View (3):** v_order_summary, v_customers_masked (pgcrypto), v_active_products (WITH CHECK OPTION).
- **Materialized view (1):** mv_daily_sales (unique index, REFRESH CONCURRENTLY).
- **Function (11):** fn_customer_lifetime_value, fn_get_order_details, fn_search_products (pg_trgm), fn_monthly_sales_pivot (tablefunc), fn_similar_products (pg_trgm, cùng danh mục), fn_nearest_warehouses (haversine trên point), wavg_sfunc, wavg_ffunc, trg_set_updated_at, trg_audit_row (hstore), trg_log_ddl.
- **Procedure (2):** sp_place_order (dùng composite type `order_line_input[]`, trừ `stock_qty`), sp_update_order_status (state machine).
- **Aggregate (1):** weighted_avg. **Sequence:** order_number_seq (+ 9 identity).
- **Trigger (3):** trg_orders_updated_at, trg_orders_audit, trg_products_audit. **Event trigger (1):** evt_ddl_audit, ghi vào audit_log với `operation='DDL'`.
- **Bảo mật:** role shop_readonly, shop_portal, demo_analyst (login, `Analyst@123`); RLS trên orders gồm 2 policy (`app.customer_id`). Extended stats: st_customers_country_city.

## 3b. UC02 (thư mục `usecase2/`) – nâng cấp 15.6 → 15.16 thất bại, phải rollback

Bản sao của UC01 chuyển sang PG 15 (sql 02–05 giống hệt, docs 02/04/05/06 đã sửa version) cộng thêm:

```
scripts/01_install_postgresql_15.6.sh   Như UC01 nhưng PG 15, tự dò chuỗi 15.6-* bằng apt-cache madison
scripts/06_install_review_data.sh       Kiểm tra encoding UTF8, chạy sql/06 (không cài extension/package)
scripts/07_pre_upgrade_backup.sh        pg_dumpall --globals, pg_dump -Fc, cold copy data dir (tar), state.env (OLD_VERSION)
scripts/08_upgrade_to_15.16.sh          unhold + apt install 15.16 (policy-rc.d chặn restart), restart tay, smoke test; có [FAIL] -> exit 1 + hướng dẫn rollback
scripts/09_rollback_to_15.6.sh          apt --allow-downgrades về OLD_VERSION, giữ data dir (RESTORE_DATA=1 để giải nén cold copy), kiểm tra nhanh
sql/06_toast_review_objects.sql         product_reviews (10k dòng, body ~3.5KB, STORAGE EXTERNAL, ký tự ’ — … €; review 1 toàn ’), fn_review_excerpt(id, len=40) = substring(body,1,len), v_review_excerpt
docs/07_loi_substring_toast_va_rollback.md  Giải thích lỗi, giả thuyết kích hoạt, cách chạy, cách thử nếu không lỗi, mục 5 để điền kết quả thật
docs/08_cac_ban_minor_loi.md            Ghi chú các bản 15.x từng lỗi thật: 15.9, 15.11, 15.16; bản sửa 15.10/15.12/15.17
```

**Rút gọn (yêu cầu 17)**: usecase2 chỉ còn bảng demo + hàm, không còn sql 02–05, script 04, docs 02/04/05; sql/06 tự tạo schema shop, không FK, review_id lỗi = 1 và id%30=19 (334 dòng). docs/00 và docs/06 viết lại ngắn. Số thứ tự file 06–09 giữ nguyên.
Đã bỏ hoàn toàn extension giả lập legacy_guard (thư mục, script, sql, docs). Lỗi UC02 là hồi quy thật của 15.16 (CVE-2026-2006, sửa ở 15.17): `substring()` trên text TOAST có ký tự nhiều byte báo `invalid byte sequence for encoding`.
**Đã tái hiện thật trên Ubuntu 15.16-1.pgdg24.04+1**: smoke test [FAIL] fn_review_excerpt(1) và v_review_excerpt `invalid byte sequence for encoding "UTF8": 0xe2 0x80`, 334/10000 review lỗi (khớp dự đoán: review 1 + review_id%30=19, đoạn slice 160 byte kết thúc bằng đúng 1 byte đầu `e2` của ký tự 3 byte). Dev PG 18.4 đã sửa nên không tái hiện cục bộ. Giải thích dễ hiểu: docs/09.

## 4. Cách tự test trên máy Windows này

Máy có sẵn PostgreSQL **18** (Windows) tại `/c/Program Files/PostgreSQL/18/bin`. Máy không có Docker/WSL/Python;
có Git Bash và perl. Project chỉ dùng extension contrib nên test được toàn bộ script.

```bash
# chạy từ usecase1/ (hoặc usecase2/)
S=<scratchpad>; B="/c/Program Files/PostgreSQL/18/bin"; P="$B/psql"
"$B/initdb" -D "$S/pgdata" -U postgres -A trust -E UTF8 --no-locale
echo "shared_preload_libraries='pg_stat_statements'" >> "$S/pgdata/postgresql.conf"
"$B/pg_ctl" -D "$S/pgdata" -o "-p 55432" -l "$S/pg.log" -w start
"$P" -p 55432 -U postgres -c "create database shopdb"
"$P" -p 55432 -U postgres -d shopdb -f sql/02_schema.sql
"$P" -p 55432 -U postgres -d shopdb -v scale=0.1 -f sql/03_insert_data.sql      # ~3 phút, ~335 MB
"$P" -p 55432 -U postgres -d shopdb -f sql/04_extensions.sql
"$P" -p 55432 -U postgres -d shopdb -f sql/05_database_objects.sql
awk '/^```sql/{f=1;next} /^```/{f=0} f' docs/06_verification_queries.md > "$S/06_test.sql"   # các khối SQL trong file verify
# xong thì: pg_ctl -D "$S/pgdata" stop -m fast && rm -rf "$S/pgdata"
```

Lưu ý khi viết SQL (rút ra từ các lỗi đã gặp):
- Phải tương thích **PG16**: identity column trên bảng partitioned chỉ có từ PG17 (hiện không còn partition).
- `chr()` và `round(x, n)` cần cast (`::int`, `::numeric`).
- `"char"` (relkind/prokind) phải cast `::text` trước khi nối chuỗi.
- `CALL` không nhận subquery làm tham số; dùng `\gset` hoặc khối `DO`.
- Hàm dùng symbol của extension thì đặt `SET search_path = shop, public`.
- MV phải được tạo **trước** các SQL function tham chiếu tới nó (SQL function bị validate lúc tạo).

## 5. Lịch sử thay đổi

| # | Yêu cầu của người dùng | Đã làm |
|---|---|---|
| 1 | Đọc `requirement/`, tạo toàn bộ output | Tạo script cài 16.2, schema 13 bảng, data ~7.4 GB, 22 extension, object đầy đủ (có partition + pg_partman), file verify |
| 2 | Chỉ cần **standalone** | `wal_level=minimal`, `max_wal_senders=0`, `max_replication_slots=0`; verify kiểm tra `pg_is_in_recovery()=false` |
| 3 | Dữ liệu chỉ **3–4 GB** | Giảm volume, đo lại ở scale 0.1 |
| 4 | Hỏi `scale=1.0` | Trả lời: đó là mặc định, ra ~3.3–3.7 GB |
| 5 | Tổng hợp số lượng object | Lập bảng (khi đó: 75 index, 22 function, 4 procedure…) |
| 6 | **Giảm mọi thứ còn ~1/2, index giảm mạnh, bỏ partition, ưu tiên đa dạng** | Viết lại 02–06 và docs: 10 bảng, 28 index, 11 extension, 11 function, 2 procedure… Tăng số đơn lên 3.8M để giữ ~3.4 GB. Đã test (bỏ phần EXT) |
| 7 | Tạo file theo dõi tiến độ | Tạo `CLAUDE.md` này |
| 8 | Cài postgis/pgvector/pg_cron lỗi `Breaks: postgresql-16-jit-llvm (< 19)`; **bỏ 3 extension bên thứ ba** | 04 chỉ còn 8 ext contrib, script .sh không cài package, preload chỉ pg_stat_statements. 05: warehouses dùng `point` + GiST, fn_nearest_warehouses (haversine), fn_similar_products (pg_trgm), bỏ embedding/HNSW/cron job. Cập nhật docs, verify, README (27 index, 8 ext) |
| 9 | **Giảm dữ liệu 1 GB** (đã chạy xong 02→05) | Hướng dẫn chạy lại 03 với `-v scale=0.7` rồi chạy lại 05 (TRUNCATE CASCADE xóa cả promotions). Đổi mặc định `scale` 1 → 0.7 (~2.35 GB), cập nhật 03, README, docs/02, comment WAL trong 01 |
| 10 | **Giảm dữ liệu còn 1.5 GB** để chừa chỗ backup (đã chạy xong 02→05) | Đổi mặc định `scale` 0.7 → 0.44 (~1.5 GB, tính theo 335 MB/0.1). Hướng dẫn chạy lại 03 + 05 rồi `VACUUM`/`CHECKPOINT`. Cập nhật 03, README, docs/02, comment trong 01 |
| 11 | Tạo 1 file .md tổng hợp cho team đọc (cài DB, bảng, index, function, procedure, extension, gendata), không cần phần verify | Tạo `docs/00_tong_hop_trien_khai.md`, thêm vào README |
| 12 | Doc 00 trông "giống AI", chỉ cần gom script + giải thích ngắn | Viết lại `docs/00_tong_hop_trien_khai.md`: mỗi bước 1–2 câu + code thật lấy từ script, bỏ bảng/bold/emoji |
| 13 | Bỏ pgBackRest, rollback mọi thứ về trước bước đó | Xóa script 07 và docs/07 pgBackRest, sửa README/CLAUDE.md |
| 14 | **UC02**: tách thành 2 folder; UC02 = cài PG 15.6, nâng 15.12 phải lỗi và rollback | Chuyển UC01 vào `usecase1/`; tạo `usecase2/` (bản sao sang PG 15) + C extension legacy_guard, sql/06, scripts 06–09, docs/07, sửa docs/06. Chưa chạy trên Ubuntu thật |
| 15 | Extension giả lập bằng C bị lỗi, đổi sang extension thật | Bỏ C, viết legacy_guard bằng SQL trên pgcrypto (không build), script 06 đổi tên 06_install_legacy_guard.sh, 08 thêm smoke test, docs/06/07/04/00 sửa. Đã nói rõ với user: không có extension thật nào hỏng giữa 15.6 và 15.12 |
| 16 | **UC02 đổi lỗi**: bỏ legacy_guard, tái hiện hồi quy 15.16 (substring + TOAST) | Xóa legacy_guard; thêm sql/06_toast_review_objects.sql, script 06_install_review_data.sh, 08_upgrade_to_15.16.sh; sửa 07/09/01, docs 00/04/06/07/08, README. Test SQL trên PG18 (không tái hiện được lỗi vì 18.4 đã sửa) |
| 18 | UC01: bỏ cấu hình postgresql.conf trong script 01 (giống UC02), giảm dữ liệu còn ~100 MB | Script 01 chỉ còn sửa pg_hba (bỏ conf.d/00-demo.conf). sql/03 và README: mặc định scale 0.44 → 0.03. Chưa sửa docs/00, 02, 06 (còn nhắc 00-demo.conf, wal_level, 1.5 GB, bảng số dòng scale 0.44). Chưa đo dung lượng thật |
| 19 | UC01 verify chỉ 3 lệnh (hết thời gian chạy hết) | Viết lại docs/06: lệnh 1 version+service, lệnh 2 dữ liệu (count/sum/md5, tee ra file rồi diff), lệnh 3 log. Giữ phần upgrade + CVE + rollback. Sửa scripts/04 dùng `< file` thay `-f` (postgres không đọc được /root). Chưa chạy thử 3 lệnh |
| 20 | Cheat sheet lệnh psql (liệt kê table/index/function, dung lượng...) | Tạo `psql_cheatsheet.md` ở gốc project (chưa chạy thử từng câu SQL) |
| 21 | UC01 docs/06: verify đầy đủ index, function, data... trước/sau patch | Viết lại thành 6 lệnh, ghi `/tmp/verify_<TAG>_*.txt` rồi diff: version, checksum từng bảng, index (invalid/pg_amcheck/so index-vs-seq), function/procedure/view/trigger (hash + gọi thật), constraint/extension/quyền, log. Chưa chạy thử trên Ubuntu/PG16 (chỉ viết) |
| 22 | UC01 docs/06: thêm SELECT + EXPLAIN ANALYZE chứng minh index hoạt động | Thêm "Lệnh 7": vòng lặp PASS/FAIL 21 câu SELECT (mỗi câu một index, ép `enable_seqscan=off`), so plan có/không có index, đọc `pg_stat_user_indexes.idx_scan`. Chưa chạy thử trên PG16 |
| 23 | File riêng: mỗi index 1 câu EXPLAIN ANALYZE (27 index user liệt kê) | Tạo `usecase1/sql/07_explain_all_indexes.sql` (ép `enable_seqscan=off`, VACUUM ANALYZE trước). Chưa chạy thử |
| 24 | UC02: thêm table/index/function, ~80 MB, script cài từ đầu + script cài tiếp | Thêm `usecase2/sql/10_extra_objects.sql` (7 bảng, 13 index tạo tay, 4 function, 1 procedure, 2 view, scale mặc định 1 = ~86 MB; chỉ drop object của chính nó, không đụng product_reviews), `scripts/10_install_extra_only.sh` (cài tiếp), `scripts/11_install_full.sh` (01 + 06 + 10). Test sql trên PG18; .sh mới kiểm `bash -n` |
| 25 | UC02: check lại toàn bộ data/function/index trước và sau upgrade, chỉ SELECT, 1 file, không md5 | `usecase2/sql/12_verify_all.sql`: 8 SELECT aggregate (count/sum/min/max) cho bảng, 24 EXPLAIN (ANALYZE, BUFFERS OFF, COSTS OFF, TIMING OFF, SUMMARY OFF) cho từng index (ép enable_seqscan=off), gọi thẳng function/view, structure. `psql -X -f` trước/sau rồi diff. Test PG18: 2 lần chạy giống hệt |
| 26 | UC02: 3 script check trong scripts/ giống UC1 | `usecase2/scripts/verify_1_data.sh` (đếm/sum/md5 mọi bảng), `verify_2_index.sh` (amcheck B-tree + index invalid; tự CREATE EXTENSION amcheck), `verify_3_function.sh` (gọi mọi function/view + fn_review_excerpt toàn bộ review). Xóa verify_2_substring.sh (gộp vào 3). Test PG18, chưa chạy trên Ubuntu |
| 27 | UC02: các script check là check tổng thể toàn bộ data/index/function như UC1, không phải check riêng substring | `verify_3_function.sh` gọi cả fn_review_excerpt và v_review_excerpt như mọi function/view khác (4 function + 2 view + 2 excerpt + procedure). verify_1/2 không đổi. Test PG18 |
| 17 | UC02 chỉ giữ bảng demo bị lỗi + function, bỏ hết data khác | Xóa sql 02–05, scripts/04, docs 02/04/05; sửa sql/06 (CREATE SCHEMA, bỏ FK/GRANT), 08/09 (bỏ shop.orders), 01; viết lại docs 00/06, README. Test sql/06 trên DB trống PG18 |

## 6. Việc còn mở / cần lưu ý khi chạy thật

- Chưa chạy trọn trên Ubuntu 24.04 thật: các script `.sh` mới kiểm tra `bash -n`.
- (UC01) Chuỗi version 16.3 (`16.3-1.pgdg24.04+1`) chưa xác minh; cần kiểm tra bằng `apt-cache madison postgresql-16`.
- 16.3 cần chạy `fix-CVE-2024-4317.sql` cho mọi DB (kể cả template0/1), đã ghi trong verify §11.
- Mật khẩu demo (`Postgres@123`, `Analyst@123`) và `pg_hba` mở `0.0.0.0/0` chỉ dùng cho lab.
