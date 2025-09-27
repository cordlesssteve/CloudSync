#!/bin/bash
# CloudSync Checksum Verification System
# Uses rclone check to verify file integrity with MD5/SHA1 checksums

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
LOG_FILE="$HOME/.cloudsync/checksum-verify.log"
REPORT_FILE="$HOME/.cloudsync/checksum-report-$(date '+%Y%m%d-%H%M%S').json"

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
    echo "  --local <path>      Local path to verify (default: HOME)"
    echo "  --remote <remote>   Remote to verify against (default: $DEFAULT_REMOTE)"
    echo "  --path <path>       Remote path (default: $SYNC_BASE_PATH)"
    echo "  --size-only         Check only file sizes, not checksums (faster)"
    echo "  --download          Download missing files from remote"
    echo "  --one-way           Check local against remote only"
    echo "  --missing-on-src    Show files missing on source (local)"
    echo "  --missing-on-dst    Show files missing on destination (remote)"
    echo "  --match             Show matching files"
    echo "  --differ            Show files that differ"
    echo "  --error             Show files with errors"
    echo "  --combined          Show combined report of all categories"
    echo "  --report <file>     Save detailed JSON report to file"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --local ~/projects --combined"
    echo "  $0 --size-only --missing-on-src"
    echo "  $0 --local ~/.ssh --remote onedrive --path DevEnvironment/ssh"
}

# Default options
LOCAL_PATH="$HOME"
REMOTE="$DEFAULT_REMOTE"
REMOTE_PATH="$SYNC_BASE_PATH"
SIZE_ONLY=false
DOWNLOAD=false
ONE_WAY=false
SHOW_MISSING_SRC=false
SHOW_MISSING_DST=false
SHOW_MATCH=false
SHOW_DIFFER=false
SHOW_ERROR=false
SHOW_COMBINED=false
CUSTOM_REPORT=""

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
        --size-only)
            SIZE_ONLY=true
            shift
            ;;
        --download)
            DOWNLOAD=true
            shift
            ;;
        --one-way)
            ONE_WAY=true
            shift
            ;;
        --missing-on-src)
            SHOW_MISSING_SRC=true
            shift
            ;;
        --missing-on-dst)
            SHOW_MISSING_DST=true
            shift
            ;;
        --match)
            SHOW_MATCH=true
            shift
            ;;
        --differ)
            SHOW_DIFFER=true
            shift
            ;;
        --error)
            SHOW_ERROR=true
            shift
            ;;
        --combined)
            SHOW_COMBINED=true
            shift
            ;;
        --report)
            CUSTOM_REPORT="$2"
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

# Set report file if custom specified
if [[ -n "$CUSTOM_REPORT" ]]; then
    REPORT_FILE="$CUSTOM_REPORT"
fi

# Validate paths and connectivity
validate_setup() {
    log_message "${BLUE}🔍 Validating setup...${NC}"

    # Check local path exists
    if [[ ! -d "$LOCAL_PATH" ]]; then
        log_message "${RED}❌ Local path does not exist: $LOCAL_PATH${NC}"
        exit 1
    fi

    # Check remote connectivity
    if ! rclone lsd "$REMOTE:" >/dev/null 2>&1; then
        log_message "${RED}❌ Cannot connect to remote: $REMOTE${NC}"
        exit 1
    fi

    # Check remote path exists
    if ! rclone lsd "$REMOTE:$REMOTE_PATH" >/dev/null 2>&1; then
        log_message "${YELLOW}⚠️ Remote path may not exist: $REMOTE:$REMOTE_PATH${NC}"
    fi

    log_message "${GREEN}✅ Setup validation: OK${NC}"
}

# Perform checksum verification
perform_verification() {
    local local_target="$LOCAL_PATH"
    local remote_target="$REMOTE:$REMOTE_PATH"
    local check_cmd="rclone check"

    # Build command options
    if $SIZE_ONLY; then
        check_cmd="$check_cmd --size-only"
        log_message "${BLUE}📏 Using size-only verification (faster)${NC}"
    else
        log_message "${BLUE}🔢 Using full checksum verification${NC}"
    fi

    if $ONE_WAY; then
        check_cmd="$check_cmd --one-way"
        log_message "${BLUE}➡️ One-way check: local → remote${NC}"
    fi

    if $DOWNLOAD; then
        check_cmd="$check_cmd --download"
        log_message "${BLUE}⬇️ Download mode: will fetch missing files${NC}"
    fi

    # Determine what to show based on flags
    local show_flags=""
    if $SHOW_MISSING_SRC; then show_flags="$show_flags --missing-on-src"; fi
    if $SHOW_MISSING_DST; then show_flags="$show_flags --missing-on-dst"; fi
    if $SHOW_MATCH; then show_flags="$show_flags --match"; fi
    if $SHOW_DIFFER; then show_flags="$show_flags --differ"; fi
    if $SHOW_ERROR; then show_flags="$show_flags --error"; fi
    if $SHOW_COMBINED; then show_flags="$show_flags --combined"; fi

    # If no specific flags, show combined by default
    if [[ -z "$show_flags" ]]; then
        show_flags="--combined"
        SHOW_COMBINED=true
    fi

    check_cmd="$check_cmd $show_flags"

    log_message "${BLUE}🚀 Starting checksum verification${NC}"
    log_message "${BLUE}Local: $local_target${NC}"
    log_message "${BLUE}Remote: $remote_target${NC}"
    log_message "${BLUE}Command: $check_cmd${NC}"

    # Execute verification
    local start_time=$(date +%s)
    local check_output
    local exit_code=0

    if check_output=$($check_cmd "$local_target" "$remote_target" 2>&1); then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        log_message "${GREEN}✅ Verification completed successfully${NC}"
        log_message "${GREEN}⏱️ Duration: ${duration} seconds${NC}"

        # Process and display results
        process_results "$check_output"

    else
        exit_code=$?
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        log_message "${YELLOW}⚠️ Verification completed with differences found${NC}"
        log_message "${YELLOW}⏱️ Duration: ${duration} seconds${NC}"
        log_message "${YELLOW}Exit code: $exit_code${NC}"

        # Process results even on non-zero exit (differences found)
        process_results "$check_output"
    fi

    # Log detailed output
    echo "$check_output" >> "$LOG_FILE"

    # Update last verification timestamp
    echo "$TIMESTAMP" > "$HOME/.cloudsync/last-checksum-verify"

    return $exit_code
}

