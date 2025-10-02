#!/bin/bash
# CloudSync Bandwidth Management and Throttling System
# Provides intelligent bandwidth control and network optimization

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
NC='\033[0m'

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE="$HOME/.cloudsync/bandwidth-manager.log"
CONFIG_DIR="$HOME/.cloudsync/bandwidth"
PROFILES_DIR="$CONFIG_DIR/profiles"

# Default bandwidth profiles
DEFAULT_PROFILES=(
    "conservative:5M:1:2:Low usage profile for background sync"
    "balanced:20M:4:4:Balanced profile for normal operations"
    "aggressive:100M:8:8:High-speed profile for bulk transfers"
    "unlimited:0:16:16:Maximum performance profile"
    "mobile:2M:1:1:Mobile/metered connection profile"
)

# Network monitoring settings
MONITOR_INTERFACE="auto"
USAGE_THRESHOLD_HIGH=80  # Percentage
USAGE_THRESHOLD_LOW=30   # Percentage
ADAPTATION_ENABLED=true

# Create directories
mkdir -p "$HOME/.cloudsync"
mkdir -p "$CONFIG_DIR"
mkdir -p "$PROFILES_DIR"

# Function to log messages
log_message() {
    echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
    echo -e "$1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo ""
    echo "Commands:"
    echo "  profiles            List available bandwidth profiles"
    echo "  create-profile      Create a new bandwidth profile"
    echo "  apply-profile       Apply a bandwidth profile"
    echo "  monitor             Monitor network usage and adapt"
    echo "  optimize            Auto-optimize bandwidth settings"
    echo "  test-speed          Test current network speed"
    echo "  reset               Reset to default settings"
    echo ""
    echo "Options:"
    echo "  --profile <name>    Bandwidth profile name"
    echo "  --limit <speed>     Bandwidth limit (e.g., 10M, 1G, 0 for unlimited)"
    echo "  --transfers <num>   Number of parallel transfers"
    echo "  --checkers <num>    Number of checker threads"
    echo "  --description <txt> Profile description"
    echo "  --interface <if>    Network interface to monitor (default: auto)"
    echo "  --threshold <pct>   Usage threshold for adaptation (default: 80%)"
    echo "  --adaptive          Enable adaptive bandwidth management"
    echo "  --duration <sec>    Test duration for speed test (default: 30)"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 profiles"
    echo "  $0 create-profile --profile work --limit 50M --transfers 4"
    echo "  $0 apply-profile --profile balanced"
    echo "  $0 monitor --adaptive --threshold 75"
    echo "  $0 test-speed --duration 60"
}

# Function to detect active network interface
detect_interface() {
    # Find default route interface
    local interface
    interface=$(ip route show default | awk '/default/ { print $5 }' | head -n1)

    if [[ -z "$interface" ]]; then
        # Fallback: find interface with highest traffic
        interface=$(cat /proc/net/dev | awk -F: '/eth|wlan|en/ { print $1 }' | awk '{ print $1 }' | head -n1)
    fi

    echo "${interface:-eth0}"
}

# Function to get network usage
get_network_usage() {
    local interface="$1"

    if [[ "$interface" == "auto" ]]; then
        interface=$(detect_interface)
    fi

    if [[ ! -f "/sys/class/net/$interface/statistics/rx_bytes" ]]; then
        log_message "${RED}❌ Interface $interface not found${NC}"
        return 1
    fi

    local rx_bytes tx_bytes
    rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes")
    tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes")

    echo "$rx_bytes $tx_bytes"
}

# Function to calculate bandwidth usage
calculate_bandwidth_usage() {
    local interface="$1"
    local duration="${2:-5}"  # seconds

    local before after
    before=$(get_network_usage "$interface")
    sleep "$duration"
    after=$(get_network_usage "$interface")

    local rx_before tx_before rx_after tx_after
    read -r rx_before tx_before <<< "$before"
    read -r rx_after tx_after <<< "$after"

    local rx_rate tx_rate total_rate
    rx_rate=$(( (rx_after - rx_before) / duration ))
    tx_rate=$(( (tx_after - tx_before) / duration ))
    total_rate=$((rx_rate + tx_rate))

    # Convert to human readable format
    local rx_mbps tx_mbps total_mbps
    rx_mbps=$(echo "scale=2; $rx_rate / 1024 / 1024 * 8" | bc -l 2>/dev/null || echo "0")
    tx_mbps=$(echo "scale=2; $tx_rate / 1024 / 1024 * 8" | bc -l 2>/dev/null || echo "0")
    total_mbps=$(echo "scale=2; $total_rate / 1024 / 1024 * 8" | bc -l 2>/dev/null || echo "0")

    echo "$rx_mbps $tx_mbps $total_mbps"
}

