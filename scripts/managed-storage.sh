#!/bin/bash

# CloudSync Managed Storage
# Git-based storage management with unified versioning
# Creates and manages ~/cloudsync-managed/ with Git foundation

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/managed-storage.conf"
LOG_FILE="${HOME}/.cloudsync/logs/managed-storage.log"
MANAGED_DIR="${HOME}/cloudsync-managed"

# Default configuration
DEFAULT_REMOTE_NAME="onedrive"
DEFAULT_REMOTE_PATH="DevEnvironment/managed"
DEFAULT_GIT_ANNEX_DIRS="projects:archives:media"
DEFAULT_GIT_DIRS="configs:documents:scripts"

# Load configuration if exists
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Use config values or defaults
REMOTE_NAME="${REMOTE_NAME:-$DEFAULT_REMOTE_NAME}"
REMOTE_PATH="${REMOTE_PATH:-$DEFAULT_REMOTE_PATH}"
GIT_ANNEX_DIRS="${GIT_ANNEX_DIRS:-$DEFAULT_GIT_ANNEX_DIRS}"
GIT_DIRS="${GIT_DIRS:-$DEFAULT_GIT_DIRS}"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log_managed() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
    [[ "${VERBOSE:-false}" == "true" ]] && echo "[$level] $message" >&2
}

