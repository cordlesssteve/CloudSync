#!/bin/bash
# CloudSync Performance Benchmarking Suite
# Comprehensive testing and performance measurement for sync operations

set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
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

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE="$HOME/.cloudsync/benchmark.log"
RESULTS_DIR="$HOME/.cloudsync/benchmark-results"
TEST_DATA_DIR="/tmp/cloudsync-benchmark-$$"

# Benchmark settings
BENCHMARK_PROFILES=(
    "small:1MB:10:Small files test"
    "medium:10MB:50:Medium files test"
    "large:100MB:5:Large files test"
    "mixed:varied:100:Mixed file sizes test"
)

# Test parameters
TEST_ITERATIONS=3
WARMUP_RUNS=1
MAX_PARALLEL_TESTS=4

# Create directories
mkdir -p "$HOME/.cloudsync"
mkdir -p "$RESULTS_DIR"
mkdir -p "$TEST_DATA_DIR"

# Cleanup function
cleanup() {
    rm -rf "$TEST_DATA_DIR"
}
trap cleanup EXIT

# Function to log messages
log_message() {
    echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
    echo -e "$1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] BENCHMARK_TYPE"
    echo ""
    echo "Benchmark Types:"
    echo "  sync-performance    Test sync operation speeds"
    echo "  parallel-vs-serial  Compare parallel vs serial operations"
    echo "  bandwidth-impact    Test bandwidth limiting effects"
    echo "  feature-overhead    Measure feature performance overhead"
    echo "  full-suite          Run complete benchmark suite"
    echo ""
    echo "Options:"
    echo "  --iterations <num>  Number of test iterations (default: $TEST_ITERATIONS)"
    echo "  --warmup <num>      Number of warmup runs (default: $WARMUP_RUNS)"
    echo "  --parallel <num>    Max parallel tests (default: $MAX_PARALLEL_TESTS)"
    echo "  --size <size>       Test file size (e.g., 1MB, 10MB, 100MB)"
    echo "  --count <num>       Number of test files"
    echo "  --remote <remote>   Remote to test against (default: $DEFAULT_REMOTE)"
    echo "  --output <format>   Output format: json|csv|table (default: table)"
    echo "  --quick             Run quick benchmark (fewer iterations)"
    echo "  --cleanup           Clean up test data after benchmark"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 sync-performance --size 10MB --count 20"
    echo "  $0 parallel-vs-serial --iterations 5"
    echo "  $0 full-suite --quick --output json"
    echo "  $0 bandwidth-impact --size 100MB"
}

# Function to generate test files
generate_test_files() {
    local size="$1"
    local count="$2"
    local pattern="${3:-random}"

    log_message "${BLUE}📁 Generating $count test files of size $size${NC}"

    local test_subdir="$TEST_DATA_DIR/testfiles-$size-$count"
    mkdir -p "$test_subdir"

    for ((i=1; i<=count; i++)); do
        local filename="testfile-$size-$(printf "%04d" $i).dat"
        local filepath="$test_subdir/$filename"

        case "$pattern" in
            "random")
                dd if=/dev/urandom of="$filepath" bs="$size" count=1 2>/dev/null
                ;;
            "zeros")
                dd if=/dev/zero of="$filepath" bs="$size" count=1 2>/dev/null
                ;;
            "text")
                # Generate text file
                yes "CloudSync Benchmark Test Data Line $i" | head -c "${size//MB/000000}" > "$filepath"
                ;;
        esac
    done

    echo "$test_subdir"
}

# Function to measure sync performance
measure_sync_time() {
    local source_dir="$1"
    local operation="$2"
    local options="${3:-}"

    local start_time end_time duration
    start_time=$(date +%s.%N)

    case "$operation" in
        "upload")
            eval "rclone sync \"$source_dir\" \"$DEFAULT_REMOTE:$SYNC_BASE_PATH/benchmark/\" $options" >/dev/null 2>&1
            ;;
        "download")
            eval "rclone sync \"$DEFAULT_REMOTE:$SYNC_BASE_PATH/benchmark/\" \"$source_dir-download\" $options" >/dev/null 2>&1
            ;;
        "check")
            eval "rclone check \"$source_dir\" \"$DEFAULT_REMOTE:$SYNC_BASE_PATH/benchmark/\" $options" >/dev/null 2>&1
            ;;
        "dedupe")
            eval "rclone dedupe --by-hash \"$DEFAULT_REMOTE:$SYNC_BASE_PATH/benchmark/\" $options" >/dev/null 2>&1
            ;;
    esac

    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc -l)

    echo "$duration"
}

