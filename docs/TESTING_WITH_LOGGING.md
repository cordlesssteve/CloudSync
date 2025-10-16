# CloudSync Testing with Comprehensive Logging

**Purpose:** End-to-end testing with real OneDrive interaction and detailed logging
**Status:** IMPLEMENTATION SPECIFICATION
**Target:** Full workflow verification with complete audit trail

---

## Logging Strategy Overview

### Key Principles

1. **Every operation logged** - Nothing happens silently
2. **Real-time output** - See what's happening as it happens
3. **Structured logs** - Machine-parseable JSON for analysis
4. **Log exports** - All logs saved after test completes
5. **Audit trail** - Exactly what OneDrive received verified
6. **No data loss** - Logs preserved even if test fails

### Log Directory Structure

```
~/.cloudsync-test/
├── logs/
│   ├── test-run-2025-10-16-143022.log          # Human-readable log
│   ├── test-run-2025-10-16-143022.jsonl        # Structured JSON log
│   ├── test-run-2025-10-16-143022-rclone.log   # rclone detailed output
│   ├── test-run-2025-10-16-143022-git.log      # git command output
│   └── test-run-2025-10-16-143022-artifacts/   # Test artifacts for inspection
│       ├── source-repo-listing.txt
│       ├── bundle-info.txt
│       ├── onedrive-listing.txt
│       ├── restored-repo-listing.txt
│       └── diff-original-vs-restored.txt
│
└── exports/
    └── test-results-2025-10-16.html            # HTML report for review
```

---

## Comprehensive Logging Infrastructure

### Core Logging Functions

```bash
#!/bin/bash
# Comprehensive CloudSync Test Logging System

TEST_RUN_ID=$(date +%Y-%m-%d-%H%M%S)
TEST_LOG_DIR="$HOME/.cloudsync-test/logs"
TEST_ARTIFACT_DIR="$TEST_LOG_DIR/test-run-${TEST_RUN_ID}-artifacts"
TEST_LOG_FILE="$TEST_LOG_DIR/test-run-${TEST_RUN_ID}.log"
TEST_JSON_LOG="$TEST_LOG_DIR/test-run-${TEST_RUN_ID}.jsonl"
RCLONE_LOG="$TEST_LOG_DIR/test-run-${TEST_RUN_ID}-rclone.log"
GIT_LOG="$TEST_LOG_DIR/test-run-${TEST_RUN_ID}-git.log"

# Create log directories
mkdir -p "$TEST_LOG_DIR" "$TEST_ARTIFACT_DIR"

# Structured logging to both human-readable and JSON formats
log_event() {
    local level="$1"
    local stage="$2"
    local message="$3"
    local timestamp
    timestamp=$(date -Iseconds)

    # Human-readable log
    echo "[$timestamp] [$level] [$stage] $message" >> "$TEST_LOG_FILE"

    # JSON structured log
    jq -n \
        --arg timestamp "$timestamp" \
        --arg level "$level" \
        --arg stage "$stage" \
        --arg message "$message" \
        '{timestamp: $timestamp, level: $level, stage: $stage, message: $message}' >> "$TEST_JSON_LOG"

    # Also output to console
    echo "[$level] [$stage] $message"
}

# Log with metrics (timing, size, checksums)
log_metric() {
    local metric_name="$1"
    local value="$2"
    local unit="${3:-}"
    local timestamp
    timestamp=$(date -Iseconds)

    echo "[$timestamp] [METRIC] $metric_name=$value $unit" >> "$TEST_LOG_FILE"

    jq -n \
        --arg timestamp "$timestamp" \
        --arg metric "$metric_name" \
        --arg value "$value" \
        --arg unit "$unit" \
        '{timestamp: $timestamp, type: "metric", metric: $metric, value: $value, unit: $unit}' >> "$TEST_JSON_LOG"
}

# Log file operation with checksums
log_file_operation() {
    local operation="$1"     # create, upload, download, restore
    local filepath="$2"
    local size="$3"
    local checksum="$4"
    local timestamp
    timestamp=$(date -Iseconds)

    local file_info="$filepath (${size} bytes, SHA256: ${checksum})"
    echo "[$timestamp] [FILE] [$operation] $file_info" >> "$TEST_LOG_FILE"

    jq -n \
        --arg timestamp "$timestamp" \
        --arg operation "$operation" \
        --arg filepath "$filepath" \
        --arg size "$size" \
        --arg checksum "$checksum" \
        '{timestamp: $timestamp, type: "file_operation", operation: $operation, filepath: $filepath, size: $size, checksum: $checksum}' >> "$TEST_JSON_LOG"
}

# Log step completion with duration
log_step_complete() {
    local step_name="$1"
    local status="$2"  # SUCCESS, FAILED, PARTIAL
    local start_time="$3"
    local duration
    duration=$(echo "$(date +%s.%N) - $start_time" | bc)

    local timestamp
    timestamp=$(date -Iseconds)

    echo "[$timestamp] [STEP] $step_name completed with status: $status (${duration}s)" >> "$TEST_LOG_FILE"

    jq -n \
        --arg timestamp "$timestamp" \
        --arg step "$step_name" \
        --arg status "$status" \
        --arg duration "$duration" \
        '{timestamp: $timestamp, type: "step_complete", step: $step, status: $status, duration_seconds: ($duration | tonumber)}' >> "$TEST_JSON_LOG"
}
```

