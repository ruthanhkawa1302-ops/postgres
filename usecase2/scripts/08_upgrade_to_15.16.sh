#!/usr/bin/env bash
# =============================================================================
# 08_upgrade_to_15.16.sh
# In-place minor upgrade 15.6 -> 15.16 with apt. In this lab it is EXPECTED TO FAIL the smoke test:
# 15.16 has a regression of the CVE-2026-2006 fix (fixed in 15.17): substring() on TOASTed
# multi-byte text raises "invalid byte sequence for encoding", so shop.fn_review_excerpt() fails.
# Run 09_rollback_to_15.6.sh afterwards.
#
# Usage:
#   sudo BACKUP_DIR=/var/backups/pg_upgrade_lab bash scripts/08_upgrade_to_15.16.sh
#   (PG_NEW_VERSION_PKG=<exact string> to override the auto-detected 15.16-* build)
# =============================================================================
set -uo pipefail

PG_MAJOR=15
BACKUP_DIR="${BACKUP_DIR:-/var/backups/pg_upgrade_lab}"
NEW="${PG_NEW_VERSION_PKG:-}"
LOG_FILE="/var/log/postgresql/postgresql-${PG_MAJOR}-main.log"

log() { echo -e "\n\033[1;32m==> $*\033[0m"; }
die() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root (sudo)."
[[ -f "${BACKUP_DIR}/state.env" ]] || die "No backup found in ${BACKUP_DIR} - run 07_pre_upgrade_backup.sh first."

log "1. Pre-check"
dpkg-query -W -f='${Package} ${Version}\n' "postgresql-${PG_MAJOR}"
sudo -u postgres psql -At -c "SELECT version();" -c "SHOW shared_preload_libraries;" || die "Cluster is not running."

log "2. Find the 15.16 package"
apt-get update -y
apt-cache madison "postgresql-${PG_MAJOR}" | head -n 20
if [[ -z "${NEW}" ]]; then
  NEW="$(apt-cache madison "postgresql-${PG_MAJOR}" | awk -F'|' '{gsub(/ /,"",$2); print $2}' | grep -E '^15.16-' | head -n1)"
fi
[[ -n "${NEW}" ]] || die "No 15.16-* build found. Check: apt-cache madison postgresql-${PG_MAJOR}"
echo "Target version: ${NEW}"

log "3. Install ${NEW} (service restart suppressed during dpkg, we restart by hand in step 4)"
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d
apt-mark unhold "postgresql-${PG_MAJOR}" "postgresql-client-${PG_MAJOR}"
apt-get install -y "postgresql-${PG_MAJOR}=${NEW}" "postgresql-client-${PG_MAJOR}=${NEW}"
APT_RC=$?
rm -f /usr/sbin/policy-rc.d
apt-mark hold "postgresql-${PG_MAJOR}" "postgresql-client-${PG_MAJOR}"
echo "apt exit code: ${APT_RC}"
dpkg-query -W -f='${Package} ${Version}\n' "postgresql-${PG_MAJOR}" "postgresql-client-${PG_MAJOR}"

log "4. Restart the cluster on the new binaries"
systemctl restart "postgresql@${PG_MAJOR}-main"
for i in {1..20}; do pg_isready -q -h /var/run/postgresql && break; sleep 1; done

FAILED=0
if ! pg_isready -h /var/run/postgresql; then
  FAILED=1
  log "PostgreSQL does not start on ${NEW}"
  systemctl --no-pager status "postgresql@${PG_MAJOR}-main" | head -n 12
  pg_lsclusters
  echo "---- last log lines ----"
  tail -n 15 "${LOG_FILE}"
else
  log "5. Cluster is up on $(sudo -u postgres psql -At -c 'SHOW server_version;') - smoke test of the application objects"
  # each statement runs separately so that one failure does not hide the others
  run_check() {
    local name="$1" sql="$2"
    if out="$(sudo -u postgres psql -d "${DB_NAME:-shopdb}" -X -At -v ON_ERROR_STOP=1 -c "${sql}" 2>&1)"; then
      echo "  [ OK ] ${name}: ${out}"
    else
      echo "  [FAIL] ${name}: $(echo "${out}" | head -n 1)"
      FAILED=1
    fi
  }
  run_check "reviews are TOASTed"             "SELECT count(*) FROM shop.product_reviews WHERE pg_column_size(body) > 2000"
  run_check "fn_review_excerpt(1)"           "SELECT shop.fn_review_excerpt(1)"
  run_check "fn_review_excerpt(2)"           "SELECT shop.fn_review_excerpt(2)"
  run_check "v_review_excerpt (all rows)"    "SELECT count(*), count(excerpt) FROM shop.v_review_excerpt"
  run_check "all 10k excerpts (no error)"    'DO $$ DECLARE r bigint; n int := 0; BEGIN FOR r IN SELECT review_id FROM shop.product_reviews LOOP BEGIN PERFORM shop.fn_review_excerpt(r); EXCEPTION WHEN OTHERS THEN n := n + 1; END; END LOOP; IF n > 0 THEN RAISE EXCEPTION $m$% reviews cannot be cut$m$, n; END IF; END $$'
fi

if (( FAILED == 0 )); then
  log "Upgrade OK - run the full verification in docs/06_verification_queries.md"
  exit 0
fi

log "UPGRADE FAILED on ${NEW}"
echo "The cause is the substring() regression of 15.16 (fixed only in 15.17, which is not the plan here) -> ROLL BACK:"
echo "  sudo BACKUP_DIR=${BACKUP_DIR} bash scripts/09_rollback_to_15.6.sh"
exit 1
