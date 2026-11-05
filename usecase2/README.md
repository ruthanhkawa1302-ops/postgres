# UC02 – Nâng cấp minor PostgreSQL 15.6 → 15.16 bị lỗi và rollback (standalone, Ubuntu 24.04)

Dựng **1 server PostgreSQL 15.6 standalone** (không replication / HA). Dữ liệu chỉ gồm bảng demo và hàm cần thiết, không có schema shop đầy đủ như UC01.
Thêm bảng `product_reviews` (10.000 đánh giá text dài, có ký tự nhiều byte, lưu TOAST) và hàm `fn_review_excerpt()` dùng `substring()`.
Bản 15.16 có hồi quy của bản vá CVE-2026-2006 (sửa ở 15.17): `substring()` báo `invalid byte sequence for encoding` với một phần dữ liệu, phải **rollback về 15.6**.
Lỗi đã tái hiện thật trên 15.16 (334/10.000 đánh giá lỗi), xem `docs/07_loi_substring_toast_va_rollback.md`.

## Cấu trúc

```
scripts/
  01_install_postgresql_15.6.sh   Cài postgresql-15 bản 15.6-* từ apt-archive (tự dò chuỗi version), hold, cấu hình standalone, tạo DB shopdb
  06_install_review_data.sh       Tạo bảng product_reviews, dữ liệu và hàm fn_review_excerpt (chạy sql/06)
  07_pre_upgrade_backup.sh        pg_dump + cold copy data dir + ghi version hiện tại
  08_upgrade_to_15.16.sh          Nâng cấp lên 15.16, chạy smoke test (dự kiến [FAIL], exit 1)
  09_rollback_to_15.6.sh          Rollback về 15.6
sql/
  06_toast_review_objects.sql     Schema shop + product_reviews (10k dòng), fn_review_excerpt, v_review_excerpt (không phụ thuộc bảng khác)
docs/
  00_tong_hop_trien_khai.md       Tổng hợp ngắn: cài 15.6, bảng demo + hàm, backup, nâng cấp lỗi, rollback
  06_verification_queries.md      Kiểm tra trước / sau nâng cấp / sau rollback (ngắn)
  09_giai_thich_loi_toast.md      Giải thích dễ hiểu: TOAST, ví dụ chuỗi, id lỗi, cách kiểm tra
  07_loi_substring_toast_va_rollback.md  Giải thích lỗi, giả thuyết kích hoạt, cách chạy và cách thử
  08_cac_ban_minor_loi.md         Các bản 15.x từng lỗi thật (15.9, 15.11, 15.16), nguồn tham khảo
```

## Thứ tự chạy (Ubuntu 24.04, user có sudo, chạy từ thư mục usecase2)

```bash
sudo PG_PASSWORD='123' bash scripts/01_install_postgresql_15.6.sh
sudo DB_NAME=shopdb bash scripts/06_install_review_data.sh        # bảng đánh giá + hàm substring (không cần build)

# kiểm tra trên 15.6: docs/06_verification_queries.md (§1)
sudo bash scripts/07_pre_upgrade_backup.sh
sudo bash scripts/08_upgrade_to_15.16.sh                          # lỗi: [FAIL] fn_review_excerpt ... invalid byte sequence
sudo bash scripts/09_rollback_to_15.6.sh                          # quay về 15.6
# kiểm tra lại: docs/06_verification_queries.md
```

Yêu cầu máy: 4 vCPU, 8 GB RAM, ≥ 5 GB disk trống (data nhỏ, thêm bản backup).
