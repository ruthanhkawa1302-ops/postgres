# 08 – Verify trước và sau khi patch (16.2 → 16.3)

Ba script, mỗi script chạy đúng 1 câu SQL và in kết quả ra màn hình. Chạy một lần trước khi patch (16.2)
và một lần sau khi patch (16.3), rồi so sánh kết quả bằng mắt. Hai lần phải giống nhau.

| Script | Câu hỏi | Cách kiểm tra |
|---|---|---|
| `verify_1_data.sh` | Dữ liệu còn đủ không | Đếm dòng 5 bảng chính, tổng tiền, md5 của 1000 khách hàng đầu |
| `verify_2_index.sh` | Có phải build lại index không | amcheck trên mọi B-tree index của schema shop, đếm index invalid |
| `verify_3_function.sh` | Function chạy ổn không | Gọi 6 function, 1 aggregate, 1 view, in md5 của kết quả |

Script 3 cần đã chạy `sql/04` và `sql/05`. Script 2 cần extension amcheck (`sql/04`).

## Cách chạy

Chạy từ thư mục `usecase1/`, có quyền sudo. Đổi database bằng biến `DB_NAME` nếu cần (mặc định `shopdb`).

```bash
bash scripts/verify_1_data.sh
bash scripts/verify_2_index.sh
bash scripts/verify_3_function.sh
```

## Kết quả mong đợi (scale=0.03)

Script 1: 15000 customers, 1500 products, 114000 orders, khoảng 342k order_items, khoảng 114k payments.
Các tổng tiền và `md5_customers` giống hệt trước và sau.

Script 2: `total_indexes` = 27, `invalid_indexes` = 0, `btree_checked_ok` = 21. Nếu amcheck phát hiện
index hỏng thì script dừng với lỗi, khi đó mới cần `REINDEX`. amcheck ở PG16 chỉ kiểm tra B-tree nên
các index GIN, GiST, BRIN, Hash không nằm trong con số 21.

Script 3: các giá trị md5, `lifetime_value`, `weighted_avg`, `view_rows` giống hệt trước và sau.
