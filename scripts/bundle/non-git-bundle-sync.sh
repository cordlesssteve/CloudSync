#!/bin/bash

# CloudSync Non-Git Bundle Sync
# Creates compressed archives of non-git-tracked directories with incremental updates
# Similar to git-bundle-sync.sh but for regular directories like backups, media, etc.

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="${HOME}/.cloudsync/logs/non-git-bundle-sync.log"
BUNDLE_BASE_DIR="${HOME}/.cloudsync/bundles"
REMOTE_BASE="onedrive:DevEnvironment/bundles"

# Compression settings
COMPRESSION="zstd"
COMPRESSION_LEVEL="3"  # Balance between speed and compression

# Size thresholds for deciding full vs incremental
SIZE_THRESHOLD_SMALL_MB=100   # Always do full archives
SIZE_THRESHOLD_LARGE_GB=5     # Consider incremental for these

# Consolidation settings
MAX_INCREMENTALS=10           # Consolidate after this many incrementals
CONSOLIDATION_DAYS=30         # Or consolidate after this many days

# Directories to bundle (add more as needed)
NON_GIT_DIRS=(
    "$HOME/backups"
    "$HOME/media"
    "$HOME/.local/bin"
)

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$BUNDLE_BASE_DIR"

# Logging
log() {
    local level="$1"
    shift
    local message="$*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

# Get directory size in MB
get_dir_size_mb() {
    local dir="$1"
    local size_kb
    size_kb=$(du -sk "$dir" 2>/dev/null | cut -f1)
    echo $((size_kb / 1024))
}

# Get directory name (safe for use in filenames)
get_safe_dirname() {
    local dir="$1"
    basename "$dir" | tr '.' '_'
}

# Get bundle directory for a source directory
get_bundle_dir() {
    local source_dir="$1"
    local safe_name=$(get_safe_dirname "$source_dir")
    echo "${BUNDLE_BASE_DIR}/${safe_name}"
}

# Get manifest path
get_manifest_path() {
    local source_dir="$1"
    local bundle_dir=$(get_bundle_dir "$source_dir")
    echo "${bundle_dir}/bundle-manifest.json"
}

# Initialize manifest
init_manifest() {
    local manifest_file="$1"
    local source_path="$2"

    cat > "$manifest_file" <<EOF
{
  "source_path": "$source_path",
  "hostname": "$(hostname)",
  "archive_type": "non-git-directory",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "archives": [],
  "metadata": {
    "total_size_uncompressed": 0,
    "total_size_compressed": 0,
    "compression_ratio": 0,
    "last_checksum": null,
    "file_types": {},
    "categories": []
  },
  "restore_instructions": {
    "target_path": "$source_path",
    "order": [],
    "commands": []
  }
}
EOF
}

# Load manifest
load_manifest() {
    local manifest_file="$1"

    if [[ -f "$manifest_file" ]]; then
        cat "$manifest_file"
    else
        echo "{}"
    fi
}

# Calculate directory checksum
calculate_dir_checksum() {
    local dir="$1"

    # Use find + stat to create a fingerprint of the directory
    # Include file paths, sizes, and mtimes
    find "$dir" -type f -printf '%p %s %T@\n' 2>/dev/null | \
        sort | \
        sha256sum | \
        awk '{print $1}'
}

# Analyze file types in directory
analyze_file_types() {
    local dir="$1"

    # Count files by extension
    find "$dir" -type f 2>/dev/null | \
        sed 's/.*\.//' | \
        sort | uniq -c | \
        awk '{printf "{\"extension\":\".%s\",\"count\":%d},", $2, $1}' | \
        sed 's/,$//' | \
        awk '{print "["$0"]"}' || echo "[]"
}

# Determine category based on content
determine_category() {
    local source_dir="$1"

    case "$(basename "$source_dir")" in
        backups)
            echo "backup-archives"
            ;;
        media)
            echo "media-files"
            ;;
        *.local/bin|bin)
            echo "executables"
            ;;
        docs|documents)
            echo "documentation"
            ;;
        *)
            echo "miscellaneous"
            ;;
    esac
}

