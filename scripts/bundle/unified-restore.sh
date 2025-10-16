#!/bin/bash

# CloudSync Unified Restore
# Restores both git bundles and non-git archives from OneDrive backups
# Handles automatic detection and extraction of both bundle types

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="${HOME}/.cloudsync/logs/unified-restore.log"
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

# Detect bundle type from manifest
detect_bundle_type() {
    local manifest_file="$1"

    if [[ ! -f "$manifest_file" ]]; then
        echo "unknown"
        return 1
    fi

    local bundle_type=$(jq -r '.archive_type // empty' "$manifest_file" 2>/dev/null)

    if [[ -z "$bundle_type" ]]; then
        # Fallback: check for git-specific fields
        if jq -e '.bundles' "$manifest_file" >/dev/null 2>&1; then
            echo "git-repository"
        else
            echo "unknown"
        fi
    else
        echo "$bundle_type"
    fi
}

# List available bundles
list_bundles() {
    log "INFO" "Available bundles:"
    echo ""
    echo "GIT REPOSITORIES:"
    echo "================"

    find "$BUNDLE_BASE_DIR" -name "bundle-manifest.json" -type f 2>/dev/null | while read manifest; do
        local bundle_type=$(detect_bundle_type "$manifest")
        local bundle_dir=$(dirname "$manifest")
        local bundle_name=$(basename "$bundle_dir")

        if [[ "$bundle_type" == "git-repository" ]] || [[ "$bundle_type" == "unknown" && -f "${bundle_dir}/full.bundle" ]]; then
            local source_path=$(jq -r '.source_path // "unknown"' "$manifest" 2>/dev/null || echo "unknown")
            local last_commit=$(jq -r '.last_bundle_commit // "unknown"' "$manifest" 2>/dev/null || echo "unknown")
            local archive_count=$(jq '.bundles | length' "$manifest" 2>/dev/null || echo "0")

            echo "  📦 $bundle_name"
            echo "     Source: $source_path"
            echo "     Commit: ${last_commit:0:8}"
            echo "     Bundles: $archive_count"
            echo ""
        fi
    done

    echo ""
    echo "NON-GIT DIRECTORIES:"
    echo "===================="

    find "$BUNDLE_BASE_DIR" -name "bundle-manifest.json" -type f 2>/dev/null | while read manifest; do
        local bundle_type=$(detect_bundle_type "$manifest")
        local bundle_dir=$(dirname "$manifest")
        local bundle_name=$(basename "$bundle_dir")

        if [[ "$bundle_type" == "non-git-directory" ]]; then
            local source_path=$(jq -r '.source_path // "unknown"' "$manifest" 2>/dev/null || echo "unknown")
            local last_updated=$(jq -r '.last_updated // "unknown"' "$manifest" 2>/dev/null || echo "unknown")
            local archive_count=$(jq '.archives | length' "$manifest" 2>/dev/null || echo "0")
            local total_size=$(jq -r '.metadata.total_size_compressed // 0' "$manifest" 2>/dev/null || echo "0")
            local size_human=$(numfmt --to=iec "$total_size" 2>/dev/null || echo "unknown")

            echo "  📁 $bundle_name"
            echo "     Source: $source_path"
            echo "     Updated: $last_updated"
            echo "     Archives: $archive_count"
            echo "     Size: $size_human"
            echo ""
        fi
    done
}

# Restore git bundle
restore_git_bundle() {
    local bundle_dir="$1"
    local manifest="${bundle_dir}/bundle-manifest.json"
    local target_path="${2:-}"

    log "INFO" "Restoring GIT bundle from: $bundle_dir"

    # Read source path from manifest
    local source_path=$(jq -r '.source_path // empty' "$manifest")

    if [[ -z "$source_path" ]]; then
        # Fallback: try to determine from bundle directory name
        local bundle_name=$(basename "$bundle_dir")
        source_path="${HOME}/projects/${bundle_name}"
        log "WARN" "Source path not in manifest, using: $source_path"
    fi

    # Use provided target path or source path
    local restore_path="${target_path:-$source_path}"

    log "INFO" "  Source: $source_path"
    log "INFO" "  Target: $restore_path"

    # Create target directory
    mkdir -p "$restore_path"
    cd "$restore_path"

    # Initialize git if needed
    if [[ ! -d ".git" ]]; then
        log "INFO" "Initializing git repository"
        git init
    fi

    # Get list of bundles in order
    local bundles=$(jq -r '.bundles[] | .filename' "$manifest" 2>/dev/null)

    if [[ -z "$bundles" ]]; then
        log "ERROR" "No bundles found in manifest"
        return 1
    fi

    # Restore bundles
    for bundle_file in $bundles; do
        local bundle_path="${bundle_dir}/${bundle_file}"

        if [[ ! -f "$bundle_path" ]]; then
            log "WARN" "Bundle file not found: $bundle_file"
            continue
        fi

        log "INFO" "Fetching from bundle: $bundle_file"

        if git fetch "$bundle_path" --all 2>&1 | tee -a "$LOG_FILE"; then
            log "INFO" "✓ Fetched $bundle_file"
        else
            log "ERROR" "✗ Failed to fetch $bundle_file"
            return 1
        fi
    done

    # Checkout main/master branch
    local main_branch=$(git branch -r | grep -E 'origin/(main|master)' | head -1 | sed 's/.*\///' || echo "main")

    log "INFO" "Checking out branch: $main_branch"

    if git checkout "$main_branch" 2>&1 | tee -a "$LOG_FILE"; then
        log "INFO" "✓ Git repository restored to: $restore_path"
        return 0
    else
        log "ERROR" "✗ Failed to checkout $main_branch"
        return 1
    fi
}

