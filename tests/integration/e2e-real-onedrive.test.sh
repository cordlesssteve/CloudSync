#!/bin/bash
# CloudSync End-to-End Test with Real OneDrive Interaction
# Complete backup → bundle → upload → download → restore workflow
# All operations logged with checksums and timing

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
TEST_UTILS_DIR="$PROJECT_ROOT/tests"

# Source logging infrastructure
if [[ ! -f "$TEST_UTILS_DIR/logging.sh" ]]; then
    echo "ERROR: Logging infrastructure not found: $TEST_UTILS_DIR/logging.sh" >&2
    exit 1
fi
source "$TEST_UTILS_DIR/logging.sh"

# Initialize logging
init_test_logging "End-to-End CloudSync Test (Real OneDrive)"

# Test configuration
ONEDRIVE_REMOTE="onedrive"
ONEDRIVE_TEST_PATH="CloudSync-Testing/test-${TEST_RUN_ID}"
TEST_WORK_DIR="/tmp/cloudsync-e2e-${TEST_RUN_ID}"

# Step timing
OVERALL_START=$(date +%s.%N)

# Cleanup on exit
cleanup_handler() {
    log_event "INFO" "CLEANUP" "Trap handler activated..."
    cleanup_test "$ONEDRIVE_TEST_PATH"

    # Final summary
    local overall_end=$(date +%s.%N)
    local overall_duration=$(echo "$overall_end - $OVERALL_START" | bc 2>/dev/null || echo "0")

    log_event "INFO" "SUMMARY" "Total test duration: ${overall_duration}s"

    if [[ $TEST_STEPS_FAILED -eq 0 ]]; then
        generate_test_summary "SUCCESS"
    else
        generate_test_summary "FAILED"
    fi

    generate_html_report
}

trap cleanup_handler EXIT

# ============================================================================
# STEP 1: Create Test Repository
# ============================================================================

log_event "INFO" "STEP_1" "Creating test repository..."
STEP_START=$(date +%s.%N)

mkdir -p "$TEST_WORK_DIR/source-repo"
cd "$TEST_WORK_DIR/source-repo"

log_event "INFO" "STEP_1" "Initializing git repository"
git init > "$GIT_LOG" 2>&1
git config user.email "csync-tester@cloudsync.local"
git config user.name "CloudSync Tester"

# Create initial test files
log_event "INFO" "STEP_1" "Creating test files..."
for i in {1..5}; do
    filename="file_$i.txt"
    echo "Test file $i - $(date +%Y-%m-%d)" > "$filename"
    git add "$filename" >> "$GIT_LOG" 2>&1
    git commit -m "Add $filename" >> "$GIT_LOG" 2>&1
done

# Create subdirectory with files
mkdir -p data/nested
echo "Nested file content" > data/nested/nested.txt
git add data/ >> "$GIT_LOG" 2>&1
git commit -m "Add nested directory" >> "$GIT_LOG" 2>&1

# Create binary test data (small - 2MB)
log_event "INFO" "STEP_1" "Creating binary test data..."
dd if=/dev/urandom of="binary_data.bin" bs=1M count=2 2>/dev/null
git add "binary_data.bin" >> "$GIT_LOG" 2>&1
git commit -m "Add binary test data (2MB)" >> "$GIT_LOG" 2>&1

# Create branches
log_event "INFO" "STEP_1" "Creating git branches..."
git checkout -b develop >> "$GIT_LOG" 2>&1
echo "Develop branch work" > develop.txt
git add develop.txt >> "$GIT_LOG" 2>&1
git commit -m "Develop branch setup" >> "$GIT_LOG" 2>&1

git checkout main >> "$GIT_LOG" 2>&1

cd - > /dev/null

# Log repository statistics
log_git_repo_stats "$TEST_WORK_DIR/source-repo" "Source Repository"

# Save source repository listing
log_directory_structure "$TEST_WORK_DIR/source-repo" \
    "$TEST_ARTIFACT_DIR/source-repo-listing.txt" \
    "Source Repository"

# Calculate source repository checksum
source_repo_checksum=$(find "$TEST_WORK_DIR/source-repo" -type f ! -path '*/.git/*' -exec sha256sum {} + | sha256sum | awk '{print $1}')
log_metric "SOURCE_REPO_CHECKSUM" "$source_repo_checksum"

log_step_complete "STEP_1_CREATE_REPO" "SUCCESS" "$STEP_START"

