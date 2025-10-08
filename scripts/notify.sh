#!/bin/bash
# CloudSync Notification System
# Multi-backend notification support for sync events

set -euo pipefail

# Default configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/config/notifications.conf"

# Source configuration if it exists
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Default values (can be overridden by config)
: "${ENABLE_NOTIFICATIONS:=true}"
: "${ENABLE_NTFY:=false}"
: "${ENABLE_WEBHOOK:=false}"
: "${ENABLE_EMAIL:=false}"
: "${NTFY_URL:=https://ntfy.sh}"
: "${NTFY_TOPIC:=}"
: "${WEBHOOK_URL:=}"
: "${EMAIL_TO:=}"
: "${EMAIL_FROM:=cloudsync@$(hostname)}"
: "${MIN_SEVERITY:=info}"  # info, success, warning, error

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Severity priority mapping
declare -A SEVERITY_PRIORITY=(
    [info]=1
    [success]=2
    [warning]=3
    [error]=4
)

#######################
# Utility Functions
#######################

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

get_emoji() {
    local severity="$1"
    case "$severity" in
        info) echo "ℹ️" ;;
        success) echo "✅" ;;
        warning) echo "⚠️" ;;
        error) echo "❌" ;;
        *) echo "📢" ;;
    esac
}

should_notify() {
    local severity="$1"
    local msg_priority="${SEVERITY_PRIORITY[$severity]:-1}"
    local min_priority="${SEVERITY_PRIORITY[$MIN_SEVERITY]:-1}"

    [[ $msg_priority -ge $min_priority ]]
}

#######################
# Backend Functions
#######################

send_ntfy() {
    local title="$1"
    local message="$2"
    local severity="$3"
    local emoji
    emoji="$(get_emoji "$severity")"

    if [[ "$ENABLE_NTFY" != "true" ]] || [[ -z "$NTFY_TOPIC" ]]; then
        return 0
    fi

    log "Sending ntfy notification to ${NTFY_URL}/${NTFY_TOPIC}"

    # Map severity to ntfy priority
    local priority="default"
    case "$severity" in
        error) priority="urgent" ;;
        warning) priority="high" ;;
        success) priority="default" ;;
        info) priority="low" ;;
    esac

    # Send notification
    curl -f -s -S \
        -H "Title: ${emoji} ${title}" \
        -H "Priority: ${priority}" \
        -H "Tags: ${severity}" \
        -d "${message}" \
        "${NTFY_URL}/${NTFY_TOPIC}" 2>&1 | log

    return "${PIPESTATUS[0]}"
}

send_webhook() {
    local title="$1"
    local message="$2"
    local severity="$3"
    local emoji
    emoji="$(get_emoji "$severity")"

    if [[ "$ENABLE_WEBHOOK" != "true" ]] || [[ -z "$WEBHOOK_URL" ]]; then
        return 0
    fi

    log "Sending webhook notification to ${WEBHOOK_URL}"

    # Prepare JSON payload
    local payload
    payload=$(cat <<EOF
{
    "title": "${emoji} ${title}",
    "message": "${message}",
    "severity": "${severity}",
    "hostname": "$(hostname)",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

    # Send webhook
    curl -f -s -S \
        -H "Content-Type: application/json" \
        -X POST \
        -d "${payload}" \
        "${WEBHOOK_URL}" 2>&1 | log

    return "${PIPESTATUS[0]}"
}

send_email() {
    local title="$1"
    local message="$2"
    local severity="$3"
    local emoji
    emoji="$(get_emoji "$severity")"

    if [[ "$ENABLE_EMAIL" != "true" ]] || [[ -z "$EMAIL_TO" ]]; then
        return 0
    fi

    # Check if mail command is available
    if ! command -v mail &> /dev/null; then
        log "mail command not found, skipping email notification"
        return 1
    fi

    log "Sending email notification to ${EMAIL_TO}"

    # Prepare email body
    local email_body
    email_body=$(cat <<EOF
CloudSync Notification
======================
Severity: ${severity}
Hostname: $(hostname)
Time: $(date)

${message}

---
This is an automated notification from CloudSync.
EOF
)

    # Send email
    echo "$email_body" | mail -s "${emoji} CloudSync: ${title}" -r "$EMAIL_FROM" "$EMAIL_TO"
}

#######################
# Main Notification Function
#######################

notify() {
    local severity="${1:-info}"
    local title="${2:-CloudSync Notification}"
    local message="${3:-}"

    # Check if notifications are enabled
    if [[ "$ENABLE_NOTIFICATIONS" != "true" ]]; then
        log "Notifications disabled, skipping"
        return 0
    fi

    # Check severity threshold
    if ! should_notify "$severity"; then
        log "Severity '$severity' below threshold '$MIN_SEVERITY', skipping"
        return 0
    fi

    # Terminal output with colors
    local color="$NC"
    case "$severity" in
        error) color="$RED" ;;
        warning) color="$YELLOW" ;;
        success) color="$GREEN" ;;
        info) color="$BLUE" ;;
    esac

    echo -e "${color}$(get_emoji "$severity") ${title}${NC}"
    if [[ -n "$message" ]]; then
        echo -e "${color}${message}${NC}"
    fi

    # Send to all enabled backends
    local failed_backends=()

    if [[ "$ENABLE_NTFY" == "true" ]]; then
        if ! send_ntfy "$title" "$message" "$severity"; then
            failed_backends+=("ntfy")
        fi
    fi

    if [[ "$ENABLE_WEBHOOK" == "true" ]]; then
        if ! send_webhook "$title" "$message" "$severity"; then
            failed_backends+=("webhook")
        fi
    fi

    if [[ "$ENABLE_EMAIL" == "true" ]]; then
        if ! send_email "$title" "$message" "$severity"; then
            failed_backends+=("email")
        fi
    fi

    # Report failures
    if [[ ${#failed_backends[@]} -gt 0 ]]; then
        log "Warning: Failed to send notifications to: ${failed_backends[*]}"
        return 1
    fi

    return 0
}

#######################
# CLI Interface
#######################

show_usage() {
    cat <<EOF
Usage: $(basename "$0") [SEVERITY] [TITLE] [MESSAGE]

Send notifications through configured backends (ntfy.sh, webhooks, email).

SEVERITY:
    info        Informational message (default)
    success     Successful operation
    warning     Warning condition
    error       Error condition

EXAMPLES:
    $(basename "$0") success "Sync Complete" "All 51 repositories synced successfully"
    $(basename "$0") error "Sync Failed" "Bundle creation failed for repo XYZ"
    $(basename "$0") warning "Large Repo" "Repository size exceeds 500MB"

CONFIGURATION:
    Edit ${CONFIG_FILE} to configure notification backends.

EOF
}

# Main entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        show_usage
        exit 0
    fi

    severity="${1:-info}"
    title="${2:-CloudSync Notification}"
    message="${3:-}"

    # Validate severity
    if [[ ! "${SEVERITY_PRIORITY[$severity]+exists}" ]]; then
        echo "Error: Invalid severity '$severity'" >&2
        echo "Valid values: info, success, warning, error" >&2
        exit 1
    fi

    notify "$severity" "$title" "$message"
fi
