# CloudSync

Advanced cloud synchronization and backup system for development environments.

## 🎯 Project Overview

CloudSync is a comprehensive solution for managing cloud-based development environment synchronization, featuring smart deduplication, conflict resolution, and incremental syncing capabilities. Useful when you need Github LFS solutions, but don't want to pay for it. So far, fully functioning with an existing OneDrive storage subscription. Plans to expand features, integrations, etc. in the future.

## 📁 Project Structure

```
CloudSync/
├── scripts/
│   ├── core/           # Core sync functionality
│   ├── backup/         # Backup management
│   ├── monitoring/     # Sync monitoring & health checks
│   └── utils/          # Utility functions
├── config/             # Configuration files and templates
├── docs/               # Project documentation
├── tests/              # Test suites
├── examples/           # Usage examples
└── templates/          # Script and config templates
```

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/cordlesssteve/CloudSync.git
cd CloudSync

# Create configuration from template
cp config/cloudsync.conf.template config/cloudsync.conf
nano config/cloudsync.conf  # Edit: Set RESTIC_PASSWORD and other values

# Copy rclone config template
cp config/rclone.conf.template ~/.config/rclone/rclone.conf
# Edit with your cloud provider credentials

# Run git bundle sync (backs up all repositories)
./scripts/bundle/git-bundle-sync.sh sync

# Monitor sync status
./scripts/monitoring/sync-health-check.sh
```

See [Setup Guide](docs/reference/03-development/setup-guide.md) for detailed installation instructions.

## 🔧 Features

### Four-Tier Backup System
CloudSync provides comprehensive protection through multiple complementary systems:

1. **Git Bundle Sync** - 60+ repositories backed up daily as efficient bundles
2. **Non-Git Archives** - Large directories (backups, media, .local/bin) archived weekly
3. **Dev Environment Sync** - Real-time protection for SSH keys, configs, and secrets
4. **System Backups** - Full home directory via Restic (weekly) and TAR (quarterly)

**Result:** 99.9% reduction in OneDrive API calls (110,000 → 102 per sync)

### Core Sync Capabilities
- **Intelligent Orchestrator**: Unified interface with smart tool selection (Git/Git-annex/rclone)
- **Bidirectional Sync**: Two-way synchronization with rclone bisync
- **Conflict Resolution**: Automated and interactive conflict handling
- **Smart Deduplication**: Hash-based duplicate detection and removal
- **Checksum Verification**: MD5/SHA1 integrity checking with reporting

### Git Bundle Sync System
- **Efficient Cloud Storage**: Bundle repos as single files instead of thousands of individual files
- **Incremental Bundles**: Smart strategy for medium/large repos with automatic consolidation
- **Bundle Consolidation**: Automated monitoring and manual consolidation for optimal performance
- **Critical Files Preservation**: Intelligent backup of .gitignored credentials and configs
- **OneDrive Optimization**: Dramatically reduces API calls and rate limiting issues

### Non-Git Archive System (NEW!)
- **Compressed Archives**: tar.zst compression for optimal storage efficiency
- **Source Path Tracking**: Manifest records exact origin paths for disaster recovery
- **Incremental Updates**: Only archives changed directories, consolidates automatically
- **Category Analysis**: Tracks file types and metadata for each archive
- **Unified Restore**: Single interface restores both git repos and non-git archives

### Advanced Features
- **Git-Annex Integration**: Large file handling with OneDrive backend
- **Unified Versioning**: Git-based version history for all file types
- **Managed Storage**: Organized, version-controlled storage with automatic categorization
- **Multi-Device Coordination**: Distributed synchronization across multiple devices
- **Health Monitoring**: Comprehensive status tracking and reporting
- **Notifications System**: Multi-backend alerts (ntfy.sh, webhooks, email)
- **Restore Verification**: Automated disaster recovery testing
- **Git Hooks Auto-Backup**: Automatic backup within 10 minutes of commit

## 📋 Current Capabilities

- ✅ Intelligent orchestrator with unified interface (`cloudsync` commands)
- ✅ Bidirectional sync with conflict resolution
- ✅ Git bundle sync for efficient cloud storage (51+ repos tested)
- ✅ Incremental bundles with automatic consolidation
- ✅ Git-annex integration for large files
- ✅ Smart deduplication and checksum verification
- ✅ Unified versioning across all file types
- ✅ Production-ready with comprehensive documentation

## 🔗 Related Systems

- **rclone**: Primary cloud storage interface
- **Restic**: Backup and versioning
- **OneDrive**: Current primary cloud backend
- **system-config**: System configuration management

## 📦 Usage Examples

### Git Bundle Sync
```bash
# Sync all repositories to OneDrive as bundles
./scripts/bundle/git-bundle-sync.sh sync

