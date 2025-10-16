#!/bin/bash
# CloudSync Test Logging Infrastructure
# Comprehensive logging for all test operations
# Provides human-readable, JSON, and artifact tracking

set -euo pipefail

# ============================================================================
# Logging Configuration
# ============================================================================

# Initialize test run - must be called at start of test script
init_test_logging() {
    local test_name="${1:-unknown-test}"

    # Generate unique run ID
    export TEST_RUN_ID=$(date +%Y-%m-%d-%H%M%S-$$)
    export TEST_NAME="$test_name"

    # Create log directories
    export TEST_LOG_BASE_DIR="${HOME}/.cloudsync-test"
    export TEST_LOG_DIR="${TEST_LOG_BASE_DIR}/logs"
    export TEST_ARTIFACT_DIR="${TEST_LOG_DIR}/test-run-${TEST_RUN_ID}-artifacts"
    export TEST_EXPORT_DIR="${TEST_LOG_BASE_DIR}/exports"

    # Log files
    export TEST_LOG_FILE="${TEST_LOG_DIR}/test-run-${TEST_RUN_ID}.log"
    export TEST_JSON_LOG="${TEST_LOG_DIR}/test-run-${TEST_RUN_ID}.jsonl"
    export RCLONE_LOG="${TEST_LOG_DIR}/test-run-${TEST_RUN_ID}-rclone.log"
    export GIT_LOG="${TEST_LOG_DIR}/test-run-${TEST_RUN_ID}-git.log"
    export SUMMARY_JSON="${TEST_LOG_DIR}/test-summary-${TEST_RUN_ID}.json"

    # Create all directories
    mkdir -p "$TEST_LOG_DIR" "$TEST_ARTIFACT_DIR" "$TEST_EXPORT_DIR"

    # Initialize log files
    touch "$TEST_LOG_FILE" "$TEST_JSON_LOG" "$RCLONE_LOG" "$GIT_LOG"

    # Initialize counters
    export TEST_STEPS_TOTAL=0
    export TEST_STEPS_SUCCESS=0
    export TEST_STEPS_FAILED=0
    export TEST_METRICS=()

    # Print initialization header
    {
        echo "================================================================================"
        echo "CloudSync Test Suite: $TEST_NAME"
        echo "Test Run ID: $TEST_RUN_ID"
        echo "Started: $(date -Iseconds)"
        echo "User: $(whoami)"
        echo "Host: $(hostname)"
        echo "================================================================================"
        echo ""
    } | tee -a "$TEST_LOG_FILE"
}

# ============================================================================
# Core Logging Functions
# ============================================================================

# Log a single event with structured output
log_event() {
    local level="$1"      # INFO, SUCCESS, WARN, ERROR, DEBUG
    local stage="$2"      # SETUP, BUNDLE_CREATE, UPLOAD, DOWNLOAD, RESTORE, VERIFY, CLEANUP
    local message="$3"
    local timestamp
    timestamp=$(date -Iseconds)

    # Validate inputs
    if [[ -z "$level" || -z "$stage" || -z "$message" ]]; then
        echo "ERROR: log_event requires level, stage, and message" >&2
        return 1
    fi

    # Format for human-readable log
    local formatted_log="[$timestamp] [$level] [$stage] $message"

    # Append to human-readable log
    echo "$formatted_log" >> "$TEST_LOG_FILE"

    # Also output to console (with colors if not piped)
    if [[ -t 1 ]]; then
        case "$level" in
            SUCCESS) echo -e "\033[32m$formatted_log\033[0m" ;;
            ERROR)   echo -e "\033[31m$formatted_log\033[0m" ;;
            WARN)    echo -e "\033[33m$formatted_log\033[0m" ;;
            DEBUG)   echo -e "\033[36m$formatted_log\033[0m" ;;
            *)       echo "$formatted_log" ;;
        esac
    else
        echo "$formatted_log"
    fi

    # Append to JSON log
    jq -n \
        --arg timestamp "$timestamp" \
        --arg level "$level" \
        --arg stage "$stage" \
        --arg message "$message" \
        '{timestamp: $timestamp, level: $level, stage: $stage, message: $message}' >> "$TEST_JSON_LOG"

    return 0
}

