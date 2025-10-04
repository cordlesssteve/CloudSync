#!/bin/bash

# CloudSync Orchestrator
# Main unified interface that coordinates Git, Git-Annex, and rclone
# Provides single commands: cloudsync add/sync/rollback for all file types

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/managed-storage.conf"
LOG_FILE="${HOME}/.cloudsync/logs/orchestrator.log"
DECISION_ENGINE="${SCRIPT_DIR}/decision-engine.sh"
MANAGED_STORAGE="${SCRIPT_DIR}/managed-storage.sh"

# Ensure dependencies exist
for script in "$DECISION_ENGINE" "$MANAGED_STORAGE"; do
    if [[ ! -f "$script" ]]; then
        echo "❌ Missing dependency: $script"
        exit 1
    fi
done

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log_orchestrator() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
    [[ "${VERBOSE:-false}" == "true" ]] && echo "[$level] $message" >&2
}

# Execute tool-specific action
execute_tool_action() {
    local tool="$1"
    local operation="$2"
    local file_path="$3"
    local context="${4:-}"
    
    log_orchestrator "INFO" "Executing $tool action: $operation on $file_path"
    
    case "$tool" in
        git)
            execute_git_action "$operation" "$file_path"
            ;;
        git-annex)
            execute_git_annex_action "$operation" "$file_path"
            ;;
        git-annex-init)
            execute_git_annex_init "$operation" "$file_path"
            ;;
        rclone)
            execute_rclone_action "$operation" "$file_path"
            ;;
        managed-init)
            execute_managed_init "$operation" "$file_path"
            ;;
        managed-suggest)
            execute_managed_suggest "$operation" "$file_path"
            ;;
        *)
            echo "❌ Unknown tool: $tool"
            return 1
            ;;
    esac
}

# Git operations
execute_git_action() {
    local operation="$1"
    local file_path="$2"
    local dir_path
    
    if [[ -d "$file_path" ]]; then
        dir_path="$file_path"
    else
        dir_path="$(dirname "$file_path")"
    fi
    
    cd "$dir_path"
    
    case "$operation" in
        add)
            echo "📝 Adding to Git: $(basename "$file_path")"
            git add "$file_path"
            git commit -m "Add $(basename "$file_path")

Added by CloudSync orchestrator
Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Size: $(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || echo "unknown")"
            echo "✅ Added to Git and committed"
            ;;
        sync)
            echo "🔄 Syncing Git repository..."
            git pull --rebase
            git push
            echo "✅ Git sync complete"
            ;;
        remove)
            echo "🗑️  Removing from Git: $(basename "$file_path")"
            git rm "$file_path"
            git commit -m "Remove $(basename "$file_path")"
            echo "✅ Removed from Git"
            ;;
        *)
            echo "❌ Unknown Git operation: $operation"
            return 1
            ;;
    esac
}

# Git-Annex operations
execute_git_annex_action() {
    local operation="$1"
    local file_path="$2"
    local dir_path
    
    if [[ -d "$file_path" ]]; then
        dir_path="$file_path"
    else
        dir_path="$(dirname "$file_path")"
    fi
    
    cd "$dir_path"
    
    case "$operation" in
        add)
            echo "📦 Adding to Git-Annex: $(basename "$file_path")"
            git annex add "$file_path"
            git commit -m "Add $(basename "$file_path") to Git-Annex

Added by CloudSync orchestrator
Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Size: $(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || echo "unknown")"
            echo "✅ Added to Git-Annex and committed"
            ;;
        sync)
            echo "🔄 Syncing Git-Annex repository..."
            git annex sync --content
            echo "✅ Git-Annex sync complete"
            ;;
        remove)
            echo "🗑️  Removing from Git-Annex: $(basename "$file_path")"
            git annex drop "$file_path"
            git rm "$file_path"
            git commit -m "Remove $(basename "$file_path") from Git-Annex"
            echo "✅ Removed from Git-Annex"
            ;;
        *)
            echo "❌ Unknown Git-Annex operation: $operation"
            return 1
            ;;
    esac
}

# Git-Annex initialization
execute_git_annex_init() {
    local operation="$1"
    local file_path="$2"
    local dir_path
    
    if [[ -d "$file_path" ]]; then
        dir_path="$file_path"
    else
        dir_path="$(dirname "$file_path")"
    fi
    
    cd "$dir_path"
    
    echo "🔧 Initializing Git-Annex in repository..."
    git annex init "cloudsync-$(hostname)-$(date +%s)"
    
    # Now add the file
    execute_git_annex_action "$operation" "$file_path"
}

