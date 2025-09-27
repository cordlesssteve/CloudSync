#!/bin/bash

# Weekly Restic Backup Script
# Backs up home directory to /mnt/c/wsl_backups/restic_repo
# Runs every Sunday at 02:00 AM

# Configuration
REPO_PATH="/mnt/c/Dev/wsl_backups/restic_repo"
BACKUP_SOURCE="$HOME"
PASSWORD="acordlessblorpwalksintoabar"
LOG_FILE="$HOME/.backup_logs/restic_weekly.log"
STATUS_FILE="$HOME/.backup_status"
RESTIC_BIN="$HOME/.local/bin/restic"

# Ensure PATH includes local bin
export PATH="$HOME/.local/bin:$PATH"

# Create log directory
mkdir -p "$HOME/.backup_logs"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"
}

# Function to update status file
update_status() {
    local status="$1"
    local message="$2"
    echo "RESTIC_WEEKLY|$(date '+%Y-%m-%d %H:%M:%S')|$status|$message" > "$STATUS_FILE"
}

# Start backup
log_message "Starting weekly Restic backup"
update_status "RUNNING" "Backup in progress"

# Set password for restic
export RESTIC_PASSWORD="$PASSWORD"
export RESTIC_REPOSITORY="$REPO_PATH"

# Run backup with exclusions
log_message "Running restic backup with exclusions"
$RESTIC_BIN backup "$BACKUP_SOURCE" \
    --exclude="$HOME/.cache" \
    --exclude="$HOME/node_modules" \
    --exclude="$HOME/.npm" \
    --exclude="$HOME/dist" \
    --exclude="$HOME/build" \
    --exclude="$HOME/__pycache__" \
    --exclude="$HOME/.venv" \
    --exclude="$HOME/env" \
    --exclude="$HOME/venv" \
    --exclude="*/node_modules" \
    --exclude="*/dist" \
    --exclude="*/build" \
    --exclude="*/__pycache__" \
    --exclude="*/.venv" \
    --exclude="*/env" \
    --exclude="*/venv" \
    --exclude="*/.cache" \
    --exclude="*/.npm" \
    --tag "weekly" \
    --tag "$(date '+%Y-%m-%d')" 2>&1 | tee -a "$LOG_FILE"

BACKUP_RESULT=${PIPESTATUS[0]}

if [ $BACKUP_RESULT -eq 0 ]; then
    log_message "Backup completed successfully"
    
    # Apply retention policy - keep last 8 weekly snapshots
    log_message "Applying retention policy: keeping last 8 weekly snapshots"
    $RESTIC_BIN forget --tag weekly --keep-weekly 8 --prune 2>&1 | tee -a "$LOG_FILE"
    
    RETENTION_RESULT=${PIPESTATUS[0]}
    
    if [ $RETENTION_RESULT -eq 0 ]; then
        log_message "Retention policy applied successfully"
        update_status "SUCCESS" "Weekly backup completed and retention applied"
    else
        log_message "ERROR: Retention policy failed"
        update_status "PARTIAL_SUCCESS" "Backup completed but retention failed"
    fi
    
    # Show repository statistics
    log_message "Repository statistics:"
    $RESTIC_BIN stats 2>&1 | tee -a "$LOG_FILE"
    
else
    log_message "ERROR: Backup failed with exit code $BACKUP_RESULT"
    update_status "FAILED" "Backup failed with exit code $BACKUP_RESULT"
fi

log_message "Weekly Restic backup script finished"

# Clean up old log files (keep last 30 days)
find "$HOME/.backup_logs" -name "restic_weekly.log.*" -mtime +30 -delete 2>/dev/null

# Rotate current log if it's getting large (> 10MB)
if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt 10485760 ]; then
    mv "$LOG_FILE" "$LOG_FILE.$(date '+%Y%m%d_%H%M%S')"
fi

exit $BACKUP_RESULT