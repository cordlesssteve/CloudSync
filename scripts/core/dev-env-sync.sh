#!/bin/bash

# Development Environment Sync - Enhanced for Identical Dev Workflows
# Syncs irreplaceable data + development configs for true environment mirroring
# Replaces: dev-env-push.sh, dev-env-push-critical.sh, quick-sync.sh, complete-env-sync.sh

set -e

TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
HOSTNAME=$(hostname)

case "$1" in
    "push"|"up"|"")
        echo "=== Development Environment Sync - Enhanced Push to OneDrive ==="
        echo "Syncing irreplaceable data + dev configs for true environment mirroring"
        echo "Started: $(date)"
        echo ""

# CRITICAL DATA ONLY - Cannot be rebuilt
CRITICAL_PATHS=(
    "$HOME/.ssh"                    # SSH keys, configs (CRITICAL)
    "$HOME/scripts"                 # Custom automation scripts
    "$HOME/mcp-servers"             # Custom MCP server code
    "$HOME/docs"                    # Documentation and notes
    "$HOME/.claude/templates"       # Custom Claude templates
    "$HOME/templates"               # Project templates
    "$HOME/.notez"                  # Personal notes and secrets
)

# CRITICAL FILES - Custom configurations
CRITICAL_FILES=(
    "$HOME/.gitconfig"              # Git config with credentials
    "$HOME/.bash_aliases"           # Custom shell aliases
    "$HOME/.bashrc"                 # Custom shell configuration
    "$HOME/.profile"                # Shell profile
    "$HOME/.vimrc"                  # Editor config
    "$HOME/.git-credentials"        # Git credential storage (GitHub tokens)
    "$HOME/.claude/.credentials.json" # Claude API credentials
    "$HOME/.bash_aliases_backup"    # Backup shell aliases
    "$HOME/.bash_history"           # Command history (convenience)
)

# CUSTOM SCRIPTS - Local scripts that can't be rebuilt from packages
CUSTOM_SCRIPTS=(
    "$HOME/.local/bin/claude-activity"    # Custom Claude activity script
    "$HOME/.local/bin/claude-dashboard"   # Custom Claude dashboard script
    "$HOME/.local/bin/claude-register"    # Custom Claude register script
    "$HOME/.local/bin/claude-status"      # Custom Claude status script
)

# SELECTIVE CONFIG - Only configs with auth/custom settings
SELECTIVE_CONFIG=(
    "$HOME/.config/rclone"          # Cloud storage credentials
    "$HOME/.config/gh"              # GitHub CLI auth
    "$HOME/.config/git"             # Git credentials
    "$HOME/.config/syncthing"       # File synchronization config
    "$HOME/.config/claude-code"     # Claude Code IDE settings
)

# ENHANCED CONFIG - Project-specific and development tool configs
# Since both devices work on identical projects/stacks, sync these for true mirroring
ENHANCED_CONFIG=(
    "$HOME/.config/firebase"         # Deployment configs
    "$HOME/.config/turborepo"        # Monorepo settings
    "$HOME/.config/nextjs-nodejs"    # Framework configs
    "$HOME/.config/configstore"      # Tool authentication tokens
    "$HOME/.config/Cypress"          # E2E test configs
    "$HOME/.config/chromium"         # Browser automation configs
)

echo "🔑 Syncing critical directories..."
for path in "${CRITICAL_PATHS[@]}"; do
    if [ -d "$path" ]; then
        dir_name=$(basename "$path")
        echo "Syncing $path -> onedrive:DevEnvironment/$HOSTNAME/essentials/$dir_name/"
        rclone sync "$path" "onedrive:DevEnvironment/$HOSTNAME/essentials/$dir_name" \
            --progress \
            --exclude "*.tmp" \
            --exclude "*.log" \
            --exclude "node_modules/" \
            --exclude ".git/" \
            --exclude "__pycache__/" \
            --exclude "*.pyc" \
            --exclude "venv/" \
            --exclude ".venv/" \
            --exclude "env/" \
            --exclude ".env/" \
            --exclude "*.egg-info/" \
            --exclude "dist/" \
            --exclude "build/" \
            --exclude ".pytest_cache/"
    else
        echo "⚠️  Skipping $path (not found)"
    fi
