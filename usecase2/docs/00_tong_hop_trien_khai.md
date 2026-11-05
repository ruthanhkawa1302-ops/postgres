# Tổng hợp triển khai UC02

UC02 chỉ cần một server PostgreSQL 15.6 standalone, một database `shopdb`, một bảng demo và một hàm. Giải thích dễ hiểu về lỗi: `09_giai_thich_loi_toast.md`.

## 1. Cài PostgreSQL 15.6

Script cài đúng bản 15.6 từ kho apt-archive, giữ version bằng `apt-mark hold`, cấu hình standalone và tạo database `shopdb` (UTF8).

```bash
sudo PG_PASSWORD='fpt@123' bash scripts/01_install_postgresql_15.6.sh
```

## 2. Bảng demo và hàm

Bảng `shop.product_reviews` có 10.000 đánh giá tiếng Anh, mỗi bài khoảng 3,5 KB và có ký tự nhiều byte (’ — … €). Cột `body` đặt `STORAGE EXTERNAL` nên nằm trong TOAST, không nén. Review 1 toàn ký tự ’.

```bash
sudo DB_NAME=shopdb bash scripts/06_install_review_data.sh
```

```sql
ALTER TABLE shop.product_reviews ALTER COLUMN body SET STORAGE EXTERNAL;
```

Hàm lấy 40 ký tự đầu của một đánh giá:

```sql
CREATE OR REPLACE FUNCTION shop.fn_review_excerpt(p_review_id bigint, p_len integer DEFAULT 40)
RETURNS text
LANGUAGE sql STABLE
AS $$
    SELECT substring(body, 1, p_len) FROM shop.product_reviews WHERE review_id = p_review_id;
$$;
```

View `shop.v_review_excerpt` cắt 40 ký tự đầu của cả 10.000 đánh giá.

## 3. Backup, nâng cấp lỗi, rollback

Backup (pg_dump, cold copy thư mục data, ghi version hiện tại):

```bash
sudo bash scripts/07_pre_upgrade_backup.sh
```

Nâng cấp lên 15.16. Cluster vẫn lên, nhưng `fn_review_excerpt` báo `invalid byte sequence for encoding` với 334 đánh giá:

```bash
sudo bash scripts/08_upgrade_to_15.16.sh
```

Rollback về 15.6, giữ nguyên thư mục data:

```bash
sudo bash scripts/09_rollback_to_15.6.sh
```

Các câu kiểm tra: `06_verification_queries.md`.
