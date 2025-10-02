#!/bin/bash
# CloudSync Test Utilities
# Common functions and utilities for CloudSync testing

# Color codes for test output
TEST_RED='\033[0;31m'
TEST_GREEN='\033[0;32m'
TEST_YELLOW='\033[1;33m'
TEST_BLUE='\033[0;34m'
TEST_CYAN='\033[0;36m'
TEST_NC='\033[0m'

# Test logging functions
log_test_info() {
    local message="$1"
    echo -e "${TEST_BLUE}[INFO]${TEST_NC} $message"
}

log_test_success() {
    local message="$1"
    echo -e "${TEST_GREEN}[SUCCESS]${TEST_NC} $message"
}

log_test_error() {
    local message="$1"
    echo -e "${TEST_RED}[ERROR]${TEST_NC} $message" >&2
}

log_test_warn() {
    local message="$1"
    echo -e "${TEST_YELLOW}[WARN]${TEST_NC} $message"
}

log_test_debug() {
    local message="$1"
    if [[ "${TEST_DEBUG:-false}" == "true" ]]; then
        echo -e "${TEST_CYAN}[DEBUG]${TEST_NC} $message"
    fi
}

# Test assertion utilities
assert_file_exists() {
    local filepath="$1"
    local message="${2:-File does not exist: $filepath}"

    if [[ -f "$filepath" ]]; then
        log_test_debug "File exists: $filepath"
        return 0
    else
        log_test_error "$message"
        return 1
    fi
}

assert_dir_exists() {
    local dirpath="$1"
    local message="${2:-Directory does not exist: $dirpath}"

    if [[ -d "$dirpath" ]]; then
        log_test_debug "Directory exists: $dirpath"
        return 0
    else
        log_test_error "$message"
        return 1
    fi
}

assert_command_exists() {
    local command="$1"
    local message="${2:-Command not found: $command}"

    if command -v "$command" >/dev/null 2>&1; then
        log_test_debug "Command exists: $command"
        return 0
    else
        log_test_error "$message"
        return 1
    fi
}

assert_command_success() {
    local command="$1"
    local message="${2:-Command failed: $command}"

    log_test_debug "Running command: $command"

    if eval "$command" >/dev/null 2>&1; then
        log_test_debug "Command succeeded: $command"
        return 0
    else
        log_test_error "$message"
        return 1
    fi
}

assert_command_fails() {
    local command="$1"
    local message="${2:-Command unexpectedly succeeded: $command}"

    log_test_debug "Running command (expecting failure): $command"

    if eval "$command" >/dev/null 2>&1; then
        log_test_error "$message"
        return 1
    else
        log_test_debug "Command failed as expected: $command"
        return 0
    fi
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Expected '$expected', got '$actual'}"

    if [[ "$expected" == "$actual" ]]; then
        log_test_debug "Values equal: '$expected' == '$actual'"
        return 0
    else
        log_test_error "$message"
        return 1
    fi
}

assert_not_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should not be equal: '$expected' == '$actual'}"

    if [[ "$expected" != "$actual" ]]; then
        log_test_debug "Values not equal: '$expected' != '$actual'"
        return 0
    else
        log_test_error "$message"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String '$haystack' does not contain '$needle'}"

    if [[ "$haystack" == *"$needle"* ]]; then
        log_test_debug "String contains substring: '$haystack' contains '$needle'"
        return 0
    else
        log_test_error "$message"
        return 1
    fi
}

assert_greater_than() {
    local actual="$1"
    local threshold="$2"
    local message="${3:-Value $actual is not greater than $threshold}"

    if (( $(echo "$actual > $threshold" | bc -l) )); then
        log_test_debug "Value is greater: $actual > $threshold"
        return 0
    else
        log_test_error "$message"
        return 1
    fi
}

assert_less_than() {
    local actual="$1"
    local threshold="$2"
    local message="${3:-Value $actual is not less than $threshold}"

    if (( $(echo "$actual < $threshold" | bc -l) )); then
        log_test_debug "Value is less: $actual < $threshold"
        return 0
    else
        log_test_error "$message"
        return 1
    fi
}

# File content utilities
create_test_file() {
    local filepath="$1"
    local content="${2:-Test file content}"
    local size="${3:-}"

    mkdir -p "$(dirname "$filepath")"

    if [[ -n "$size" ]]; then
        # Create file of specific size
        dd if=/dev/zero of="$filepath" bs="$size" count=1 2>/dev/null
    else
        # Create file with content
        echo "$content" > "$filepath"
    fi

    log_test_debug "Created test file: $filepath"
}

create_test_structure() {
    local base_dir="$1"

    mkdir -p "$base_dir"/{docs,scripts,config,data}

    # Create various file types
    echo "# Test Documentation" > "$base_dir/docs/README.md"
    echo "Configuration file" > "$base_dir/config/test.conf"
    echo '#!/bin/bash\necho "test"' > "$base_dir/scripts/test.sh"
    chmod +x "$base_dir/scripts/test.sh"

    # Create binary test data
    dd if=/dev/urandom of="$base_dir/data/binary.dat" bs=1024 count=5 2>/dev/null

    log_test_debug "Created test directory structure: $base_dir"
}