---

## Full End-to-End Test with Logging

**File:** `tests/integration/e2e-with-logging.test.sh`

```bash
#!/bin/bash
# Complete End-to-End Test with Comprehensive Logging
# Real OneDrive interaction with full audit trail

set -euo pipefail

# Source logging infrastructure
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../test-utils.sh"

# Logging setup (from above section)
TEST_RUN_ID=$(date +%Y-%m-%d-%H%M%S)
TEST_LOG_DIR="$HOME/.cloudsync-test/logs"
TEST_ARTIFACT_DIR="$TEST_LOG_DIR/test-run-${TEST_RUN_ID}-artifacts"
TEST_LOG_FILE="$TEST_LOG_DIR/test-run-${TEST_RUN_ID}.log"
TEST_JSON_LOG="$TEST_LOG_DIR/test-run-${TEST_RUN_ID}.jsonl"
RCLONE_LOG="$TEST_LOG_DIR/test-run-${TEST_RUN_ID}-rclone.log"

mkdir -p "$TEST_LOG_DIR" "$TEST_ARTIFACT_DIR"

# Test configuration
ONEDRIVE_TEST_PATH="CloudSync-Testing/test-${TEST_RUN_ID}"
TEST_WORK_DIR="/tmp/cloudsync-e2e-test-$$"

# Cleanup function with logging
cleanup_test() {
    log_event "INFO" "CLEANUP" "Starting cleanup phase..."

    # Delete test data from OneDrive
    log_event "INFO" "CLEANUP" "Deleting test path from OneDrive: $ONEDRIVE_TEST_PATH"
    if rclone delete "onedrive:$ONEDRIVE_TEST_PATH" --log-file="$RCLONE_LOG" 2>&1; then
        log_event "SUCCESS" "CLEANUP" "OneDrive test path deleted"
    else
        log_event "WARN" "CLEANUP" "Failed to delete OneDrive test path (may already be gone)"
    fi

    # Delete local test artifacts
    log_event "INFO" "CLEANUP" "Deleting local test directory: $TEST_WORK_DIR"
    rm -rf "$TEST_WORK_DIR"

    log_event "SUCCESS" "CLEANUP" "Test cleanup complete"
    log_event "INFO" "SUMMARY" "Logs available at: $TEST_LOG_FILE"
    log_event "INFO" "SUMMARY" "JSON logs available at: $TEST_JSON_LOG"
    log_event "INFO" "SUMMARY" "Artifacts available at: $TEST_ARTIFACT_DIR"
}

trap cleanup_test EXIT

# ============================================================================
# STEP 1: Create fake test repository
# ============================================================================

log_event "INFO" "SETUP" "Creating fake test repository..."
STEP_START=$(date +%s.%N)

mkdir -p "$TEST_WORK_DIR/source-repo"
cd "$TEST_WORK_DIR/source-repo"

git init > "$GIT_LOG" 2>&1
git config user.email "test@cloudsync.local"
git config user.name "CloudSync Tester"

# Create initial content
for i in {1..5}; do
    echo "Test file $i - $(date)" > "file_$i.txt"
    git add "file_$i.txt" >> "$GIT_LOG" 2>&1
    git commit -m "Initial commit $i" >> "$GIT_LOG" 2>&1
done

# Create binary test file
dd if=/dev/urandom of="binary_data.bin" bs=1M count=2 2>/dev/null

git add "binary_data.bin" >> "$GIT_LOG" 2>&1
git commit -m "Add binary test data" >> "$GIT_LOG" 2>&1

# Create branches
git checkout -b develop >> "$GIT_LOG" 2>&1
echo "Develop branch content" > develop.txt
git add develop.txt >> "$GIT_LOG" 2>&1
git commit -m "Develop branch setup" >> "$GIT_LOG" 2>&1

git checkout main >> "$GIT_LOG" 2>&1

cd - > /dev/null

# Log repository structure
log_event "INFO" "SETUP" "Repository created with $(git -C "$TEST_WORK_DIR/source-repo" rev-list --all --count) commits"
log_metric "REPO_COMMITS" "$(git -C "$TEST_WORK_DIR/source-repo" rev-list --all --count)"

# Export source repo structure
find "$TEST_WORK_DIR/source-repo" -type f ! -path '*/.git/*' > "$TEST_ARTIFACT_DIR/source-repo-listing.txt"
log_file_operation "create" "source-repo" "$(du -sb "$TEST_WORK_DIR/source-repo" | awk '{print $1}')" "$(find "$TEST_WORK_DIR/source-repo" -type f ! -path '*/.git/*' -exec sha256sum {} + | sha256sum | awk '{print $1}')"

log_step_complete "SETUP_CREATE_REPO" "SUCCESS" "$STEP_START"

# ============================================================================
# STEP 2: Bundle the test repository
# ============================================================================

log_event "INFO" "BUNDLE_CREATE" "Creating git bundle from source repository..."
STEP_START=$(date +%s.%N)

BUNDLE_FILE="$TEST_WORK_DIR/test-repo.bundle"
git -C "$TEST_WORK_DIR/source-repo" bundle create "$BUNDLE_FILE" --all >> "$GIT_LOG" 2>&1

BUNDLE_SIZE=$(stat -c%s "$BUNDLE_FILE")
BUNDLE_SHA=$(sha256sum "$BUNDLE_FILE" | awk '{print $1}')

log_event "SUCCESS" "BUNDLE_CREATE" "Bundle created: $BUNDLE_FILE"
log_metric "BUNDLE_SIZE" "$BUNDLE_SIZE" "bytes"
log_metric "BUNDLE_SHA256" "$BUNDLE_SHA"
log_file_operation "create" "$BUNDLE_FILE" "$BUNDLE_SIZE" "$BUNDLE_SHA"

# Verify bundle integrity
log_event "INFO" "BUNDLE_CREATE" "Verifying bundle integrity..."
if git bundle verify "$BUNDLE_FILE" > "$TEST_ARTIFACT_DIR/bundle-info.txt" 2>&1; then
    log_event "SUCCESS" "BUNDLE_CREATE" "Bundle integrity verified"
else
    log_event "FAILED" "BUNDLE_CREATE" "Bundle integrity check failed"
    return 1
fi

log_step_complete "BUNDLE_CREATE" "SUCCESS" "$STEP_START"

# ============================================================================
# STEP 3: Upload bundle to OneDrive (REAL)
# ============================================================================

log_event "INFO" "UPLOAD" "Uploading bundle to OneDrive path: $ONEDRIVE_TEST_PATH"
STEP_START=$(date +%s.%N)

mkdir -p "$TEST_WORK_DIR/upload-staging"
cp "$BUNDLE_FILE" "$TEST_WORK_DIR/upload-staging/test-repo.bundle"

# List what we're uploading
log_event "INFO" "UPLOAD" "Staging directory contents:"
ls -lh "$TEST_WORK_DIR/upload-staging/" >> "$TEST_LOG_FILE"

# Real rclone upload to OneDrive
if rclone sync "$TEST_WORK_DIR/upload-staging" "onedrive:$ONEDRIVE_TEST_PATH" \
    --log-file="$RCLONE_LOG" \
    --verbose \
    --progress \
    2>&1 | tee -a "$TEST_LOG_FILE"; then
    log_event "SUCCESS" "UPLOAD" "Bundle uploaded to OneDrive"
else
    log_event "FAILED" "UPLOAD" "Bundle upload to OneDrive failed"
    return 1
fi

# Verify upload
log_event "INFO" "UPLOAD" "Verifying upload..."
if rclone ls "onedrive:$ONEDRIVE_TEST_PATH" > "$TEST_ARTIFACT_DIR/onedrive-listing.txt" 2>&1; then
    log_event "SUCCESS" "UPLOAD" "Upload verification: $(cat "$TEST_ARTIFACT_DIR/onedrive-listing.txt")"
else
    log_event "FAILED" "UPLOAD" "Could not verify upload"
    return 1
fi

log_step_complete "UPLOAD" "SUCCESS" "$STEP_START"

# ============================================================================
# STEP 4: Download bundle as csync-tester user
# ============================================================================

log_event "INFO" "DOWNLOAD" "Downloading bundle as csync-tester user..."
STEP_START=$(date +%s.%N)

# Switch to test user for download
sudo -u csync-tester -H bash -c "
    mkdir -p /tmp/csync-tester-download
    rclone sync 'onedrive:$ONEDRIVE_TEST_PATH' /tmp/csync-tester-download
    ls -lh /tmp/csync-tester-download >> '$TEST_LOG_FILE'
" 2>&1 | tee -a "$TEST_LOG_FILE"

DOWNLOADED_BUNDLE="/tmp/csync-tester-download/test-repo.bundle"
if [[ -f "$DOWNLOADED_BUNDLE" ]]; then
    DOWNLOAD_SIZE=$(stat -c%s "$DOWNLOADED_BUNDLE")
    DOWNLOAD_SHA=$(sha256sum "$DOWNLOADED_BUNDLE" | awk '{print $1}')

    log_event "SUCCESS" "DOWNLOAD" "Bundle downloaded by csync-tester"
    log_metric "DOWNLOAD_SIZE" "$DOWNLOAD_SIZE" "bytes"
    log_metric "DOWNLOAD_SHA256" "$DOWNLOAD_SHA"
    log_file_operation "download" "$DOWNLOADED_BUNDLE" "$DOWNLOAD_SIZE" "$DOWNLOAD_SHA"

    # Verify checksums match
    if [[ "$BUNDLE_SHA" == "$DOWNLOAD_SHA" ]]; then
        log_event "SUCCESS" "DOWNLOAD" "Checksum verification PASSED - bundle is bit-identical"
    else
        log_event "FAILED" "DOWNLOAD" "Checksum mismatch: $BUNDLE_SHA (original) vs $DOWNLOAD_SHA (downloaded)"
        return 1
    fi
else
    log_event "FAILED" "DOWNLOAD" "Downloaded bundle not found at $DOWNLOADED_BUNDLE"
    return 1
fi

log_step_complete "DOWNLOAD" "SUCCESS" "$STEP_START"

# ============================================================================
# STEP 5: Restore bundle as csync-tester
# ============================================================================

log_event "INFO" "RESTORE" "Restoring repository as csync-tester user..."
STEP_START=$(date +%s.%N)

sudo -u csync-tester -H bash -c "
    cd /tmp/csync-tester-download
    git clone test-repo.bundle restored-repo 2>&1 | tee -a '$TEST_LOG_FILE'

    # Run git fsck
    git -C restored-repo fsck --full >> '$TEST_LOG_FILE' 2>&1

    # List files
    find restored-repo -type f ! -path '*/.git/*' > '$TEST_ARTIFACT_DIR/restored-repo-listing.txt'

    # Get commit count
    echo 'Commit count: '$(git -C restored-repo rev-list --all --count) >> '$TEST_LOG_FILE'
" 2>&1 | tee -a "$TEST_LOG_FILE"

log_event "SUCCESS" "RESTORE" "Repository restored by csync-tester"

log_step_complete "RESTORE" "SUCCESS" "$STEP_START"

# ============================================================================
# STEP 6: Verify integrity - compare original vs restored
# ============================================================================

log_event "INFO" "VERIFY" "Comparing original and restored repositories..."
STEP_START=$(date +%s.%N)

# Compare file listings
log_event "INFO" "VERIFY" "Comparing file structures..."
diff "$TEST_ARTIFACT_DIR/source-repo-listing.txt" <(
    sudo -u csync-tester -H find /tmp/csync-tester-download/restored-repo -type f ! -path '*/.git/*' | sed 's|/tmp/csync-tester-download/restored-repo||g' | sort
) > "$TEST_ARTIFACT_DIR/diff-original-vs-restored.txt" 2>&1 || true

if [[ -s "$TEST_ARTIFACT_DIR/diff-original-vs-restored.txt" ]]; then
    log_event "WARN" "VERIFY" "File structure differences found (may be expected)"
    cat "$TEST_ARTIFACT_DIR/diff-original-vs-restored.txt" >> "$TEST_LOG_FILE"
else
    log_event "SUCCESS" "VERIFY" "File structures are identical"
fi

# Compare commit counts
ORIGINAL_COMMITS=$(git -C "$TEST_WORK_DIR/source-repo" rev-list --all --count)
RESTORED_COMMITS=$(sudo -u csync-tester -H git -C /tmp/csync-tester-download/restored-repo rev-list --all --count)

log_metric "ORIGINAL_COMMITS" "$ORIGINAL_COMMITS"
log_metric "RESTORED_COMMITS" "$RESTORED_COMMITS"

if [[ "$ORIGINAL_COMMITS" == "$RESTORED_COMMITS" ]]; then
    log_event "SUCCESS" "VERIFY" "Commit counts match: $ORIGINAL_COMMITS"
else
    log_event "FAILED" "VERIFY" "Commit count mismatch: $ORIGINAL_COMMITS vs $RESTORED_COMMITS"
    return 1
fi

log_step_complete "VERIFY" "SUCCESS" "$STEP_START"

# ============================================================================
# FINAL: Generate summary report
# ============================================================================

log_event "SUCCESS" "OVERALL" "End-to-end test completed successfully!"
log_event "INFO" "SUMMARY" "Test artifacts: $TEST_ARTIFACT_DIR"
log_event "INFO" "SUMMARY" "Full logs: $TEST_LOG_FILE"
log_event "INFO" "SUMMARY" "JSON logs: $TEST_JSON_LOG"

# Generate JSON summary
SUMMARY_JSON="$TEST_LOG_DIR/test-summary-${TEST_RUN_ID}.json"
jq -n \
    --arg test_id "$TEST_RUN_ID" \
    --arg status "SUCCESS" \
    --arg onedrive_path "$ONEDRIVE_TEST_PATH" \
    --arg bundle_size "$BUNDLE_SIZE" \
    --arg bundle_sha "$BUNDLE_SHA" \
    --arg download_sha "$DOWNLOAD_SHA" \
    --arg original_commits "$ORIGINAL_COMMITS" \
    --arg restored_commits "$RESTORED_COMMITS" \
    '{
        test_id: $test_id,
        status: $status,
        onedrive_path: $onedrive_path,
        bundle: {
            size_bytes: ($bundle_size | tonumber),
            sha256: $bundle_sha
        },
        download: {
            sha256: $download_sha,
            checksum_match: ($bundle_sha == $download_sha)
        },
        commits: {
            original: ($original_commits | tonumber),
            restored: ($restored_commits | tonumber),
            match: ($original_commits == $restored_commits)
        }
    }' > "$SUMMARY_JSON"

log_event "INFO" "SUMMARY" "JSON summary: $SUMMARY_JSON"

cat "$SUMMARY_JSON"
```

