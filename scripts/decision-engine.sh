#!/bin/bash

# CloudSync Decision Engine
# Smart tool selection logic for Git/Git-annex/rclone routing
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

# Decision engine configuration
LARGE_FILE_THRESHOLD=${LARGE_FILE_THRESHOLD:-100M}
BINARY_FILE_PATTERNS=("*.zip" "*.tar.gz" "*.iso" "*.img" "*.bin" "*.exe" "*.dmg" "*.deb" "*.rpm")
TEXT_FILE_PATTERNS=("*.txt" "*.md" "*.json" "*.yaml" "*.yml" "*.sh" "*.py" "*.js" "*.ts" "*.html" "*.css")
CODE_FILE_PATTERNS=("*.py" "*.js" "*.ts" "*.sh" "*.go" "*.rs" "*.c" "*.cpp" "*.java" "*.rb")

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Context detection functions
detect_git_repo() {
    local path="$1"
    local current_dir="$(cd "$path" 2>/dev/null && pwd || echo "$path")"
    
    while [[ "$current_dir" != "/" ]]; do
        if [[ -d "$current_dir/.git" ]]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done
    
    return 1
}

get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        stat --printf="%s" "$file" 2>/dev/null || echo "0"
    else
        echo "0"
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
    local file_size=$(get_file_size "$file")
    local threshold_bytes=$(convert_size_to_bytes "$LARGE_FILE_THRESHOLD")
    
    [[ "$file_size" -gt "$threshold_bytes" ]]
}

detect_file_type() {
    local file="$1"
    local filename="$(basename "$file")"
    
    # Check for binary patterns
    for pattern in "${BINARY_FILE_PATTERNS[@]}"; do
        if [[ "$filename" == $pattern ]]; then
            echo "binary"
            return 0
        fi
    done
    
    # Check for code patterns
    for pattern in "${CODE_FILE_PATTERNS[@]}"; do
        if [[ "$filename" == $pattern ]]; then
            echo "code"
            return 0
        fi
    done
    
    # Check for text patterns
    for pattern in "${TEXT_FILE_PATTERNS[@]}"; do
        if [[ "$filename" == $pattern ]]; then
            echo "text"
            return 0
        fi
    done
    
    # Use file command as fallback
    if command -v file >/dev/null 2>&1 && [[ -f "$file" ]]; then
        local file_output=$(file -b "$file" 2>/dev/null || echo "")
        if [[ "$file_output" =~ text|ASCII|UTF-8 ]]; then
            echo "text"
        else
            echo "binary"
        fi
    else
        echo "unknown"
    fi
}

is_managed_storage() {
    local path="$1"
    local managed_root="$HOME/cloudsync-managed"
    
    case "$path" in
        "$managed_root"*) return 0 ;;
        *) return 1 ;;
    esac
}

# Decision logic functions
decide_tool_for_add() {
    local file="$1"
    local target_path="${2:-}"
    
    # Validate file exists
    if [[ ! -e "$file" ]]; then
        echo "error:file_not_found"
        return 1
    fi
    
    # Context detection
    local file_type=$(detect_file_type "$file")
    local is_large=$(is_large_file "$file" && echo "true" || echo "false")
    local git_repo_root=""
    
    if git_repo_root=$(detect_git_repo "$(dirname "$file")"); then
        local in_git_repo="true"
    else
        local in_git_repo="false"
    fi
    
    local in_managed=$(is_managed_storage "$file" && echo "true" || echo "false")
    
    # Decision matrix
    if [[ "$in_managed" == "true" ]]; then
        # Files in managed storage always use Git-based versioning
        if [[ "$is_large" == "true" || "$file_type" == "binary" ]]; then
            echo "git-annex:managed"
        else
            echo "git:managed"
        fi
    elif [[ "$in_git_repo" == "true" ]]; then
        # Files in existing Git repos
        if [[ "$is_large" == "true" || "$file_type" == "binary" ]]; then
            echo "git-annex:existing"
        else
            echo "git:existing"
        fi
    else
        # Files outside Git repos - promote to managed storage
        if [[ "$is_large" == "true" || "$file_type" == "binary" ]]; then
            echo "promote:git-annex"
        elif [[ "$file_type" == "code" || "$file_type" == "text" ]]; then
            echo "promote:git"
        else
            echo "rclone:direct"
        fi
    fi
}

