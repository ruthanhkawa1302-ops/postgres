# Lab nâng cấp minor version PostgreSQL 16.2 → 16.3 (standalone, Ubuntu 24.04)

UC01 – *Minor patch thông thường*: dựng **1 server PostgreSQL 16.2 standalone** (không replication / HA)
có dữ liệu **~100 MB** và **đủ loại thành phần database (đa dạng, mỗi loại vài cái)**, sau đó nâng cấp
in-place bằng apt lên 16.3 và kiểm tra lại mọi thứ.

## Cấu trúc

```
scripts/
  01_install_postgresql_16.2.sh   Cài postgresql-16=16.2-2.pgdg24.04+1 từ apt-archive, hold version, cấu hình standalone, tạo DB shopdb
  04_install_extensions.sh        Preload pg_stat_statements + restart + chạy sql/04_extensions.sql (chỉ extension contrib, không cài package)
sql/
  02_schema.sql                   7 bảng, PK/FK/UNIQUE/CHECK, enum, domain, 9 index (mỗi loại 1 cái)
  03_insert_data.sql              Sinh dữ liệu tiếng Anh ~100 MB (tham số scale, mặc định 0.03)
  04_extensions.sql               CREATE EXTENSION (8 extension contrib)
  05_database_objects.sql         View, MV, function, procedure, aggregate, trigger, event trigger, RLS, role...
docs/
  00_tong_hop_trien_khai.md       Tài liệu tổng hợp cho team: cài DB, bảng, index, gendata, extension, function, procedure
  02_schema.md                    Bảng, khóa, index, dữ liệu
  04_extensions.md                Extension đã cài: dùng làm gì, dùng ở đâu
  05_database_objects.md          Tổng hợp số lượng + ý nghĩa từng thành phần + extension sử dụng
  06_verification_queries.md      Câu lệnh verify trước/sau upgrade + quy trình nâng cấp 16.2 → 16.3
  07_ban_minor_anh_huong.md       Bản minor 16.x nào ảnh hưởng tới object hiện có (chủ yếu 16.3 / CVE-2024-4317) + cách kiểm tra trước/sau
```

## Tổng hợp thành phần

| Bảng | Index | View | MV | Function | Procedure | Aggregate | Trigger | Event trigger | Type | Policy | Role | Extension |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 27 | 3 | 1 | 11 | 2 | 1 | 3 | 1 | 3 | 2 | 3 | 8 |

## Thứ tự chạy (trên Ubuntu 24.04, user có sudo)

```bash
# 1. Cài PostgreSQL 16.2 standalone
sudo PG_PASSWORD='123' bash scripts/01_install_postgresql_16.2.sh

# 2. Tạo schema + bảng + index
sudo -u postgres psql -d shopdb -f sql/02_schema.sql

# 3. Nạp dữ liệu (~100 MB, khoảng 1 phút, mặc định scale=0.03). Muốn ~1.5 GB thì thêm -v scale=0.44
sudo -u postgres psql -d shopdb -f sql/03_insert_data.sql

# 4. Cài extension (contrib)
sudo DB_NAME=shopdb bash scripts/04_install_extensions.sh

# 5. Tạo các thành phần database
sudo -u postgres psql -d shopdb -f sql/05_database_objects.sql


# 6. Verify trên 16.2 -> nâng cấp 16.3 -> verify lại: xem docs/06_verification_queries.md
```

Yêu cầu máy: tối thiểu 4 vCPU, 8 GB RAM, **≥ 15 GB disk trống** (database ~100 MB, cộng WAL,
bản backup pg_dump và chỗ trống khi refresh MV).

Nên chạy script từ thư mục gốc của project. Nếu user `postgres` không đọc được file trong thư mục home,
hãy copy project sang `/tmp` hoặc `chmod o+rx` cho thư mục.