# rclone operations
execute_rclone_action() {
    local operation="$1"
    local file_path="$2"
    
    case "$operation" in
        add|sync)
            echo "☁️  Copying to cloud: $(basename "$file_path")"
            local remote_path="DevEnvironment/$(basename "$file_path")"
            rclone copy "$file_path" "onedrive:$remote_path"
            echo "✅ Copied to cloud storage"
            ;;
        remove)
            echo "🗑️  Removing from cloud: $(basename "$file_path")"
            local remote_path="DevEnvironment/$(basename "$file_path")"
            rclone delete "onedrive:$remote_path"
            echo "✅ Removed from cloud storage"
            ;;
        *)
            echo "❌ Unknown rclone operation: $operation"
            return 1
            ;;
    esac
}

# Managed storage initialization
execute_managed_init() {
    local operation="$1"
    local file_path="$2"
    
    echo "🏗️  Initializing managed storage for file..."
    "$MANAGED_STORAGE" init
    
    if [[ "$operation" == "add" ]]; then
        echo "📁 Adding file to managed storage..."
        "$MANAGED_STORAGE" add "$file_path"
    fi
}

# Managed storage suggestion
execute_managed_suggest() {
    local operation="$1"
    local file_path="$2"
    
    echo "💡 Suggestion: This file could benefit from managed versioning"
    echo "   File: $file_path"
    echo "   To add to managed storage: cloudsync managed-add '$file_path'"
    echo "   To initialize managed storage: cloudsync managed-init"
}

# Main add command
cmd_add() {
    local file_path="$1"
    local context="${2:-}"
    
    if [[ ! -e "$file_path" ]]; then
        echo "❌ File or directory not found: $file_path"
        return 1
    fi
    
    # Get absolute path
    file_path="$(realpath "$file_path")"
    
    echo "🎯 CloudSync Add: $file_path"
    
    # Use decision engine to determine best tool
    local decision_output
    decision_output=$(MACHINE_READABLE=true "$DECISION_ENGINE" add "$file_path" "$context")
    
    # Parse decision
    local tool reason
    tool=$(echo "$decision_output" | grep "^TOOL:" | cut -d: -f2)
    reason=$(echo "$decision_output" | grep "^REASON:" | cut -d: -f2-)
    
    echo "🧠 Decision: $tool"
    echo "   Reason: $reason"
    echo ""
    
    # Execute action
    execute_tool_action "$tool" "add" "$file_path" "$context"
}

# Main sync command
cmd_sync() {
    local path="${1:-.}"
    local direction="${2:-both}"  # push, pull, both
    
    # Get absolute path
    path="$(realpath "$path")"
    
    echo "🔄 CloudSync Sync: $path (direction: $direction)"
    
    # Use decision engine to determine approach
    local decision_output
    decision_output=$(MACHINE_READABLE=true "$DECISION_ENGINE" sync "$path")
    
    # Parse decision
    local tool reason
    tool=$(echo "$decision_output" | grep "^TOOL:" | cut -d: -f2)
    reason=$(echo "$decision_output" | grep "^REASON:" | cut -d: -f2-)
    
    echo "🧠 Decision: $tool"
    echo "   Reason: $reason"
    echo ""
    
    # Execute sync
    execute_tool_action "$tool" "sync" "$path"
}

# Rollback functionality
cmd_rollback() {
    local file_path="$1"
    local target="${2:-HEAD~1}"  # Default to previous commit
    
    if [[ ! -e "$file_path" ]]; then
        echo "❌ File not found: $file_path"
        return 1
    fi
    
    # Get absolute path
    file_path="$(realpath "$file_path")"
    
    echo "⏪ CloudSync Rollback: $file_path to $target"
    
    # Determine which system manages this file
    local decision_output
    decision_output=$(MACHINE_READABLE=true "$DECISION_ENGINE" analyze "$file_path")
    
    local tool
    tool=$(echo "$decision_output" | grep "^TOOL:" | cut -d: -f2)
    
    echo "🧠 File managed by: $tool"
    
    case "$tool" in
        git|git-annex)
            local dir_path
            if [[ -d "$file_path" ]]; then
                dir_path="$file_path"
            else
                dir_path="$(dirname "$file_path")"
            fi
            
            cd "$dir_path"
            echo "📜 Git history for $(basename "$file_path"):"
            git log --oneline --follow "$(basename "$file_path")" | head -5
            echo ""
            
            read -p "Rollback to commit $target? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                git checkout "$target" -- "$(basename "$file_path")"
                git commit -m "Rollback $(basename "$file_path") to $target"
                echo "✅ Rolled back to $target"
            else
                echo "❌ Rollback cancelled"
            fi
            ;;
        rclone)
            echo "❌ Rollback not supported for files managed by rclone only"
            echo "💡 Consider moving to managed storage for version control"
            ;;
        *)
            echo "❌ Cannot rollback: file not under version control"
            ;;
    esac
}

