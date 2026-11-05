#!/usr/bin/env bash
# =============================================================================
# 06_install_review_data.sh
# Create shop.product_reviews (10k long non-ASCII reviews stored in TOAST) and the function
# fn_review_excerpt() that uses substring(). This is the component that breaks on 15.16 (UC02).
# Nothing to install: no extension, no package.
#
# Usage:
#   sudo DB_NAME=shopdb bash scripts/06_install_review_data.sh
#
# Requires: 01 (PostgreSQL 15.6) only.
# =============================================================================
set -euo pipefail

PG_MAJOR=15
DB_NAME="${DB_NAME:-shopdb}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="${SCRIPT_DIR}/../sql/06_toast_review_objects.sql"

log() { echo -e "\n\033[1;32m==> $*\033[0m"; }
die() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root (sudo)."
[[ -f "${SQL_FILE}" ]] || die "Missing ${SQL_FILE}"

log "1. Check server version and database encoding (must be UTF8)"
dpkg-query -W -f='postgresql-15 ${Version}\n' "postgresql-${PG_MAJOR}"
ENC="$(sudo -u postgres psql -At -d "${DB_NAME}" -c 'SHOW server_encoding;')"
[[ "${ENC}" == "UTF8" ]] || die "server_encoding=${ENC}, the lab needs UTF8 (multi-byte characters)."

log "2. Create table, data and function in ${DB_NAME}"
sudo -u postgres psql -d "${DB_NAME}" -v ON_ERROR_STOP=1 -f "${SQL_FILE}"

log "Done. Review excerpts work on PostgreSQL $(sudo -u postgres psql -At -c 'SHOW server_version;')"
