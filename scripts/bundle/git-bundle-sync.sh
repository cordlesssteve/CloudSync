#!/bin/bash

# CloudSync Git Bundle Sync
# Creates git bundles and syncs critical .gitignored files for efficient cloud sync
# Phase 1: Small repositories only (< 100MB)

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/config/critical-ignored-patterns.conf"
LOG_FILE="${HOME}/.cloudsync/logs/bundle-sync.log"
BUNDLE_BASE_DIR="${HOME}/.cloudsync/bundles"
REMOTE_BASE="onedrive:DevEnvironment/bundles"

# Size threshold for small repos (100MB)
SIZE_THRESHOLD_MB=100

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

# Load critical ignored patterns
load_critical_patterns() {
    local patterns=()

    # Load from global config
    if [[ -f "$CONFIG_FILE" ]]; then
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            # Skip exclusions (start with !)
            [[ "$line" =~ ^! ]] && continue

            patterns+=("$line")
        done < "$CONFIG_FILE"
    fi

    printf '%s\n' "${patterns[@]}"
}

# Load per-project critical patterns
load_project_patterns() {
    local repo_dir="$1"
    local project_file="${repo_dir}/.cloudsync-critical"
    local patterns=()

    if [[ -f "$project_file" ]]; then
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            patterns+=("$line")
        done < "$project_file"
    fi

    printf '%s\n' "${patterns[@]}"
}

# Get repository size in MB
get_repo_size_mb() {
    local repo_dir="$1"
    local size_kb
    size_kb=$(du -sk "$repo_dir" 2>/dev/null | cut -f1)
    echo $((size_kb / 1024))
}

# Check if repository is small enough for this phase
is_small_repo() {
    local repo_dir="$1"
    local size_mb
    size_mb=$(get_repo_size_mb "$repo_dir")

    [[ $size_mb -lt $SIZE_THRESHOLD_MB ]]
}

# Get repository name (relative to ~/projects)
get_repo_name() {
    local repo_dir="$1"
    local projects_dir="${HOME}/projects"

    # Remove projects prefix and normalize
    echo "${repo_dir#$projects_dir/}"
}

# Create git bundle for repository
create_bundle() {
    local repo_dir="$1"
    local repo_name="$2"
    local bundle_dir="${BUNDLE_BASE_DIR}/${repo_name}"

    mkdir -p "$bundle_dir"

    cd "$repo_dir"

    log "INFO" "Creating bundle for: $repo_name"

    # Create full bundle
    local bundle_file="${bundle_dir}/full.bundle"
    local timestamp_file="${bundle_dir}/full.bundle.timestamp"

    if git bundle create "$bundle_file" --all 2>&1 | tee -a "$LOG_FILE"; then
        date -u +"%Y-%m-%dT%H:%M:%SZ" > "$timestamp_file"
        log "INFO" "✓ Bundle created: $bundle_file"

        # Get bundle size
        local bundle_size
        bundle_size=$(du -h "$bundle_file" | cut -f1)
        log "INFO" "  Bundle size: $bundle_size"

        return 0
    else
        log "ERROR" "✗ Failed to create bundle for $repo_name"
        return 1
    fi
}

# Find critical ignored files in repository
find_critical_files() {
    local repo_dir="$1"
    local patterns=("$@")
    shift

    cd "$repo_dir"

    local critical_files=()

    # For each pattern, find matching gitignored files
    for pattern in "${patterns[@]}"; do
        # Find files matching pattern that are ignored by git
        while IFS= read -r file; do
            # Check if file is actually ignored by git
            if git check-ignore -q "$file" 2>/dev/null; then
                critical_files+=("$file")
            fi
        done < <(find . -path "./.git" -prune -o -name "$pattern" -type f -print 2>/dev/null)
    done

    # Remove duplicates and sort
    printf '%s\n' "${critical_files[@]}" | sort -u
}

