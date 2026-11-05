# 07 – Lỗi substring() trên 15.16 và rollback về 15.6

Nâng cấp 15.6 → 15.16 cài được, cluster lên bình thường, nhưng hàm `shop.fn_review_excerpt()` (cắt đoạn trích của đánh giá sản phẩm) báo lỗi với một phần dữ liệu. Cách xử lý là rollback về 15.6.

Lỗi đã được tái hiện thật trên PostgreSQL 15.16 (Ubuntu 24.04). Máy dev PG 18.4 đã có bản sửa nên không tái hiện được ở đó.

## 1. Lỗi là gì

Release notes 15.17 ghi: "Avoid incorrect complaint of invalid encoding when substring() is applied to toasted data". Bản 15.16 vá CVE-2026-2006 quá chặt, nên `substring()` có thể báo `invalid byte sequence for encoding "UTF8"` (hoặc "incomplete character") với dữ liệu hoàn toàn hợp lệ. Bản sửa là 15.17. Kịch bản này nâng 15.6 → 15.16 rồi quay lại, nên không nâng tiếp lên 15.17.

Giả thuyết dùng để dựng dữ liệu (cần xác nhận): với cột text lưu ngoài dòng (TOAST) không nén, `substring(body, 1, N)` chỉ đọc một đoạn byte đầu của giá trị, tối đa N × 4 byte với UTF8. Đoạn đọc này có thể kết thúc giữa một ký tự nhiều byte. Bản vá chặt coi đó là dữ liệu sai, trong khi bước cắt sau đó vẫn bỏ phần dư đúng cách.

## 2. Dữ liệu và hàm đã dựng

Script `scripts/06_install_review_data.sh` chạy `sql/06_toast_review_objects.sql`:

- Bảng `shop.product_reviews`, 10.000 dòng, cột `body` dài khoảng 3,5 KB, tiếng Anh có ký tự typographic nhiều byte (’ — … €). Cột đặt `STORAGE EXTERNAL`, nên giá trị nằm trong TOAST và không bị nén.
- Review 1 là dòng thử cố định, gồm toàn ký tự ’ (3 byte).
- Hàm `shop.fn_review_excerpt(review_id, len = 40)` trả về `substring(body, 1, len)`.
- View `shop.v_review_excerpt` hiển thị đoạn trích 40 ký tự của mọi đánh giá.

Nghiệp vụ: trang sản phẩm và email tổng hợp dùng đoạn trích này. Khi hàm lỗi, trang không hiển thị được đánh giá.

Kết quả chạy thật trên 15.16-1.pgdg24.04+1: 334/10.000 đánh giá lỗi `invalid byte sequence for encoding "UTF8": 0xe2 0x80`. Giải thích dễ hiểu: `09_giai_thich_loi_toast.md`.

## 3. Chạy trên máy thật

```bash
sudo DB_NAME=shopdb bash scripts/06_install_review_data.sh
sudo bash scripts/07_pre_upgrade_backup.sh
sudo bash scripts/08_upgrade_to_15.16.sh
```

Script 08 in `[ OK ]` hoặc `[FAIL]` cho từng lệnh. Kết quả mong đợi trên 15.16 nếu giả thuyết đúng:

```
[ OK ] fn_review_excerpt(2) ...
[FAIL] fn_review_excerpt(1): ERROR:  invalid byte sequence for encoding "UTF8": ...
[FAIL] v_review_excerpt (all rows): ERROR: ...
[FAIL] all 10k excerpts (no error): ERROR:  NNN reviews cannot be cut
```

Nếu mọi lệnh đều `[ OK ]` trên 15.16, giả thuyết sai ở một chi tiết. Thử lần lượt:

```sql
-- đổi độ dài đoạn trích
SELECT shop.fn_review_excerpt(1, 10);
SELECT shop.fn_review_excerpt(1, 100);

-- xem giá trị có thật sự nằm trong TOAST và có bị nén không
SELECT pg_column_size(body), pg_column_compression(body) FROM shop.product_reviews WHERE review_id = 1;

-- ép lưu ngoài dòng, không nén, rồi ghi lại giá trị
ALTER TABLE shop.product_reviews ALTER COLUMN body SET STORAGE EXTERNAL;
UPDATE shop.product_reviews SET body = body || '';
```

Nếu vẫn không lỗi, ghi kết quả vào mục 5 rồi chỉnh dữ liệu theo điều kiện thật.