done

echo ""
echo "📁 Syncing critical files..."
mkdir -p "/tmp/critical-files-$TIMESTAMP"
for file in "${CRITICAL_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "Copying $file"
        cp "$file" "/tmp/critical-files-$TIMESTAMP/"
    fi
done

if [ "$(ls -A /tmp/critical-files-$TIMESTAMP 2>/dev/null)" ]; then
    echo "Uploading critical files..."
    rclone sync "/tmp/critical-files-$TIMESTAMP" "onedrive:DevEnvironment/$HOSTNAME/essentials/dotfiles/"
    rm -rf "/tmp/critical-files-$TIMESTAMP"
fi

echo ""
echo "⏰ Backing up crontab..."
if crontab -l >/dev/null 2>&1; then
    crontab -l > "/tmp/crontab-backup-$TIMESTAMP" 2>/dev/null
    echo "Uploading crontab backup..."
    rclone copy "/tmp/crontab-backup-$TIMESTAMP" "onedrive:DevEnvironment/$HOSTNAME/essentials/"
    rm "/tmp/crontab-backup-$TIMESTAMP"
else
    echo "⏭️  No crontab to backup"
fi

echo ""
echo "⚙️  Syncing selective configs..."
for path in "${SELECTIVE_CONFIG[@]}"; do
    if [ -d "$path" ]; then
        dir_name=$(basename "$path")
        echo "Syncing $path"
        rclone sync "$path" "onedrive:DevEnvironment/$HOSTNAME/essentials/config/$dir_name" \
            --exclude "cache/" \
            --exclude "logs/" \
            --exclude "tmp/"
    fi
done

echo ""
echo "🚀 Syncing enhanced development configs..."
for path in "${ENHANCED_CONFIG[@]}"; do
    if [ -d "$path" ]; then
        dir_name=$(basename "$path")
        echo "Syncing $path (dev config)"
        rclone sync "$path" "onedrive:DevEnvironment/$HOSTNAME/essentials/dev-config/$dir_name" \
            --exclude "cache/" \
            --exclude "logs/" \
            --exclude "tmp/" \
            --exclude "node_modules/" \
            --exclude "*.lock"
    else
        echo "⏭️  Skipping $path (not found)"
    fi
done

echo ""
echo "🔧 Syncing custom scripts..."
mkdir -p "/tmp/custom-scripts-$TIMESTAMP"
for script in "${CUSTOM_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        script_name=$(basename "$script")
        echo "Copying $script_name"
        cp "$script" "/tmp/custom-scripts-$TIMESTAMP/"
    else
        echo "⏭️  Skipping $script (not found)"
    fi
done

if [ "$(ls -A /tmp/custom-scripts-$TIMESTAMP 2>/dev/null)" ]; then
    echo "Uploading custom scripts..."
    rclone sync "/tmp/custom-scripts-$TIMESTAMP" "onedrive:DevEnvironment/$HOSTNAME/essentials/local-bin/"
    rm -rf "/tmp/custom-scripts-$TIMESTAMP"
fi

# Sync VS Code settings if they exist
echo ""
echo "🆚 Checking for VS Code settings..."
VS_CODE_PATHS=(
    "$HOME/.vscode"
    "$HOME/.config/Code/User"
    "/mnt/c/Users/$USER/AppData/Roaming/Code/User"  # Windows VS Code via WSL
)

for vscode_path in "${VS_CODE_PATHS[@]}"; do
    if [ -d "$vscode_path" ]; then
        echo "Found VS Code config at $vscode_path"
        rclone sync "$vscode_path" "onedrive:DevEnvironment/$HOSTNAME/essentials/vscode/" \
            --exclude "logs/" \
            --exclude "CachedExtensions/" \
            --exclude "CachedData/" \
            --exclude "*.log"
        break
    fi
done

echo ""
echo "📋 Creating rebuild instructions..."
cat > "/tmp/rebuild-instructions-$TIMESTAMP.md" << 'EOF'
# Environment Rebuild Instructions

