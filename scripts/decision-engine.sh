#!/bin/bash

# CloudSync Decision Engine
# Intelligent tool selection based on file context and user intent
# Routes operations to Git, Git-Annex, or rclone based on optimal strategy

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/managed-storage.conf"
LOG_FILE="${HOME}/.cloudsync/logs/decision-engine.log"

# Default thresholds
DEFAULT_LARGE_FILE_THRESHOLD=$((10 * 1024 * 1024))  # 10MB
DEFAULT_BINARY_EXTENSIONS="jpg|jpeg|png|gif|bmp|tiff|mp4|avi|mkv|mov|mp3|wav|flac|zip|tar|gz|7z|rar|exe|dmg|iso|pdf"
DEFAULT_TEXT_EXTENSIONS="txt|md|py|js|ts|jsx|tsx|c|cpp|h|hpp|java|go|rs|sh|bash|zsh|json|xml|yaml|yml|toml|ini|conf|cfg|css|html|scss|sass"

# Load configuration if exists
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Use config values or defaults
LARGE_FILE_THRESHOLD="${LARGE_FILE_THRESHOLD:-$DEFAULT_LARGE_FILE_THRESHOLD}"
BINARY_EXTENSIONS="${BINARY_EXTENSIONS:-$DEFAULT_BINARY_EXTENSIONS}"
TEXT_EXTENSIONS="${TEXT_EXTENSIONS:-$DEFAULT_TEXT_EXTENSIONS}"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log_decision() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
    [[ "${VERBOSE:-false}" == "true" ]] && echo "[$level] $message" >&2
}

# Check if file is in a git repository
is_git_repo() {
    local file_path="$1"
    local dir_path
    
    if [[ -d "$file_path" ]]; then
        dir_path="$file_path"
    else
        dir_path="$(dirname "$file_path")"
    fi
    
    (cd "$dir_path" && git rev-parse --is-inside-work-tree >/dev/null 2>&1)
}

# Check if git-annex is initialized in repo
is_git_annex_repo() {
    local file_path="$1"
    local dir_path
    
    if [[ -d "$file_path" ]]; then
        dir_path="$file_path"
    else
        dir_path="$(dirname "$file_path")"
    fi
    
    [[ -d "${dir_path}/.git/annex" ]] || (cd "$dir_path" && git config --get annex.uuid >/dev/null 2>&1)
}

# Get file size in bytes
get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Detect file type based on extension
get_file_type() {
    local file="$1"
    local extension="${file##*.}"
    extension="${extension,,}"  # Convert to lowercase
    
    if [[ "$file" == *.* ]]; then
        if [[ "$extension" =~ ^($TEXT_EXTENSIONS)$ ]]; then
            echo "text"
        elif [[ "$extension" =~ ^($BINARY_EXTENSIONS)$ ]]; then
            echo "binary"
        else
            # Use file command as fallback
            if file -b "$file" 2>/dev/null | grep -qi "text"; then
                echo "text"
            else
                echo "binary"
            fi
        fi
    else
        # No extension - use file command
        if [[ -f "$file" ]] && file -b "$file" 2>/dev/null | grep -qi "text"; then
            echo "text"
        else
            echo "binary"
        fi
    fi
}

# Check if file matches gitignore patterns
is_git_ignored() {
    local file="$1"
    local dir_path
    
    if [[ -d "$file" ]]; then
        dir_path="$file"
    else
        dir_path="$(dirname "$file")"
    fi
    
    if is_git_repo "$file"; then
        (cd "$dir_path" && git check-ignore "$file" >/dev/null 2>&1)
    else
        return 1
    fi
}

# Main decision function
decide_tool() {
    local operation="$1"  # add, sync, remove, etc.
    local file_path="$2"
    local context="${3:-}"  # Optional context hints
    
    local decision=""
    local reason=""
    local file_size
    local file_type
    
    log_decision "INFO" "Analyzing: operation=$operation, file=$file_path, context=$context"
    
    # Check if path exists
    if [[ ! -e "$file_path" ]]; then
        if [[ "$operation" == "remove" ]] || [[ "$operation" == "delete" ]]; then
            # For removal, check which system knows about it
            if is_git_repo "$(dirname "$file_path")"; then
                decision="git"
                reason="File in git repository (for removal)"
            else
                decision="rclone"
                reason="File not in git repository (for removal)"
            fi
        else
            decision="error"
            reason="Path does not exist: $file_path"
        fi
    else
        # Get file properties
        file_size=$(get_file_size "$file_path")
        file_type=$(get_file_type "$file_path")
        
        log_decision "DEBUG" "File properties: size=$file_size bytes, type=$file_type"
        
        # Decision tree
        if is_git_repo "$file_path"; then
            # File is in a git repository
            if is_git_annex_repo "$file_path"; then
                # Git-annex is available
                if [[ "$file_size" -gt "$LARGE_FILE_THRESHOLD" ]]; then
                    decision="git-annex"
                    reason="Large file ($file_size bytes) in git-annex enabled repo"
                elif [[ "$file_type" == "binary" ]] && [[ "$file_size" -gt $((1024 * 1024)) ]]; then
                    # Binary files over 1MB go to git-annex
                    decision="git-annex"
                    reason="Binary file over 1MB in git-annex enabled repo"
                else
                    decision="git"
                    reason="Small/text file in git repository"
                fi
            else
                # Regular git repo without annex
                if [[ "$file_size" -gt "$LARGE_FILE_THRESHOLD" ]]; then
                    decision="git-annex-init"
                    reason="Large file needs git-annex initialization"
                else
                    decision="git"
                    reason="File in git repository"
                fi
            fi
        else
            # Not in a git repository
            if [[ "$context" == "managed" ]] || [[ "$file_path" == *"/csync-managed/"* ]]; then
                # File should be in managed storage
                decision="managed-init"
                reason="File needs managed storage initialization"
            elif [[ "$file_size" -gt "$LARGE_FILE_THRESHOLD" ]]; then
                # Large file outside git - use rclone directly
                decision="rclone"
                reason="Large file outside git repository"
            elif [[ "$operation" == "sync" ]]; then
                # Sync operation outside git - use rclone
                decision="rclone"
                reason="Sync operation outside git repository"
            else
                # Suggest managed storage for versioning
                decision="managed-suggest"
                reason="File could benefit from managed versioning"
            fi
        fi
    fi
    
    log_decision "INFO" "Decision: tool=$decision, reason=$reason"
    
    # Output decision in parseable format
    echo "TOOL:$decision"
    echo "REASON:$reason"
    echo "SIZE:$file_size"
    echo "TYPE:$file_type"
    
    return 0
}

