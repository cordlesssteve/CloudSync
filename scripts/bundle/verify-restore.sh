#!/bin/bash
# CloudSync Bundle Restore Verification
# Automated testing to verify disaster recovery readiness

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESTORE_SCRIPT="${SCRIPT_DIR}/restore-from-bundle.sh"
NOTIFY_SCRIPT="${PROJECT_ROOT}/scripts/notify.sh"

# Configuration
BUNDLE_DIR="${HOME}/.cloudsync/bundles"
TEST_DIR="/tmp/cloudsync-restore-test-$$"
LOG_DIR="${HOME}/.cloudsync/logs"
VERIFY_LOG="${LOG_DIR}/restore-verification.log"

# Test configuration
: "${TEST_SMALL_REPO:=true}"     # Test small repo restore
: "${TEST_LARGE_REPO:=true}"     # Test large repo with incremental bundles
: "${TEST_IGNORED_FILES:=true}"  # Test critical .gitignored file recovery
: "${MAX_REPOS_TO_TEST:=5}"      # Limit number of repos to test
: "${CLEANUP_AFTER:=true}"       # Clean up test directory after

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

#######################
# Utility Functions
#######################

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$VERIFY_LOG"
}

log_success() {
    echo -e "${GREEN}✓ $*${NC}" | tee -a "$VERIFY_LOG"
    ((PASSED_TESTS++)) || true
}

log_failure() {
    echo -e "${RED}✗ $*${NC}" | tee -a "$VERIFY_LOG"
    ((FAILED_TESTS++)) || true
}

log_warning() {
    echo -e "${YELLOW}⚠ $*${NC}" | tee -a "$VERIFY_LOG"
    ((WARNINGS++)) || true
}

log_info() {
    echo -e "${BLUE}ℹ $*${NC}" | tee -a "$VERIFY_LOG"
}

run_test() {
    ((TOTAL_TESTS++)) || true
}

#######################
# Test Functions
#######################