# Restore non-git archive
restore_non_git_archive() {
    local bundle_dir="$1"
    local manifest="${bundle_dir}/bundle-manifest.json"
    local target_path="${2:-}"

    log "INFO" "Restoring NON-GIT archive from: $bundle_dir"

    # Read source path from manifest
    local source_path=$(jq -r '.source_path' "$manifest")
    local hostname=$(jq -r '.hostname' "$manifest")

    # Use provided target path or source path
    local restore_path="${target_path:-$source_path}"

    log "INFO" "  Source: $source_path"
    log "INFO" "  Original hostname: $hostname"
    log "INFO" "  Target: $restore_path"

    # Get restore order from manifest
    local archives=$(jq -r '.restore_instructions.order[]' "$manifest" 2>/dev/null)

    if [[ -z "$archives" ]]; then
        # Fallback: extract in chronological order
        archives=$(jq -r '.archives[] | .filename' "$manifest")
    fi

    if [[ -z "$archives" ]]; then
        log "ERROR" "No archives found in manifest"
        return 1
    fi

    # Create target directory parent
    mkdir -p "$(dirname "$restore_path")"

    # Extract archives in order
    local extracted_count=0
    for archive_file in $archives; do
        local archive_path="${bundle_dir}/${archive_file}"

        if [[ ! -f "$archive_path" ]]; then
            log "WARN" "Archive file not found: $archive_file"
            continue
        fi

        log "INFO" "Extracting: $archive_file"

        # Determine compression type
        local compression=""
        if [[ "$archive_file" == *.tar.zst ]]; then
            compression="--zstd"
        elif [[ "$archive_file" == *.tar.gz ]]; then
            compression="--gzip"
        elif [[ "$archive_file" == *.tar.bz2 ]]; then
            compression="--bzip2"
        fi

        # Extract to root (preserves absolute paths)
        if tar --extract \
            $compression \
            --file "$archive_path" \
            --directory / \
            2>&1 | tee -a "$LOG_FILE"; then
            log "INFO" "✓ Extracted $archive_file"
            ((extracted_count++))
        else
            log "ERROR" "✗ Failed to extract $archive_file"
            return 1
        fi
    done

    log "INFO" "✓ Non-git archive restored to: $restore_path"
    log "INFO" "  Extracted $extracted_count archives"

    return 0
}

# Restore specific bundle
restore_bundle() {
    local bundle_name="$1"
    local target_path="${2:-}"
    local bundle_dir="${BUNDLE_BASE_DIR}/${bundle_name}"
    local manifest="${bundle_dir}/bundle-manifest.json"

    if [[ ! -d "$bundle_dir" ]]; then
        log "ERROR" "Bundle not found: $bundle_name"
        log "INFO" "Run '$0 list' to see available bundles"
        return 1
    fi

    if [[ ! -f "$manifest" ]]; then
        log "ERROR" "Manifest not found: $manifest"
        return 1
    fi

    # Detect bundle type
    local bundle_type=$(detect_bundle_type "$manifest")

    log "INFO" "========================================="
    log "INFO" "Restoring bundle: $bundle_name"
    log "INFO" "Type: $bundle_type"
    log "INFO" "========================================="

    case "$bundle_type" in
        git-repository)
            restore_git_bundle "$bundle_dir" "$target_path"
            ;;
        non-git-directory)
            restore_non_git_archive "$bundle_dir" "$target_path"
            ;;
        *)
            log "ERROR" "Unknown bundle type: $bundle_type"
            return 1
            ;;
    esac
}

