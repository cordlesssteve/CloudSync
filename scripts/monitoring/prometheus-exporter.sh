#!/bin/bash
# CloudSync Prometheus Metrics Exporter
# Exports CloudSync backup and synchronization metrics to Prometheus

set -euo pipefail

CLOUDSYNC_PROJECT="${CLOUDSYNC_PROJECT:-$HOME/projects/Utility/LOGISTICAL/CloudSync}"
METRICS_FILE="/var/lib/prometheus/node-exporter/cloudsync.prom"
TEMP_FILE=$(mktemp)

# Track which metrics have had HELP/TYPE written
declare -A METRICS_SEEN

# Helper: Add metric with proper Prometheus format
add_metric() {
    local help="$1"
    local type="$2"
    local name="$3"
    local value="$4"
    local labels="${5:-}"

    # Only write HELP and TYPE once per metric name
    if [[ -z "${METRICS_SEEN[$name]:-}" ]]; then
        echo "# HELP $name $help" >> "$TEMP_FILE"
        echo "# TYPE $name $type" >> "$TEMP_FILE"
        METRICS_SEEN[$name]=1
    fi

    # Always write the metric value
    if [[ -n "$labels" ]]; then
        echo "${name}{${labels}} ${value}" >> "$TEMP_FILE"
    else
        echo "${name} ${value}" >> "$TEMP_FILE"
    fi
}

# ==========================================
# GIT BUNDLE METRICS
# ==========================================

collect_bundle_metrics() {
    local bundle_dir="$HOME/.cloudsync/bundles"

    if [[ ! -d "$bundle_dir" ]]; then
        add_metric "Git bundles tracked" "gauge" "cloudsync_bundle_total" "0" "type=\"full\""
        add_metric "Git bundles tracked" "gauge" "cloudsync_bundle_total" "0" "type=\"incremental\""
        add_metric "CloudSync bundle health" "gauge" "cloudsync_health_status" "0" "component=\"bundles\""
        return
    fi

    # Count bundles by type
    local full_count=$(find "$bundle_dir" -name "*-full.bundle" 2>/dev/null | wc -l)
    local incremental_count=$(find "$bundle_dir" -name "*-incremental-*.bundle" 2>/dev/null | wc -l)

    add_metric "Git bundles tracked" "gauge" "cloudsync_bundle_total" "$full_count" "type=\"full\""
    add_metric "Git bundles tracked" "gauge" "cloudsync_bundle_total" "$incremental_count" "type=\"incremental\""
    echo "" >> "$TEMP_FILE"

    # Bundle health (1 if any bundles exist)
    if [[ $((full_count + incremental_count)) -gt 0 ]]; then
        add_metric "CloudSync component health status" "gauge" "cloudsync_health_status" "1" "component=\"bundles\""
    else
        add_metric "CloudSync component health status" "gauge" "cloudsync_health_status" "0" "component=\"bundles\""
    fi

    # Last sync timestamp (from CloudSync logs)
    if [[ -f "$HOME/.cloudsync/logs/bundle-sync.log" ]]; then
        local last_sync=$(stat -c%Y "$HOME/.cloudsync/logs/bundle-sync.log" 2>/dev/null || echo "0")
        add_metric "Last bundle sync timestamp (Unix)" "gauge" "cloudsync_bundle_last_sync_timestamp" "$last_sync"
        echo "" >> "$TEMP_FILE"
    fi
}

# ==========================================
# RESTIC METRICS
# ==========================================

