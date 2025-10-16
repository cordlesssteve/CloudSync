# Programmatic Test Execution via systemd

This document explains how CloudSync E2E tests are configured for programmatic execution without password prompts, suitable for CI/CD integration.

## Architecture

**Security Model:**
```
cordlesssteve (operator/CI)
    ↓ [sudo systemctl - restricted permissions via sudoers]
systemd (process supervisor)
    ↓ [executes as csync-tester user]
E2E Test Script
    ↓ [runs in isolated test environment]
Test Results (logged to journalctl)
```

## Components

### 1. systemd Service (`cloudsync-e2e-test.service`)

**Location:** `/etc/systemd/system/cloudsync-e2e-test.service`

**Features:**
- Runs as `csync-tester` user (isolated test environment)
- Automatically updates repository before test (`git pull`)
- Logs output to systemd journal
- Security hardening (PrivateTmp, NoNewPrivileges, ProtectSystem)
- Resource limits (10min timeout, 2GB memory limit)

### 2. Sudoers Configuration (`/etc/sudoers.d/cloudsync-testing`)

**Permissions Granted to `cordlesssteve`:**
- `systemctl start cloudsync-e2e-test.service` - Start tests
- `systemctl stop cloudsync-e2e-test.service` - Stop runaway tests
- `systemctl status cloudsync-e2e-test.service` - Check test status
- `systemctl daemon-reload` - Reload after service changes
- `journalctl -u cloudsync-e2e-test.service` - View test logs

**Security:**
- ✅ NOPASSWD for listed commands only
- ✅ Cannot run arbitrary commands as csync-tester
- ✅ Cannot modify other systemd services
- ✅ Suitable for CI/CD automation

### 3. Test User (`csync-tester`)

**Purpose:** Isolated test execution environment

**Setup:**
- Home directory: `/home/csync-tester/`
- CloudSync repository: `/home/csync-tester/CloudSync` (clone of main repo)
- OneDrive configuration: Separate rclone remote for testing
- Git identity: `csync-tester@cloudsync.local`

## Installation

### Quick Setup

Run the automated setup script:

```bash
cd ~/projects/Utility/LOGISTICAL/CloudSync
./scripts/setup-test-service.sh
```

This script will:
1. ✅ Verify `csync-tester` user exists
2. ✅ Clone CloudSync repository to csync-tester home (if missing)
3. ✅ Install systemd service file
4. ✅ Validate and install sudoers configuration
5. ✅ Reload systemd
6. ✅ Verify setup completed successfully

### Manual Setup

If you prefer manual installation:

```bash
# 1. Create csync-tester user (if not exists)
sudo useradd -m -s /bin/bash csync-tester

# 2. Clone CloudSync repository
sudo -u csync-tester git clone https://github.com/cordlesssteve/CloudSync.git /home/csync-tester/CloudSync

# 3. Install systemd service
sudo cp config/cloudsync-e2e-test.service /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/cloudsync-e2e-test.service

# 4. Install sudoers configuration (validate first!)
sudo visudo -cf config/cloudsync-testing-sudoers
sudo cp config/cloudsync-testing-sudoers /etc/sudoers.d/cloudsync-testing
sudo chmod 440 /etc/sudoers.d/cloudsync-testing

# 5. Reload systemd
sudo systemctl daemon-reload
```

## Usage

### Running Tests

**Start E2E test:**
```bash
sudo systemctl start cloudsync-e2e-test.service
```

**Check test status:**
```bash
sudo systemctl status cloudsync-e2e-test.service
```

**View test logs (last run):**
```bash
sudo journalctl -u cloudsync-e2e-test.service --no-pager
```

**Follow logs in real-time:**
```bash
sudo journalctl -u cloudsync-e2e-test.service -f
```

**Stop running test:**
```bash
sudo systemctl stop cloudsync-e2e-test.service
```

### CI/CD Integration

**Example GitHub Actions workflow:**

