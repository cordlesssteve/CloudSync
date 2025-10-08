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

## 📦 Git Bundle Sync Usage

```bash
# Sync all repositories to OneDrive as bundles
./scripts/bundle/git-bundle-sync.sh sync

# Test a single repository
./scripts/bundle/git-bundle-sync.sh test ~/projects/path/to/repo

# Restore from bundle
./scripts/bundle/restore-from-bundle.sh restore <repo_name> [target_dir]

# Test restore to /tmp
./scripts/bundle/restore-from-bundle.sh test <repo_name>
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

See [NOTIFICATIONS_AND_MONITORING.md](./docs/NOTIFICATIONS_AND_MONITORING.md) for complete setup guide.
See [BUNDLE_CONSOLIDATION_GUIDE.md](./docs/BUNDLE_CONSOLIDATION_GUIDE.md) for consolidation details.
See [GIT_HOOKS_AUTO_BACKUP.md](./docs/GIT_HOOKS_AUTO_BACKUP.md) for auto-backup setup.

---

**Status**: Production Ready
**Maintainer**: cordlesssteve
**Last Updated**: 2025-10-07
