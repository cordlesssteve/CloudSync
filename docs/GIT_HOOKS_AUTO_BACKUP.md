# Git Hooks Auto-Backup Guide

**Last Updated:** 2025-10-07
**CloudSync Version:** 2.2+

## Overview

CloudSync includes automatic backup via git hooks - your commits are automatically backed up to OneDrive within 10 minutes, with no manual intervention required.

## Table of Contents

- [How It Works](#how-it-works)
- [Installation](#installation)
- [Usage](#usage)
- [Monitoring](#monitoring)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)

---

## How It Works

### Automatic Backup Workflow

```
You make a commit
    ↓
Git executes post-commit hook
    ↓
Hook starts 10-minute debounce timer
    ↓
You make another commit (timer resets)
    ↓
10 minutes pass with no new commits
    ↓
Hook triggers CloudSync bundle sync
    ↓
Repository backed up to OneDrive
    ↓
You receive success notification
```

### 10-Minute Debounce

**Why 10 minutes?**
- Prevents excessive syncs during active development
- Allows you to make multiple commits without triggering sync each time
- Balances responsiveness with efficiency

**Example timeline:**
```
2:00 PM - Commit #1 (timer starts: 2:10 PM)
2:03 PM - Commit #2 (timer resets: 2:13 PM)
2:05 PM - Commit #3 (timer resets: 2:15 PM)
2:08 PM - Commit #4 (timer resets: 2:18 PM)
2:10 PM - (stop committing)
2:20 PM - Timer expires, sync triggers
2:22 PM - Backup complete!
```

**Result:** 4 commits backed up in single sync operation

### Background Execution

**Important:** Commits complete instantly
- Hook runs in background (doesn't block your commit)
- No waiting for backup to complete
- Continue working immediately

---

## Installation

### Quick Install (All Repositories)

```bash
# Install hooks in all git repositories
cd ~/projects/Utility/LOGISTICAL/CloudSync
./scripts/hooks/install-git-hooks.sh
```

**Output:**
```
✓ Git hooks successfully installed/updated in 50 repositories
ℹ Auto-backup is now enabled with 10-minute debounce
```

### Manual Install (Single Repository)

```bash
# Copy hook to specific repository
cp ~/projects/Utility/LOGISTICAL/CloudSync/scripts/hooks/post-commit \
   ~/projects/Work/my-repo/.git/hooks/post-commit

chmod +x ~/projects/Work/my-repo/.git/hooks/post-commit
```

### Verify Installation

```bash
# Check if hook is installed
ls -la ~/projects/Work/spaceful/.git/hooks/post-commit

# Should show: -rwxr-xr-x ... post-commit
```

---

## Usage

### Make Commits as Normal

```bash
cd ~/projects/Work/spaceful

# Work on your code
vim src/app.js

# Commit normally
git commit -m "Add new feature"

# Output:
# [main abc1234] Add new feature
#  1 file changed, 50 insertions(+)
# CloudSync: Auto-backup scheduled in 10 minutes
```

**That's it!** Backup happens automatically.

### Multiple Commits

```bash
# Make several commits
git commit -m "Add feature part 1"
git commit -m "Add feature part 2"
git commit -m "Add feature part 3"

# All 3 commits backed up together after 10 minutes
```

### Immediate Backup (Skip Debounce)

If you want immediate backup without waiting 10 minutes:

```bash
# Manual sync (bypasses hook debounce)
~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/git-bundle-sync.sh test ~/projects/Work/spaceful
```

---

## Monitoring

### Watch Hook Activity

```bash
# Monitor hook log in real-time
tail -f ~/.cloudsync/logs/hook-sync.log
```

**Sample output:**
```
[2025-10-07 22:14:56] [spaceful] Commit detected, debounce timer started (600s)
[2025-10-07 22:14:56] [spaceful] Auto-backup scheduled (will run in 600s if no more commits)
[2025-10-07 22:24:56] [spaceful] Debounce timer expired, triggering sync...
[2025-10-07 22:24:58] [INFO] Creating bundle for: Work/spaceful
[2025-10-07 22:25:00] [INFO] ✓ Bundle created: 68M
[2025-10-07 22:25:15] [INFO] ✓ Synced to OneDrive
[2025-10-07 22:25:15] [spaceful] ✓ Auto-backup completed successfully
```

### Check Lock Files

```bash
# See which repositories have pending backups
ls -la /tmp/cloudsync-hook-locks/

# Each .lock file represents a repository with active debounce timer
```

### View Last Backup Time

```bash
# Check when repository was last backed up
cat ~/.cloudsync/bundles/Work/spaceful/bundle-manifest.json | jq '.bundles[-1].timestamp'

# Output: "2025-10-07T22:25:15Z"
```

---

## Configuration

### Adjust Debounce Delay

**Edit hook script:**
```bash
# Open hook in editor
vim ~/projects/Utility/LOGISTICAL/CloudSync/scripts/hooks/post-commit

# Find this line (near top):
DEBOUNCE_DELAY=600  # 10 minutes in seconds

# Change to desired delay:
DEBOUNCE_DELAY=300   # 5 minutes
DEBOUNCE_DELAY=1800  # 30 minutes
```

**After editing, reinstall hooks:**
```bash
cd ~/projects/Utility/LOGISTICAL/CloudSync
./scripts/hooks/install-git-hooks.sh
```

### Disable Hook for Specific Repository

```bash
# Temporarily disable
cd ~/projects/Work/spaceful
mv .git/hooks/post-commit .git/hooks/post-commit.disabled

# Re-enable
mv .git/hooks/post-commit.disabled .git/hooks/post-commit
```

### Disable Notifications

Edit hook script and comment out notification lines:

```bash
# Find these lines in scripts/hooks/post-commit:
# if [[ -x "$NOTIFY_SCRIPT" ]]; then
#     "$NOTIFY_SCRIPT" success ...
# fi

# Comment them out to disable notifications
```

---

## Troubleshooting

### Hook Not Running

**Check if hook is installed:**
```bash
ls -la ~/projects/Work/spaceful/.git/hooks/post-commit
```

**Check if hook is executable:**
```bash
# Should show: -rwxr-xr-x
# If not, make it executable:
chmod +x ~/projects/Work/spaceful/.git/hooks/post-commit
```

**Test hook manually:**
```bash
cd ~/projects/Work/spaceful
.git/hooks/post-commit
```

### Backup Not Triggering

**Check hook log:**
```bash
tail -50 ~/.cloudsync/logs/hook-sync.log
```

**Common issues:**

1. **Timer still running:**
   ```
   [spaceful] Auto-backup scheduled (will run in 600s if no more commits)
   ```
   Solution: Wait for timer to expire (10 minutes)

2. **CloudSync script not found:**
   ```
   ERROR: CloudSync script not found or not executable
   ```
   Solution: Verify CloudSync installation
   ```bash
   ls -la ~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/git-bundle-sync.sh
   ```

3. **Permission denied:**
   ```
   ERROR: Permission denied
   ```
   Solution: Make scripts executable
   ```bash
   chmod +x ~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/*.sh
   ```

### Backup Fails

**Check error in hook log:**
```bash
grep "ERROR\|failed" ~/.cloudsync/logs/hook-sync.log
```

**Check bundle sync log:**
```bash
tail -50 ~/.cloudsync/logs/bundle-sync.log
```

**Common causes:**
- OneDrive offline/unreachable
- Insufficient disk space
- Repository corruption
- Network issues

**Test manual sync:**
```bash
~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/git-bundle-sync.sh test ~/projects/Work/spaceful
```

### Multiple Timers Running

**Symptom:** Multiple sync operations for same repo

**Check running processes:**
```bash
ps aux | grep debounce_worker
```

**Solution:** The hook design prevents this automatically:
- Each new commit updates timestamp
- Old timers check timestamp before running
- Only newest timer will actually trigger sync

**Manual cleanup (if needed):**
```bash
rm /tmp/cloudsync-hook-locks/spaceful.lock
```

### Hook Disabled After Git Update

Some git operations may remove hooks. Reinstall:

```bash
cd ~/projects/Utility/LOGISTICAL/CloudSync
./scripts/hooks/install-git-hooks.sh
```

---

## Advanced Usage

### Batch Reinstall Hooks

```bash
# Reinstall hooks in all repositories
cd ~/projects/Utility/LOGISTICAL/CloudSync
./scripts/hooks/install-git-hooks.sh

# View installation log
cat ~/.cloudsync/logs/hook-install.log
```

### Custom Hook Per Repository

You can customize the hook for specific repositories:

```bash
cd ~/projects/Work/important-project

# Edit hook directly
vim .git/hooks/post-commit

# Example: Reduce debounce to 1 minute for this repo
DEBOUNCE_DELAY=60  # instead of 600
```

### Trigger Sync Immediately After Commit

Add this to a specific repository's hook:

```bash
# In .git/hooks/post-commit, change:
DEBOUNCE_DELAY=0  # No debounce, immediate sync
```

**Warning:** This will sync after every single commit (can be slow during active development)

---

## Integration with Workflow

### Development Workflow

**Morning startup:**
```bash
# No action needed - hooks already installed
# Just work normally
```

**During development:**
```bash
git commit -m "Feature A"  # Timer starts
git commit -m "Feature B"  # Timer resets
git commit -m "Feature C"  # Timer resets
# ... 10 minutes of silence ...
# Auto-backup triggers automatically
```

**End of day:**
```bash
git commit -m "Final changes"
# Wait 10 minutes or manually sync:
~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/git-bundle-sync.sh test $(pwd)

# All work backed up to OneDrive
```

### Combined with Scheduled Sync

**Best practice:** Use both hooks and scheduled sync

- **Git hooks:** Immediate backup (within 10 min of commit)
- **Scheduled sync (1 AM):** Safety net backup of all repos

**Benefit:** Double protection
1. Hook backs up active repos immediately
2. Scheduled sync ensures everything is backed up daily

---

## Performance Impact

### Resource Usage

**CPU:** Minimal
- Only runs when you commit
- Background execution
- ~1-2 seconds CPU time per sync

**Memory:** Minimal
- Small bash script (~100KB)
- No persistent daemon

**Network:** Moderate
- Only syncs changed repositories
- Incremental bundles are small (KB-MB)
- Full bundles for first sync (MB-GB)

**Disk I/O:** Low
- Bundle creation: temporary disk usage
- Cleaned up after sync

### Battery Impact (Laptops)

**Negligible:**
- No continuous background process
- Only runs on commit
- Network sync may use battery, but only briefly

---

## Comparison: Hooks vs Scheduled Sync

| Aspect | Git Hooks | Scheduled Sync (1 AM) |
|--------|-----------|------------------------|
| **Trigger** | On commit | Daily at 1 AM |
| **Delay** | 10 minutes | Up to 24 hours |
| **Risk Window** | 10 minutes | 24 hours |
| **Repos Synced** | Only committed repos | All repos |
| **Setup** | Install hooks once | Configure cron once |
| **Reliability** | High (per-repo) | Very high (system-wide) |
| **Resource Usage** | Per-commit | Daily batch |
| **Best For** | Active development | Comprehensive backup |

**Recommendation:** Use both for maximum protection

---

## Summary

**Git Hooks Auto-Backup provides:**
- ✅ Automatic backup within 10 minutes of commit
- ✅ Smart debouncing (multiple commits = single sync)
- ✅ Background execution (doesn't block commits)
- ✅ Integrated notifications
- ✅ Zero configuration after installation
- ✅ Works with existing CloudSync infrastructure

**Quick Start:**
```bash
# Install hooks
cd ~/projects/Utility/LOGISTICAL/CloudSync
./scripts/hooks/install-git-hooks.sh

# Make commits as normal
cd ~/projects/Work/my-project
git commit -m "My changes"

# Backup happens automatically in 10 minutes!
```

**Monitor:**
```bash
tail -f ~/.cloudsync/logs/hook-sync.log
```

For more information, see:
- [NOTIFICATIONS_AND_MONITORING.md](./NOTIFICATIONS_AND_MONITORING.md) - Notification setup
- [BACKUP_SYSTEMS_OVERVIEW.md](./BACKUP_SYSTEMS_OVERVIEW.md) - Complete backup documentation
