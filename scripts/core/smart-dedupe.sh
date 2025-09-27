#!/bin/bash
# CloudSync Smart Deduplication Script
# Uses rclone dedupe to eliminate duplicate files with hash-based detection

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
LOG_FILE="$HOME/.cloudsync/dedupe.log"

# Create log directory
mkdir -p "$HOME/.cloudsync"

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
    echo "  --dry-run           Show what would be deduplicated without making changes"
    echo "  --by-hash           Use hash-based deduplication (recommended)"
    echo "  --by-name           Use name-based deduplication (for duplicate names)"
    echo "  --remote <remote>   Specify remote to dedupe (default: $DEFAULT_REMOTE)"
    echo "  --path <path>       Specify path within remote (default: $SYNC_BASE_PATH)"
    echo "  --interactive       Interactive mode for manual selection"
    echo "  --stats             Show deduplication statistics"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --dry-run --by-hash"
    echo "  $0 --by-hash --remote onedrive --path DevEnvironment"
    echo "  $0 --interactive --by-name"
}

# Default options
DRY_RUN=false
BY_HASH=true
BY_NAME=false
INTERACTIVE=false
SHOW_STATS=false
REMOTE="$DEFAULT_REMOTE"
REMOTE_PATH="$SYNC_BASE_PATH"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --by-hash)
            BY_HASH=true
            BY_NAME=false
            shift
            ;;
        --by-name)
            BY_NAME=true
            BY_HASH=false
            shift
            ;;
        --remote)
            REMOTE="$2"
            shift 2
            ;;
        --path)
            REMOTE_PATH="$2"
            shift 2
            ;;
        --interactive)
            INTERACTIVE=true
            shift
            ;;
        --stats)
            SHOW_STATS=true
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

# Validate remote connectivity
check_remote_connectivity() {
    log_message "${BLUE}🔍 Checking remote connectivity...${NC}"

    if ! rclone lsd "$REMOTE:" >/dev/null 2>&1; then
        log_message "${RED}❌ Cannot connect to remote: $REMOTE${NC}"
        exit 1
    fi

    log_message "${GREEN}✅ Remote connectivity: OK${NC}"
}

# Get deduplication statistics
get_dedupe_stats() {
    local target="$REMOTE:$REMOTE_PATH"

    log_message "${BLUE}📊 Analyzing files for deduplication...${NC}"

    # Get file count and total size before deduplication
    local file_info
    file_info=$(rclone size "$target" 2>/dev/null || echo "0 0")
    local total_files=$(echo "$file_info" | awk '{print $4}' | tr -d '()')
    local total_size=$(echo "$file_info" | awk '{print $2}')

    log_message "${BLUE}📁 Total files: ${total_files:-0}${NC}"
    log_message "${BLUE}💾 Total size: ${total_size:-0} bytes${NC}"

    # Check for potential duplicates (this is an approximation)
    if command -v rclone >/dev/null 2>&1; then
        local duplicate_check
        if $BY_HASH; then
            duplicate_check=$(rclone dedupe --dry-run --by-hash "$target" 2>&1 | grep -c "duplicate" || echo "0")
        else
            duplicate_check=$(rclone dedupe --dry-run "$target" 2>&1 | grep -c "duplicate" || echo "0")
        fi

        log_message "${YELLOW}🔍 Potential duplicates found: $duplicate_check${NC}"
    fi
}

# Perform deduplication
perform_dedupe() {
    local target="$REMOTE:$REMOTE_PATH"
    local dedupe_cmd="rclone dedupe"

    # Build command options
    if $DRY_RUN; then
        dedupe_cmd="$dedupe_cmd --dry-run"
        log_message "${YELLOW}🧪 DRY RUN MODE - No files will be modified${NC}"
    fi

    if $BY_HASH; then
        dedupe_cmd="$dedupe_cmd --by-hash"
        log_message "${BLUE}🔢 Using hash-based deduplication${NC}"
    else
        log_message "${BLUE}📝 Using name-based deduplication${NC}"
    fi

    if $INTERACTIVE; then
        dedupe_cmd="$dedupe_cmd --interactive"
        log_message "${BLUE}👤 Interactive mode enabled${NC}"
    else
        # For non-interactive, we need to specify what to do with duplicates
        # Default to keeping the first (oldest) file
        dedupe_cmd="$dedupe_cmd first"
    fi

    # Add progress reporting
    if [[ "$ENABLE_PROGRESS" == "true" ]]; then
        dedupe_cmd="$dedupe_cmd --progress"
    fi

    log_message "${BLUE}🚀 Starting deduplication: $target${NC}"
    log_message "${BLUE}Command: $dedupe_cmd \"$target\"${NC}"

    # Execute deduplication
    local start_time=$(date +%s)
    local dedupe_output

    if dedupe_output=$($dedupe_cmd "$target" 2>&1); then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        log_message "${GREEN}✅ Deduplication completed successfully${NC}"
        log_message "${GREEN}⏱️ Duration: ${duration} seconds${NC}"

        # Parse and display results
        local files_removed=$(echo "$dedupe_output" | grep -c "Deleted" || echo "0")
        log_message "${GREEN}🗑️ Files removed: $files_removed${NC}"

        # Log detailed output
        echo "$dedupe_output" >> "$LOG_FILE"

        # Update last dedupe timestamp
        echo "$TIMESTAMP" > "$HOME/.cloudsync/last-dedupe"

    else
        log_message "${RED}❌ Deduplication failed${NC}"
        log_message "${RED}Error output: $dedupe_output${NC}"
        exit 1
    fi
}

# Show post-deduplication statistics
show_post_stats() {
    if $SHOW_STATS && ! $DRY_RUN; then
        log_message "${BLUE}📊 Post-deduplication statistics:${NC}"
        get_dedupe_stats
    fi
}

# Main execution
main() {
    log_message "${BLUE}🔧 CloudSync Smart Deduplication${NC}"
    log_message "Timestamp: $TIMESTAMP"
    log_message "Target: $REMOTE:$REMOTE_PATH"
    echo "=" | head -c 50 && echo

    check_remote_connectivity

    if $SHOW_STATS; then
        get_dedupe_stats
        echo
    fi

    perform_dedupe

    show_post_stats

    log_message "${GREEN}🎉 Smart deduplication completed${NC}"
    log_message "📝 Full log: $LOG_FILE"
}

# Run main function
main "$@"