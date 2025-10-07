#!/bin/bash

# CloudSync Bundle Restore
# Restore a repository from git bundle + critical ignored files

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="${HOME}/.cloudsync/logs/bundle-restore.log"
BUNDLE_BASE_DIR="${HOME}/.cloudsync/bundles"
REMOTE_BASE="onedrive:DevEnvironment/bundles"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging
log() {
    local level="$1"
    shift
    local message="$*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
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
    local bundle_file="${bundle_dir}/full.bundle"
    local critical_tarball="${bundle_dir}/critical-ignored.tar.gz"

    log "INFO" "========================================="
    log "INFO" "Restoring: $repo_name"
    log "INFO" "Target: $target_dir"

    # Check if bundle exists locally, if not download from cloud
    if [[ ! -f "$bundle_file" ]]; then
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

        log "INFO" "✓ Bundle downloaded"
    fi

    # Verify bundle exists
    if [[ ! -f "$bundle_file" ]]; then
        log "ERROR" "Bundle file not found: $bundle_file"
        return 1
    fi

    # Verify bundle is valid
    log "INFO" "Verifying bundle..."
    if ! git bundle verify "$bundle_file" >/dev/null 2>&1; then
        log "ERROR" "Bundle verification failed"
        return 1
    fi
    log "INFO" "✓ Bundle verified"

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

    # Clone from bundle
    log "INFO" "Cloning from bundle..."
    if ! git clone "$bundle_file" "$target_dir" 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR" "Failed to clone from bundle"
        return 1
    fi
    log "INFO" "✓ Repository cloned"

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