# Initialize managed storage directory
init_managed_storage() {
    local force="${1:-false}"
    
    log_managed "INFO" "Initializing managed storage at $MANAGED_DIR"
    
    if [[ -d "$MANAGED_DIR" ]] && [[ "$force" != "true" ]]; then
        echo "Managed storage already exists at $MANAGED_DIR"
        echo "Use 'init --force' to reinitialize"
        return 1
    fi
    
    # Create directory structure
    mkdir -p "$MANAGED_DIR"
    cd "$MANAGED_DIR"
    
    # Initialize Git repository
    if [[ ! -d ".git" ]]; then
        log_managed "INFO" "Initializing Git repository"
        git init
        
        # Configure Git for managed storage
        git config user.name "${GIT_USER_NAME:-CloudSync}"
        git config user.email "${GIT_USER_EMAIL:-cloudsync@local}"
        git config init.defaultBranch main
    fi
    
    # Create directory structure
    log_managed "INFO" "Creating directory structure"
    IFS=':' read -ra DIRS <<< "$GIT_DIRS"
    for dir in "${DIRS[@]}"; do
        mkdir -p "$dir"
        echo "# $dir" > "$dir/README.md"
        echo "This directory contains ${dir} managed by CloudSync." >> "$dir/README.md"
    done
    
    IFS=':' read -ra ANNEX_DIRS <<< "$GIT_ANNEX_DIRS"
    for dir in "${ANNEX_DIRS[@]}"; do
        mkdir -p "$dir"
        echo "# $dir" > "$dir/README.md"
        echo "This directory contains large files (${dir}) managed by Git-Annex." >> "$dir/README.md"
    done
    
    # Create CloudSync metadata directory
    mkdir -p ".cloudsync"
    
    # Create .gitignore
    cat > .gitignore << 'EOF'
# CloudSync temporary files
.cloudsync/tmp/
.cloudsync/cache/
*.cloudsync-tmp

# System files
.DS_Store
Thumbs.db

# Editor files
*~
.*.swp
.*.swo
EOF
    
    # Create initial gitattributes for Git-Annex
    cat > .gitattributes << EOF
# Git-Annex configuration for large files
$(echo "$GIT_ANNEX_DIRS" | tr ':' '\n' | sed 's/^//')/** annex.largefiles=anything
$(echo "$GIT_DIRS" | tr ':' '\n' | sed 's/^//')/** annex.largefiles=nothing

# Specific patterns for Git-Annex
*.zip annex.largefiles=anything
*.tar.gz annex.largefiles=anything
*.mp4 annex.largefiles=anything
*.mov annex.largefiles=anything
*.avi annex.largefiles=anything
*.jpg annex.largefiles=anything
*.jpeg annex.largefiles=anything
*.png annex.largefiles=anything
*.pdf annex.largefiles=(largerthan=1mb)

# Keep these in Git
*.md annex.largefiles=nothing
*.txt annex.largefiles=nothing
*.json annex.largefiles=nothing
*.yaml annex.largefiles=nothing
*.yml annex.largefiles=nothing
EOF
    
    # Initialize Git-Annex
    log_managed "INFO" "Initializing Git-Annex"
    git annex init "cloudsync-managed-$(hostname)"
    
    # Configure Git-Annex remote
    if command -v rclone >/dev/null 2>&1; then
        log_managed "INFO" "Configuring rclone remote for Git-Annex"
        git annex initremote "$REMOTE_NAME" \
            type=external \
            externaltype=rclone \
            target="$REMOTE_NAME" \
            prefix="$REMOTE_PATH/" \
            encryption=none \
            chunk=50MiB
    fi
    
    # Create initial commit
    git add .
    git commit -m "Initialize CloudSync managed storage

Created by CloudSync orchestrator with:
- Git directories: $GIT_DIRS
- Git-Annex directories: $GIT_ANNEX_DIRS
- Remote: $REMOTE_NAME:$REMOTE_PATH"
    
    # Create configuration file
    cat > .cloudsync/config << EOF
# CloudSync Managed Storage Configuration
CREATED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
VERSION=1.0
HOSTNAME=$(hostname)
GIT_DIRS="$GIT_DIRS"
GIT_ANNEX_DIRS="$GIT_ANNEX_DIRS"
REMOTE_NAME="$REMOTE_NAME"
REMOTE_PATH="$REMOTE_PATH"
EOF
    
    echo "✅ Managed storage initialized at $MANAGED_DIR"
    echo "📁 Git directories: $GIT_DIRS"
    echo "📦 Git-Annex directories: $GIT_ANNEX_DIRS"
    echo "☁️  Remote: $REMOTE_NAME:$REMOTE_PATH"
    
    log_managed "INFO" "Managed storage initialization complete"
    return 0
}

# Add file to managed storage
add_to_managed() {
    local file_path="$1"
    local target_category="${2:-}"
    local copy_mode="${3:-move}"  # move, copy, or link
    
    if [[ ! -d "$MANAGED_DIR" ]]; then
        echo "❌ Managed storage not initialized. Run: cloudsync managed-init"
        return 1
    fi
    
    if [[ ! -f "$file_path" ]]; then
        echo "❌ File not found: $file_path"
        return 1
    fi
    
    cd "$MANAGED_DIR"
    
    # Determine target category if not specified
    if [[ -z "$target_category" ]]; then
        target_category=$(determine_category "$file_path")
    fi
    
    # Validate category
    if ! is_valid_category "$target_category"; then
        echo "❌ Invalid category: $target_category"
        echo "Valid categories: $(echo "$GIT_DIRS:$GIT_ANNEX_DIRS" | tr ':' ' ')"
        return 1
    fi
    
    local filename
    filename="$(basename "$file_path")"
    local target_path="$target_category/$filename"
    
    # Check if file already exists
    if [[ -f "$target_path" ]]; then
        echo "⚠️  File already exists: $target_path"
        echo "Use --force to overwrite"
        return 1
    fi
    
    log_managed "INFO" "Adding $file_path to managed storage as $target_path"
    
    # Copy/move file
    case "$copy_mode" in
        move)
            mv "$file_path" "$target_path"
            echo "📁 Moved: $file_path → $target_path"
            ;;
        copy)
            cp "$file_path" "$target_path"
            echo "📁 Copied: $file_path → $target_path"
            ;;
        link)
            ln "$file_path" "$target_path"
            echo "📁 Linked: $file_path → $target_path"
            ;;
        *)
            echo "❌ Invalid copy mode: $copy_mode"
            return 1
            ;;
    esac
    
    # Add to version control
    if is_git_annex_category "$target_category"; then
        log_managed "INFO" "Adding to Git-Annex: $target_path"
        git annex add "$target_path"
        echo "📦 Added to Git-Annex: $target_path"
    else
        log_managed "INFO" "Adding to Git: $target_path"
        git add "$target_path"
        echo "📝 Added to Git: $target_path"
    fi
    
    # Commit changes
    git commit -m "Add $filename to $target_category

File: $filename
Category: $target_category
Source: $file_path
Mode: $copy_mode
Size: $(stat -f%z "$target_path" 2>/dev/null || stat -c%s "$target_path" 2>/dev/null || echo "unknown")
Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    
    echo "✅ File added to managed storage and committed"
    return 0
}

# Determine appropriate category for a file
determine_category() {
    local file_path="$1"
    local filename extension size
    
    filename="$(basename "$file_path")"
    extension="${filename##*.}"
    extension="${extension,,}"
    size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || echo "0")
    
    # Rule-based categorization
    case "$extension" in
        # Configuration files
        conf|cfg|ini|yaml|yml|json|toml)
            echo "configs"
            ;;
        # Documentation
        md|txt|doc|docx|rtf)
            echo "documents"
            ;;
        # Scripts
        sh|bash|zsh|py|js|ts|rb|pl)
            echo "scripts"
            ;;
        # Large media files (Git-Annex)
        mp4|mov|avi|mkv|mp3|wav|flac|jpg|jpeg|png|gif|bmp|tiff)
            echo "media"
            ;;
        # Archives (Git-Annex)
        zip|tar|gz|7z|rar|dmg|iso)
            echo "archives"
            ;;
        # Large files (>10MB) go to projects
        *)
            if [[ "$size" -gt $((10 * 1024 * 1024)) ]]; then
                echo "projects"
            else
                echo "documents"
            fi
            ;;
    esac
}

# Check if category is valid
is_valid_category() {
    local category="$1"
    local all_categories="$GIT_DIRS:$GIT_ANNEX_DIRS"
    
    [[ ":$all_categories:" == *":$category:"* ]]
}

# Check if category uses Git-Annex
is_git_annex_category() {
    local category="$1"
    
    [[ ":$GIT_ANNEX_DIRS:" == *":$category:"* ]]
}

# Sync managed storage
sync_managed() {
    local direction="${1:-both}"  # push, pull, or both
    
    if [[ ! -d "$MANAGED_DIR" ]]; then
        echo "❌ Managed storage not initialized. Run: cloudsync managed-init"
        return 1
    fi
    
    cd "$MANAGED_DIR"
    
    log_managed "INFO" "Syncing managed storage (direction: $direction)"
    
    case "$direction" in
        pull|both)
            echo "📥 Pulling changes..."
            git pull
            git annex sync --content
            ;;
    esac
    
    case "$direction" in
        push|both)
            echo "📤 Pushing changes..."
            git push
            git annex sync --content
            if git annex find --want-get | head -1 >/dev/null; then
                echo "📦 Copying content to remote..."
                git annex copy --to="$REMOTE_NAME"
            fi
            ;;
    esac
    
    echo "✅ Sync complete"
    return 0
}

# Promote file from external location to managed storage
promote_file() {
    local file_path="$1"
    local tool="${2:-auto}"  # git, git-annex, or auto
    local category="${3:-auto}"
    
    log_managed "INFO" "Promoting $file_path to managed storage"
    
    if [[ "$category" == "auto" ]]; then
        category=$(determine_category "$file_path")
    fi
    
    if [[ "$tool" == "auto" ]]; then
        if is_git_annex_category "$category"; then
            tool="git-annex"
        else
            tool="git"
        fi
    fi
    
    echo "📈 Promoting file to managed storage:"
    echo "  File: $file_path"
    echo "  Category: $category"
    echo "  Tool: $tool"
    
    add_to_managed "$file_path" "$category" "move"
}

# List managed storage contents
list_managed() {
    local category="${1:-}"
    local show_status="${2:-false}"
    
    if [[ ! -d "$MANAGED_DIR" ]]; then
        echo "❌ Managed storage not initialized. Run: cloudsync managed-init"
        return 1
    fi
    
    cd "$MANAGED_DIR"
    
    if [[ -n "$category" ]]; then
        if [[ ! -d "$category" ]]; then
            echo "❌ Category not found: $category"
            return 1
        fi
        echo "📂 Contents of $category:"
        find "$category" -type f | sort
    else
        echo "📂 Managed Storage Contents:"
        IFS=':' read -ra ALL_DIRS <<< "$GIT_DIRS:$GIT_ANNEX_DIRS"
        for dir in "${ALL_DIRS[@]}"; do
            if [[ -d "$dir" ]]; then
                local count
                count=$(find "$dir" -type f | wc -l)
                if is_git_annex_category "$dir"; then
                    echo "  📦 $dir/ ($count files, Git-Annex)"
                else
                    echo "  📝 $dir/ ($count files, Git)"
                fi
                if [[ "$show_status" == "true" ]]; then
                    find "$dir" -type f | head -5 | sed 's/^/    /'
                    [[ "$count" -gt 5 ]] && echo "    ... and $((count - 5)) more"
                fi
            fi
        done
    fi
}

# Main execution
main() {
    local command="${1:-}"
    
    case "$command" in
        init)
            local force="false"
            [[ "${2:-}" == "--force" ]] && force="true"
            init_managed_storage "$force"
            ;;
        add)
            local file_path="${2:-}"
            local category="${3:-}"
            local copy_mode="${4:-move}"
            if [[ -z "$file_path" ]]; then
                echo "Usage: $(basename "$0") add <file_path> [category] [move|copy|link]"
                exit 1
            fi
            add_to_managed "$file_path" "$category" "$copy_mode"
            ;;
        promote)
            local file_path="${2:-}"
            local tool="${3:-auto}"
            local category="${4:-auto}"
            if [[ -z "$file_path" ]]; then
                echo "Usage: $(basename "$0") promote <file_path> [git|git-annex|auto] [category]"
                exit 1
            fi
            promote_file "$file_path" "$tool" "$category"
            ;;
        sync)
            local direction="${2:-both}"
            sync_managed "$direction"
            ;;
        list)
            local category="${2:-}"
            local show_status="${3:-false}"
            list_managed "$category" "$show_status"
            ;;
        status)
            if [[ ! -d "$MANAGED_DIR" ]]; then
                echo "❌ Managed storage not initialized"
                exit 1
            fi
            cd "$MANAGED_DIR"
            echo "📊 Managed Storage Status:"
            echo "  Location: $MANAGED_DIR"
            git status --short
            echo ""
            echo "📦 Git-Annex Status:"
            git annex info --fast
            ;;
        *)
            cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  init [--force]                    - Initialize managed storage
  add <file> [category] [mode]      - Add file to managed storage
  promote <file> [tool] [category]  - Promote file to managed storage
  sync [push|pull|both]             - Synchronize with remote
  list [category] [show-files]      - List managed files
  status                            - Show status

Examples:
  $(basename "$0") init
  $(basename "$0") add /path/to/file.txt documents
  $(basename "$0") promote /path/to/large.zip git-annex archives
  $(basename "$0") sync push
  $(basename "$0") list projects true
EOF
            exit 1
            ;;
    esac
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi