#!/bin/bash

# CloudSync Git Bundle Sync
# Creates git bundles and syncs critical .gitignored files for efficient cloud sync
# Supports incremental bundles for efficient syncing of all repository sizes

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/config/critical-ignored-patterns.conf"
LOG_FILE="${HOME}/.cloudsync/logs/bundle-sync.log"
BUNDLE_BASE_DIR="${HOME}/.cloudsync/bundles"
REMOTE_BASE="onedrive:DevEnvironment/bundles"

# Size thresholds
SIZE_THRESHOLD_SMALL_MB=100   # Small repos: always full bundle
SIZE_THRESHOLD_MEDIUM_MB=500  # Medium repos: incremental bundles

# Consolidation settings
MAX_INCREMENTALS=10           # Consolidate after 10 incremental bundles
CONSOLIDATION_DAYS=30         # Or after 30 days

# Git tag for tracking last bundle
BUNDLE_TAG="cloudsync-last-bundle"

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

# Determine repository size category
get_repo_category() {
    local repo_dir="$1"
    local size_mb
    size_mb=$(get_repo_size_mb "$repo_dir")

    if [[ $size_mb -lt $SIZE_THRESHOLD_SMALL_MB ]]; then
        echo "small"
    elif [[ $size_mb -lt $SIZE_THRESHOLD_MEDIUM_MB ]]; then
        echo "medium"
    else
        echo "large"
    fi
}

# Check if repository is small enough for this phase (legacy compatibility)
is_small_repo() {
    local repo_dir="$1"
    local category
    category=$(get_repo_category "$repo_dir")
    [[ "$category" == "small" ]]
}

# Get repository name (relative to ~/projects)
get_repo_name() {
    local repo_dir="$1"
    local projects_dir="${HOME}/projects"

    # Remove projects prefix and normalize
    echo "${repo_dir#$projects_dir/}"
}

# Get manifest file path for repository
get_manifest_path() {
    local repo_name="$1"
    local bundle_dir="${BUNDLE_BASE_DIR}/${repo_name}"
    echo "${bundle_dir}/bundle-manifest.json"
}

# Initialize or load manifest
load_manifest() {
    local manifest_file="$1"

    if [[ -f "$manifest_file" ]]; then
        cat "$manifest_file"
    else
        # Return empty manifest structure
        echo '{
  "bundles": [],
  "last_bundle_commit": null,
  "incremental_count": 0,
  "last_full_bundle_date": null
}'
    fi
}

# Update manifest with new bundle
update_manifest() {
    local manifest_file="$1"
    local bundle_type="$2"
    local bundle_filename="$3"
    local commit="$4"
    local size="$5"
    local commit_range="${6:-}"
    local parent="${7:-}"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local manifest
    manifest=$(load_manifest "$manifest_file")

    # Build bundle entry
    local bundle_entry
    if [[ "$bundle_type" == "full" ]]; then
        bundle_entry=$(cat <<EOF
{
  "type": "full",
  "filename": "$bundle_filename",
  "timestamp": "$timestamp",
  "commit": "$commit",
  "size": $size
}
EOF
)
        # Reset incremental count for full bundle
        manifest=$(echo "$manifest" | jq \
            --argjson bundle "$bundle_entry" \
            '.bundles += [$bundle] | .last_bundle_commit = $bundle.commit | .incremental_count = 0 | .last_full_bundle_date = $bundle.timestamp')
    else
        bundle_entry=$(cat <<EOF
{
  "type": "incremental",
  "filename": "$bundle_filename",
  "timestamp": "$timestamp",
  "parent": "$parent",
  "commit_range": "$commit_range",
  "commit": "$commit",
  "size": $size
}
EOF
)
        # Increment incremental count
        manifest=$(echo "$manifest" | jq \
            --argjson bundle "$bundle_entry" \
            '.bundles += [$bundle] | .last_bundle_commit = $bundle.commit | .incremental_count += 1')
    fi

    echo "$manifest" > "$manifest_file"
}

# Check if consolidation is needed
should_consolidate() {
    local manifest_file="$1"

    if [[ ! -f "$manifest_file" ]]; then
        return 1
    fi

    local manifest
    manifest=$(cat "$manifest_file")

    local incremental_count
    incremental_count=$(echo "$manifest" | jq -r '.incremental_count // 0')

    # Check if max incrementals reached
    if [[ $incremental_count -ge $MAX_INCREMENTALS ]]; then
        return 0
    fi

    # Check if consolidation due by date
    local last_full_date
    last_full_date=$(echo "$manifest" | jq -r '.last_full_bundle_date // ""')

    if [[ -n "$last_full_date" ]]; then
        local days_old
        days_old=$(( ( $(date +%s) - $(date -d "$last_full_date" +%s) ) / 86400 ))

        if [[ $days_old -ge $CONSOLIDATION_DAYS ]]; then
            return 0
        fi
    fi

    return 1
}

# Get last bundled commit from repo
get_last_bundle_commit() {
    local repo_dir="$1"

    cd "$repo_dir"

    # Check for git tag first
    if git rev-parse "$BUNDLE_TAG" >/dev/null 2>&1; then
        git rev-parse "$BUNDLE_TAG"
        return 0
    fi

    # No tag found
    return 1
}

# Check if repository has new commits since last bundle
has_new_commits() {
    local repo_dir="$1"

    cd "$repo_dir"

    local last_commit
    if ! last_commit=$(get_last_bundle_commit "$repo_dir" 2>/dev/null); then
        # No previous bundle, has new commits
        return 0
    fi

    # Check if HEAD is ahead of last bundle commit
    if ! git merge-base --is-ancestor HEAD "$last_commit" 2>/dev/null; then
        # Current HEAD is not an ancestor of last bundle (new commits exist)
        return 0
    fi

    # Check if there are commits since last bundle
    local new_commits
    new_commits=$(git rev-list "$last_commit..HEAD" 2>/dev/null | wc -l)

    [[ $new_commits -gt 0 ]]
}

# Create full git bundle
create_full_bundle() {
    local repo_dir="$1"
    local repo_name="$2"
    local bundle_dir="${BUNDLE_BASE_DIR}/${repo_name}"

    cd "$repo_dir"

    log "INFO" "Creating FULL bundle for: $repo_name"

    local bundle_file="${bundle_dir}/full.bundle"
    local timestamp_file="${bundle_dir}/full.bundle.timestamp"

    if git bundle create "$bundle_file" --all 2>&1 | tee -a "$LOG_FILE"; then
        date -u +"%Y-%m-%dT%H:%M:%SZ" > "$timestamp_file"

        # Tag current HEAD
        git tag -f "$BUNDLE_TAG" HEAD

        # Get bundle info
        local bundle_size_bytes
        bundle_size_bytes=$(stat -c%s "$bundle_file" 2>/dev/null || stat -f%z "$bundle_file" 2>/dev/null)
        local bundle_size_human
        bundle_size_human=$(du -h "$bundle_file" | cut -f1)
        local current_commit
        current_commit=$(git rev-parse HEAD)

        log "INFO" "✓ Full bundle created: $bundle_size_human"

        # Update manifest
        local manifest_file
        manifest_file=$(get_manifest_path "$repo_name")
        update_manifest "$manifest_file" "full" "full.bundle" "$current_commit" "$bundle_size_bytes"

        return 0
    else
        log "ERROR" "✗ Failed to create full bundle for $repo_name"
        return 1
    fi
}

# Create incremental git bundle
create_incremental_bundle() {
    local repo_dir="$1"
    local repo_name="$2"
    local bundle_dir="${BUNDLE_BASE_DIR}/${repo_name}"

    cd "$repo_dir"

    local last_commit
    if ! last_commit=$(get_last_bundle_commit "$repo_dir"); then
        log "ERROR" "Cannot create incremental bundle without previous bundle"
        return 1
    fi

    local current_commit
    current_commit=$(git rev-parse HEAD)

    if [[ "$last_commit" == "$current_commit" ]]; then
        log "INFO" "No new commits since last bundle"
        return 0
    fi

    local datestamp
    datestamp=$(date -u +"%Y%m%d-%H%M%S")
    local bundle_filename="incremental-${datestamp}.bundle"
    local bundle_file="${bundle_dir}/${bundle_filename}"
    local commit_range="${last_commit}..HEAD"

    log "INFO" "Creating INCREMENTAL bundle for: $repo_name"
    log "INFO" "  Commit range: ${last_commit:0:8}..${current_commit:0:8}"

    if git bundle create "$bundle_file" "$commit_range" 2>&1 | tee -a "$LOG_FILE"; then
        # Tag current HEAD
        git tag -f "$BUNDLE_TAG" HEAD

        # Get bundle info
        local bundle_size_bytes
        bundle_size_bytes=$(stat -c%s "$bundle_file" 2>/dev/null || stat -f%z "$bundle_file" 2>/dev/null)
        local bundle_size_human
        bundle_size_human=$(du -h "$bundle_file" | cut -f1)

        # Get parent bundle from manifest
        local manifest_file
        manifest_file=$(get_manifest_path "$repo_name")
        local parent_bundle
        parent_bundle=$(load_manifest "$manifest_file" | jq -r '.bundles[-1].filename // "full.bundle"')

        log "INFO" "✓ Incremental bundle created: $bundle_size_human"
        log "INFO" "  Parent: $parent_bundle"

        # Update manifest
        update_manifest "$manifest_file" "incremental" "$bundle_filename" "$current_commit" "$bundle_size_bytes" "$commit_range" "$parent_bundle"

        return 0
    else
        log "ERROR" "✗ Failed to create incremental bundle for $repo_name"
        return 1
    fi
}

# Create git bundle (decides between full and incremental)
create_bundle() {
    local repo_dir="$1"
    local repo_name="$2"
    local bundle_dir="${BUNDLE_BASE_DIR}/${repo_name}"
    local category="${3:-}"

    mkdir -p "$bundle_dir"

    cd "$repo_dir"

    # Determine if we need full or incremental bundle
    local manifest_file
    manifest_file=$(get_manifest_path "$repo_name")

    # Check if consolidation is needed
    if should_consolidate "$manifest_file"; then
        log "INFO" "Consolidation needed for $repo_name"
        create_full_bundle "$repo_dir" "$repo_name"
        return $?
    fi

    # Check if this is first bundle
    if [[ ! -f "$manifest_file" ]] || [[ $(load_manifest "$manifest_file" | jq '.bundles | length') -eq 0 ]]; then
        create_full_bundle "$repo_dir" "$repo_name"
        return $?
    fi

    # Check for small repos (always full bundle)
    if [[ "$category" == "small" ]]; then
        create_full_bundle "$repo_dir" "$repo_name"
        return $?
    fi

    # For medium/large repos, create incremental if there are new commits
    if has_new_commits "$repo_dir"; then
        create_incremental_bundle "$repo_dir" "$repo_name"
        return $?
    else
        log "INFO" "No new commits for $repo_name, skipping bundle creation"
        return 0
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

    local repo_name
    repo_name=$(get_repo_name "$repo_dir")

    local size_mb
    size_mb=$(get_repo_size_mb "$repo_dir")

    local category
    category=$(get_repo_category "$repo_dir")

    log "INFO" "========================================="
    log "INFO" "Processing: $repo_name"
    log "INFO" "Size: ${size_mb}MB (category: $category)"

    # Determine bundle strategy
    case "$category" in
        small)
            log "INFO" "Strategy: Full bundle (small repo)"
            ;;
        medium)
            log "INFO" "Strategy: Incremental bundles"
            ;;
        large)
            log "INFO" "Strategy: Incremental bundles"
            ;;
    esac

    # Create bundle (will decide full vs incremental internally)
    if ! create_bundle "$repo_dir" "$repo_name" "$category"; then
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
            log "INFO" "Starting Git Bundle Sync (All Repositories)"
            log "INFO" "Size categories:"
            log "INFO" "  - Small (< ${SIZE_THRESHOLD_SMALL_MB}MB): Full bundles"
            log "INFO" "  - Medium (${SIZE_THRESHOLD_SMALL_MB}-${SIZE_THRESHOLD_MEDIUM_MB}MB): Incremental bundles"
            log "INFO" "  - Large (> ${SIZE_THRESHOLD_MEDIUM_MB}MB): Incremental bundles"
            log "INFO" "  - Consolidation: After ${MAX_INCREMENTALS} incrementals or ${CONSOLIDATION_DAYS} days"

            # Find all git repositories
            local repo_count=0
            local success_count=0
            local skip_count=0
            local error_count=0
            local small_count=0
            local medium_count=0
            local large_count=0

            while IFS= read -r -d '' repo_dir; do
                repo_count=$((repo_count + 1))
                local repo_path="${repo_dir%/.git}"
                log "DEBUG" "Found repo: $repo_path (count: $repo_count)"

                # Count by category
                local category
                category=$(get_repo_category "$repo_path")
                case "$category" in
                    small) small_count=$((small_count + 1)) ;;
                    medium) medium_count=$((medium_count + 1)) ;;
                    large) large_count=$((large_count + 1)) ;;
                esac

                if process_repository "$repo_path"; then
                    success_count=$((success_count + 1))
                else
                    error_count=$((error_count + 1))
                fi
            done < <(find ~/projects -name ".git" -type d -print0 2>/dev/null)

            log "INFO" "========================================="
            log "INFO" "Sync Complete"
            log "INFO" "Total repositories: $repo_count"
            log "INFO" "  - Small (< ${SIZE_THRESHOLD_SMALL_MB}MB): $small_count"
            log "INFO" "  - Medium (${SIZE_THRESHOLD_SMALL_MB}-${SIZE_THRESHOLD_MEDIUM_MB}MB): $medium_count"
            log "INFO" "  - Large (> ${SIZE_THRESHOLD_MEDIUM_MB}MB): $large_count"
            log "INFO" "✓ Successfully synced: $success_count"
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
