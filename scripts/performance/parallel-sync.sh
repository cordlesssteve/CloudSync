#!/bin/bash
# CloudSync Parallel Operations Engine
# Implements parallel file transfers and operations for improved performance

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
CYAN='\033[0;36m'
NC='\033[0m'

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE="$HOME/.cloudsync/parallel-sync.log"
TEMP_DIR="/tmp/cloudsync-parallel-$$"

# Performance tuning defaults
MAX_PARALLEL_JOBS=4
CHUNK_SIZE=50
TRANSFER_TIMEOUT=3600
BANDWIDTH_LIMIT=""
CONNECTIONS_PER_TRANSFER=4

# Create directories
mkdir -p "$HOME/.cloudsync"
mkdir -p "$TEMP_DIR"

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
    # Kill any remaining background jobs
    jobs -p | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT

# Function to log messages
log_message() {
    echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
    echo -e "$1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] OPERATION"
    echo ""
    echo "Operations:"
    echo "  batch-sync          Sync multiple directories in parallel"
    echo "  multi-remote        Sync to multiple remotes simultaneously"
    echo "  parallel-verify     Verify checksums using parallel workers"
    echo "  bulk-dedupe         Deduplicate multiple paths concurrently"
    echo ""
    echo "Options:"
    echo "  --jobs <num>        Number of parallel jobs (default: $MAX_PARALLEL_JOBS)"
    echo "  --chunk-size <num>  Files per chunk for parallel processing (default: $CHUNK_SIZE)"
    echo "  --timeout <sec>     Transfer timeout per job (default: $TRANSFER_TIMEOUT)"
    echo "  --bandwidth <limit> Bandwidth limit per transfer (e.g., 10M, 1G)"
    echo "  --connections <num> Connections per transfer (default: $CONNECTIONS_PER_TRANSFER)"
    echo "  --paths <file>      File containing paths to sync (one per line)"
    echo "  --remotes <list>    Comma-separated list of remotes"
    echo "  --dry-run           Show what would be done without executing"
    echo "  --verbose           Enable verbose output"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 batch-sync --jobs 8 --paths /tmp/sync-paths.txt"
    echo "  $0 multi-remote --remotes onedrive,gdrive,dropbox"
    echo "  $0 parallel-verify --chunk-size 100 --jobs 6"
    echo "  $0 bulk-dedupe --bandwidth 50M --connections 2"
}

# Parse command line arguments
OPERATION=""
DRY_RUN=false
VERBOSE=false
PATHS_FILE=""
REMOTES_LIST=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --jobs)
            MAX_PARALLEL_JOBS="$2"
            shift 2
            ;;
        --chunk-size)
            CHUNK_SIZE="$2"
            shift 2
            ;;
        --timeout)
            TRANSFER_TIMEOUT="$2"
            shift 2
            ;;
        --bandwidth)
            BANDWIDTH_LIMIT="$2"
            shift 2
            ;;
        --connections)
            CONNECTIONS_PER_TRANSFER="$2"
            shift 2
            ;;
        --paths)
            PATHS_FILE="$2"
            shift 2
            ;;
        --remotes)
            REMOTES_LIST="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        batch-sync|multi-remote|parallel-verify|bulk-dedupe)
            OPERATION="$1"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

if [[ -z "$OPERATION" ]]; then
    echo "Error: No operation specified"
    show_usage
    exit 1
fi

# Function to build rclone command with performance optimizations
build_rclone_cmd() {
    local operation="$1"
    local cmd="rclone $operation"

    # Add performance flags
    cmd="$cmd --transfers=$CONNECTIONS_PER_TRANSFER"
    cmd="$cmd --checkers=8"
    cmd="$cmd --retries=3"
    cmd="$cmd --low-level-retries=10"
    cmd="$cmd --stats=30s"

    # Add bandwidth limit if specified
    if [[ -n "$BANDWIDTH_LIMIT" ]]; then
        cmd="$cmd --bwlimit=$BANDWIDTH_LIMIT"
    fi

    # Add progress if not in batch mode
    if [[ "$VERBOSE" == "true" ]]; then
        cmd="$cmd --progress"
        cmd="$cmd -v"
    fi

    # Add dry run if specified
    if [[ "$DRY_RUN" == "true" ]]; then
        cmd="$cmd --dry-run"
    fi

    echo "$cmd"
}

# Function to execute command with timeout and logging
execute_with_timeout() {
    local cmd="$1"
    local timeout="$2"
    local job_id="$3"
    local log_prefix="[$job_id]"

    log_message "${BLUE}$log_prefix Starting: $cmd${NC}"

    if timeout "$timeout" bash -c "$cmd" >> "$LOG_FILE" 2>&1; then
        log_message "${GREEN}$log_prefix Completed successfully${NC}"
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_message "${RED}$log_prefix Timed out after ${timeout}s${NC}"
        else
            log_message "${RED}$log_prefix Failed with exit code $exit_code${NC}"
        fi
        return $exit_code
    fi
}

# Function to wait for jobs with progress tracking
wait_for_jobs() {
    local max_jobs="$1"
    local current_jobs

    while true; do
        current_jobs=$(jobs -r | wc -l)
        if [[ $current_jobs -lt $max_jobs ]]; then
            break
        fi
        sleep 1
        if [[ "$VERBOSE" == "true" ]]; then
            echo -ne "\rActive jobs: $current_jobs/$max_jobs"
        fi
    done
}

# Operation: Batch Sync - Sync multiple directories in parallel
batch_sync() {
    log_message "${CYAN}🚀 Starting batch sync with $MAX_PARALLEL_JOBS parallel jobs${NC}"

    local paths_to_sync=()

    if [[ -n "$PATHS_FILE" && -f "$PATHS_FILE" ]]; then
        # Read paths from file
        while IFS= read -r path; do
            if [[ -n "$path" && -d "$path" ]]; then
                paths_to_sync+=("$path")
            fi
        done < "$PATHS_FILE"
    else
        # Use default critical paths
        for path in "${CRITICAL_PATHS[@]}"; do
            local full_path="$HOME/$path"
            if [[ -d "$full_path" ]]; then
                paths_to_sync+=("$full_path")
            fi
        done
    fi

    if [[ ${#paths_to_sync[@]} -eq 0 ]]; then
        log_message "${YELLOW}⚠️ No valid paths found to sync${NC}"
        return 1
    fi

    log_message "${BLUE}📂 Found ${#paths_to_sync[@]} directories to sync${NC}"

    local job_counter=0
    for path in "${paths_to_sync[@]}"; do
        wait_for_jobs "$MAX_PARALLEL_JOBS"

        ((job_counter++))
        local job_id="BATCH-$job_counter"
        local rel_path="${path#$HOME/}"
        local remote_path="$DEFAULT_REMOTE:$SYNC_BASE_PATH/$rel_path"

        local sync_cmd
        sync_cmd=$(build_rclone_cmd "sync")
        sync_cmd="$sync_cmd \"$path\" \"$remote_path\""

        execute_with_timeout "$sync_cmd" "$TRANSFER_TIMEOUT" "$job_id" &
    done

    # Wait for all jobs to complete
    log_message "${BLUE}⏳ Waiting for all sync jobs to complete...${NC}"
    wait

    log_message "${GREEN}✅ Batch sync completed${NC}"
}

# Operation: Multi-Remote Sync - Sync to multiple remotes simultaneously
multi_remote() {
    log_message "${CYAN}🚀 Starting multi-remote sync${NC}"

    local remotes=()
    if [[ -n "$REMOTES_LIST" ]]; then
        IFS=',' read -ra remotes <<< "$REMOTES_LIST"
    else
        log_message "${RED}❌ No remotes specified. Use --remotes flag${NC}"
        return 1
    fi

    log_message "${BLUE}☁️ Syncing to ${#remotes[@]} remotes: ${remotes[*]}${NC}"

    local sync_path="$HOME"
    if [[ -n "$PATHS_FILE" && -f "$PATHS_FILE" ]]; then
        sync_path=$(head -n1 "$PATHS_FILE")
    fi

    local job_counter=0
    for remote in "${remotes[@]}"; do
        wait_for_jobs "$MAX_PARALLEL_JOBS"

        ((job_counter++))
        local job_id="REMOTE-$job_counter"
        local remote_path="$remote:$SYNC_BASE_PATH"

        local sync_cmd
        sync_cmd=$(build_rclone_cmd "sync")
        sync_cmd="$sync_cmd \"$sync_path\" \"$remote_path\""

        execute_with_timeout "$sync_cmd" "$TRANSFER_TIMEOUT" "$job_id" &
    done

    log_message "${BLUE}⏳ Waiting for all remote syncs to complete...${NC}"
    wait

    log_message "${GREEN}✅ Multi-remote sync completed${NC}"
}

# Operation: Parallel Verify - Verify checksums using parallel workers
parallel_verify() {
    log_message "${CYAN}🚀 Starting parallel checksum verification${NC}"

    local verify_cmd
    verify_cmd=$(build_rclone_cmd "check")
    verify_cmd="$verify_cmd \"$HOME\" \"$DEFAULT_REMOTE:$SYNC_BASE_PATH\""

    # Add parallel-specific flags
    verify_cmd="$verify_cmd --one-way --missing-on-src --missing-on-dst"

    execute_with_timeout "$verify_cmd" "$TRANSFER_TIMEOUT" "VERIFY-MAIN" &

    log_message "${BLUE}⏳ Waiting for verification to complete...${NC}"
    wait

    log_message "${GREEN}✅ Parallel verification completed${NC}"
}

# Operation: Bulk Dedupe - Deduplicate multiple paths concurrently
bulk_dedupe() {
    log_message "${CYAN}🚀 Starting bulk deduplication${NC}"

    local paths_to_dedupe=()

    # Build list of remote paths to dedupe
    for path in "${CRITICAL_PATHS[@]}"; do
        paths_to_dedupe+=("$DEFAULT_REMOTE:$SYNC_BASE_PATH/$path")
    done

    # Add root path
    paths_to_dedupe+=("$DEFAULT_REMOTE:$SYNC_BASE_PATH")

    log_message "${BLUE}🗜️ Deduplicating ${#paths_to_dedupe[@]} remote paths${NC}"

    local job_counter=0
    for remote_path in "${paths_to_dedupe[@]}"; do
        wait_for_jobs "$MAX_PARALLEL_JOBS"

        ((job_counter++))
        local job_id="DEDUPE-$job_counter"

        local dedupe_cmd
        dedupe_cmd=$(build_rclone_cmd "dedupe")
        dedupe_cmd="$dedupe_cmd --by-hash \"$remote_path\""

        execute_with_timeout "$dedupe_cmd" "$TRANSFER_TIMEOUT" "$job_id" &
    done

    log_message "${BLUE}⏳ Waiting for all deduplication jobs to complete...${NC}"
    wait

    log_message "${GREEN}✅ Bulk deduplication completed${NC}"
}

# Performance monitoring and statistics
show_performance_stats() {
    local start_time="$1"
    local end_time="$2"
    local operation="$3"

    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    log_message "${CYAN}📊 Performance Statistics for $operation:${NC}"
    log_message "${BLUE}   Duration: ${minutes}m ${seconds}s${NC}"
    log_message "${BLUE}   Parallel jobs: $MAX_PARALLEL_JOBS${NC}"
    log_message "${BLUE}   Connections per transfer: $CONNECTIONS_PER_TRANSFER${NC}"
    if [[ -n "$BANDWIDTH_LIMIT" ]]; then
        log_message "${BLUE}   Bandwidth limit: $BANDWIDTH_LIMIT${NC}"
    fi

    # Save performance stats
    cat > "$HOME/.cloudsync/last-performance-stats.json" << EOF
{
  "timestamp": "$TIMESTAMP",
  "operation": "$operation",
  "duration_seconds": $duration,
  "parallel_jobs": $MAX_PARALLEL_JOBS,
  "connections_per_transfer": $CONNECTIONS_PER_TRANSFER,
  "bandwidth_limit": "${BANDWIDTH_LIMIT:-unlimited}",
  "dry_run": $DRY_RUN
}
EOF
}

# Main execution
main() {
    log_message "${BLUE}⚡ CloudSync Parallel Operations Engine${NC}"
    log_message "Operation: $OPERATION"
    log_message "Parallel jobs: $MAX_PARALLEL_JOBS"
    log_message "Timestamp: $TIMESTAMP"
    echo "=" | head -c 50 && echo

    local start_time=$(date +%s)

    case "$OPERATION" in
        batch-sync)
            batch_sync
            ;;
        multi-remote)
            multi_remote
            ;;
        parallel-verify)
            parallel_verify
            ;;
        bulk-dedupe)
            bulk_dedupe
            ;;
        *)
            echo "Unknown operation: $OPERATION"
            exit 1
            ;;
    esac

    local end_time=$(date +%s)
    show_performance_stats "$start_time" "$end_time" "$OPERATION"

    # Update last run timestamp
    echo "$TIMESTAMP" > "$HOME/.cloudsync/last-parallel-sync"

    log_message "📝 Full log: $LOG_FILE"
    log_message "📊 Performance stats: $HOME/.cloudsync/last-performance-stats.json"
}

# Run main function
main "$@"