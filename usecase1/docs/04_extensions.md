# 04 – Extension đã cài (script: `scripts/04_install_extensions.sh` + `sql/04_extensions.sql`)

```bash
sudo DB_NAME=shopdb bash scripts/04_install_extensions.sh
```

Script thực hiện:

1. Kiểm tra `postgresql-16` vẫn đang **hold ở 16.2**.
2. Tạo `/etc/postgresql/16/main/conf.d/10-extensions.conf` với
   `shared_preload_libraries = 'pg_stat_statements'`.
3. Restart service, sau đó chạy `sql/04_extensions.sql` (`CREATE EXTENSION`) trong database `shopdb`.

Project **chỉ dùng extension contrib**. Các extension này đi kèm package `postgresql-16`, nên **không cần cài thêm package apt nào**.
Các extension bên thứ ba (PostGIS, pgvector, pg_cron) đã bị bỏ. Lý do: trên repo `apt-archive`, bản build mới nhất
của chúng đòi server build bằng LLVM mới hơn bản 16.2 (`Breaks: postgresql-16-jit-llvm (< 19)`), nên xung đột với
gói `postgresql-16` đang bị hold.

> Khi nâng minor 16.2 → 16.3, extension contrib được nâng cùng package server và `extversion` **không đổi**.
> File verify (§6) kiểm tra đúng điều này.

## Danh sách: 8 extension (đều là contrib)

| # | Extension | Nhóm | Dùng để làm gì | Dùng trong demo |
|---|-----------|------|----------------|-----------------|
| 1 | **pg_trgm** | tìm kiếm | So khớp gần đúng bằng trigram (`similarity`, `%`); giúp `ILIKE '%...%'` dùng được index | index `idx_products_name_trgm`, hàm `fn_search_products`, `fn_similar_products` |
| 2 | **citext** | kiểu dữ liệu | Text không phân biệt hoa thường (so sánh, UNIQUE) | `promotions.promo_code` |
| 3 | **hstore** | kiểu dữ liệu | Key/value; `hstore(NEW) - hstore(OLD)` cho ra các cột đã đổi | trigger audit `trg_audit_row` |
| 4 | **tablefunc** | xử lý dữ liệu | `crosstab()` pivot dòng thành cột | hàm `fn_monthly_sales_pivot` |
| 5 | **btree_gist** | index | Cho phép đưa cột scalar vào GiST, cần cho exclusion constraint | `promotions`: không cho khuyến mãi trùng thời gian |
| 6 | **pgcrypto** | bảo mật | Hash (`digest`), bcrypt (`crypt`), random bytes | view `v_customers_masked` (hash email) |
| 7 | **pg_stat_statements** *(preload)* | giám sát | Thống kê mọi câu SQL: số lần gọi, thời gian, I/O | so hiệu năng trước/sau upgrade |
| 8 | **amcheck** | toàn vẹn | Kiểm tra cấu trúc B-tree (`bt_index_check`) và heap (`verify_heapam`) | verify §5, phát hiện hỏng index sau patch |

## Cấu hình thêm (`conf.d/10-extensions.conf`)

| Tham số | Giá trị | Ý nghĩa |
|---------|---------|---------|
| `shared_preload_libraries` | `pg_stat_statements` | Thư viện nạp khi khởi động |
| `pg_stat_statements.max / track` | `10000 / all` | Số câu SQL được theo dõi; theo dõi cả SQL bên trong function |
| `track_io_timing` | `on` | Thời gian I/O trong thống kê và `EXPLAIN (BUFFERS)` |

## Lưu ý

* Extension là object riêng của **từng database**. Muốn xem đúng thì phải kết nối vào `shopdb`
  (`psql -d shopdb`, rồi `\dx`). Chạy `psql` không có `-d` sẽ vào DB `postgres` và chỉ thấy `plpgsql`.
* Nếu trước đó đã lỡ tạo `10-extensions.conf` có `pg_cron`, chạy lại script này sẽ ghi đè file đó.
