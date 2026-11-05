# Gỡ cài đặt hoàn toàn PostgreSQL (Ubuntu 24.04)

File này dùng để dọn sạch server sau khi demo xong UC01 (PG 16) hoặc UC02 (PG 15): gỡ package, xóa dữ liệu, xóa cấu hình, xóa repo apt và các file backup.

Các lệnh dưới đây xóa vĩnh viễn toàn bộ database. Nếu còn cần dữ liệu thì backup trước (bước 0). Chạy bằng user có sudo.

## 0. Backup (bỏ qua nếu không cần giữ dữ liệu)

```bash
sudo -u postgres pg_dumpall --globals-only > ~/globals.sql
sudo -u postgres pg_dump -Fc -d shopdb -f ~/shopdb.dump
```

## 1. Xem đang cài những gì

```bash
dpkg -l | grep -i postgres
pg_lsclusters
```

## 2. Dừng service và xóa cluster

```bash
sudo systemctl stop postgresql
sudo systemctl disable postgresql

# xóa từng cluster (đổi 16 thành 15 nếu là UC02); cũng xóa luôn data dir
sudo pg_dropcluster --stop 16 main 2>/dev/null || true
sudo pg_dropcluster --stop 15 main 2>/dev/null || true
```

Nếu còn tiến trình postgres chạy sót:

```bash
sudo pkill -u postgres || true
```

## 3. Bỏ hold và gỡ package

Bản cài trong demo bị `apt-mark hold` nên phải unhold trước, nếu không apt sẽ không gỡ.

```bash
sudo apt-mark unhold $(apt-mark showhold | grep -i postgresql) 2>/dev/null || true
sudo apt-get purge -y 'postgresql*' 'libpq*' pgdg-keyring
sudo apt-get autoremove -y --purge
sudo apt-get clean
```

`purge` (không phải `remove`) để xóa luôn file cấu hình trong `/etc/postgresql`.

## 4. Xóa dữ liệu, cấu hình, log còn sót

```bash
sudo rm -rf /var/lib/postgresql
sudo rm -rf /etc/postgresql /etc/postgresql-common
sudo rm -rf /var/log/postgresql
sudo rm -rf /var/run/postgresql /run/postgresql
sudo rm -rf /usr/share/postgresql-common
```

## 5. Xóa file backup và file tạm của demo

Thư mục backup do script `07_pre_upgrade_backup.sh` của UC02 tạo ra (chứa dump, bản copy data dir, `state.env`).

```bash
sudo rm -rf /var/backups/pg_upgrade_lab
sudo rm -f /usr/sbin/policy-rc.d
```

`policy-rc.d` thường đã được script nâng cấp tự xóa; lệnh trên chỉ để chắc chắn không còn, vì file này sẽ chặn mọi service tự khởi động.

## 6. Xóa repo apt và key đã thêm

Script `01_install_postgresql_*.sh` thêm repo apt-archive, file pin và key.

```bash
sudo rm -f /etc/apt/sources.list.d/pgdg-archive.list
sudo rm -f /etc/apt/preferences.d/pgdg.pref
sudo rm -f /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc
sudo apt-get update
```

## 7. Xóa user và group postgres

```bash
sudo deluser --remove-home postgres 2>/dev/null || true
sudo delgroup postgres 2>/dev/null || true
```

## 8. Kiểm tra đã sạch

Các lệnh dưới đây đều phải không in ra gì (hoặc báo không tìm thấy).

```bash
dpkg -l | grep -i postgres
which psql postgres pg_ctl
ls /var/lib/postgresql /etc/postgresql /var/log/postgresql 2>&1
getent passwd postgres
systemctl list-units --all | grep -i postgres
ss -ltnp | grep 5432
```

Nếu `ss` vẫn thấy cổng 5432 thì còn tiến trình chạy, quay lại bước 2 và dùng `pkill`.

## Chạy một lần (gộp tất cả bước 2–7)

Chỉ dùng khi đã chắc chắn không cần dữ liệu.

```bash
sudo bash -c '
systemctl stop postgresql; systemctl disable postgresql
pkill -u postgres
apt-mark unhold $(apt-mark showhold | grep -i postgresql) 2>/dev/null
apt-get purge -y "postgresql*" "libpq*" pgdg-keyring
apt-get autoremove -y --purge
rm -rf /var/lib/postgresql /etc/postgresql /etc/postgresql-common /var/log/postgresql /run/postgresql /usr/share/postgresql-common
rm -rf /var/backups/pg_upgrade_lab
rm -f /usr/sbin/policy-rc.d /etc/apt/sources.list.d/pgdg-archive.list /etc/apt/preferences.d/pgdg.pref
deluser --remove-home postgres 2>/dev/null; delgroup postgres 2>/dev/null
apt-get update
'
```

---

# Phụ lục: máy Windows (bản PostgreSQL 18 dùng để test cục bộ)

Mở PowerShell bằng quyền Administrator.

```powershell
# 1. Dừng và xóa service
Get-Service | Where-Object Name -like 'postgresql*' | Stop-Service -Force

# 2. Gỡ bằng uninstaller đi kèm (xóa luôn data dir nếu được hỏi)
& "C:\Program Files\PostgreSQL\18\uninstall-postgresql.exe" --mode unattended

# 3. Xóa thư mục còn sót (kể cả data)
Remove-Item -Recurse -Force "C:\Program Files\PostgreSQL" -ErrorAction SilentlyContinue

# 4. Xóa user postgres do installer tạo
net user postgres /delete

# 5. Xóa dữ liệu cấu hình của người dùng (pgAdmin, pgpass)
Remove-Item -Recurse -Force "$env:APPDATA\postgresql" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$env:APPDATA\pgadmin" -ErrorAction SilentlyContinue
```

Kiểm tra: `Get-Service postgresql*` và `Test-Path "C:\Program Files\PostgreSQL"` phải không còn kết quả. Nếu đã tạo cluster test bằng `initdb` trong thư mục tạm thì chỉ cần `pg_ctl -D <pgdata> stop -m fast` rồi xóa thư mục đó.
