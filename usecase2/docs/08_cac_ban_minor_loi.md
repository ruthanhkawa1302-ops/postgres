# 08 – Các bản minor PostgreSQL 15.x từng bị lỗi (tham khảo cho UC02)

Tra cứu ngày 22/10/2026. Cả ba bản dưới đây đều có trong `apt-archive` (noble-pgdg-archive) của PostgreSQL 15.
UC02 dùng bản 15.16 làm đích nâng cấp lỗi (xem `07_loi_substring_toast_va_rollback.md`). Bản 15.12 là bản sửa cho lỗi của 15.11.

PostgreSQL cam kết minor release không phá API/ABI, nên các lỗi dưới đây là ngoại lệ, đều được sửa trong vòng 1–2 tuần bằng một bản out-of-cycle.

## Tóm tắt

| Bản lỗi | Ngày ra | Lỗi | Loại | Bản sửa |
|---|---|---|---|---|
| 15.9 | 14/11/2024 | ABI break: cấu trúc `ResultRelInfo` đổi kích thước | Extension (TimescaleDB, Apache AGE) | 15.10, 21/11/2024 |
| 15.11 | 13/02/2025 | Bản vá CVE-2025-1094 làm hàm quote của libpq bỏ qua tham số độ dài | Phía client (libpq) | 15.12, 20/02/2025 |
| 15.16 | 12/02/2026 | Bản vá CVE-2026-2006 quá chặt, `substring()` báo lỗi sai | Phía server | 15.17, 26/02/2026 |

## 15.9 – ABI break của ResultRelInfo

Bản 15.9 (cùng 17.1, 16.5, 14.14) thêm một trường vào struct `ResultRelInfo`, làm kích thước struct thay đổi.
Một số API của executor yêu cầu extension truy cập mảng `ResultRelInfo` theo chỉ số, nên extension build với bản cũ chạy trên bản mới (hoặc ngược lại) sẽ sai.
Extension bị ảnh hưởng chính: TimescaleDB và Apache AGE.

Bản 15.10 (cùng 17.2, 16.6, 14.15) đưa trường mới vào phần padding sẵn có để kích thước struct trở lại như cũ. Release notes 14.15 ghi:
"Repair ABI break for extensions that work with struct ResultRelInfo". Extension không cần build lại.

Ghi chú cho lab:
- Phù hợp nhất với kịch bản "lỗi extension", nhưng TimescaleDB không có trong PGDG apt, và chưa xác nhận Apache AGE có gói apt cho Ubuntu 24.04.
- Lỗi chỉ xảy ra ở một số đường thực thi cụ thể, khó tái hiện ổn định.

## 15.11 – Hồi quy của bản vá CVE-2025-1094

Bản vá CVE-2025-1094 (lỗ hổng quoting trong libpq) làm `PQescapeLiteral()` và `PQescapeIdentifier()` không tôn trọng tham số độ dài chuỗi,
một số trường hợp gây crash. Mức ảnh hưởng tùy cách driver client dùng libpq, không phải driver nào cũng gặp.
PostgreSQL khuyên ai bị ảnh hưởng nên chờ 15.12 (cùng 17.4, 16.8, 14.17, 13.20) rồi hãy nâng cấp.

Bản 15.12 sửa lỗi này, đồng thời sửa một memory leak nhỏ trong `pg_createsubscriber`, và đổi cách libpq xử lý chuỗi sai encoding
(thay chỉ byte đầu của ký tự sai).

Ghi chú cho lab:
- Lỗi nằm ở client, không làm hỏng dữ liệu hay server, nên không phù hợp để chứng minh rollback ở phía database.

## 15.16 – Hồi quy của bản vá CVE-2026-2006

Theo release notes 15.17: "Avoid incorrect complaint of invalid encoding when `substring()` is applied to toasted data".
Bản vá CVE-2026-2006 quá chặt, có thể báo lỗi "incomplete character" trong các trường hợp thực ra hợp lệ.
Thông báo của bản out-of-cycle gọi lỗi là `invalid byte sequence for encoding`, xảy ra với giá trị không phải ASCII lấy từ cột trong database.

Bản 15.17 sửa thêm một số lỗi nhỏ khác:
- Lỗi replay WAL (multixid truncation) khi standby ở bản mới đọc WAL của primary ở bản cũ. Chỉ ảnh hưởng mô hình có standby, không ảnh hưởng server standalone.
- Cast biến composite sang domain trong PL/pgSQL, trả về NULL gây lỗi "cache lookup failed for type 0".
- `pg_stat_get_backend_wait_event()` và `_type()` không trả về giá trị cho auxiliary process.
- Crash trong `hstore` khi nhận binary input có key trùng.

Ghi chú cho lab (đã dùng cho UC02):
- Dựng kịch bản rollback phía server cho server standalone: bảng `shop.product_reviews` có text dài, ký tự ngoài ASCII, lưu TOAST không nén; hàm `shop.fn_review_excerpt()` chạy `substring()` trên cột đó.
- Chưa rõ điều kiện chính xác kích hoạt lỗi (thông báo chỉ nói dữ liệu bị TOAST và có ký tự nhiều byte). Dữ liệu lab dựng theo giả thuyết, cần xác nhận trên 15.16 thật, xem `07_loi_substring_toast_va_rollback.md`.

## Nguồn

- A change to ResultRelInfo, a near miss with Postgres 17.1 (Crunchy Data): https://www.crunchydata.com/blog/a-change-to-relresultinfo-a-near-miss-with-postgres-17-1
- PostgreSQL 14.15 release notes: https://www.postgresql.org/docs/release/14.15/
- Out-of-cycle release scheduled for February 20, 2025: https://www.postgresql.org/about/news/out-of-cycle-release-scheduled-for-february-20-2025-3016/
- Mageia bug 34039 (hồi quy của bản vá CVE-2025-1094): https://bugs.mageia.org/show_bug.cgi?id=34039
- PostgreSQL 15.17 release notes: https://www.postgresql.org/docs/release/15.17/
- PostgreSQL 18.3, 17.9, 16.13, 15.17, and 14.22 Released: https://www.postgresql.org/about/news/postgresql-183-179-1613-1517-and-1422-released-3246/