# Log a metric (timing, size, checksum, count)
log_metric() {
    local metric_name="$1"
    local value="$2"
    local unit="${3:-}"
    local timestamp
    timestamp=$(date -Iseconds)

    # Format: METRIC_NAME=value unit
    local formatted="[$timestamp] [METRIC] $metric_name=$value $unit"
    echo "$formatted" >> "$TEST_LOG_FILE"

    # JSON format
    jq -n \
        --arg timestamp "$timestamp" \
        --arg metric "$metric_name" \
        --arg value "$value" \
        --arg unit "$unit" \
        '{timestamp: $timestamp, type: "metric", metric: $metric, value: $value, unit: $unit}' >> "$TEST_JSON_LOG"

    # Track for summary
    TEST_METRICS+=("$metric_name=$value $unit")
}

# Log file operation with checksums and sizes
log_file_operation() {
    local operation="$1"    # create, upload, download, restore, delete
    local filepath="$2"
    local size="${3:-0}"
    local checksum="${4:-}"
    local timestamp
    timestamp=$(date -Iseconds)

    local file_info="$filepath"
    [[ -n "$size" ]] && file_info="$file_info (${size} bytes)"
    [[ -n "$checksum" ]] && file_info="$file_info [SHA256: ${checksum:0:16}...]"

    local formatted="[$timestamp] [FILE] [$operation] $file_info"
    echo "$formatted" >> "$TEST_LOG_FILE"

    # JSON format
    jq -n \
        --arg timestamp "$timestamp" \
        --arg operation "$operation" \
        --arg filepath "$filepath" \
        --arg size "$size" \
        --arg checksum "$checksum" \
        '{timestamp: $timestamp, type: "file_operation", operation: $operation, filepath: $filepath, size_bytes: ($size | tonumber), checksum: $checksum}' >> "$TEST_JSON_LOG"
}

# Log step completion with timing and status
log_step_complete() {
    local step_name="$1"
    local status="$2"       # SUCCESS, FAILED, PARTIAL
    local start_time="$3"
    local end_time
    end_time=$(date +%s.%N)
    local duration
    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
    local timestamp
    timestamp=$(date -Iseconds)

    ((TEST_STEPS_TOTAL++))
    case "$status" in
        SUCCESS) ((TEST_STEPS_SUCCESS++)) ;;
        FAILED)  ((TEST_STEPS_FAILED++)) ;;
    esac

    local formatted="[$timestamp] [STEP] [$status] $step_name completed (${duration}s)"
    echo "$formatted" >> "$TEST_LOG_FILE"

    # JSON format
    jq -n \
        --arg timestamp "$timestamp" \
        --arg step "$step_name" \
        --arg status "$status" \
        --arg duration "$duration" \
        '{timestamp: $timestamp, type: "step_complete", step: $step, status: $status, duration_seconds: ($duration | tonumber)}' >> "$TEST_JSON_LOG"
}

# ============================================================================
# File Verification Logging
# ============================================================================

# Calculate SHA256 checksum with logging
get_file_checksum() {
    local filepath="$1"

    if [[ ! -f "$filepath" ]]; then
        log_event "ERROR" "FILE_CHECK" "File not found: $filepath"
        return 1
    fi

    sha256sum "$filepath" | awk '{print $1}'
}

# Log checksum comparison
log_checksum_comparison() {
    local label="$1"
    local original_checksum="$2"
    local new_checksum="$3"

    if [[ "$original_checksum" == "$new_checksum" ]]; then
        log_event "SUCCESS" "VERIFY" "Checksum match [$label]: $original_checksum"
        return 0
    else
        log_event "ERROR" "VERIFY" "Checksum mismatch [$label]: $original_checksum != $new_checksum"
        return 1
    fi
}

