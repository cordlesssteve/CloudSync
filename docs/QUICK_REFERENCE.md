# CloudSync Quick Reference Card
**Version:** 2.0 | **Status:** Production Ready | **Date:** 2025-10-04

---

## 🚀 Essential Commands

```bash
# Initialize CloudSync
cloudsync managed-init

# Add any file (automatic tool selection)
cloudsync add <file>

# Sync to backup location
cloudsync sync

# Check file status and history
cloudsync status <file>

# Rollback to previous version
cloudsync rollback <file> <commit>
```

---

## 🎯 Decision Engine Quick Reference

| File Type | Size | Tool | Storage Location |
|-----------|------|------|------------------|
| Text files | < 10MB | **Git** | `~/csync-managed/documents/` |
| Config files | Any size | **Git** | `~/csync-managed/configs/` |
| Binary files | > 1MB | **Git-Annex** | `~/csync-managed/media/` |
| Large files | > 10MB | **Git-Annex** | `~/csync-managed/projects/` |
| Archives | Any size | **Git-Annex** | `~/csync-managed/archives/` |

---

## 🔄 Common Workflows

### Adding Files
```bash
cloudsync add document.txt      # → Git (small text)
cloudsync add video.mp4         # → Git-Annex (large binary)
cloudsync add config.yaml       # → Git (config override)
cloudsync add dataset.zip       # → Git-Annex (large archive)
```

### Syncing
```bash
cloudsync sync                  # Bidirectional sync
cloudsync sync . push          # Push changes only
cloudsync sync . pull          # Pull updates only
cloudsync sync ~/projects      # Sync specific directory
```

### Version Management
```bash
cloudsync status file.txt      # Show version history
cloudsync rollback file.txt HEAD~1   # Rollback one version
cloudsync analyze file.bin     # Preview decision (no action)
```

---

## 🏗️ Directory Structure

```
~/csync-managed/           # Managed Storage Root
├── configs/      (Git)        # Configuration files
├── documents/    (Git)        # Documents and text files
├── scripts/      (Git)        # Scripts and code
├── projects/     (Git-Annex)  # Large project files  
├── archives/     (Git-Annex)  # Archive files
└── media/        (Git-Annex)  # Media files
```

**Remote**: `onedrive:DevEnvironment/managed/`

---

## ⚡ Configuration Quick-Set

```bash
# Enable auto-sync after add
echo 'AUTO_SYNC="true"' >> config/managed-storage.conf

# Enable verbose output
export CLOUDSYNC_VERBOSE=true

# Test mode (no changes)
export CLOUDSYNC_DRY_RUN=true

# Change size threshold (20MB)
echo 'LARGE_FILE_THRESHOLD=$((20 * 1024 * 1024))' >> config/managed-storage.conf
```

---

## 🛠️ Troubleshooting

```bash
# Check system status
cloudsync managed-status

# Analyze file without adding
cloudsync analyze problematic-file.txt

# Check remote connectivity
rclone lsd onedrive:

# Verbose operation
CLOUDSYNC_VERBOSE=true cloudsync add file.txt

# Test all components
./test-orchestrator.sh
```

---

## 📊 File Type Examples

### Git Files (Full versioning)
- `config.yaml`, `settings.json`, `*.conf`
- `README.md`, `*.txt`, `*.py`, `*.js`
- Small images < 1MB: `icon.png`, `logo.svg`

### Git-Annex Files (Pointer versioning)
- `video.mp4`, `audio.wav`, `presentation.pptx`
- `dataset.zip`, `backup.tar.gz`, `image.iso`
- `large-document.pdf`, `high-res-photo.jpg`

---

## 🔍 Status Indicators

- `📄` File tracked in Git
- `📦` File tracked in Git-Annex  
- `☁️` File synced to remote
- `🔄` File needs sync
- `⚠️` File has conflicts
- `✅` File fully synchronized

---

## 📞 Getting Help

```bash
cloudsync --help              # Main help
cloudsync add --help          # Command-specific help
cloudsync managed-status      # System overview
```

**Log Location**: `~/.cloudsync/logs/`  
**Config File**: `config/managed-storage.conf`  
**Full Guide**: `docs/CLOUDSYNC_USAGE_GUIDE.md`

---

**🎯 Remember**: `cloudsync add` + `cloudsync sync` handles 95% of use cases!