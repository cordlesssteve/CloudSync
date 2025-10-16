#!/bin/bash
# CloudSync Test Service Installation Script
# Sets up systemd service and sudoers for programmatic test execution

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "========================================"
echo "CloudSync Test Service Setup"
echo "========================================"
echo ""

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Do not run this script as root!"
    echo "This script will prompt for sudo when needed."
    exit 1
fi

# Step 1: Verify csync-tester user exists
echo "[1/6] Checking csync-tester user..."
if ! id csync-tester &>/dev/null; then
    echo "ERROR: csync-tester user does not exist!"
    echo "Create it with: sudo useradd -m -s /bin/bash csync-tester"
    exit 1
fi
echo "✓ csync-tester user exists"

# Step 2: Ensure CloudSync repo exists in csync-tester home
echo ""
echo "[2/6] Checking CloudSync repository in csync-tester home..."

# Check if directory exists and is a valid git repository
if [[ -d /home/csync-tester/CloudSync/.git ]]; then
    echo "✓ CloudSync repository exists"

    # Update to latest
    echo "  Updating repository..."
    sudo -u csync-tester bash -c "
        cd /home/csync-tester/CloudSync && \
        git fetch origin && \
        git reset --hard origin/main
    "
    echo "  ✓ Updated to latest main"
elif [[ -d /home/csync-tester/CloudSync ]]; then
    # Directory exists but is not a git repo - remove and recreate
    echo "  Directory exists but is not a valid git repository"
    echo "  Removing and recreating..."

    sudo rm -rf /home/csync-tester/CloudSync

    sudo -u csync-tester bash -c "
        cd /home/csync-tester && \
        git clone https://github.com/cordlesssteve/CloudSync.git && \
        cd CloudSync && \
        git config user.email 'csync-tester@cloudsync.local' && \
        git config user.name 'CloudSync Tester'
    "
    echo "  ✓ Repository cloned"
else
    # Directory doesn't exist - create it
    echo "  CloudSync repository not found in /home/csync-tester/"
    echo "  Creating it now..."

    sudo -u csync-tester bash -c "
        cd /home/csync-tester && \
        git clone https://github.com/cordlesssteve/CloudSync.git && \
        cd CloudSync && \
        git config user.email 'csync-tester@cloudsync.local' && \
        git config user.name 'CloudSync Tester'
    "
    echo "  ✓ Repository cloned"
fi

# Step 3: Install systemd service file
echo ""
echo "[3/6] Installing systemd service file..."
sudo cp "$PROJECT_ROOT/config/cloudsync-e2e-test.service" /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/cloudsync-e2e-test.service
echo "✓ Service file installed"

# Step 4: Validate and install sudoers configuration
echo ""
echo "[4/6] Installing sudoers configuration..."
SUDOERS_FILE="$PROJECT_ROOT/config/cloudsync-testing-sudoers"

# Validate syntax before installing
if ! sudo visudo -cf "$SUDOERS_FILE"; then
    echo "ERROR: Sudoers file has syntax errors!"
    exit 1
fi

sudo cp "$SUDOERS_FILE" /etc/sudoers.d/cloudsync-testing
sudo chmod 440 /etc/sudoers.d/cloudsync-testing
echo "✓ Sudoers configuration installed"

# Step 5: Reload systemd
echo ""
echo "[5/6] Reloading systemd..."
sudo systemctl daemon-reload
echo "✓ Systemd reloaded"

# Step 6: Verify setup
echo ""
echo "[6/6] Verifying setup..."
if systemctl list-unit-files | grep -q cloudsync-e2e-test.service; then
    echo "✓ Service registered with systemd"
else
    echo "WARNING: Service not found in systemd list"
fi

echo ""
echo "========================================"
echo "✓ Setup Complete!"
echo "========================================"
echo ""
echo "Usage:"
echo "  Start test:   sudo systemctl start cloudsync-e2e-test.service"
echo "  Check status: sudo systemctl status cloudsync-e2e-test.service"
echo "  View logs:    sudo journalctl -u cloudsync-e2e-test.service --no-pager"
echo "  Follow logs:  sudo journalctl -u cloudsync-e2e-test.service -f"
echo ""
echo "Note: After sudoers configuration, no password will be required for these commands."
