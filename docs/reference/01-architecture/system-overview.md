# CloudSync System Architecture Overview

**Last Updated:** 2025-10-07
**Version:** 2.0
**Status:** Production Ready

## System Purpose

CloudSync is a comprehensive cloud synchronization system built on rclone that provides intelligent bidirectional sync, conflict resolution, data integrity verification, and storage optimization for development environments and critical data.

## Core Components

### 1. Sync Engine (`scripts/core/`)
The heart of CloudSync, providing four main synchronization capabilities:

#### **Smart Deduplication** (`smart-dedupe.sh`)
- **Purpose**: Eliminate duplicate files to optimize storage and sync performance
- **Technology**: rclone dedupe with hash-based detection
- **Features**: Interactive/automated modes, dry-run testing, statistics reporting

#### **Checksum Verification** (`checksum-verify.sh`)
- **Purpose**: Ensure data integrity across local and remote locations
- **Technology**: rclone check with MD5/SHA1 verification
- **Features**: Size-only mode, JSON reporting, integrity scoring, missing file detection

#### **Bidirectional Sync** (`bidirectional-sync.sh`)
- **Purpose**: Two-way synchronization with conflict detection
- **Technology**: rclone bisync with configurable conflict resolution
- **Features**: Multiple resolution strategies, safety limits, filter management

#### **Conflict Resolution** (`conflict-resolver.sh`)
- **Purpose**: Detect and resolve sync conflicts automatically or interactively
- **Technology**: Pattern-based conflict detection with backup workflows
- **Features**: Auto-resolution strategies, conflict backup, interactive resolution

### 2. Git Bundle Sync System (`scripts/bundle/`)
Efficient repository synchronization via git bundles for cloud storage optimization.

#### **Git Bundle Sync** (`git-bundle-sync.sh`)
- **Purpose**: Sync git repositories to cloud as single bundle files instead of thousands of individual files
- **Technology**: Git bundles with incremental strategy and JSON manifest tracking
- **Features**:
  - Size-based strategy: Small repos (< 100MB) use full bundles, medium/large use incremental bundles
  - Automatic consolidation after 10 incremental bundles or 30 days
  - Critical .gitignored files preservation (credentials, .env, API keys)
  - Manifest-based bundle chain tracking
  - OneDrive API rate limiting mitigation (reduces from thousands of files to 4 per repo)

#### **Bundle Restore** (`restore-from-bundle.sh`)
- **Purpose**: Restore repositories from bundle chains
- **Technology**: Git bundle verification and application with critical files restoration
- **Features**: Full bundle + incremental chain support, test mode, integrity verification

### 3. Intelligent Orchestrator (`scripts/`)
Unified interface with smart tool selection for all file operations.

#### **CloudSync Orchestrator** (`cloudsync-orchestrator.sh`)
- **Purpose**: Single interface for all sync operations with intelligent tool routing
- **Technology**: Decision engine coordinating Git, Git-Annex, and rclone
- **Features**:
  - Unified commands: `cloudsync add/sync/status/rollback`
  - Context-aware tool selection based on file type, size, and location
  - Managed storage with Git-based versioning for all file types
  - Automatic categorization and organization

#### **Decision Engine** (`decision-engine.sh`)
- **Purpose**: Smart routing logic for tool selection
- **Technology**: Rule-based decision tree with context detection
- **Features**:
  - Git detection for source code and text files
  - Git-annex routing for large files (> 100MB)
  - rclone fallback for non-Git contexts
  - Size-based strategy selection

### 4. Git-Annex Integration
Large file handling with OneDrive backend support.

#### **Git-Annex with OneDrive**
- **Purpose**: Version control for large files without bloating Git repositories
- **Technology**: git-annex with rclone special remote for OneDrive
- **Features**:
  - Large file (> 100MB) automatic detection and routing
  - OneDrive as git-annex backend storage
  - Version history for large binary files
  - Seamless integration with orchestrator

### 5. Configuration Management (`config/`)
Centralized configuration system for consistent operation across all components.

#### **Main Configuration** (`cloudsync.conf`)
```bash
# Core settings
DEFAULT_REMOTE="onedrive"
SYNC_BASE_PATH="DevEnvironment"
CONFLICT_RESOLUTION="ask"

# Performance settings
ENABLE_CHECKSUMS=true
ENABLE_PROGRESS=true
DEFAULT_TIMEOUT=300

# Path definitions
CRITICAL_PATHS=(".ssh" "scripts" "mcp-servers" "docs")
EXCLUDE_PATTERNS=("*.tmp" "*.log" "node_modules/")
```

### 6. Monitoring System (`scripts/monitoring/`)
Comprehensive health monitoring and reporting for all system components.

#### **Health Check System** (`sync-health-check.sh`)
- Remote connectivity verification
- Conflict detection and reporting
- Advanced feature status monitoring
- Usage statistics and performance tracking
- Backup system integration

### 7. Data Flow Architecture

```
┌─────────────────┐    ┌──────────────────────┐    ┌─────────────────┐
│   Local Files   │◄──►│   CloudSync          │◄──►│  Cloud Storage  │
│                 │    │   Orchestrator       │    │   (OneDrive)    │
│ ~/projects/     │    │                      │    │                 │
│ ~/.ssh/         │    │ ┌──────────────────┐ │    │ DevEnvironment/ │
│ ~/scripts/      │    │ │ Decision Engine  │ │    │ Git Bundles/    │
│ ~/docs/         │    │ │  (Smart Routing) │ │    │ Git-Annex/      │
└─────────────────┘    │ └──────────────────┘ │    │ rclone Files/   │
         │              │         │            │    └─────────────────┘
         │              │         ▼            │              │
         │              │ ┌──────────────────┐ │              │
         │              │ │  Git / Git-Annex │ │              │
         ▼              │ │  / rclone / Bundle│ │              ▼
┌─────────────────┐    │ └──────────────────┘ │    ┌─────────────────┐
│ Managed Storage │    │ ┌──────────────────┐ │    │   Integrity     │
│ (Git-based)     │    │ │  Bidirectional   │ │    │   Verification  │
│                 │    │ │  Sync & Conflict │ │    │                 │
│ ~/cloudsync-    │    │ │    Resolution    │ │    │ Hash Validation │
│    managed/     │    │ └──────────────────┘ │    │ Bundle Verify   │
└─────────────────┘    │ ┌──────────────────┐ │    └─────────────────┘
                       │ │  Deduplication   │ │
                       │ │  & Checksum      │ │
                       │ └──────────────────┘ │
                       └──────────────────────┘
```

## Technology Stack

### Core Dependencies
- **rclone**: Cloud storage interface and bidirectional sync engine
- **git**: Version control and bundle creation for repository sync
- **git-annex**: Large file version control with cloud backend
- **bash**: Script runtime environment
- **jq**: JSON processing for reports, statistics, and manifest tracking
- **restic**: Backup system integration

### Cloud Provider Support
- **Primary**: Microsoft OneDrive (Office 365)
- **Extensible**: Any rclone-supported provider (Google Drive, Dropbox, AWS S3, etc.)

## Security Architecture

### Data Protection
- No credentials stored in code (configuration-based)
- Backup creation before destructive operations
- Dry-run modes for safe testing
- Comprehensive logging for audit trails

### Access Control
- File permission preservation
- Path validation and sandboxing
- Configurable exclusion patterns
- Safe operation limits (max deletes, timeouts)

## Performance Characteristics

### Optimization Features
- **Incremental Sync**: Only transfers changed files
- **Hash-based Deduplication**: Eliminates storage waste
- **Checksum Verification**: Ensures data integrity
- **Parallel Operations**: Concurrent sync processes where possible

### Scalability Considerations
- **Filter Management**: Excludes unnecessary files (node_modules, logs, caches)
- **Bandwidth Control**: Configurable transfer limits
- **Progress Reporting**: Real-time operation feedback
- **Resource Limits**: Configurable safety thresholds

## Integration Points

### Health Monitoring Integration
All core components integrate with the health monitoring system:
- Feature availability detection
- Usage statistics tracking
- Performance metrics collection
- Error reporting and alerting

### Configuration Integration
All scripts use centralized configuration:
- Consistent remote and path settings
- Shared exclusion patterns
- Common timeout and safety limits
- Unified logging configuration

### Backup System Integration
Integration with existing backup infrastructure:
- Restic repository monitoring
- Backup verification reporting
- Retention policy enforcement
- Recovery workflow support

## Operational Modes

### Development Mode
- Dry-run capabilities for safe testing
- Verbose logging and progress reporting
- Interactive conflict resolution
- Development environment path focus

### Production Mode
- Automated conflict resolution
- Silent operation with logging
- Performance optimized settings
- Comprehensive path coverage

### Maintenance Mode
- System health verification
- Storage optimization (deduplication)
- Integrity verification workflows
- Conflict cleanup and resolution

## Future Architecture Considerations

### Optional Enhancements (System is Production Ready)
- Real-time file monitoring (inotify integration) for automatic sync triggers
- Web-based dashboard for visual monitoring and management
- Multi-cloud provider support beyond OneDrive
- API integration for external systems
- Enhanced encryption capabilities beyond rclone's native support
- Large repository (> 500MB) incremental bundle testing and optimization

### Extensibility Points
- Plugin architecture for custom file routing rules
- Webhook integration for sync notifications
- Additional conflict resolution strategy plugins
- External backup system integration beyond Restic
- Multi-profile configuration support for different sync scenarios
- Custom bundle consolidation triggers and strategies