#!/bin/bash
# CloudSync Health Check Script
# Monitors sync status, conflicts, and system health

set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$PROJECT_ROOT/config/cloudsync.conf"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "⚠️ Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE="$HOME/.cloudsync/health-check.log"

# Create log directory
mkdir -p "$HOME/.cloudsync"

echo -e "${BLUE}🔍 CloudSync Health Check${NC}"
echo "Timestamp: $TIMESTAMP"
echo "=" | head -c 50 && echo

# Function to log messages
log_message() {
    echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
    echo -e "$1"
}

# Check rclone connectivity
check_rclone_connectivity() {
    echo -n "🌐 Checking rclone connectivity... "
    if rclone lsd "$DEFAULT_REMOTE:" >/dev/null 2>&1; then
        log_message "${GREEN}✅ rclone connectivity: OK${NC}"
    else
        log_message "${RED}❌ rclone connectivity: FAILED${NC}"
        return 1
    fi
}

# Check for conflicts
check_conflicts() {
    echo -n "⚔️ Checking for sync conflicts... "
    CONFLICT_COUNT=0

    # Check for .conflict files
    if find "$HOME" -name "*.conflict" -type f 2>/dev/null | grep -q .; then
        CONFLICT_COUNT=$(find "$HOME" -name "*.conflict" -type f 2>/dev/null | wc -l)
        log_message "${YELLOW}⚠️ Found $CONFLICT_COUNT conflict files${NC}"
    else
        log_message "${GREEN}✅ No conflicts detected${NC}"
    fi

    return $CONFLICT_COUNT
}

# Check last sync status
check_last_sync() {
    echo -n "📅 Checking last sync status... "

    if [[ -f "$HOME/.cloudsync/last-sync" ]]; then
        LAST_SYNC=$(cat "$HOME/.cloudsync/last-sync")
        LAST_SYNC_TIME=$(date -d "$LAST_SYNC" +%s 2>/dev/null || echo "0")
        CURRENT_TIME=$(date +%s)
        TIME_DIFF=$((CURRENT_TIME - LAST_SYNC_TIME))

        if [[ $TIME_DIFF -lt 86400 ]]; then  # 24 hours
            log_message "${GREEN}✅ Last sync: $LAST_SYNC (recent)${NC}"
        elif [[ $TIME_DIFF -lt 604800 ]]; then  # 7 days
            log_message "${YELLOW}⚠️ Last sync: $LAST_SYNC (aging)${NC}"
        else
            log_message "${RED}❌ Last sync: $LAST_SYNC (stale)${NC}"
        fi
    else
        log_message "${YELLOW}⚠️ No sync history found${NC}"
    fi
}

# Check disk space
check_disk_space() {
    echo -n "💾 Checking disk space... "

    DISK_USAGE=$(df "$HOME" | tail -1 | awk '{print $5}' | sed 's/%//')

    if [[ $DISK_USAGE -lt 80 ]]; then
        log_message "${GREEN}✅ Disk usage: ${DISK_USAGE}% (OK)${NC}"
    elif [[ $DISK_USAGE -lt 90 ]]; then
        log_message "${YELLOW}⚠️ Disk usage: ${DISK_USAGE}% (Warning)${NC}"
    else
        log_message "${RED}❌ Disk usage: ${DISK_USAGE}% (Critical)${NC}"
    fi
}

# Check backup status
check_backup_status() {
    echo -n "🗄️ Checking backup status... "

    if command -v restic >/dev/null 2>&1; then
        if [[ -d "$RESTIC_REPOSITORY_PATH" ]]; then
            export RESTIC_REPOSITORY="$RESTIC_REPOSITORY_PATH"
            export RESTIC_PASSWORD="$RESTIC_PASSWORD"

            SNAPSHOTS=$(restic snapshots --json 2>/dev/null | jq length 2>/dev/null || echo "0")
            if [[ $SNAPSHOTS -gt 0 ]]; then
                LAST_BACKUP=$(restic snapshots --json 2>/dev/null | jq -r '.[0].time' 2>/dev/null || echo "unknown")
                log_message "${GREEN}✅ Backup status: $SNAPSHOTS snapshots, last: $LAST_BACKUP${NC}"
            else
                log_message "${YELLOW}⚠️ Backup status: No snapshots found${NC}"
            fi
        else
            log_message "${YELLOW}⚠️ Backup repository not found${NC}"
        fi
    else
        log_message "${YELLOW}⚠️ Restic not installed${NC}"
    fi
}

# Main health check
main() {
    local exit_code=0

    check_rclone_connectivity || exit_code=1
    check_conflicts || exit_code=1
    check_last_sync
    check_disk_space
    check_backup_status

    echo
    if [[ $exit_code -eq 0 ]]; then
        log_message "${GREEN}🎉 CloudSync health check: ALL SYSTEMS OPERATIONAL${NC}"
    else
        log_message "${RED}⚠️ CloudSync health check: ISSUES DETECTED${NC}"
    fi

    echo "📝 Full log: $LOG_FILE"
    exit $exit_code
}

# Run health check
main "$@"