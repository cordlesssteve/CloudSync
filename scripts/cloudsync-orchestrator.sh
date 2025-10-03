#!/bin/bash

# CloudSync Intelligent Orchestrator
# Main orchestrator interface providing unified cloudsync commands
# Coordinates Git, Git-annex, and rclone for optimal cloud storage workflows

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

# Component scripts
DECISION_ENGINE="$SCRIPT_DIR/decision-engine.sh"
MANAGED_STORAGE="$SCRIPT_DIR/managed-storage.sh"
CORE_DIR="$SCRIPT_DIR/core"

# Logging configuration
LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/orchestrator.log"
VERBOSE=${VERBOSE:-false}
DRY_RUN=${DRY_RUN:-false}

# Ensure log directory exists
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
check_dependencies() {
    local missing_deps=()
    
    if ! command -v git >/dev/null 2>&1; then
        missing_deps+=("git")
    fi
    
    if ! command -v rclone >/dev/null 2>&1; then
        missing_deps+=("rclone")
    fi
    
    if ! command -v git-annex >/dev/null 2>&1; then
        log_warn "git-annex not found - large file operations will be limited"
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        return 1
    fi
    
    return 0
}

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

# Core operations
cloudsync_add() {
    local file="$1"
    local target_path="${2:-}"
    
    log_info "Adding file to CloudSync: $file"
    
    # Validate file exists
    if [[ ! -e "$file" ]]; then
        log_error "File does not exist: $file"
        return 1
    fi
    
    # Get decision from decision engine
    local decision
    if ! decision=$("$DECISION_ENGINE" add "$file" "$target_path"); then
        log_error "Decision engine failed for file: $file"
        return 1
    fi
    
    log_debug "Decision engine result: $decision"
    
    # Parse decision
    local tool="${decision%%:*}"
    local context="${decision#*:}"
    
    case "$tool" in
        "git")
            cloudsync_add_git "$file" "$context"
            ;;
        "git-annex")
            cloudsync_add_git_annex "$file" "$context"
            ;;
        "promote")
            cloudsync_add_promote "$file" "$context"
            ;;
        "rclone")
            cloudsync_add_rclone "$file" "$context"
            ;;
        "error")
            log_error "Cannot add file: $context"
            return 1
            ;;
        *)
            log_error "Unknown tool decision: $tool"
            return 1
            ;;
    esac
}

cloudsync_add_git() {
    local file="$1"
    local context="$2"
    
    log_info "Adding file via Git: $file (context: $context)"
    
    local git_root
    if git_root=$("$DECISION_ENGINE" analyze "$file" | grep -o '"git_repo":"[^"]*"' | cut -d'"' -f4); then
        cd "$git_root"
        execute_command "git add '$file'"
        log_info "File added to Git staging area: $file"
    else
        log_error "Could not determine Git repository root for: $file"
        return 1
    fi
}

cloudsync_add_git_annex() {
    local file="$1"
    local context="$2"
    
    log_info "Adding file via Git-annex: $file (context: $context)"
    
    local git_root
    if git_root=$("$DECISION_ENGINE" analyze "$file" | grep -o '"git_repo":"[^"]*"' | cut -d'"' -f4); then
        cd "$git_root"
        
        # Ensure git-annex is initialized
        if [[ ! -d ".git/annex" ]]; then
            log_info "Initializing git-annex in repository: $git_root"
            execute_command "git annex init"
        fi
        
        execute_command "git annex add '$file'"
        log_info "File added to Git-annex: $file"
    else
        log_error "Could not determine Git repository root for: $file"
        return 1
    fi
}

cloudsync_add_promote() {
    local file="$1"
    local target_tool="$2"
    
    log_info "Promoting file to managed storage: $file (tool: $target_tool)"
    
    # Use managed storage script to promote file
    if [[ -x "$MANAGED_STORAGE" ]]; then
        execute_command "'$MANAGED_STORAGE' promote '$file' '$target_tool'"
    else
        log_error "Managed storage script not found or not executable: $MANAGED_STORAGE"
        return 1
    fi
}

cloudsync_add_rclone() {
    local file="$1"
    local context="$2"
    
    log_info "Adding file via rclone: $file (context: $context)"
    
    local remote_path="$DEFAULT_REMOTE:$SYNC_BASE_PATH/$(basename "$file")"
    execute_command "rclone copy '$file' '$remote_path'"
    log_info "File copied to remote storage: $file -> $remote_path"
}

