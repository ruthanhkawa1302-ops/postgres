#!/usr/bin/env bash
# =============================================================================
# 11_install_full.sh
# FULL install from scratch on a clean Ubuntu 24.04 server:
#   01 PostgreSQL 15.6 (+ hold)  ->  06 product_reviews + fn_review_excerpt  ->  10 extra objects
# For a server that already has 01 + 06, use 10_install_extra_only.sh instead.
#
# Usage:
#   sudo PG_PASSWORD='ChangeMe@123' ALLOW_CIDR='0.0.0.0/0' DB_NAME=shopdb SCALE=1 bash scripts/11_install_full.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DB_NAME="${DB_NAME:-shopdb}"
export SCALE="${SCALE:-1}"

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }

bash "${SCRIPT_DIR}/01_install_postgresql_15.6.sh"
bash "${SCRIPT_DIR}/06_install_review_data.sh"
bash "${SCRIPT_DIR}/10_install_extra_only.sh"

echo
echo "Full install finished: PostgreSQL 15.6 + product_reviews + extra objects in '${DB_NAME}'."
echo "Next: sudo bash scripts/07_pre_upgrade_backup.sh"
