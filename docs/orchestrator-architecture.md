# CloudSync Orchestrator Architecture

**Status:** ACTIVE DESIGN  
**Created:** 2025-10-03  
**Last Updated:** 2025-10-03  
**Architecture Version:** 2.0 (Orchestrator Evolution)

## Overview

CloudSync has evolved from a sync tool to an **intelligent orchestrator** that coordinates three complementary tools for optimal cloud storage workflows with unified versioning.

## Three-Layer Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                CloudSync Orchestrator                      │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              Decision Engine                            │ │
│  │  • Context detection (git repo, file size, type)       │ │
│  │  • Smart tool selection                                │ │
│  │  • Unified versioning coordination                     │ │
│  │  • Multi-device synchronization                        │ │
│  └─────────────────────────────────────────────────────────┘ │
│                              │                               │
│     ┌────────────────────────┼────────────────────────┐      │
│     │                        │                        │      │
│  ┌──▼──┐                 ┌───▼───┐               ┌────▼───┐  │
│  │ Git │                 │Git-   │               │ rclone │  │
│  │Versioning            │Annex  │               │Transport│  │
│  │History               │Large  │               │Sync     │  │
│  │Merging               │Files  │               │Features │  │
│  └─────┘                 └───────┘               └────────┘  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                    OneDrive Storage                         │
│  DevEnvironment/                                            │
│  ├── managed/              ← Git repositories + Git-annex   │
│  ├── git-annex-storage/    ← Large file content            │
│  ├── coordination/         ← Multi-device metadata         │
│  └── legacy/               ← Existing CloudSync data       │
└─────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

### 1. CloudSync Orchestrator (Intelligence Layer)
**Role:** Smart decision making and unified interface

**Responsibilities:**
- **Context Detection:** Analyze file size, type, location (git repo vs standalone)
- **Tool Selection:** Choose optimal tool based on context and user intent
- **Unified Interface:** Provide single command interface (`cloudsync add/sync/rollback`)
- **Versioning Coordination:** Ensure all operations create version history
- **Multi-Device Coordination:** Synchronize state across devices
- **Error Handling:** Unified error handling and logging across all tools

### 2. Git (Versioning Layer)
**Role:** Version control and change tracking

**Responsibilities:**
- **Version History:** Complete change tracking for all managed files
- **Branch Management:** Support experimental changes and rollbacks
- **Merge Conflicts:** Handle concurrent edits from multiple devices
- **Small File Storage:** Direct storage for text files and small binaries
- **Metadata Tracking:** File relationships, timestamps, and user annotations

**When Used:**
- All files routed through Git for versioning
- Small files (< 10MB) stored directly in Git
- Configuration files, scripts, documents
- Any file requiring detailed change tracking

### 3. Git-Annex (Large File Layer)
**Role:** Efficient large file management with versioning

**Responsibilities:**
- **Large File Optimization:** Store large files efficiently outside Git repo
- **Content Deduplication:** Share identical content across files/repos
- **Distributed Storage:** Coordinate content across multiple remotes
- **Checksums:** Automatic integrity verification
- **Pointer Files:** Maintain Git history while storing content remotely

**When Used:**
- Files > 10MB within Git repositories
- Binary files (videos, datasets, archives)
- Any large content requiring version control
- Files that need distributed availability

### 4. rclone (Transport Layer)
**Role:** Cloud connectivity and advanced sync features

**Responsibilities:**
- **Cloud Connectivity:** OneDrive authentication and data transfer
- **Git Repository Sync:** Transport Git repos between devices
- **Performance Features:** Bandwidth limiting, progress tracking, parallel transfers
- **Advanced Sync:** Bidirectional sync with conflict detection
- **Backup Operations:** Non-versioned backup and cleanup tasks
- **Git-Annex Backend:** Provide cloud storage for git-annex content

**When Used:**
- All cloud data transport (for Git, Git-annex, and direct operations)
- Git repository synchronization between devices
- Large directory backups that don't need versioning
- Quick file sharing and temporary operations
- System manifests and device coordination

## Managed Storage Structure

### Local Storage (~/cloudsync-managed/)
```
~/cloudsync-managed/                    # Main managed Git repository
├── .git/                              # Git version control
├── configs/                           # Configuration files
│   ├── .ssh/                          # SSH keys and config
│   ├── .gitconfig                     # Git configuration
│   └── shell/                         # Shell configurations
├── documents/                         # Document files
│   ├── notes/                         # Personal notes
│   ├── templates/                     # File templates
│   └── guides/                        # Documentation
├── scripts/                           # Executable scripts
│   ├── automation/                    # Automation scripts
│   └── utilities/                     # Utility scripts
├── projects/                          # Large project files (git-annex)
│   ├── datasets/                      # Data files (annexed)
│   ├── media/                         # Video/audio files (annexed)
│   └── archives/                      # Archive files (annexed)
└── .cloudsync/                        # Orchestrator metadata
    ├── config.json                    # Orchestrator configuration
    ├── tool-preferences.json          # User tool preferences
    └── sync-status.json               # Last sync state
```

### Cloud Storage (onedrive:DevEnvironment/)
```
onedrive:DevEnvironment/
├── managed/                           # Git repositories (rclone sync)
│   ├── .git/                          # Git metadata
│   ├── configs/                       # Config files (Git-tracked)
│   ├── documents/                     # Documents (Git-tracked)
│   └── scripts/                       # Scripts (Git-tracked)
├── git-annex-storage/                 # Large file content (git-annex)
│   ├── f68/d79/                       # Content-addressed storage
│   └── tmp/                           # Temporary content
├── coordination/                      # Multi-device coordination
│   ├── devices/                       # Device metadata
│   └── locks/                         # Sync coordination
└── legacy/                           # Existing CloudSync data
    ├── CloudSync/                     # Original CloudSync scripts
    └── Laptop/                        # Device-specific data
```