cloudsync_sync() {
    local path="$1"
    local mode="${2:-bidirectional}"  # bidirectional, push, pull
    
    log_info "Synchronizing path: $path (mode: $mode)"
    
    # Get decision from decision engine
    local decision
    if ! decision=$("$DECISION_ENGINE" sync "$path" "$mode"); then
        log_error "Decision engine failed for path: $path"
        return 1
    fi
    
    log_debug "Decision engine result: $decision"
    
    # Parse decision
    local tool="${decision%%:*}"
    local context="${decision#*:}"
    
    case "$tool" in
        "orchestrator")
            cloudsync_sync_orchestrator "$path" "$mode" "$context"
            ;;
        "git")
            cloudsync_sync_git "$path" "$mode" "$context"
            ;;
        "rclone")
            cloudsync_sync_rclone "$path" "$mode" "$context"
            ;;
        "error")
            log_error "Cannot sync path: $context"
            return 1
            ;;
        *)
            log_error "Unknown tool decision: $tool"
            return 1
            ;;
    esac
}

cloudsync_sync_orchestrator() {
    local path="$1"
    local mode="$2"
    local context="$3"
    
    log_info "Orchestrated sync: $path (mode: $mode, context: $context)"
    
    case "$context" in
        "managed")
            # Use managed storage for coordinated sync
            if [[ -x "$MANAGED_STORAGE" ]]; then
                execute_command "'$MANAGED_STORAGE' sync '$path' '$mode'"
            else
                log_error "Managed storage script not available"
                return 1
            fi
            ;;
        "git-annex")
            # Coordinate Git + Git-annex + rclone sync
            cloudsync_sync_git_annex "$path" "$mode"
            ;;
        *)
            log_error "Unknown orchestrator context: $context"
            return 1
            ;;
    esac
}

cloudsync_sync_git() {
    local path="$1"
    local mode="$2"
    local context="$3"
    
    log_info "Git sync: $path (mode: $mode)"
    
    local git_root
    if git_root=$("$DECISION_ENGINE" analyze "$path" | grep -o '"git_repo":"[^"]*"' | cut -d'"' -f4); then
        cd "$git_root"
        
        case "$mode" in
            "push")
                execute_command "git push origin HEAD"
                ;;
            "pull")
                execute_command "git pull origin HEAD"
                ;;
            "bidirectional")
                execute_command "git pull origin HEAD"
                execute_command "git push origin HEAD"
                ;;
        esac
    else
        log_error "Not a Git repository: $path"
        return 1
    fi
}

cloudsync_sync_git_annex() {
    local path="$1"
    local mode="$2"
    
    log_info "Git-annex sync: $path (mode: $mode)"
    
    local git_root
    if git_root=$("$DECISION_ENGINE" analyze "$path" | grep -o '"git_repo":"[^"]*"' | cut -d'"' -f4); then
        cd "$git_root"
        
        case "$mode" in
            "push")
                execute_command "git annex sync --content"
                execute_command "git annex copy --to=$DEFAULT_REMOTE ."
                ;;
            "pull")
                execute_command "git annex sync"
                execute_command "git annex get ."
                ;;
            "bidirectional")
                execute_command "git annex sync --content"
                ;;
        esac
    else
        log_error "Not a Git repository: $path"
        return 1
    fi
}

cloudsync_sync_rclone() {
    local path="$1"
    local mode="$2"
    local context="$3"
    
    log_info "rclone sync: $path (mode: $mode, context: $context)"
    
    local remote_path="$DEFAULT_REMOTE:$SYNC_BASE_PATH/$(basename "$path")"
    
    case "$mode" in
        "push")
            execute_command "rclone sync '$path' '$remote_path'"
            ;;
        "pull")
            execute_command "rclone sync '$remote_path' '$path'"
            ;;
        "bidirectional")
            # Use existing bidirectional sync script
            if [[ -x "$CORE_DIR/bidirectional-sync.sh" ]]; then
                execute_command "'$CORE_DIR/bidirectional-sync.sh' '$path' '$remote_path'"
            else
                log_warn "Bidirectional sync script not found, falling back to manual sync"
                execute_command "rclone sync '$remote_path' '$path'"
                execute_command "rclone sync '$path' '$remote_path'"
            fi
            ;;
    esac
}

