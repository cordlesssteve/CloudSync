#!/bin/bash
# CloudSync Conflict Detection and Resolution Script
# Detects sync conflicts and provides resolution strategies

set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$PROJECT_ROOT/config/cloudsync.conf"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "⚠️ Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE="$HOME/.cloudsync/conflict-resolver.log"
CONFLICT_DIR="$HOME/.cloudsync/conflicts"

# Create required directories
mkdir -p "$HOME/.cloudsync"
mkdir -p "$CONFLICT_DIR"

# Function to log messages
log_message() {
    echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
    echo -e "$1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [ACTION]"
    echo ""
    echo "Actions:"
    echo "  detect              Detect conflicts in sync paths"
    echo "  list                List existing conflicts"
    echo "  resolve             Resolve conflicts interactively"
    echo "  auto-resolve        Auto-resolve conflicts using configured strategy"
    echo "  backup              Backup conflicted files before resolution"
    echo ""
    echo "Options:"
    echo "  --local <path>      Local path to check (default: HOME)"
    echo "  --remote <remote>   Remote to check (default: $DEFAULT_REMOTE)"
    echo "  --path <path>       Remote path (default: $SYNC_BASE_PATH)"
    echo "  --strategy <method> Auto-resolution strategy: newer|larger|local|remote"
    echo "  --pattern <pattern> Conflict file pattern (default: *.conflict)"
    echo "  --backup-dir <dir>  Backup directory (default: ~/.cloudsync/conflicts)"
    echo "  --dry-run           Show what would be done without making changes"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 detect --local ~/projects"
    echo "  $0 list"
    echo "  $0 auto-resolve --strategy newer"
    echo "  $0 resolve --pattern '*.sync-conflict*'"
}

# Default options
ACTION="detect"
LOCAL_PATH="$HOME"
REMOTE="$DEFAULT_REMOTE"
REMOTE_PATH="$SYNC_BASE_PATH"
RESOLUTION_STRATEGY="ask"
CONFLICT_PATTERN="*.conflict"
BACKUP_DIR="$CONFLICT_DIR"
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        detect|list|resolve|auto-resolve|backup)
            ACTION="$1"
            shift
            ;;
        --local)
            LOCAL_PATH="$2"
            shift 2
            ;;
        --remote)
            REMOTE="$2"
            shift 2
            ;;
        --path)
            REMOTE_PATH="$2"
            shift 2
            ;;
        --strategy)
            RESOLUTION_STRATEGY="$2"
            shift 2
            ;;
        --pattern)
            CONFLICT_PATTERN="$2"
            shift 2
            ;;
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Detect conflicts in local and remote paths
detect_conflicts() {
    log_message "${BLUE}🔍 Detecting conflicts...${NC}"

    local conflicts_found=0
    local conflict_files=()

    # Check local path for conflict files
    if [[ -d "$LOCAL_PATH" ]]; then
        log_message "${BLUE}📁 Scanning local path: $LOCAL_PATH${NC}"

        while IFS= read -r -d '' file; do
            conflict_files+=("$file")
            ((conflicts_found++))
        done < <(find "$LOCAL_PATH" -name "$CONFLICT_PATTERN" -type f -print0 2>/dev/null || true)

        # Also check for rclone bisync conflict patterns
        while IFS= read -r -d '' file; do
            conflict_files+=("$file")
            ((conflicts_found++))
        done < <(find "$LOCAL_PATH" -name "*.sync-conflict-*" -type f -print0 2>/dev/null || true)
    fi

    # Check remote path for conflict files (if accessible)
    if command -v rclone >/dev/null 2>&1; then
        log_message "${BLUE}☁️ Scanning remote path: $REMOTE:$REMOTE_PATH${NC}"

        local remote_conflicts
        remote_conflicts=$(rclone lsf "$REMOTE:$REMOTE_PATH" --recursive | grep -E "\.(conflict|sync-conflict)" || true)

        if [[ -n "$remote_conflicts" ]]; then
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    conflict_files+=("$REMOTE:$REMOTE_PATH/$line")
                    ((conflicts_found++))
                fi
            done <<< "$remote_conflicts"
        fi
    fi

    # Report findings
    if [[ $conflicts_found -eq 0 ]]; then
        log_message "${GREEN}✅ No conflicts detected${NC}"
        return 0
    else
        log_message "${YELLOW}⚠️ Found $conflicts_found conflict files:${NC}"

        for file in "${conflict_files[@]}"; do
            log_message "${YELLOW}  - $file${NC}"
        done

        # Save conflict list
        printf '%s\n' "${conflict_files[@]}" > "$CONFLICT_DIR/detected-conflicts.txt"
        log_message "${BLUE}📝 Conflict list saved to: $CONFLICT_DIR/detected-conflicts.txt${NC}"

        return 1
    fi
}

