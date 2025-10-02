#!/bin/bash
# CloudSync Real-time File Monitoring System
# Uses inotify to watch for file changes and trigger automatic sync operations

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

# Global variables
MONITOR_PID=""
TRIGGER_PID=""
LAST_SYNC_TIME=0
PENDING_CHANGES=""
CHANGE_BATCH_FILE="/tmp/cloudsync-changes-$$"
MONITOR_STATUS_FILE="$HOME/.cloudsync/monitor-status.json"

# Create required directories
mkdir -p "$HOME/.cloudsync"
mkdir -p "$(dirname "$MONITOR_LOG_FILE")"

# Cleanup function
cleanup() {
    log_message "INFO" "🛑 Stopping real-time monitoring..."

    if [[ -n "$MONITOR_PID" ]] && kill -0 "$MONITOR_PID" 2>/dev/null; then
        kill "$MONITOR_PID" 2>/dev/null || true
    fi

    if [[ -n "$TRIGGER_PID" ]] && kill -0 "$TRIGGER_PID" 2>/dev/null; then
        kill "$TRIGGER_PID" 2>/dev/null || true
    fi

    rm -f "$CHANGE_BATCH_FILE"
    rm -f "$EMERGENCY_STOP_FILE"

    update_monitor_status "stopped" "Manual stop"
    log_message "INFO" "✅ Real-time monitoring stopped"
}
trap cleanup EXIT INT TERM

# Logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Log to file
    echo "[$timestamp] [$level] $message" >> "$MONITOR_LOG_FILE"

    # Log to console based on level
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
            if [[ "$MONITOR_LOG_LEVEL" == "DEBUG" ]]; then
                echo -e "${BLUE}[$timestamp] [DEBUG] $message${NC}"
            fi
            ;;
    esac

    # Also log file events to separate file
    if [[ "$level" == "EVENT" ]]; then
        echo "[$timestamp] $message" >> "$MONITOR_EVENT_LOG"
    fi
}

# Function to update monitor status
update_monitor_status() {
    local status="$1"
    local message="$2"

    cat > "$MONITOR_STATUS_FILE" << EOF
{
  "status": "$status",
  "message": "$message",
  "last_update": "$(date -Iseconds)",
  "pid": $$,
  "monitor_pid": "${MONITOR_PID:-}",
  "trigger_pid": "${TRIGGER_PID:-}",
  "watches_active": $(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo "0"),
  "last_sync": $LAST_SYNC_TIME,
  "config": {
    "enabled": $REALTIME_MONITORING_ENABLED,
    "auto_sync": $AUTO_SYNC_ENABLED,
    "sync_delay": $SYNC_DELAY_SECONDS,
    "batch_changes": $BATCH_CHANGES
  }
}
EOF
}

# Function to check system resources
check_system_resources() {
    # Check CPU usage
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}' | cut -d' ' -f1)

    # Check memory usage
    local memory_usage
    memory_usage=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')

    if (( $(echo "$cpu_usage > $MONITOR_CPU_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
        log_message "WARN" "High CPU usage detected: ${cpu_usage}% (threshold: ${MONITOR_CPU_THRESHOLD}%)"
        return 1
    fi

    if (( memory_usage > MONITOR_MEMORY_THRESHOLD )); then
        log_message "WARN" "High memory usage detected: ${memory_usage}% (threshold: ${MONITOR_MEMORY_THRESHOLD}%)"
        return 1
    fi

    return 0
}

# Function to check if file should be monitored
should_monitor_file() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")

    # Check file size
    if [[ -f "$filepath" ]]; then
        local file_size_mb
        file_size_mb=$(du -m "$filepath" 2>/dev/null | cut -f1)
        if (( file_size_mb > MONITOR_MAX_FILE_SIZE_MB )); then
            log_message "DEBUG" "Skipping large file: $filepath (${file_size_mb}MB)"
            return 1
        fi
    fi

    # Check blacklisted extensions
    for ext in "${MONITOR_BLACKLIST_EXTENSIONS[@]}"; do
        if [[ "$filename" == *"$ext" ]]; then
            log_message "DEBUG" "Skipping blacklisted extension: $filepath"
            return 1
        fi
    done

    # Check exclusion patterns
    for pattern in "${MONITOR_EXCLUDE_PATTERNS[@]}"; do
        if [[ "$filepath" == *"$pattern"* ]] || [[ "$filename" == $pattern ]]; then
            log_message "DEBUG" "Skipping excluded pattern: $filepath"
            return 1
        fi
    done

    return 0
}

# Function to build inotify command
build_inotify_cmd() {
    local events_list=""
    for event in "${MONITOR_EVENTS[@]}"; do
        if [[ -n "$events_list" ]]; then
            events_list="$events_list,$event"
        else
            events_list="$event"
        fi
    done

    local cmd="inotifywait --monitor --format '%w%f|%e|%T'"
    cmd="$cmd --timefmt '%Y-%m-%d %H:%M:%S'"
    cmd="$cmd --events $events_list"

    if [[ "$MONITOR_RECURSIVE" == "true" ]]; then
        cmd="$cmd --recursive"
    fi

    if [[ "$MONITOR_QUIET" == "true" ]]; then
        cmd="$cmd --quiet"
    fi

    # Add exclude patterns
    for pattern in "${MONITOR_EXCLUDE_PATTERNS[@]}"; do
        cmd="$cmd --exclude '$pattern'"
    done

    echo "$cmd"
}

# Function to process file change event
process_file_event() {
    local event_line="$1"
    IFS='|' read -r filepath events timestamp <<< "$event_line"

    log_message "EVENT" "File event: $events on $filepath at $timestamp"

    # Check if file should be monitored
    if ! should_monitor_file "$filepath"; then
        return
    fi

    # Add to pending changes
    echo "$timestamp|$events|$filepath" >> "$CHANGE_BATCH_FILE"

    log_message "DEBUG" "Added to batch: $events $filepath"

    # Notify dashboard if enabled
    if [[ "$DASHBOARD_NOTIFY" == "true" ]]; then
        notify_dashboard "$events" "$filepath" "$timestamp"
    fi
}

# Function to notify dashboard
notify_dashboard() {
    local events="$1"
    local filepath="$2"
    local timestamp="$3"

    # Create notification for dashboard (if running)
    local notification_file="$HOME/.cloudsync/dashboard-events.jsonl"
    echo "{\"type\":\"file_event\",\"events\":\"$events\",\"path\":\"$filepath\",\"timestamp\":\"$timestamp\"}" >> "$notification_file"
}

# Function to trigger sync operation
trigger_sync() {
    local current_time
    current_time=$(date +%s)

    # Check minimum sync frequency
    if (( current_time - LAST_SYNC_TIME < MAX_SYNC_FREQUENCY )); then
        log_message "DEBUG" "Sync frequency limit reached, skipping trigger"
        return
    fi

    # Check if there are pending changes
    if [[ ! -f "$CHANGE_BATCH_FILE" ]] || [[ ! -s "$CHANGE_BATCH_FILE" ]]; then
        log_message "DEBUG" "No pending changes to sync"
        return
    fi

    local change_count
    change_count=$(wc -l < "$CHANGE_BATCH_FILE")

    log_message "INFO" "🚀 Triggering automatic sync for $change_count changes"

    # Run sync operation
    local sync_script="$PROJECT_ROOT/scripts/monitoring/sync-trigger.sh"

    if [[ -x "$sync_script" ]]; then
        if "$sync_script" "$CHANGE_BATCH_FILE"; then
            LAST_SYNC_TIME=$current_time
            log_message "INFO" "✅ Automatic sync completed successfully"

            # Clear batch file
            > "$CHANGE_BATCH_FILE"
        else
            log_message "ERROR" "❌ Automatic sync failed"
        fi
    else
        log_message "ERROR" "Sync trigger script not found or not executable: $sync_script"
    fi

    # Update status
    update_monitor_status "monitoring" "Last sync: $(date -Iseconds)"
}

# Function to start file monitoring
start_monitoring() {
    log_message "INFO" "🔍 Starting real-time file monitoring..."

    # Check if emergency stop file exists
    if [[ -f "$EMERGENCY_STOP_FILE" ]]; then
        log_message "ERROR" "Emergency stop file exists: $EMERGENCY_STOP_FILE"
        log_message "ERROR" "Remove this file to enable monitoring"
        return 1
    fi

    # Check system resources
    if ! check_system_resources; then
        log_message "ERROR" "System resources exceeded thresholds"
        return 1
    fi

    # Build watch paths
    local watch_paths=()
    for path in "${MONITOR_PATHS[@]}"; do
        local full_path="$HOME/$path"
        if [[ -e "$full_path" ]]; then
            watch_paths+=("$full_path")
            log_message "INFO" "📂 Monitoring: $full_path"
        else
            log_message "WARN" "Path not found: $full_path"
        fi
    done

    if [[ ${#watch_paths[@]} -eq 0 ]]; then
        log_message "ERROR" "No valid paths to monitor"
        return 1
    fi

    # Build and execute inotify command
    local inotify_cmd
    inotify_cmd=$(build_inotify_cmd)

    log_message "INFO" "Starting inotify with command: $inotify_cmd"

    # Start inotify in background
    {
        eval "$inotify_cmd ${watch_paths[*]}" | while IFS= read -r line; do
            if [[ -f "$EMERGENCY_STOP_FILE" ]]; then
                log_message "INFO" "Emergency stop detected, exiting monitor"
                break
            fi

            process_file_event "$line"
        done
    } &

    MONITOR_PID=$!
    log_message "INFO" "✅ File monitoring started with PID: $MONITOR_PID"

    # Start sync trigger loop
    start_sync_trigger_loop &
    TRIGGER_PID=$!
    log_message "INFO" "✅ Sync trigger loop started with PID: $TRIGGER_PID"

    update_monitor_status "monitoring" "Active monitoring started"

    return 0
}

# Function to start sync trigger loop
start_sync_trigger_loop() {
    while true; do
        if [[ -f "$EMERGENCY_STOP_FILE" ]]; then
            log_message "INFO" "Emergency stop detected, exiting trigger loop"
            break
        fi

        # Check if batch timeout reached or if we have pending changes
        if [[ -f "$CHANGE_BATCH_FILE" ]] && [[ -s "$CHANGE_BATCH_FILE" ]]; then
            local oldest_change
            oldest_change=$(head -n1 "$CHANGE_BATCH_FILE" | cut -d'|' -f1)
            local oldest_time
            oldest_time=$(date -d "$oldest_change" +%s 2>/dev/null || echo "0")
            local current_time
            current_time=$(date +%s)

            # Check if delay period has passed
            if (( current_time - oldest_time >= SYNC_DELAY_SECONDS )); then
                trigger_sync
            fi

            # Check if batch timeout reached
            if (( current_time - oldest_time >= BATCH_TIMEOUT_SECONDS )); then
                log_message "INFO" "Batch timeout reached, forcing sync"
                trigger_sync
            fi
        fi

        sleep 5  # Check every 5 seconds
    done
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo ""
    echo "Commands:"
    echo "  start               Start real-time monitoring"
    echo "  stop                Stop real-time monitoring"
    echo "  status              Show monitoring status"
    echo "  restart             Restart monitoring service"
    echo "  test                Test monitoring configuration"
    echo ""
    echo "Options:"
    echo "  --daemon            Run as daemon (background)"
    echo "  --debug             Enable debug logging"
    echo "  --dry-run           Test mode without actual sync"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 start --daemon"
    echo "  $0 status"
    echo "  $0 test --debug"
}

# Function to check if monitoring is running
is_monitoring_running() {
    if [[ -f "$MONITOR_STATUS_FILE" ]]; then
        local status
        status=$(jq -r '.status' "$MONITOR_STATUS_FILE" 2>/dev/null || echo "unknown")
        local pid
        pid=$(jq -r '.pid' "$MONITOR_STATUS_FILE" 2>/dev/null || echo "0")

        if [[ "$status" == "monitoring" ]] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# Function to show monitoring status
show_status() {
    log_message "INFO" "📊 CloudSync Real-time Monitoring Status"

    if [[ -f "$MONITOR_STATUS_FILE" ]]; then
        echo "Status file contents:"
        cat "$MONITOR_STATUS_FILE" | jq '.' 2>/dev/null || cat "$MONITOR_STATUS_FILE"
    else
        echo "Status: Not running (no status file)"
    fi

    echo ""
    echo "System information:"
    echo "  inotify max watches: $(cat /proc/sys/fs/inotify/max_user_watches)"
    echo "  Current watches: $(find /proc/*/fd -lname anon_inode:inotify 2>/dev/null | wc -l)"
    echo "  Emergency stop file: $([[ -f "$EMERGENCY_STOP_FILE" ]] && echo "EXISTS" || echo "not present")"
}

# Main execution
main() {
    local command=""
    local daemon_mode=false
    local debug_mode=false
    local dry_run=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            start|stop|status|restart|test)
                command="$1"
                shift
                ;;
            --daemon)
                daemon_mode=true
                shift
                ;;
            --debug)
                debug_mode=true
                MONITOR_LOG_LEVEL="DEBUG"
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    if [[ -z "$command" ]]; then
        show_usage
        exit 1
    fi

    log_message "INFO" "🔧 CloudSync Real-time Monitor - Command: $command"

    case "$command" in
        start)
            if is_monitoring_running; then
                log_message "WARN" "Monitoring is already running"
                exit 1
            fi

            if ! $REALTIME_MONITORING_ENABLED; then
                log_message "ERROR" "Real-time monitoring is disabled in configuration"
                exit 1
            fi

            if $daemon_mode; then
                log_message "INFO" "Starting in daemon mode..."
                nohup "$0" start > "$MONITOR_LOG_FILE" 2>&1 &
                echo "Monitoring started in background with PID: $!"
            else
                start_monitoring

                # Keep running until interrupted
                while true; do
                    if [[ -f "$EMERGENCY_STOP_FILE" ]]; then
                        log_message "INFO" "Emergency stop file detected"
                        break
                    fi
                    sleep 10
                done
            fi
            ;;
        stop)
            if [[ -f "$MONITOR_STATUS_FILE" ]]; then
                local pid
                pid=$(jq -r '.pid' "$MONITOR_STATUS_FILE" 2>/dev/null || echo "0")
                if kill -TERM "$pid" 2>/dev/null; then
                    log_message "INFO" "Sent stop signal to monitoring process (PID: $pid)"
                else
                    log_message "WARN" "Could not stop monitoring process"
                fi
            else
                log_message "WARN" "No monitoring process found"
            fi
            ;;
        status)
            show_status
            ;;
        restart)
            "$0" stop
            sleep 2
            "$0" start $([[ $daemon_mode == true ]] && echo "--daemon")
            ;;
        test)
            log_message "INFO" "🧪 Testing monitoring configuration..."

            # Test inotify availability
            if ! command -v inotifywait >/dev/null 2>&1; then
                log_message "ERROR" "inotifywait not found. Install inotify-tools package."
                exit 1
            fi

            # Test configuration
            if [[ ! -f "$MONITOR_CONFIG" ]]; then
                log_message "ERROR" "Monitoring configuration not found: $MONITOR_CONFIG"
                exit 1
            fi

            # Test watch paths
            for path in "${MONITOR_PATHS[@]}"; do
                local full_path="$HOME/$path"
                if [[ -e "$full_path" ]]; then
                    log_message "INFO" "✅ Path exists: $full_path"
                else
                    log_message "WARN" "⚠️ Path not found: $full_path"
                fi
            done

            log_message "INFO" "✅ Configuration test completed"
            ;;
    esac
}

# Run main function
main "$@"