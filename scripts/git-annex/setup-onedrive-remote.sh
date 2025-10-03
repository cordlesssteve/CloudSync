#!/bin/bash
# CloudSync - Git-Annex OneDrive Remote Setup
# Usage: ./setup-onedrive-remote.sh [repo-path] [remote-name]

set -e

REPO_PATH=${1:-"."}
REMOTE_NAME=${2:-"onedrive"}
PREFIX="DevEnvironment/git-annex-storage"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_message() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Change to repository directory
cd "$REPO_PATH"

log_message "Setting up git-annex OneDrive remote in $(pwd)"

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    log_error "Not in a Git repository. Please run 'git init' first."
    exit 1
fi

# Check if git-annex is initialized
if [ ! -d ".git/annex" ]; then
    log_message "Initializing git-annex..."
    git annex init "$(hostname)-cloudsync"
    log_success "Git-annex initialized"
fi

# Check if the remote already exists
if git annex info "$REMOTE_NAME" >/dev/null 2>&1; then
    log_warning "Remote '$REMOTE_NAME' already exists"
    git annex info "$REMOTE_NAME"
    exit 0
fi

# Verify rclone OneDrive connection
log_message "Testing rclone OneDrive connection..."
if ! rclone lsd onedrive: >/dev/null 2>&1; then
    log_error "Cannot connect to OneDrive via rclone. Please check your rclone configuration."
    echo "Run 'rclone config' to set up OneDrive access."
    exit 1
fi
log_success "OneDrive connection verified"

# Set up the OneDrive remote
log_message "Configuring OneDrive as git-annex special remote..."
if git annex initremote "$REMOTE_NAME" \
    type=external \
    externaltype=rclone \
    target=onedrive \
    prefix="$PREFIX/" \
    encryption=none; then
    log_success "OneDrive remote '$REMOTE_NAME' configured successfully"
else
    log_error "Failed to configure OneDrive remote"
    exit 1
fi

# Test the remote
log_message "Testing remote functionality..."
REMOTE_INFO=$(git annex info "$REMOTE_NAME" 2>/dev/null || echo "Remote info not available")
echo "$REMOTE_INFO"

log_success "Git-annex OneDrive integration complete!"
echo ""
echo "📋 Next steps:"
echo "  1. Add large files: git annex add large-file.dat"
echo "  2. Commit changes: git commit -m 'Add large file'"
echo "  3. Copy to OneDrive: git annex copy large-file.dat --to $REMOTE_NAME"
echo "  4. Drop local copy: git annex drop large-file.dat"
echo "  5. Retrieve later: git annex get large-file.dat"
echo ""
echo "🔍 Useful commands:"
echo "  - git annex whereis [file]     # Show where file copies exist"
echo "  - git annex list              # List all annexed files"
echo "  - git annex status            # Show annex status"
echo "  - git annex sync              # Sync git-annex branch"