## Decision Engine Logic

### Context Detection
```bash
# File classification
is_git_repository()     # Check if PWD is in a Git repo
get_file_size()         # Determine file size category
detect_file_type()      # Classify: config, document, media, code, etc.
check_user_preferences() # User-defined routing rules
```

### Tool Selection Matrix
| Context | File Size | Location | Tool | Reasoning |
|---------|-----------|----------|------|-----------|
| Git repo | < 10MB | Any | Git | Small files benefit from direct Git storage |
| Git repo | > 10MB | Any | Git-annex | Large files need efficient storage with versioning |
| Non-Git | Config file | Standard paths | Git (managed) | Config files need versioning and sync |
| Non-Git | < 100MB | Any | Git (managed) | Enable versioning for important files |
| Non-Git | > 100MB | Any | rclone direct | Large non-versioned backups |
| Any | Temp/cache | Any | rclone direct | Temporary files don't need versioning |

### Command Routing Examples
```bash
# Smart routing based on context
cloudsync add ~/.ssh/config
# → Context: config file, non-Git
# → Route: Copy to managed/configs/.ssh/config → Git add → commit

cloudsync add dataset.zip  # (in Git repo, 2GB file)
# → Context: Git repo, large file
# → Route: git annex add → git commit → git annex copy --to onedrive

cloudsync add src/main.py  # (in Git repo, 5KB file)
# → Context: Git repo, small file
# → Route: git add → git commit

cloudsync sync
# → Route: git annex sync + rclone sync managed/ + device coordination
```

## Unified Interface Commands

### Primary Commands
```bash
cloudsync add [path]              # Smart add with automatic tool selection
cloudsync sync                    # Comprehensive sync across all tools
cloudsync status                  # Unified status across all systems
cloudsync get [file]              # Intelligent retrieval (git pull/annex get/rclone copy)
cloudsync rollback [file] --to [version]  # Version rollback for any file
```

### Version Management
```bash
cloudsync log [file]              # Show version history
cloudsync diff [file] --between [v1] [v2]  # Compare versions
cloudsync branch [name]           # Create experimental branch
cloudsync versions                # List all versioned files
```

### Advanced Operations
```bash
cloudsync dedupe                  # Smart deduplication across all tools
cloudsync optimize                # Storage optimization recommendations
cloudsync clean                   # Clean temporary and cache files
cloudsync backup [path]           # Direct backup without versioning
```

### Tool-Specific Override
```bash
cloudsync git [command]           # Force Git operations
cloudsync annex [command]         # Force Git-annex operations
cloudsync rclone [command]        # Force rclone operations
```

## Multi-Device Synchronization

### Device Coordination
1. **Device Registration:** Each device registers in coordination metadata
2. **State Synchronization:** Git branches track per-device state
3. **Conflict Resolution:** Git merge strategies handle concurrent changes
4. **Content Distribution:** Git-annex manages content availability

### Sync Process
```bash
cloudsync sync
# 1. Git operations: pull → merge → push
# 2. Git-annex operations: sync → content transfer
# 3. rclone operations: sync managed repo
# 4. Device coordination: update metadata
```

## Performance Characteristics

### Storage Efficiency
- **Small files:** Git delta compression (highly efficient)
- **Large files:** Git-annex content deduplication (single copy per content)
- **Versioning:** Git history (efficient for text, reasonable for binaries)
- **Transport:** rclone with bandwidth limiting and parallel transfers

### Operational Performance
- **Context switches:** Minimal overhead for decision engine
- **Tool coordination:** Efficient handoffs between tools
- **Network usage:** Optimized by tool selection (don't sync large files as Git objects)
- **Storage usage:** Optimal tool selection prevents waste

## Integration Points

### Existing CloudSync Features
- **Conflict Resolution:** Enhanced with Git merge capabilities
- **Health Monitoring:** Extended to cover all three tools
- **Device Coordination:** Integrated with Git distributed model
- **Configuration Management:** Maintained and enhanced

### Backward Compatibility
- **Legacy scripts:** Continue to work in parallel
- **Existing data:** Gradual migration to managed storage
- **Current workflows:** Enhanced, not replaced

## Security Considerations

### Authentication
- **Git:** SSH keys for Git remote access (if needed)
- **Git-annex:** Leverages rclone authentication
- **rclone:** Existing OneDrive OAuth (unchanged)

### Data Protection
- **Versioning:** All managed data has version history
- **Checksums:** Git and Git-annex provide integrity verification
- **Encryption:** Can be enabled at Git-annex level for sensitive files
- **Access Control:** Inherits OneDrive's access controls

## Future Enhancements

### Phase 2 Features
- **Web Dashboard:** Unified monitoring interface
- **Real-time Sync:** inotify-based automatic sync
- **Multiple Remotes:** Support for S3, Dropbox, etc.
- **Smart Predictions:** ML-based tool selection optimization

### Advanced Capabilities
- **Selective Sync:** Fine-grained control over what syncs where
- **Bandwidth Optimization:** Intelligent scheduling based on network conditions
- **Conflict Prevention:** Predictive conflict detection and prevention
- **Analytics:** Storage usage patterns and optimization recommendations

This architecture provides the foundation for a sophisticated, efficient, and user-friendly cloud storage orchestration system that combines the strengths of Git versioning, Git-annex large file management, and rclone cloud connectivity.