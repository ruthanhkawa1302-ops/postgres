# Lệnh tắt trong psql

Các lệnh bắt đầu bằng dấu `\` là lệnh của psql, không phải SQL, nên không cần dấu `;` ở cuối.

## Kết nối

```bash
sudo -u postgres psql                      # vào bằng user postgres trên chính server
psql -h 127.0.0.1 -p 5432 -U postgres -d shopdb
psql -d shopdb -c "SELECT version();"      # chạy 1 câu rồi thoát
psql -d shopdb -f file.sql                 # chạy file SQL
```

```
\c shopdb            đổi sang database shopdb
\conninfo            xem đang kết nối vào đâu, bằng user nào
\q                   thoát
```

## Xem danh sách object

```
\l                   danh sách database
\dn                  danh sách schema
\dt                  bảng trong schema hiện tại
\dt shop.*           bảng trong schema shop
\dv                  view
\dm                  materialized view
\di                  index
\ds                  sequence
\df                  function
\df shop.*           function trong schema shop
\dx                  extension đã cài
\du                  role / user
\dT                  kiểu dữ liệu (enum, composite)
\dy                  event trigger
```

Thêm dấu `+` để xem chi tiết hơn (kích thước, mô tả): `\dt+`, `\l+`, `\di+`.

## Xem cấu trúc một object

```
\d shop.orders       cột, index, FK, trigger của bảng
\d+ shop.orders      thêm storage, mô tả
\d+ shop.v_review_excerpt   định nghĩa view
\sf shop.fn_review_excerpt  xem mã nguồn function
\sv shop.v_review_excerpt   xem mã nguồn view
\dp shop.orders      quyền trên bảng
```

## Hiển thị kết quả

```
\x                   bật/tắt hiển thị dạng dọc (mỗi cột 1 dòng)
\x auto              tự chọn dọc hoặc ngang tùy độ rộng
\timing              bật/tắt đo thời gian chạy câu lệnh
\pset null '(null)'  hiện NULL rõ ràng
\pset pager off      tắt pager (khỏi phải bấm q)
\a                   bật/tắt căn lề
\t                   bật/tắt tiêu đề cột (chỉ lấy dữ liệu)
```

## Chạy lại và sửa câu lệnh

```
\g                   chạy lại câu lệnh trong bộ đệm
\e                   mở editor để sửa câu lệnh hiện tại
\p                   in ra câu lệnh trong bộ đệm
\r                   xóa bộ đệm
\s                   xem lịch sử lệnh
\watch 5             chạy lại câu vừa rồi mỗi 5 giây
```

## File và xuất dữ liệu

```
\i file.sql          chạy file SQL
\o ketqua.txt        ghi kết quả ra file (gõ \o để tắt)
\copy shop.countries TO 'countries.csv' CSV HEADER
\copy shop.countries FROM 'countries.csv' CSV HEADER
\! ls                chạy lệnh shell
\cd /tmp             đổi thư mục làm việc
```

## Biến và kịch bản

```
\set scale 0.44      đặt biến, dùng là :scale
\echo :scale         in giá trị biến
\unset scale         xóa biến
\gset                gán kết quả câu SELECT vào biến
\gexec               chạy từng dòng kết quả như một câu SQL
\if / \elif / \else / \endif   điều kiện trong script
```

Ví dụ lưu kết quả vào biến:

```
SELECT count(*) AS n FROM shop.product_reviews \gset
\echo :n
```

## Thông tin server hay dùng

```sql
SHOW server_version;
SHOW data_directory;
SHOW config_file;
SHOW all;                                  -- toàn bộ tham số
SELECT pg_postmaster_start_time();
SELECT pg_size_pretty(pg_database_size(current_database()));
SELECT pg_reload_conf();                   -- nạp lại cấu hình, không restart
```

## Trợ giúp

```
\?                   danh sách lệnh bắt đầu bằng \
\h                   danh sách câu lệnh SQL
\h CREATE INDEX      cú pháp một câu lệnh SQL
```
