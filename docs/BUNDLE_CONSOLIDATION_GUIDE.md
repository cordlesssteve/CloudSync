# Bundle Consolidation Guide

**Last Updated:** 2025-10-07
**CloudSync Version:** 2.1+

## Overview

Bundle consolidation merges multiple incremental bundles into a single full bundle, improving restore performance and reducing complexity.

## Table of Contents

- [Why Consolidate](#why-consolidate)
- [When to Consolidate](#when-to-consolidate)
- [How to Consolidate](#how-to-consolidate)
- [Monitoring](#monitoring)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)

---

## Why Consolidate

### The Problem

As you make changes to a repository, CloudSync creates incremental bundles to efficiently sync only new commits:

```
repo/
├── full.bundle (1 GB, commits 1-500)
├── incremental-001.bundle (5 MB, commits 501-510)
├── incremental-002.bundle (8 MB, commits 511-525)
├── incremental-003.bundle (12 MB, commits 526-545)
└── ... (more incrementals)
```

After months of development, you might have 10-20 incremental bundles.

### Impact on Restore

**Restore time increases:**
- **Full bundle only:** 30 seconds
- **10 incremental bundles:** 2-3 minutes
- **20 incremental bundles:** 5-10 minutes

**Reliability decreases:**
- More files = more potential failure points
- Missing/corrupted incremental breaks entire chain
- OneDrive sync issues more likely

### The Solution

Consolidation creates a new full bundle containing all commits, then archives the old bundles:

```
# Before (13 files)
repo/
├── full.bundle (1 GB)
├── incremental-001.bundle (5 MB)
├── ... (10 more incrementals)

# After (1 file + archive)
repo/
├── full.bundle (1.2 GB)  ← New full bundle
├── .archive-20251007/    ← Old bundles preserved
│   ├── full.bundle
│   ├── incremental-001.bundle
│   └── ...
└── bundle-manifest.json (incremental_count: 0)
```

**Benefits:**
- ✅ Fast restore (single bundle to fetch and apply)
- ✅ Simple integrity verification
- ✅ Fewer OneDrive files (better sync reliability)
- ✅ Smaller storage (Git repacks more efficiently)

---

## When to Consolidate

### Automatic Warnings

CloudSync automatically checks for consolidation needs during weekly restore verification (Sundays 4:30 AM).

**You'll receive a notification when:**
- Repository has 10+ incremental bundles (default threshold)

**Example notification:**
```
⚠️ CloudSync: Bundle Consolidation Recommended

2 repositories have 10+ incremental bundles:
  - Work/large-project
  - Utility/active-development

Run consolidation to improve restore performance.
```

### Manual Check

Check consolidation status anytime:

```bash
# Run restore verification (includes consolidation check)
~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/verify-restore.sh
```

**Sample output:**
```
=== Consolidation Health Check ===
Checking all repositories for consolidation needs...
Threshold: 10 incremental bundles

⚠ Work/large-project: 12 incremental bundles (threshold: 10)
✓ Work/stable-project: 3 incremental bundles
✓ Utility/small-tool: 0 incremental bundles (full bundle)

Checked 51 repositories
```

### Good Indicators to Consolidate

✅ **Consolidate when:**
- Incremental count ≥ 10
- Restore is noticeably slower
- Monthly/quarterly maintenance window
- Before important milestone or release

❌ **Not necessary when:**
- Incremental count < 5
- Repository rarely changes
- Recently consolidated (< 1 month ago)

---

## How to Consolidate

### Basic Consolidation

**Command:**
```bash
~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/git-bundle-sync.sh consolidate <repo>
```

**Examples:**
```bash
# Using absolute path
./scripts/bundle/git-bundle-sync.sh consolidate ~/projects/Work/spaceful

# Using relative path (from ~/projects)
./scripts/bundle/git-bundle-sync.sh consolidate Work/spaceful
```

### What Happens During Consolidation

1. **Verification:**
   - Checks bundle directory and manifest exist
   - Verifies repository is valid
   - Confirms incremental bundles present

2. **Archival:**
   - Creates `.archive-YYYYMMDD-HHMMSS/` directory
   - Moves all existing bundles to archive
   - Backs up old manifest

3. **Consolidation:**
   - Creates new full bundle with all commits
   - Tags current HEAD with tracking tag
   - Updates manifest with reset incremental_count

4. **Sync to Cloud:**
   - Uploads new full bundle to OneDrive
   - Deletes old incrementals from remote
   - Preserves archive locally only

5. **Completion:**
   - Logs consolidation to manifest history
   - Reports final bundle size and stats

### Example Output

```
[2025-10-07 22:04:23] =========================================
[2025-10-07 22:04:23] Consolidating bundles for: Work/spaceful
[2025-10-07 22:04:23] Current incremental bundles: 12
[2025-10-07 22:04:23] Archiving old bundles to: .archive-20251007-220423
[2025-10-07 22:04:23] Creating new consolidated full bundle...
[2025-10-07 22:04:25] ✓ Consolidated bundle created: 1.2G
[2025-10-07 22:04:25] Syncing consolidated bundle to OneDrive...
[2025-10-07 22:04:50] ✓ Consolidated bundle synced to remote
[2025-10-07 22:04:50] =========================================
[2025-10-07 22:04:50] ✓ Consolidation complete for: Work/spaceful
[2025-10-07 22:04:50] Previous incrementals: 12
[2025-10-07 22:04:50] New bundle size: 1.2G
[2025-10-07 22:04:50] Old bundles archived in: .archive-20251007-220423
[2025-10-07 22:04:50] =========================================
```

---

## Monitoring

### Check Incremental Count

**View manifest:**
```bash
cat ~/.cloudsync/bundles/Work/spaceful/bundle-manifest.json | jq '.incremental_count'
```

**Output:**
```
0  ← Freshly consolidated
```

### View Consolidation History

```bash
cat ~/.cloudsync/bundles/Work/spaceful/bundle-manifest.json | jq '.consolidation_history'
```

**Output:**
```json
[
  {
    "date": "2025-10-08T03:04:25Z",
    "previous_incremental_count": 12,
    "archive_dir": ".archive-20251007-220423"
  }
]
```

### Check Archives

```bash
ls -lh ~/.cloudsync/bundles/Work/spaceful/.archive-*/
```

**Output:**
```
.archive-20251007-220423/:
total 1.2G
-rw-r--r-- 1 user user  683 Oct  7 22:04 bundle-manifest.json.bak
-rw-r--r-- 1 user user 1.0G Oct  7 19:05 full.bundle
-rw-r--r-- 1 user user  5M Oct  7 19:26 incremental-001.bundle
-rw-r--r-- 1 user user  8M Oct  7 19:45 incremental-002.bundle
```

### Weekly Monitoring

Consolidation health check runs automatically:
- **Schedule:** Every Sunday at 4:30 AM
- **Action:** Checks all repositories
- **Threshold:** 10 incremental bundles (default)
- **Notification:** Warns if consolidation needed

---

## Configuration

### Consolidation Threshold

**File:** `~/projects/Utility/LOGISTICAL/CloudSync/config/bundle-sync.conf`

```bash
# Alert threshold: Warn when incremental count exceeds this value
# Recommended: 10-15 for most repos
CONSOLIDATION_THRESHOLD=10

# Auto-consolidate repos that exceed threshold
# If true, consolidation runs automatically during weekly maintenance
# If false, only send warnings (manual consolidation required)
AUTO_CONSOLIDATE=false

# Auto-consolidate schedule (if AUTO_CONSOLIDATE=true)
# Options: weekly, monthly, never
AUTO_CONSOLIDATE_SCHEDULE=weekly

# Preserve old bundles after consolidation
# If true, moves old bundles to archive directory
# If false, deletes old bundles after successful consolidation
PRESERVE_OLD_BUNDLES=true

# Archive directory for old bundles (if PRESERVE_OLD_BUNDLES=true)
BUNDLE_ARCHIVE_DIR="${BUNDLE_DIR}/.archive"
```

### Adjust Threshold

**Smaller threshold (more frequent consolidation):**
```bash
CONSOLIDATION_THRESHOLD=5
```

**Larger threshold (less frequent consolidation):**
```bash
CONSOLIDATION_THRESHOLD=20
```

---

## Troubleshooting

### Consolidation Failed

**Error:** `Failed to create consolidated bundle`

**Causes:**
- Corrupted repository
- Git errors
- Insufficient disk space

**Solution:**
```bash
# 1. Check repository health
cd ~/projects/Work/spaceful
git fsck

# 2. Check disk space
df -h ~/.cloudsync/bundles

# 3. Try consolidation again
./scripts/bundle/git-bundle-sync.sh consolidate Work/spaceful
```

**If consolidation fails, old bundles are automatically restored.**

### Cannot Find Repository

**Error:** `Repository not found: Work/spaceful`

**Solution:**
```bash
# Use absolute path instead
./scripts/bundle/git-bundle-sync.sh consolidate ~/projects/Work/spaceful

# Or check if path is correct
ls ~/projects/Work/spaceful/.git
```

### Sync to OneDrive Failed

**Error:** `Failed to sync consolidated bundle to remote`

**Causes:**
- OneDrive offline
- Network issues
- Insufficient OneDrive space

**Solution:**
```bash
# 1. Check OneDrive connection
rclone about onedrive:

# 2. Retry consolidation (bundle is already created)
./scripts/bundle/git-bundle-sync.sh consolidate Work/spaceful
```

### Archive Directory Too Large

**Problem:** Archive directories accumulate over time

**Solution:**
```bash
# List all archives
find ~/.cloudsync/bundles -name ".archive-*" -type d

# Delete old archives (older than 90 days)
find ~/.cloudsync/bundles -name ".archive-*" -type d -mtime +90 -exec rm -rf {} +

# Or manually delete specific archive
rm -rf ~/.cloudsync/bundles/Work/spaceful/.archive-20251007-220423
```

---

## Best Practices

1. **Consolidate during low-activity periods** (weekends, after-hours)
2. **Verify consolidation success** before deleting archives
3. **Keep at least one recent archive** for rollback capability
4. **Monitor weekly notifications** and consolidate promptly
5. **Test restore after consolidation** to confirm integrity

---

## Advanced Usage

### Batch Consolidation

Consolidate multiple repositories:

```bash
#!/bin/bash
# consolidate-all.sh

for repo in Work/spaceful Work/large-project Utility/active-tool; do
    echo "Consolidating: $repo"
    ./scripts/bundle/git-bundle-sync.sh consolidate "$repo"
done
```

### Scheduled Auto-Consolidation

**Enable in config:**
```bash
AUTO_CONSOLIDATE=true
AUTO_CONSOLIDATE_SCHEDULE=weekly
```

**Manually trigger weekly consolidation:**
```bash
# Add to cron (runs after weekly verification)
0 5 * * 0 ~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/auto-consolidate.sh
```

---

## Summary

**Bundle consolidation:**
- ✅ Improves restore performance (30 seconds vs 5+ minutes)
- ✅ Increases reliability (fewer failure points)
- ✅ Simplifies bundle management (1 file vs 10+)
- ✅ Reduces OneDrive sync issues (fewer files)

**When to consolidate:**
- Automatically warned at 10+ incremental bundles
- Weekly health check during restore verification
- Before important milestones or releases

**How to consolidate:**
```bash
./scripts/bundle/git-bundle-sync.sh consolidate <repo_path>
```

**Next steps:**
1. Wait for weekly consolidation health check
2. Consolidate when warned
3. Verify restore after consolidation
4. Archive management (delete old archives periodically)

For more information, see:
- [BACKUP_SYSTEMS_OVERVIEW.md](./BACKUP_SYSTEMS_OVERVIEW.md) - Complete backup documentation
- [NOTIFICATIONS_AND_MONITORING.md](./NOTIFICATIONS_AND_MONITORING.md) - Notification setup
- [FEATURE_BACKLOG.md](./FEATURE_BACKLOG.md) - Future enhancements
