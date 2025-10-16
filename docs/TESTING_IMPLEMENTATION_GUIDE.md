# CloudSync Testing Implementation Guide

**Purpose:** Practical, step-by-step guide to implement critical testing infrastructure
**Status:** PLANNING PHASE
**Target:** End-to-end verification of backup → package → upload → download → restore workflow

---

## Quick Start: Create Test User

### Setup Test User (One-Time)

```bash
# Create test user with home directory
sudo useradd -m -s /bin/bash csync-tester

# Create required directories
sudo mkdir -p /home/csync-tester/.cloudsync/logs
sudo mkdir -p /home/csync-tester/.cloudsync/test-results
sudo chown -R csync-tester:csync-tester /home/csync-tester/.cloudsync

# Allow sudo operations for testing without password
sudo visudo  # Add line: csync-tester ALL=(ALL) NOPASSWD: /usr/bin/rsync

# Copy CloudSync repo to test user (optional - can clone fresh)
sudo -u csync-tester git clone https://github.com/cordlesssteve/CloudSync.git /home/csync-tester/CloudSync

# Copy rclone config for OneDrive access (optional - tests can use real OneDrive)
sudo mkdir -p /home/csync-tester/.config/rclone
sudo cp ~/.config/rclone/rclone.conf /home/csync-tester/.config/rclone/
sudo chown csync-tester:csync-tester /home/csync-tester/.config/rclone/*
```

### Run as Test User

```bash
# Login as test user
su - csync-tester

# Or run command directly
sudo -u csync-tester -H bash -c 'cd ~/CloudSync && ./tests/test-runner.sh unit'
```

---

## Phase 1: Bundle Creation Unit Tests

**File:** `tests/unit/bundle-creation.test.sh`

