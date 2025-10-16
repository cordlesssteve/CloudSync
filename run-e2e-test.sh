#!/bin/bash
# CloudSync E2E Test Runner
# Runs the end-to-end test as csync-tester user

set -euo pipefail

# Run the test as csync-tester user
sudo -u csync-tester -H bash -c 'cd /home/csync-tester/CloudSync && git pull origin main && ./tests/integration/e2e-real-onedrive.test.sh'