# Status command
cmd_status() {
    local path="${1:-.}"
    
    # Get absolute path
    path="$(realpath "$path")"
    
    echo "📊 CloudSync Status: $path"
    
    # Use decision engine to analyze
    local decision_output
    decision_output=$(MACHINE_READABLE=true "$DECISION_ENGINE" analyze "$path")
    
    # Parse decision
    local tool reason size type
    tool=$(echo "$decision_output" | grep "^TOOL:" | cut -d: -f2)
    reason=$(echo "$decision_output" | grep "^REASON:" | cut -d: -f2-)
    size=$(echo "$decision_output" | grep "^SIZE:" | cut -d: -f2)
    type=$(echo "$decision_output" | grep "^TYPE:" | cut -d: -f2)
    
    echo "  Path: $path"
    echo "  Size: $size bytes"
    echo "  Type: $type"
    echo "  Managed by: $tool"
    echo "  Context: $reason"
    
    # Show repository status if applicable
    if [[ "$tool" =~ ^git ]]; then
        local dir_path
        if [[ -d "$path" ]]; then
            dir_path="$path"
        else
            dir_path="$(dirname "$path")"
        fi
        
        echo ""
        echo "📂 Repository Status:"
        (cd "$dir_path" && git status --short)
        
        if git -C "$dir_path" config --get annex.uuid >/dev/null 2>&1; then
            echo ""
            echo "📦 Git-Annex Status:"
            (cd "$dir_path" && git annex info --fast)
        fi
    fi
}

# Managed storage commands
cmd_managed_init() {
    echo "🏗️  Initializing CloudSync Managed Storage..."
    "$MANAGED_STORAGE" init "$@"
}

cmd_managed_add() {
    local file_path="$1"
    shift
    
    echo "📁 Adding to Managed Storage: $file_path"
    "$MANAGED_STORAGE" add "$file_path" "$@"
}

cmd_managed_sync() {
    echo "🔄 Syncing Managed Storage..."
    "$MANAGED_STORAGE" sync "$@"
}

cmd_managed_list() {
    echo "📂 Managed Storage Contents:"
    "$MANAGED_STORAGE" list "$@"
}

cmd_managed_status() {
    echo "📊 Managed Storage Status:"
    "$MANAGED_STORAGE" status
}

# Decision engine passthrough
cmd_analyze() {
    local file_path="$1"
    local context="${2:-}"
    
    echo "🧠 Decision Engine Analysis:"
    "$DECISION_ENGINE" analyze "$file_path" "$context"
}

# Main execution
main() {
    local command="${1:-}"
    
    # Set up logging
    log_orchestrator "INFO" "CloudSync orchestrator started: $*"
    
    case "$command" in
        add)
            shift
            cmd_add "$@"
            ;;
        sync)
            shift
            cmd_sync "$@"
            ;;
        rollback)
            shift
            cmd_rollback "$@"
            ;;
        status)
            shift
            cmd_status "$@"
            ;;
        analyze)
            shift
            cmd_analyze "$@"
            ;;
        managed-init)
            shift
            cmd_managed_init "$@"
            ;;
        managed-add)
            shift
            cmd_managed_add "$@"
            ;;
        managed-sync)
            shift
            cmd_managed_sync "$@"
            ;;
        managed-list)
            shift
            cmd_managed_list "$@"
            ;;
        managed-status)
            shift
            cmd_managed_status "$@"
            ;;
        *)
            cat <<EOF
CloudSync Orchestrator - Intelligent Git + Git-Annex + rclone coordination

Usage: $(basename "$0") <command> [options]

Core Commands:
  add <file> [context]              - Add file using optimal tool
  sync [path] [direction]           - Sync using appropriate method
  rollback <file> [target]          - Rollback file to previous version
  status [path]                     - Show status and management info
  analyze <file> [context]          - Analyze file without action

Managed Storage Commands:
  managed-init [--force]            - Initialize managed storage
  managed-add <file> [category]     - Add file to managed storage
  managed-sync [direction]          - Sync managed storage
  managed-list [category]           - List managed files
  managed-status                    - Show managed storage status

Context Options:
  managed                           - Force managed storage
  force=<tool>                      - Force specific tool
  prefer=<tool>                     - Prefer specific tool

Examples:
  $(basename "$0") add /path/to/document.txt
  $(basename "$0") add /path/to/large.zip managed
  $(basename "$0") sync . push
  $(basename "$0") rollback important.txt HEAD~2
  $(basename "$0") status /path/to/project/
  $(basename "$0") managed-init
  $(basename "$0") managed-add /path/to/config.yaml configs

The orchestrator automatically chooses between Git, Git-Annex, and rclone based on:
- File size and type
- Repository context
- User preferences
- Performance optimization
EOF
            [[ -n "$command" ]] && exit 1 || exit 0
            ;;
    esac
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi