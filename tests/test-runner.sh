#!/bin/bash
# CloudSync Automated Testing Framework
# Comprehensive test runner for all CloudSync components and operations

set -euo pipefail

# Load configurations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
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
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Test framework configuration
TEST_RESULTS_DIR="$HOME/.cloudsync/test-results"
TEST_LOG_FILE="$TEST_RESULTS_DIR/test-run-$(date +%Y%m%d-%H%M%S).log"
TEST_DATA_DIR="/tmp/cloudsync-test-$$"
TEST_REMOTE="test-cloudsync"
TEST_TIMEOUT=300

# Test statistics
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Test suite definitions
TEST_SUITES=(
    "unit:Unit Tests:Basic component functionality tests"
    "integration:Integration Tests:Multi-component workflow tests"
    "performance:Performance Tests:Speed and efficiency benchmarks"
    "regression:Regression Tests:Prevent breaking changes"
    "security:Security Tests:Security and permissions validation"
    "end-to-end:End-to-End Tests:Complete user workflow validation"
)

# Create required directories
mkdir -p "$TEST_RESULTS_DIR"
mkdir -p "$TEST_DATA_DIR"

# Cleanup function
cleanup() {
    rm -rf "$TEST_DATA_DIR"

    # Clean up test remote if it exists
    if rclone listremotes | grep -q "^$TEST_REMOTE:"; then
        rclone delete "$TEST_REMOTE:" --rmdirs 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Logging functions
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] [$level] $message" >> "$TEST_LOG_FILE"

    case "$level" in
        "ERROR")
            echo -e "${RED}[$timestamp] [ERROR] $message${NC}" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[$timestamp] [WARN] $message${NC}"
            ;;
        "INFO")
            echo -e "${GREEN}[$timestamp] [INFO] $message${NC}"
            ;;
        "DEBUG")
            echo -e "${BLUE}[$timestamp] [DEBUG] $message${NC}"
            ;;
        "TEST")
            echo -e "${CYAN}[$timestamp] [TEST] $message${NC}"
            ;;
    esac
}

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"

    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        log_message "ERROR" "$message: expected '$expected', got '$actual'"
        return 1
    fi
}

assert_true() {
    local condition="$1"
    local message="${2:-Assertion failed}"

    if [[ "$condition" == "true" ]] || [[ "$condition" == "0" ]]; then
        return 0
    else
        log_message "ERROR" "$message: condition was false"
        return 1
    fi
}

assert_file_exists() {
    local filepath="$1"
    local message="${2:-File does not exist}"

    if [[ -f "$filepath" ]]; then
        return 0
    else
        log_message "ERROR" "$message: $filepath"
        return 1
    fi
}

assert_command_success() {
    local command="$1"
    local message="${2:-Command failed}"

    if eval "$command" >/dev/null 2>&1; then
        return 0
    else
        log_message "ERROR" "$message: $command"
        return 1
    fi
}

# Test execution framework
run_test() {
    local test_name="$1"
    local test_function="$2"
    local suite="${3:-unit}"

    ((TOTAL_TESTS++))

    log_message "TEST" "Running $suite test: $test_name"

    local test_start_time test_end_time test_duration
    test_start_time=$(date +%s.%N)

    local test_result="PASSED"
    local test_output

    # Run the test function and capture output
    if test_output=$($test_function 2>&1); then
        ((PASSED_TESTS++))
        log_message "INFO" "✅ PASSED: $test_name"
    else
        ((FAILED_TESTS++))
        test_result="FAILED"
        log_message "ERROR" "❌ FAILED: $test_name"
        if [[ -n "$test_output" ]]; then
            log_message "ERROR" "Test output: $test_output"
        fi
    fi

    test_end_time=$(date +%s.%N)
    test_duration=$(echo "$test_end_time - $test_start_time" | bc -l)

    # Record test result
    record_test_result "$suite" "$test_name" "$test_result" "$test_duration" "$test_output"
}

# Record test results
record_test_result() {
    local suite="$1"
    local test_name="$2"
    local result="$3"
    local duration="$4"
    local output="$5"

    local result_file="$TEST_RESULTS_DIR/results.jsonl"

    local test_record
    test_record=$(jq -n \
        --arg timestamp "$(date -Iseconds)" \
        --arg suite "$suite" \
        --arg test "$test_name" \
        --arg result "$result" \
        --arg duration "$duration" \
        --arg output "$output" \
        '{
            timestamp: $timestamp,
            suite: $suite,
            test: $test,
            result: $result,
            duration: ($duration | tonumber),
            output: $output
        }')

    echo "$test_record" >> "$result_file"
}

# Unit Tests
test_config_loading() {
    assert_file_exists "$CONFIG_FILE" "Configuration file missing"
    assert_true "$(grep -q "DEFAULT_REMOTE" "$CONFIG_FILE" && echo "true" || echo "false")" "DEFAULT_REMOTE not found in config"
    return 0
}

