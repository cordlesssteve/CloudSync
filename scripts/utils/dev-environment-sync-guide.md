# Development Environment Sync Guide

A comprehensive strategy for keeping development environments synchronized across multiple machines, with special consideration for WSL/Windows hybrid setups.

## Core Principles

### 1. Treat Your Dev Environment Like a Project

- Create a `dev-env` repository (private if needed) in Git
- Store configs, install scripts, and tool version files
- Update whenever you change tooling and push to Git
- On other machines: `git pull && ./sync-dev.sh` to match

### 2. Repository Structure

Organize your environment repo with clear separation:

```
dev-env/
├── windows/              # Windows-specific configs
│   ├── packages.yaml     # Declarative package lists
│   ├── choco-packages.txt
│   ├── winget-packages.json
│   └── terminal.json     # Windows Terminal settings
├── wsl/                  # WSL/Linux configs
│   ├── apt-packages.txt  # System packages
│   ├── snap-packages.txt
│   ├── npm-global.txt    # Global npm packages
│   ├── pip-packages.txt  # Python packages
│   └── .bashrc
├── shared/               # Cross-platform configs
│   ├── .gitconfig
│   ├── .npmrc
│   └── .tool-versions    # For version managers
├── scripts/              # Automation scripts
│   ├── install.sh
│   ├── sync-dev.sh
│   ├── backup.sh
│   └── check-env.sh     # Health check script
├── docs/
│   └── bin-locations.md # Installation path documentation
└── .env.example          # Environment variable template
```

## Implementation Steps

### 3. Use Declarative Package Lists

Instead of complex install scripts with conditional logic, maintain simple lists of what should be installed.

#### Windows Package Lists

**windows/choco-packages.txt:**
```
git
vscode
docker-desktop
nodejs
python3
```

**windows/winget-packages.json:**
```json
{
  "packages": [
    "Microsoft.WindowsTerminal",
    "Microsoft.PowerToys",
    "GitHub.cli"
  ]
}
```

#### WSL/Linux Package Lists

**wsl/apt-packages.txt:**
```
build-essential
git
curl
wget
htop
jq
ripgrep
```

**wsl/npm-global.txt:**
```
typescript
eslint
prettier
nodemon
```

### 4. Capture Configuration with Dotfiles

Store important config files in the repo and use symlinks:

```bash
# In sync-dev.sh
ln -sf ~/dev-env/wsl/.bashrc ~/.bashrc
ln -sf ~/dev-env/shared/.gitconfig ~/.gitconfig
ln -sf ~/dev-env/shared/.npmrc ~/.npmrc
```

Include these essential configs:
- Shell configuration (`.bashrc`, `.zshrc`)
- Aliases (`.aliases`)
- PATH and environment exports (`.exports`)
- Git configuration (`.gitconfig`)
- Tool-specific configs (`.npmrc`, etc.)

### 5. Manage PATH Explicitly

Create a centralized `.exports` file for PATH management:

**shared/.exports:**
```bash
# User-local binaries (highest priority)
export PATH="$HOME/.local/bin:$PATH"

# Language-specific paths
export PATH="$HOME/.npm-global/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"

# Snap packages
export PATH="/snap/bin:$PATH"

# WSL-specific: Selective Windows tools
export PATH="$PATH:/mnt/c/Program Files/Git/bin"
export PATH="$PATH:/mnt/c/Windows/System32"

# System paths (lowest priority)
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
```

### 6. Document Install Locations

Maintain a clear map of your environment:

**docs/bin-locations.md:**
```markdown
# Binary and Tool Locations

## Windows Side
| Tool | Package Manager | Location | Relocatable |
|------|----------------|----------|-------------|
| git | Chocolatey | C:\Program Files\Git | No |
| node | nvm-windows | C:\nvm4w\nodejs | Yes |
| python | winget | C:\Python39 | No |

## WSL Side
| Tool | Package Manager | Location | Relocatable |
|------|----------------|----------|-------------|
| node | nvm | ~/.nvm/versions | Yes |
| python | apt | /usr/bin/python3 | No |
| docker | snap | /snap/bin/docker | No |
```

### 7. Use Version Managers

Standardize runtime versions across machines:

**shared/.tool-versions:** (for asdf)
```
nodejs 20.11.0
python 3.11.7
ruby 3.2.0
```

Or use specific version files:
- `.nvmrc` for Node.js
- `.python-version` for pyenv
- `.ruby-version` for rbenv

### 8. Automation Scripts

#### Main Installation Script