```yaml
name: CloudSync E2E Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  e2e-test:
    runs-on: self-hosted
    steps:
      - name: Run E2E Tests
        run: sudo systemctl start cloudsync-e2e-test.service

      - name: Wait for completion
        run: |
          while systemctl is-active --quiet cloudsync-e2e-test.service; do
            sleep 5
          done

      - name: Check test results
        run: |
          sudo journalctl -u cloudsync-e2e-test.service --no-pager
          sudo systemctl status cloudsync-e2e-test.service
```

**Example cron schedule (nightly tests):**

```bash
# Run E2E tests every night at 2 AM
0 2 * * * /usr/bin/systemctl start cloudsync-e2e-test.service
```

## Troubleshooting

### Service won't start

**Check service status:**
```bash
sudo systemctl status cloudsync-e2e-test.service
```

**View detailed logs:**
```bash
sudo journalctl -u cloudsync-e2e-test.service -n 50 --no-pager
```

**Common issues:**
- Repository not found: Clone CloudSync to `/home/csync-tester/CloudSync`
- Permission denied: Ensure csync-tester owns the repository
- Script not executable: `chmod +x /home/csync-tester/CloudSync/tests/integration/e2e-real-onedrive.test.sh`

### Password still required

**Verify sudoers configuration:**
```bash
sudo visudo -cf /etc/sudoers.d/cloudsync-testing
```

**Check sudoers file syntax:**
```bash
cat /etc/sudoers.d/cloudsync-testing
```

**Ensure correct permissions:**
```bash
ls -l /etc/sudoers.d/cloudsync-testing
# Should show: -r--r----- 1 root root
```

### Test script not found

**Ensure repository is up to date:**
```bash
sudo -u csync-tester git -C /home/csync-tester/CloudSync pull origin main
```

**Verify test script exists:**
```bash
sudo ls -l /home/csync-tester/CloudSync/tests/integration/e2e-real-onedrive.test.sh
```

## Security Considerations

### What's Protected

✅ **Restricted sudo access** - Only specific systemctl commands allowed
✅ **User isolation** - Tests run as csync-tester, not cordlesssteve
✅ **Resource limits** - Memory and timeout constraints prevent runaway tests
✅ **System protection** - ProtectSystem=strict prevents system modification
✅ **Private temp** - Test artifacts isolated in private /tmp

### What's NOT Protected

⚠️ **csync-tester home directory** - Tests can modify csync-tester's files
⚠️ **OneDrive test data** - Tests have full access to csync-tester's OneDrive
⚠️ **Test script logic** - Trust the test script not to be malicious

**Mitigation:** Regular code review of test scripts, limit csync-tester's OneDrive quota

## Maintenance

### Updating the Service

**After modifying service file:**
```bash
sudo cp config/cloudsync-e2e-test.service /etc/systemd/system/
sudo systemctl daemon-reload
```

### Updating Test Scripts

**Tests automatically update before each run** via `ExecStartPre` git pull.

**Manual update:**
```bash
sudo -u csync-tester git -C /home/csync-tester/CloudSync pull origin main
```

### Removing the Service

```bash
# Stop service
sudo systemctl stop cloudsync-e2e-test.service

# Remove service file
sudo rm /etc/systemd/system/cloudsync-e2e-test.service

# Remove sudoers configuration
sudo rm /etc/sudoers.d/cloudsync-testing

# Reload systemd
sudo systemctl daemon-reload
```

## Comparison with Other Approaches

| Approach | Security | Flexibility | CI/CD Ready | Maintenance |
|----------|----------|-------------|-------------|-------------|
| **systemd service** ✅ | High | Medium | Yes | Low |
| Whitelist test script | High | Low | Yes | Medium |
| Whitelist bash wrapper | Medium | Medium | Yes | Medium |
| Full bash access | Low | High | Yes | Low |
| Manual execution | High | Low | No | High |

## See Also

- [Running E2E Tests](RUNNING_E2E_TESTS.md) - Test execution guide
- [Testing Infrastructure Analysis](TESTING_INFRASTRUCTURE_ANALYSIS.md) - Gap analysis
- [Testing with Logging](TESTING_WITH_LOGGING.md) - Logging architecture
