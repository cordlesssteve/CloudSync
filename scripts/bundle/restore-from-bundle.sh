#!/bin/bash

# CloudSync Bundle Restore
# Restore repositories and directories from git bundles + non-git archives
# This script now delegates to unified-restore.sh for all bundle types

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
UNIFIED_RESTORE="${SCRIPT_DIR}/unified-restore.sh"

# Check if unified restore exists
if [[ ! -f "$UNIFIED_RESTORE" ]]; then
    echo "ERROR: Unified restore script not found: $UNIFIED_RESTORE"
    exit 1
fi

# Delegate to unified restore
echo "🔄 Using unified restore system..."
echo ""

# Pass all arguments to unified restore
exec bash "$UNIFIED_RESTORE" "$@"

# Load manifest file
load_manifest() {
    local manifest_file="$1"

    if [[ -f "$manifest_file" ]]; then
        cat "$manifest_file"
    else
        echo '{}'
    fi
}

# Restore repository from bundle
restore_repository() {
    local repo_name="$1"
    local target_dir="${2:-}"

    # Default target directory
    if [[ -z "$target_dir" ]]; then
        target_dir="${HOME}/projects/${repo_name}"
    fi

    local bundle_dir="${BUNDLE_BASE_DIR}/${repo_name}"
    local manifest_file="${bundle_dir}/bundle-manifest.json"
    local critical_tarball="${bundle_dir}/critical-ignored.tar.gz"

    log "INFO" "========================================="
    log "INFO" "Restoring: $repo_name"
    log "INFO" "Target: $target_dir"

    # Check if bundles exist locally, if not download from cloud
    if [[ ! -d "$bundle_dir" ]] || [[ ! -f "$manifest_file" ]]; then
        log "INFO" "Bundle not found locally, downloading from cloud..."
        local remote_dir="${REMOTE_BASE}/${repo_name}"

        mkdir -p "$bundle_dir"

        if ! rclone copy "$remote_dir/" "$bundle_dir/" \
            --progress \
            --stats-one-line \
            2>&1 | tee -a "$LOG_FILE"; then
            log "ERROR" "Failed to download bundle from cloud"
            return 1
        fi

        log "INFO" "✓ Bundles downloaded"
    fi

    # Load manifest
    local manifest
    manifest=$(load_manifest "$manifest_file")

    # Get bundle count
    local bundle_count
    bundle_count=$(echo "$manifest" | jq '.bundles | length')

    if [[ $bundle_count -eq 0 ]]; then
        log "ERROR" "No bundles found in manifest"
        return 1
    fi

    log "INFO" "Found $bundle_count bundle(s) to apply"

    # Find the full bundle
    local full_bundle
    full_bundle=$(echo "$manifest" | jq -r '.bundles[] | select(.type == "full") | .filename' | tail -1)

    if [[ -z "$full_bundle" ]] || [[ "$full_bundle" == "null" ]]; then
        log "ERROR" "No full bundle found in manifest"
        return 1
    fi

    local full_bundle_path="${bundle_dir}/${full_bundle}"

    # Verify full bundle exists
    if [[ ! -f "$full_bundle_path" ]]; then
        log "ERROR" "Full bundle file not found: $full_bundle_path"
        return 1
    fi

    # Verify full bundle is valid
    log "INFO" "Verifying full bundle: $full_bundle..."
    if ! git bundle verify "$full_bundle_path" >/dev/null 2>&1; then
        log "ERROR" "Full bundle verification failed"
        return 1
    fi
    log "INFO" "✓ Full bundle verified"

    # Check if target directory exists
    if [[ -d "$target_dir" ]]; then
        log "WARN" "Target directory already exists: $target_dir"
        read -p "Delete and restore? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "INFO" "Restore cancelled"
            return 1
        fi
        rm -rf "$target_dir"
    fi

    # Clone from full bundle
    log "INFO" "Cloning from full bundle..."
    if ! git clone "$full_bundle_path" "$target_dir" 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR" "Failed to clone from full bundle"
        return 1
    fi
    log "INFO" "✓ Repository cloned from full bundle"

    # Apply incremental bundles in order
    local incremental_bundles
    incremental_bundles=$(echo "$manifest" | jq -r '.bundles[] | select(.type == "incremental") | .filename')

    if [[ -n "$incremental_bundles" ]]; then
        log "INFO" "Applying incremental bundles..."

        local incremental_count=0
        while IFS= read -r incremental_bundle; do
            if [[ -z "$incremental_bundle" ]]; then
                continue
            fi

            incremental_count=$((incremental_count + 1))
            local incremental_path="${bundle_dir}/${incremental_bundle}"

            if [[ ! -f "$incremental_path" ]]; then
                log "ERROR" "Incremental bundle not found: $incremental_path"
                return 1
            fi

            log "INFO" "  Applying: $incremental_bundle"

            # Verify incremental bundle
            if ! git -C "$target_dir" bundle verify "$incremental_path" >/dev/null 2>&1; then
                log "ERROR" "Incremental bundle verification failed: $incremental_bundle"
                return 1
            fi

            # Pull from incremental bundle
            if ! git -C "$target_dir" pull "$incremental_path" HEAD 2>&1 | tee -a "$LOG_FILE"; then
                log "ERROR" "Failed to apply incremental bundle: $incremental_bundle"
                return 1
            fi

            log "INFO" "  ✓ Applied: $incremental_bundle"
        done <<< "$incremental_bundles"

        log "INFO" "✓ Applied $incremental_count incremental bundle(s)"
    fi

    # Restore critical ignored files
    if [[ -f "$critical_tarball" ]]; then
        log "INFO" "Restoring critical ignored files..."

        # Check if tarball has content
        local tarball_size
        tarball_size=$(stat -f%z "$critical_tarball" 2>/dev/null || stat -c%s "$critical_tarball" 2>/dev/null)

        if [[ $tarball_size -gt 100 ]]; then
            # List files in tarball
            log "INFO" "Files to restore:"
            tar -tzf "$critical_tarball" 2>&1 | while read -r file; do
                log "INFO" "  - $file"
            done

            # Extract tarball
            if tar -xzf "$critical_tarball" -C "$target_dir" 2>&1 | tee -a "$LOG_FILE"; then
                log "INFO" "✓ Critical files restored"
            else
                log "WARN" "Failed to restore critical files (non-fatal)"
            fi
        else
            log "INFO" "No critical files to restore"
        fi
    fi

    log "INFO" "✓ Restore complete: $target_dir"
    return 0
}

# Test restore to temporary location
test_restore() {
    local repo_name="$1"
    local test_dir="/tmp/cloudsync-test-restore-$$"

    log "INFO" "Testing restore to temporary directory"

    if restore_repository "$repo_name" "$test_dir"; then
        log "INFO" "✓ Test restore successful"
        log "INFO" "Repository restored to: $test_dir"
        log "INFO" "Verify manually, then delete when done:"
        log "INFO" "  rm -rf $test_dir"
        return 0
    else
        log "ERROR" "✗ Test restore failed"
        return 1
    fi
}

# Main execution
main() {
    local command="${1:-}"

    case "$command" in
        restore)
            local repo_name="${2:-}"
            local target_dir="${3:-}"

            if [[ -z "$repo_name" ]]; then
                echo "Usage: $0 restore <repo_name> [target_dir]"
                echo "Example: $0 restore Extra/GAMES/Gneiss ~/projects/Extra/GAMES/Gneiss"
                exit 1
            fi

            restore_repository "$repo_name" "$target_dir"
            ;;

        test)
            local repo_name="${2:-}"

            if [[ -z "$repo_name" ]]; then
                echo "Usage: $0 test <repo_name>"
                echo "Example: $0 test Extra/GAMES/Gneiss"
                exit 1
            fi

            test_restore "$repo_name"
            ;;

        *)
            cat <<EOF
Usage: $0 <command> [options]

Commands:
  restore <repo_name> [target_dir]  - Restore repository from bundle
  test <repo_name>                  - Test restore to /tmp directory

Configuration:
  Bundle storage:  ${BUNDLE_BASE_DIR}
  Remote location: ${REMOTE_BASE}

Examples:
  $0 test Extra/GAMES/Gneiss
  $0 restore Extra/GAMES/Gneiss ~/projects/Extra/GAMES/Gneiss
EOF
            exit 1
            ;;
    esac
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