## 4. Rollback

```bash
sudo bash scripts/09_rollback_to_15.6.sh
```

Script hạ package về 15.6 (đọc từ `state.env` do script 07 ghi), giữ nguyên thư mục data (minor version dùng chung định dạng đĩa) và khởi động lại cluster. Sau đó chạy lại các câu verify trong `06_verification_queries.md`.

Nếu thư mục data bị hỏng, dùng bản sao nguội: `sudo RESTORE_DATA=1 bash scripts/09_rollback_to_15.6.sh`.

## 5. Ghi chú sau khi chạy thật

(điền sau khi chạy trên 15.16: chuỗi version thực tế, thông báo lỗi nguyên văn, số dòng lỗi)
root@post:/home/thanh/usecase2# tail -n 20 /var/log/postgresql/postgresql-15-main.log
2026-10-23 00:38:11.787 UTC [31996] postgres@shopdb CONTEXT:  SQL function "fn_review_excerpt" statement 1
2026-10-23 00:38:11.787 UTC [31996] postgres@shopdb STATEMENT:  SELECT shop.fn_review_excerpt(1)
2026-10-23 00:38:11.787 UTC [31996] postgres@shopdb LOG:  disconnection: session time: 0:00:00.013 user=postgres database=shopdb host=[local]
2026-10-23 00:38:11.844 UTC [32004] [unknown]@[unknown] LOG:  connection received: host=[local]
2026-10-23 00:38:11.846 UTC [32004] postgres@shopdb LOG:  connection authenticated: identity="postgres" method=peer (/etc/postgresql/15/main/pg_hba.conf:90)
2026-10-23 00:38:11.846 UTC [32004] postgres@shopdb LOG:  connection authorized: user=postgres database=shopdb application_name=psql
2026-10-23 00:38:11.850 UTC [32004] postgres@shopdb LOG:  disconnection: session time: 0:00:00.006 user=postgres database=shopdb host=[local]
2026-10-23 00:38:11.906 UTC [32009] [unknown]@[unknown] LOG:  connection received: host=[local]
2026-10-23 00:38:11.908 UTC [32009] postgres@shopdb LOG:  connection authenticated: identity="postgres" method=peer (/etc/postgresql/15/main/pg_hba.conf:90)
2026-10-23 00:38:11.908 UTC [32009] postgres@shopdb LOG:  connection authorized: user=postgres database=shopdb application_name=psql
2026-10-23 00:38:11.912 UTC [32009] postgres@shopdb ERROR:  invalid byte sequence for encoding "UTF8": 0xe2 0x80
2026-10-23 00:38:11.912 UTC [32009] postgres@shopdb STATEMENT:  SELECT count(*), count(excerpt) FROM shop.v_review_excerpt
2026-10-23 00:38:11.913 UTC [32009] postgres@shopdb LOG:  disconnection: session time: 0:00:00.007 user=postgres database=shopdb host=[local]
2026-10-23 00:38:11.969 UTC [32017] [unknown]@[unknown] LOG:  connection received: host=[local]
2026-10-23 00:38:11.971 UTC [32017] postgres@shopdb LOG:  connection authenticated: identity="postgres" method=peer (/etc/postgresql/15/main/pg_hba.conf:90)
2026-10-23 00:38:11.971 UTC [32017] postgres@shopdb LOG:  connection authorized: user=postgres database=shopdb application_name=psql
2026-10-23 00:38:12.909 UTC [32017] postgres@shopdb ERROR:  334 reviews cannot be cut
2026-10-23 00:38:12.909 UTC [32017] postgres@shopdb CONTEXT:  PL/pgSQL function inline_code_block line 1 at RAISE
2026-10-23 00:38:12.909 UTC [32017] postgres@shopdb STATEMENT:  DO $$ DECLARE r bigint; n int := 0; BEGIN FOR r IN SELECT review_id FROM shop.product_reviews LOOP BEGIN PERFORM shop.fn_review_excerpt(r); EXCEPTION WHEN OTHERS THEN n := n + 1; END; END LOOP; IF n > 0 THEN RAISE EXCEPTION $m$% reviews cannot be cut$m$, n; END IF; END $$
2026-10-23 00:38:12.910 UTC [32017] postgres@shopdb LOG:  disconnection: session time: 0:00:00.941 user=postgres database=shopdb host=[local]