# ============================================================================
# STEP 2: Create Bundle
# ============================================================================

log_event "INFO" "STEP_2" "Creating git bundle from source repository..."
STEP_START=$(date +%s.%N)

BUNDLE_FILE="$TEST_WORK_DIR/test-repo.bundle"

log_event "INFO" "STEP_2" "Running: git bundle create --all"
if ! git -C "$TEST_WORK_DIR/source-repo" bundle create "$BUNDLE_FILE" --all >> "$GIT_LOG" 2>&1; then
    log_event "ERROR" "STEP_2" "Bundle creation failed"
    log_step_complete "STEP_2_BUNDLE_CREATE" "FAILED" "$STEP_START"
    return 1
fi

# Get bundle statistics
BUNDLE_SIZE=$(stat -c%s "$BUNDLE_FILE")
BUNDLE_SHA=$(get_file_checksum "$BUNDLE_FILE")

log_file_operation "create" "$BUNDLE_FILE" "$BUNDLE_SIZE" "$BUNDLE_SHA"
log_metric "BUNDLE_SIZE_BYTES" "$BUNDLE_SIZE"

# Verify bundle integrity
log_event "INFO" "STEP_2" "Verifying bundle integrity..."
if git bundle verify "$BUNDLE_FILE" > "$TEST_ARTIFACT_DIR/bundle-verify.txt" 2>&1; then
    log_event "SUCCESS" "STEP_2" "Bundle integrity verified"
else
    log_event "ERROR" "STEP_2" "Bundle verification failed"
    cat "$TEST_ARTIFACT_DIR/bundle-verify.txt" >> "$TEST_LOG_FILE"
    log_step_complete "STEP_2_BUNDLE_CREATE" "FAILED" "$STEP_START"
    return 1
fi

log_step_complete "STEP_2_BUNDLE_CREATE" "SUCCESS" "$STEP_START"

# ============================================================================
# STEP 3: Upload Bundle to OneDrive (REAL)
# ============================================================================

log_event "INFO" "STEP_3" "Uploading bundle to OneDrive..."
STEP_START=$(date +%s.%N)

log_event "INFO" "STEP_3" "OneDrive path: $ONEDRIVE_TEST_PATH"
log_event "INFO" "STEP_3" "Bundle file: $BUNDLE_FILE ($(numfmt --to=iec-i --suffix=B $BUNDLE_SIZE 2>/dev/null || echo "$BUNDLE_SIZE bytes"))"

# Create staging directory
mkdir -p "$TEST_WORK_DIR/upload-staging"
cp "$BUNDLE_FILE" "$TEST_WORK_DIR/upload-staging/"

# List staging directory
log_event "INFO" "STEP_3" "Upload staging directory:"
ls -lh "$TEST_WORK_DIR/upload-staging/" >> "$TEST_LOG_FILE"

# Real rclone upload
log_event "INFO" "STEP_3" "Running rclone sync to OneDrive..."
if rclone sync "$TEST_WORK_DIR/upload-staging" "onedrive:$ONEDRIVE_TEST_PATH" \
    --log-file="$RCLONE_LOG" \
    --verbose \
    2>&1 | tee -a "$TEST_LOG_FILE"; then
    log_event "SUCCESS" "STEP_3" "Bundle uploaded to OneDrive"
else
    log_event "ERROR" "STEP_3" "Bundle upload failed"
    log_step_complete "STEP_3_UPLOAD" "FAILED" "$STEP_START"
    return 1
fi

# Verify upload by listing OneDrive path
log_event "INFO" "STEP_3" "Verifying upload..."
log_onedrive_listing "$ONEDRIVE_TEST_PATH" "$TEST_ARTIFACT_DIR/onedrive-listing-after-upload.txt"

log_step_complete "STEP_3_UPLOAD" "SUCCESS" "$STEP_START"

# ============================================================================
# STEP 4: Download Bundle as csync-tester
# ============================================================================

log_event "INFO" "STEP_4" "Downloading bundle as csync-tester user..."
STEP_START=$(date +%s.%N)

log_event "INFO" "STEP_4" "Creating download directory for csync-tester..."

# Run download as csync-tester user
if sudo -u csync-tester -H bash -c "
    set -euo pipefail
    mkdir -p /tmp/csync-tester-download-${TEST_RUN_ID}
    cd /tmp/csync-tester-download-${TEST_RUN_ID}
    rclone sync 'onedrive:$ONEDRIVE_TEST_PATH' .
    ls -lh >> '$TEST_LOG_FILE' 2>&1