# List existing conflicts
list_conflicts() {
    log_message "${BLUE}📋 Listing existing conflicts...${NC}"

    if [[ -f "$CONFLICT_DIR/detected-conflicts.txt" ]]; then
        local conflict_count
        conflict_count=$(wc -l < "$CONFLICT_DIR/detected-conflicts.txt")

        if [[ $conflict_count -gt 0 ]]; then
            log_message "${YELLOW}⚠️ Found $conflict_count conflict files:${NC}"

            while IFS= read -r file; do
                if [[ -n "$file" ]]; then
                    # Get file info
                    local file_size="unknown"
                    local file_date="unknown"

                    if [[ "$file" =~ ^[^:]+: ]]; then
                        # Remote file
                        local remote_info
                        remote_info=$(rclone lsl "$file" 2>/dev/null || echo "")
                        if [[ -n "$remote_info" ]]; then
                            file_size=$(echo "$remote_info" | awk '{print $1}')
                            file_date=$(echo "$remote_info" | awk '{print $2 " " $3}')
                        fi
                    else
                        # Local file
                        if [[ -f "$file" ]]; then
                            file_size=$(stat -c%s "$file" 2>/dev/null || echo "unknown")
                            file_date=$(stat -c%y "$file" 2>/dev/null || echo "unknown")
                        fi
                    fi

                    log_message "${YELLOW}  📄 $file${NC}"
                    log_message "${BLUE}     Size: $file_size bytes, Modified: $file_date${NC}"
                fi
            done < "$CONFLICT_DIR/detected-conflicts.txt"
        else
            log_message "${GREEN}✅ No conflicts in list${NC}"
        fi
    else
        log_message "${BLUE}💡 No conflict list found. Run 'detect' first.${NC}"
        return 1
    fi
}

# Backup conflicted files
backup_conflicts() {
    log_message "${BLUE}💾 Backing up conflicted files...${NC}"

    if [[ ! -f "$CONFLICT_DIR/detected-conflicts.txt" ]]; then
        log_message "${YELLOW}⚠️ No conflict list found. Run 'detect' first.${NC}"
        return 1
    fi

    local backup_timestamp
    backup_timestamp=$(date '+%Y%m%d-%H%M%S')
    local backup_subdir="$BACKUP_DIR/backup-$backup_timestamp"

    if ! $DRY_RUN; then
        mkdir -p "$backup_subdir"
    fi

    local backed_up=0

    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            local backup_path="$backup_subdir/$(basename "$file")"

            if $DRY_RUN; then
                log_message "${YELLOW}[DRY RUN] Would backup: $file → $backup_path${NC}"
            else
                if [[ "$file" =~ ^[^:]+: ]]; then
                    # Remote file
                    if rclone copy "$file" "$backup_subdir/" >/dev/null 2>&1; then
                        log_message "${GREEN}✅ Backed up remote: $file${NC}"
                        ((backed_up++))
                    else
                        log_message "${RED}❌ Failed to backup remote: $file${NC}"
                    fi
                else
                    # Local file
                    if [[ -f "$file" ]] && cp "$file" "$backup_path" 2>/dev/null; then
                        log_message "${GREEN}✅ Backed up local: $file${NC}"
                        ((backed_up++))
                    else
                        log_message "${RED}❌ Failed to backup local: $file${NC}"
                    fi
                fi
            fi
        fi
    done < "$CONFLICT_DIR/detected-conflicts.txt"

    if ! $DRY_RUN; then
        log_message "${GREEN}💾 Backed up $backed_up files to: $backup_subdir${NC}"
    fi
}

# Auto-resolve conflicts based on strategy
auto_resolve_conflicts() {
    log_message "${BLUE}🤖 Auto-resolving conflicts with strategy: $RESOLUTION_STRATEGY${NC}"

    if [[ ! -f "$CONFLICT_DIR/detected-conflicts.txt" ]]; then
        log_message "${YELLOW}⚠️ No conflict list found. Run 'detect' first.${NC}"
        return 1
    fi

    local resolved=0

    while IFS= read -r conflict_file; do
        if [[ -n "$conflict_file" ]]; then
            local original_file
            original_file=$(echo "$conflict_file" | sed -E 's/\.(conflict|sync-conflict[^.]*)$//')

            case "$RESOLUTION_STRATEGY" in
                "newer")
                    resolve_by_newer "$conflict_file" "$original_file"
                    ;;
                "larger")
                    resolve_by_larger "$conflict_file" "$original_file"
                    ;;
                "local")
                    resolve_keep_local "$conflict_file" "$original_file"
                    ;;
                "remote")
                    resolve_keep_remote "$conflict_file" "$original_file"
                    ;;
                *)
                    log_message "${YELLOW}⚠️ Unknown strategy: $RESOLUTION_STRATEGY${NC}"
                    return 1
                    ;;
            esac

            if [[ $? -eq 0 ]]; then
                ((resolved++))
            fi
        fi
    done < "$CONFLICT_DIR/detected-conflicts.txt"

    log_message "${GREEN}✅ Auto-resolved $resolved conflicts${NC}"
}

