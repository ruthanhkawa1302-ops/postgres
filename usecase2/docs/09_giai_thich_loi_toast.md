# 09 – Giải thích lỗi substring() + TOAST (bản dễ hiểu)

Tài liệu này giải thích lỗi của UC02 bằng ví dụ đơn giản: TOAST là gì, dữ liệu trong lab là gì, hàm nào đang chạy, sau khi nâng lên 15.16 thì lỗi gì và kiểm tra thế nào. Kết quả dưới đây lấy từ lần chạy thật trên Ubuntu với 15.16-1.pgdg24.04+1.

## 1. TOAST là gì

Một dòng trong PostgreSQL nằm trong một trang nhớ 8 KB. Nếu một giá trị quá dài (khoảng trên 2 KB), PostgreSQL không để nó trong dòng mà cất sang một bảng phụ ẩn gọi là bảng TOAST. Trong dòng chính chỉ còn một con trỏ trỏ tới đó.

Ví dụ: bài đánh giá dài 3,5 KB giống một cuốn sách quá lớn không để vừa trên bàn làm việc. Nó được cất vào kho, trên bàn chỉ để một tờ phiếu ghi "sách nằm ở kho, kệ số 17".

Khi cần đọc, PostgreSQL ra kho lấy. Nếu chỉ cần vài chữ đầu, nó chỉ lấy một đoạn đầu của cuốn sách (gọi là slice) chứ không khuân cả cuốn ra. Việc này nhanh hơn, và đó là chỗ phát sinh lỗi.

Trong lab, cột `body` được đặt `STORAGE EXTERNAL`: nằm trong kho và không nén. Nhờ không nén nên lấy đoạn đầu rất dễ, tính theo byte.

## 2. Ký tự nhiều byte

Chữ cái thường (a, b, c) chiếm 1 byte. Một số ký tự chiếm nhiều hơn, ví dụ:

```
a   = 1 byte
é   = 2 byte
’   = 3 byte   (dấu nháy cong trong "don’t")
—   = 3 byte   (gạch ngang dài)
€   = 3 byte
```

Đếm theo byte và đếm theo ký tự khác nhau. "don’t" có 5 ký tự nhưng 7 byte.

## 3. Dữ liệu trong lab

Bảng `shop.product_reviews`, 10.000 đánh giá sản phẩm bằng tiếng Anh, mỗi bài khoảng 3,5 KB. Nội dung có nhiều dấu `’ — … €`, ví dụ:

```
solid don’t would very was fast great price well time battery ... It’s great value — works well ...
```

Hai điểm quan trọng: bài đủ dài để vào TOAST, và có nhiều ký tự 3 byte. Review số 1 là dòng thử cố định, toàn ký tự `’`.

## 4. Hàm đang chạy

```sql
shop.fn_review_excerpt(review_id, len = 40)
```

Hàm lấy 40 ký tự đầu của bài đánh giá để hiện ở trang sản phẩm hoặc trong email. Bên trong chỉ có một lệnh:

```sql
SELECT substring(body, 1, 40) FROM shop.product_reviews WHERE review_id = ...
```

Ngoài ra có view `shop.v_review_excerpt` cắt 40 ký tự đầu của cả 10.000 đánh giá.

Trên 15.6: chạy đúng cả 10.000 dòng.

## 5. PostgreSQL cắt 40 ký tự như thế nào

Để lấy 40 ký tự, PostgreSQL không biết trước cần bao nhiêu byte, vì mỗi ký tự có thể từ 1 đến 4 byte. Nên nó lấy dư: 40 × 4 = 160 byte đầu từ kho. Sau đó mới đếm ký tự và cắt đúng 40.

Đoạn 160 byte này có thể kết thúc giữa một ký tự 3 byte. Ví dụ:

```
... don’t would ... [  ’  ]
                    e2 80 99
byte thứ 160 rơi ở đây ──┘ (chỉ mới có e2, còn thiếu 80 99)
```

Ký tự `’` nằm ở 3 byte `e2 80 99`, nhưng đoạn lấy về chỉ có `e2`. Phần dở này thuộc ký tự thứ 54 trở đi, nằm ngoài 40 ký tự cần lấy (40 ký tự tối đa 160 byte, nên không bao giờ chứa phần dở), vì vậy không xuất hiện trong kết quả.

Trên 15.6, PostgreSQL bỏ qua phần dở dang đó và trả đúng 40 ký tự. Kết quả đúng.

## 6. Sau khi nâng lên 15.16: lỗi gì

Bản 15.16 sửa một lỗ hổng bảo mật (CVE-2026-2006) về dữ liệu sai encoding. Bản vá này kiểm tra quá chặt: thấy đoạn 160 byte kết thúc bằng ký tự dở dang thì báo lỗi, dù dữ liệu gốc hoàn toàn hợp lệ.

Lỗi thật đã gặp trên máy:

```
ERROR:  invalid byte sequence for encoding "UTF8": 0xe2 0x80
```

