#!/usr/bin/env bash
# =============================================================================
# 09_rollback_to_15.6.sh
# Roll back PostgreSQL 15.16 -> 15.6 (apt downgrade) after the failed upgrade of 08 (15.16).
# Minor versions share the on-disk format, so the data directory is reused as is.
# Only if the data directory is damaged: RESTORE_DATA=1 restores the cold copy from 07.
#
# Usage:
#   sudo BACKUP_DIR=/var/backups/pg_upgrade_lab bash scripts/09_rollback_to_15.6.sh
#   sudo RESTORE_DATA=1 BACKUP_DIR=... bash scripts/09_rollback_to_15.6.sh
# =============================================================================
set -euo pipefail

PG_MAJOR=15
DB_NAME="${DB_NAME:-shopdb}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/pg_upgrade_lab}"
RESTORE_DATA="${RESTORE_DATA:-0}"
DATA_DIR="/var/lib/postgresql/${PG_MAJOR}/main"

log() { echo -e "\n\033[1;32m==> $*\033[0m"; }
die() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root (sudo)."
#[[ -f "${BACKUP_DIR}/state.env" ]] || die "No ${BACKUP_DIR}/state.env - cannot tell which version to go back to."
# shellcheck disable=SC1091
. "${BACKUP_DIR}/state.env"
echo "Rolling back to postgresql-${PG_MAJOR} ${OLD_VERSION}"

log "1. Stop the cluster (it may already be down)"
systemctl stop "postgresql@${PG_MAJOR}-main" || true
pg_lsclusters

log "2. Downgrade packages to ${OLD_VERSION}"
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d
apt-mark unhold "postgresql-${PG_MAJOR}" "postgresql-client-${PG_MAJOR}"
dpkg --configure -a || true
apt-get install -y --allow-downgrades \
  "postgresql-${PG_MAJOR}=${OLD_VERSION}" "postgresql-client-${PG_MAJOR}=${OLD_VERSION}"
rm -f /usr/sbin/policy-rc.d
apt-mark hold "postgresql-${PG_MAJOR}" "postgresql-client-${PG_MAJOR}"
dpkg-query -W -f='${Package} ${Version}\n' "postgresql-${PG_MAJOR}" "postgresql-client-${PG_MAJOR}"

if [[ "${RESTORE_DATA}" == "1" ]]; then
  log "3. RESTORE_DATA=1: restore the cold copy of the data directory"
  [[ -f "${BACKUP_DIR}/data_${PG_MAJOR}_main.tar" ]] || die "Missing ${BACKUP_DIR}/data_${PG_MAJOR}_main.tar"
  mv "${DATA_DIR}" "${DATA_DIR}.broken.$(date +%s)"
  tar -C "$(dirname "${DATA_DIR}")" -xpf "${BACKUP_DIR}/data_${PG_MAJOR}_main.tar"
else
  log "3. Data directory kept as is (minor versions share the on-disk format, nothing to convert)"
fi

log "4. Start the cluster on ${OLD_VERSION}"
systemctl start "postgresql@${PG_MAJOR}-main"
for i in {1..60}; do pg_isready -q -h /var/run/postgresql && break; sleep 1; done
pg_isready -h /var/run/postgresql || die "PostgreSQL still does not start - see /var/log/postgresql/postgresql-${PG_MAJOR}-main.log (try RESTORE_DATA=1)"

log "5. Quick check"
sudo -u postgres psql -d "${DB_NAME}" -v ON_ERROR_STOP=1 -X <<'SQL'
SELECT version();
SELECT count(*) AS reviews FROM shop.product_reviews;
SELECT shop.fn_review_excerpt(1) AS excerpt_review_1;
SELECT count(*) AS excerpts_ok FROM shop.v_review_excerpt;
SQL

log "Rollback finished. Run the full verification in docs/06_verification_queries.md."