**scripts/install.sh:**
```bash
#!/bin/bash
set -e

echo "Setting up development environment..."

# Backup existing configs
./scripts/backup.sh

# Install WSL packages
echo "Installing apt packages..."
sudo apt update
xargs -a wsl/apt-packages.txt sudo apt install -y

# Install global npm packages
echo "Installing npm packages..."
xargs -a wsl/npm-global.txt npm install -g

# Setup symlinks
echo "Creating config symlinks..."
ln -sf $(pwd)/wsl/.bashrc ~/.bashrc
ln -sf $(pwd)/shared/.gitconfig ~/.gitconfig
ln -sf $(pwd)/shared/.exports ~/.exports

# Source new configuration
source ~/.bashrc

echo "Installation complete!"
```

#### Environment Health Check

**scripts/check-env.sh:**
```bash
#!/bin/bash

echo "Checking development environment..."

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Check function
check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 found: $(which $1)"
    else
        echo -e "${RED}✗${NC} $1 not found"
        return 1
    fi
}

# Check essential tools
check_command git
check_command node
check_command npm
check_command python3
check_command docker

# Check PATH
echo -e "\nPATH entries:"
echo $PATH | tr ':' '\n' | head -5

# Check versions
echo -e "\nTool versions:"
node --version
npm --version
python3 --version
```

#### Sync Script

**scripts/sync-dev.sh:**
```bash
#!/bin/bash
set -e

echo "Syncing development environment..."

# Pull latest changes
git pull

# Backup current state
backup_timestamp=$(date +%Y%m%d_%H%M%S)
cp ~/.bashrc ~/.bashrc.$backup_timestamp 2>/dev/null || true

# Update packages
echo "Updating packages..."
comm -13 <(dpkg -l | awk '{print $2}' | sort) <(sort wsl/apt-packages.txt) | xargs -r sudo apt install -y

# Update npm globals
npm list -g --depth=0 --json | jq -r '.dependencies | keys[]' > /tmp/current-npm.txt
comm -13 <(sort /tmp/current-npm.txt) <(sort wsl/npm-global.txt) | xargs -r npm install -g

# Refresh symlinks
ln -sf $(pwd)/wsl/.bashrc ~/.bashrc
ln -sf $(pwd)/shared/.gitconfig ~/.gitconfig

# Reload shell configuration
source ~/.bashrc

echo "Sync complete!"
```

### 9. Environment Secrets Management

Never commit actual secrets. Use templates:

**.env.example:**
```bash
# GitHub
GITHUB_TOKEN=
GITHUB_USER=

# NPM
NPM_TOKEN=
NPM_REGISTRY=

# API Keys
OPENAI_API_KEY=
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
```

Load in `.bashrc`:
```bash
# Load environment secrets if file exists
if [ -f "$HOME/.env" ]; then
    export $(cat $HOME/.env | xargs)
fi
```

### 10. WSL-Specific Configurations

**Windows side - .wslconfig:** (in Windows user home)
```ini
[wsl2]
memory=8GB
processors=4
swap=2GB
localhostForwarding=true
```

**WSL side - /etc/wsl.conf:**
```ini
[automount]
enabled = true
options = "metadata,uid=1000,gid=1000,umask=022"

[interop]
appendWindowsPath = true
```

## Regular Maintenance Workflow

1. **When adding new tools:**
   ```bash
   # Add to appropriate package list
   echo "new-tool" >> wsl/apt-packages.txt
   
   # Commit and push
   git add wsl/apt-packages.txt
   git commit -m "Add new-tool to apt packages"
   git push
   
   # Sync on other machine
   git pull && ./scripts/sync-dev.sh
   ```

2. **Daily/Weekly sync:**
   ```bash
   cd ~/dev-env
   git pull
   ./scripts/check-env.sh  # Verify environment health
   ./scripts/sync-dev.sh   # Apply any changes
   ```

3. **Before major changes:**
   ```bash
   ./scripts/backup.sh      # Create timestamped backups
   ```

## Best Practices

1. **Start Simple:** Begin with basic package lists and scripts, add complexity as needed
2. **Version Everything:** Use git tags for major environment versions
3. **Test Changes:** Try changes on one machine before syncing to all
4. **Document Oddities:** Note any machine-specific requirements in README
5. **Regular Syncs:** Don't let environments drift too far apart
6. **Backup Before Sync:** Always backup configs before applying changes

## Troubleshooting

- **Path conflicts:** Check `.exports` for duplicate entries
- **Version mismatches:** Ensure `.tool-versions` is synchronized
- **Permission issues:** Check file ownership and executable flags on scripts
- **Windows/WSL interop:** Verify `/etc/wsl.conf` and `.wslconfig` settings

This approach keeps your development environments consistent, recoverable, and maintainable across all your machines.