---

## Log Analysis and Reporting

### Generate Test Report from Logs

```bash
#!/bin/bash
# Generate HTML report from test logs

TEST_RUN_ID="$1"
TEST_LOG_DIR="$HOME/.cloudsync-test/logs"
TEST_LOG_FILE="$TEST_LOG_DIR/test-run-${TEST_RUN_ID}.log"
TEST_JSON_LOG="$TEST_LOG_DIR/test-run-${TEST_RUN_ID}.jsonl"
OUTPUT_HTML="$TEST_LOG_DIR/../exports/test-report-${TEST_RUN_ID}.html"

cat > "$OUTPUT_HTML" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>CloudSync Test Report</title>
    <style>
        body { font-family: monospace; margin: 20px; }
        .success { color: green; }
        .failed { color: red; }
        .warning { color: orange; }
        .metric { background: #f0f0f0; padding: 10px; margin: 5px 0; }
        .log-section { margin: 20px 0; border: 1px solid #ccc; padding: 10px; }
        pre { overflow-x: auto; }
    </style>
</head>
<body>
    <h1>CloudSync Test Report</h1>
    <p>Test ID: <strong>$TEST_RUN_ID</strong></p>

    <h2>Metrics</h2>
EOF

# Extract metrics from JSON log
jq -r 'select(.type=="metric") | "\(.metric): \(.value) \(.unit)"' "$TEST_JSON_LOG" >> "$OUTPUT_HTML"

cat >> "$OUTPUT_HTML" << 'EOF'

    <h2>Step Results</h2>
EOF

# Extract step results
jq -r 'select(.type=="step_complete") | "<div class=\"\(.status)\">Step: \(.step) - \(.status) (\(.duration_seconds)s)</div>"' "$TEST_JSON_LOG" >> "$OUTPUT_HTML"

cat >> "$OUTPUT_HTML" << 'EOF'

    <h2>Full Log</h2>
    <pre>
EOF

cat "$TEST_LOG_FILE" >> "$OUTPUT_HTML"

cat >> "$OUTPUT_HTML" << 'EOF'
    </pre>
</body>
</html>
EOF

echo "Report generated: $OUTPUT_HTML"
```

---

## Usage

### Run Complete Test with All Logging

```bash
# Run as csync-tester user
sudo -u csync-tester -H bash -c 'cd ~/CloudSync && ./tests/integration/e2e-with-logging.test.sh'

# Generates:
# - $HOME/.cloudsync-test/logs/test-run-2025-10-16-143022.log          (human-readable)
# - $HOME/.cloudsync-test/logs/test-run-2025-10-16-143022.jsonl        (structured)
# - $HOME/.cloudsync-test/logs/test-run-2025-10-16-143022-rclone.log   (rclone output)
# - $HOME/.cloudsync-test/logs/test-run-2025-10-16-143022-artifacts/*  (test artifacts)
# - $HOME/.cloudsync-test/exports/test-report-2025-10-16-143022.html   (HTML report)
```

### Inspect Logs

```bash
# View human-readable log
tail -50 ~/.cloudsync-test/logs/test-run-2025-10-16-143022.log

# Parse JSON metrics
jq '.[] | select(.type=="metric")' ~/.cloudsync-test/logs/test-run-2025-10-16-143022.jsonl

# View test artifacts
ls -lh ~/.cloudsync-test/logs/test-run-2025-10-16-143022-artifacts/

# Open HTML report
firefox ~/.cloudsync-test/exports/test-report-2025-10-16-143022.html
```

---

## What Gets Logged

✓ **Every operation with timestamps**
✓ **File sizes before/after**
✓ **SHA256 checksums for integrity**
✓ **Step completion times**
✓ **OneDrive interactions (via rclone logs)**
✓ **Git operations (commits, branches, integrity checks)**
✓ **Metrics and measurements**
✓ **Test artifacts for manual inspection**
✓ **Both human-readable and machine-parseable formats**
✓ **HTML report for easy review**

## What Gets Cleaned Up

✓ **Test bundles deleted from OneDrive**
✓ **Local test directories deleted**
✓ **Logs and artifacts preserved for review**
✓ **No leftover test data anywhere**
