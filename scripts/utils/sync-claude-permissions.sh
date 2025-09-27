#!/bin/bash

# Sync Claude Code permissions from global to project-level settings
# Merges global allow/deny/ask rules into each project's settings.local.json

set -e

GLOBAL_SETTINGS="$HOME/.claude/settings.local.json"
PROJECTS_DIR="$HOME/projects"

echo "🔧 Syncing Claude Code permissions to all projects..."

# Check if global settings exists
if [[ ! -f "$GLOBAL_SETTINGS" ]]; then
    echo "❌ Global settings not found: $GLOBAL_SETTINGS"
    exit 1
fi

# Extract global permissions using jq
if ! command -v jq &> /dev/null; then
    echo "❌ jq is required but not installed. Install with: sudo apt install jq"
    exit 1
fi

# Read global permissions
GLOBAL_ALLOW=$(jq -r '.permissions.allow // []' "$GLOBAL_SETTINGS")
GLOBAL_DENY=$(jq -r '.permissions.deny // []' "$GLOBAL_SETTINGS")
GLOBAL_ASK=$(jq -r '.permissions.ask // []' "$GLOBAL_SETTINGS")

echo "📋 Global permissions summary:"
echo "  Allow rules: $(echo "$GLOBAL_ALLOW" | jq 'length')"
echo "  Deny rules: $(echo "$GLOBAL_DENY" | jq 'length')"
echo "  Ask rules: $(echo "$GLOBAL_ASK" | jq 'length')"
echo ""

# Find all project settings files
while IFS= read -r -d '' settings_file; do
    if [[ -f "$settings_file" ]]; then
        project_dir=$(dirname "$(dirname "$settings_file")")
        project_name=$(basename "$project_dir")

        echo "🔄 Processing: $project_name"

        # Create backup
        backup_file="${settings_file}.backup-$(date +%Y%m%d-%H%M%S)"
        cp "$settings_file" "$backup_file"
        echo "  📦 Backup created: $(basename "$backup_file")"

        # Merge permissions using jq
        jq --argjson global_allow "$GLOBAL_ALLOW" \
           --argjson global_deny "$GLOBAL_DENY" \
           --argjson global_ask "$GLOBAL_ASK" '
        .permissions.allow = (.permissions.allow // []) + $global_allow | unique |
        .permissions.deny = (.permissions.deny // []) + $global_deny | unique |
        .permissions.ask = (.permissions.ask // []) + $global_ask | unique
        ' "$settings_file" > "${settings_file}.tmp" && mv "${settings_file}.tmp" "$settings_file"

        echo "  ✅ Permissions merged successfully"
        echo ""
    fi
done < <(find "$PROJECTS_DIR" -name "settings.local.json" -path "*/.claude/*" -print0 2>/dev/null)

echo "✨ Permission sync complete!"
echo ""
echo "📊 Summary:"
echo "  - Merged global allow/deny/ask rules into each project"
echo "  - Removed duplicate entries automatically"
echo "  - Created timestamped backups for safety"
echo ""
echo "🔍 To verify changes:"
echo "  cd ~/projects/[project-name]"
echo "  jq '.permissions' .claude/settings.local.json"
echo ""
echo "↩️  To rollback a project:"
echo "  cd ~/projects/[project-name]/.claude"
echo "  cp settings.local.json.backup-* settings.local.json"