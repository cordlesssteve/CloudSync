#!/bin/bash
# Integration Tests for CloudSync Operations
# Tests complete sync workflows and multi-component interactions

set -euo pipefail

# Test setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
TEST_DATA_DIR="/tmp/cloudsync-integration-test-$$"
TEST_REMOTE="test-cloudsync"

# Source test utilities
source "$SCRIPT_DIR/../test-utils.sh"

# Setup test environment
setup_test_env() {
    mkdir -p "$TEST_DATA_DIR"

    # Create test files with different patterns
    mkdir -p "$TEST_DATA_DIR/source/docs"
    mkdir -p "$TEST_DATA_DIR/source/scripts"
    mkdir -p "$TEST_DATA_DIR/destination"

    # Text files
    echo "CloudSync Documentation" > "$TEST_DATA_DIR/source/docs/README.md"
    echo "Configuration Guide" > "$TEST_DATA_DIR/source/docs/config.md"

    # Script files
    echo '#!/bin/bash\necho "test script"' > "$TEST_DATA_DIR/source/scripts/test.sh"
    chmod +x "$TEST_DATA_DIR/source/scripts/test.sh"

    # Binary-like files
    dd if=/dev/urandom of="$TEST_DATA_DIR/source/random.dat" bs=1024 count=10 2>/dev/null

    # Create duplicates for deduplication testing
    cp "$TEST_DATA_DIR/source/docs/README.md" "$TEST_DATA_DIR/source/docs/README_copy.md"

    log_test_info "Test environment setup complete"
}

# Cleanup test environment
cleanup_test_env() {
    rm -rf "$TEST_DATA_DIR"
    log_test_info "Test environment cleaned up"
}

# Test bidirectional sync functionality
test_bidirectional_sync() {
    local sync_script="$PROJECT_ROOT/scripts/core/bidirectional-sync.sh"

    if [[ ! -x "$sync_script" ]]; then
        log_test_error "Bidirectional sync script not found or not executable"
        return 1
    fi

    # Test dry-run mode
    log_test_info "Testing bidirectional sync (dry-run)"
    if ! "$sync_script" --local "$TEST_DATA_DIR/source" --remote "$TEST_REMOTE" --path "integration-test" --dry-run; then
        log_test_error "Bidirectional sync dry-run failed"
        return 1
    fi

    log_test_success "Bidirectional sync test passed"
    return 0
}

# Test smart deduplication
test_smart_deduplication() {
    local dedupe_script="$PROJECT_ROOT/scripts/core/smart-dedupe.sh"

    if [[ ! -x "$dedupe_script" ]]; then
        log_test_error "Smart deduplication script not found"
        return 1
    fi

    # First, create some test data with duplicates on remote (simulated)
    log_test_info "Testing smart deduplication (dry-run)"
    if ! "$dedupe_script" --dry-run --remote "$TEST_REMOTE" --path "integration-test"; then
        log_test_error "Smart deduplication test failed"
        return 1
    fi

    log_test_success "Smart deduplication test passed"
    return 0
}

# Test checksum verification
test_checksum_verification() {
    local checksum_script="$PROJECT_ROOT/scripts/core/checksum-verify.sh"

    if [[ ! -x "$checksum_script" ]]; then
        log_test_error "Checksum verification script not found"
        return 1
    fi

    log_test_info "Testing checksum verification"
    if ! "$checksum_script" --local "$TEST_DATA_DIR/source" --remote "$TEST_REMOTE" --path "integration-test" --size-only; then
        log_test_error "Checksum verification test failed"
        return 1
    fi

    log_test_success "Checksum verification test passed"
    return 0
}

# Test conflict resolution
test_conflict_resolution() {
    local conflict_script="$PROJECT_ROOT/scripts/core/conflict-resolver.sh"

    if [[ ! -x "$conflict_script" ]]; then
        log_test_error "Conflict resolution script not found"
        return 1
    fi

    # Create a potential conflict scenario
    echo "Modified content" > "$TEST_DATA_DIR/source/docs/README.md"
    echo "Different content" > "$TEST_DATA_DIR/source/docs/README.md.conflict"

    log_test_info "Testing conflict resolution"
    if ! "$conflict_script" --scan --path "$TEST_DATA_DIR/source" --strategy "list"; then
        log_test_error "Conflict resolution test failed"
        return 1
    fi

    log_test_success "Conflict resolution test passed"
    return 0
}

# Test health monitoring integration
test_health_monitoring() {
    local health_script="$PROJECT_ROOT/scripts/monitoring/sync-health-check.sh"

    if [[ ! -x "$health_script" ]]; then
        log_test_error "Health monitoring script not found"
        return 1
    fi

    log_test_info "Testing health monitoring system"
    if ! timeout 30 "$health_script"; then
        log_test_error "Health monitoring test failed"
        return 1
    fi

    # Check if health check creates proper log files
    if [[ ! -f "$HOME/.cloudsync/health-check.log" ]]; then
        log_test_error "Health check log file not created"
        return 1
    fi

    log_test_success "Health monitoring test passed"
    return 0
}

# Test parallel operations
test_parallel_operations() {
    local parallel_script="$PROJECT_ROOT/scripts/performance/parallel-sync.sh"

    if [[ ! -x "$parallel_script" ]]; then
        log_test_error "Parallel operations script not found"
        return 1
    fi

    # Create a paths file for testing
    local paths_file="$TEST_DATA_DIR/test-paths.txt"
    echo "$TEST_DATA_DIR/source/docs" > "$paths_file"
    echo "$TEST_DATA_DIR/source/scripts" >> "$paths_file"

    log_test_info "Testing parallel operations"
    if ! "$parallel_script" batch-sync --jobs 2 --paths "$paths_file" --dry-run; then
        log_test_error "Parallel operations test failed"
        return 1
    fi

    log_test_success "Parallel operations test passed"
    return 0
}

# Test bandwidth management
test_bandwidth_management() {
    local bandwidth_script="$PROJECT_ROOT/scripts/performance/bandwidth-manager.sh"

    if [[ ! -x "$bandwidth_script" ]]; then
        log_test_error "Bandwidth management script not found"
        return 1
    fi

    log_test_info "Testing bandwidth management"

    # Test profile listing
    if ! "$bandwidth_script" profiles; then
        log_test_error "Bandwidth profile listing failed"
        return 1
    fi

    # Test profile application
    if ! "$bandwidth_script" apply-profile --profile balanced; then
        log_test_error "Bandwidth profile application failed"
        return 1
    fi

    log_test_success "Bandwidth management test passed"
    return 0
}

# Test monitoring configuration
test_monitoring_configuration() {
    local monitor_config="$PROJECT_ROOT/config/monitoring.conf"
    local monitor_script="$PROJECT_ROOT/scripts/monitoring/real-time-monitor.sh"

    if [[ ! -f "$monitor_config" ]]; then
        log_test_error "Monitoring configuration file not found"
        return 1
    fi

    if [[ ! -x "$monitor_script" ]]; then
        log_test_error "Real-time monitor script not found"
        return 1
    fi

    log_test_info "Testing monitoring configuration"

    # Test configuration loading
    if ! source "$monitor_config"; then
        log_test_error "Failed to load monitoring configuration"
        return 1
    fi

    # Test monitor script configuration test
    if ! "$monitor_script" test; then
        log_test_error "Monitoring configuration test failed"
        return 1
    fi

    log_test_success "Monitoring configuration test passed"
    return 0
}

# Test complete workflow integration
test_complete_workflow() {
    log_test_info "Testing complete CloudSync workflow"

    # 1. Health check
    if ! test_health_monitoring; then
        return 1
    fi

    # 2. Configuration validation
    if ! test_monitoring_configuration; then
        return 1
    fi

    # 3. Sync operations
    if ! test_bidirectional_sync; then
        return 1
    fi

    # 4. Post-sync operations
    if ! test_checksum_verification; then
        return 1
    fi

    # 5. Cleanup operations
    if ! test_smart_deduplication; then
        return 1
    fi

    log_test_success "Complete workflow integration test passed"
    return 0
}

# Main test execution
main() {
    log_test_info "🔗 Starting CloudSync Integration Tests"

    # Setup
    setup_test_env
    trap cleanup_test_env EXIT

    local failed_tests=0

    # Run individual integration tests
    test_bidirectional_sync || ((failed_tests++))
    test_smart_deduplication || ((failed_tests++))
    test_checksum_verification || ((failed_tests++))
    test_conflict_resolution || ((failed_tests++))
    test_health_monitoring || ((failed_tests++))
    test_parallel_operations || ((failed_tests++))
    test_bandwidth_management || ((failed_tests++))
    test_monitoring_configuration || ((failed_tests++))

    # Run complete workflow test
    test_complete_workflow || ((failed_tests++))

    if [[ $failed_tests -eq 0 ]]; then
        log_test_success "🎉 All integration tests passed!"
        exit 0
    else
        log_test_error "❌ $failed_tests integration test(s) failed"
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi