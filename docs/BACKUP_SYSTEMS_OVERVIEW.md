# CloudSync Backup Systems Overview

CloudSync has **three separate backup systems** that work together to protect different types of data. Each runs on its own schedule with anacron catch-up.

---

## 1. Git Bundle Sync (NEW)
**Schedule:** Daily at 1:00 AM
**Anacron:** Catches up if missed in last 1 day
**Script:** `scripts/bundle/git-bundle-sync.sh`

### What Gets Backed Up:
✅ **All git repositories** in `~/projects/` (51 repos currently)
- **Small repos (< 100MB):** Full git bundle created each time
- **Medium repos (100-500MB):** Incremental bundles (only new commits)
- **Large repos (> 500MB):** Incremental bundles (only new commits)
- **Critical .gitignored files:** `.env`, credentials, certificates, API keys

### What Gets Synced to OneDrive:
Each repository creates 4-6 files:
1. `repo.bundle` (full or incremental git bundle)
2. `bundle-manifest.json` (tracks all bundles and commit ranges)
3. `critical-ignored.tar.gz` (archived sensitive files)
4. `critical-ignored.list` (list of archived files)
5. Timestamp files

### OneDrive Location:
`onedrive:DevEnvironment/bundles/Category/RepoName/`

### Local Storage:
`~/.cloudsync/bundles/Category/RepoName/`

### Logs:
- Success: `~/.cloudsync/logs/cron-sync.log`
- Errors: `~/.cloudsync/logs/cron-errors.log`
- Detailed: `~/.cloudsync/logs/bundle-sync.log`

### Key Features:
- **Incremental by default** for medium/large repos (only new commits)
- **Auto-consolidation** after 10 incrementals or 30 days
- **Dramatically reduces API calls** (4-6 files vs thousands)
- **Preserves critical secrets** that would normally be gitignored

---

## 2. Managed Storage Backup
**Schedule:** Daily at 3:00 AM (Mon-Sat), 2:30 AM (Sunday in suite)
**Anacron:** Catches up if missed in last 1 day
**Script:** `~/scripts/cloud/cloudsync-auto-backup.sh`

### What Gets Backed Up:
✅ **All files in `~/csync-managed/`**
- Documents, media, configuration files
- Any non-git-repo content you want versioned
- Git commits changes automatically before sync

### What Gets Synced to OneDrive:
- **Entire managed directory** via rclone
- Uses Git for versioning, rclone for transport
- Bidirectional sync (changes flow both ways)

### OneDrive Location:
`onedrive:DevEnvironment/managed/`

### Local Storage:
`~/csync-managed/` (Git repository)

### Logs:
`~/.cloudsync/logs/auto-backup.log`

### Key Features:
- **Unified versioning** for all file types (Git-based)
- **Bidirectional sync** (OneDrive ↔ Local)
- **Conflict resolution** built-in
- **Smart tool selection** (Git/Git-annex/rclone based on file type)

---

## 3. Weekly Backup Suite
**Schedule:** Sundays at 2:30 AM
**Anacron:** Catches up if missed in last 7 days
**Script:** `~/scripts/cloud/weekly-backup-suite.sh`

### What Gets Backed Up:
✅ **Restic backup** (full system backup)
✅ **Managed storage sync** (same as #2 above)

### Components:
1. Runs `weekly_restic_backup.sh` first
2. Runs managed storage sync second
3. Logs both operations

### Logs:
`~/.cloudsync/logs/backup-suite.log`

---

## Backup System Comparison

| Feature | Git Bundle Sync | Managed Storage | Weekly Suite |
|---------|----------------|-----------------|--------------|
| **Target** | Git repositories | ~/csync-managed/ | System + managed |
| **Frequency** | Daily (1 AM) | Daily (3 AM) | Weekly (Sun 2:30 AM) |
| **Method** | Git bundles | rclone bidirectional | Restic + rclone |
| **Incremental** | Yes (medium/large repos) | Yes (changed files only) | Restic incremental |
| **OneDrive API Calls** | Minimal (4-6 files/repo) | Per-file changes | Per-file changes |
| **Versioning** | Git commits in bundle | Git commits in managed | Restic snapshots |
| **Secrets Backup** | Yes (.env, certs, etc.) | Yes (if in managed) | Yes (full system) |
| **Catch-up** | Anacron (1 day) | Anacron (1 day) | Anacron (7 days) |

---

## Anacron Catch-Up Process

**How it works:**
1. Cron runs anacron **every 6 hours** + **daily at 8 AM**
2. Anacron checks timestamp files in `~/.anacron-spool/`
3. If a job hasn't run within its period, anacron runs it
4. Each job has a delay to avoid overwhelming the system

**Current Anacron Jobs:**
```
Job Name                Period  Delay  Script
-------------------     ------  -----  ------
git_bundle_sync         1 day   2 min  cron-wrapper.sh
cloudsync_daily         1 day   3 min  cloudsync-auto-backup.sh
cloudsync_weekly        7 days  8 min  weekly-backup-suite.sh
weekly_restic_backup    7 days  5 min  weekly_restic_backup.sh
quarterly_tar_backup    90 days 10 min quarterly_tar_backup.sh
claude_tree_snapshot    7 days  2 min  tree snapshot command
```

**View catch-up status:**
```bash
ls -la ~/.anacron-spool/
```

**Test anacron manually:**
```bash
anacron -t ~/.anacrontab -S ~/.anacron-spool -d -f
```

---

## What Happens If System is Offline?

**Example: System offline for 3 days**

1. **Git bundle sync** - Will run within 6 hours of system coming online (anacron)
2. **Managed storage sync** - Will run within 6 hours of system coming online
3. **Weekly suite** - Will run within 6 hours if Sunday was missed

**Why this works:**
- Anacron checks every 6 hours via cron
- Timestamp files track last run date
- Jobs run with delays to avoid conflicts
- Multiple redundant catch-up windows (6hr + 8 AM)

---

## Monitoring Your Backups

**Check recent git bundle syncs:**
```bash
tail -50 ~/.cloudsync/logs/cron-sync.log
```

**Check for errors:**
```bash
cat ~/.cloudsync/logs/cron-errors.log
```

**Check managed storage syncs:**
```bash
tail -50 ~/.cloudsync/logs/auto-backup.log
```

**Check weekly suite:**
```bash
tail -50 ~/.cloudsync/logs/backup-suite.log
```

**View all CloudSync cron jobs:**
```bash
crontab -l | grep -i cloudsync
```

**Check anacron timestamps:**
```bash
ls -lt ~/.anacron-spool/
```

---

## Summary: What's Protected?

✅ **Git Repositories** - Full history + critical secrets (git bundle sync)
✅ **Managed Files** - Documents, media, configs (managed storage sync)
✅ **Full System** - Weekly Restic snapshots (weekly suite)

**Three layers of protection:**
1. Daily incremental backups (bundles + managed)
2. Weekly full suite (Restic + managed)
3. Anacron catch-up (never miss a backup)

**Maximum data loss window:**
- Git repos: 24 hours (daily bundle sync)
- Managed files: 24 hours (daily sync)
- System: 7 days (weekly Restic)

All with automatic catch-up if system is offline.
