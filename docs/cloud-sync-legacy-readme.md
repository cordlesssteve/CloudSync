# Cloud Development Environment Sync

Enhanced development environment synchronization for seamless multi-device workflows.

## 🚀 Quick Start

```bash
# Push essentials to OneDrive (first device)
~/scripts/cloud/dev-env-sync.sh push

# Pull essentials from OneDrive (other devices)
~/scripts/cloud/dev-env-sync.sh pull

# Clean up old OneDrive data
~/scripts/cloud/dev-env-sync.sh clean
```

## 📋 What Gets Synced (~50-100MB)

### 🔑 Critical Data (Cannot be rebuilt)
- **SSH keys & configs** (`~/.ssh/`)
- **Git credentials** (`.git-credentials`, `.gitconfig`)
- **Claude credentials** (`.claude/.credentials.json`)
- **Custom scripts** (`~/scripts/`, `~/.local/bin/claude-*`)
- **Personal docs & notes** (`~/docs/`, `~/.notez/`)
- **Templates** (`~/.claude/templates/`, `~/templates/`)
- **MCP servers** (`~/mcp-servers/`)

### ⚙️ Development Configs
- **Shell configuration** (`.bashrc`, `.bash_aliases`, `.profile`)
- **Editor configs** (`.vimrc`, VS Code settings)
- **Tool configurations** (rclone, gh, firebase, turborepo, etc.)
- **Development tool configs** (Cypress, Chromium, configstore)

### 📅 System State
- **Crontab** (backup & restore)
- **Command history** (`.bash_history`)

## ❌ What Does NOT Get Synced (Rebuildable)

- **Language packages** (node_modules/, venv/, .local/)
- **Language runtimes** (.nvm/, Python installations)
- **Git repositories** (use GitHub)
- **Caches and temporary files**
- **System packages** (use package managers)

## 📁 Script Location

- **Main script**: `~/scripts/cloud/dev-env-sync.sh`
- **OneDrive path**: `onedrive:DevEnvironment/{HOSTNAME}/essentials/`

## 🔄 Usage Patterns

### New Device Setup
1. Install basic tools: `sudo apt update && sudo apt install -y git curl wget`
2. Pull configs: `~/scripts/cloud/dev-env-sync.sh pull`
3. Run rebuild script: `~/scripts/setup/rebuild-dev-environment.sh`
4. Verify: `git status` and `claude --version`

### Regular Sync (Optional Automation)
```bash
# Weekly sync (add to crontab)
0 2 * * 0 ~/scripts/cloud/dev-env-sync.sh push
```

## ⚡ Performance Features

- **Python venv exclusions** - Prevents syncing 100MB+ of packages
- **Smart exclusions** - Skips build artifacts, caches, logs
- **Selective sync** - Only irreplaceable data
- **Progress reporting** - Real-time transfer status

## 🔍 Help & Status

```bash
# Show all options and coverage details
~/scripts/cloud/dev-env-sync.sh

# Check sync status
ls -la ~/backup-sync-*  # Local backups from pull operations
```

## 🛡️ Safety Features

- **Automatic backups** during pull operations
- **Collision detection** for symlinks and existing configs
- **Selective restore** - choose source hostname for pull
- **Rebuild instructions** included in each sync

---

**Total rebuild time**: ~30 minutes vs 2+ hours for full sync
**Coverage**: ~98% of irreplaceable development environment data