# Log directory structure to artifact file
log_directory_structure() {
    local directory="$1"
    local output_file="$2"
    local label="${3:-Directory}"

    if [[ ! -d "$directory" ]]; then
        log_event "WARN" "ARTIFACT" "$label not found: $directory"
        return 1
    fi

    find "$directory" -type f ! -path '*/.git/*' ! -path '*/.gitannex/*' | sort > "$output_file"
    local file_count
    file_count=$(wc -l < "$output_file")

    log_event "INFO" "ARTIFACT" "$label structure saved ($file_count files): $output_file"
    log_metric "${label}_FILES" "$file_count"

    return 0
}

# ============================================================================
# Command Execution Logging
# ============================================================================

# Execute command with full logging
run_logged_command() {
    local command_name="$1"
    local command="$2"
    local output_file="${3:-}"

    log_event "INFO" "EXEC" "Running: $command_name"

    local start_time
    start_time=$(date +%s.%N)
    local exit_code=0

    if [[ -n "$output_file" ]]; then
        if eval "$command" >> "$output_file" 2>&1; then
            exit_code=0
        else
            exit_code=$?
        fi

        # Count output lines
        local line_count
        line_count=$(wc -l < "$output_file" 2>/dev/null || echo "0")
        log_event "INFO" "EXEC" "Command output ($line_count lines): $output_file"
    else
        if eval "$command" >> "$TEST_LOG_FILE" 2>&1; then
            exit_code=0
        else
            exit_code=$?
        fi
    fi

    local end_time
    end_time=$(date +%s.%N)
    local duration
    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")

    if [[ $exit_code -eq 0 ]]; then
        log_event "SUCCESS" "EXEC" "$command_name completed successfully (${duration}s)"
        return 0
    else
        log_event "ERROR" "EXEC" "$command_name failed with exit code $exit_code (${duration}s)"
        return $exit_code
    fi
}

# ============================================================================
# Git Operation Logging
# ============================================================================

# Log git repository statistics
log_git_repo_stats() {
    local repo_path="$1"
    local label="${2:-Repository}"

    if [[ ! -d "$repo_path/.git" ]]; then
        log_event "ERROR" "GIT" "Not a git repository: $repo_path"
        return 1
    fi

    local commit_count
    commit_count=$(git -C "$repo_path" rev-list --all --count)

    local branch_count
    branch_count=$(git -C "$repo_path" for-each-ref --format='%(refname:short)' refs/heads/ | wc -l)

    local tag_count
    tag_count=$(git -C "$repo_path" tag | wc -l)

    local repo_size
    repo_size=$(du -sb "$repo_path" | awk '{print $1}')

    log_event "INFO" "GIT" "$label statistics: commits=$commit_count branches=$branch_count tags=$tag_count size=$repo_size"
    log_metric "${label}_COMMITS" "$commit_count"
    log_metric "${label}_BRANCHES" "$branch_count"
    log_metric "${label}_TAGS" "$tag_count"
    log_metric "${label}_SIZE" "$repo_size" "bytes"

    return 0
}