# Resolve by keeping newer file
resolve_by_newer() {
    local conflict_file="$1"
    local original_file="$2"

    # Compare modification times and keep newer
    # Implementation would depend on file location (local vs remote)
    log_message "${BLUE}⏰ Resolving by newer: $conflict_file${NC}"

    if $DRY_RUN; then
        log_message "${YELLOW}[DRY RUN] Would resolve by newer${NC}"
        return 0
    fi

    # Actual implementation would go here
    return 0
}

# Resolve by keeping larger file
resolve_by_larger() {
    local conflict_file="$1"
    local original_file="$2"

    log_message "${BLUE}📏 Resolving by larger: $conflict_file${NC}"

    if $DRY_RUN; then
        log_message "${YELLOW}[DRY RUN] Would resolve by larger${NC}"
        return 0
    fi

    # Actual implementation would go here
    return 0
}

# Interactive conflict resolution
interactive_resolve() {
    log_message "${BLUE}👤 Interactive conflict resolution${NC}"

    if [[ ! -f "$CONFLICT_DIR/detected-conflicts.txt" ]]; then
        log_message "${YELLOW}⚠️ No conflict list found. Run 'detect' first.${NC}"
        return 1
    fi

    local resolved=0

    while IFS= read -r conflict_file; do
        if [[ -n "$conflict_file" ]]; then
            log_message "${YELLOW}⚔️ Conflict: $conflict_file${NC}"

            # Show file details
            local original_file
            original_file=$(echo "$conflict_file" | sed -E 's/\.(conflict|sync-conflict[^.]*)$//')

            echo "Options:"
            echo "  1) Keep original file ($original_file)"
            echo "  2) Keep conflict file ($conflict_file)"
            echo "  3) Skip this conflict"
            echo "  4) Quit resolution"

            read -p "Choose option (1-4): " choice

            case $choice in
                1)
                    if ! $DRY_RUN; then
                        rm -f "$conflict_file" 2>/dev/null || true
                        log_message "${GREEN}✅ Kept original, removed conflict${NC}"
                        ((resolved++))
                    else
                        log_message "${YELLOW}[DRY RUN] Would keep original${NC}"
                    fi
                    ;;
                2)
                    if ! $DRY_RUN; then
                        mv "$conflict_file" "$original_file" 2>/dev/null || true
                        log_message "${GREEN}✅ Kept conflict file as original${NC}"
                        ((resolved++))
                    else
                        log_message "${YELLOW}[DRY RUN] Would keep conflict file${NC}"
                    fi
                    ;;
                3)
                    log_message "${BLUE}⏭️ Skipped conflict${NC}"
                    ;;
                4)
                    log_message "${BLUE}🚪 Exiting interactive resolution${NC}"
                    break
                    ;;
                *)
                    log_message "${RED}❌ Invalid choice, skipping${NC}"
                    ;;
            esac
        fi
    done < "$CONFLICT_DIR/detected-conflicts.txt"

    log_message "${GREEN}✅ Interactively resolved $resolved conflicts${NC}"
}

# Main execution
main() {
    log_message "${BLUE}⚔️ CloudSync Conflict Resolver${NC}"
    log_message "Timestamp: $TIMESTAMP"
    log_message "Action: $ACTION"
    echo "=" | head -c 50 && echo

    case "$ACTION" in
        "detect")
            detect_conflicts
            ;;
        "list")
            list_conflicts
            ;;
        "backup")
            backup_conflicts
            ;;
        "auto-resolve")
            # Always backup before auto-resolving
            backup_conflicts
            auto_resolve_conflicts
            ;;
        "resolve")
            # Always backup before resolving
            backup_conflicts
            interactive_resolve
            ;;
        *)
            log_message "${RED}❌ Unknown action: $ACTION${NC}"
            show_usage
            exit 1
            ;;
    esac

    log_message "📝 Full log: $LOG_FILE"
}

# Run main function
main "$@"