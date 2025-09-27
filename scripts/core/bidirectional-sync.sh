#!/bin/bash
# CloudSync Bidirectional Sync Script
# Uses rclone bisync for two-way synchronization with conflict detection

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
LOG_FILE="$HOME/.cloudsync/bisync.log"
BISYNC_DIR="$HOME/.cloudsync/bisync"

# Create required directories
mkdir -p "$HOME/.cloudsync"
mkdir -p "$BISYNC_DIR"

# Function to log messages
log_message() {
    echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
    echo -e "$1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --local <path>      Local path to sync (default: HOME)"
    echo "  --remote <remote>   Remote to sync with (default: $DEFAULT_REMOTE)"
    echo "  --path <path>       Remote path (default: $SYNC_BASE_PATH)"
    echo "  --dry-run           Show what would be synchronized without making changes"
    echo "  --resync            Force resynchronization (rebuilds sync state)"
    echo "  --check-access      Check if both paths are accessible"
    echo "  --filters <file>    Use custom filter file"
    echo "  --no-slow-hash      Don't use slow hash (MD5/SHA1) for comparison"
    echo "  --compare <method>  Comparison method: modtime|size|checksum|size,modtime"
    echo "  --conflict <action> Conflict resolution: list|winner|newer|older|larger|smaller"
    echo "  --max-delete <num>  Maximum number of deletes allowed (default: 50)"
    echo "  --workdir <dir>     Working directory for bisync state (default: ~/.cloudsync/bisync)"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --dry-run --local ~/projects"
    echo "  $0 --resync --local ~/.ssh --path DevEnvironment/ssh"
    echo "  $0 --conflict newer --compare modtime"
    echo "  $0 --check-access"
}

# Default options
LOCAL_PATH="$HOME"
REMOTE="$DEFAULT_REMOTE"
REMOTE_PATH="$SYNC_BASE_PATH"
DRY_RUN=false
RESYNC=false
CHECK_ACCESS=false
CUSTOM_FILTERS=""
NO_SLOW_HASH=false
COMPARE_METHOD="modtime"
CONFLICT_ACTION="list"
MAX_DELETE=50
WORK_DIR="$BISYNC_DIR"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --local)
            LOCAL_PATH="$2"
            shift 2
            ;;
        --remote)
            REMOTE="$2"
            shift 2
            ;;
        --path)
            REMOTE_PATH="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --resync)
            RESYNC=true
            shift
            ;;
        --check-access)
            CHECK_ACCESS=true
            shift
            ;;
        --filters)
            CUSTOM_FILTERS="$2"
            shift 2
            ;;
        --no-slow-hash)
            NO_SLOW_HASH=true
            shift
            ;;
        --compare)
            COMPARE_METHOD="$2"
            shift 2
            ;;
        --conflict)
            CONFLICT_ACTION="$2"
            shift 2
            ;;
        --max-delete)
            MAX_DELETE="$2"
            shift 2
            ;;
        --workdir)
            WORK_DIR="$2"
            shift 2
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

# Ensure work directory exists
mkdir -p "$WORK_DIR"

# Check access to both local and remote paths
check_access() {
    log_message "${BLUE}🔍 Checking access to sync paths...${NC}"

    # Check local path
    if [[ ! -d "$LOCAL_PATH" ]]; then
        log_message "${RED}❌ Local path does not exist: $LOCAL_PATH${NC}"
        exit 1
    fi

    if [[ ! -r "$LOCAL_PATH" ]]; then
        log_message "${RED}❌ Local path is not readable: $LOCAL_PATH${NC}"
        exit 1
    fi

    if [[ ! -w "$LOCAL_PATH" ]]; then
        log_message "${YELLOW}⚠️ Local path is not writable: $LOCAL_PATH${NC}"
    fi

    log_message "${GREEN}✅ Local path access: OK${NC}"

    # Check remote connectivity
    if ! rclone lsd "$REMOTE:" >/dev/null 2>&1; then
        log_message "${RED}❌ Cannot connect to remote: $REMOTE${NC}"
        exit 1
    fi

    # Check/create remote path
    if ! rclone lsd "$REMOTE:$REMOTE_PATH" >/dev/null 2>&1; then
        log_message "${YELLOW}⚠️ Remote path doesn't exist, creating: $REMOTE:$REMOTE_PATH${NC}"
        rclone mkdir "$REMOTE:$REMOTE_PATH"
    fi

    log_message "${GREEN}✅ Remote path access: OK${NC}"
}