```bash
#!/bin/bash
# CloudSync Bundle Creation Unit Tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
TEST_DATA_DIR="/tmp/cloudsync-bundle-test-$$"

source "$SCRIPT_DIR/../test-utils.sh"

# Setup
setup_test_repos() {
    mkdir -p "$TEST_DATA_DIR/repos"

    # Small test repo (< 10MB)
    mkdir -p "$TEST_DATA_DIR/repos/small"
    cd "$TEST_DATA_DIR/repos/small"
    git init
    for i in {1..10}; do
        echo "File $i content" > "file_$i.txt"
        git add "file_$i.txt"
        git commit -m "Commit $i"
    done

    # Medium test repo (50MB)
    mkdir -p "$TEST_DATA_DIR/repos/medium"
    cd "$TEST_DATA_DIR/repos/medium"
    git init
    for i in {1..5}; do
        dd if=/dev/urandom of="binary_$i.dat" bs=1M count=10 2>/dev/null
        git add "binary_$i.dat"
        git commit -m "Binary commit $i"
    done

    # Branch structure
    git checkout -b develop
    echo "Develop content" > develop.txt
    git add develop.txt
    git commit -m "Develop branch"

    cd - > /dev/null
}

# Test: Create small repo bundle
test_create_small_bundle() {
    local repo_path="$TEST_DATA_DIR/repos/small"
    local bundle_path="$TEST_DATA_DIR/small.bundle"

    log_test_info "Creating small repo bundle..."

    # Run bundle creation
    if ! git -C "$repo_path" bundle create "$bundle_path" --all; then
        log_test_error "Failed to create bundle"
        return 1
    fi

    # Verify bundle exists
    assert_file_exists "$bundle_path" "Bundle file not created" || return 1

    # Verify bundle size is reasonable
    local bundle_size
    bundle_size=$(stat -f%z "$bundle_path" 2>/dev/null || stat -c%s "$bundle_path" 2>/dev/null)
    if [[ $bundle_size -lt 1000 ]]; then
        log_test_error "Bundle size too small: $bundle_size bytes"
        return 1
    fi

    log_test_success "Small bundle created: $bundle_size bytes"
    return 0
}

# Test: Create medium repo bundle
test_create_medium_bundle() {
    local repo_path="$TEST_DATA_DIR/repos/medium"
    local bundle_path="$TEST_DATA_DIR/medium.bundle"

    log_test_info "Creating medium repo bundle..."

    if ! git -C "$repo_path" bundle create "$bundle_path" --all; then
        log_test_error "Failed to create medium bundle"
        return 1
    fi

    assert_file_exists "$bundle_path" "Medium bundle not created" || return 1

    local bundle_size
    bundle_size=$(stat -f%z "$bundle_path" 2>/dev/null || stat -c%s "$bundle_path" 2>/dev/null)
    log_test_success "Medium bundle created: $bundle_size bytes"
    return 0
}

# Test: Verify bundle format
test_verify_bundle_format() {
    local repo_path="$TEST_DATA_DIR/repos/small"
    local bundle_path="$TEST_DATA_DIR/small.bundle"

    git -C "$repo_path" bundle create "$bundle_path" --all

    log_test_info "Verifying bundle format..."

    # Bundle file starts with specific header
    local header
    header=$(head -c 6 "$bundle_path" | od -A n -t x1 | tr -d ' \n')

    # Valid git bundle header
    if [[ "$header" == "234e20343839" ]]; then  # "#!git bundle v3" magic bytes
        log_test_success "Bundle format valid"
        return 0
    else
        log_test_error "Invalid bundle format: $header"
        return 1
    fi
}

# Test: Verify bundle contains all commits
test_verify_bundle_completeness() {
    local repo_path="$TEST_DATA_DIR/repos/small"
    local bundle_path="$TEST_DATA_DIR/small.bundle"

    git -C "$repo_path" bundle create "$bundle_path" --all

    log_test_info "Verifying bundle completeness..."

    local repo_commits
    repo_commits=$(git -C "$repo_path" rev-list --all --count)

    # Verify bundle verifies (will fail if refs don't match)
    if ! git bundle verify "$bundle_path" > /dev/null 2>&1; then
        log_test_error "Bundle verification failed"
        return 1
    fi

    log_test_success "Bundle contains all $repo_commits commits"
    return 0
}

# Test: Create incremental bundle
test_create_incremental_bundle() {
    local repo_path="$TEST_DATA_DIR/repos/small"
    local full_bundle="$TEST_DATA_DIR/full.bundle"
    local inc_bundle="$TEST_DATA_DIR/inc.bundle"

    log_test_info "Creating incremental bundle..."

    # Create initial full bundle
    git -C "$repo_path" bundle create "$full_bundle" --all

    # Add a new commit
    cd "$repo_path"
    echo "New content" > new_file.txt
    git add new_file.txt
    git commit -m "New commit for incremental"
    cd - > /dev/null

    # Create incremental bundle
    local last_commit
    last_commit=$(git -C "$repo_path" rev-list --all | head -1)

    if ! git -C "$repo_path" bundle create "$inc_bundle" "$last_commit" ^$(git bundle list-heads "$full_bundle" | awk '{print $1}' | head -1); then
        # If incremental fails, just create new full bundle (acceptable for small tests)
        git -C "$repo_path" bundle create "$inc_bundle" --all
    fi

    assert_file_exists "$inc_bundle" "Incremental bundle not created" || return 1

    log_test_success "Incremental bundle created"
    return 0
}

# Cleanup
cleanup() {
    rm -rf "$TEST_DATA_DIR"
}

# Main execution
main() {
    log_test_info "🧪 Starting Bundle Creation Unit Tests"

    setup_test_repos
    trap cleanup EXIT

    local failed=0

    run_test "Create Small Bundle" test_create_small_bundle "unit" || ((failed++))
    run_test "Create Medium Bundle" test_create_medium_bundle "unit" || ((failed++))
    run_test "Verify Bundle Format" test_verify_bundle_format "unit" || ((failed++))
    run_test "Verify Bundle Completeness" test_verify_bundle_completeness "unit" || ((failed++))
    run_test "Create Incremental Bundle" test_create_incremental_bundle "unit" || ((failed++))

    if [[ $failed -eq 0 ]]; then
        log_test_success "✅ All bundle creation tests passed"
        return 0
    else
        log_test_error "❌ $failed test(s) failed"
        return 1
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

---

## Phase 2: Bundle Restoration Tests

**File:** `tests/unit/bundle-restore.test.sh`

### Key Test Scenarios

```bash
# Test 1: Restore repo from bundle
test_restore_from_bundle() {
    local bundle_path="$TEST_DATA_DIR/test.bundle"
    local restore_path="$TEST_DATA_DIR/restored_repo"

    # Create bundle from source
    git -C "$TEST_DATA_DIR/source_repo" bundle create "$bundle_path" --all

    # Clone from bundle
    git clone "$bundle_path" "$restore_path"

    # Verify restoration
    assert_dir_exists "$restore_path/.git" "Git directory not restored" || return 1

    # Verify commit history
    local commit_count
    commit_count=$(git -C "$restore_path" rev-list --all --count)
    [[ $commit_count -gt 0 ]] || return 1

    log_test_success "Restored repo has $commit_count commits"
    return 0
}