# Function to initialize default profiles
init_profiles() {
    log_message "${BLUE}📋 Initializing default bandwidth profiles${NC}"

    for profile_def in "${DEFAULT_PROFILES[@]}"; do
        IFS=':' read -r name limit transfers checkers description <<< "$profile_def"

        local profile_file="$PROFILES_DIR/$name.conf"
        if [[ ! -f "$profile_file" ]]; then
            cat > "$profile_file" << EOF
# CloudSync Bandwidth Profile: $name
BANDWIDTH_LIMIT="$limit"
TRANSFER_THREADS="$transfers"
CHECKER_THREADS="$checkers"
DESCRIPTION="$description"
CREATED="$(date '+%Y-%m-%d %H:%M:%S')"
EOF
            log_message "${GREEN}✅ Created profile: $name${NC}"
        fi
    done
}

# Function to list bandwidth profiles
list_profiles() {
    log_message "${CYAN}📊 Available Bandwidth Profiles${NC}"
    echo

    if [[ ! -d "$PROFILES_DIR" ]] || [[ -z "$(ls -A "$PROFILES_DIR")" ]]; then
        log_message "${YELLOW}⚠️ No profiles found. Initializing defaults...${NC}"
        init_profiles
    fi

    printf "%-15s %-10s %-9s %-9s %s\n" "Profile" "Limit" "Transfers" "Checkers" "Description"
    printf "%-15s %-10s %-9s %-9s %s\n" "-------" "-----" "---------" "--------" "-----------"

    for profile_file in "$PROFILES_DIR"/*.conf; do
        if [[ -f "$profile_file" ]]; then
            local name
            name=$(basename "$profile_file" .conf)

            # Source profile to get values
            local BANDWIDTH_LIMIT TRANSFER_THREADS CHECKER_THREADS DESCRIPTION
            source "$profile_file"

            local limit_display="${BANDWIDTH_LIMIT:-0}"
            if [[ "$limit_display" == "0" ]]; then
                limit_display="unlimited"
            fi

            printf "%-15s %-10s %-9s %-9s %s\n" \
                "$name" \
                "$limit_display" \
                "${TRANSFER_THREADS:-4}" \
                "${CHECKER_THREADS:-8}" \
                "${DESCRIPTION:-No description}"
        fi
    done
}

# Function to create a new bandwidth profile
create_profile() {
    local profile_name="$1"
    local bandwidth_limit="$2"
    local transfer_threads="$3"
    local checker_threads="$4"
    local description="$5"

    if [[ -z "$profile_name" ]]; then
        log_message "${RED}❌ Profile name is required${NC}"
        return 1
    fi

    local profile_file="$PROFILES_DIR/$profile_name.conf"

    cat > "$profile_file" << EOF
# CloudSync Bandwidth Profile: $profile_name
BANDWIDTH_LIMIT="${bandwidth_limit:-20M}"
TRANSFER_THREADS="${transfer_threads:-4}"
CHECKER_THREADS="${checker_threads:-8}"
DESCRIPTION="${description:-Custom profile}"
CREATED="$(date '+%Y-%m-%d %H:%M:%S')"
EOF

    log_message "${GREEN}✅ Created bandwidth profile: $profile_name${NC}"
    log_message "${BLUE}   File: $profile_file${NC}"
}

# Function to apply a bandwidth profile
apply_profile() {
    local profile_name="$1"
    local profile_file="$PROFILES_DIR/$profile_name.conf"

    if [[ ! -f "$profile_file" ]]; then
        log_message "${RED}❌ Profile not found: $profile_name${NC}"
        log_message "${BLUE}💡 Available profiles:${NC}"
        list_profiles
        return 1
    fi

    # Source profile
    local BANDWIDTH_LIMIT TRANSFER_THREADS CHECKER_THREADS DESCRIPTION
    source "$profile_file"

    # Create current profile symlink
    ln -sf "$profile_file" "$CONFIG_DIR/current.conf"

    # Save to active configuration
    cat > "$CONFIG_DIR/active.conf" << EOF
# Active CloudSync Bandwidth Configuration
# Applied from profile: $profile_name
# Applied at: $(date '+%Y-%m-%d %H:%M:%S')

ACTIVE_PROFILE="$profile_name"
BANDWIDTH_LIMIT="$BANDWIDTH_LIMIT"
TRANSFER_THREADS="$TRANSFER_THREADS"
CHECKER_THREADS="$CHECKER_THREADS"
DESCRIPTION="$DESCRIPTION"
EOF

    log_message "${GREEN}✅ Applied bandwidth profile: $profile_name${NC}"
    log_message "${BLUE}   Bandwidth limit: ${BANDWIDTH_LIMIT}${NC}"
    log_message "${BLUE}   Transfer threads: ${TRANSFER_THREADS}${NC}"
    log_message "${BLUE}   Checker threads: ${CHECKER_THREADS}${NC}"
    log_message "${BLUE}   Description: ${DESCRIPTION}${NC}"
}

# Function to test network speed
test_speed() {
    local duration="${1:-30}"
    local interface
    interface=$(detect_interface)

    log_message "${CYAN}🚀 Testing network speed for ${duration}s on interface $interface${NC}"

    # Test download speed using rclone to a known remote
    local speed_test_output
    if command -v rclone >/dev/null 2>&1; then
        log_message "${BLUE}📡 Running rclone speed test...${NC}"

        # Use size-only check as a speed test
        speed_test_output=$(timeout "$duration" rclone check \
            "$HOME" "$DEFAULT_REMOTE:$SYNC_BASE_PATH" \
            --size-only --one-way --stats=5s 2>&1 | tail -n 5)

        log_message "${GREEN}✅ Speed test completed${NC}"
        echo "$speed_test_output"
    else
        log_message "${YELLOW}⚠️ rclone not available, using network monitoring${NC}"
        calculate_bandwidth_usage "$interface" "$duration"
    fi
}

# Function to monitor network usage and adapt
monitor_network() {
    local interface="${1:-auto}"
    local threshold="${2:-80}"
    local adaptive="${3:-false}"

    if [[ "$interface" == "auto" ]]; then
        interface=$(detect_interface)
    fi

    log_message "${CYAN}👁️ Monitoring network usage on $interface (threshold: ${threshold}%)${NC}"

    while true; do
        local usage_stats
        usage_stats=$(calculate_bandwidth_usage "$interface" 5)
        read -r rx_mbps tx_mbps total_mbps <<< "$usage_stats"

        log_message "${BLUE}📊 Current usage: RX=${rx_mbps}Mbps TX=${tx_mbps}Mbps Total=${total_mbps}Mbps${NC}"

        if [[ "$adaptive" == "true" ]]; then
            # Adaptive bandwidth management logic
            local current_usage_pct
            current_usage_pct=$(echo "scale=0; $total_mbps * 100 / 100" | bc -l 2>/dev/null || echo "0")

            if (( $(echo "$current_usage_pct > $threshold" | bc -l) )); then
                log_message "${YELLOW}⚠️ High network usage detected (${current_usage_pct}%), applying conservative profile${NC}"
                apply_profile "conservative"
            elif (( $(echo "$current_usage_pct < 30" | bc -l) )); then
                log_message "${GREEN}✅ Low network usage detected (${current_usage_pct}%), applying balanced profile${NC}"
                apply_profile "balanced"
            fi
        fi

        sleep 60  # Monitor every minute
    done
}

# Function to optimize bandwidth settings
optimize_bandwidth() {
    log_message "${CYAN}🔧 Auto-optimizing bandwidth settings${NC}"

    # Test current speed
    local interface
    interface=$(detect_interface)

    log_message "${BLUE}📊 Analyzing network performance...${NC}"
    local usage_stats
    usage_stats=$(calculate_bandwidth_usage "$interface" 10)
    read -r rx_mbps tx_mbps total_mbps <<< "$usage_stats"

    # Determine optimal profile based on speed
    local optimal_profile
    if (( $(echo "$total_mbps > 50" | bc -l) )); then
        optimal_profile="aggressive"
    elif (( $(echo "$total_mbps > 10" | bc -l) )); then
        optimal_profile="balanced"
    else
        optimal_profile="conservative"
    fi

    log_message "${GREEN}🎯 Recommended profile: $optimal_profile (based on ${total_mbps}Mbps)${NC}"
    apply_profile "$optimal_profile"
}

# Function to reset bandwidth settings
reset_settings() {
    log_message "${YELLOW}🔄 Resetting bandwidth settings to defaults${NC}"

    rm -f "$CONFIG_DIR/current.conf"
    rm -f "$CONFIG_DIR/active.conf"

    apply_profile "balanced"

    log_message "${GREEN}✅ Bandwidth settings reset to defaults${NC}"
}

# Main execution
main() {
    local command="$1"
    shift

    # Parse remaining arguments
    local profile_name=""
    local bandwidth_limit=""
    local transfer_threads=""
    local checker_threads=""
    local description=""
    local interface="$MONITOR_INTERFACE"
    local threshold="$USAGE_THRESHOLD_HIGH"
    local adaptive=false
    local duration=30

    while [[ $# -gt 0 ]]; do
        case $1 in
            --profile)
                profile_name="$2"
                shift 2
                ;;
            --limit)
                bandwidth_limit="$2"
                shift 2
                ;;
            --transfers)
                transfer_threads="$2"
                shift 2
                ;;
            --checkers)
                checker_threads="$2"
                shift 2
                ;;
            --description)
                description="$2"
                shift 2
                ;;
            --interface)
                interface="$2"
                shift 2
                ;;
            --threshold)
                threshold="$2"
                shift 2
                ;;
            --adaptive)
                adaptive=true
                shift
                ;;
            --duration)
                duration="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    log_message "${BLUE}⚡ CloudSync Bandwidth Manager${NC}"
    log_message "Command: $command"
    log_message "Timestamp: $TIMESTAMP"
    echo "=" | head -c 50 && echo

    case "$command" in
        profiles)
            list_profiles
            ;;
        create-profile)
            create_profile "$profile_name" "$bandwidth_limit" "$transfer_threads" "$checker_threads" "$description"
            ;;
        apply-profile)
            apply_profile "$profile_name"
            ;;
        monitor)
            monitor_network "$interface" "$threshold" "$adaptive"
            ;;
        optimize)
            optimize_bandwidth
            ;;
        test-speed)
            test_speed "$duration"
            ;;
        reset)
            reset_settings
            ;;
        *)
            echo "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Check for command
if [[ $# -eq 0 ]]; then
    show_usage
    exit 1
fi

# Run main function
main "$@"