# Create tarball of critical ignored files
create_critical_tarball() {
    local repo_dir="$1"
    local repo_name="$2"
    local bundle_dir="${BUNDLE_BASE_DIR}/${repo_name}"

    cd "$repo_dir"

    log "INFO" "Scanning for critical ignored files in: $repo_name"

    # Load patterns
    local patterns=()
    mapfile -t patterns < <(load_critical_patterns)
    mapfile -t -O "${#patterns[@]}" patterns < <(load_project_patterns "$repo_dir")

    if [[ ${#patterns[@]} -eq 0 ]]; then
        log "INFO" "  No patterns configured, skipping critical files"
        return 0
    fi

    # Find critical files
    local critical_files=()
    mapfile -t critical_files < <(find_critical_files "$repo_dir" "${patterns[@]}")

    if [[ ${#critical_files[@]} -eq 0 ]]; then
        log "INFO" "  No critical ignored files found"
        return 0
    fi

    log "INFO" "  Found ${#critical_files[@]} critical file(s):"
    for file in "${critical_files[@]}"; do
        log "INFO" "    - $file"
    done

    # Create tarball
    local tarball="${bundle_dir}/critical-ignored.tar.gz"
    local filelist="${bundle_dir}/critical-ignored.list"

    # Save file list for reference
    printf '%s\n' "${critical_files[@]}" > "$filelist"

    # Create tarball with relative paths
    if tar -czf "$tarball" -C "$repo_dir" --files-from="$filelist" 2>&1 | tee -a "$LOG_FILE"; then
        local tarball_size
        tarball_size=$(du -h "$tarball" | cut -f1)
        log "INFO" "✓ Critical files tarball created: $tarball_size"
        return 0
    else
        log "ERROR" "✗ Failed to create critical files tarball"
        return 1
    fi
}

# Sync bundle and critical files to cloud
sync_to_cloud() {
    local repo_name="$1"
    local bundle_dir="${BUNDLE_BASE_DIR}/${repo_name}"
    local remote_dir="${REMOTE_BASE}/${repo_name}"

    log "INFO" "Syncing to cloud: $repo_name"

    if ! command -v rclone >/dev/null 2>&1; then
        log "ERROR" "rclone not found, cannot sync to cloud"
        return 1
    fi

    # Sync entire bundle directory
    if rclone sync "$bundle_dir/" "$remote_dir/" \
        --progress \
        --stats-one-line \
        2>&1 | tee -a "$LOG_FILE"; then
        log "INFO" "✓ Synced to: $remote_dir"
        return 0
    else
        log "ERROR" "✗ Failed to sync to cloud"
        return 1
    fi
}

# Process a single repository
process_repository() {
    local repo_dir="$1"

    # Check if it's a git repository
    if [[ ! -d "${repo_dir}/.git" ]]; then
        log "WARN" "Not a git repository, skipping: $repo_dir"
        return 1
    fi

    # Check if repository is small enough
    if ! is_small_repo "$repo_dir"; then
        local size_mb
        size_mb=$(get_repo_size_mb "$repo_dir")
        log "INFO" "Repository too large (${size_mb}MB), skipping: $repo_dir"
        return 0
    fi

    local repo_name
    repo_name=$(get_repo_name "$repo_dir")

    log "INFO" "========================================="
    log "INFO" "Processing: $repo_name"
    local size_mb
    size_mb=$(get_repo_size_mb "$repo_dir")
    log "INFO" "Size: ${size_mb}MB"

    # Create bundle
    if ! create_bundle "$repo_dir" "$repo_name"; then
        log "ERROR" "Failed to create bundle for: $repo_name"
        return 1
    fi

    # Create critical files tarball
    if ! create_critical_tarball "$repo_dir" "$repo_name"; then
        log "WARN" "Failed to create critical files tarball for: $repo_name"
        # Continue anyway
    fi

    # Sync to cloud
    if ! sync_to_cloud "$repo_name"; then
        log "ERROR" "Failed to sync to cloud: $repo_name"
        return 1
    fi

    log "INFO" "✓ Completed: $repo_name"
    return 0
}

# Main execution
main() {
    local command="${1:-sync}"

    case "$command" in
        sync)
            log "INFO" "Starting Git Bundle Sync (Small Repos)"
            log "INFO" "Size threshold: ${SIZE_THRESHOLD_MB}MB"

            # Find all git repositories
            local repo_count=0
            local success_count=0
            local skip_count=0
            local error_count=0

            while IFS= read -r -d '' repo_dir; do
                ((repo_count++))

                if process_repository "${repo_dir%/.git}"; then
                    ((success_count++))
                else
                    if is_small_repo "${repo_dir%/.git}"; then
                        ((error_count++))
                    else
                        ((skip_count++))
                    fi
                fi
            done < <(find ~/projects -name ".git" -type d -print0 2>/dev/null)

            log "INFO" "========================================="
            log "INFO" "Sync Complete"
            log "INFO" "Total repositories: $repo_count"
            log "INFO" "✓ Successfully synced: $success_count"
            log "INFO" "⊘ Skipped (too large): $skip_count"
            log "INFO" "✗ Errors: $error_count"
            ;;

        test)
            # Test on a single repository
            local test_repo="${2:-}"
            if [[ -z "$test_repo" ]]; then
                echo "Usage: $0 test <repo_path>"
                exit 1
            fi

            if [[ ! -d "$test_repo" ]]; then
                log "ERROR" "Repository not found: $test_repo"
                exit 1
            fi

            log "INFO" "Testing on: $test_repo"
            process_repository "$test_repo"
            ;;

        restore)
            # Restore from bundle (to be implemented)
            echo "Restore functionality coming in next iteration"
            exit 1
            ;;

        *)
            cat <<EOF
Usage: $0 <command> [options]

Commands:
  sync              - Sync all small repositories to cloud
  test <repo_path>  - Test sync on a single repository
  restore           - Restore repository from bundle (not yet implemented)

Configuration:
  Critical patterns: ${CONFIG_FILE}
  Bundle storage:    ${BUNDLE_BASE_DIR}
  Remote location:   ${REMOTE_BASE}
  Size threshold:    ${SIZE_THRESHOLD_MB}MB

Example:
  $0 test ~/projects/Extra/GAMES/Gneiss
  $0 sync
EOF
            exit 1
            ;;
    esac
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