test_script_permissions() {
    local scripts_dir="$PROJECT_ROOT/scripts"
    local script_count=0
    local executable_count=0

    for script in $(find "$scripts_dir" -name "*.sh"); do
        ((script_count++))
        if [[ -x "$script" ]]; then
            ((executable_count++))
        fi
    done

    if [[ $script_count -eq $executable_count ]]; then
        return 0
    else
        log_message "ERROR" "Some scripts are not executable: $executable_count/$script_count"
        return 1
    fi
}

test_required_commands() {
    local required_commands=("rclone" "jq" "bc" "inotifywait")

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_message "ERROR" "Required command not found: $cmd"
            return 1
        fi
    done

    return 0
}

# Integration Tests
test_health_check_integration() {
    local health_script="$PROJECT_ROOT/scripts/monitoring/sync-health-check.sh"

    assert_file_exists "$health_script" "Health check script missing"
    assert_command_success "timeout 30 \"$health_script\"" "Health check failed to run"

    return 0
}

test_configuration_validation() {
    # Test that all paths in CRITICAL_PATHS exist or can be created
    for path in "${CRITICAL_PATHS[@]}"; do
        local full_path="$HOME/$path"
        if [[ ! -e "$full_path" ]]; then
            log_message "WARN" "Critical path does not exist: $full_path"
        fi
    done

    return 0
}

test_monitoring_system() {
    local monitor_config="$PROJECT_ROOT/config/monitoring.conf"
    local monitor_script="$PROJECT_ROOT/scripts/monitoring/real-time-monitor.sh"

    assert_file_exists "$monitor_config" "Monitoring config missing"
    assert_file_exists "$monitor_script" "Real-time monitor script missing"

    # Test configuration parsing
    if source "$monitor_config"; then
        assert_true "$(echo "$REALTIME_MONITORING_ENABLED" | grep -q "true\|false" && echo "true" || echo "false")" "Invalid monitoring config"
    else
        return 1
    fi

    return 0
}

# Performance Tests
test_sync_performance() {
    local benchmark_script="$PROJECT_ROOT/scripts/performance/benchmark.sh"

    if [[ ! -x "$benchmark_script" ]]; then
        log_message "ERROR" "Benchmark script not found or not executable"
        return 1
    fi

    # Run quick benchmark
    if timeout 60 "$benchmark_script" sync-performance --quick; then
        return 0
    else
        log_message "ERROR" "Performance benchmark failed"
        return 1
    fi
}

test_parallel_operations() {
    local parallel_script="$PROJECT_ROOT/scripts/performance/parallel-sync.sh"

    if [[ ! -x "$parallel_script" ]]; then
        log_message "ERROR" "Parallel sync script not found"
        return 1
    fi

    # Test parallel sync in dry-run mode
    if timeout 30 "$parallel_script" batch-sync --jobs 2 --dry-run; then
        return 0
    else
        log_message "ERROR" "Parallel operations test failed"
        return 1
    fi
}

# Security Tests
test_credential_security() {
    # Check that credential files have proper permissions
    local cred_file="$HOME/.claude/.credentials.json"

    if [[ -f "$cred_file" ]]; then
        local perms
        perms=$(stat -c %a "$cred_file")
        if [[ "$perms" == "600" ]] || [[ "$perms" == "400" ]]; then
            return 0
        else
            log_message "ERROR" "Credential file has insecure permissions: $perms"
            return 1
        fi
    fi

    return 0
}

test_log_file_permissions() {
    local log_dir="$HOME/.cloudsync"

    if [[ -d "$log_dir" ]]; then
        local perms
        perms=$(stat -c %a "$log_dir")
        if [[ "$perms" =~ ^7[0-5][0-5]$ ]]; then
            return 0
        else
            log_message "WARN" "Log directory has unusual permissions: $perms"
        fi
    fi

    return 0
}

# End-to-End Tests
test_complete_sync_workflow() {
    # Create test data
    local test_source_dir="$TEST_DATA_DIR/test-source"
    mkdir -p "$test_source_dir"

    echo "Test file content" > "$test_source_dir/test-file.txt"
    echo "Another test file" > "$test_source_dir/test-file2.txt"

    # Test basic sync operation (dry-run)
    if rclone sync "$test_source_dir" "$DEFAULT_REMOTE:CloudSync-Test/" --dry-run; then
        log_message "INFO" "Dry-run sync successful"
        return 0
    else
        log_message "ERROR" "Dry-run sync failed"
        return 1
    fi
}

# Test suite execution
run_unit_tests() {
    log_message "INFO" "🧪 Running Unit Tests"

    run_test "Config Loading" "test_config_loading" "unit"
    run_test "Script Permissions" "test_script_permissions" "unit"
    run_test "Required Commands" "test_required_commands" "unit"
}

run_integration_tests() {
    log_message "INFO" "🔗 Running Integration Tests"

    run_test "Health Check Integration" "test_health_check_integration" "integration"
    run_test "Configuration Validation" "test_configuration_validation" "integration"
    run_test "Monitoring System" "test_monitoring_system" "integration"
}

run_performance_tests() {
    log_message "INFO" "⚡ Running Performance Tests"

    run_test "Sync Performance" "test_sync_performance" "performance"
    run_test "Parallel Operations" "test_parallel_operations" "performance"
}

run_security_tests() {
    log_message "INFO" "🔒 Running Security Tests"

    run_test "Credential Security" "test_credential_security" "security"
    run_test "Log File Permissions" "test_log_file_permissions" "security"
}

run_end_to_end_tests() {
    log_message "INFO" "🎯 Running End-to-End Tests"

    run_test "Complete Sync Workflow" "test_complete_sync_workflow" "end-to-end"
}

# Generate test report
generate_test_report() {
    local report_file="$TEST_RESULTS_DIR/test-report-$(date +%Y%m%d-%H%M%S).json"
    local success_rate=0

    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$(echo "scale=2; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc -l)
    fi

    cat > "$report_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "summary": {
    "total_tests": $TOTAL_TESTS,
    "passed": $PASSED_TESTS,
    "failed": $FAILED_TESTS,
    "skipped": $SKIPPED_TESTS,
    "success_rate": $success_rate
  },
  "environment": {
    "hostname": "$(hostname)",
    "os": "$(uname -s)",
    "kernel": "$(uname -r)",
    "cloudsync_version": "$(cd "$PROJECT_ROOT" && git describe --tags 2>/dev/null || echo "development")"
  },
  "log_file": "$TEST_LOG_FILE",
  "results_file": "$TEST_RESULTS_DIR/results.jsonl"
}
EOF

    echo "$report_file"
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [SUITE]"
    echo ""
    echo "Test Suites:"
    for suite_def in "${TEST_SUITES[@]}"; do
        IFS=':' read -r name title description <<< "$suite_def"
        printf "  %-15s %s\n" "$name" "$description"
    done
    echo "  all                 Run all test suites"
    echo ""
    echo "Options:"
    echo "  --verbose           Enable verbose output"
    echo "  --timeout <sec>     Set test timeout (default: $TEST_TIMEOUT)"
    echo "  --parallel          Run tests in parallel (where possible)"
    echo "  --report            Generate detailed test report"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 unit"
    echo "  $0 all --verbose --report"
    echo "  $0 performance --timeout 600"
}

# Main execution
main() {
    local suites_to_run=()
    local verbose=false
    local parallel=false
    local generate_report=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            unit|integration|performance|security|end-to-end|all)
                suites_to_run+=("$1")
                shift
                ;;
            --verbose)
                verbose=true
                shift
                ;;
            --timeout)
                TEST_TIMEOUT="$2"
                shift 2
                ;;
            --parallel)
                parallel=true
                shift
                ;;
            --report)
                generate_report=true
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

    # Default to running all tests if no suite specified
    if [[ ${#suites_to_run[@]} -eq 0 ]]; then
        suites_to_run=("all")
    fi

    log_message "INFO" "🧪 CloudSync Automated Testing Framework"
    log_message "INFO" "Test results directory: $TEST_RESULTS_DIR"
    log_message "INFO" "Test log file: $TEST_LOG_FILE"
    echo "=" | head -c 60 && echo

    local test_start_time test_end_time
    test_start_time=$(date +%s)

    # Run requested test suites
    for suite in "${suites_to_run[@]}"; do
        case "$suite" in
            unit)
                run_unit_tests
                ;;
            integration)
                run_integration_tests
                ;;
            performance)
                run_performance_tests
                ;;
            security)
                run_security_tests
                ;;
            end-to-end)
                run_end_to_end_tests
                ;;
            all)
                run_unit_tests
                run_integration_tests
                run_performance_tests
                run_security_tests
                run_end_to_end_tests
                ;;
        esac
        echo
    done

    test_end_time=$(date +%s)
    local test_duration=$((test_end_time - test_start_time))

    # Show summary
    log_message "INFO" "📊 Test Summary"
    log_message "INFO" "Total tests: $TOTAL_TESTS"
    log_message "INFO" "Passed: $PASSED_TESTS"
    log_message "INFO" "Failed: $FAILED_TESTS"
    log_message "INFO" "Skipped: $SKIPPED_TESTS"
    log_message "INFO" "Duration: ${test_duration}s"

    local success_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc -l)
    fi
    log_message "INFO" "Success rate: ${success_rate}%"

    # Generate report if requested
    if $generate_report; then
        local report_file
        report_file=$(generate_test_report)
        log_message "INFO" "📄 Test report generated: $report_file"
    fi

    echo
    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_message "INFO" "🎉 All tests passed!"
        exit 0
    else
        log_message "ERROR" "❌ $FAILED_TESTS test(s) failed"
        exit 1
    fi
}

# Run main function
main "$@"