# Log git fsck results
log_git_fsck() {
    local repo_path="$1"
    local label="${2:-Repository}"
    local fsck_output

    log_event "INFO" "GIT" "Running git fsck on $label: $repo_path"

    fsck_output=$(git -C "$repo_path" fsck --full 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_event "SUCCESS" "GIT" "$label integrity check passed (fsck OK)"
        return 0
    else
        log_event "ERROR" "GIT" "$label integrity check failed (fsck returned $exit_code)"
        echo "$fsck_output" >> "$TEST_LOG_FILE"
        return $exit_code
    fi
}

# ============================================================================
# OneDrive/rclone Logging
# ============================================================================

# Log OneDrive listing
log_onedrive_listing() {
    local onedrive_path="$1"
    local output_file="$2"

    log_event "INFO" "ONEDRIVE" "Listing OneDrive path: $onedrive_path"

    if rclone ls "onedrive:$onedrive_path" > "$output_file" 2>&1; then
        local file_count
        file_count=$(wc -l < "$output_file" 2>/dev/null || echo "0")
        log_event "SUCCESS" "ONEDRIVE" "Listing complete ($file_count files): $output_file"
        return 0
    else
        log_event "ERROR" "ONEDRIVE" "Failed to list: $onedrive_path"
        return 1
    fi
}

# ============================================================================
# Test Cleanup and Reporting
# ============================================================================

# Generate test summary
generate_test_summary() {
    local overall_status="$1"   # SUCCESS, FAILED, PARTIAL
    local timestamp
    timestamp=$(date -Iseconds)

    # Calculate pass rate
    local pass_rate=0
    if [[ $TEST_STEPS_TOTAL -gt 0 ]]; then
        pass_rate=$(echo "scale=1; $TEST_STEPS_SUCCESS * 100 / $TEST_STEPS_TOTAL" | bc 2>/dev/null || echo "0")
    fi

    # Create JSON summary
    jq -n \
        --arg test_id "$TEST_RUN_ID" \
        --arg test_name "$TEST_NAME" \
        --arg status "$overall_status" \
        --arg timestamp "$timestamp" \
        --arg total_steps "$TEST_STEPS_TOTAL" \
        --arg successful "$TEST_STEPS_SUCCESS" \
        --arg failed "$TEST_STEPS_FAILED" \
        --arg pass_rate "$pass_rate" \
        --arg log_file "$TEST_LOG_FILE" \
        --arg json_log "$TEST_JSON_LOG" \
        --arg artifacts_dir "$TEST_ARTIFACT_DIR" \
        '{
            test_id: $test_id,
            test_name: $test_name,
            status: $status,
            timestamp: $timestamp,
            steps: {
                total: ($total_steps | tonumber),
                successful: ($successful | tonumber),
                failed: ($failed | tonumber),
                pass_rate: ($pass_rate | tonumber)
            },
            logs: {
                human_readable: $log_file,
                json: $json_log,
                artifacts: $artifacts_dir
            }
        }' > "$SUMMARY_JSON"

    # Print summary
    {
        echo ""
        echo "================================================================================"
        echo "Test Summary"
        echo "================================================================================"
        echo "Status: $overall_status"
        echo "Steps: $TEST_STEPS_SUCCESS/$TEST_STEPS_TOTAL passed ($pass_rate%)"
        echo "Completed: $(date -Iseconds)"
        echo ""
        echo "Logs:"
        echo "  Human-readable: $TEST_LOG_FILE"
        echo "  JSON structured: $TEST_JSON_LOG"
        echo "  Artifacts: $TEST_ARTIFACT_DIR"
        echo "  Summary JSON: $SUMMARY_JSON"
        echo "================================================================================"
    } | tee -a "$TEST_LOG_FILE"
}

# Generate HTML report
generate_html_report() {
    local html_file="${TEST_EXPORT_DIR}/test-report-${TEST_RUN_ID}.html"

    log_event "INFO" "REPORT" "Generating HTML report..."

    cat > "$html_file" << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>CloudSync Test Report</title>
    <style>
        body {
            font-family: 'Courier New', monospace;
            margin: 20px;
            background: #f5f5f5;
            color: #333;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            padding: 20px;
            border-radius: 5px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
        }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; }
        .success { color: #27ae60; font-weight: bold; }
        .failed { color: #e74c3c; font-weight: bold; }
        .warning { color: #f39c12; font-weight: bold; }
        .metric { background: #ecf0f1; padding: 8px 12px; margin: 5px 0; border-left: 4px solid #3498db; }
        .log-section { margin: 20px 0; border: 1px solid #bdc3c7; padding: 15px; background: #f9f9f9; }
        pre {
            overflow-x: auto;
            background: #2c3e50;
            color: #ecf0f1;
            padding: 15px;
            border-radius: 3px;
            font-size: 12px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 10px 0;
        }
        th, td {
            border: 1px solid #bdc3c7;
            padding: 10px;
            text-align: left;
        }
        th {
            background: #3498db;
            color: white;
        }
        tr:nth-child(even) {
            background: #ecf0f1;
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        .stat-box {
            background: #3498db;
            color: white;
            padding: 15px;
            border-radius: 5px;
            text-align: center;
        }
        .stat-box .number {
            font-size: 2em;
            font-weight: bold;
        }
        .stat-box .label {
            font-size: 0.9em;
            margin-top: 5px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>CloudSync Test Report</h1>
HTMLEOF

    # Add summary stats
    cat >> "$html_file" << 'HTMLEOF'
        <div class="stats-grid">
            <div class="stat-box">
                <div class="number" id="total-steps">-</div>
                <div class="label">Total Steps</div>
            </div>
            <div class="stat-box">
                <div class="number" id="success-steps">-</div>
                <div class="label">Successful</div>
            </div>
            <div class="stat-box">
                <div class="number" id="failed-steps">-</div>
                <div class="label">Failed</div>
            </div>
            <div class="stat-box">
                <div class="number" id="pass-rate">-</div>
                <div class="label">Pass Rate</div>
            </div>
        </div>

        <h2>Test Details</h2>
        <table>
            <tr><th>Property</th><th>Value</th></tr>
            <tr><td>Test ID</td><td id="test-id">-</td></tr>
            <td>Test Name</td><td id="test-name">-</td></tr>
            <tr><td>Status</td><td id="status">-</td></tr>
            <tr><td>Started</td><td id="started">-</td></tr>
            <tr><td>User</td><td id="user">-</td></tr>
            <tr><td>Host</td><td id="host">-</td></tr>
        </table>

        <h2>Metrics</h2>
        <div id="metrics-section" class="log-section">
            <!-- Metrics will be populated here -->
        </div>

        <h2>Full Log</h2>
        <div class="log-section">
            <pre id="log-content">Loading...</pre>
        </div>
    </div>

    <script>
        // Placeholder for dynamic content
        document.addEventListener('DOMContentLoaded', function() {
            document.getElementById('total-steps').textContent = 'See logs';
        });
    </script>
</body>
</html>
HTMLEOF

    log_event "SUCCESS" "REPORT" "HTML report generated: $html_file"
    return 0
}

# ============================================================================
# Cleanup Function
# ============================================================================

# Cleanup test artifacts and OneDrive data
cleanup_test() {
    local onedrive_path="${1:-}"

    log_event "INFO" "CLEANUP" "Starting cleanup phase..."

    # Delete from OneDrive if path provided
    if [[ -n "$onedrive_path" ]]; then
        log_event "INFO" "CLEANUP" "Deleting OneDrive test path: $onedrive_path"
        if rclone delete "onedrive:$onedrive_path" --log-file="$RCLONE_LOG" 2>&1; then
            log_event "SUCCESS" "CLEANUP" "OneDrive test path deleted"
        else
            log_event "WARN" "CLEANUP" "Failed to delete OneDrive test path (may already be gone)"
        fi
    fi

    log_event "SUCCESS" "CLEANUP" "Test cleanup complete"
    log_event "INFO" "CLEANUP" "Logs preserved at: $TEST_LOG_DIR"
}

# ============================================================================
# Export Functions for Tests
# ============================================================================

# Source this file to get all logging functions
export -f init_test_logging
export -f log_event
export -f log_metric
export -f log_file_operation
export -f log_step_complete
export -f get_file_checksum
export -f log_checksum_comparison
export -f log_directory_structure
export -f run_logged_command
export -f log_git_repo_stats
export -f log_git_fsck
export -f log_onedrive_listing
export -f generate_test_summary
export -f generate_html_report
export -f cleanup_test
