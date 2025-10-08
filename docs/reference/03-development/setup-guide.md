# CloudSync Development Setup Guide

**Last Updated:** 2025-09-27
**Prerequisites Verified:** ✅

## Quick Start (5 minutes)

### 1. Clone and Configure
```bash
# Clone the repository
git clone https://github.com/cordlesssteve/CloudSync.git
cd CloudSync

# Copy and customize configuration
cp config/rclone.conf.template ~/.config/rclone/rclone.conf
# Edit with your cloud provider credentials

# Create CloudSync configuration from template
cp config/cloudsync.conf.template config/cloudsync.conf
nano config/cloudsync.conf  # Edit: Set RESTIC_PASSWORD and other values

# Load CloudSync configuration
source config/cloudsync.conf
echo "Default remote: $DEFAULT_REMOTE"
```

### 2. Verify Setup
```bash
# Test connectivity
rclone lsd onedrive:

# Run health check
./scripts/monitoring/sync-health-check.sh
```

### 3. Test Core Features
```bash
# Test deduplication (dry-run)
./scripts/core/smart-dedupe.sh --dry-run --stats

# Test integrity verification
./scripts/core/checksum-verify.sh --size-only --local ~/projects

# Test bidirectional sync access
./scripts/core/bidirectional-sync.sh --check-access
```

**Verification:**
```bash
# All scripts should show help without errors
./scripts/core/smart-dedupe.sh --help
./scripts/core/checksum-verify.sh --help
./scripts/core/bidirectional-sync.sh --help
./scripts/core/conflict-resolver.sh --help
```

## Detailed Setup

### Prerequisites

#### Required Dependencies
```bash
# Install rclone (if not already installed)
curl https://rclone.org/install.sh | sudo bash

# Verify rclone version (1.60+ recommended)
rclone version

# Install jq for JSON processing
sudo apt-get install jq  # Ubuntu/Debian
brew install jq          # macOS

# Verify bash version (4.0+ required)
bash --version
```

#### Optional Dependencies
```bash
# For backup integration
sudo apt-get install restic

# For development
sudo apt-get install shellcheck  # Script linting
```

### Configuration Setup

#### 1. rclone Configuration
```bash
# Interactive configuration
rclone config

# Or copy template and edit
cp config/rclone.conf.template ~/.config/rclone/rclone.conf
```

**Example OneDrive configuration:**
```ini
[onedrive]
type = onedrive
drive_id = your_drive_id
drive_type = business
```

#### 2. CloudSync Configuration
```bash
# Edit main configuration
nano config/cloudsync.conf
```

**Key settings to customize:**
```bash
# Your cloud provider
DEFAULT_REMOTE="onedrive"

# Base sync path
SYNC_BASE_PATH="DevEnvironment"

# Paths to sync (relative to HOME)
CRITICAL_PATHS=(
    ".ssh"
    "scripts"
    "projects/important"
    # Add your critical paths
)

# Files to sync
CRITICAL_FILES=(
    ".gitconfig"
    ".bash_aliases"
    # Add your critical files
)
```

#### 3. Directory Structure
```bash
# CloudSync creates these automatically
~/.cloudsync/
├── bisync/              # Bidirectional sync state
├── conflicts/           # Conflict backups
├── *.log               # Operation logs
├── last-*              # Last operation timestamps
└── *.json              # Statistics and reports
```

### Development Environment

#### Script Development
All scripts follow consistent patterns:

```bash
#!/bin/bash
set -euo pipefail  # Strict mode

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$PROJECT_ROOT/config/cloudsync.conf"

source "$CONFIG_FILE"
```

#### Testing Workflow
```bash
# 1. Always test with dry-run first
./scripts/core/script-name.sh --dry-run

# 2. Check logs for issues
tail -f ~/.cloudsync/script-name.log

# 3. Run health check to verify system state
./scripts/monitoring/sync-health-check.sh

# 4. Test with small datasets before full sync
```