# Check if directory has changed since last archive
has_changed() {
    local source_dir="$1"
    local manifest_file=$(get_manifest_path "$source_dir")

    if [[ ! -f "$manifest_file" ]]; then
        return 0  # No manifest = changed
    fi

    local current_checksum=$(calculate_dir_checksum "$source_dir")
    local last_checksum=$(jq -r '.metadata.last_checksum // empty' "$manifest_file")

    if [[ -z "$last_checksum" ]] || [[ "$current_checksum" != "$last_checksum" ]]; then
        return 0  # Changed
    fi

    return 1  # Not changed
}

# Check if consolidation is needed
should_consolidate() {
    local manifest_file="$1"

    if [[ ! -f "$manifest_file" ]]; then
        return 1  # No consolidation needed if no manifest
    fi

    local incremental_count=$(jq -r '.archives | map(select(.type == "incremental")) | length' "$manifest_file")

    if [[ "$incremental_count" -ge "$MAX_INCREMENTALS" ]]; then
        log "INFO" "Consolidation needed: $incremental_count incrementals"
        return 0
    fi

    # Check age of last full bundle
    local last_full_date=$(jq -r '.archives | map(select(.type == "full")) | .[-1].created // empty' "$manifest_file")

    if [[ -n "$last_full_date" ]]; then
        local last_full_epoch=$(date -d "$last_full_date" +%s 2>/dev/null || echo 0)
        local current_epoch=$(date +%s)
        local days_since=$((( current_epoch - last_full_epoch ) / 86400))

        if [[ "$days_since" -ge "$CONSOLIDATION_DAYS" ]]; then
            log "INFO" "Consolidation needed: $days_since days since last full"
            return 0
        fi
    fi

    return 1
}

# Create full archive
create_full_archive() {
    local source_dir="$1"
    local bundle_dir=$(get_bundle_dir "$source_dir")
    local manifest_file=$(get_manifest_path "$source_dir")

    mkdir -p "$bundle_dir"

    local safe_name=$(get_safe_dirname "$source_dir")
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local archive_name="${safe_name}-full-${timestamp}.tar.${COMPRESSION}"
    local archive_path="${bundle_dir}/${archive_name}"

    log "INFO" "Creating FULL archive: $archive_name"
    log "INFO" "  Source: $source_dir"

    # Create archive with absolute paths preserved
    local rel_path="${source_dir#$HOME/}"

    if tar --create \
        --${COMPRESSION} \
        --file "$archive_path" \
        --directory "$HOME" \
        "$rel_path" 2>&1 | tee -a "$LOG_FILE"; then

        # Calculate sizes and checksums
        local archive_size=$(stat -c%s "$archive_path" 2>/dev/null || stat -f%z "$archive_path" 2>/dev/null)
        local archive_checksum=$(sha256sum "$archive_path" | awk '{print $1}')
        local dir_checksum=$(calculate_dir_checksum "$source_dir")
        local files_count=$(find "$source_dir" -type f 2>/dev/null | wc -l)
        local uncompressed_size=$(du -sb "$source_dir" 2>/dev/null | cut -f1)

        # Analyze file types
        local file_types=$(analyze_file_types "$source_dir")
        local category=$(determine_category "$source_dir")

        log "INFO" "✓ Full archive created"
        log "INFO" "  Size: $(numfmt --to=iec "$archive_size")"
        log "INFO" "  Files: $files_count"
        log "INFO" "  Compression: $((100 - (archive_size * 100 / uncompressed_size)))%"

        # Initialize or update manifest
        if [[ ! -f "$manifest_file" ]]; then
            init_manifest "$manifest_file" "$source_dir"
        fi

        # Update manifest with archive info
        local archive_entry=$(cat <<EOF
{
  "type": "full",
  "filename": "$archive_name",
  "source_path": "$source_dir",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "size": $archive_size,
  "files_count": $files_count,
  "checksum": "$archive_checksum",
  "compression": "$COMPRESSION",
  "directories_included": $(find "$source_dir" -mindepth 1 -maxdepth 1 -type d -printf '"%f",' 2>/dev/null | sed 's/,$//' | awk '{print "["$0"]"}' || echo "[]"),
  "file_types": $file_types,
  "category": "$category"
}
EOF
)

        # Add to manifest
        jq --argjson entry "$archive_entry" \
           --arg checksum "$dir_checksum" \
           --arg uncompressed "$uncompressed_size" \
           --arg compressed "$archive_size" \
           --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           '.archives += [$entry] |
            .last_updated = $timestamp |
            .metadata.last_checksum = $checksum |
            .metadata.total_size_uncompressed = ($uncompressed | tonumber) |
            .metadata.total_size_compressed = ($compressed | tonumber) |
            .metadata.compression_ratio = (($compressed | tonumber) / ($uncompressed | tonumber)) |
            .metadata.categories |= (. + [$entry.category] | unique) |
            .restore_instructions.order = [.archives[].filename]' \
           "$manifest_file" > "${manifest_file}.tmp"

        mv "${manifest_file}.tmp" "$manifest_file"

        return 0
    else
        log "ERROR" "✗ Failed to create full archive"
        return 1
    fi
}

