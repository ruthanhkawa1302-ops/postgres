# Lab nâng cấp minor version PostgreSQL (Ubuntu 24.04, standalone)

- `usecase1/` – UC01: PostgreSQL 16.2 → 16.3, nâng cấp thành công, verify trước / sau.
- `usecase2/` – UC02: PostgreSQL 15.6 → 15.16, nâng cấp lỗi do hồi quy `substring()` trên dữ liệu TOAST, rollback về 15.6.
- `requirement/` – yêu cầu gốc.

Mỗi use case có `scripts/`, `sql/`, `docs/` và `README.md` riêng; chạy các lệnh từ thư mục của use case đó.