# Parse context hints
parse_context() {
    local context_string="$1"
    
    # Parse key=value pairs
    while IFS='=' read -r key value; do
        case "$key" in
            force)
                echo "FORCE:$value"
                ;;
            prefer)
                echo "PREFER:$value"
                ;;
            managed)
                echo "MANAGED:true"
                ;;
        esac
    done <<< "$(echo "$context_string" | tr ',' '\n')"
}

# Recommend action based on decision
recommend_action() {
    local tool="$1"
    local operation="$2"
    local file_path="$3"
    
    case "$tool" in
        git)
            case "$operation" in
                add)
                    echo "git add '$file_path' && git commit -m 'Add $(basename "$file_path")'"
                    ;;
                sync)
                    echo "git pull && git push"
                    ;;
                remove)
                    echo "git rm '$file_path' && git commit -m 'Remove $(basename "$file_path")'"
                    ;;
            esac
            ;;
        git-annex)
            case "$operation" in
                add)
                    echo "git annex add '$file_path' && git commit -m 'Add $(basename "$file_path")'"
                    ;;
                sync)
                    echo "git annex sync --content"
                    ;;
                remove)
                    echo "git annex drop '$file_path' && git rm '$file_path'"
                    ;;
            esac
            ;;
        git-annex-init)
            echo "cd '$(dirname "$file_path")' && git annex init && git annex add '$file_path'"
            ;;
        rclone)
            case "$operation" in
                add|sync)
                    echo "rclone copy '$file_path' onedrive:DevEnvironment/$(dirname "$file_path")"
                    ;;
                remove)
                    echo "rclone delete 'onedrive:DevEnvironment/$file_path'"
                    ;;
            esac
            ;;
        managed-init)
            echo "cloudsync managed-init '$file_path'"
            ;;
        managed-suggest)
            echo "# Consider: cloudsync managed-add '$file_path' (for version control)"
            ;;
    esac
}

# Main execution
main() {
    local operation="${1:-}"
    local file_path="${2:-}"
    local context="${3:-}"
    
    if [[ -z "$operation" ]] || [[ -z "$file_path" ]]; then
        cat <<EOF
Usage: $(basename "$0") <operation> <file_path> [context]

Operations:
  add     - Add file to cloud storage
  sync    - Synchronize file/directory
  remove  - Remove file from storage
  analyze - Analyze file without action

Context (optional):
  managed       - Force managed storage
  force=<tool>  - Force specific tool (git/git-annex/rclone)
  prefer=<tool> - Prefer specific tool if applicable

Examples:
  $(basename "$0") add /path/to/file.txt
  $(basename "$0") add /path/to/large.zip managed
  $(basename "$0") sync /path/to/project
  $(basename "$0") analyze /path/to/file.dat
EOF
        exit 1
    fi
    
    # Resolve absolute path
    file_path="$(realpath "$file_path" 2>/dev/null || echo "$file_path")"
    
    # Make decision
    local decision_output
    decision_output=$(decide_tool "$operation" "$file_path" "$context")
    
    # Parse decision
    local tool reason size type
    tool=$(echo "$decision_output" | grep "^TOOL:" | cut -d: -f2)
    reason=$(echo "$decision_output" | grep "^REASON:" | cut -d: -f2-)
    size=$(echo "$decision_output" | grep "^SIZE:" | cut -d: -f2)
    type=$(echo "$decision_output" | grep "^TYPE:" | cut -d: -f2)
    
    # Output decision
    if [[ "${MACHINE_READABLE:-false}" == "true" ]]; then
        echo "$decision_output"
    else
        echo "Decision Engine Analysis:"
        echo "  File: $file_path"
        echo "  Size: $size bytes"
        echo "  Type: $type"
        echo "  Tool: $tool"
        echo "  Reason: $reason"
        echo ""
        echo "Recommended action:"
        recommend_action "$tool" "$operation" "$file_path"
    fi
    
    # Return appropriate exit code
    [[ "$tool" == "error" ]] && exit 1
    exit 0
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi