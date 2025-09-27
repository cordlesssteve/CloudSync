#!/bin/bash

# Quarterly Full Tar Backup Script
# Creates full compressed tarball of home directory
# Runs on first Sunday of January, April, July, October at 03:00 AM

# Configuration
BACKUP_SOURCE="$HOME"
BACKUP_DIR="/mnt/c/Dev/wsl_backups/full_archives"
LOG_FILE="$HOME/.backup_logs/tar_quarterly.log"
STATUS_FILE="$HOME/.backup_status"
DATE_STAMP=$(date '+%Y-%m-%d')
BACKUP_FILENAME="home_full_${DATE_STAMP}.tar.gz"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_FILENAME"

# Create directories
mkdir -p "$BACKUP_DIR"
mkdir -p "$HOME/.backup_logs"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"
}

# Function to update status file
update_status() {
    local status="$1"
    local message="$2"
    echo "TAR_QUARTERLY|$(date '+%Y-%m-%d %H:%M:%S')|$status|$message" > "$STATUS_FILE"
}

# Check if we're in the right quarter and week
check_quarterly_schedule() {
    local current_month=$(date '+%m')
    local current_day=$(date '+%d')
    
    # Check if we're in a quarterly month (Jan=01, Apr=04, Jul=07, Oct=10)
    case $current_month in
        01|04|07|10)
            # Check if we're in the first week of the month (day 1-7)
            if [ $current_day -le 7 ]; then
                return 0
            fi
            ;;
    esac
    return 1
}

# Start backup
log_message "Starting quarterly tar backup"
update_status "RUNNING" "Quarterly backup in progress"

# Verify this should run (optional check - can be removed if called by cron)
if ! check_quarterly_schedule; then
    log_message "WARNING: Not in quarterly schedule (first week of Jan/Apr/Jul/Oct), but proceeding anyway"
fi

# Create exclude file for tar
EXCLUDE_FILE=$(mktemp)
cat > "$EXCLUDE_FILE" << 'EOF'
.cache
node_modules
.npm
dist
build
__pycache__
.venv
env
venv
*/.cache
*/node_modules
*/.npm
*/dist
*/build
*/__pycache__
*/.venv
*/env
*/venv
*.log
*.tmp
*.temp
.backup_logs
.backup_status
EOF

log_message "Created tar exclude file: $EXCLUDE_FILE"
log_message "Backup source: $BACKUP_SOURCE"
log_message "Backup destination: $BACKUP_PATH"

# Calculate estimated size before backup
log_message "Calculating estimated backup size..."
ESTIMATED_SIZE=$(du -sh "$BACKUP_SOURCE" --exclude-from="$EXCLUDE_FILE" 2>/dev/null | cut -f1 || echo "unknown")
log_message "Estimated backup size: $ESTIMATED_SIZE"

# Check available space
AVAILABLE_SPACE=$(df -h "$BACKUP_DIR" | tail -1 | awk '{print $4}')
log_message "Available space in backup directory: $AVAILABLE_SPACE"

# Create the tar backup
# Note: --dereference follows symbolic links to backup the actual file contents
# This ensures Claude conversation files stored via symlinks are properly backed up
log_message "Starting tar compression to $BACKUP_PATH"
tar --exclude-from="$EXCLUDE_FILE" \
    --dereference \
    -czf "$BACKUP_PATH" \
    -C "$(dirname "$BACKUP_SOURCE")" \
    "$(basename "$BACKUP_SOURCE")" 2>&1 | tee -a "$LOG_FILE"

TAR_RESULT=${PIPESTATUS[0]}

# Clean up exclude file
rm -f "$EXCLUDE_FILE"

# Tar exit code 1 often means "files changed during backup" which is usually not fatal
# We'll treat exit code 0 and 1 as success, but log any warnings
if [ $TAR_RESULT -eq 0 ] || [ $TAR_RESULT -eq 1 ]; then
    if [ $TAR_RESULT -eq 1 ]; then
        log_message "WARNING: Some files changed during backup (tar exit code 1) - this is usually not critical"
    fi
    # Get actual backup size
    ACTUAL_SIZE=$(ls -lh "$BACKUP_PATH" | awk '{print $5}')
    log_message "Backup completed successfully"
    log_message "Final backup size: $ACTUAL_SIZE"
    log_message "Backup file: $BACKUP_PATH"
    
    # Verify the archive integrity
    log_message "Verifying archive integrity..."
    tar -tzf "$BACKUP_PATH" > /dev/null 2>&1
    VERIFY_RESULT=$?
    
    if [ $VERIFY_RESULT -eq 0 ]; then
        log_message "Archive integrity verification passed"
        update_status "SUCCESS" "Quarterly backup completed successfully ($ACTUAL_SIZE)"
        
        # Clean up old quarterly backups (keep last 4 quarterly backups)
        log_message "Cleaning up old quarterly backups (keeping last 4)..."
        cd "$BACKUP_DIR" || exit 1
        ls -t home_full_*.tar.gz 2>/dev/null | tail -n +5 | while read -r old_backup; do
            if [ -f "$old_backup" ]; then
                log_message "Removing old backup: $old_backup"
                rm -f "$old_backup"
            fi
        done
        
    else
        log_message "ERROR: Archive integrity verification failed"
        update_status "FAILED" "Backup completed but verification failed"
        TAR_RESULT=1
    fi
    
    # List all current quarterly backups
    log_message "Current quarterly backups:"
    ls -lh "$BACKUP_DIR"/home_full_*.tar.gz 2>/dev/null | tee -a "$LOG_FILE" || log_message "No existing quarterly backups found"
    
else
    log_message "ERROR: Tar backup failed with exit code $TAR_RESULT"
    update_status "FAILED" "Backup failed with exit code $TAR_RESULT"
    
    # Clean up partial backup file
    if [ -f "$BACKUP_PATH" ]; then
        log_message "Removing partial backup file: $BACKUP_PATH"
        rm -f "$BACKUP_PATH"
    fi
fi

log_message "Quarterly tar backup script finished"

# Clean up old log files (keep last 12 months)
find "$HOME/.backup_logs" -name "tar_quarterly.log.*" -mtime +365 -delete 2>/dev/null

# Rotate current log if it's getting large (> 10MB)
if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt 10485760 ]; then
    mv "$LOG_FILE" "$LOG_FILE.$(date '+%Y%m%d_%H%M%S')"
fi

exit $TAR_RESULT