## Quick Start (5-10 minutes)
1. Install basic tools: `sudo apt update && sudo apt install -y git curl wget`
2. Pull critical configs: `~/scripts/cloud/dev-env-sync.sh pull`
3. Run rebuild script: `~/scripts/setup/rebuild-dev-environment.sh`
4. Verify credentials are working: `git status` and `claude --version`
5. Check templates restored: `ls ~/.claude/templates ~/templates`
6. Verify crontab: `crontab -l` (should show backup schedule)

## What Was NOT Synced (Rebuildable)
- Python packages (~400MB) - Run: `pip install -r requirements.txt`
- Node.js versions (~1GB) - Run: `nvm install node && nvm use node`
- System packages - Run: `sudo apt install $(cat system-packages.list)`

## Rebuild Commands
```bash
# Development essentials (global packages)
npm install -g $(cat ~/system-state/npm-global-packages-*.json | jq -r '.dependencies | keys[]')
pip install --user -r ~/system-state/pip-packages-global-*.txt

# Node.js environment
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install node

# System packages (essential dev tools)
sudo apt install $(cat ~/system-state/apt-packages-*.txt | awk '{print $1}')
```

Total rebuild time: ~30 minutes vs 2+ hours for full sync
EOF

rclone copy "/tmp/rebuild-instructions-$TIMESTAMP.md" "onedrive:DevEnvironment/$HOSTNAME/essentials/"
rm "/tmp/rebuild-instructions-$TIMESTAMP.md"

        echo ""
        echo "✅ Development Environment Push Complete!"
        echo "📊 Data synced: ~50-100MB (vs 20GB+ for full sync)"
        echo "⏱️  Total time: $(date)"
        echo ""
        echo "🚀 Next steps:"
        echo "1. On Device B: run: ~/scripts/cloud/dev-env-sync.sh pull"
        echo "2. Rebuild environment in ~30 minutes vs 2+ hours"
        echo "3. Use system manifests to restore packages"
        ;;

    "pull"|"down")
        echo "=== Development Environment Sync - Pull from OneDrive ==="
        echo ""

        read -p "Source hostname [$HOSTNAME]: " SOURCE_HOST
        SOURCE_HOST=${SOURCE_HOST:-$HOSTNAME}

        echo "Pulling essentials from: $SOURCE_HOST"
        echo ""

        # Create backup
        BACKUP_DIR="$HOME/backup-sync-$TIMESTAMP"
        mkdir -p "$BACKUP_DIR"

        # Pull critical directories
        echo "📥 Restoring critical directories..."
        for path in "${CRITICAL_PATHS[@]}"; do
            if [ -d "$path" ]; then
                cp -r "$path" "$BACKUP_DIR/"
            fi
            dir_name=$(basename "$path")
            echo "Pulling $dir_name"
            rclone sync "onedrive:DevEnvironment/$SOURCE_HOST/essentials/$dir_name" "$path" --progress
        done

        # Pull dotfiles
        echo "📁 Restoring dotfiles..."
        rclone copy "onedrive:DevEnvironment/$SOURCE_HOST/essentials/dotfiles/" "$HOME/" --progress

        # Pull crontab
        echo "⏰ Restoring crontab..."
        if rclone copy "onedrive:DevEnvironment/$SOURCE_HOST/essentials/crontab-backup-"* "/tmp/" --progress 2>/dev/null; then
            LATEST_CRONTAB=$(ls -t /tmp/crontab-backup-* 2>/dev/null | head -1)
            if [ -f "$LATEST_CRONTAB" ]; then
                crontab "$LATEST_CRONTAB"
                rm "$LATEST_CRONTAB"
                echo "✅ Crontab restored"
            fi
        else
            echo "⏭️  No crontab backup found to restore"
        fi

        # Pull configs
        echo "⚙️  Restoring configs..."
        for path in "${SELECTIVE_CONFIG[@]}"; do
            dir_name=$(basename "$path")
            if rclone lsd "onedrive:DevEnvironment/$SOURCE_HOST/essentials/config/$dir_name" >/dev/null 2>&1; then
                echo "Pulling $dir_name config"
                rclone sync "onedrive:DevEnvironment/$SOURCE_HOST/essentials/config/$dir_name" "$path" --progress
            fi
        done

        # Pull enhanced development configs
        echo "🚀 Restoring development configs..."
        for path in "${ENHANCED_CONFIG[@]}"; do
            dir_name=$(basename "$path")
            if rclone lsd "onedrive:DevEnvironment/$SOURCE_HOST/essentials/dev-config/$dir_name" >/dev/null 2>&1; then
                echo "Pulling $dir_name dev config"
                mkdir -p "$path"
                rclone sync "onedrive:DevEnvironment/$SOURCE_HOST/essentials/dev-config/$dir_name" "$path" --progress
            fi
        done

        # Pull custom scripts
        echo "🔧 Restoring custom scripts..."
        if rclone lsd "onedrive:DevEnvironment/$SOURCE_HOST/essentials/local-bin/" >/dev/null 2>&1; then
            mkdir -p "$HOME/.local/bin"
            rclone copy "onedrive:DevEnvironment/$SOURCE_HOST/essentials/local-bin/" "$HOME/.local/bin/" --progress
            # Make scripts executable
            chmod +x "$HOME"/.local/bin/claude-* 2>/dev/null || true
            echo "✅ Custom scripts restored to ~/.local/bin/"
        else
            echo "⏭️  No custom scripts found to restore"
        fi

        # Pull VS Code settings
        echo "🆚 Restoring VS Code settings..."
        if rclone lsd "onedrive:DevEnvironment/$SOURCE_HOST/essentials/vscode/" >/dev/null 2>&1; then
            # Try to restore to the first available VS Code path
            for vscode_path in "${VS_CODE_PATHS[@]}"; do
                if [[ -d "$(dirname "$vscode_path")" ]] || mkdir -p "$(dirname "$vscode_path")" 2>/dev/null; then
                    echo "Restoring VS Code settings to $vscode_path"
                    rclone sync "onedrive:DevEnvironment/$SOURCE_HOST/essentials/vscode/" "$vscode_path" --progress
                    break
                fi
            done
        else
            echo "⏭️  No VS Code settings found to restore"
        fi

        echo ""
        echo "✅ Development Environment Pull Complete!"
        echo "💾 Backup saved to: $BACKUP_DIR"
        echo "🔄 Run 'source ~/.bashrc' to reload shell configs"
        ;;

    "clean")
        echo "🧹 Cleaning old OneDrive backups..."
        echo "WARNING: This will delete bloated folders (.local/, quick-sync/)"
        read -p "Continue? [y/N]: " CONFIRM
        if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
            echo "Deleting bloated folders..."
            rclone purge "onedrive:DevEnvironment/$HOSTNAME/.local/" || echo "(.local not found)"
            rclone purge "onedrive:DevEnvironment/$HOSTNAME/quick-sync/" || echo "(quick-sync not found)"
            echo "✅ Cleanup complete!"
        else
            echo "Cleanup cancelled"
        fi
        ;;

    *)
        echo "Usage: $0 {push|pull|clean|up|down}"
        echo ""
        echo "Commands:"
        echo "  push/up - Upload essentials to OneDrive"
        echo "  pull/down - Download essentials from OneDrive"
        echo "  clean - Remove bloated folders from OneDrive"
        echo ""
        echo "What gets synced (comprehensive coverage ~98%):"
        echo "  🔑 SSH keys and critical configs"
        echo "  🗝️  Git and Claude credentials (portable tokens)"
        echo "  📜 Custom scripts and docs"
        echo "  📋 Personal templates and notes (~/.claude/templates, ~/.notez)"
        echo "  🛠️  MCP servers"
        echo "  🔧 Custom local binaries (claude-* scripts)"
        echo "  ⚙️  Critical dotfiles and configs + backups"
        echo "  🚀 Development tool configs (Firebase, Turborepo, etc.)"
        echo "  🆚 VS Code settings and extensions"
        echo "  🔄 Syncthing and Claude Code IDE settings"
        echo "  ⏰ Scheduled tasks (crontab backup)"
        echo "  📚 Command history (convenience)"
        echo ""
        echo "What does NOT get synced (rebuildable):"
        echo "  📦 Language packages (.local/, node_modules/)"
        echo "  🟢 Language runtimes (.nvm/, Python installations)"
        echo "  📁 Git repositories (use GitHub)"
        echo "  💾 Caches and temporary files"
        exit 1
        ;;
esac