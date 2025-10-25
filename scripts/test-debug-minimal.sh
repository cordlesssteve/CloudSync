#!/bin/bash
# Minimal debug script to identify test failure point
set -euo pipefail

echo "=== Starting minimal debug test ==="
echo "User: $(whoami)"
echo "PATH: $PATH"

# Test 1: Basic tools availability
echo "--- Test 1: Tool availability ---"
which jq && echo "✓ jq found" || echo "✗ jq NOT found"
which bc && echo "✓ bc found" || echo "✗ bc NOT found"
which git && echo "✓ git found" || echo "✗ git NOT found"

# Test 2: Array initialization and export
echo "--- Test 2: Array export ---"
export TEST_ARRAY=()
TEST_ARRAY+=("item1")
echo "✓ Array export works: ${TEST_ARRAY[@]}"

# Test 3: Source logging.sh
echo "--- Test 3: Source logging.sh ---"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/tests/logging.sh"
echo "✓ logging.sh sourced successfully"

# Test 4: Initialize logging
echo "--- Test 4: Initialize logging ---"
init_test_logging "minimal-debug-test"
echo "✓ Logging initialized"
echo "  TEST_RUN_ID: $TEST_RUN_ID"
echo "  TEST_LOG_FILE: $TEST_LOG_FILE"

# Test 5: Log a metric
echo "--- Test 5: Log metric ---"
log_metric "TEST_METRIC" "123" "units"
echo "✓ Metric logged"

# Test 6: Log directory structure
echo "--- Test 6: Log directory structure ---"
TEST_DIR="/tmp/test-dir-$$"
mkdir -p "$TEST_DIR"
touch "$TEST_DIR/file1.txt"
touch "$TEST_DIR/file2.txt"
log_directory_structure "$TEST_DIR" "$TEST_ARTIFACT_DIR/test-listing.txt" "Test Directory"
rm -rf "$TEST_DIR"
echo "✓ Directory structure logged"

# Test 7: bc arithmetic
echo "--- Test 7: bc arithmetic ---"
START_TIME=$(date +%s.%N)
END_TIME=$(date +%s.%N)
DURATION=$(echo "$END_TIME - $START_TIME" | bc 2>/dev/null || echo "0")
echo "✓ bc arithmetic works: $DURATION"

echo "=== All tests passed! ==="
exit 0
