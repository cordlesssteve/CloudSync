#!/bin/bash
# CloudSync Performance Regression Testing
# Compares current performance against baseline measurements to detect regressions

set -euo pipefail

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
BASELINE_DIR="$HOME/.cloudsync/performance-baselines"
RESULTS_DIR="$HOME/.cloudsync/regression-results"
TEST_DATA_DIR="/tmp/cloudsync-regression-$$"

# Source test utilities
source "$SCRIPT_DIR/../test-utils.sh"

# Performance thresholds (percentage variance allowed)
SYNC_PERFORMANCE_THRESHOLD=20    # 20% slower is a regression
PARALLEL_PERFORMANCE_THRESHOLD=15
MEMORY_USAGE_THRESHOLD=30
CPU_USAGE_THRESHOLD=25

# Create required directories
mkdir -p "$BASELINE_DIR"
mkdir -p "$RESULTS_DIR"
mkdir -p "$TEST_DATA_DIR"

# Cleanup function
cleanup() {
    rm -rf "$TEST_DATA_DIR"
}
trap cleanup EXIT

# Generate performance test data
generate_regression_test_data() {
    log_test_info "Generating regression test data"

    # Create different file size categories
    local small_files_dir="$TEST_DATA_DIR/small"
    local medium_files_dir="$TEST_DATA_DIR/medium"
    local large_files_dir="$TEST_DATA_DIR/large"

    mkdir -p "$small_files_dir" "$medium_files_dir" "$large_files_dir"

    # Small files (1KB each, 100 files)
    for i in {1..100}; do
        generate_random_file "$small_files_dir/small_$i.dat" "1K"
    done

    # Medium files (100KB each, 20 files)
    for i in {1..20}; do
        generate_random_file "$medium_files_dir/medium_$i.dat" "100K"
    done

    # Large files (10MB each, 3 files)
    for i in {1..3}; do
        generate_random_file "$large_files_dir/large_$i.dat" "10M"
    done

    log_test_info "Generated test data: $(du -sh "$TEST_DATA_DIR" | cut -f1)"
}

# Measure sync performance
measure_sync_performance() {
    local test_dir="$1"
    local test_name="$2"

    log_test_info "Measuring sync performance: $test_name"

    local sync_script="$PROJECT_ROOT/scripts/core/bidirectional-sync.sh"

    # Measure upload performance
    start_timer
    "$sync_script" --local "$test_dir" --remote "test-cloudsync" --path "regression-test/$test_name" --dry-run >/dev/null 2>&1
    local upload_time
    upload_time=$(stop_timer)

    # Calculate throughput
    local test_size_mb
    test_size_mb=$(du -sm "$test_dir" | cut -f1)
    local throughput
    throughput=$(echo "scale=2; $test_size_mb / $upload_time" | bc -l)

    echo "$upload_time|$throughput|$test_size_mb"
}

# Measure parallel operation performance
measure_parallel_performance() {
    log_test_info "Measuring parallel operation performance"

    local parallel_script="$PROJECT_ROOT/scripts/performance/parallel-sync.sh"

    # Create paths file for parallel testing
    local paths_file="$TEST_DATA_DIR/parallel-paths.txt"
    echo "$TEST_DATA_DIR/small" > "$paths_file"
    echo "$TEST_DATA_DIR/medium" >> "$paths_file"
    echo "$TEST_DATA_DIR/large" >> "$paths_file"

    # Measure serial vs parallel performance
    start_timer
    "$parallel_script" batch-sync --jobs 1 --paths "$paths_file" --dry-run >/dev/null 2>&1
    local serial_time
    serial_time=$(stop_timer)

    start_timer
    "$parallel_script" batch-sync --jobs 4 --paths "$paths_file" --dry-run >/dev/null 2>&1
    local parallel_time
    parallel_time=$(stop_timer)

    local speedup
    speedup=$(echo "scale=2; $serial_time / $parallel_time" | bc -l)

    echo "$serial_time|$parallel_time|$speedup"
}

# Measure resource usage
measure_resource_usage() {
    log_test_info "Measuring resource usage"

    local benchmark_script="$PROJECT_ROOT/scripts/performance/benchmark.sh"

    # Start monitoring
    local monitor_file="$TEST_DATA_DIR/resource-monitor.log"
    {
        while true; do
            # CPU usage
            local cpu_usage
            cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')

            # Memory usage
            local memory_usage
            memory_usage=$(free | grep Mem | awk '{printf("%.1f", $3/$2 * 100.0)}')

            echo "$(date +%s)|$cpu_usage|$memory_usage" >> "$monitor_file"
            sleep 1
        done
    } &
    local monitor_pid=$!

    # Run benchmark
    "$benchmark_script" sync-performance --quick >/dev/null 2>&1

    # Stop monitoring
    kill "$monitor_pid" 2>/dev/null || true
    wait "$monitor_pid" 2>/dev/null || true

    # Calculate average resource usage
    if [[ -f "$monitor_file" ]]; then
        local avg_cpu avg_memory
        avg_cpu=$(awk -F'|' '{sum+=$2; count++} END {print sum/count}' "$monitor_file")
        avg_memory=$(awk -F'|' '{sum+=$3; count++} END {print sum/count}' "$monitor_file")

        echo "$avg_cpu|$avg_memory"
    else
        echo "0|0"
    fi
}

# Save performance baseline
save_baseline() {
    local test_name="$1"
    local results="$2"
    local timestamp="$3"

    local baseline_file="$BASELINE_DIR/$test_name.baseline"

    cat > "$baseline_file" << EOF
{
  "test": "$test_name",
  "timestamp": "$timestamp",
  "results": "$results",
  "git_commit": "$(cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null || echo "unknown")",
  "system_info": {
    "hostname": "$(hostname)",
    "os": "$(uname -s)",
    "kernel": "$(uname -r)",
    "cpu_cores": "$(nproc)",
    "memory_gb": "$(free -g | awk '/^Mem:/{print $2}')"
  }
}
EOF

    log_test_info "Saved baseline: $baseline_file"
}

# Load performance baseline
load_baseline() {
    local test_name="$1"
    local baseline_file="$BASELINE_DIR/$test_name.baseline"

    if [[ -f "$baseline_file" ]]; then
        jq -r '.results' "$baseline_file" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Compare performance against baseline
compare_performance() {
    local test_name="$1"
    local current_results="$2"
    local baseline_results="$3"
    local threshold="$4"

    if [[ -z "$baseline_results" ]]; then
        log_test_warn "No baseline found for $test_name, creating new baseline"
        save_baseline "$test_name" "$current_results" "$(date -Iseconds)"
        return 0
    fi

    # Parse results based on test type
    case "$test_name" in
        "sync_small"|"sync_medium"|"sync_large")
            local current_time current_throughput
            IFS='|' read -r current_time current_throughput _ <<< "$current_results"

            local baseline_time baseline_throughput
            IFS='|' read -r baseline_time baseline_throughput _ <<< "$baseline_results"

            # Check if performance degraded
            local time_increase
            time_increase=$(echo "scale=2; ($current_time - $baseline_time) / $baseline_time * 100" | bc -l)

            local throughput_decrease
            throughput_decrease=$(echo "scale=2; ($baseline_throughput - $current_throughput) / $baseline_throughput * 100" | bc -l)

            log_test_info "Performance comparison for $test_name:"
            log_test_info "  Time: ${current_time}s vs ${baseline_time}s (${time_increase}% change)"
            log_test_info "  Throughput: ${current_throughput}MB/s vs ${baseline_throughput}MB/s (${throughput_decrease}% change)"

            # Check for regression
            if (( $(echo "$time_increase > $threshold" | bc -l) )) || (( $(echo "$throughput_decrease > $threshold" | bc -l) )); then
                log_test_error "Performance regression detected in $test_name"
                return 1
            fi
            ;;
        "parallel")
            local current_serial current_parallel current_speedup
            IFS='|' read -r current_serial current_parallel current_speedup <<< "$current_results"

            local baseline_serial baseline_parallel baseline_speedup
            IFS='|' read -r baseline_serial baseline_parallel baseline_speedup <<< "$baseline_results"

            local speedup_decrease
            speedup_decrease=$(echo "scale=2; ($baseline_speedup - $current_speedup) / $baseline_speedup * 100" | bc -l)

            log_test_info "Parallel performance comparison:"
            log_test_info "  Current speedup: ${current_speedup}x vs baseline: ${baseline_speedup}x (${speedup_decrease}% change)"

            if (( $(echo "$speedup_decrease > $threshold" | bc -l) )); then
                log_test_error "Parallel performance regression detected"
                return 1
            fi
            ;;
        "resources")
            local current_cpu current_memory
            IFS='|' read -r current_cpu current_memory <<< "$current_results"

            local baseline_cpu baseline_memory
            IFS='|' read -r baseline_cpu baseline_memory <<< "$baseline_results"

            local cpu_increase memory_increase
            cpu_increase=$(echo "scale=2; ($current_cpu - $baseline_cpu) / $baseline_cpu * 100" | bc -l)
            memory_increase=$(echo "scale=2; ($current_memory - $baseline_memory) / $baseline_memory * 100" | bc -l)

            log_test_info "Resource usage comparison:"
            log_test_info "  CPU: ${current_cpu}% vs ${baseline_cpu}% (${cpu_increase}% change)"
            log_test_info "  Memory: ${current_memory}% vs ${baseline_memory}% (${memory_increase}% change)"

            if (( $(echo "$cpu_increase > $CPU_USAGE_THRESHOLD" | bc -l) )) || (( $(echo "$memory_increase > $MEMORY_USAGE_THRESHOLD" | bc -l) )); then
                log_test_error "Resource usage regression detected"
                return 1
            fi
            ;;
    esac

    log_test_success "No performance regression detected in $test_name"
    return 0
}