# Time measurement utilities
start_timer() {
    TEST_START_TIME=$(date +%s.%N)
}

stop_timer() {
    local end_time
    end_time=$(date +%s.%N)
    echo "$(echo "$end_time - $TEST_START_TIME" | bc -l)"
}

# Test data generation
generate_random_file() {
    local filepath="$1"
    local size_mb="${2:-1}"

    mkdir -p "$(dirname "$filepath")"
    dd if=/dev/urandom of="$filepath" bs=1M count="$size_mb" 2>/dev/null

    log_test_debug "Generated random file: $filepath (${size_mb}MB)"
}

generate_text_file() {
    local filepath="$1"
    local lines="${2:-100}"

    mkdir -p "$(dirname "$filepath")"

    for ((i=1; i<=lines; i++)); do
        echo "This is line $i of the test file - $(date)" >> "$filepath"
    done

    log_test_debug "Generated text file: $filepath ($lines lines)"
}

# Configuration utilities
load_test_config() {
    local config_file="${1:-$PROJECT_ROOT/config/cloudsync.conf}"

    if [[ -f "$config_file" ]]; then
        source "$config_file"
        log_test_debug "Loaded test configuration: $config_file"
        return 0
    else
        log_test_error "Test configuration not found: $config_file"
        return 1
    fi
}

create_test_config() {
    local config_file="$1"

    cat > "$config_file" << 'EOF'
# Test Configuration
DEFAULT_REMOTE="test-remote"
SYNC_BASE_PATH="test-sync"
ENABLE_CHECKSUMS=true
ENABLE_PROGRESS=false
CONFLICT_RESOLUTION="ask"
EOF

    log_test_debug "Created test configuration: $config_file"
}

# Process utilities
wait_for_process() {
    local pid="$1"
    local timeout="${2:-30}"
    local count=0

    while kill -0 "$pid" 2>/dev/null && [[ $count -lt $timeout ]]; do
        sleep 1
        ((count++))
    done

    if kill -0 "$pid" 2>/dev/null; then
        log_test_error "Process $pid did not exit within ${timeout}s"
        return 1
    else
        log_test_debug "Process $pid exited within ${count}s"
        return 0
    fi
}

# Cleanup utilities
cleanup_test_files() {
    local pattern="$1"

    if [[ -n "$pattern" ]]; then
        find /tmp -name "$pattern" -type f -delete 2>/dev/null || true
        log_test_debug "Cleaned up test files matching: $pattern"
    fi
}

cleanup_test_dirs() {
    local pattern="$1"

    if [[ -n "$pattern" ]]; then
        find /tmp -name "$pattern" -type d -exec rm -rf {} + 2>/dev/null || true
        log_test_debug "Cleaned up test directories matching: $pattern"
    fi
}

# Mock utilities for testing
mock_command() {
    local command="$1"
    local mock_script="$2"
    local mock_dir="/tmp/mock-commands-$$"

    mkdir -p "$mock_dir"
    echo "$mock_script" > "$mock_dir/$command"
    chmod +x "$mock_dir/$command"

    # Add to PATH
    export PATH="$mock_dir:$PATH"

    log_test_debug "Mocked command: $command"
}

unmock_commands() {
    local mock_dir="/tmp/mock-commands-$$"

    if [[ -d "$mock_dir" ]]; then
        # Remove from PATH
        export PATH="${PATH//$mock_dir:/}"
        export PATH="${PATH//:$mock_dir/}"
        export PATH="${PATH//$mock_dir/}"

        rm -rf "$mock_dir"
        log_test_debug "Removed command mocks"
    fi
}

# Performance testing utilities
measure_execution_time() {
    local command="$1"
    local iterations="${2:-1}"
    local total_time=0

    for ((i=1; i<=iterations; i++)); do
        start_timer
        eval "$command" >/dev/null 2>&1
        local execution_time
        execution_time=$(stop_timer)
        total_time=$(echo "$total_time + $execution_time" | bc -l)
    done

    local average_time
    average_time=$(echo "scale=3; $total_time / $iterations" | bc -l)
    echo "$average_time"
}

# Test environment validation
validate_test_environment() {
    local required_commands=("rclone" "jq" "bc" "timeout")
    local missing_commands=()

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_test_error "Missing required commands: ${missing_commands[*]}"
        return 1
    fi

    log_test_debug "Test environment validation passed"
    return 0
}

# Test result reporting
create_test_result() {
    local test_name="$1"
    local result="$2"
    local duration="${3:-0}"
    local details="${4:-}"

    local timestamp
    timestamp=$(date -Iseconds)

    cat << EOF
{
  "test": "$test_name",
  "result": "$result",
  "timestamp": "$timestamp",
  "duration": $duration,
  "details": "$details"
}
EOF
}

# Initialize test environment
init_test_environment() {
    # Set test-specific environment variables
    export TEST_MODE=true
    export TEST_DEBUG="${TEST_DEBUG:-false}"

    # Create test directories
    mkdir -p "$HOME/.cloudsync-test"

    # Validate environment
    validate_test_environment

    log_test_info "Test environment initialized"
}