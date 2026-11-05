# 07 – Bản minor 16.x nào ảnh hưởng tới dữ liệu / function của UC01

Tra cứu ngày 22/10/2026 từ release notes chính thức của PostgreSQL 16.3, 16.4, 16.9, 16.10, 16.12, 16.13, đối chiếu với `sql/02_schema.sql` và `sql/05_database_objects.sql`.

## Kết luận

Không có bản 16.x nào làm hỏng dữ liệu, function hay procedure hiện có của UC01. Minor release không cần dump/restore và các object trong schema `shop` chỉ dùng tính năng ổn định.

Thay đổi duy nhất chắc chắn làm một kết quả kiểm tra đổi khác là bản 16.3 (đích của UC01), do bản vá CVE-2024-4317:

- UC01 có extended statistics `shop.st_customers_country_city`.
- View `pg_stats_ext` sau khi vá chỉ cho thấy dòng của chủ sở hữu bảng. Role `demo_analyst` (kế thừa `shop_readonly`, có quyền SELECT trên mọi bảng) từ chỗ thấy dòng thống kê sẽ thấy 0 dòng.
- Đây là thay đổi hành vi, không phải lỗi làm server hay dữ liệu hỏng. Nó có thể được dùng làm điểm "kiểm tra không đạt" nếu muốn demo.

Nếu cần một lỗi đủ nặng để bắt buộc rollback thì UC01 hiện tại chưa có. Cách dựng lỗi thật ở mục cuối.

## Từng bản đã xem

| Bản | Ngày | Thay đổi liên quan | Ảnh hưởng tới UC01 |
|---|---|---|---|
| 16.3 | 09/05/2024 | CVE-2024-4317: `pg_stats_ext` và `pg_stats_ext_exprs` chỉ hiện cho chủ bảng. Cluster cũ phải chạy `fix-CVE-2024-4317.sql` | Có. Xem mục "Kiểm tra 16.3" |
| 16.3 | | `MERGE ... DO NOTHING` cần quyền SELECT trên bảng đích | Không, UC01 không dùng MERGE |
| 16.3 | | INSERT nhiều dòng VALUES vào domain trên kiểu array/composite | Không, `money_amount` là domain trên `numeric(12,2)` |
| 16.4 | 08/2024 | `CREATE TABLE ... LIKE ... STATISTICS` sinh statistics sai khi bảng nguồn có cột đã xóa | Không, UC01 không dùng LIKE |
| 16.4 | | `pg_stat_statements`: utility statement trong SQL function có query ID riêng | Chỉ làm đổi số dòng trong `pg_stat_statements`, không gây lỗi |
| 16.5 | 11/2024 | ABI break `ResultRelInfo` (sửa ở 16.6) | Không, UC01 không có extension C bên thứ ba |
| 16.9 | 08/05/2025 | `ALTER TABLE ADD COLUMN` với domain có DEFAULT sẽ điền vào dòng cũ | Không, `money_amount` không có DEFAULT |
| 16.9 | | BRIN bloom cần reindex | Không, UC01 chỉ có BRIN minmax trên `paid_at` |
| 16.10 | 14/08/2025 | BRIN `numeric_minmax_multi_ops` cần reindex | Không, `idx_payments_paid_at_brin` là kiểu timestamp |
| 16.10 | | Kiểm tra quyền trên view được làm ở đầu bước plan; RLS áp dụng khi đọc thống kê của partition | Nên chạy lại kiểm tra `v_customers_masked` và RLS bằng role không phải superuser |
| 16.12 | 12/02/2026 | CVE-2026-2006: hàm chuỗi báo `invalid byte sequence for encoding` với text sai encoding đã lưu | Không, dữ liệu UC01 là tiếng Anh, hợp lệ |
| 16.12 | | Báo lỗi nếu sub-select trong aggregate tham chiếu CTE ở mức thấp hơn | Không, UC01 không có truy vấn dạng này |
| 16.13 | 26/02/2026 | Sửa hồi quy của 16.12: `substring()` trên dữ liệu TOAST báo lỗi sai | Không bị ảnh hưởng vì UC01 không gọi `substring()`. Xem mục cuối |
| 16.13 | | Cast biến composite sang domain trong PL/pgSQL trả về NULL báo `cache lookup failed for type 0` | Không, UC01 không có hàm kiểu này |
| 16.13 | | `hstore` binary input crash khi có key trùng | Không, trigger audit dùng đường text |