# Test a single repository
./scripts/bundle/git-bundle-sync.sh test ~/projects/path/to/repo
```

### Non-Git Archive Sync (NEW!)
```bash
# Archive large directories (backups, media, .local/bin)
./scripts/bundle/non-git-bundle-sync.sh sync

# Archive specific directory
./scripts/bundle/non-git-bundle-sync.sh sync-dir ~/backups

# Check status
./scripts/bundle/non-git-bundle-sync.sh status
```

### Dev Environment Sync (Enhanced!)
```bash
# Sync SSH keys, configs, secrets, scripts (23 new items added!)
./scripts/core/dev-env-sync.sh push

# Now backs up: .gnupg, .pki, .secrets, .cloudsync-secrets.conf, and more
```

### Unified Restore (NEW!)
```bash
# List all available bundles (git repos + non-git archives)
./scripts/bundle/unified-restore.sh list

# Restore git repository
./scripts/bundle/unified-restore.sh restore Work/spaceful

# Restore non-git archive
./scripts/bundle/unified-restore.sh restore backups

# Download from OneDrive first
./scripts/bundle/unified-restore.sh download backups
```

## 🔔 Notifications & Monitoring

```bash
# Send manual notification
./scripts/notify.sh success "Title" "Message"

# Run restore verification (includes consolidation check)
./scripts/bundle/verify-restore.sh --max-repos 5

# Consolidate incremental bundles
./scripts/bundle/git-bundle-sync.sh consolidate Work/spaceful

# Install git hooks for auto-backup
./scripts/hooks/install-git-hooks.sh

# View sync logs
tail -f ~/.cloudsync/logs/cron-sync.log

# View git hook auto-backup log
tail -f ~/.cloudsync/logs/hook-sync.log

# View restore verification results
tail -f ~/.cloudsync/logs/restore-verification.log
```

## 📚 Documentation

**Start Here:**
- **[COMPLETE_BACKUP_GUIDE.md](./docs/COMPLETE_BACKUP_GUIDE.md)** - Crystal-clear guide for ALL backup systems (NEW!)
- **[QUICK_REFERENCE.md](./docs/QUICK_REFERENCE_CHEATSHEET.md)** - One-page cheat sheet (NEW!)

**Detailed Guides:**
- [CLOUDSYNC_USAGE_GUIDE.md](./docs/CLOUDSYNC_USAGE_GUIDE.md) - Orchestrator commands
- [BUNDLE_CONSOLIDATION_GUIDE.md](./docs/BUNDLE_CONSOLIDATION_GUIDE.md) - Bundle management
- [NOTIFICATIONS_AND_MONITORING.md](./docs/NOTIFICATIONS_AND_MONITORING.md) - Alerts & monitoring
- [GIT_HOOKS_AUTO_BACKUP.md](./docs/GIT_HOOKS_AUTO_BACKUP.md) - Auto-backup setup
- [TROUBLESHOOTING_REFERENCE.md](./docs/TROUBLESHOOTING_REFERENCE.md) - Common issues

---

**Status**: Production Ready with 4-Tier Backup System
**Maintainer**: cordlesssteve
**Last Updated**: 2025-10-15
