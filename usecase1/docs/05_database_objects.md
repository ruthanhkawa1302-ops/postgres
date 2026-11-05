# 05 – Các thành phần database (script: `sql/05_database_objects.sql`)

```bash
sudo -u postgres psql -d shopdb -f sql/05_database_objects.sql
```

Chạy sau 02 (schema), 03 (data), 04 (extension). Script **chạy lại được** và chỉ cần extension contrib. Nguyên tắc thiết kế: **mỗi loại thành phần vài cái tiêu biểu, ưu tiên đa dạng**.

## 0. Tổng hợp số lượng (toàn database sau khi chạy 02 → 05)

| Thành phần | Số lượng | Danh sách |
|---|---:|---|
| Bảng | 10 | 7 bảng gốc + `audit_log`, `promotions`, `warehouses` (không có bảng partition) |
| Index | 27 | 19 index từ bước 02 + 8 index ở bước 05 (xem mục 1) |
| Khóa ngoại | 9 | 7 ở bước 02 (kể cả 1 FK tự tham chiếu) + `promotions.product_id`, `warehouses.country_code` |
| View | 3 | `v_order_summary`, `v_customers_masked`, `v_active_products` |
| Materialized view | 1 | `mv_daily_sales` |
| Function | 11 | 6 hàm nghiệp vụ + 2 hàm cho aggregate + 3 trigger function |
| Procedure | 2 | `sp_place_order`, `sp_update_order_status` |
| Aggregate | 1 | `weighted_avg` |
| Trigger | 3 | `trg_orders_updated_at`, `trg_orders_audit`, `trg_products_audit` |
| Event trigger | 1 | `evt_ddl_audit` |
| Sequence | 10 | 9 sequence identity + `order_number_seq` |
| Kiểu dữ liệu | 3 | ENUM `order_status`, DOMAIN `money_amount`, COMPOSITE `order_line_input` |
| RLS policy | 2 | `p_orders_readonly`, `p_orders_portal` |
| Extended statistics | 1 | `st_customers_country_city` |
| Role | 3 | `shop_readonly`, `shop_portal`, `demo_analyst` (login) |
| Extension | 8 | đều là contrib, xem `04_extensions.md` |

## 1. Index tạo thêm ở bước 05 (8)

| Index | Bảng | Loại | Extension |
|-------|------|------|-----------|
| `idx_products_name_trgm` | products(product_name) | GIN `gin_trgm_ops` | **pg_trgm** |
| `idx_warehouses_location` | warehouses(location) | GiST trên kiểu `point` (core), hỗ trợ KNN `<->` | – |
| `ex_promotions_no_overlap` | promotions(product_id, valid_during) | GiST (exclusion constraint) | **btree_gist** |
| `promotions_promo_code_key` | promotions(promo_code) | B-tree UNIQUE trên kiểu citext | **citext** |
| `uq_mv_daily_sales` | mv_daily_sales(sales_date, sales_channel) | B-tree UNIQUE, cần cho `REFRESH CONCURRENTLY` | – |
| `audit_log_pkey`, `promotions_pkey`, `warehouses_pkey` | | B-tree PK | – |

Các loại index có trong database: **B-tree, composite, covering, partial, unique expression, GIN, BRIN, Hash,
trigram GIN, GiST, exclusion** (11 loại).

## 2. Sequence, composite type, aggregate

| Object | Ý nghĩa |
|--------|---------|
| `shop.order_number_seq` | Sinh số đơn `ORD-xxxxxxxxxx` cho đơn mới (bắt đầu từ max(order_id)+1) |
| `shop.order_line_input` | Kiểu composite `(product_id, quantity)`, là tham số mảng của `sp_place_order` |
| `shop.weighted_avg(numeric, numeric)` | Aggregate tự định nghĩa: trung bình có trọng số (hàm `wavg_sfunc` + `wavg_ffunc`) |

## 3. Bảng / cột mới

| Object | Ý nghĩa | Extension |
|--------|---------|-----------|
| `audit_log` | Ghi thay đổi dòng của `orders`, `products` (`changed_fields` dạng hstore) và mọi lệnh DDL (`operation = 'DDL'`) | **hstore** |
| `promotions` | 10.000 khuyến mãi; `promo_code citext UNIQUE` và exclusion constraint chặn thời gian chồng nhau | **citext, btree_gist** |
| `warehouses` | 9 kho, tọa độ lưu bằng kiểu `point(longitude, latitude)` có sẵn trong core | – |

## 4. Materialized view

| MV | Nội dung | Refresh |
|----|----------|---------|
| `mv_daily_sales` | Doanh thu, số đơn, AOV, số khách theo **ngày × kênh bán** (bỏ đơn CANCELLED) | `REFRESH MATERIALIZED VIEW CONCURRENTLY` (chạy tay) |

## 5. View