# Create incremental archive
create_incremental_archive() {
    local source_dir="$1"
    local bundle_dir=$(get_bundle_dir "$source_dir")
    local manifest_file=$(get_manifest_path "$source_dir")

    local safe_name=$(get_safe_dirname "$source_dir")
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local archive_name="${safe_name}-incremental-${timestamp}.tar.${COMPRESSION}"
    local archive_path="${bundle_dir}/${archive_name}"
    local snapshot_file="${bundle_dir}/.tar-snapshot"

    log "INFO" "Creating INCREMENTAL archive: $archive_name"

    # Create incremental archive using tar snapshot
    local rel_path="${source_dir#$HOME/}"

    if tar --create \
        --${COMPRESSION} \
        --file "$archive_path" \
        --directory "$HOME" \
        --listed-incremental="$snapshot_file" \
        "$rel_path" 2>&1 | tee -a "$LOG_FILE"; then

        # Calculate metadata
        local archive_size=$(stat -c%s "$archive_path" 2>/dev/null || stat -f%z "$archive_path" 2>/dev/null)
        local archive_checksum=$(sha256sum "$archive_path" | awk '{print $1}')
        local dir_checksum=$(calculate_dir_checksum "$source_dir")
        local files_count=$(tar -tzf "$archive_path" 2>/dev/null | wc -l)

        # Get parent archive
        local parent_archive=$(jq -r '.archives[-1].filename' "$manifest_file")

        log "INFO" "✓ Incremental archive created"
        log "INFO" "  Size: $(numfmt --to=iec "$archive_size")"
        log "INFO" "  Files: $files_count"
        log "INFO" "  Parent: $parent_archive"

        # Create archive entry
        local archive_entry=$(cat <<EOF
{
  "type": "incremental",
  "filename": "$archive_name",
  "source_path": "$source_dir",
  "parent": "$parent_archive",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "size": $archive_size,
  "files_count": $files_count,
  "checksum": "$archive_checksum",
  "compression": "$COMPRESSION"
}
EOF
)

        # Update manifest
        jq --argjson entry "$archive_entry" \
           --arg checksum "$dir_checksum" \
           --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           '.archives += [$entry] |
            .last_updated = $timestamp |
            .metadata.last_checksum = $checksum |
            .restore_instructions.order = [.archives[].filename]' \
           "$manifest_file" > "${manifest_file}.tmp"

        mv "${manifest_file}.tmp" "$manifest_file"

        return 0
    else
        log "ERROR" "✗ Failed to create incremental archive"
        return 1
    fi
}