# Process and categorize results
process_results() {
    local output="$1"
    local total_files=0
    local matched_files=0
    local differ_files=0
    local missing_src=0
    local missing_dst=0
    local error_files=0

    # Parse output for statistics
    matched_files=0
    differ_files=0
    missing_src=0
    missing_dst=0
    error_files=0

    if echo "$output" | grep -q "files matched"; then
        matched_files=$(echo "$output" | grep "files matched" | awk '{print $1}')
    fi

    if echo "$output" | grep -q "differences found"; then
        differ_files=$(echo "$output" | grep "differences found" | awk '{print $1}')
    fi

    if echo "$output" | grep -q "missing on source"; then
        missing_src=$(echo "$output" | grep "missing on source" | awk '{print $1}')
    fi

    if echo "$output" | grep -q "missing on destination"; then
        missing_dst=$(echo "$output" | grep "missing on destination" | awk '{print $1}')
    fi

    if echo "$output" | grep -q "errors"; then
        error_files=$(echo "$output" | grep "errors" | awk '{print $1}')
    fi

    total_files=$((matched_files + differ_files + missing_src + missing_dst + error_files))

    # Display summary
    log_message "${BLUE}📊 Verification Summary:${NC}"
    log_message "${GREEN}✅ Matched files: $matched_files${NC}"

    if [[ $differ_files -gt 0 ]]; then
        log_message "${YELLOW}⚠️ Different files: $differ_files${NC}"
    fi

    if [[ $missing_src -gt 0 ]]; then
        log_message "${RED}❌ Missing on source: $missing_src${NC}"
    fi

    if [[ $missing_dst -gt 0 ]]; then
        log_message "${RED}❌ Missing on destination: $missing_dst${NC}"
    fi

    if [[ $error_files -gt 0 ]]; then
        log_message "${RED}🚨 Files with errors: $error_files${NC}"
    fi

    log_message "${BLUE}📁 Total files processed: $total_files${NC}"

    # Generate JSON report
    generate_json_report "$matched_files" "$differ_files" "$missing_src" "$missing_dst" "$error_files" "$total_files" "$output"

    # Calculate integrity score
    if [[ $total_files -gt 0 ]]; then
        local integrity_score=$((matched_files * 100 / total_files))
        log_message "${BLUE}🎯 Integrity Score: ${integrity_score}%${NC}"
    fi
}

# Generate detailed JSON report
generate_json_report() {
    local matched=$1
    local differ=$2
    local missing_src=$3
    local missing_dst=$4
    local errors=$5
    local total=$6
    local raw_output="$7"

    cat > "$REPORT_FILE" << EOF
{
  "timestamp": "$TIMESTAMP",
  "verification": {
    "local_path": "$LOCAL_PATH",
    "remote": "$REMOTE",
    "remote_path": "$REMOTE_PATH",
    "size_only": $SIZE_ONLY,
    "one_way": $ONE_WAY
  },
  "results": {
    "matched_files": $matched,
    "different_files": $differ,
    "missing_on_source": $missing_src,
    "missing_on_destination": $missing_dst,
    "error_files": $errors,
    "total_files": $total,
    "integrity_score": $(( total > 0 ? matched * 100 / total : 100 ))
  },
  "raw_output": $(echo "$raw_output" | jq -R -s .)
}
EOF

    log_message "${GREEN}📄 Detailed report saved: $REPORT_FILE${NC}"
}

# Main execution
main() {
    log_message "${BLUE}🔐 CloudSync Checksum Verification${NC}"
    log_message "Timestamp: $TIMESTAMP"
    log_message "Local: $LOCAL_PATH"
    log_message "Remote: $REMOTE:$REMOTE_PATH"
    echo "=" | head -c 50 && echo

    validate_setup

    local exit_code=0
    perform_verification || exit_code=$?

    echo
    if [[ $exit_code -eq 0 ]]; then
        log_message "${GREEN}🎉 All files verified successfully${NC}"
    else
        log_message "${YELLOW}⚠️ Verification completed with differences found${NC}"
        log_message "${BLUE}💡 Use sync commands to resolve differences${NC}"
    fi

    log_message "📝 Full log: $LOG_FILE"
    log_message "📄 Report: $REPORT_FILE"

    exit $exit_code
}

# Run main function
main "$@"