collect_restic_metrics() {
    local restic_repo="/mnt/d/wsl_backups/restic_repo"

    if [[ ! -d "$restic_repo" ]]; then
        add_metric "CloudSync component health status" "gauge" "cloudsync_health_status" "0" "component=\"restic\""
        echo "" >> "$TEMP_FILE"
        return
    fi

    # Restic stats (requires RESTIC_PASSWORD env var)
    if [[ -n "${RESTIC_PASSWORD:-}" ]]; then
        local snapshot_count=$(restic -r "$restic_repo" snapshots --json 2>/dev/null | jq '. | length' || echo "0")
        local repo_size=$(du -sb "$restic_repo" 2>/dev/null | awk '{print $1}' || echo "0")

        add_metric "Total Restic snapshots" "gauge" "cloudsync_restic_snapshots_total" "$snapshot_count"
        add_metric "Restic repository size (bytes)" "gauge" "cloudsync_restic_repository_size_bytes" "$repo_size"

        # Last backup timestamp
        if [[ -f "$HOME/.backup_logs/restic_weekly.log" ]]; then
            local last_backup=$(stat -c%Y "$HOME/.backup_logs/restic_weekly.log" 2>/dev/null || echo "0")
            add_metric "Last Restic backup timestamp (Unix)" "gauge" "cloudsync_restic_last_backup_timestamp" "$last_backup"
        fi
        echo "" >> "$TEMP_FILE"

        add_metric "CloudSync component health status" "gauge" "cloudsync_health_status" "1" "component=\"restic\""
    else
        add_metric "CloudSync component health status" "gauge" "cloudsync_health_status" "0" "component=\"restic\""
    fi
    echo "" >> "$TEMP_FILE"
}

# ==========================================
# ONEDRIVE SYNC METRICS
# ==========================================

collect_sync_metrics() {
    # Check rclone availability
    if ! command -v rclone &> /dev/null; then
        add_metric "CloudSync component health status" "gauge" "cloudsync_health_status" "0" "component=\"rclone\""
        echo "" >> "$TEMP_FILE"
        return
    fi

    # OneDrive storage usage (requires rclone config)
    if rclone about onedrive: --json &> /dev/null 2>&1; then
        local used_bytes=$(rclone about onedrive: --json 2>/dev/null | jq -r '.used // 0')
        add_metric "OneDrive storage used (bytes)" "gauge" "cloudsync_storage_onedrive_used_bytes" "$used_bytes"
        echo "" >> "$TEMP_FILE"
        add_metric "CloudSync component health status" "gauge" "cloudsync_health_status" "1" "component=\"rclone\""
    else
        add_metric "CloudSync component health status" "gauge" "cloudsync_health_status" "0" "component=\"rclone\""
    fi

    # Local managed directory size
    local managed_dir="$HOME/cloudsync-managed"
    if [[ -d "$managed_dir" ]]; then
        local local_size=$(du -sb "$managed_dir" 2>/dev/null | awk '{print $1}' || echo "0")
        add_metric "Local managed directory size (bytes)" "gauge" "cloudsync_storage_local_managed_bytes" "$local_size"
        echo "" >> "$TEMP_FILE"
    fi
}

# ==========================================
# HEALTH CHECK TIMESTAMP
# ==========================================

collect_health_timestamp() {
    local current_timestamp=$(date +%s)
    add_metric "Last CloudSync health check timestamp (Unix)" "gauge" "cloudsync_health_last_check_timestamp" "$current_timestamp"
}

# ==========================================
# MAIN EXECUTION
# ==========================================

main() {
    echo "# CloudSync Metrics Export" > "$TEMP_FILE"
    echo "# Generated: $(date --iso-8601=seconds)" >> "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"

    collect_bundle_metrics
    collect_restic_metrics
    collect_sync_metrics
    collect_health_timestamp

    # Atomic write to metrics file
    mkdir -p "$(dirname "$METRICS_FILE")" 2>/dev/null || true
    if mv "$TEMP_FILE" "$METRICS_FILE" 2>/dev/null; then
        chmod 644 "$METRICS_FILE" 2>/dev/null || true
        echo "✓ CloudSync metrics exported to $METRICS_FILE"
    else
        # Fallback to temp location
        LOCAL_METRICS="/tmp/cloudsync-metrics.prom"
        if mv "$TEMP_FILE" "$LOCAL_METRICS" 2>/dev/null; then
            chmod 644 "$LOCAL_METRICS" 2>/dev/null || true
            echo "⚠ Exported to $LOCAL_METRICS (Prometheus directory not available)"
        else
            echo "ERROR: Failed to write metrics file" >&2
            rm -f "$TEMP_FILE"
            exit 1
        fi
    fi
}

# Trap cleanup
trap 'rm -f "$TEMP_FILE"' EXIT

main "$@"