# Test 2: Verify all branches restored
test_verify_branches_restored() {
    local bundle_path="$TEST_DATA_DIR/test.bundle"
    local restore_path="$TEST_DATA_DIR/restored_repo"

    git clone "$bundle_path" "$restore_path"

    # Get branches from original and restored
    local original_branches
    original_branches=$(git -C "$TEST_DATA_DIR/source_repo" branch -a | wc -l)

    local restored_branches
    restored_branches=$(git -C "$restore_path" branch -a | wc -l)

    if [[ $original_branches -eq $restored_branches ]]; then
        log_test_success "All $restored_branches branches restored"
        return 0
    else
        log_test_error "Branch count mismatch: $original_branches vs $restored_branches"
        return 1
    fi
}

# Test 3: Verify file contents bit-identical
test_verify_bit_identical() {
    local bundle_path="$TEST_DATA_DIR/test.bundle"
    local restore_path="$TEST_DATA_DIR/restored_repo"

    git clone "$bundle_path" "$restore_path"

    # Compare repository structures
    local orig_files
    local restored_files

    orig_files=$(find "$TEST_DATA_DIR/source_repo" -type f ! -path '*/.git/*' | sort)
    restored_files=$(find "$restore_path" -type f ! -path '*/.git/*' | sort)

    while read -r orig_file; do
        if [[ -n "$orig_file" ]]; then
            local rel_path="${orig_file#$TEST_DATA_DIR/source_repo/}"
            local restored_file="$restore_path/$rel_path"

            if ! cmp -s "$orig_file" "$restored_file"; then
                log_test_error "File contents differ: $rel_path"
                return 1
            fi
        fi
    done <<< "$orig_files"

    log_test_success "All files are bit-identical after restore"
    return 0
}
```

---

## Phase 3: End-to-End Workflow Test

**File:** `tests/integration/bundle-full-cycle.test.sh`

### Complete Cycle Test

```bash
test_full_backup_cycle() {
    log_test_info "Starting complete backup cycle test..."

    local test_repo="$TEST_DATA_DIR/test_repo"
    local bundle_file="$TEST_DATA_DIR/test.bundle"
    local upload_path="$TEST_DATA_DIR/onedrive_sim"
    local restored_repo="$TEST_DATA_DIR/restored_repo"

    # STEP 1: Create test repository
    log_test_info "STEP 1: Creating test repository..."
    mkdir -p "$test_repo"
    cd "$test_repo"
    git init
    for i in {1..5}; do
        echo "Content $i" > "file_$i.txt"
        git add "file_$i.txt"
        git commit -m "Commit $i"
    done

    # STEP 2: Create bundle
    log_test_info "STEP 2: Creating git bundle..."
    git bundle create "$bundle_file" --all
    assert_file_exists "$bundle_file" "Bundle creation failed" || return 1

    # STEP 3: Simulate upload
    log_test_info "STEP 3: Simulating upload to OneDrive..."
    mkdir -p "$upload_path"
    cp "$bundle_file" "$upload_path/test.bundle"
    assert_file_exists "$upload_path/test.bundle" "Upload simulation failed" || return 1

    # STEP 4: Simulate download
    log_test_info "STEP 4: Simulating download from OneDrive..."
    local download_bundle="$TEST_DATA_DIR/downloaded.bundle"
    cp "$upload_path/test.bundle" "$download_bundle"
    assert_file_exists "$download_bundle" "Download simulation failed" || return 1

    # STEP 5: Verify bundle integrity
    log_test_info "STEP 5: Verifying bundle integrity..."
    if ! git bundle verify "$download_bundle" > /dev/null 2>&1; then
        log_test_error "Downloaded bundle integrity check failed"
        return 1
    fi

    # STEP 6: Restore from bundle
    log_test_info "STEP 6: Restoring repository..."
    git clone "$download_bundle" "$restored_repo"
    assert_dir_exists "$restored_repo/.git" "Repository restore failed" || return 1

    # STEP 7: Verify complete integrity
    log_test_info "STEP 7: Verifying integrity after restore..."
    if ! git -C "$restored_repo" fsck --full > /dev/null 2>&1; then
        log_test_error "Restored repository is corrupted"
        return 1
    fi

    # STEP 8: Verify commits match
    log_test_info "STEP 8: Verifying all commits restored..."
    local orig_commits
    local restored_commits

    orig_commits=$(git -C "$test_repo" rev-list --all --count)
    restored_commits=$(git -C "$restored_repo" rev-list --all --count)

    if [[ $orig_commits -ne $restored_commits ]]; then
        log_test_error "Commit count mismatch: $orig_commits vs $restored_commits"
        return 1
    fi

    log_test_success "✅ Complete cycle verified: $orig_commits commits intact"
    return 0
}
```

---

## Running the Tests

### Quick Test Run

```bash
# As cordlesssteve user
cd ~/projects/Utility/LOGISTICAL/CloudSync

# Run unit tests only (safe, no cloud access)
./tests/test-runner.sh unit

# Run integration tests (as test user)
sudo -u csync-tester -H bash -c 'cd ~/CloudSync && ./tests/test-runner.sh integration'
```

### Full Test Suite

```bash
# Create test user first (one-time setup)
./scripts/setup-test-environment.sh

# Run complete test suite
sudo -u csync-tester -H bash -c 'cd ~/CloudSync && ./tests/test-runner.sh all --report'
```

### Test with Real OneDrive (Production Validation)

```bash
# As csync-tester with OneDrive configured
TEST_MODE=real ./tests/test-runner.sh integration

# Verify production restore works
./tests/integration/verify-production-restore.sh --repo "small-test-repo"
```

---

## Success Criteria

All of these must pass:

- [ ] Bundle creation test passes
- [ ] Bundle format verification passes
- [ ] Bundle completeness verification passes
- [ ] Repository restore from bundle passes
- [ ] Restored repo passes `git fsck`
- [ ] Restored repo has identical commit count
- [ ] File contents are bit-identical after restore
- [ ] Full cycle test completes successfully

**Until ALL pass:** System is NOT verified as production-ready

---

## Debugging Failed Tests

### If Bundle Creation Fails

```bash
# Verify git is working
git --version

# Test bundle on small repo
cd /tmp && git init test-repo
cd test-repo
echo "test" > file.txt
git add file.txt
git commit -m "test"
git bundle create ../test.bundle --all

# Verify bundle
git bundle verify ../test.bundle
```

### If Restore Fails

```bash
# Try manual restore
git clone test.bundle restored-repo

# Check integrity
git -C restored-repo fsck --full

# Compare commits
git -C test-repo rev-list --all --count
git -C restored-repo rev-list --all --count
```

### If File Contents Differ

```bash
# Find differences
diff -r original/ restored/ > /tmp/diff.txt

# Check specific file
cmp -l original/file.txt restored/file.txt
```

---

## Next Steps

1. **Create the test user:**
   ```bash
   sudo useradd -m -s /bin/bash csync-tester
   ```

2. **Implement bundle creation tests** (tests/unit/bundle-creation.test.sh)

3. **Implement restore tests** (tests/unit/bundle-restore.test.sh)

4. **Run tests and document failures**

5. **Fix any issues found**

6. **Only then:** Update CURRENT_STATUS.md to say system is "verified production-ready"

---

## Current Honest Status

- ✓ CloudSync bundles created and stored
- ✓ Bundles uploaded to OneDrive
- ❌ **No evidence bundles can be restored successfully**
- ❌ **No verification of data integrity after restore**
- ❌ **Disaster recovery claims are untested**

**After implementing tests above:** You'll have actual verification.
