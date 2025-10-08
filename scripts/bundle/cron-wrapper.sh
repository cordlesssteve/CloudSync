#!/bin/bash
# CloudSync Git Bundle Sync - Cron Wrapper
# Adds monitoring, notifications, and error handling for scheduled runs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SYNC_SCRIPT="${SCRIPT_DIR}/git-bundle-sync.sh"
NOTIFY_SCRIPT="${PROJECT_ROOT}/scripts/notify.sh"
LOG_DIR="${HOME}/.cloudsync/logs"
CRON_LOG="${LOG_DIR}/cron-sync.log"
ERROR_LOG="${LOG_DIR}/cron-errors.log"

# Create log directory
mkdir -p "${LOG_DIR}"

# Log start
echo "========================================" | tee -a "${CRON_LOG}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting scheduled CloudSync bundle sync" | tee -a "${CRON_LOG}"

# Track start time for duration calculation
START_TIME=$(date +%s)

# Run sync and capture output
if "${SYNC_SCRIPT}" sync >> "${CRON_LOG}" 2>&1; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Sync completed successfully in ${DURATION}s" | tee -a "${CRON_LOG}"

    # Send success notification
    if [[ -x "${NOTIFY_SCRIPT}" ]]; then
        "${NOTIFY_SCRIPT}" success \
            "CloudSync: Bundle Sync Complete" \
            "All repositories synced successfully in ${DURATION}s at $(date '+%Y-%m-%d %H:%M:%S')" || true
    fi

    exit 0
else
    EXIT_CODE=$?
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ Sync failed with exit code ${EXIT_CODE} after ${DURATION}s" | tee -a "${CRON_LOG}" "${ERROR_LOG}"

    # Log error details
    echo "========================================" >> "${ERROR_LOG}"
    echo "Error occurred at: $(date)" >> "${ERROR_LOG}"
    echo "Exit code: ${EXIT_CODE}" >> "${ERROR_LOG}"
    echo "Duration: ${DURATION}s" >> "${ERROR_LOG}"
    echo "Last 50 lines of log:" >> "${ERROR_LOG}"
    tail -50 "${CRON_LOG}" >> "${ERROR_LOG}"

    # Send error notification
    if [[ -x "${NOTIFY_SCRIPT}" ]]; then
        "${NOTIFY_SCRIPT}" error \
            "CloudSync: Bundle Sync Failed" \
            "Sync failed with exit code ${EXIT_CODE} after ${DURATION}s. Check logs: ${ERROR_LOG}" || true
    fi

    exit "${EXIT_CODE}"
fi