| View | Ý nghĩa | Đặc điểm |
|------|---------|----------|
| `v_order_summary` | Đơn + tên khách + số dòng + trạng thái thanh toán gần nhất | JOIN + `LATERAL` + subquery |
| `v_customers_masked` | Dữ liệu khách đã che PII: email che / hash SHA-256, phone che | **pgcrypto** `digest` |
| `v_active_products` | Sản phẩm đang bán, **updatable view** `WITH CASCADED CHECK OPTION` | Không cho update làm sản phẩm thành inactive |

## 6. Function (11)

| Function | Loại | Ý nghĩa | Extension |
|----------|------|---------|-----------|
| `fn_customer_lifetime_value(customer_id)` | PL/pgSQL, trả numeric | Tổng chi tiêu (bỏ đơn hủy/trả); raise lỗi nếu khách không tồn tại | – |
| `fn_get_order_details(order_id)` | SQL, trả jsonb | Toàn bộ đơn (khách, dòng, thanh toán) dạng JSON | – |
| `fn_search_products(query, limit)` | SQL, trả TABLE | Tìm sản phẩm gần đúng (gõ sai chính tả vẫn ra) | **pg_trgm** |
| `fn_monthly_sales_pivot(year)` | SQL, trả TABLE | Doanh thu 12 tháng × 4 kênh bán | **tablefunc** |
| `fn_similar_products(product_id, k)` | PL/pgSQL, trả TABLE | K sản phẩm cùng danh mục có tên giống nhất | **pg_trgm** |
| `fn_nearest_warehouses(lat, lon, k)` | SQL, trả TABLE | K kho gần nhất + khoảng cách km (công thức haversine) | – |
| `wavg_sfunc`, `wavg_ffunc` | SQL | Hàm state/final của aggregate `weighted_avg` | – |
| `trg_set_updated_at()` | trigger function | Cập nhật `updated_at` | – |
| `trg_audit_row()` | trigger function | Ghi audit, chỉ lưu cột thay đổi | **hstore** |
| `trg_log_ddl()` | event trigger function, SECURITY DEFINER | Ghi DDL vào `audit_log` | – |

## 7. Procedure (2)

| Procedure | Ý nghĩa |
|-----------|---------|
| `sp_place_order(customer_id, items order_line_input[], INOUT order_id)` | Tạo đơn: trừ tồn kho (`stock_qty`, báo lỗi nếu hết hàng), thêm dòng, tính tổng tiền, sinh số đơn từ sequence |
| `sp_update_order_status(order_id, new_status)` | Đổi trạng thái theo state machine (PENDING→PAID→PROCESSING→SHIPPED→DELIVERED→RETURNED, được hủy trước khi ship). Khóa dòng bằng `FOR UPDATE`; thay đổi được ghi audit |

## 8. Trigger (3) & event trigger (1)

| Trigger | Bảng / sự kiện | Function |
|---------|---------------|----------|
| `trg_orders_updated_at` | orders BEFORE UPDATE | `trg_set_updated_at()` |
| `trg_orders_audit` | orders AFTER UPDATE OR DELETE | `trg_audit_row('order_id')` |
| `trg_products_audit` | products AFTER UPDATE OF unit_price, unit_cost, is_active OR DELETE | `trg_audit_row('product_id')` |
| `evt_ddl_audit` (event trigger) | `ddl_command_end`, áp dụng toàn database | `trg_log_ddl()` |

## 9. Role, quyền, Row Level Security, extended statistics

| Role | Quyền |
|------|-------|
| `shop_readonly` (NOLOGIN) | SELECT mọi bảng (**trừ** `audit_log`), EXECUTE function; RLS policy `p_orders_readonly` cho thấy mọi đơn |
| `demo_analyst` / `Analyst@123` (LOGIN, thuộc `shop_readonly`) | Dùng để test kết nối từ client |
| `shop_portal` (NOLOGIN) | Chỉ SELECT `orders`; policy `p_orders_portal` giới hạn theo `current_setting('app.customer_id')` |

* Extended statistics `st_customers_country_city` (dependencies, ndistinct, mcv): city phụ thuộc country,
  giúp planner ước lượng số dòng chính xác hơn. Liên quan bản 16.3: CVE-2024-4317, xem §11 của file verify.
* Đổi mật khẩu `demo_analyst` trước khi mở mạng.

## 10. Extension → object sử dụng

| Extension | Object |
|-----------|--------|
| pg_trgm | `idx_products_name_trgm`, `fn_search_products`, `fn_similar_products` |
| citext | `promotions.promo_code` |
| hstore | `audit_log.changed_fields`, `trg_audit_row` |
| tablefunc | `fn_monthly_sales_pivot` |
| btree_gist | `promotions.ex_promotions_no_overlap` |
| pgcrypto | `v_customers_masked` |
| pg_stat_statements, amcheck | dùng trong các câu verify (`06_verification_queries.md`) |
