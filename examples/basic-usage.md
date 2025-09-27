# CloudSync Basic Usage Examples

## Quick Start Examples

### 1. Development Environment Sync

```bash
# Push your development environment to cloud
cd /home/cordlesssteve/projects/Utility/CloudSync
./scripts/core/dev-env-sync.sh push

# Pull development environment on another device
./scripts/core/dev-env-sync.sh pull
```

### 2. Health Check

```bash
# Run comprehensive health check
./scripts/monitoring/sync-health-check.sh

# Expected output:
# 🌐 Checking rclone connectivity... ✅ rclone connectivity: OK
# ⚔️ Checking for sync conflicts... ✅ No conflicts detected
# 📅 Checking last sync status... ✅ Last sync: 2025-09-27 10:30:15 (recent)
# 💾 Checking disk space... ✅ Disk usage: 45% (OK)
# 🗄️ Checking backup status... ✅ Backup status: 15 snapshots, last: 2025-09-27T08:00:00Z
```

### 3. Configuration Setup

```bash
# Copy and customize configuration
cp config/rclone.conf.template ~/.config/rclone/rclone.conf
# Edit with your credentials

# Load CloudSync configuration
source config/cloudsync.conf
echo "Default remote: $DEFAULT_REMOTE"
```

### 4. Manual Backup Operations

```bash
# Run weekly backup
./scripts/backup/weekly_restic_backup.sh

# Run quarterly backup
./scripts/backup/quarterly_tar_backup.sh
```

## Advanced Usage

### 5. Custom Sync Paths

```bash
# Edit config/cloudsync.conf to add custom paths
CRITICAL_PATHS+=(
    "my-custom-project"
    ".my-special-config"
)

# Then run sync
./scripts/core/dev-env-sync.sh push
```

### 6. Conflict Resolution

```bash
# Check for conflicts
find $HOME -name "*.conflict" -type f

# Manual resolution example
mv file.txt.conflict file.txt  # Choose conflict version
# or
rm file.txt.conflict          # Keep original
```

### 7. Monitoring Automation

```bash
# Add to crontab for automated monitoring
echo "0 */6 * * * $HOME/projects/Utility/CloudSync/scripts/monitoring/sync-health-check.sh" | crontab -

# Weekly sync automation
echo "0 2 * * 0 $HOME/projects/Utility/CloudSync/scripts/core/dev-env-sync.sh push" | crontab -
```

## Troubleshooting Examples

### 8. Connection Issues

```bash
# Test rclone connectivity
rclone lsd onedrive:

# Check configuration
rclone config show

# Verify credentials
rclone about onedrive:
```

### 9. Storage Issues

```bash
# Check available space
rclone about onedrive:

# Clean up old backups
./scripts/core/dev-env-sync.sh clean
```

### 10. Recovery Operations

```bash
# Restore from backup (if available)
./scripts/core/dev-env-sync.sh pull

# Check backup directory
ls -la ~/backup-sync-*/

# Restore specific files
cp ~/backup-sync-*/ssh/* ~/.ssh/
```