# Create filter file from configuration
create_filter_file() {
    local filter_file="$WORK_DIR/filters.txt"

    if [[ -n "$CUSTOM_FILTERS" && -f "$CUSTOM_FILTERS" ]]; then
        cp "$CUSTOM_FILTERS" "$filter_file"
        log_message "${BLUE}📋 Using custom filters: $CUSTOM_FILTERS${NC}"
    else
        # Generate filter file from configuration
        cat > "$filter_file" << EOF
# CloudSync Bidirectional Sync Filters
# Generated from cloudsync.conf

# Exclude patterns
EOF

        # Add exclude patterns from configuration
        for pattern in "${EXCLUDE_PATTERNS[@]}"; do
            echo "- $pattern" >> "$filter_file"
        done

        # Add critical paths as includes (if we're not syncing from HOME)
        if [[ "$LOCAL_PATH" != "$HOME" ]]; then
            echo "" >> "$filter_file"
            echo "# Include critical paths" >> "$filter_file"
            for path in "${CRITICAL_PATHS[@]}"; do
                echo "+ $path/**" >> "$filter_file"
            done

            for file in "${CRITICAL_FILES[@]}"; do
                echo "+ $file" >> "$filter_file"
            done
        fi

        log_message "${BLUE}📋 Generated filter file: $filter_file${NC}"
    fi

    echo "$filter_file"
}

# Perform bidirectional sync
perform_bisync() {
    local local_target="$LOCAL_PATH"
    local remote_target="$REMOTE:$REMOTE_PATH"
    local filter_file
    filter_file=$(create_filter_file)

    local bisync_cmd="rclone bisync"

    # Build command options
    if $DRY_RUN; then
        bisync_cmd="$bisync_cmd --dry-run"
        log_message "${YELLOW}🧪 DRY RUN MODE - No files will be modified${NC}"
    fi

    if $RESYNC; then
        bisync_cmd="$bisync_cmd --resync"
        log_message "${YELLOW}🔄 RESYNC MODE - Rebuilding sync state${NC}"
    fi

    # Add filter file
    bisync_cmd="$bisync_cmd --filters-file=\"$filter_file\""

    # Add comparison method
    case "$COMPARE_METHOD" in
        "modtime")
            # Default - no additional flags
            ;;
        "size")
            bisync_cmd="$bisync_cmd --size-only"
            ;;
        "checksum")
            bisync_cmd="$bisync_cmd --checksum"
            ;;
        "size,modtime")
            # Default behavior
            ;;
        *)
            log_message "${YELLOW}⚠️ Unknown compare method: $COMPARE_METHOD, using default${NC}"
            ;;
    esac

    if $NO_SLOW_HASH; then
        bisync_cmd="$bisync_cmd --no-slow-hash"
    fi

    # Add conflict resolution
    case "$CONFLICT_ACTION" in
        "list"|"winner"|"newer"|"older"|"larger"|"smaller")
            bisync_cmd="$bisync_cmd --conflict-resolve=$CONFLICT_ACTION"
            ;;
        *)
            log_message "${YELLOW}⚠️ Unknown conflict action: $CONFLICT_ACTION, using list${NC}"
            bisync_cmd="$bisync_cmd --conflict-resolve=list"
            ;;
    esac

    # Add safety limits
    bisync_cmd="$bisync_cmd --max-delete=$MAX_DELETE"

    # Add working directory
    bisync_cmd="$bisync_cmd --workdir=\"$WORK_DIR\""

    # Add progress if enabled
    if [[ "$ENABLE_PROGRESS" == "true" ]]; then
        bisync_cmd="$bisync_cmd --progress"
    fi

    # Add verbose logging
    bisync_cmd="$bisync_cmd -v"

    log_message "${BLUE}🚀 Starting bidirectional sync${NC}"
    log_message "${BLUE}Local: $local_target${NC}"
    log_message "${BLUE}Remote: $remote_target${NC}"
    log_message "${BLUE}Compare method: $COMPARE_METHOD${NC}"
    log_message "${BLUE}Conflict resolution: $CONFLICT_ACTION${NC}"

    # Execute bisync
    local start_time=$(date +%s)
    local bisync_output
    local exit_code=0

    log_message "${BLUE}Command: $bisync_cmd \"$local_target\" \"$remote_target\"${NC}"

    if bisync_output=$(eval $bisync_cmd \"$local_target\" \"$remote_target\" 2>&1); then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        log_message "${GREEN}✅ Bidirectional sync completed successfully${NC}"
        log_message "${GREEN}⏱️ Duration: ${duration} seconds${NC}"

        # Process results
        process_bisync_results "$bisync_output"

    else
        exit_code=$?
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        if [[ $exit_code -eq 2 ]]; then
            log_message "${YELLOW}⚠️ Sync completed with conflicts detected${NC}"
            log_message "${YELLOW}⏱️ Duration: ${duration} seconds${NC}"
            process_bisync_results "$bisync_output"
        else
            log_message "${RED}❌ Bidirectional sync failed${NC}"
            log_message "${RED}⏱️ Duration: ${duration} seconds${NC}"
            log_message "${RED}Exit code: $exit_code${NC}"
            echo "$bisync_output" >> "$LOG_FILE"
            return $exit_code
        fi
    fi

    # Log detailed output
    echo "$bisync_output" >> "$LOG_FILE"

    # Update last bisync timestamp
    echo "$TIMESTAMP" > "$HOME/.cloudsync/last-bisync"

    return $exit_code
}