cloudsync_rollback() {
    local path="$1"
    local target_version="${2:-HEAD~1}"
    
    log_info "Rolling back path: $path to version: $target_version"
    
    # Get decision from decision engine
    local decision
    if ! decision=$("$DECISION_ENGINE" rollback "$path" "$target_version"); then
        log_error "Decision engine failed for rollback: $path"
        return 1
    fi
    
    log_debug "Decision engine result: $decision"
    
    # Parse decision
    local tool="${decision%%:*}"
    local context="${decision#*:}"
    
    case "$tool" in
        "git")
            cloudsync_rollback_git "$path" "$target_version"
            ;;
        "error")
            log_error "Cannot rollback: $context"
            return 1
            ;;
        *)
            log_error "Unknown tool decision: $tool"
            return 1
            ;;
    esac
}

cloudsync_rollback_git() {
    local path="$1"
    local target_version="$2"
    
    log_info "Git rollback: $path to $target_version"
    
    local git_root
    if git_root=$("$DECISION_ENGINE" analyze "$path" | grep -o '"git_repo":"[^"]*"' | cut -d'"' -f4); then
        cd "$git_root"
        
        # Check if path is a file or directory
        if [[ -f "$path" ]]; then
            execute_command "git checkout '$target_version' -- '$path'"
        else
            execute_command "git checkout '$target_version' -- '$path/'"
        fi
        
        log_info "Rollback completed: $path"
    else
        log_error "Not a Git repository: $path"
        return 1
    fi
}

cloudsync_status() {
    local path="${1:-.}"
    
    log_info "Getting CloudSync status for: $path"
    
    # Analyze context
    local context
    if ! context=$("$DECISION_ENGINE" analyze "$path"); then
        log_error "Failed to analyze path: $path"
        return 1
    fi
    
    echo "CloudSync Status for: $path"
    echo "=================================="
    echo "$context" | jq '.' 2>/dev/null || echo "$context"
    echo ""
    
    # Get additional status based on context
    local in_git_repo=$(echo "$context" | grep -o '"in_git_repo":[^,]*' | cut -d':' -f2)
    local in_managed=$(echo "$context" | grep -o '"in_managed_storage":[^,]*' | cut -d':' -f2)
    
    if [[ "$in_git_repo" == "true" ]]; then
        echo "Git Status:"
        echo "----------"
        if cd "$(dirname "$path")" 2>/dev/null; then
            git status --porcelain "$path" 2>/dev/null || echo "No changes"
        fi
        echo ""
    fi
    
    if [[ "$in_managed" == "true" ]]; then
        echo "Managed Storage Status:"
        echo "----------------------"
        if [[ -x "$MANAGED_STORAGE" ]]; then
            "$MANAGED_STORAGE" status "$path" 2>/dev/null || echo "Status unavailable"
        fi
        echo ""
    fi
}

# CLI interface
show_usage() {
    cat << EOF
CloudSync Intelligent Orchestrator - Unified interface for Git/Git-annex/rclone

Usage: $0 <command> [options]

Commands:
    add <file> [target]     - Add file to version control (smart tool selection)
    sync <path> [mode]      - Synchronize path (mode: push/pull/bidirectional)
    rollback <path> [rev]   - Rollback to previous version
    status [path]           - Show CloudSync status for path
    
Global Options:
    --verbose               - Enable verbose output
    --dry-run              - Show what would be done without executing
    --help                 - Show this help message

Examples:
    $0 add ~/Documents/important-file.txt
    $0 add ~/Videos/large-video.mp4
    $0 sync ~/project push
    $0 sync ~/Documents bidirectional
    $0 rollback ~/project/file.txt HEAD~2
    $0 status ~/project

Environment Variables:
    VERBOSE=true           - Enable verbose logging
    DRY_RUN=true          - Enable dry-run mode
EOF
}

# Main execution
main() {
    # Parse global options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage >&2
                exit 1
                ;;
            *)
                break
                ;;
        esac
    done
    
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 1
    fi
    
    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi
    
    # Execute command
    local command="$1"
    shift
    
    case "$command" in
        "add")
            if [[ $# -lt 1 ]]; then
                log_error "Add command requires a file path"
                exit 1
            fi
            cloudsync_add "$@"
            ;;
        "sync")
            if [[ $# -lt 1 ]]; then
                log_error "Sync command requires a path"
                exit 1
            fi
            cloudsync_sync "$@"
            ;;
        "rollback")
            if [[ $# -lt 1 ]]; then
                log_error "Rollback command requires a path"
                exit 1
            fi
            cloudsync_rollback "$@"
            ;;
        "status")
            cloudsync_status "$@"
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