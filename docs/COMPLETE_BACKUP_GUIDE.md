# CloudSync Complete Backup & Restore Guide

**Version:** 3.0
**Status:** PRODUCTION ACTIVE
**Last Updated:** 2025-10-15
**Purpose:** Crystal-clear documentation for ALL CloudSync backup systems

---

## 📚 Table of Contents

1. [System Overview](#system-overview)
2. [Backup Systems Matrix](#backup-systems-matrix)
3. [Git Bundle Sync](#git-bundle-sync)
4. [Non-Git Bundle Archives](#non-git-bundle-archives)
5. [Dev Environment Sync](#dev-environment-sync)
6. [Unified Restore System](#unified-restore-system)
7. [Quick Reference Commands](#quick-reference-commands)
8. [Troubleshooting](#troubleshooting)

---

## 🎯 System Overview

CloudSync uses **four complementary backup systems** to protect your data:

| System | What It Backs Up | Technology | Frequency |
|--------|------------------|------------|-----------|
| **Git Bundle Sync** | All git repositories (60+ repos) | Git bundles | Daily |
| **Non-Git Archives** | backups/, media/, .local/bin/ | Compressed tar archives | Weekly |
| **Dev Environment Sync** | SSH keys, configs, scripts | Individual file sync | On-demand |
| **System Backups** | Entire home directory | Restic + TAR | Weekly/Quarterly |

**Why multiple systems?**
- Git bundles: Efficient for version-controlled projects
- Archives: Efficient for large non-git directories (reduces 50,000 API calls → 2)
- Dev sync: Real-time protection for critical configs
- System backups: Full disaster recovery

---

## 📊 Backup Systems Matrix

### What Gets Backed Up Where

```
~/
├── projects/                    → GIT BUNDLE SYNC (60+ repos)
│   ├── Work/spaceful/.git      → Git bundle
│   ├── Utility/CloudSync/.git  → Git bundle
│   └── ... (all git repos)
│
├── backups/                     → NON-GIT ARCHIVE
│   └── restic_repo/            → Compressed weekly
│
├── media/                       → NON-GIT ARCHIVE
│   └── photos/videos/          → Compressed weekly
│
├── .local/bin/                  → NON-GIT ARCHIVE
│   └── custom-scripts          → Compressed weekly
│
├── .ssh/                        → DEV ENVIRONMENT SYNC
├── scripts/                     → DEV ENVIRONMENT SYNC
├── mcp-servers/                 → DEV ENVIRONMENT SYNC
├── docs/                        → DEV ENVIRONMENT SYNC
├── .gnupg/                      → DEV ENVIRONMENT SYNC (NEW!)
├── .pki/                        → DEV ENVIRONMENT SYNC (NEW!)
├── .secrets/                    → DEV ENVIRONMENT SYNC (NEW!)
│
├── .gitconfig                   → DEV ENVIRONMENT SYNC
├── .bash_aliases                → DEV ENVIRONMENT SYNC
├── .cloudsync-secrets.conf      → DEV ENVIRONMENT SYNC (NEW!)
│
└── (everything)                 → RESTIC BACKUP (weekly)
```

---

## 📦 Git Bundle Sync

### Purpose
Backs up all git repositories as single bundle files instead of thousands of individual files. Dramatically reduces OneDrive API calls and sync time.

### What It Does
- Finds all repos in `~/projects/` automatically
- Creates git bundles (full + incrementals)
- Tracks with manifest.json
- Consolidates after 10 incrementals or 30 days
- Syncs to `onedrive:DevEnvironment/bundles/`

### Usage

```bash
# Manual sync (auto-runs daily via anacron)
~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/git-bundle-sync.sh

# Sync all repos
./git-bundle-sync.sh

# Sync specific repo (test mode)
./git-bundle-sync.sh test ~/projects/Work/spaceful

# Check status
./git-bundle-sync.sh status

# Consolidate all incrementals
./git-bundle-sync.sh consolidate Work/spaceful
```

### Location
- **Script:** `~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/git-bundle-sync.sh`
- **Local bundles:** `~/.cloudsync/bundles/<repo-name>/`
- **OneDrive:** `onedrive:DevEnvironment/bundles/<repo-name>/`
- **Log:** `~/.cloudsync/logs/bundle-sync.log`

### Schedule
- **Anacron:** Runs daily (catches up if missed)
- **Entry:** `1 2 git_bundle_sync /path/to/cron-wrapper.sh`

### Output
```
~/.cloudsync/bundles/Work/spaceful/
├── full.bundle                  # Full git history
├── incremental-20251015.bundle  # Changes since full
├── incremental-20251016.bundle  # Recent changes
└── bundle-manifest.json         # Tracking metadata
```

---

## 🗄️ Non-Git Bundle Archives

### Purpose
Backs up large non-git directories as compressed archives. Same bundle concept as git repos, but for regular directories.

### What It Does
- Archives `~/backups/`, `~/media/`, `~/.local/bin/`
- Creates compressed tar.zst files (full + incrementals)
- Tracks with manifest.json (includes source paths!)
- Consolidates after 10 incrementals or 30 days
- Syncs to OneDrive

### Usage

```bash
# Manual sync (auto-runs weekly via anacron)
~/scripts/system/non-git-bundle-sync.sh

# Sync all configured directories
./non-git-bundle-sync.sh sync

# Sync specific directory
./non-git-bundle-sync.sh sync-dir ~/backups

# List configured directories
./non-git-bundle-sync.sh list

# Check status
./non-git-bundle-sync.sh status
```

### Configuration

Edit the script to add more directories:
```bash
NON_GIT_DIRS=(
    "$HOME/backups"
    "$HOME/media"
    "$HOME/.local/bin"
    # Add more here
)
```

### Location
- **Script:** `~/scripts/system/non-git-bundle-sync.sh`
- **Source:** `~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/non-git-bundle-sync.sh`
- **Local archives:** `~/.cloudsync/bundles/<dirname>/`
- **OneDrive:** `onedrive:DevEnvironment/bundles/<dirname>/`
- **Log:** `~/.cloudsync/logs/non-git-bundle-sync.log`

### Schedule
- **Anacron:** Runs weekly (7-day catchup)
- **Entry:** `7 5 non_git_bundle_sync /path/to/script.sh`

### Output
```
~/.cloudsync/bundles/backups/
├── backups-full-20251015.tar.zst
├── backups-incremental-20251016.tar.zst
└── bundle-manifest.json
```

### Manifest Example
```json
{
  "source_path": "/home/cordlesssteve/backups",
  "hostname": "DESKTOP-OO6C62K",
  "archive_type": "non-git-directory",
  "archives": [
    {
      "type": "full",
      "filename": "backups-full-20251015.tar.zst",
      "source_path": "/home/cordlesssteve/backups",
      "size": 6442450944,
      "files_count": 1234,
      "checksum": "sha256:abc123...",
      "compression": "zstd"
    }
  ],
  "restore_instructions": {
    "target_path": "/home/cordlesssteve/backups",
    "order": ["backups-full-20251015.tar.zst"]
  }
}
```

---

## 🔧 Dev Environment Sync

### Purpose
Real-time protection for critical configuration files, SSH keys, and custom scripts. Uses individual file sync for immediate access.

### What It Does
- Syncs SSH keys, GPG keys, secrets
- Syncs custom scripts and MCP servers
- Syncs config files (.gitconfig, .bashrc, etc.)
- Syncs cloud provider credentials
- Can be run manually anytime

### Usage

```bash
# Manual sync
~/scripts/system/dev-env-sync.sh push

# The script handles everything automatically
```

### What Gets Synced

**CRITICAL_PATHS (directories):**
- `~/.ssh/` - SSH keys
- `~/scripts/` - Custom automation
- `~/mcp-servers/` - Custom MCP code
- `~/docs/` - Documentation
- `~/.claude/templates/` - Templates
- `~/templates/` - Project templates
- `~/.notez/` - Personal notes
- `~/.gnupg/` - GPG keys **[NEW]**
- `~/.pki/` - PKI certs **[NEW]**
- `~/.secrets/` - Secrets folder **[NEW]**
- `~/media/` - Media files **[NEW]**
- `~/backups/` - Backup archives **[NEW]**
- `~/.local/bin/` - All custom scripts **[NEW]**

**CRITICAL_FILES (individual files):**
- `.gitconfig`, `.bash_aliases`, `.bashrc`, `.profile`, `.vimrc`
- `.git-credentials` - GitHub tokens
- `.claude/.credentials.json` - Claude API
- `.cloudsync-secrets.conf` - Centralized secrets **[NEW]**
- `.neo4j.env` - Database password **[NEW]**
- `.npmrc` - NPM auth **[NEW]**
- `.wsl-config`, `.stignore`, `.packj.yaml` **[NEW]**
- `litellm_*.yaml` - LiteLLM configs **[NEW]**
- `.claude.json` - Claude Code config **[NEW]**
- `.gitconfig.local`, `.anacrontab` **[NEW]**

**SELECTIVE_CONFIG (config directories):**
- `.config/rclone/` - Cloud credentials
- `.config/gh/` - GitHub CLI
- `.config/git/` - Git creds
- `.config/syncthing/` - Sync settings
- `.config/claude-code/` - IDE settings
- `.config/Code/`, `.config/gcloud/`, `.config/aws/`, `.config/azure/` **[NEW]**

### Location
- **Script:** `~/scripts/system/dev-env-sync.sh`
- **Source:** `~/projects/Utility/LOGISTICAL/CloudSync/scripts/core/dev-env-sync.sh`
- **OneDrive:** `onedrive:DevEnvironment/<hostname>/essentials/`

### Schedule
- **On-demand only** (run manually when needed)
- Not in anacrontab (too frequent for daily use)

---

## 🔄 Unified Restore System

### Purpose
Single interface to restore BOTH git repositories AND non-git archives. Automatically detects bundle type and restores correctly.

### Usage

```bash
# List all available bundles (git + non-git)
~/scripts/system/unified-restore.sh list

# Download specific bundle from OneDrive
~/scripts/system/unified-restore.sh download backups

# Download all bundles
~/scripts/system/unified-restore.sh download

# Restore to original location (reads from manifest)
~/scripts/system/unified-restore.sh restore backups

# Restore to custom location
~/scripts/system/unified-restore.sh restore backups /tmp/restored-backups

# Restore git repository
~/scripts/system/unified-restore.sh restore Work/spaceful

# Verify bundle integrity
~/scripts/system/unified-restore.sh verify backups
```

### How It Works

1. **Detects bundle type** from manifest.json:
   - `"archive_type": "non-git-directory"` → Extract tar archives
   - `"archive_type": "git-repository"` → Fetch git bundles

2. **Reads source path** from manifest:
   - `"source_path": "/home/cordlesssteve/backups"`

3. **Restores to correct location**:
   - Default: Original source path
   - Override: Specify custom path

4. **Handles incremental restores**:
   - Extracts in order from manifest
   - Full bundle first, then incrementals

### Location
- **Script:** `~/scripts/system/unified-restore.sh`
- **Source:** `~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/unified-restore.sh`
- **Backward compat:** `restore-from-bundle.sh` delegates to this

### Example Output

```bash
$ ./unified-restore.sh list

GIT REPOSITORIES:
================
  📦 Work/spaceful
     Source: /home/cordlesssteve/projects/Work/spaceful
     Commit: a0cf5990
     Bundles: 14

  📦 Utility/CloudSync
     Source: /home/cordlesssteve/projects/Utility/LOGISTICAL/CloudSync
     Commit: 68f9715a
     Bundles: 3

NON-GIT DIRECTORIES:
====================
  📁 backups
     Source: /home/cordlesssteve/backups
     Updated: 2025-10-15T22:00:00Z
     Archives: 2
     Size: 6.0G

  📁 media
     Source: /home/cordlesssteve/media
     Updated: 2025-10-15T22:00:00Z
     Archives: 1
     Size: 1.2G
```

---

## 🚀 Quick Reference Commands

### Daily Operations

```bash
# Check what's backed up (git repos)
find ~/.cloudsync/bundles -name "bundle-manifest.json" | wc -l

# Check what's backed up (non-git)
~/scripts/system/non-git-bundle-sync.sh status

# Manually trigger git bundle sync
~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/git-bundle-sync.sh

# Manually trigger non-git bundle sync
~/scripts/system/non-git-bundle-sync.sh sync

# Manually trigger dev environment sync
~/scripts/system/dev-env-sync.sh push
```

### Restore Operations

```bash
# See everything available
~/scripts/system/unified-restore.sh list

# Download from OneDrive
~/scripts/system/unified-restore.sh download

# Restore specific item
~/scripts/system/unified-restore.sh restore <name>

# Verify integrity
~/scripts/system/unified-restore.sh verify <name>
```

### Monitoring

```bash
# Check anacron jobs
cat ~/.anacrontab

# View recent git bundle sync log
tail -100 ~/.cloudsync/logs/bundle-sync.log

# View recent non-git bundle sync log
tail -100 ~/.cloudsync/logs/non-git-bundle-sync.log

# Check OneDrive usage
rclone about onedrive:

# List remote bundles
rclone lsf onedrive:DevEnvironment/bundles/
```

---

## 🔧 Troubleshooting

### Git Bundle Sync Issues

**Problem:** Repository not being bundled
```bash
# Check if repo is detected
find ~/projects -name ".git" -type d | grep <repo-name>

# Test single repo
./git-bundle-sync.sh test ~/projects/Work/spaceful
```

**Problem:** Bundle verification fails
```bash
# Check bundle integrity
git bundle verify ~/.cloudsync/bundles/<repo>/full.bundle
```

### Non-Git Archive Issues

**Problem:** Directory not being archived
```bash
# Check configuration
~/scripts/system/non-git-bundle-sync.sh list

# Check if directory changed
~/scripts/system/non-git-bundle-sync.sh sync-dir ~/backups
```

**Problem:** Archive extraction fails
```bash
# Verify archive integrity
tar -tzf ~/.cloudsync/bundles/backups/backups-full-*.tar.zst | head

# Check checksum
sha256sum ~/.cloudsync/bundles/backups/backups-full-*.tar.zst
```

### Dev Environment Sync Issues

**Problem:** Files not syncing
```bash
# Check rclone connectivity
rclone lsd onedrive:DevEnvironment/

# Run with verbose output
~/scripts/system/dev-env-sync.sh push
```

### General Issues

**Problem:** OneDrive rate limiting
```bash
# Check sync frequency
grep "bundle_sync\|dev-env-sync" ~/.anacrontab

# Reduce frequency or use bundles (already doing this!)
```

**Problem:** Disk space on local bundles
```bash
# Check bundle directory size
du -sh ~/.cloudsync/bundles/

# Remove old incrementals (consolidate instead)
./git-bundle-sync.sh consolidate <repo-name>
./non-git-bundle-sync.sh sync  # triggers auto-consolidation
```

---

## 📈 Backup Coverage Summary

### What's Protected

✅ **60+ Git Repositories** → Daily bundles
✅ **6.3GB Backups** → Weekly archives
✅ **1.2GB Media** → Weekly archives
✅ **380MB Custom Scripts** → Weekly archives
✅ **SSH/GPG Keys** → Individual sync
✅ **All Configs** → Individual sync
✅ **Entire Home** → Restic (weekly)

### Recovery Time Objectives (RTO)

| Data Type | RTO | Command |
|-----------|-----|---------|
| Single git repo | <5 min | `unified-restore.sh restore <repo>` |
| All git repos | <30 min | Download all + restore |
| Critical configs | <2 min | Already on OneDrive |
| Non-git archives | <10 min | `unified-restore.sh restore backups` |
| Full system | <2 hours | Restic restore |

### API Call Efficiency

**Before Bundling:**
- 60 repos × 1,000 files = 60,000 API calls per sync
- backups/ = 50,000 API calls
- Total: ~110,000 API calls

**After Bundling:**
- 60 repos × 1-2 bundles = ~100 API calls
- backups/ = 1-2 archives = 2 API calls
- Total: **~102 API calls** (99.9% reduction!)

---

## 🎓 Best Practices

1. **Let automated syncs run** - Anacron catches up missed jobs
2. **Test restores periodically** - Verify backups work
3. **Monitor log files** - Check for errors weekly
4. **Keep local bundles** - Faster restore if OneDrive is slow
5. **Consolidate incrementals** - Happens automatically, but can force
6. **Document custom directories** - Add to NON_GIT_DIRS array

---

**Questions? Check:**
- [CLOUDSYNC_USAGE_GUIDE.md](./CLOUDSYNC_USAGE_GUIDE.md) - Orchestrator commands
- [BUNDLE_CONSOLIDATION_GUIDE.md](./BUNDLE_CONSOLIDATION_GUIDE.md) - Bundle management
- [TROUBLESHOOTING_REFERENCE.md](./TROUBLESHOOTING_REFERENCE.md) - General issues
