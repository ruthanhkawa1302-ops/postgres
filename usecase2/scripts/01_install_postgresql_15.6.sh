#!/usr/bin/env bash
# =============================================================================
# 01_install_postgresql_15.6.sh
# Install a STANDALONE PostgreSQL 15.6 server (postgresql-15 = 15.6-*.pgdg24.04+*)
# on Ubuntu 24.04 (single node, no replication)
# from the PGDG *archive* repository, pin the version (apt-mark hold) so that
# it stays on 15.6 until we deliberately run the minor upgrade to 15.16.
#
# Usage:
#   sudo PG_PASSWORD='ChangeMe@123' ALLOW_CIDR='0.0.0.0/0' bash 01_install_postgresql_15.6.sh
#
# Env variables (optional):
#   PG_VERSION_PKG  package version to install   (default: auto-detect 15.6-*)
#   PG_PASSWORD     password for role "postgres"  (default Postgres@123 - CHANGE IT)
#   ALLOW_CIDR      client network allowed in pg_hba (default 0.0.0.0/0 - lab only)
#   DB_NAME         demo database to create       (default shopdb)
# =============================================================================
set -euo pipefail

PG_MAJOR=15
PG_VERSION_PKG="${PG_VERSION_PKG:-}"      # empty = auto-detect the 15.6-* build from apt-cache madison
PG_PASSWORD="${PG_PASSWORD:-Postgres@123}"
ALLOW_CIDR="${ALLOW_CIDR:-0.0.0.0/0}"
DB_NAME="${DB_NAME:-shopdb}"

PG_CONF_DIR="/etc/postgresql/${PG_MAJOR}/main"
ARCHIVE_URL="https://apt-archive.postgresql.org/pub/repos/apt"
KEY_URL="https://www.postgresql.org/media/keys/ACCC4CF8.asc"
KEYRING="/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc"

log() { echo -e "\n\033[1;32m==> $*\033[0m"; }
die() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run this script as root (sudo)."
. /etc/os-release
[[ "${VERSION_CODENAME:-}" == "noble" ]] || die "This script targets Ubuntu 24.04 (noble). Found: ${PRETTY_NAME:-unknown}"

# -----------------------------------------------------------------------------
log "1. Install prerequisites"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl ca-certificates gnupg lsb-release

# -----------------------------------------------------------------------------
log "2. Add PGDG archive repository (noble-pgdg-archive) + signing key"
install -d /usr/share/postgresql-common/pgdg
curl -fsSL -o "${KEYRING}" "${KEY_URL}"
echo "deb [signed-by=${KEYRING}] ${ARCHIVE_URL} noble-pgdg-archive main" \
  > /etc/apt/sources.list.d/pgdg-archive.list

# Prefer PGDG packages over Ubuntu's own postgresql-15 build
cat > /etc/apt/preferences.d/pgdg.pref <<'EOF'
Package: *
Pin: origin apt-archive.postgresql.org
Pin-Priority: 600
EOF

apt-get update -y

log "Available postgresql-${PG_MAJOR} versions:"
MADISON="$(apt-cache madison "postgresql-${PG_MAJOR}" || true)"   # keep in a variable: grep -q + pipefail would SIGPIPE apt-cache
echo "${MADISON}" | head -n 20
if [[ -z "${PG_VERSION_PKG}" ]]; then
  PG_VERSION_PKG="$(echo "${MADISON}" | awk -F'|' '{gsub(/ /,"",$2); print $2}' | grep -E '^15\.6-' | head -n1 || true)"
fi
[[ -n "${PG_VERSION_PKG}" ]] || die "No 15.6-* build of postgresql-${PG_MAJOR} in the repository."
grep -qF "| ${PG_VERSION_PKG} |" <<< "${MADISON}" \
  || die "Version ${PG_VERSION_PKG} not found in repository."

# -----------------------------------------------------------------------------
log "3. Install postgresql-${PG_MAJOR}=${PG_VERSION_PKG}"
apt-get install -y \
  "postgresql-${PG_MAJOR}=${PG_VERSION_PKG}" \
  "postgresql-client-${PG_MAJOR}=${PG_VERSION_PKG}" \
  postgresql-common postgresql-client-common

# Freeze the version so 'apt upgrade' cannot move us to 15.16 by accident
apt-mark hold "postgresql-${PG_MAJOR}" "postgresql-client-${PG_MAJOR}"

# -----------------------------------------------------------------------------
log "4. Configure pg_hba (postgresql.conf is left at PostgreSQL defaults)"
HBA="${PG_CONF_DIR}/pg_hba.conf"
if ! grep -q "# demo-lab-remote-access" "${HBA}"; then
  cat >> "${HBA}" <<EOF

# demo-lab-remote-access
host    all             all             ${ALLOW_CIDR}            scram-sha-256
host    all             all             ::/0                     scram-sha-256
EOF
fi

# -----------------------------------------------------------------------------
log "5. Enable + restart service"
systemctl enable postgresql
systemctl restart postgresql
for i in {1..30}; do
  pg_isready -q -h /var/run/postgresql -p 5432 && break
  sleep 1
done
pg_isready -h /var/run/postgresql -p 5432 || die "PostgreSQL did not start."

# -----------------------------------------------------------------------------
log "6. Set postgres password + create demo database '${DB_NAME}'"
sudo -u postgres psql -v ON_ERROR_STOP=1 -q <<EOF
ALTER ROLE postgres WITH PASSWORD '${PG_PASSWORD}';
SELECT 'CREATE DATABASE ${DB_NAME} ENCODING ''UTF8'' TEMPLATE template0'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}')\gexec
EOF

# Open firewall if ufw is active
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow 5432/tcp
fi

# -----------------------------------------------------------------------------
log "7. Result"
dpkg -l | grep -E "^.i +postgresql-(15|client-15) " || true
apt-mark showhold
pg_lsclusters
sudo -u postgres psql -At -c "SELECT version();"
sudo -u postgres psql -At -c "SHOW server_version;"
systemctl --no-pager status "postgresql@${PG_MAJOR}-main" | head -n 5

echo
echo "PostgreSQL ${PG_VERSION_PKG} installed. Database '${DB_NAME}' ready."
echo "Next: sudo DB_NAME=${DB_NAME} bash scripts/06_install_review_data.sh"
