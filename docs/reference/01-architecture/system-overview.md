# CloudSync System Architecture Overview

**Last Updated:** 2025-09-27
**Version:** 1.0
**Status:** Active

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

### 2. Configuration Management (`config/`)
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

### 3. Monitoring System (`scripts/monitoring/`)
Comprehensive health monitoring and reporting for all system components.

#### **Health Check System** (`sync-health-check.sh`)
- Remote connectivity verification
- Conflict detection and reporting
- Advanced feature status monitoring
- Usage statistics and performance tracking
- Backup system integration

### 4. Data Flow Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Local Files   │◄──►│   CloudSync      │◄──►│  Cloud Storage  │
│                 │    │   Engine         │    │   (OneDrive)    │
│ ~/projects/     │    │                  │    │ DevEnvironment/ │
│ ~/.ssh/         │    │ ┌──────────────┐ │    │                 │
│ ~/scripts/      │    │ │ Bidirectional│ │    │                 │
│ ~/docs/         │    │ │     Sync     │ │    │                 │
└─────────────────┘    │ └──────────────┘ │    └─────────────────┘
         │              │ ┌──────────────┐ │              │
         │              │ │   Conflict   │ │              │
         ▼              │ │  Resolution  │ │              ▼
┌─────────────────┐    │ └──────────────┘ │    ┌─────────────────┐
│   Backup        │    │ ┌──────────────┐ │    │   Integrity     │
│   Storage       │    │ │ Deduplication│ │    │   Verification  │
│                 │    │ │ & Checksum   │ │    │                 │
│ Restic Repo     │    │ └──────────────┘ │    │ Hash Validation │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Technology Stack

### Core Dependencies
- **rclone**: Primary sync engine and cloud storage interface
- **bash**: Script runtime environment
- **jq**: JSON processing for reports and statistics
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

### Planned Enhancements
- Real-time file monitoring (inotify integration)
- Web-based dashboard for monitoring
- Multi-cloud provider support
- API integration for external systems
- Enhanced encryption capabilities

### Extensibility Points
- Plugin architecture for custom filters
- Webhook integration for notifications
- Custom conflict resolution strategies
- External backup system integration
- Multi-profile configuration support