find_test_repos() {
    local size_category="$1"  # small, medium, or large
    local limit="$2"

    if [[ ! -d "$BUNDLE_DIR" ]]; then
        log_warning "Bundle directory not found: ${BUNDLE_DIR}"
        return 1
    fi

    # Find repos with bundles and categorize by incremental count
    local repos=()
    while IFS= read -r manifest; do
        # Get repo path relative to bundle dir
        local repo_dir
        repo_dir=$(dirname "$manifest")
        local repo_path="${repo_dir#${BUNDLE_DIR}/}"

        # Check incremental count to determine category
        local incremental_count
        incremental_count=$(jq -r '.incremental_count // 0' "$manifest" 2>/dev/null || echo "0")

        # Categorize: small = no incrementals, medium = 1-2, large = 3+
        local category="small"
        if [[ $incremental_count -ge 3 ]]; then
            category="large"
        elif [[ $incremental_count -ge 1 ]]; then
            category="medium"
        fi

        if [[ "$category" == "$size_category" ]]; then
            repos+=("$repo_path")
            [[ ${#repos[@]} -ge $limit ]] && break
        fi
    done < <(find "$BUNDLE_DIR" -name "bundle-manifest.json" -type f | head -30)

    printf '%s\n' "${repos[@]}"
}

test_repo_restore() {
    local repo_path="$1"
    local test_name="$2"

    run_test
    log_info "Testing restore: ${repo_path} (${test_name})"

    local restore_dir="${TEST_DIR}/$(basename "$repo_path")"
    local start_time
    start_time=$(date +%s)

    # Run restore
    if "${RESTORE_SCRIPT}" restore "$repo_path" "$restore_dir" >> "$VERIFY_LOG" 2>&1; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))

        # Verify restoration
        if [[ ! -d "${restore_dir}/.git" ]]; then
            log_failure "${repo_name}: No .git directory found after restore"
            return 1
        fi

        # Check if repo is valid
        if ! git -C "$restore_dir" status &>/dev/null; then
            log_failure "${repo_name}: Git repository is invalid"
            return 1
        fi

        # Count commits
        local commit_count
        commit_count=$(git -C "$restore_dir" rev-list --count HEAD 2>/dev/null || echo "0")

        log_success "${repo_path}: Restored successfully in ${duration}s (${commit_count} commits)"
        return 0
    else
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_failure "${repo_path}: Restore failed after ${duration}s"
        return 1
    fi
}

test_ignored_files_restore() {
    local repo_path="$1"

    run_test
    log_info "Testing critical ignored files: ${repo_path}"

    local restore_dir="${TEST_DIR}/$(basename "$repo_path")"
    local repo_base=$(basename "$repo_path")
    local ignored_archive="${BUNDLE_DIR}/${repo_path}/${repo_base}-critical-ignored.tar.gz"

    if [[ ! -f "$ignored_archive" ]]; then
        log_info "${repo_path}: No critical ignored files to test (archive not found)"
        return 0
    fi

    # List files in archive
    local file_count
    file_count=$(tar -tzf "$ignored_archive" 2>/dev/null | wc -l || echo "0")

    if [[ $file_count -eq 0 ]]; then
        log_warning "${repo_path}: Critical ignored archive is empty"
        return 0
    fi

    # Verify files were restored
    local restored_count=0
    while IFS= read -r file; do
        if [[ -f "${restore_dir}/${file}" ]] || [[ -d "${restore_dir}/${file}" ]]; then
            ((restored_count++)) || true
        fi
    done < <(tar -tzf "$ignored_archive" 2>/dev/null || true)

    if [[ $restored_count -eq $file_count ]]; then
        log_success "${repo_path}: All ${file_count} critical ignored files restored"
        return 0
    elif [[ $restored_count -gt 0 ]]; then
        log_warning "${repo_path}: Partial restore (${restored_count}/${file_count} files)"
        return 0
    else
        log_failure "${repo_path}: Critical ignored files not restored (0/${file_count})"
        return 1
    fi
}

test_incremental_bundle_chain() {
    local repo_path="$1"

    run_test
    log_info "Testing incremental bundle chain: ${repo_path}"

    local manifest="${BUNDLE_DIR}/${repo_path}/bundle-manifest.json"
    if [[ ! -f "$manifest" ]]; then
        log_warning "${repo_path}: No manifest found, skipping incremental test"
        return 0
    fi

    # Check if repo uses incremental bundles
    local incremental_count
    incremental_count=$(jq -r '.incremental_count // 0' "$manifest" 2>/dev/null || echo "0")

    if [[ $incremental_count -eq 0 ]]; then
        log_info "${repo_path}: Using full bundle (not incremental)"
        return 0
    fi

    # Verify all bundles exist
    local bundle_dir="${BUNDLE_DIR}/${repo_path}"
    local full_bundle="${bundle_dir}/full.bundle"
    local missing_bundles=0

    # Check full bundle
    if [[ ! -f "$full_bundle" ]]; then
        log_failure "${repo_path}: Missing full bundle"
        ((missing_bundles++)) || true
    fi

    # Check incremental bundles
    local incremental_bundles
    incremental_bundles=$(find "$bundle_dir" -name "incremental-*.bundle" 2>/dev/null | wc -l || echo "0")

    if [[ $incremental_bundles -eq $incremental_count ]]; then
        log_success "${repo_path}: All ${incremental_count} incremental bundles present (+ full bundle)"
        return 0
    else
        log_failure "${repo_path}: Expected ${incremental_count} incremental bundles, found ${incremental_bundles}"
        return 1
    fi
}

check_consolidation_needed() {
    local threshold="${1:-10}"  # Default threshold: 10 incrementals

    log_info "=== Consolidation Health Check ==="
    log "Checking all repositories for consolidation needs..."
    log "Threshold: ${threshold} incremental bundles"
    log ""

    local needs_consolidation=()
    local total_checked=0

    # Check all bundle manifests
    while IFS= read -r manifest; do
        ((total_checked++)) || true

        local repo_dir
        repo_dir=$(dirname "$manifest")
        local repo_path="${repo_dir#${BUNDLE_DIR}/}"

        # Get incremental count
        local incremental_count
        incremental_count=$(jq -r '.incremental_count // 0' "$manifest" 2>/dev/null || echo "0")

        if [[ $incremental_count -ge $threshold ]]; then
            log_warning "${repo_path}: ${incremental_count} incremental bundles (threshold: ${threshold})"
            needs_consolidation+=("$repo_path")
        elif [[ $incremental_count -gt 0 ]]; then
            log "✓ ${repo_path}: ${incremental_count} incremental bundles"
        fi
    done < <(find "$BUNDLE_DIR" -name "bundle-manifest.json" -type f 2>/dev/null)

    log ""
    log "Checked ${total_checked} repositories"

    if [[ ${#needs_consolidation[@]} -gt 0 ]]; then
        log_warning "=== Consolidation Recommended for ${#needs_consolidation[@]} repositories ==="
        for repo in "${needs_consolidation[@]}"; do
            log_warning "  - ${repo}"
        done
        log ""
        log "To consolidate a repository, run:"
        log "  ./scripts/bundle/git-bundle-sync.sh consolidate <repo_path>"
        log ""

        # Send notification if enabled
        if [[ -x "$NOTIFY_SCRIPT" ]]; then
            local repo_list
            repo_list=$(printf '  - %s\n' "${needs_consolidation[@]}")
            "$NOTIFY_SCRIPT" warning \
                "CloudSync: Bundle Consolidation Recommended" \
                "${#needs_consolidation[@]} repositories have ${threshold}+ incremental bundles:
${repo_list}
Run consolidation to improve restore performance." || true
        fi

        return 1  # Indicates consolidation needed
    else
        log_info "✓ All repositories within consolidation threshold"
        return 0
    fi
}

#######################
# Main Test Execution
#######################

run_verification_suite() {
    log "=========================================="
    log "CloudSync Restore Verification Test Suite"
    log "=========================================="
    log "Start time: $(date)"
    log "Test directory: ${TEST_DIR}"
    log ""

    # Create test directory
    mkdir -p "$TEST_DIR"
    mkdir -p "$LOG_DIR"

    # Consolidation health check (before restore tests)
    check_consolidation_needed 10
    local consolidation_needed=$?
    log ""

    # Test 1: Small repository restore
    if [[ "$TEST_SMALL_REPO" == "true" ]]; then
        log_info "=== Test Suite 1: Small Repository Restore ==="
        local small_repos
        mapfile -t small_repos < <(find_test_repos "small" 3)

        if [[ ${#small_repos[@]} -eq 0 ]]; then
            log_warning "No small repos found to test"
        else
            for repo in "${small_repos[@]}"; do
                test_repo_restore "$repo" "small repo"
                if [[ "$TEST_IGNORED_FILES" == "true" ]]; then
                    test_ignored_files_restore "$repo"
                fi
            done
        fi
        log ""
    fi

    # Test 2: Large repository with incremental bundles
    if [[ "$TEST_LARGE_REPO" == "true" ]]; then
        log_info "=== Test Suite 2: Large Repository Incremental Restore ==="
        local large_repos
        mapfile -t large_repos < <(find_test_repos "large" 2)

        if [[ ${#large_repos[@]} -eq 0 ]]; then
            log_warning "No large repos found to test"
        else
            for repo in "${large_repos[@]}"; do
                test_incremental_bundle_chain "$repo"
                test_repo_restore "$repo" "large repo with incremental bundles"
            done
        fi
        log ""
    fi

    # Test 3: Medium repository (if we have tests remaining)
    local remaining_tests=$((MAX_REPOS_TO_TEST - TOTAL_TESTS))
    if [[ $remaining_tests -gt 0 ]]; then
        log_info "=== Test Suite 3: Medium Repository Restore ==="
        local medium_repos
        mapfile -t medium_repos < <(find_test_repos "medium" "$remaining_tests")

        if [[ ${#medium_repos[@]} -eq 0 ]]; then
            log_warning "No medium repos found to test"
        else
            for repo in "${medium_repos[@]}"; do
                test_repo_restore "$repo" "medium repo"
            done
        fi
        log ""
    fi

    # Summary
    log "=========================================="
    log "Restore Verification Summary"
    log "=========================================="
    log "Total tests run: ${TOTAL_TESTS}"
    log "Passed: ${PASSED_TESTS}"
    log "Failed: ${FAILED_TESTS}"
    log "Warnings: ${WARNINGS}"
    log "End time: $(date)"
    log ""

    # Cleanup
    if [[ "$CLEANUP_AFTER" == "true" ]]; then
        log_info "Cleaning up test directory: ${TEST_DIR}"
        rm -rf "$TEST_DIR"
    else
        log_info "Test directory preserved: ${TEST_DIR}"
    fi

    # Send notification
    if [[ -x "$NOTIFY_SCRIPT" ]]; then
        if [[ $FAILED_TESTS -eq 0 ]]; then
            "$NOTIFY_SCRIPT" success \
                "CloudSync: Restore Verification Passed" \
                "${PASSED_TESTS}/${TOTAL_TESTS} tests passed. Disaster recovery confirmed operational." || true
        else
            "$NOTIFY_SCRIPT" error \
                "CloudSync: Restore Verification Failed" \
                "${FAILED_TESTS}/${TOTAL_TESTS} tests failed. Check logs: ${VERIFY_LOG}" || true
        fi
    fi

    # Exit code
    [[ $FAILED_TESTS -eq 0 ]]
}

#######################
# CLI Interface
#######################

show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Verify CloudSync disaster recovery readiness by testing bundle restoration.

OPTIONS:
    --no-small          Skip small repo tests
    --no-large          Skip large repo tests
    --no-ignored        Skip critical ignored file tests
    --no-cleanup        Don't delete test directory after
    --max-repos N       Maximum repos to test (default: 5)
    -h, --help          Show this help message

EXAMPLES:
    $(basename "$0")                    # Run full verification suite
    $(basename "$0") --max-repos 10     # Test up to 10 repos
    $(basename "$0") --no-cleanup       # Keep test directory for inspection

The test results are logged to: ${VERIFY_LOG}

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-small)
            TEST_SMALL_REPO=false
            shift
            ;;
        --no-large)
            TEST_LARGE_REPO=false
            shift
            ;;
        --no-ignored)
            TEST_IGNORED_FILES=false
            shift
            ;;
        --no-cleanup)
            CLEANUP_AFTER=false
            shift
            ;;
        --max-repos)
            MAX_REPOS_TO_TEST="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_verification_suite
fi
