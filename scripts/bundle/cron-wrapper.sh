#!/bin/bash
# CloudSync Git Bundle Sync - Cron Wrapper
# Adds monitoring, notifications, and error handling for scheduled runs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="${SCRIPT_DIR}/git-bundle-sync.sh"
LOG_DIR="${HOME}/.cloudsync/logs"
CRON_LOG="${LOG_DIR}/cron-sync.log"
ERROR_LOG="${LOG_DIR}/cron-errors.log"

# Create log directory
mkdir -p "${LOG_DIR}"

# Log start
echo "========================================" | tee -a "${CRON_LOG}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting scheduled CloudSync bundle sync" | tee -a "${CRON_LOG}"

# Run sync and capture output
if "${SYNC_SCRIPT}" sync >> "${CRON_LOG}" 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Sync completed successfully" | tee -a "${CRON_LOG}"
    exit 0
else
    EXIT_CODE=$?
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ Sync failed with exit code ${EXIT_CODE}" | tee -a "${CRON_LOG}" "${ERROR_LOG}"

    # Log error details
    echo "========================================" >> "${ERROR_LOG}"
    echo "Error occurred at: $(date)" >> "${ERROR_LOG}"
    echo "Exit code: ${EXIT_CODE}" >> "${ERROR_LOG}"
    echo "Last 50 lines of log:" >> "${ERROR_LOG}"
    tail -50 "${CRON_LOG}" >> "${ERROR_LOG}"

    exit "${EXIT_CODE}"
fi
