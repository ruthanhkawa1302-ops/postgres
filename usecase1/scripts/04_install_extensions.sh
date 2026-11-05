#!/usr/bin/env bash
# =============================================================================
# 04_install_extensions.sh
# Configure preload libraries, restart PostgreSQL and run sql/04_extensions.sql
# (CREATE EXTENSION ...). Only contrib extensions are used - they ship inside the
# postgresql-16 package, so no apt package is installed here.
#
# Usage:
#   sudo DB_NAME=shopdb bash scripts/04_install_extensions.sh
#
# Requires: 01_install_postgresql_16.2.sh already executed (postgresql-16 held at 16.2).
# =============================================================================
set -euo pipefail

PG_MAJOR=16
DB_NAME="${DB_NAME:-shopdb}"
PG_CONF_DIR="/etc/postgresql/${PG_MAJOR}/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="${SCRIPT_DIR}/../sql/04_extensions.sql"

log() { echo -e "\n\033[1;32m==> $*\033[0m"; }
die() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root (sudo)."
[[ -f "${SQL_FILE}" ]] || die "Not found: ${SQL_FILE}"

# -----------------------------------------------------------------------------
log "1. Check that postgresql-${PG_MAJOR} is still held at 16.2"
apt-mark showhold | grep -q "^postgresql-${PG_MAJOR}$" \
  || die "postgresql-${PG_MAJOR} is not on hold - run 01_install_postgresql_16.2.sh first."
dpkg-query -W -f='${Version}\n' "postgresql-${PG_MAJOR}"

# -----------------------------------------------------------------------------
log "2. Configure preload library (pg_stat_statements)"
cat > "${PG_CONF_DIR}/conf.d/10-extensions.conf" <<EOF
# ---- Extensions that need shared_preload_libraries ----
shared_preload_libraries = 'pg_stat_statements'

# pg_stat_statements
pg_stat_statements.max = 10000
pg_stat_statements.track = all
track_io_timing = on
EOF
chown postgres:postgres "${PG_CONF_DIR}/conf.d/10-extensions.conf"

# -----------------------------------------------------------------------------
log "3. Restart PostgreSQL to load the library"
systemctl restart "postgresql@${PG_MAJOR}-main"
for i in {1..30}; do pg_isready -q -h /var/run/postgresql && break; sleep 1; done
pg_isready -h /var/run/postgresql || die "PostgreSQL did not start - check /var/log/postgresql/postgresql-${PG_MAJOR}-main.log"
sudo -u postgres psql -At -c "SHOW shared_preload_libraries;"

# -----------------------------------------------------------------------------
log "4. CREATE EXTENSION in database ${DB_NAME}"
sudo -u postgres psql -d "${DB_NAME}" -v ON_ERROR_STOP=1 < "${SQL_FILE}"   # root reads the file: user postgres cannot enter /root

log "Done."
