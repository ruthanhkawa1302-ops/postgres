# 06 – Kiểm tra trước và sau khi nâng cấp 15.6 → 15.16

Dữ liệu của UC02 chỉ có bảng `shop.product_reviews` (10.000 đánh giá) và hàm `shop.fn_review_excerpt()`. Các câu dưới đây chạy bằng `sudo -u postgres psql -d shopdb`.

Quy trình: chạy §1 trên 15.6, backup, nâng cấp lên 15.16 và chạy lại §1 (sẽ lỗi), rollback về 15.6 rồi chạy lại §1 (phải giống lúc đầu).

## 1. Bộ kiểm tra

Version và encoding:

```sql
SHOW server_version;       -- 15.6 (trước và sau rollback), 15.16 (sau nâng cấp)
SHOW server_encoding;      -- UTF8
```

Dữ liệu nằm trong TOAST:

```sql
SELECT count(*) AS reviews,
       count(*) FILTER (WHERE pg_column_size(body) > 2000) AS big_values
FROM shop.product_reviews;                       -- 10000 / 10000
```

Thử hai đánh giá:

```sql
SELECT shop.fn_review_excerpt(2);                -- chạy được trên cả 15.6 và 15.16
SELECT shop.fn_review_excerpt(19);               -- 15.6: trả 40 ký tự; 15.16: ERROR invalid byte sequence
```

Đếm số đánh giá lỗi và liệt kê id:

```sql
DO $$
DECLARE r bigint; bad int := 0; good int := 0; ids text := '';
BEGIN
  FOR r IN SELECT review_id FROM shop.product_reviews ORDER BY review_id LOOP
    BEGIN PERFORM shop.fn_review_excerpt(r); good := good + 1;
    EXCEPTION WHEN OTHERS THEN bad := bad + 1; IF bad <= 10 THEN ids := ids || r || ' '; END IF; END;
  END LOOP;
  RAISE NOTICE 'ok = %, loi = %, 10 id dau: %', good, bad, ids;
END $$;
```

Kết quả mong đợi:

```
15.6  : ok = 10000, loi = 0
15.16 : ok = 9666,  loi = 334   (id lỗi: 1, 19, 49, 79, 109, ...)
```

Dấu vân tay của dữ liệu (chỉ chạy được khi không lỗi, tức trên 15.6; phải giống nhau trước nâng cấp và sau rollback):

```sql
SELECT md5(string_agg(excerpt, '|' ORDER BY review_id)) FROM shop.v_review_excerpt;
SELECT md5(string_agg(body, '|' ORDER BY review_id)) FROM shop.product_reviews;   -- chạy được cả trên 15.16
```

Câu thứ hai không dùng `substring()` nên chạy được trên 15.16 và chứng minh dữ liệu không bị hỏng.

## 2. Nâng cấp lỗi và rollback

```bash
sudo bash scripts/07_pre_upgrade_backup.sh
sudo bash scripts/08_upgrade_to_15.16.sh          # dự kiến [FAIL], thoát mã 1
tail -n 20 /var/log/postgresql/postgresql-15-main.log
sudo bash scripts/09_rollback_to_15.6.sh
```

## 3. Checklist

| Hạng mục | Trước (15.6) | Trên 15.16 | Sau rollback (15.6) |
|---|:---:|:---:|:---:|
| `server_version` | 15.6 | 15.16 | 15.6 |
| Có backup trước nâng cấp | ☐ | n/a | n/a |
| Khối `DO` đếm lỗi | ok = 10000, loi = 0 | loi = 334 | ok = 10000, loi = 0 |
| `fn_review_excerpt(19)` | trả 40 ký tự | ERROR | trả 40 ký tự |
| md5 `body` | A | A | A |
| md5 `excerpt` | B | không chạy được | B |
| Service active, client kết nối được | ☐ | ☐ | ☐ |
| Log có `invalid byte sequence` | không | có | không (log cũ vẫn còn dòng lỗi) |