# Download bundles from OneDrive
download_bundles() {
    local bundle_name="${1:-}"

    log "INFO" "Downloading bundles from OneDrive"

    if [[ -n "$bundle_name" ]]; then
        log "INFO" "Downloading specific bundle: $bundle_name"
        rclone sync "${REMOTE_BASE}/${bundle_name}/" "${BUNDLE_BASE_DIR}/${bundle_name}/" \
            --progress \
            --log-level INFO 2>&1 | tee -a "$LOG_FILE"
    else
        log "INFO" "Downloading all bundles"
        rclone sync "${REMOTE_BASE}/" "${BUNDLE_BASE_DIR}/" \
            --progress \
            --log-level INFO 2>&1 | tee -a "$LOG_FILE"
    fi

    log "INFO" "✓ Download complete"
}

# Verify bundle integrity
verify_bundle() {
    local bundle_name="$1"
    local bundle_dir="${BUNDLE_BASE_DIR}/${bundle_name}"
    local manifest="${bundle_dir}/bundle-manifest.json"

    log "INFO" "Verifying bundle: $bundle_name"

    if [[ ! -f "$manifest" ]]; then
        log "ERROR" "Manifest not found"
        return 1
    fi

    local bundle_type=$(detect_bundle_type "$manifest")
    local verified=0
    local failed=0

    case "$bundle_type" in
        git-repository)
            # Verify git bundles
            jq -r '.bundles[] | "\(.filename) \(.commit)"' "$manifest" | while read filename commit; do
                local bundle_path="${bundle_dir}/${filename}"

                if [[ ! -f "$bundle_path" ]]; then
                    log "ERROR" "Missing bundle file: $filename"
                    ((failed++))
                    continue
                fi

                if git bundle verify "$bundle_path" >/dev/null 2>&1; then
                    log "INFO" "✓ $filename (commit: ${commit:0:8})"
                    ((verified++))
                else
                    log "ERROR" "✗ $filename - verification failed"
                    ((failed++))
                fi
            done
            ;;
        non-git-directory)
            # Verify non-git archives
            jq -r '.archives[] | "\(.filename) \(.checksum)"' "$manifest" | while read filename checksum; do
                local archive_path="${bundle_dir}/${filename}"

                if [[ ! -f "$archive_path" ]]; then
                    log "ERROR" "Missing archive file: $filename"
                    ((failed++))
                    continue
                fi

                local actual_checksum=$(sha256sum "$archive_path" | awk '{print $1}')

                if [[ "$actual_checksum" == "$checksum" ]]; then
                    log "INFO" "✓ $filename"
                    ((verified++))
                else
                    log "ERROR" "✗ $filename - checksum mismatch"
                    ((failed++))
                fi
            done
            ;;
    esac

    log "INFO" "Verification complete: $verified passed, $failed failed"

    [[ "$failed" -eq 0 ]]
}

# Main execution
main() {
    local command="${1:-}"

    case "$command" in
        list)
            list_bundles
            ;;
        restore)
            local bundle_name="${2:-}"
            local target_path="${3:-}"

            if [[ -z "$bundle_name" ]]; then
                echo "Usage: $0 restore <bundle-name> [target-path]"
                echo ""
                echo "Available bundles:"
                list_bundles
                exit 1
            fi

            restore_bundle "$bundle_name" "$target_path"
            ;;
        download)
            local bundle_name="${2:-}"
            download_bundles "$bundle_name"
            ;;
        verify)
            local bundle_name="${2:-}"

            if [[ -z "$bundle_name" ]]; then
                echo "Usage: $0 verify <bundle-name>"
                exit 1
            fi

            verify_bundle "$bundle_name"
            ;;
        *)
            cat <<EOF
CloudSync Unified Restore - Restore git and non-git bundles

Usage: $(basename "$0") <command> [options]

Commands:
  list                           - List all available bundles
  restore <name> [target]        - Restore a specific bundle
  download [name]                - Download bundles from OneDrive
  verify <name>                  - Verify bundle integrity

Examples:
  $(basename "$0") list
  $(basename "$0") download
  $(basename "$0") restore backups
  $(basename "$0") restore Work/spaceful ~/projects/restored/spaceful
  $(basename "$0") verify backups

Bundle Types:
  - git-repository: Full git history with all branches
  - non-git-directory: Compressed archives of regular directories

Target Path:
  If not specified, restores to original source path from manifest
EOF
            [[ -n "$command" ]] && exit 1 || exit 0
            ;;
    esac
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