`0xe2 0x80` chính là 2 byte đầu của `’` bị đứt giữa chừng. Bản 15.17 sửa lại lỗi này.

Kết quả smoke test thật khi chạy script 08:

```
[ OK ] reviews are TOASTed: 10000
[FAIL] fn_review_excerpt(1): ERROR:  invalid byte sequence for encoding "UTF8": 0xe2 0x80
[ OK ] fn_review_excerpt(2): solid don’t would very was fast great pr
[FAIL] v_review_excerpt (all rows): ERROR:  invalid byte sequence for encoding "UTF8": 0xe2 0x80
[FAIL] all 10k excerpts (no error): ERROR:  334 reviews cannot be cut
```

Nghĩa là 334 trong 10.000 đánh giá (3,3%) bị lỗi. Review 2 may mắn không bị cắt giữa ký tự nên vẫn chạy.

Những review bị lỗi (tính trên dữ liệu lab, khớp đúng 334 dòng lỗi thật): review 1 và mọi review có `review_id % 30 = 19`, tức 19, 49, 79, 109, ... 9979 (333 dòng). Chúng bị lỗi vì đoạn 160 byte kết thúc bằng đúng 1 byte đầu của ký tự 3 byte (`e2`, thiếu `80 99`). Các bài mà đoạn kết thúc bằng `e2 80` (thiếu 1 byte cuối, ví dụ `review_id % 30 = 12` hoặc `21`) lại không lỗi. Đây là suy luận từ số liệu (khớp 334 = 334), chưa đọc mã nguồn của bản vá.

## 7. Ảnh hưởng nghiệp vụ

- Trang sản phẩm có đánh giá "xui" sẽ báo lỗi thay vì hiện đoạn trích. Trang khác vẫn bình thường, nên rất khó phát hiện.
- Truy vấn view `v_review_excerpt` lỗi toàn bộ, vì một dòng lỗi làm hỏng cả câu truy vấn.
- Email tổng hợp đánh giá cũng lỗi theo, vì dùng cùng hàm.
- Đơn hàng, các bảng khác và cluster vẫn chạy bình thường. Dữ liệu không mất hay hỏng.

## 8. Cách kiểm tra (chỉ vào trọng tâm)

Chạy trong `sudo -u postgres psql -d shopdb`.

Bước 1: xem version.

```sql
SHOW server_version;
```

Bước 2: thử một đánh giá bị lỗi.

```sql
SELECT shop.fn_review_excerpt(1);
```

Trên 15.6 trả 40 ký tự `’`. Trên 15.16 báo lỗi `invalid byte sequence`.

Bước 3: đếm số đánh giá lỗi.

```sql
DO $$
DECLARE r bigint; bad int := 0; good int := 0;
BEGIN
  FOR r IN SELECT review_id FROM shop.product_reviews LOOP
    BEGIN PERFORM shop.fn_review_excerpt(r); good := good + 1;
    EXCEPTION WHEN OTHERS THEN bad := bad + 1; END;
  END LOOP;
  RAISE NOTICE 'ok = %, loi = %', good, bad;
END $$;
```

Kết quả mong đợi:

```
15.6  : ok = 10000, loi = 0
15.16 : ok = 9666,  loi = 334
```

Bước 4: xem log.

```bash
tail -n 20 /var/log/postgresql/postgresql-15-main.log
```

Sẽ có dòng `ERROR: invalid byte sequence for encoding "UTF8"`.

## 9. Cách xử lý

Rollback về 15.6:

```bash
sudo BACKUP_DIR=/var/backups/pg_upgrade_lab bash scripts/09_rollback_to_15.6.sh
```

Sau rollback chạy lại bước 1 và bước 3: mong đợi `15.6`, `ok = 10000, loi = 0`. Cách khác là nâng lên 15.17 (bản sửa lỗi), nhưng bài lab này chủ đích quay về 15.6.

## 10. Tài liệu tham khảo của PostgreSQL

- Release notes 15.17 (mục sửa lỗi này): https://www.postgresql.org/docs/release/15.17/
  Nguyên văn: "Avoid incorrect complaint of invalid encoding when substring() is applied to toasted data. The fix for CVE-2026-2006 was too aggressive and could raise an error about an incomplete character in cases that are actually valid."
- Thông báo bảo mật CVE-2026-2006 (lỗ hổng được vá ở 15.16, phát hành 12/02/2026): https://www.postgresql.org/support/security/CVE-2026-2006/
- Release notes 15.16 (bản gây ra lỗi này): https://www.postgresql.org/docs/release/15.16/
- Thông báo phát hành 15.17: https://www.postgresql.org/about/news/postgresql-183-179-1613-1517-and-1422-released-3246/

Ghi chú: release notes 15.17 chỉ nói bản vá CVE-2026-2006 "quá chặt", không nêu tên bản gây lỗi. Việc đó là 15.16 được suy ra từ ngày phát hành của bản vá, và đã khớp với kết quả chạy thật trên máy.
