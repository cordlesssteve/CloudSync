#!/bin/bash
# CloudSync Automatic Sync Trigger System
# Processes batched file changes and triggers appropriate sync operations

set -euo pipefail

# Load configurations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$PROJECT_ROOT/config/cloudsync.conf"
MONITOR_CONFIG="$PROJECT_ROOT/config/monitoring.conf"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "⚠️ Configuration file not found: $CONFIG_FILE"
    exit 1
fi

if [[ -f "$MONITOR_CONFIG" ]]; then
    source "$MONITOR_CONFIG"
else
    echo "⚠️ Monitoring configuration not found: $MONITOR_CONFIG"
    exit 1
fi

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE="$HOME/.cloudsync/sync-trigger.log"
SYNC_LOCK_FILE="$HOME/.cloudsync/sync.lock"

# Create required directories
mkdir -p "$HOME/.cloudsync"

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

    case "$level" in
        "ERROR")
            echo -e "${RED}[$timestamp] [ERROR] $message${NC}" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[$timestamp] [WARN] $message${NC}"
            ;;
        "INFO")
            echo -e "${GREEN}[$timestamp] [INFO] $message${NC}"
            ;;
        "DEBUG")
            echo -e "${BLUE}[$timestamp] [DEBUG] $message${NC}"
            ;;
    esac
}