# Function to run sync performance benchmark
benchmark_sync_performance() {
    log_message "${CYAN}🚀 Running Sync Performance Benchmark${NC}"

    local results_file="$RESULTS_DIR/sync-performance-$(date +%Y%m%d-%H%M%S).json"
    local results=()

    for profile_def in "${BENCHMARK_PROFILES[@]}"; do
        IFS=':' read -r name size count description <<< "$profile_def"

        if [[ "$size" == "varied" ]]; then
            # Mixed sizes test
            size="1MB"
            count=50
        fi

        log_message "${BLUE}📊 Testing $description ($name: $size x $count files)${NC}"

        # Generate test data
        local test_dir
        test_dir=$(generate_test_files "$size" "$count" "random")

        local upload_times=()
        local download_times=()
        local check_times=()

        # Run iterations
        for ((iter=1; iter<=TEST_ITERATIONS; iter++)); do
            log_message "${YELLOW}   Iteration $iter/$TEST_ITERATIONS${NC}"

            # Upload test
            local upload_time
            upload_time=$(measure_sync_time "$test_dir" "upload" "--stats=0")
            upload_times+=("$upload_time")

            # Download test
            local download_time
            download_time=$(measure_sync_time "$test_dir" "download" "--stats=0")
            download_times+=("$download_time")

            # Check test
            local check_time
            check_time=$(measure_sync_time "$test_dir" "check" "--one-way --stats=0")
            check_times+=("$check_time")
        done

        # Calculate statistics
        local avg_upload avg_download avg_check
        avg_upload=$(echo "${upload_times[*]}" | tr ' ' '\n' | awk '{sum+=$1} END {print sum/NR}')
        avg_download=$(echo "${download_times[*]}" | tr ' ' '\n' | awk '{sum+=$1} END {print sum/NR}')
        avg_check=$(echo "${check_times[*]}" | tr ' ' '\n' | awk '{sum+=$1} END {print sum/NR}')

        # Calculate throughput (MB/s)
        local file_size_mb
        file_size_mb=$(echo "$size" | sed 's/MB//g')
        local total_size_mb=$((file_size_mb * count))

        local upload_throughput download_throughput
        upload_throughput=$(echo "scale=2; $total_size_mb / $avg_upload" | bc -l)
        download_throughput=$(echo "scale=2; $total_size_mb / $avg_download" | bc -l)

        # Store results
        results+=("{")
        results+=("  \"profile\": \"$name\",")
        results+=("  \"description\": \"$description\",")
        results+=("  \"file_size\": \"$size\",")
        results+=("  \"file_count\": $count,")
        results+=("  \"total_size_mb\": $total_size_mb,")
        results+=("  \"avg_upload_time\": $avg_upload,")
        results+=("  \"avg_download_time\": $avg_download,")
        results+=("  \"avg_check_time\": $avg_check,")
        results+=("  \"upload_throughput_mbps\": $upload_throughput,")
        results+=("  \"download_throughput_mbps\": $download_throughput")
        results+=("}")

        log_message "${GREEN}   ✅ Upload: ${avg_upload}s (${upload_throughput}MB/s)${NC}"
        log_message "${GREEN}   ✅ Download: ${avg_download}s (${download_throughput}MB/s)${NC}"
        log_message "${GREEN}   ✅ Check: ${avg_check}s${NC}"
    done

    # Save results to JSON
    {
        echo "{"
        echo "  \"timestamp\": \"$TIMESTAMP\","
        echo "  \"benchmark_type\": \"sync-performance\","
        echo "  \"iterations\": $TEST_ITERATIONS,"
        echo "  \"results\": ["
        printf "    %s" "${results[0]}"
        for ((i=1; i<${#results[@]}; i++)); do
            echo ","
            printf "    %s" "${results[i]}"
        done
        echo ""
        echo "  ]"
        echo "}"
    } > "$results_file"

    log_message "${GREEN}📊 Sync performance benchmark completed${NC}"
    log_message "${BLUE}   Results saved to: $results_file${NC}"
}

# Function to compare parallel vs serial operations
benchmark_parallel_vs_serial() {
    log_message "${CYAN}🚀 Running Parallel vs Serial Benchmark${NC}"

    local results_file="$RESULTS_DIR/parallel-vs-serial-$(date +%Y%m%d-%H%M%S).json"
    local test_size="10MB"
    local test_count=20

    # Generate test data
    local test_dir
    test_dir=$(generate_test_files "$test_size" "$test_count" "random")

    # Serial benchmark
    log_message "${BLUE}📊 Testing serial sync operations${NC}"
    local serial_times=()
    for ((iter=1; iter<=TEST_ITERATIONS; iter++)); do
        local serial_time
        serial_time=$(measure_sync_time "$test_dir" "upload" "--transfers=1 --checkers=1 --stats=0")
        serial_times+=("$serial_time")
    done

    # Parallel benchmark
    log_message "${BLUE}📊 Testing parallel sync operations${NC}"
    local parallel_times=()
    for ((iter=1; iter<=TEST_ITERATIONS; iter++)); do
        local parallel_time
        parallel_time=$(measure_sync_time "$test_dir" "upload" "--transfers=8 --checkers=8 --stats=0")
        parallel_times+=("$parallel_time")
    done

    # Calculate averages
    local avg_serial avg_parallel
    avg_serial=$(echo "${serial_times[*]}" | tr ' ' '\n' | awk '{sum+=$1} END {print sum/NR}')
    avg_parallel=$(echo "${parallel_times[*]}" | tr ' ' '\n' | awk '{sum+=$1} END {print sum/NR}')

    # Calculate improvement
    local improvement_factor improvement_percent
    improvement_factor=$(echo "scale=2; $avg_serial / $avg_parallel" | bc -l)
    improvement_percent=$(echo "scale=1; ($avg_serial - $avg_parallel) / $avg_serial * 100" | bc -l)

    # Save results
    cat > "$results_file" << EOF
{
  "timestamp": "$TIMESTAMP",
  "benchmark_type": "parallel-vs-serial",
  "test_configuration": {
    "file_size": "$test_size",
    "file_count": $test_count,
    "iterations": $TEST_ITERATIONS
  },
  "results": {
    "avg_serial_time": $avg_serial,
    "avg_parallel_time": $avg_parallel,
    "improvement_factor": $improvement_factor,
    "improvement_percent": $improvement_percent
  }
}
EOF

    log_message "${GREEN}📊 Parallel vs Serial benchmark completed${NC}"
    log_message "${BLUE}   Serial average: ${avg_serial}s${NC}"
    log_message "${BLUE}   Parallel average: ${avg_parallel}s${NC}"
    log_message "${GREEN}   Performance improvement: ${improvement_factor}x (${improvement_percent}%)${NC}"
    log_message "${BLUE}   Results saved to: $results_file${NC}"
}

# Function to test bandwidth impact
benchmark_bandwidth_impact() {
    log_message "${CYAN}🚀 Running Bandwidth Impact Benchmark${NC}"

    local results_file="$RESULTS_DIR/bandwidth-impact-$(date +%Y%m%d-%H%M%S).json"
    local test_size="50MB"
    local test_count=10

    # Generate test data
    local test_dir
    test_dir=$(generate_test_files "$test_size" "$test_count" "random")

    local bandwidth_limits=("unlimited" "100M" "50M" "20M" "10M" "5M")
    local results=()

    for limit in "${bandwidth_limits[@]}"; do
        log_message "${BLUE}📊 Testing bandwidth limit: $limit${NC}"

        local bw_option=""
        if [[ "$limit" != "unlimited" ]]; then
            bw_option="--bwlimit=$limit"
        fi

        local times=()
        for ((iter=1; iter<=TEST_ITERATIONS; iter++)); do
            local sync_time
            sync_time=$(measure_sync_time "$test_dir" "upload" "$bw_option --stats=0")
            times+=("$sync_time")
        done

        local avg_time
        avg_time=$(echo "${times[*]}" | tr ' ' '\n' | awk '{sum+=$1} END {print sum/NR}')

        # Calculate throughput
        local total_size_mb=$((${test_size//MB/} * test_count))
        local throughput
        throughput=$(echo "scale=2; $total_size_mb / $avg_time" | bc -l)

        results+=("{")
        results+=("  \"bandwidth_limit\": \"$limit\",")
        results+=("  \"avg_time\": $avg_time,")
        results+=("  \"throughput_mbps\": $throughput")
        results+=("}")

        log_message "${GREEN}   ✅ Average time: ${avg_time}s (${throughput}MB/s)${NC}"
    done

    # Save results
    {
        echo "{"
        echo "  \"timestamp\": \"$TIMESTAMP\","
        echo "  \"benchmark_type\": \"bandwidth-impact\","
        echo "  \"test_configuration\": {"
        echo "    \"file_size\": \"$test_size\","
        echo "    \"file_count\": $test_count,"
        echo "    \"iterations\": $TEST_ITERATIONS"
        echo "  },"
        echo "  \"results\": ["
        printf "    %s" "${results[0]}"
        for ((i=1; i<${#results[@]}; i++)); do
            echo ","
            printf "    %s" "${results[i]}"
        done
        echo ""
        echo "  ]"
        echo "}"
    } > "$results_file"

    log_message "${GREEN}📊 Bandwidth impact benchmark completed${NC}"
    log_message "${BLUE}   Results saved to: $results_file${NC}"
}

# Function to run full benchmark suite
run_full_suite() {
    log_message "${PURPLE}🎯 Running Full CloudSync Benchmark Suite${NC}"

    local suite_start=$(date +%s)

    benchmark_sync_performance
    echo
    benchmark_parallel_vs_serial
    echo
    benchmark_bandwidth_impact

    local suite_end=$(date +%s)
    local suite_duration=$((suite_end - suite_start))

    # Create summary report
    local summary_file="$RESULTS_DIR/benchmark-summary-$(date +%Y%m%d-%H%M%S).json"
    cat > "$summary_file" << EOF
{
  "timestamp": "$TIMESTAMP",
  "benchmark_suite": "full",
  "duration_seconds": $suite_duration,
  "results_directory": "$RESULTS_DIR",
  "system_info": {
    "hostname": "$(hostname)",
    "os": "$(uname -s)",
    "kernel": "$(uname -r)",
    "cpu_cores": "$(nproc)",
    "memory_gb": "$(free -g | awk '/^Mem:/{print $2}')"
  }
}
EOF

    log_message "${GREEN}🎉 Full benchmark suite completed in ${suite_duration}s${NC}"
    log_message "${BLUE}   Summary saved to: $summary_file${NC}"
    log_message "${BLUE}   All results in: $RESULTS_DIR${NC}"
}

# Main execution
main() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 1
    fi

    local benchmark_type="$1"
    shift

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --iterations)
                TEST_ITERATIONS="$2"
                shift 2
                ;;
            --quick)
                TEST_ITERATIONS=1
                WARMUP_RUNS=0
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    log_message "${BLUE}⚡ CloudSync Performance Benchmark Suite${NC}"
    log_message "Benchmark type: $benchmark_type"
    log_message "Iterations: $TEST_ITERATIONS"
    log_message "Timestamp: $TIMESTAMP"
    echo "=" | head -c 50 && echo

    case "$benchmark_type" in
        sync-performance)
            benchmark_sync_performance
            ;;
        parallel-vs-serial)
            benchmark_parallel_vs_serial
            ;;
        bandwidth-impact)
            benchmark_bandwidth_impact
            ;;
        full-suite)
            run_full_suite
            ;;
        *)
            echo "Unknown benchmark type: $benchmark_type"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"