Các bản 16.6, 16.7, 16.8, 16.11 và 16.14 trở đi mình chưa đọc kỹ release notes, nên không có kết luận cho các bản đó.

## Kiểm tra 16.3 (CVE-2024-4317)

Các lệnh chạy bằng role `demo_analyst` (mật khẩu `Analyst@123`), vì superuser luôn thấy mọi dòng nên không phát hiện được thay đổi này.

```bash
psql "host=<SERVER_IP> dbname=shopdb user=demo_analyst password=Analyst@123"
```

```sql
SELECT current_user;                                                  -- demo_analyst
SELECT has_table_privilege('shop.customers', 'SELECT');               -- true
SELECT statistics_name, kinds FROM pg_stats_ext WHERE schemaname = 'shop';
SELECT count(*) FROM pg_stats_ext WHERE schemaname = 'shop';
```

Kết quả mong đợi:

- Trước nâng cấp (16.2): 1 dòng `st_customers_country_city | {d,f,m}`, count = 1.
- Sau nâng cấp 16.3, chưa chạy fix script: không đổi (view cũ vẫn còn), count = 1.
- Sau nâng cấp 16.3 và chạy `fix-CVE-2024-4317.sql`: 0 dòng, count = 0. Tương tự với `pg_stats_ext_exprs`.

Cùng lúc chạy bằng `postgres` thì vẫn thấy 1 dòng ở cả ba trạng thái. Chênh lệch giữa hai role là dấu hiệu fix script đã có hiệu lực.

Kiểm tra view đã được vá hay chưa:

```sql
SELECT pg_get_viewdef('pg_catalog.pg_stats_ext'::regclass) LIKE '%pg_has_role%' AS fixed;
```

Trước fix script: `false`. Sau: `true`.

Phần 0 dòng với `demo_analyst` đã được thử trên PostgreSQL 18 (bản đã vá sẵn): `demo_analyst` có quyền SELECT trên `shop.customers` nhưng đọc `pg_stats_ext` ra 0 dòng. Dòng "trước nâng cấp = 1" chưa được thử trên 16.2 thật, chỉ dựa trên mô tả lỗ hổng.

Cách xử lý nếu muốn `demo_analyst` thấy lại: cấp thêm vai trò chủ sở hữu bảng cho nó, hoặc chấp nhận kết quả mới và sửa checklist. Chạy lại fix script là việc không thể hoàn tác bằng downgrade gói, vì nó sửa view trong catalog của từng database. Muốn quay về hoàn toàn thì restore bản backup trước nâng cấp.

## Quy trình kiểm tra trước và sau nâng cấp

Dùng đúng quy trình trong `docs/06_verification_queries.md` (§3 chụp snapshot `before` / `after`, §5 → §9). Bổ sung thêm các bước sau cho 16.3:

1. Trước nâng cấp, chạy 4 lệnh ở mục "Kiểm tra 16.3" bằng `demo_analyst` và lưu kết quả.
2. Nâng cấp lên 16.3, chạy lại 4 lệnh. Kết quả phải giống bước 1 vì chưa chạy fix script.
3. Chạy `fix-CVE-2024-4317.sql` cho mọi database (§11 của file verify). Chạy lại 4 lệnh: count từ 1 xuống 0, `fixed` từ `false` thành `true`.
4. Chạy lại §5 → §9 bằng `postgres`: mọi kết quả khác không đổi.

## Nếu cần lỗi nặng đủ để rollback ở UC01

Release notes không có thay đổi nào làm hỏng object hiện có, nên phải tự thêm đối tượng chịu lỗi. Có hai hướng, chưa làm trong repo:

- Bản 16.12: thêm một cột text dài, có ký tự ngoài ASCII (đủ lớn để bị TOAST) và một hàm dùng `substring()` trên cột đó. Bản 16.13 ghi nhận bản 16.12 có thể báo lỗi sai ở trường hợp này. Thông báo chính thức không nói rõ điều kiện chính xác, nên phải thử trên máy thật trước khi dựa vào. Bản 16.13 là bản sửa.
- Dùng extension tự viết có kiểm tra version như `legacy_guard` của UC02.

## Nguồn

- https://www.postgresql.org/docs/release/16.3/
- https://www.postgresql.org/docs/release/16.4/
- https://www.postgresql.org/docs/release/16.9/
- https://www.postgresql.org/docs/release/16.10/
- https://www.postgresql.org/docs/release/16.12/
- https://www.postgresql.org/docs/release/16.13/
