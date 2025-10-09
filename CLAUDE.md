# Project CLAUDE.md

## ═══════════════════════════════════════════════════════
## GLOBAL CONFIGURATION (Auto-Inherited - Do Not Edit Here)
## ═══════════════════════════════════════════════════════
## These are imported from ~/.claude/config/*
## To update global behavior, edit those files directly
## Changes will automatically apply to all projects using this template
##
## NOTE: Using tilde paths (~/.claude/...) works across all project locations
## Alternative formats: relative (@../../../.claude/...) or absolute (@/home/user/...)

@~/.claude/config/intellectual-honesty.md
@~/.claude/config/verification-protocols.md
@~/.claude/config/file-organization.md
@~/.claude/config/backup-systems.md
@~/.claude/config/mcp-discovery-protocol.md

## ═══════════════════════════════════════════════════════
## PROJECT-SPECIFIC CONFIGURATION
## ═══════════════════════════════════════════════════════
## Edit below this line for project-specific instructions

## Project Context
- **Name:** CloudSync
- **Type:** CLI Tool / Sync Service
- **Status:** Active
- **Tech Stack:** Bash, rclone, git-annex
- **Repository:** https://github.com/cordlesssteve/CloudSync.git
- **Data Directory:** `~/cloudsync-managed/` (synced to OneDrive, NOT git-tracked)

## 🚨 MANDATORY READING ORDER 🚨
Before starting ANY development work, Claude MUST read these files in order:

1. **CURRENT_STATUS.md** - Current reality and what's actually done
2. **ACTIVE_PLAN.md** - What we're currently executing (if exists)
3. Only then reference other documentation for context

## Project-Specific Guidelines

### Directory Structure
**Directory Tree:** Use `.directory_tree.txt` in project root for complete structure
**NEVER regenerate directory tree** - read existing file to save context tokens

### Development Workflow
[Add project-specific development workflow here]

### Testing Requirements
[Add project-specific testing requirements here]

### Deployment Process
[Add deployment instructions if applicable]

## Architecture Overview
Cloud synchronization service management using rclone for OneDrive sync and custom orchestration scripts.

**Key Components:**
- **Development Repository:** This git repo (scripts, monitoring, orchestration)
- **Data Directory:** `~/cloudsync-managed/` - Files being synced to cloud
- **Backup Scripts:** `scripts/backup/` - System-level backup automation

## Backup Script Locations & D: Drive Migration

**IMPORTANT: Multiple script locations exist for different purposes**

### Script Locations Matrix

| Location | Purpose | Git Tracked | Used By |
|----------|---------|-------------|---------|
| `~/scripts/system/` | **Active cron jobs** | ❌ No | System cron |
| `~/cloudsync-managed/scripts/system/` | **Data backup** | ❌ No | OneDrive sync |
| `~/projects/.../CloudSync/scripts/backup/` | **Development** | ✅ Yes | This repo |

### D: Drive Migration (Oct 2025)

**Background:** C: drive reached 94% capacity (416GB/447GB). Moved all backups to D: drive.

**Symlink for Compatibility:**
```bash
/mnt/c/Dev/wsl_backups -> /mnt/d/wsl_backups  # Created Oct 7, 2025
```

**Backup Paths (Updated Oct 9, 2025):**
- **Restic:** `/mnt/d/wsl_backups/restic_repo` (42GB, 6 snapshots)
- **TAR Archives:** `/mnt/d/wsl_backups/full_archives`
- **Scripts use symlink:** `/mnt/c/Dev/wsl_backups/*` (points to D: drive)

**Scripts Updated:**
- ✅ `quarterly_tar_backup.sh` - BACKUP_DIR → `/mnt/d/wsl_backups/full_archives`
- ✅ `weekly_restic_backup.sh` - Comment updated to document D: drive + symlink
- ✅ `startup_health_check.sh` - RESTIC_REPO → `/mnt/d/wsl_backups/restic_repo`

**Maintenance Tasks:**
- Restic prune run: Reclaimed 5.5GB (331 duplicate files removed)
- Repository optimized: 48GB → 42GB
- Stale lock cleared: Retention policy now working

## External Dependencies
- **rclone** - Cloud sync engine (OneDrive remote configured)
- **restic** - Backup tool (`~/.local/bin/restic`)
- **OneDrive** - Cloud storage backend
- **git-annex** - Large file management (optional)

## Common Tasks

### Update Active Backup Scripts
```bash
# 1. Edit in this repo
vim scripts/backup/quarterly_tar_backup.sh

# 2. Copy to active location
cp scripts/backup/*.sh ~/scripts/system/

# 3. Copy to data directory for cloud sync
cp scripts/backup/*.sh ~/cloudsync-managed/scripts/system/

# 4. Commit changes
git add scripts/backup/
git commit -m "Update backup scripts"
git push

# 5. Sync to OneDrive
rclone sync ~/cloudsync-managed/ onedrive:cloudsync-managed
```

### Check Backup Status
```bash
# Check restic repository
export RESTIC_PASSWORD="acordlessblorpwalksintoabar"
export RESTIC_REPOSITORY="/mnt/d/wsl_backups/restic_repo"
~/.local/bin/restic snapshots

# Check disk usage
df -h /mnt/c /mnt/d

# View backup logs
tail -50 ~/.backup_logs/restic_weekly.log
```

## Known Issues / Gotchas

### Script Location Confusion
- **Problem:** Three different script locations can get out of sync
- **Solution:** Always update all three locations when modifying backup scripts
- **Order:** Edit in repo → Copy to `~/scripts/` → Copy to `~/cloudsync-managed/` → Commit & sync

### CloudSync Auto-Backup Broken
- **Issue:** `cloudsync-auto-backup.sh` expects git repo in `~/cloudsync-managed/`
- **Status:** Cron job failing since Oct 6, 2025
- **Workaround:** Use manual `rclone sync` commands
- **Resolution:** Needs script update or removal from cron

### C: Drive Still Shows in Scripts
- **Note:** Some scripts reference `/mnt/c/Dev/wsl_backups/`
- **This is OK:** It's a symlink to `/mnt/d/wsl_backups/`
- **Actual writes:** Go to D: drive automatically
- **Why keep it:** Backwards compatibility with existing configs