# Sync directory archives
sync_directory() {
    local source_dir="$1"

    if [[ ! -d "$source_dir" ]]; then
        log "WARN" "Directory not found: $source_dir"
        return 1
    fi

    local bundle_dir=$(get_bundle_dir "$source_dir")
    local manifest_file=$(get_manifest_path "$source_dir")
    local safe_name=$(get_safe_dirname "$source_dir")

    log "INFO" "========================================="
    log "INFO" "Processing: $source_dir"

    # Check if directory has changed
    if ! has_changed "$source_dir"; then
        log "INFO" "No changes detected, skipping"
        return 0
    fi

    log "INFO" "Changes detected"

    # Decide: full or incremental?
    local create_full=false

    if [[ ! -f "$manifest_file" ]]; then
        log "INFO" "No previous archive, creating full"
        create_full=true
    elif should_consolidate "$manifest_file"; then
        log "INFO" "Consolidation needed, creating full"
        create_full=true
    else
        local dir_size_mb=$(get_dir_size_mb "$source_dir")
        if [[ "$dir_size_mb" -lt "$SIZE_THRESHOLD_SMALL_MB" ]]; then
            log "INFO" "Small directory ($dir_size_mb MB), creating full"
            create_full=true
        fi
    fi

    # Create archive
    if [[ "$create_full" == "true" ]]; then
        create_full_archive "$source_dir" || return 1
    else
        create_incremental_archive "$source_dir" || return 1
    fi

    # Sync to OneDrive
    log "INFO" "Syncing to OneDrive: ${safe_name}/"
    if rclone sync "$bundle_dir/" "${REMOTE_BASE}/${safe_name}/" \
        --progress \
        --log-level INFO 2>&1 | tee -a "$LOG_FILE"; then
        log "INFO" "✓ Synced to OneDrive"
    else
        log "ERROR" "✗ Failed to sync to OneDrive"
        return 1
    fi

    return 0
}

# Main sync all directories
sync_all() {
    log "INFO" "========================================="
    log "INFO" "Non-Git Bundle Sync Started"
    log "INFO" "========================================="

    local success_count=0
    local error_count=0
    local skipped_count=0

    for source_dir in "${NON_GIT_DIRS[@]}"; do
        if sync_directory "$source_dir"; then
            ((success_count++))
        else
            ((error_count++))
        fi
    done

    log "INFO" "========================================="
    log "INFO" "Sync Complete"
    log "INFO" "Total directories: ${#NON_GIT_DIRS[@]}"
    log "INFO" "✓ Successfully synced: $success_count"
    log "INFO" "✗ Errors: $error_count"
    log "INFO" "========================================="
}

# Main execution
main() {
    local command="${1:-sync}"

    case "$command" in
        sync)
            sync_all
            ;;
        sync-dir)
            local dir="${2:-}"
            if [[ -z "$dir" ]]; then
                echo "Usage: $0 sync-dir <directory>"
                exit 1
            fi
            sync_directory "$dir"
            ;;
        list)
            echo "Configured non-git directories:"
            for dir in "${NON_GIT_DIRS[@]}"; do
                echo "  - $dir"
            done
            ;;
        status)
            echo "Bundle status:"
            for source_dir in "${NON_GIT_DIRS[@]}"; do
                local manifest=$(get_manifest_path "$source_dir")
                if [[ -f "$manifest" ]]; then
                    echo ""
                    echo "$(basename "$source_dir"):"
                    echo "  Archives: $(jq '.archives | length' "$manifest")"
                    echo "  Last updated: $(jq -r '.last_updated' "$manifest")"
                    echo "  Total size: $(jq -r '.metadata.total_size_compressed' "$manifest" | numfmt --to=iec)"
                else
                    echo ""
                    echo "$(basename "$source_dir"): No archives yet"
                fi
            done
            ;;
        *)
            cat <<EOF
Non-Git Bundle Sync - Archive non-git directories efficiently

Usage: $(basename "$0") <command> [options]

Commands:
  sync                  - Sync all configured directories
  sync-dir <dir>        - Sync specific directory
  list                  - List configured directories
  status                - Show bundle status

Examples:
  $(basename "$0") sync
  $(basename "$0") sync-dir ~/backups
  $(basename "$0") status
EOF
            [[ -n "$command" ]] && exit 1 || exit 0
            ;;
    esac
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
