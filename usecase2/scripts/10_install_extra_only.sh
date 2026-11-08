#!/usr/bin/env bash
# =============================================================================
# 10_install_extra_only.sh
# INCREMENTAL install: add the extra tables / indexes / functions (sql/10) on top of what is
# already installed (PostgreSQL + shop.product_reviews from 01 and 06). Nothing existing is
# reinstalled or modified. Re-running it only recreates the objects of sql/10.
#
# Usage:
#   sudo DB_NAME=shopdb SCALE=1 bash scripts/10_install_extra_only.sh
#   SCALE=1 is about 80-90 MB of new data; SCALE=0.5 is about half.
# =============================================================================
set -euo pipefail

DB_NAME="${DB_NAME:-shopdb}"
SCALE="${SCALE:-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="${SCRIPT_DIR}/../sql/10_extra_objects.sql"

log() { echo -e "\n\033[1;32m==> $*\033[0m"; }
die() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root (sudo)."
[[ -f "${SQL_FILE}" ]] || die "Missing ${SQL_FILE}"

log "1. Check the current installation"
pg_isready -q -h /var/run/postgresql -p 5432 || die "PostgreSQL is not running."
sudo -u postgres psql -At -c 'SHOW server_version;'
[[ "$(sudo -u postgres psql -At -d "${DB_NAME}" -c "SELECT to_regclass('shop.product_reviews') IS NOT NULL")" == "t" ]] \
  || die "shop.product_reviews not found in ${DB_NAME}. Run 01 and 06 first, or use scripts/11_install_full.sh."
echo "product_reviews rows: $(sudo -u postgres psql -At -d "${DB_NAME}" -c 'SELECT count(*) FROM shop.product_reviews')"

log "2. Create the extra objects (scale=${SCALE})"
# Read the file via stdin: the postgres user may not be able to read the path of this script.
sudo -u postgres psql -d "${DB_NAME}" -v ON_ERROR_STOP=1 -v scale="${SCALE}" < "${SQL_FILE}"

log "3. Existing component still fine"
sudo -u postgres psql -d "${DB_NAME}" -At -c "SELECT 'fn_review_excerpt(2,10) = ' || shop.fn_review_excerpt(2,10)"

log "Done."