# Function to check if sync is already running
check_sync_lock() {
    if [[ -f "$SYNC_LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$SYNC_LOCK_FILE" 2>/dev/null || echo "")

        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            log_message "WARN" "Sync already running with PID: $lock_pid"
            return 1
        else
            log_message "INFO" "Removing stale lock file"
            rm -f "$SYNC_LOCK_FILE"
        fi
    fi
    return 0
}

# Function to create sync lock
create_sync_lock() {
    echo $$ > "$SYNC_LOCK_FILE"
    log_message "DEBUG" "Created sync lock with PID: $$"
}

# Function to remove sync lock
remove_sync_lock() {
    rm -f "$SYNC_LOCK_FILE"
    log_message "DEBUG" "Removed sync lock"
}

# Function to analyze file changes
analyze_changes() {
    local changes_file="$1"

    if [[ ! -f "$changes_file" ]] || [[ ! -s "$changes_file" ]]; then
        log_message "ERROR" "Changes file not found or empty: $changes_file"
        return 1
    fi

    local total_changes
    total_changes=$(wc -l < "$changes_file")

    # Count different types of changes
    local creates deletes modifies moves attribs
    creates=$(grep -c "|CREATE|" "$changes_file" || echo "0")
    deletes=$(grep -c "|DELETE|" "$changes_file" || echo "0")
    modifies=$(grep -c "|MODIFY|" "$changes_file" || echo "0")
    moves=$(grep -c "|MOVE|" "$changes_file" || echo "0")
    attribs=$(grep -c "|ATTRIB|" "$changes_file" || echo "0")

    log_message "INFO" "📊 Change analysis: Total=$total_changes Creates=$creates Deletes=$deletes Modifies=$modifies Moves=$moves Attribs=$attribs"

    # Identify affected paths
    local affected_paths=()
    while IFS='|' read -r timestamp events filepath; do
        # Extract the relative path from HOME
        local rel_path="${filepath#$HOME/}"
        local base_path
        base_path=$(echo "$rel_path" | cut -d'/' -f1)

        # Add to affected paths if not already present
        if [[ ! " ${affected_paths[*]} " =~ " ${base_path} " ]]; then
            affected_paths+=("$base_path")
        fi
    done < "$changes_file"

    log_message "INFO" "📂 Affected paths: ${affected_paths[*]}"

    # Determine sync strategy based on changes
    local sync_strategy="bidirectional"
    if (( deletes > total_changes / 2 )); then
        sync_strategy="careful"
        log_message "WARN" "Many deletions detected, using careful sync strategy"
    elif (( creates > total_changes * 3 / 4 )); then
        sync_strategy="upload-focused"
        log_message "INFO" "Many new files detected, using upload-focused strategy"
    fi

    echo "$sync_strategy|${affected_paths[*]}|$total_changes"
}

# Function to determine sync scope
determine_sync_scope() {
    local affected_paths="$1"
    local strategy="$2"

    read -ra paths_array <<< "$affected_paths"

    # Check if we should do full sync or partial sync
    local full_sync=false
    local critical_paths_affected=0

    for path in "${paths_array[@]}"; do
        for critical_path in "${CRITICAL_PATHS[@]}"; do
            if [[ "$path" == "$critical_path" ]] || [[ "$critical_path" == *"$path"* ]]; then
                ((critical_paths_affected++))
                break
            fi
        done
    done

    # If more than half of critical paths affected, do full sync
    if (( critical_paths_affected > ${#CRITICAL_PATHS[@]} / 2 )); then
        full_sync=true
        log_message "INFO" "Multiple critical paths affected, performing full sync"
    fi

    echo "$full_sync"
}

# Function to execute sync operation
execute_sync() {
    local strategy="$1"
    local affected_paths="$2"
    local full_sync="$3"
    local change_count="$4"

    log_message "INFO" "🚀 Executing sync: strategy=$strategy, full_sync=$full_sync, changes=$change_count"

    local sync_options=""
    local sync_command

    # Build sync options based on strategy
    case "$strategy" in
        "careful")
            sync_options="--dry-run --verbose"
            ;;
        "upload-focused")
            sync_options="--checksum"
            ;;
        "bidirectional")
            sync_options=""
            ;;
    esac

    # Add auto-sync specific options
    if [[ "$AUTO_SYNC_DRY_RUN_FIRST" == "true" ]]; then
        sync_options="$sync_options --dry-run"
    fi

    # Choose sync script based on strategy and scope
    if [[ "$AUTO_SYNC_BIDIRECTIONAL" == "true" ]] && [[ "$full_sync" == "true" ]]; then
        sync_command="$PROJECT_ROOT/scripts/core/bidirectional-sync.sh"
        log_message "INFO" "Using bidirectional sync for full sync"
    else
        # Use regular rclone sync for partial syncs
        sync_command="rclone sync"
        log_message "INFO" "Using unidirectional sync for partial sync"
    fi

    # Execute pre-sync hooks if they exist
    local pre_hook="$PROJECT_ROOT/scripts/hooks/pre-sync.sh"
    if [[ -x "$pre_hook" ]]; then
        log_message "INFO" "Running pre-sync hook"
        if ! "$pre_hook"; then
            log_message "ERROR" "Pre-sync hook failed"
            return 1
        fi
    fi

    # Execute the sync
    local sync_start_time sync_end_time sync_duration
    sync_start_time=$(date +%s)

    local sync_success=true
    if [[ "$sync_command" == *"bidirectional-sync.sh"* ]]; then
        # Use our bidirectional sync script
        if ! eval "$sync_command $sync_options"; then
            sync_success=false
        fi
    else
        # Use direct rclone for specific paths
        read -ra paths_array <<< "$affected_paths"
        for path in "${paths_array[@]}"; do
            local local_path="$HOME/$path"
            local remote_path="$DEFAULT_REMOTE:$SYNC_BASE_PATH/$path"

            if [[ -e "$local_path" ]]; then
                log_message "INFO" "Syncing: $local_path -> $remote_path"
                if ! eval "rclone sync \"$local_path\" \"$remote_path\" $sync_options"; then
                    sync_success=false
                    log_message "ERROR" "Failed to sync: $path"
                    break
                fi
            fi
        done
    fi

    sync_end_time=$(date +%s)
    sync_duration=$((sync_end_time - sync_start_time))

    if $sync_success; then
        log_message "INFO" "✅ Sync completed successfully in ${sync_duration}s"

        # Execute post-sync hooks if they exist
        local post_hook="$PROJECT_ROOT/scripts/hooks/post-sync.sh"
        if [[ -x "$post_hook" ]]; then
            log_message "INFO" "Running post-sync hook"
            "$post_hook" "$strategy" "$change_count" "$sync_duration" || true
        fi

        # Update sync statistics
        update_sync_statistics "$strategy" "$change_count" "$sync_duration" "success"

        # Send notification if enabled
        if [[ "$AUTO_SYNC_NOTIFY" == "true" ]]; then
            send_notification "success" "$change_count" "$sync_duration"
        fi

        return 0
    else
        log_message "ERROR" "❌ Sync failed after ${sync_duration}s"
        update_sync_statistics "$strategy" "$change_count" "$sync_duration" "failed"

        if [[ "$AUTO_SYNC_NOTIFY" == "true" ]]; then
            send_notification "failed" "$change_count" "$sync_duration"
        fi

        return 1
    fi
}

# Function to update sync statistics
update_sync_statistics() {
    local strategy="$1"
    local change_count="$2"
    local duration="$3"
    local result="$4"

    local stats_file="$HOME/.cloudsync/auto-sync-stats.json"

    # Read existing stats or create new
    local existing_stats="{}"
    if [[ -f "$stats_file" ]]; then
        existing_stats=$(cat "$stats_file")
    fi

    # Update stats
    local updated_stats
    updated_stats=$(echo "$existing_stats" | jq \
        --arg timestamp "$(date -Iseconds)" \
        --arg strategy "$strategy" \
        --argjson changes "$change_count" \
        --argjson duration "$duration" \
        --arg result "$result" \
        '
        .last_sync = {
            timestamp: $timestamp,
            strategy: $strategy,
            changes: $changes,
            duration: $duration,
            result: $result
        } |
        .total_syncs = (.total_syncs // 0) + 1 |
        if $result == "success" then
            .successful_syncs = (.successful_syncs // 0) + 1
        else
            .failed_syncs = (.failed_syncs // 0) + 1
        end |
        .total_changes = (.total_changes // 0) + $changes |
        .total_duration = (.total_duration // 0) + $duration
        ')

    echo "$updated_stats" > "$stats_file"
    log_message "DEBUG" "Updated sync statistics"
}

# Function to send notification
send_notification() {
    local result="$1"
    local change_count="$2"
    local duration="$3"

    # Create notification for dashboard
    local notification_file="$HOME/.cloudsync/dashboard-events.jsonl"
    local notification
    notification=$(jq -n \
        --arg type "auto_sync" \
        --arg result "$result" \
        --argjson changes "$change_count" \
        --argjson duration "$duration" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            type: $type,
            result: $result,
            changes: $changes,
            duration: $duration,
            timestamp: $timestamp
        }')

    echo "$notification" >> "$notification_file"

    # Send webhook if enabled
    if [[ "$WEBHOOK_ENABLED" == "true" ]] && [[ -n "$WEBHOOK_URL" ]]; then
        curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "$notification" || true
    fi

    log_message "DEBUG" "Sent notification: $result"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 <changes_file>"
    echo ""
    echo "Arguments:"
    echo "  changes_file        File containing batched file changes"
    echo ""
    echo "Description:"
    echo "  Processes a file containing batched file change events and"
    echo "  triggers appropriate sync operations based on the changes."
    echo ""
    echo "Change file format:"
    echo "  Each line should contain: timestamp|events|filepath"
    echo ""
    echo "Examples:"
    echo "  $0 /tmp/cloudsync-changes-12345"
}

# Main execution
main() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 1
    fi

    local changes_file="$1"

    log_message "INFO" "🔧 CloudSync Automatic Sync Trigger"
    log_message "INFO" "Processing changes from: $changes_file"

    # Check if auto-sync is enabled
    if [[ "$AUTO_SYNC_ENABLED" != "true" ]]; then
        log_message "WARN" "Auto-sync is disabled in configuration"
        exit 0
    fi

    # Check for sync lock
    if ! check_sync_lock; then
        log_message "ERROR" "Another sync operation is already running"
        exit 1
    fi

    # Create sync lock
    create_sync_lock
    trap remove_sync_lock EXIT

    # Analyze the changes
    local analysis_result
    if ! analysis_result=$(analyze_changes "$changes_file"); then
        log_message "ERROR" "Failed to analyze changes"
        exit 1
    fi

    IFS='|' read -r strategy affected_paths change_count <<< "$analysis_result"

    # Determine sync scope
    local full_sync
    full_sync=$(determine_sync_scope "$affected_paths" "$strategy")

    # Execute the sync
    if execute_sync "$strategy" "$affected_paths" "$full_sync" "$change_count"; then
        log_message "INFO" "🎉 Automatic sync trigger completed successfully"
        exit 0
    else
        log_message "ERROR" "❌ Automatic sync trigger failed"
        exit 1
    fi
}

# Run main function
main "$@"