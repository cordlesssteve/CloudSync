# rclone Integration Reference

**Last Updated:** 2025-09-27
**rclone Version:** 1.60+
**Status:** Active

## Overview

CloudSync is built on rclone as the primary cloud storage interface. This document details how CloudSync integrates with rclone commands and provides API-like interfaces for cloud operations.

## Core rclone Commands Used

### Smart Deduplication
**Base Command:** `rclone dedupe`

**Usage Patterns:**
```bash
# Hash-based deduplication (recommended)
rclone dedupe --by-hash [remote:path]

# Name-based deduplication
rclone dedupe [remote:path]

# Interactive mode
rclone dedupe --interactive [remote:path]

# Dry-run mode
rclone dedupe --dry-run [remote:path]
```

**CloudSync Implementation:**
```bash
# Smart deduplication script integrates as:
./scripts/core/smart-dedupe.sh --by-hash --dry-run
./scripts/core/smart-dedupe.sh --interactive --by-name
./scripts/core/smart-dedupe.sh --stats --remote onedrive --path DevEnvironment
```

**Return Codes:**
- `0`: Success, duplicates found and removed
- `1`: Error in operation
- `2`: No duplicates found

---

### Checksum Verification
**Base Command:** `rclone check`

**Usage Patterns:**
```bash
# Full checksum verification
rclone check [local:path] [remote:path]

# Size-only verification (faster)
rclone check --size-only [local:path] [remote:path]

# One-way check
rclone check --one-way [local:path] [remote:path]

# Combined output with different file states
rclone check --combined [local:path] [remote:path]
```

**CloudSync Implementation:**
```bash
# Checksum verification script integrates as:
./scripts/core/checksum-verify.sh --size-only --local ~/projects
./scripts/core/checksum-verify.sh --combined --report /tmp/verify-report.json
./scripts/core/checksum-verify.sh --missing-on-dst --download
```

**Output Processing:**
```bash
# Example output parsing
files_matched=$(echo "$output" | grep "files matched" | awk '{print $1}')
differences_found=$(echo "$output" | grep "differences found" | awk '{print $1}')
```

---

### Bidirectional Sync
**Base Command:** `rclone bisync`

**Usage Patterns:**
```bash
# Basic bidirectional sync
rclone bisync [local:path] [remote:path]

# Force resynchronization
rclone bisync --resync [local:path] [remote:path]

# Conflict resolution strategies
rclone bisync --conflict-resolve=newer [local:path] [remote:path]
rclone bisync --conflict-resolve=larger [local:path] [remote:path]
rclone bisync --conflict-resolve=list [local:path] [remote:path]

# Custom working directory
rclone bisync --workdir=/path/to/workdir [local:path] [remote:path]
```

**CloudSync Implementation:**
```bash
# Bidirectional sync script integrates as:
./scripts/core/bidirectional-sync.sh --dry-run --local ~/projects
./scripts/core/bidirectional-sync.sh --resync --conflict newer
./scripts/core/bidirectional-sync.sh --check-access
```

**Conflict Resolution Options:**
- `list`: List conflicts without resolving (default)
- `newer`: Keep the newer file
- `older`: Keep the older file
- `larger`: Keep the larger file
- `smaller`: Keep the smaller file
- `winner`: Keep the file that wins alphabetically

---

### Additional rclone Commands

#### Connectivity and Information
```bash
# List remotes
rclone listremotes

# Test connectivity
rclone lsd [remote:]

# Get quota information
rclone about [remote:]

# Get remote size
rclone size [remote:path]
```

#### File Operations
```bash
# List files
rclone ls [remote:path]
rclone lsl [remote:path]    # With details
rclone lsf [remote:path]    # Files only

# Copy operations
rclone copy [source] [dest]
rclone sync [source] [dest]  # Make dest identical to source

# Create directories
rclone mkdir [remote:path]
```

## Configuration Integration

### rclone Configuration
CloudSync reads from standard rclone configuration:
```bash
# Location: ~/.config/rclone/rclone.conf
[onedrive]
type = onedrive
drive_id = your_drive_id
drive_type = business
```

### CloudSync Configuration Mapping
```bash
# config/cloudsync.conf maps to rclone parameters
DEFAULT_REMOTE="onedrive"           # Maps to [onedrive] section
SYNC_BASE_PATH="DevEnvironment"     # Maps to remote:DevEnvironment
ENABLE_PROGRESS=true                # Maps to --progress flag
ENABLE_CHECKSUMS=true               # Maps to --checksum flag
DEFAULT_TIMEOUT=300                 # Maps to --timeout 5m
```

## Error Handling and Return Codes

### Standard rclone Return Codes
- `0`: Success
- `1`: Syntax or usage error
- `2`: Error not otherwise categorised
- `3`: Directory not found
- `4`: File not found
- `5`: Temporary error (e.g. network)
- `6`: Less serious errors (e.g. deprecated usage)
- `7`: Fatal error (e.g. corrupted data)
- `8`: Transfer exceeded - limit set by --max-transfer reached

### CloudSync Error Handling
```bash
# Pattern used in all CloudSync scripts
if rclone_command_output=$(rclone_command 2>&1); then
    # Success handling
    log_message "${GREEN}✅ Operation successful${NC}"
    process_success_output "$rclone_command_output"
else
    exit_code=$?
    # Error handling based on exit code
    case $exit_code in
        3|4) log_message "${RED}❌ Path not found${NC}" ;;
        5)   log_message "${YELLOW}⚠️ Network error - retrying${NC}" ;;
        *)   log_message "${RED}❌ rclone error: $exit_code${NC}" ;;
    esac
fi
```

## Performance Optimization

### Transfer Settings
```bash
# CloudSync applies these optimizations
--transfers=4              # Parallel transfers
--checkers=8              # Parallel checkers
--progress                # Progress reporting
--stats=10s               # Statistics interval
```

### Bandwidth Management
```bash
# Available in CloudSync scripts
--bwlimit=10M             # Bandwidth limit
--bwlimit-file=5M         # Per-file bandwidth limit
```

### Efficiency Settings
```bash
# Size-only comparison for speed
--size-only

# Skip checksum verification for speed
--no-checksum

# Use modification time comparison
--no-update-modtime=false
```

## Filter Integration

### CloudSync Filter File Generation
```bash
# Generated filter file format
# CloudSync Bidirectional Sync Filters

# Exclude patterns from config
- *.tmp
- *.log
- node_modules/
- .git/
- __pycache__/

# Include critical paths (if not syncing from HOME)
+ .ssh/**
+ scripts/**
+ docs/**
```

### rclone Filter Application
```bash
# Applied in bidirectional sync
rclone bisync --filters-file="$filter_file" [local] [remote]
```

## Logging and Monitoring Integration

### rclone Log Output Capture
```bash
# CloudSync captures and parses rclone output
rclone_output=$(rclone command --log-level INFO 2>&1)

# Parse for statistics
transferred_files=$(echo "$rclone_output" | grep "Transferred:" | awk '{print $2}')
transfer_speed=$(echo "$rclone_output" | grep "Transferred:" | awk '{print $4$5}')
```

### Integration with CloudSync Logging
```bash
# All rclone operations logged to CloudSync logs
echo "[$TIMESTAMP] rclone $command" >> "$LOG_FILE"
echo "$rclone_output" >> "$LOG_FILE"
```

## Security Considerations

### Credential Handling
- CloudSync never stores rclone credentials directly
- Uses standard rclone configuration files
- Supports rclone's built-in encryption for config files

### Safe Operations
```bash
# CloudSync enforces safe operation patterns
--dry-run                 # Test mode for all operations
--max-delete=50          # Limit accidental deletions
--backup-dir             # Backup before destructive operations
```

### Access Control
```bash
# CloudSync validates paths before rclone operations
if [[ ! -d "$LOCAL_PATH" ]]; then
    log_message "❌ Local path does not exist: $LOCAL_PATH"
    exit 1
fi

if ! rclone lsd "$REMOTE:" >/dev/null 2>&1; then
    log_message "❌ Cannot connect to remote: $REMOTE"
    exit 1
fi
```

## Extension Points

### Custom rclone Commands
CloudSync can be extended to use additional rclone commands:
```bash
# Template for new rclone integrations
execute_rclone_command() {
    local command="$1"
    local args="$2"

    log_message "Executing: rclone $command $args"

    if output=$(rclone $command $args 2>&1); then
        log_message "✅ Success: $command"
        echo "$output"
        return 0
    else
        local exit_code=$?
        log_message "❌ Failed: $command (exit code: $exit_code)"
        echo "$output" >&2
        return $exit_code
    fi
}
```

### Future rclone Features
CloudSync is designed to easily incorporate new rclone features:
- Enhanced bisync capabilities
- New cloud provider support
- Advanced filtering options
- Improved performance optimizations

For the latest rclone documentation, see: https://rclone.org/docs/