# Process bisync results
process_bisync_results() {
    local output="$1"

    # Parse output for statistics
    local files_copied_to_remote=0
    local files_copied_to_local=0
    local files_deleted=0
    local conflicts_found=0

    if echo "$output" | grep -q "Copied.*to.*remote"; then
        files_copied_to_remote=$(echo "$output" | grep "Copied.*to.*remote" | wc -l)
    fi

    if echo "$output" | grep -q "Copied.*to.*local"; then
        files_copied_to_local=$(echo "$output" | grep "Copied.*to.*local" | wc -l)
    fi

    if echo "$output" | grep -q "Deleted"; then
        files_deleted=$(echo "$output" | grep "Deleted" | wc -l)
    fi

    if echo "$output" | grep -q -i "conflict"; then
        conflicts_found=$(echo "$output" | grep -i "conflict" | wc -l)
    fi

    # Display summary
    log_message "${BLUE}📊 Sync Summary:${NC}"
    log_message "${GREEN}⬆️ Files copied to remote: $files_copied_to_remote${NC}"
    log_message "${GREEN}⬇️ Files copied to local: $files_copied_to_local${NC}"

    if [[ $files_deleted -gt 0 ]]; then
        log_message "${YELLOW}🗑️ Files deleted: $files_deleted${NC}"
    fi

    if [[ $conflicts_found -gt 0 ]]; then
        log_message "${RED}⚔️ Conflicts detected: $conflicts_found${NC}"
        log_message "${BLUE}💡 Check conflict files and resolve manually${NC}"
    fi

    # Save sync statistics
    cat > "$HOME/.cloudsync/last-bisync-stats.json" << EOF
{
  "timestamp": "$TIMESTAMP",
  "files_copied_to_remote": $files_copied_to_remote,
  "files_copied_to_local": $files_copied_to_local,
  "files_deleted": $files_deleted,
  "conflicts_found": $conflicts_found,
  "local_path": "$LOCAL_PATH",
  "remote": "$REMOTE:$REMOTE_PATH"
}
EOF
}

# Main execution
main() {
    log_message "${BLUE}🔄 CloudSync Bidirectional Sync${NC}"
    log_message "Timestamp: $TIMESTAMP"
    log_message "Local: $LOCAL_PATH"
    log_message "Remote: $REMOTE:$REMOTE_PATH"
    echo "=" | head -c 50 && echo

    # Check access first
    check_access

    if $CHECK_ACCESS; then
        log_message "${GREEN}🎉 Access check completed successfully${NC}"
        exit 0
    fi

    # Perform sync
    local exit_code=0
    perform_bisync || exit_code=$?

    echo
    case $exit_code in
        0)
            log_message "${GREEN}🎉 Bidirectional sync completed successfully${NC}"
            ;;
        2)
            log_message "${YELLOW}⚠️ Sync completed with conflicts - manual resolution required${NC}"
            ;;
        *)
            log_message "${RED}❌ Sync failed with exit code: $exit_code${NC}"
            ;;
    esac

    log_message "📝 Full log: $LOG_FILE"
    log_message "📊 Stats: $HOME/.cloudsync/last-bisync-stats.json"

    exit $exit_code
}

# Run main function
main "$@"