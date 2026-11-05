#!/usr/bin/env bash
# =============================================================================
# 07_pre_upgrade_backup.sh
# Safety net before the 15.6 -> 15.16 upgrade (standalone, so no pgBackRest / base backup):
#   1. logical backup: pg_dumpall --globals-only + pg_dump -Fc of the demo database
#   2. cold copy of the data directory (cluster stopped for the copy)
#   3. a state file recording the current package version (used by the rollback script)
#
# Usage:
#   sudo DB_NAME=shopdb BACKUP_DIR=/var/backups/pg_upgrade_lab bash scripts/07_pre_upgrade_backup.sh
# =============================================================================
set -euo pipefail

PG_MAJOR=15
DB_NAME="${DB_NAME:-shopdb}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/pg_upgrade_lab}"
DATA_DIR="/var/lib/postgresql/${PG_MAJOR}/main"

log() { echo -e "\n\033[1;32m==> $*\033[0m"; }
die() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root (sudo)."
install -d -m 0750 -o postgres -g postgres "${BACKUP_DIR}"

OLD_VERSION="$(dpkg-query -W -f='${Version}' "postgresql-${PG_MAJOR}")"
NEED_KB=$(( $(du -sk "${DATA_DIR}" | cut -f1) * 12 / 10 ))
AVAIL_KB=$(df -Pk "${BACKUP_DIR}" | awk 'NR==2{print $4}')
(( AVAIL_KB > NEED_KB )) || die "Not enough free space in ${BACKUP_DIR} (need ~$((NEED_KB/1024)) MB)."

log "1. Logical backup (cluster online)"
sudo -u postgres pg_dumpall --globals-only > "${BACKUP_DIR}/globals.sql"
sudo -u postgres pg_dump -Fc -d "${DB_NAME}" -f "${BACKUP_DIR}/${DB_NAME}.dump"
ls -lh "${BACKUP_DIR}"

log "2. Cold copy of ${DATA_DIR} (cluster stopped)"
systemctl stop "postgresql@${PG_MAJOR}-main"
tar -C "$(dirname "${DATA_DIR}")" -cf "${BACKUP_DIR}/data_${PG_MAJOR}_main.tar" "$(basename "${DATA_DIR}")"
systemctl start "postgresql@${PG_MAJOR}-main"
for i in {1..60}; do pg_isready -q -h /var/run/postgresql && break; sleep 1; done
pg_isready -h /var/run/postgresql || die "PostgreSQL did not come back after the cold copy."

log "3. Record state for rollback"
cat > "${BACKUP_DIR}/state.env" <<STATE
OLD_VERSION='${OLD_VERSION}'
BACKUP_TIME='$(date -Is)'
STATE
cat "${BACKUP_DIR}/state.env"
log "Backup finished: ${BACKUP_DIR}"
