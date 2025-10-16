#!/bin/bash
# Debug script for E2E test failures
# Runs test and gathers diagnostic information

set -euo pipefail

# Output to both terminal and file
DEBUG_LOG="/tmp/cloudsync-debug-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "$DEBUG_LOG") 2>&1

echo "========================================"
echo "CloudSync E2E Test Diagnostics"
echo "========================================"
echo "Debug log: $DEBUG_LOG"
echo ""

# Start the test service
echo "🚀 Starting test service..."
sudo systemctl start cloudsync-e2e-test.service || echo "⚠️  Test service failed (continuing diagnostics...)"

# Wait for test to complete (or fail)
echo "⏳ Waiting for test to complete..."
sleep 3

# Wait for service to finish (up to 60 seconds)
for i in {1..60}; do
    if ! sudo systemctl is-active --quiet cloudsync-e2e-test.service; then
        break
    fi
    sleep 1
done

echo "✓ Test completed"
echo ""

# Get the latest test run ID
LATEST_RUN=$(sudo ls -t /home/csync-tester/.cloudsync-test/logs/test-run-*.log 2>/dev/null | head -1 | grep -oP 'test-run-\K[^.]+(?=\.log)' || echo "none")

if [[ "$LATEST_RUN" == "none" ]]; then
    echo "⚠️  No test run logs found (test may have failed before creating logs)"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "SYSTEMD SERVICE STATUS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    sudo systemctl status cloudsync-e2e-test.service --no-pager -l || true
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "SYSTEMD LOGS (last 50 lines)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    sudo journalctl -u cloudsync-e2e-test.service --no-pager -n 50
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "REPOSITORY STATUS (csync-tester)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    sudo -u csync-tester bash -c 'cd /home/csync-tester/CloudSync && git log -1 --oneline && git status -sb'
    exit 0
fi

echo "📊 Latest Test Run: $LATEST_RUN"
echo ""

# Show end of test log first (most important)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "0. TEST LOG (last 30 lines)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo tail -30 "/home/csync-tester/.cloudsync-test/logs/test-run-$LATEST_RUN.log"
echo ""

# 1. Show last 30 lines of journalctl
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. SYSTEMD SERVICE LOGS (last 30 lines)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo journalctl -u cloudsync-e2e-test.service --no-pager -n 30
echo ""

# 2. Show test summary log
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. TEST RUN LOG (first 50 lines)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo head -50 "/home/csync-tester/.cloudsync-test/logs/test-run-$LATEST_RUN.log"
echo ""

# 3. Show git operations log (where errors show up)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. GIT OPERATIONS LOG (all errors)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if sudo test -f "/home/csync-tester/.cloudsync-test/logs/test-run-$LATEST_RUN-git.log"; then
    sudo cat "/home/csync-tester/.cloudsync-test/logs/test-run-$LATEST_RUN-git.log" | grep -i "error\|fatal\|warning" || echo "No errors found in git log"
else
    echo "Git log file not found"
fi
echo ""

# 4. Show test summary JSON
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. TEST SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if sudo test -f "/home/csync-tester/.cloudsync-test/logs/test-summary-$LATEST_RUN.json"; then
    sudo cat "/home/csync-tester/.cloudsync-test/logs/test-summary-$LATEST_RUN.json" | jq '.' 2>/dev/null || sudo cat "/home/csync-tester/.cloudsync-test/logs/test-summary-$LATEST_RUN.json"
else
    echo "Summary JSON not found"
fi
echo ""

# 5. Check what step failed
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. STEP COMPLETION STATUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo grep -E "\[STEP_[0-9]+\]|log_step_complete" "/home/csync-tester/.cloudsync-test/logs/test-run-$LATEST_RUN.log" || echo "No step logs found"
echo ""

# 6. Check service status
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6. SERVICE STATUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo systemctl status cloudsync-e2e-test.service --no-pager || true
echo ""

# 7. Check if csync-tester has latest code
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "7. CSYNC-TESTER REPOSITORY STATUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo -u csync-tester bash -c 'cd /home/csync-tester/CloudSync && git log -1 --oneline && git status -sb'
echo ""

echo "========================================"
echo "✓ Diagnostics Complete"
echo "========================================"
echo ""
echo "📄 Full diagnostics saved to: $DEBUG_LOG"
echo ""
echo "Quick Actions:"
echo "  - View this log: cat $DEBUG_LOG"
echo "  - Share with Claude: Just tell Claude to read $DEBUG_LOG"
echo ""
echo "  - Retry test:"
echo "    sudo systemctl start cloudsync-e2e-test.service"