#### Debugging Tools
```bash
# Enable bash debugging
bash -x ./scripts/core/script-name.sh --help

# Check script syntax
shellcheck scripts/core/*.sh

# Monitor file operations
# (Install inotify-tools if needed)
inotifywait -m -r ~/projects
```

### Testing Framework

#### Unit Testing
```bash
# Test individual functions (future enhancement)
# Currently: manual testing with --dry-run modes

# Test configuration loading
source config/cloudsync.conf && echo "Config loaded: $DEFAULT_REMOTE"

# Test path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Script dir: $SCRIPT_DIR"
```

#### Integration Testing
```bash
# Test end-to-end workflows

# 1. Deduplication workflow
./scripts/core/smart-dedupe.sh --dry-run --by-hash --stats

# 2. Verification workflow
./scripts/core/checksum-verify.sh --local ~/test-dir --size-only

# 3. Sync workflow
./scripts/core/bidirectional-sync.sh --dry-run --local ~/test-dir

# 4. Conflict resolution workflow
./scripts/core/conflict-resolver.sh detect --local ~/test-dir
```

### Performance Testing

#### Benchmarking
```bash
# Time operations
time ./scripts/core/checksum-verify.sh --local ~/large-dir --size-only

# Monitor resource usage
top -p $(pgrep rclone)

# Network usage monitoring
iftop  # or nethogs
```

#### Load Testing
```bash
# Test with increasing file counts
# Create test datasets of various sizes:
# - 100 files (~10MB)
# - 1,000 files (~100MB)
# - 10,000 files (~1GB)

# Test deduplication performance
time ./scripts/core/smart-dedupe.sh --dry-run --by-hash
```

## Common Issues

### Setup Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| `rclone: command not found` | rclone not installed | Install rclone using official script |
| `Config file not found` | Wrong working directory | Run from CloudSync project root |
| `Permission denied` | Scripts not executable | `chmod +x scripts/core/*.sh` |
| `Remote not accessible` | rclone config issue | Run `rclone config` to reconfigure |

### Runtime Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| `No such remote` | Invalid remote name in config | Check `DEFAULT_REMOTE` setting |
| `Path does not exist` | Remote path not found | Verify `SYNC_BASE_PATH` exists |
| `Operation timed out` | Slow network/large files | Increase `DEFAULT_TIMEOUT` |
| `Permission errors` | File access restrictions | Check file/directory permissions |

### Performance Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Slow sync operations | Large files without chunking | Use `--size-only` for quick checks |
| High memory usage | Large file lists | Process in smaller batches |
| Network throttling | ISP/provider limits | Use rclone bandwidth limits |
| Disk space warnings | Insufficient local space | Clean up before sync operations |

## Security Considerations

### Credential Management
```bash
# Never commit credentials to git
echo "config/*.conf" >> .gitignore
echo "!config/*.conf.template" >> .gitignore

# Use environment variables for sensitive data
export RCLONE_CONFIG_PASS="your-config-password"

# Regular credential rotation
rclone config update onedrive
```

### Data Protection
```bash
# Always backup before destructive operations
./scripts/core/conflict-resolver.sh backup

# Use dry-run for testing
./scripts/core/bidirectional-sync.sh --dry-run

# Monitor operations
tail -f ~/.cloudsync/*.log
```

### Access Control
```bash
# Restrict script permissions
chmod 750 scripts/core/*.sh

# Protect configuration
chmod 600 config/cloudsync.conf

# Regular security audits
shellcheck scripts/core/*.sh
```

## Next Steps

After setup completion:

1. **Initial Sync**: Start with a small test directory
2. **Health Monitoring**: Set up regular health checks
3. **Automation**: Consider cron jobs for regular operations
4. **Monitoring**: Set up log rotation and monitoring
5. **Backup Integration**: Configure restic if not already done

For production deployment, see [Deployment Guide](../04-deployment/production.md).