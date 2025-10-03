# Git-Annex Integration in CloudSync Orchestrator

**Status:** ✅ Active - Orchestrator Component  
**Last Updated:** 2025-10-03  
**Integration:** CloudSync Orchestrator → Git-Annex ← rclone ← OneDrive

## Overview

Git-annex is a core component of the CloudSync orchestrator architecture, providing sophisticated large file management with versioning. The orchestrator intelligently routes large files through git-annex while maintaining unified versioning and interface consistency.

## What's Installed

- **git-annex:** Version 8.20210223 (local installation)
- **git-annex-remote-rclone:** External special remote for rclone integration
- **Symlink:** `~/bin/git-annex-remote-rclone-builtin` for older git-annex compatibility

## Storage Structure

```
onedrive:DevEnvironment/
├── git-annex-storage/          # New: Git-annex object storage
│   └── f68/d79/SHA256E-s66--[hash].txt
├── Laptop/                     # Existing: Your device coordination
├── CloudSync/                  # Existing: CloudSync metadata
└── configs/                    # Existing: Your configuration files
```

## Integration with CloudSync Orchestrator

### Automatic Routing (Planned)
```bash
# Orchestrator automatically routes large files to git-annex
cloudsync add large-dataset.zip     # → Detects: Git repo + large file → Uses git-annex
cloudsync sync                      # → Coordinates git-annex + Git + rclone
cloudsync get large-dataset.zip     # → Routes to git annex get
cloudsync rollback large-dataset.zip --to yesterday  # → Git-based rollback
```

### Current Manual Workflow
```bash
# Until orchestrator is built, use git-annex directly
cd /path/to/your/git/repo
~/CloudSync/scripts/git-annex/setup-onedrive-remote.sh

# Standard git-annex workflow
git annex add large-dataset.zip
git commit -m "Add large dataset"
git annex copy large-dataset.zip --to onedrive
git annex drop large-dataset.zip
git annex get large-dataset.zip  # When needed later
```

## Key Commands

### File Management
```bash
git annex add [file]              # Add file to git-annex
git annex get [file]              # Download file from remotes
git annex drop [file]             # Remove local copy (keep remote)
git annex copy [file] --to remote # Upload to specific remote
```

### Information
```bash
git annex whereis [file]          # Show where copies exist
git annex list                    # List all annexed files
git annex status                  # Show repository status
git annex info [remote]           # Show remote information
```

### Synchronization
```bash
git annex sync                    # Sync git-annex branch
git annex sync --content          # Sync both metadata and content
```

## Integration with CloudSync

### Complementary Features
- **CloudSync:** Handles development environment synchronization
- **Git-annex:** Handles large files within Git repositories
- **Shared Storage:** Both use the same OneDrive account and rclone configuration

### No Conflicts
- Different prefixes: `DevEnvironment/git-annex-storage/` vs `DevEnvironment/Laptop/`
- Different use cases: Environment sync vs Git LFS replacement
- Same authentication: Leverages existing rclone OneDrive setup

## Cost Benefits

- **GitHub LFS:** ~$5/month per 50GB
- **OneDrive + git-annex:** Existing OneDrive subscription
- **Savings:** ~14x cheaper for equivalent storage

## Advanced Configuration

### Custom Remote Setup
```bash
git annex initremote myremote \
    type=external \
    externaltype=rclone \
    target=onedrive \
    prefix=CustomPath/git-annex/ \
    encryption=none
```

### Preferred Content Rules
```bash
# Set repository to want large files
git annex wanted . "include=*.zip or include=*.tar.gz or largerthan=100MB"

# Set OneDrive remote to want everything
git annex wanted onedrive "anything"
```

### Automatic Sync
```bash
# Add to your sync scripts
git annex sync --content --all
```

## File Size Recommendations

### Use git-annex for:
- Binary files > 10MB
- Media files (videos, large images)
- Datasets and archives
- Build artifacts
- Large documentation (PDFs)

### Keep in Git for:
- Source code (text files)
- Small configuration files
- Documentation < 1MB
- Scripts and utilities

## Troubleshooting

### Connection Issues
```bash
# Test rclone connection
rclone lsd onedrive:

# Test git-annex remote
git annex testremote onedrive
```

### Missing Files
```bash
# Check where file copies exist
git annex whereis problematic-file.txt

# Force download from specific remote
git annex get problematic-file.txt --from onedrive
```

### Remote Not Found
```bash
# Re-enable remote (after clone)
git annex enableremote onedrive

# List available remotes
git annex info
```

## Security Considerations

- **Encryption:** Currently disabled for simplicity (can be enabled)
- **Authentication:** Uses existing rclone OneDrive OAuth tokens
- **Access Control:** Inherits OneDrive's access controls

## Monitoring Integration

Git-annex operations can be monitored through your existing CloudSync health monitoring system. The OneDrive usage will be visible in your storage utilization reports.

## Orchestrator Integration Roadmap

### Phase 1: Foundation ✅ Complete
- [x] Git-annex working with OneDrive via rclone
- [x] Manual setup scripts and documentation
- [x] Tested workflows and troubleshooting

### Phase 2: Orchestrator Integration 🚧 Q4 2025
- [ ] **Decision Engine:** Automatic routing of large files to git-annex
- [ ] **Unified Interface:** `cloudsync add/sync/get` commands
- [ ] **Managed Storage:** Git-based versioning coordination
- [ ] **Context Detection:** Smart file size and type analysis

### Phase 3: Advanced Features 📋 Q1 2026
- [ ] **Automatic Rules:** `.gitattributes` integration for automatic detection
- [ ] **Enhanced Monitoring:** Git-annex status in CloudSync dashboard
- [ ] **Multiple Remotes:** Backup remotes (S3, etc.) for redundancy
- [ ] **Encryption:** Content encryption for sensitive files

## Role in Three-Layer Architecture

**Git-Annex Layer Responsibilities:**
- **Large File Optimization:** Efficient storage of files > 10MB in Git repos
- **Content Deduplication:** Share identical content across files/repositories
- **Distributed Versioning:** Version control for large files with remote storage
- **Transport Coordination:** Use rclone as cloud storage backend

**Integration Points:**
- **CloudSync Orchestrator:** Receives routing decisions for large files
- **Git Layer:** Provides versioning foundation and pointer file management
- **rclone Layer:** Provides cloud connectivity and transport services

## Documentation Links

- [git-annex documentation](https://git-annex.branchable.com/)
- [rclone special remote](https://git-annex.branchable.com/special_remotes/rclone/)
- [git-annex-remote-rclone](https://github.com/git-annex-remote-rclone/git-annex-remote-rclone)