# CloudSync Quick Reference Cheat Sheet

**One-page guide for daily operations** | Last Updated: 2025-10-15

---

## 🎯 Four Backup Systems At-A-Glance

| System | What | When | Command |
|--------|------|------|---------|
| **Git Bundles** | 60+ repos | Daily | `git-bundle-sync.sh` |
| **Non-Git Archives** | backups/, media/, .local/bin/ | Weekly | `non-git-bundle-sync.sh sync` |
| **Dev Env Sync** | SSH keys, configs, secrets | On-demand | `dev-env-sync.sh push` |
| **System Backup** | Full home directory | Weekly | Restic (automatic) |

---

## ⚡ Most Common Commands

### Daily Operations
```bash
# Check what's backed up
find ~/.cloudsync/bundles -name "bundle-manifest.json" | wc -l  # Git repos
~/scripts/system/non-git-bundle-sync.sh status                  # Non-git

# Manually trigger syncs
~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/git-bundle-sync.sh
~/scripts/system/non-git-bundle-sync.sh sync
~/scripts/system/dev-env-sync.sh push
```

### Restore Operations
```bash
# See everything available
~/scripts/system/unified-restore.sh list

# Download from OneDrive
~/scripts/system/unified-restore.sh download <name>

# Restore
~/scripts/system/unified-restore.sh restore <name> [custom-path]

# Verify integrity
~/scripts/system/unified-restore.sh verify <name>
```

### Monitoring
```bash
# View logs
tail -100 ~/.cloudsync/logs/bundle-sync.log
tail -100 ~/.cloudsync/logs/non-git-bundle-sync.log

# Check OneDrive usage
rclone about onedrive:

# List remote bundles
rclone lsf onedrive:DevEnvironment/bundles/
```

---

## 📋 What Gets Backed Up

### Git Bundle Sync (Daily)
```
All repos in ~/projects/ with .git directories
→ ~/.cloudsync/bundles/<repo-name>/
→ onedrive:DevEnvironment/bundles/<repo-name>/
```

### Non-Git Archives (Weekly)
```
~/backups/      (6.3G)  → backups-full-*.tar.zst
~/media/        (1.2G)  → media-full-*.tar.zst
~/.local/bin/   (380M)  → local-bin-full-*.tar.zst
```

### Dev Environment Sync (On-Demand)
```
Directories:
  ~/.ssh/, ~/scripts/, ~/mcp-servers/, ~/docs/
  ~/.gnupg/, ~/.pki/, ~/.secrets/, ~/media/, ~/backups/

Files:
  .gitconfig, .bash_aliases, .bashrc, .profile
  .git-credentials, .cloudsync-secrets.conf
  .npmrc, .wsl-config, litellm_*.yaml

Configs:
  .config/rclone/, .config/gh/, .config/git/
  .config/syncthing/, .config/claude-code/
```

---

## 🚨 Emergency Restore

### Restore Single Git Repo
```bash
~/scripts/system/unified-restore.sh download Work/spaceful
~/scripts/system/unified-restore.sh restore Work/spaceful
```

### Restore Backups Directory
```bash
~/scripts/system/unified-restore.sh download backups
~/scripts/system/unified-restore.sh restore backups
```

### Restore All Critical Configs
```bash
# Already on OneDrive at:
rclone sync onedrive:DevEnvironment/$(hostname)/essentials/ ~/restored-configs/
```

---

## 📁 Key File Locations

```
Scripts (Active):
  ~/scripts/system/non-git-bundle-sync.sh
  ~/scripts/system/unified-restore.sh
  ~/scripts/system/dev-env-sync.sh

Scripts (Source):
  ~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/
  ~/projects/Utility/LOGISTICAL/CloudSync/scripts/core/

Local Bundles:
  ~/.cloudsync/bundles/<name>/
  └── bundle-manifest.json

Logs:
  ~/.cloudsync/logs/
  ├── bundle-sync.log
  ├── non-git-bundle-sync.log
  └── restore-verification.log

OneDrive:
  onedrive:DevEnvironment/bundles/          # Git + non-git bundles
  onedrive:DevEnvironment/<hostname>/       # Dev environment files
```

---

## ⏱️ Scheduled Jobs (Anacrontab)

```bash
# Daily
1  2   git_bundle_sync           # Git repos

# Weekly
7  5   non_git_bundle_sync       # Large directories
7  5   weekly_restic_backup      # Full system
7  10  bundle_restore_verify     # Test restores

# Quarterly
90 10  quarterly_tar_backup      # TAR archive
```

View schedule: `cat ~/.anacrontab`

---

## 🔧 Quick Fixes

### Bundle Not Created
```bash
# Check if directory/repo changed
~/scripts/system/non-git-bundle-sync.sh sync-dir ~/backups
./git-bundle-sync.sh test ~/projects/Work/spaceful
```

### Restore Failed
```bash
# Verify bundle integrity
~/scripts/system/unified-restore.sh verify <name>

# Check OneDrive connectivity
rclone lsd onedrive:DevEnvironment/
```

### Out of Disk Space
```bash
# Check bundle size
du -sh ~/.cloudsync/bundles/

# Consolidate incrementals (happens automatically)
# Or clean old incrementals after consolidation
```

---

## 📈 Performance Stats

**API Call Reduction:**
- Before: ~110,000 calls per sync
- After: ~102 calls per sync
- **Reduction: 99.9%**

**Recovery Times:**
- Single repo: <5 min
- Critical configs: <2 min
- Non-git archive: <10 min
- Full system: <2 hours

---

## 📞 Need Help?

**Full Documentation:**
- [COMPLETE_BACKUP_GUIDE.md](./COMPLETE_BACKUP_GUIDE.md) - Comprehensive guide
- [CLOUDSYNC_USAGE_GUIDE.md](./CLOUDSYNC_USAGE_GUIDE.md) - Orchestrator
- [TROUBLESHOOTING_REFERENCE.md](./TROUBLESHOOTING_REFERENCE.md) - Issues

**Test Your Backups:**
```bash
# Verify a restore works
~/scripts/system/unified-restore.sh download backups
~/scripts/system/unified-restore.sh restore backups /tmp/test-restore
```

---

**Print this page and keep it handy for emergencies!**
