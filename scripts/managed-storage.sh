#!/bin/bash

# CloudSync Managed Storage
# Git-based storage management for unified versioning
# Part of CloudSync Intelligent Orchestrator

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_ROOT/config/cloudsync.conf"

# Source configuration
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "Error: Configuration file not found at $CONFIG_FILE" >&2
    exit 1
fi

# Managed storage configuration
MANAGED_ROOT="$HOME/cloudsync-managed"
MANAGED_CONFIG="$PROJECT_ROOT/config/managed-storage.conf"
GIT_ANNEX_THRESHOLD=${LARGE_FILE_THRESHOLD:-100M}

# Logging
LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/managed-storage.log"
VERBOSE=${VERBOSE:-false}
DRY_RUN=${DRY_RUN:-false}

mkdir -p "$LOG_DIR"

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    if [[ "$VERBOSE" == "true" || "$level" == "ERROR" || "$level" == "INFO" ]]; then
        echo "[$level] $message" >&2
    fi
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { log "DEBUG" "$@"; }

# Utility functions
execute_command() {
    local cmd="$1"
    log_debug "Executing: $cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute: $cmd"
        return 0
    fi
    
    if eval "$cmd"; then
        log_debug "Command succeeded: $cmd"
        return 0
    else
        local exit_code=$?
        log_error "Command failed with exit code $exit_code: $cmd"
        return $exit_code
    fi
}

convert_size_to_bytes() {
    local size="$1"
    local number="${size%[KMGT]*}"
    local unit="${size#$number}"
    
    case "$unit" in
        "K"|"k") echo "$((number * 1024))" ;;
        "M"|"m") echo "$((number * 1024 * 1024))" ;;
        "G"|"g") echo "$((number * 1024 * 1024 * 1024))" ;;
        "T"|"t") echo "$((number * 1024 * 1024 * 1024 * 1024))" ;;
        *) echo "$number" ;;
    esac
}

is_large_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    local file_size=$(stat --printf="%s" "$file" 2>/dev/null || echo "0")
    local threshold_bytes=$(convert_size_to_bytes "$GIT_ANNEX_THRESHOLD")
    
    [[ "$file_size" -gt "$threshold_bytes" ]]
}

# Managed storage operations
init_managed_storage() {
    log_info "Initializing managed storage at: $MANAGED_ROOT"
    
    if [[ -d "$MANAGED_ROOT" ]]; then
        log_warn "Managed storage already exists at: $MANAGED_ROOT"
        return 0
    fi
    
    # Create managed storage directory
    execute_command "mkdir -p '$MANAGED_ROOT'"
    
    # Initialize Git repository
    cd "$MANAGED_ROOT"
    execute_command "git init"
    execute_command "git config user.name 'CloudSync'"
    execute_command "git config user.email 'cloudsync@localhost'"
    
    # Initialize Git-annex
    execute_command "git annex init 'cloudsync-managed'"
    
    # Configure rclone remote
    if [[ -n "${DEFAULT_REMOTE:-}" ]]; then
        execute_command "git annex initremote $DEFAULT_REMOTE type=external externaltype=rclone target=$DEFAULT_REMOTE prefix=cloudsync-managed/"
        log_info "Configured rclone remote: $DEFAULT_REMOTE"
    fi
    
    # Create initial structure
    mkdir -p "documents" "code" "media" "archives"
    
    # Create .gitignore
    cat > .gitignore << 'EOF'
# Temporary files
*.tmp
*.temp
.DS_Store
Thumbs.db

# Log files
*.log

# Cache directories
.cache/
tmp/
EOF
    
    # Create README
    cat > README.md << 'EOF'
# CloudSync Managed Storage

This directory is managed by CloudSync's intelligent orchestrator.

## Structure
- `documents/` - Text documents and small files (Git)
- `code/` - Source code and configuration files (Git)
- `media/` - Images, videos, audio files (Git-annex)
- `archives/` - Compressed archives and backups (Git-annex)

## Usage
Use the `cloudsync` command to add, sync, and manage files:

```bash
cloudsync add /path/to/file
cloudsync sync . push
cloudsync rollback file.txt HEAD~1
```

Files are automatically routed to appropriate storage based on:
- File size (large files → Git-annex)
- File type (binary files → Git-annex, text files → Git)
- Content type (code → Git, media → Git-annex)
EOF
    
    # Initial commit
    execute_command "git add ."
    execute_command "git commit -m 'Initial CloudSync managed storage setup'"
    
    log_info "Managed storage initialized successfully"
}

promote_file() {
    local source_file="$1"
    local target_tool="$2"  # git or git-annex
    local category="${3:-documents}"  # documents, code, media, archives
    
    log_info "Promoting file to managed storage: $source_file (tool: $target_tool, category: $category)"
    
    # Validate source file
    if [[ ! -f "$source_file" ]]; then
        log_error "Source file does not exist: $source_file"
        return 1
    fi
    
    # Initialize managed storage if needed
    if [[ ! -d "$MANAGED_ROOT" ]]; then
        init_managed_storage
    fi
    
    cd "$MANAGED_ROOT"
    
    # Determine target path
    local filename="$(basename "$source_file")"
    local target_dir="$category"
    local target_path="$target_dir/$filename"
    
    # Handle name conflicts
    local counter=1
    local base_name="${filename%.*}"
    local extension="${filename##*.}"
    
    while [[ -e "$target_path" ]]; do
        if [[ "$filename" == "$extension" ]]; then
            # No extension
            target_path="$target_dir/${base_name}_$counter"
        else
            target_path="$target_dir/${base_name}_$counter.$extension"
        fi
        ((counter++))
    done
    
    # Create category directory if needed
    mkdir -p "$target_dir"
    
    # Copy file to managed storage
    execute_command "cp '$source_file' '$target_path'"
    
    # Add to appropriate version control
    case "$target_tool" in
        "git")
            execute_command "git add '$target_path'"
            execute_command "git commit -m 'Add $filename to managed storage'"
            log_info "File added to Git: $target_path"
            ;;
        "git-annex")
            execute_command "git annex add '$target_path'"
            execute_command "git commit -m 'Add $filename to managed storage (git-annex)'"
            log_info "File added to Git-annex: $target_path"
            ;;
        *)
            log_error "Unknown target tool: $target_tool"
            return 1
            ;;
    esac
    
    echo "$target_path"
}

sync_managed_storage() {
    local path="${1:-.}"
    local mode="${2:-bidirectional}"  # push, pull, bidirectional
    
    log_info "Syncing managed storage: $path (mode: $mode)"
    
    if [[ ! -d "$MANAGED_ROOT" ]]; then
        log_error "Managed storage not initialized at: $MANAGED_ROOT"
        return 1
    fi
    
    cd "$MANAGED_ROOT"
    
    case "$mode" in
        "push")
            # Push Git commits
            if git remote | grep -q origin; then
                execute_command "git push origin main"
            else
                log_warn "No Git remote configured for push"
            fi
            
            # Push Git-annex content to configured remotes
            if [[ -n "${DEFAULT_REMOTE:-}" ]]; then
                execute_command "git annex copy --to=$DEFAULT_REMOTE ."
                execute_command "git annex sync $DEFAULT_REMOTE"
            fi
            ;;
        "pull")
            # Pull Git commits
            if git remote | grep -q origin; then
                execute_command "git pull origin main"
            else
                log_warn "No Git remote configured for pull"
            fi
            
            # Get Git-annex content from remotes
            if [[ -n "${DEFAULT_REMOTE:-}" ]]; then
                execute_command "git annex sync $DEFAULT_REMOTE"
                execute_command "git annex get ."
            fi
            ;;
        "bidirectional")
            # Full sync
            sync_managed_storage "$path" "pull"
            sync_managed_storage "$path" "push"
            ;;
        *)
            log_error "Unknown sync mode: $mode"
            return 1
            ;;
    esac
}

rollback_file() {
    local file_path="$1"
    local target_version="${2:-HEAD~1}"
    
    log_info "Rolling back file in managed storage: $file_path to $target_version"
    
    if [[ ! -d "$MANAGED_ROOT" ]]; then
        log_error "Managed storage not initialized"
        return 1
    fi
    
    cd "$MANAGED_ROOT"
    
    # Check if file exists in managed storage
    if [[ ! -e "$file_path" ]]; then
        log_error "File not found in managed storage: $file_path"
        return 1
    fi
    
    # Rollback using Git
    execute_command "git checkout '$target_version' -- '$file_path'"
    log_info "File rolled back: $file_path to $target_version"
}

get_managed_status() {
    local path="${1:-.}"
    
    if [[ ! -d "$MANAGED_ROOT" ]]; then
        echo "Managed storage not initialized"
        return 1
    fi
    
    cd "$MANAGED_ROOT"
    
    echo "Managed Storage Status"
    echo "======================"
    echo "Root: $MANAGED_ROOT"
    echo "Path: $path"
    echo ""
    
    # Git status
    echo "Git Status:"
    echo "-----------"
    git status --porcelain "$path" 2>/dev/null || echo "No changes"
    echo ""
    
    # Git-annex status
    echo "Git-annex Status:"
    echo "----------------"
    if [[ -d ".git/annex" ]]; then
        git annex info "$path" 2>/dev/null || echo "No annex information"
    else
        echo "Git-annex not initialized"
    fi
    echo ""
    
    # Storage breakdown
    echo "Storage Breakdown:"
    echo "-----------------"
    if command -v du >/dev/null 2>&1; then
        echo "Total size: $(du -sh "$path" 2>/dev/null | cut -f1 || echo "Unknown")"
        
        # Count files by category
        local git_files=$(find "$path" -type f -not -path ".git/*" -exec git ls-files --cached {} \; 2>/dev/null | wc -l)
        local annex_files=$(find "$path" -type l 2>/dev/null | wc -l)
        
        echo "Git files: $git_files"
        echo "Git-annex files: $annex_files"
    fi
}

list_managed_files() {
    local category="${1:-}"
    
    if [[ ! -d "$MANAGED_ROOT" ]]; then
        echo "Managed storage not initialized"
        return 1
    fi
    
    cd "$MANAGED_ROOT"
    
    if [[ -n "$category" ]]; then
        echo "Files in category: $category"
        echo "=========================="
        if [[ -d "$category" ]]; then
            find "$category" -type f -o -type l | sort
        else
            echo "Category not found: $category"
            return 1
        fi
    else
        echo "All managed files:"
        echo "=================="
        find . -type f -o -type l | grep -v "^\.git/" | sort
        echo ""
        echo "Categories:"
        echo "----------"
        find . -maxdepth 1 -type d | grep -v "^\.git$" | grep -v "^\.$" | sort
    fi
}

# CLI interface
show_usage() {
    cat << EOF
CloudSync Managed Storage - Git-based storage management

Usage: $0 <command> [options]

Commands:
    init                    - Initialize managed storage
    promote <file> <tool>   - Promote file to managed storage (tool: git|git-annex)
    sync [path] [mode]      - Sync managed storage (mode: push/pull/bidirectional)
    rollback <file> [rev]   - Rollback file to previous version
    status [path]           - Show managed storage status
    list [category]         - List managed files by category
    
Examples:
    $0 init
    $0 promote ~/document.txt git
    $0 promote ~/video.mp4 git-annex
    $0 sync . push
    $0 rollback documents/file.txt HEAD~2
    $0 status documents/
    $0 list media

Categories:
    documents - Text documents and small files
    code      - Source code and configuration files  
    media     - Images, videos, audio files
    archives  - Compressed archives and backups
EOF
}

# Main execution
main() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 1
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        "init")
            init_managed_storage
            ;;
        "promote")
            if [[ $# -lt 2 ]]; then
                log_error "Promote command requires file and tool arguments"
                exit 1
            fi
            promote_file "$@"
            ;;
        "sync")
            sync_managed_storage "$@"
            ;;
        "rollback")
            if [[ $# -lt 1 ]]; then
                log_error "Rollback command requires a file path"
                exit 1
            fi
            rollback_file "$@"
            ;;
        "status")
            get_managed_status "$@"
            ;;
        "list")
            list_managed_files "$@"
            ;;
        "--help"|"-h")
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage >&2
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"