decide_tool_for_sync() {
    local path="$1"
    local operation="${2:-bidirectional}"  # bidirectional, push, pull
    
    local git_repo_root=""
    if git_repo_root=$(detect_git_repo "$path"); then
        local in_git_repo="true"
    else
        local in_git_repo="false"
    fi
    
    local in_managed=$(is_managed_storage "$path" && echo "true" || echo "false")
    
    if [[ "$in_managed" == "true" ]]; then
        echo "orchestrator:managed"
    elif [[ "$in_git_repo" == "true" ]]; then
        # Check if git-annex is initialized
        if [[ -d "$git_repo_root/.git/annex" ]]; then
            echo "orchestrator:git-annex"
        else
            echo "git:standard"
        fi
    else
        echo "rclone:$operation"
    fi
}

decide_tool_for_rollback() {
    local path="$1"
    local target_version="${2:-HEAD~1}"
    
    local git_repo_root=""
    if git_repo_root=$(detect_git_repo "$path"); then
        local in_git_repo="true"
    else
        local in_git_repo="false"
    fi
    
    local in_managed=$(is_managed_storage "$path" && echo "true" || echo "false")
    
    if [[ "$in_managed" == "true" || "$in_git_repo" == "true" ]]; then
        echo "git:rollback"
    else
        echo "error:no_version_history"
    fi
}

# Context analysis function
analyze_context() {
    local path="$1"
    local operation="${2:-analyze}"
    
    local result="{"
    
    # Basic path info
    result+='"path":"'"$path"'",'
    result+='"exists":'$(if [[ -e "$path" ]]; then echo "true"; else echo "false"; fi)','
    result+='"type":"'$(if [[ -f "$path" ]]; then echo "file"; elif [[ -d "$path" ]]; then echo "directory"; else echo "unknown"; fi)'",'
    
    if [[ -f "$path" ]]; then
        result+='"file_type":"'$(detect_file_type "$path")'",'
        result+='"size":'$(get_file_size "$path")','
        result+='"is_large":'$(is_large_file "$path" && echo "true" || echo "false")','
    fi
    
    # Git context
    local git_repo_root=""
    if git_repo_root=$(detect_git_repo "$path" 2>/dev/null); then
        result+='"git_repo":"'"$git_repo_root"'",'
        result+='"in_git_repo":true,'
        
        # Check for git-annex
        if [[ -d "$git_repo_root/.git/annex" ]]; then
            result+='"has_git_annex":true,'
        else
            result+='"has_git_annex":false,'
        fi
    else
        result+='"in_git_repo":false,'
        result+='"has_git_annex":false,'
    fi
    
    # Managed storage context
    result+='"in_managed_storage":'$(is_managed_storage "$path" && echo "true" || echo "false")','
    
    # Remove trailing comma and close
    result="${result%,}}"
    
    echo "$result"
}

# Main decision function
make_decision() {
    local operation="$1"
    local path="$2"
    shift 2
    
    case "$operation" in
        "add")
            decide_tool_for_add "$path" "$@"
            ;;
        "sync")
            decide_tool_for_sync "$path" "$@"
            ;;
        "rollback")
            decide_tool_for_rollback "$path" "$@"
            ;;
        "analyze")
            analyze_context "$path" "$@"
            ;;
        *)
            echo "error:unknown_operation"
            return 1
            ;;
    esac
}

# CLI interface
show_usage() {
    cat << EOF
CloudSync Decision Engine - Smart tool selection for Git/Git-annex/rclone

Usage: $0 <operation> <path> [options]

Operations:
    add <file> [target]     - Decide tool for adding file to version control
    sync <path> [mode]      - Decide tool for synchronization (mode: push/pull/bidirectional)
    rollback <path> [rev]   - Decide tool for rollback operation
    analyze <path>          - Analyze context and provide detailed information

Examples:
    $0 add ~/Documents/large-file.zip
    $0 sync ~/project push
    $0 rollback ~/project HEAD~2
    $0 analyze ~/Documents

Output format: tool:context or error:reason
EOF
}

# Main execution
if [[ $# -eq 0 ]]; then
    show_usage
    exit 1
fi

case "$1" in
    "--help"|"-h")
        show_usage
        exit 0
        ;;
    *)
        make_decision "$@"
        ;;
esac