# Run sync performance regression tests
test_sync_performance_regression() {
    log_test_info "Running sync performance regression tests"

    local failed_tests=0

    # Test different file sizes
    for size in small medium large; do
        local test_dir="$TEST_DATA_DIR/$size"
        local results
        results=$(measure_sync_performance "$test_dir" "$size")

        local baseline
        baseline=$(load_baseline "sync_$size")

        if ! compare_performance "sync_$size" "$results" "$baseline" "$SYNC_PERFORMANCE_THRESHOLD"; then
            ((failed_tests++))
        else
            # Update baseline if performance improved significantly
            if [[ -n "$baseline" ]]; then
                local current_time baseline_time
                current_time=$(echo "$results" | cut -d'|' -f1)
                baseline_time=$(echo "$baseline" | cut -d'|' -f1)

                local improvement
                improvement=$(echo "scale=2; ($baseline_time - $current_time) / $baseline_time * 100" | bc -l)

                if (( $(echo "$improvement > 10" | bc -l) )); then
                    log_test_info "Significant performance improvement detected, updating baseline"
                    save_baseline "sync_$size" "$results" "$(date -Iseconds)"
                fi
            fi
        fi
    done

    return $failed_tests
}

# Run parallel operation regression tests
test_parallel_performance_regression() {
    log_test_info "Running parallel performance regression tests"

    local results
    results=$(measure_parallel_performance)

    local baseline
    baseline=$(load_baseline "parallel")

    if ! compare_performance "parallel" "$results" "$baseline" "$PARALLEL_PERFORMANCE_THRESHOLD"; then
        return 1
    else
        # Update baseline if needed
        if [[ -n "$baseline" ]]; then
            local current_speedup baseline_speedup
            current_speedup=$(echo "$results" | cut -d'|' -f3)
            baseline_speedup=$(echo "$baseline" | cut -d'|' -f3)

            local improvement
            improvement=$(echo "scale=2; ($current_speedup - $baseline_speedup) / $baseline_speedup * 100" | bc -l)

            if (( $(echo "$improvement > 15" | bc -l) )); then
                log_test_info "Significant parallel performance improvement, updating baseline"
                save_baseline "parallel" "$results" "$(date -Iseconds)"
            fi
        fi
    fi

    return 0
}

# Run resource usage regression tests
test_resource_usage_regression() {
    log_test_info "Running resource usage regression tests"

    local results
    results=$(measure_resource_usage)

    local baseline
    baseline=$(load_baseline "resources")

    if ! compare_performance "resources" "$results" "$baseline" "$MEMORY_USAGE_THRESHOLD"; then
        return 1
    else
        # Update baseline if resource usage improved
        if [[ -n "$baseline" ]]; then
            save_baseline "resources" "$results" "$(date -Iseconds)"
        fi
    fi

    return 0
}

# Generate regression test report
generate_regression_report() {
    local test_results="$1"
    local report_file="$RESULTS_DIR/regression-report-$(date +%Y%m%d-%H%M%S).json"

    cat > "$report_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "git_commit": "$(cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null || echo "unknown")",
  "test_results": $test_results,
  "baselines_directory": "$BASELINE_DIR",
  "system_info": {
    "hostname": "$(hostname)",
    "os": "$(uname -s)",
    "kernel": "$(uname -r)",
    "cpu_cores": "$(nproc)",
    "memory_gb": "$(free -g | awk '/^Mem:/{print $2}')"
  }
}
EOF

    log_test_info "Generated regression report: $report_file"
    echo "$report_file"
}

# Main execution
main() {
    local create_baseline=false
    local verbose=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --baseline)
                create_baseline=true
                shift
                ;;
            --verbose)
                verbose=true
                export TEST_DEBUG=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --baseline    Create new performance baselines"
                echo "  --verbose     Enable verbose output"
                echo "  --help        Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    log_test_info "🔄 CloudSync Performance Regression Testing"
    log_test_info "Results directory: $RESULTS_DIR"

    # Generate test data
    generate_regression_test_data

    local total_failures=0

    # Run regression tests
    test_sync_performance_regression || ((total_failures++))
    test_parallel_performance_regression || ((total_failures++))
    test_resource_usage_regression || ((total_failures++))

    # Generate report
    local test_results_json
    test_results_json=$(cat << EOF
{
  "sync_performance": "$(if [[ $total_failures -eq 0 ]]; then echo "PASSED"; else echo "FAILED"; fi)",
  "parallel_performance": "$(if [[ $total_failures -eq 0 ]]; then echo "PASSED"; else echo "FAILED"; fi)",
  "resource_usage": "$(if [[ $total_failures -eq 0 ]]; then echo "PASSED"; else echo "FAILED"; fi)",
  "total_failures": $total_failures
}
EOF
)

    generate_regression_report "$test_results_json"

    if [[ $total_failures -eq 0 ]]; then
        log_test_success "🎉 All performance regression tests passed!"
        exit 0
    else
        log_test_error "❌ $total_failures performance regression(s) detected"
        exit 1
    fi
}

# Run main function
main "$@"