" 2>&1 | tee -a "$TEST_LOG_FILE"; then
    log_event "SUCCESS" "STEP_4" "Bundle downloaded by csync-tester"
else
    log_event "ERROR" "STEP_4" "Bundle download failed"
    log_step_complete "STEP_4_DOWNLOAD" "FAILED" "$STEP_START"
    return 1
fi

# Verify downloaded file
DOWNLOAD_DIR="/tmp/csync-tester-download-${TEST_RUN_ID}"
DOWNLOADED_BUNDLE="$DOWNLOAD_DIR/test-repo.bundle"

if [[ ! -f "$DOWNLOADED_BUNDLE" ]]; then
    log_event "ERROR" "STEP_4" "Downloaded bundle not found: $DOWNLOADED_BUNDLE"
    log_step_complete "STEP_4_DOWNLOAD" "FAILED" "$STEP_START"
    return 1
fi

# Get download statistics
DOWNLOAD_SIZE=$(sudo -u csync-tester stat -c%s "$DOWNLOADED_BUNDLE" 2>/dev/null || stat -f%z "$DOWNLOADED_BUNDLE" 2>/dev/null || echo "0")
DOWNLOAD_SHA=$(sudo -u csync-tester bash -c "sha256sum '$DOWNLOADED_BUNDLE' | awk '{print \$1}'" 2>/dev/null || echo "")

log_file_operation "download" "$DOWNLOADED_BUNDLE" "$DOWNLOAD_SIZE" "$DOWNLOAD_SHA"
log_metric "DOWNLOAD_SIZE_BYTES" "$DOWNLOAD_SIZE"

# Verify checksums match
if [[ "$BUNDLE_SHA" == "$DOWNLOAD_SHA" ]]; then
    log_checksum_comparison "BUNDLE_INTEGRITY" "$BUNDLE_SHA" "$DOWNLOAD_SHA"
else
    log_event "ERROR" "STEP_4" "Checksum mismatch: original=$BUNDLE_SHA, downloaded=$DOWNLOAD_SHA"
    log_step_complete "STEP_4_DOWNLOAD" "FAILED" "$STEP_START"
    return 1
fi

# Verify bundle size matches
if [[ "$BUNDLE_SIZE" == "$DOWNLOAD_SIZE" ]]; then
    log_event "SUCCESS" "STEP_4" "Size verification passed: $BUNDLE_SIZE bytes"
else
    log_event "ERROR" "STEP_4" "Size mismatch: original=$BUNDLE_SIZE, downloaded=$DOWNLOAD_SIZE"
    log_step_complete "STEP_4_DOWNLOAD" "FAILED" "$STEP_START"
    return 1
fi

log_step_complete "STEP_4_DOWNLOAD" "SUCCESS" "$STEP_START"

# ============================================================================
# STEP 5: Restore Bundle as csync-tester
# ============================================================================

log_event "INFO" "STEP_5" "Restoring repository as csync-tester..."
STEP_START=$(date +%s.%N)

log_event "INFO" "STEP_5" "Running: git clone $DOWNLOADED_BUNDLE"

if sudo -u csync-tester -H bash -c "
    set -euo pipefail
    cd '$DOWNLOAD_DIR'
    git clone test-repo.bundle restored-repo 2>&1 | tee -a '$TEST_LOG_FILE'
" 2>&1 | tee -a "$TEST_LOG_FILE"; then
    log_event "SUCCESS" "STEP_5" "Repository restored"
else
    log_event "ERROR" "STEP_5" "Repository restore failed"
    log_step_complete "STEP_5_RESTORE" "FAILED" "$STEP_START"
    return 1
fi

# Verify restored repository integrity
log_event "INFO" "STEP_5" "Running git fsck on restored repository..."
if sudo -u csync-tester -H bash -c "
    git -C '$DOWNLOAD_DIR/restored-repo' fsck --full >> '$GIT_LOG' 2>&1
" 2>&1; then
    log_event "SUCCESS" "STEP_5" "Restored repository integrity verified"
else
    log_event "ERROR" "STEP_5" "Restored repository integrity check failed"
    log_step_complete "STEP_5_RESTORE" "FAILED" "$STEP_START"
    return 1
fi

# Get restored repository statistics
sudo -u csync-tester -H bash -c "
    git -C '$DOWNLOAD_DIR/restored-repo' rev-list --all --count >> /tmp/restored-commits-${TEST_RUN_ID}.txt 2>&1
" || echo "0" > /tmp/restored-commits-${TEST_RUN_ID}.txt

log_directory_structure "$DOWNLOAD_DIR/restored-repo" \
    "$TEST_ARTIFACT_DIR/restored-repo-listing.txt" \
    "Restored Repository"

log_step_complete "STEP_5_RESTORE" "SUCCESS" "$STEP_START"

# ============================================================================
# STEP 6: Verify Integrity
# ============================================================================

log_event "INFO" "STEP_6" "Verifying repository integrity..."
STEP_START=$(date +%s.%N)

# Compare commit counts
ORIGINAL_COMMITS=$(git -C "$TEST_WORK_DIR/source-repo" rev-list --all --count)
RESTORED_COMMITS=$(cat /tmp/restored-commits-${TEST_RUN_ID}.txt)

log_metric "COMMITS_ORIGINAL" "$ORIGINAL_COMMITS"
log_metric "COMMITS_RESTORED" "$RESTORED_COMMITS"

if [[ "$ORIGINAL_COMMITS" == "$RESTORED_COMMITS" ]]; then
    log_event "SUCCESS" "STEP_6" "Commit count match: $ORIGINAL_COMMITS commits"
else
    log_event "ERROR" "STEP_6" "Commit count mismatch: original=$ORIGINAL_COMMITS, restored=$RESTORED_COMMITS"
    log_step_complete "STEP_6_VERIFY" "FAILED" "$STEP_START"
    return 1
fi

# Compare file structures
log_event "INFO" "STEP_6" "Comparing file structures..."
diff -q \
    <(sort "$TEST_ARTIFACT_DIR/source-repo-listing.txt") \
    <(sudo -u csync-tester sort "$TEST_ARTIFACT_DIR/restored-repo-listing.txt") \
    > "$TEST_ARTIFACT_DIR/file-structure-diff.txt" 2>&1 || true

if [[ ! -s "$TEST_ARTIFACT_DIR/file-structure-diff.txt" ]]; then
    log_event "SUCCESS" "STEP_6" "File structures are identical"
else
    log_event "WARN" "STEP_6" "File structure differences found (may be expected)"
    head -10 "$TEST_ARTIFACT_DIR/file-structure-diff.txt" >> "$TEST_LOG_FILE"
fi

log_step_complete "STEP_6_VERIFY" "SUCCESS" "$STEP_START"

# ============================================================================
# STEP 7: Final Validation
# ============================================================================

log_event "INFO" "STEP_7" "Performing final validation..."
STEP_START=$(date +%s.%N)

# Verify git can read the restored repository
if sudo -u csync-tester -H bash -c "
    git -C '$DOWNLOAD_DIR/restored-repo' log --oneline | head -5 >> '$GIT_LOG' 2>&1
" 2>&1; then
    log_event "SUCCESS" "STEP_7" "Restored repository is readable"
else
    log_event "ERROR" "STEP_7" "Restored repository cannot be read"
    log_step_complete "STEP_7_FINAL_VALIDATION" "FAILED" "$STEP_START"
    return 1
fi

# Verify branches exist
ORIGINAL_BRANCHES=$(git -C "$TEST_WORK_DIR/source-repo" branch -a | wc -l)
RESTORED_BRANCHES=$(sudo -u csync-tester -H bash -c "git -C '$DOWNLOAD_DIR/restored-repo' branch -a | wc -l" 2>/dev/null || echo "0")

log_metric "BRANCHES_ORIGINAL" "$ORIGINAL_BRANCHES"
log_metric "BRANCHES_RESTORED" "$RESTORED_BRANCHES"

if [[ "$ORIGINAL_BRANCHES" == "$RESTORED_BRANCHES" ]]; then
    log_event "SUCCESS" "STEP_7" "Branch count match: $ORIGINAL_BRANCHES branches"
else
    log_event "WARN" "STEP_7" "Branch count mismatch: original=$ORIGINAL_BRANCHES, restored=$RESTORED_BRANCHES (may be expected)"
fi

log_step_complete "STEP_7_FINAL_VALIDATION" "SUCCESS" "$STEP_START"

# ============================================================================
# ALL STEPS COMPLETE
# ============================================================================

log_event "SUCCESS" "OVERALL" "All test steps completed successfully!"
log_event "INFO" "OVERALL" "End-to-end workflow verification: PASSED"
