#!/bin/bash
# CloudSync Git Hook Installer
# Installs post-commit hooks in all git repositories

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK_SOURCE="${SCRIPT_DIR}/post-commit"
REPOS_BASE="${HOME}/projects"
LOG_FILE="${HOME}/.cloudsync/logs/hook-install.log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✓ $*${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}⚠ $*${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}✗ $*${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}ℹ $*${NC}" | tee -a "$LOG_FILE"
}

# Check if hook source exists
if [[ ! -f "$HOOK_SOURCE" ]]; then
    log_error "Hook source not found: ${HOOK_SOURCE}"
    exit 1
fi

if [[ ! -x "$HOOK_SOURCE" ]]; then
    log_error "Hook source is not executable: ${HOOK_SOURCE}"
    exit 1
fi

# Statistics
TOTAL_REPOS=0
INSTALLED=0
SKIPPED=0
UPDATED=0
ERRORS=0

log "=========================================="
log "CloudSync Git Hook Installer"
log "=========================================="
log "Hook source: ${HOOK_SOURCE}"
log "Repositories base: ${REPOS_BASE}"
log ""

# Find all git repositories
log_info "Scanning for git repositories..."

while IFS= read -r -d '' git_dir; do
    ((TOTAL_REPOS++)) || true

    repo_dir="$(dirname "$git_dir")"
    repo_name="${repo_dir#${HOME}/projects/}"
    hook_file="${git_dir}/hooks/post-commit"

    # Ensure hooks directory exists
    mkdir -p "${git_dir}/hooks"

    # Check if hook already exists
    if [[ -f "$hook_file" ]]; then
        # Check if it's our hook (contains CloudSync signature)
        if grep -q "CloudSync Auto-Backup Git Hook" "$hook_file" 2>/dev/null; then
            # Check if it's the same version
            if diff -q "$HOOK_SOURCE" "$hook_file" > /dev/null 2>&1; then
                log_info "${repo_name}: Hook already installed (up to date)"
                ((SKIPPED++)) || true
            else
                # Update existing hook
                cp "$HOOK_SOURCE" "$hook_file"
                chmod +x "$hook_file"
                log_success "${repo_name}: Hook updated"
                ((UPDATED++)) || true
            fi
        else
            # Existing hook is not ours, back it up
            backup_file="${hook_file}.backup-$(date +%Y%m%d-%H%M%S)"
            mv "$hook_file" "$backup_file"
            cp "$HOOK_SOURCE" "$hook_file"
            chmod +x "$hook_file"
            log_warning "${repo_name}: Existing hook backed up to $(basename "$backup_file"), new hook installed"
            ((INSTALLED++)) || true
        fi
    else
        # No existing hook, install new one
        cp "$HOOK_SOURCE" "$hook_file"
        chmod +x "$hook_file"
        log_success "${repo_name}: Hook installed"
        ((INSTALLED++)) || true
    fi

done < <(find "$REPOS_BASE" -name ".git" -type d -print0 2>/dev/null)

# Summary
echo ""
log "=========================================="
log "Installation Summary"
log "=========================================="
log "Total repositories scanned: ${TOTAL_REPOS}"
log "  ✓ Newly installed: ${INSTALLED}"
log "  ↻ Updated: ${UPDATED}"
log "  - Already up to date: ${SKIPPED}"
log "  ✗ Errors: ${ERRORS}"
log ""

if [[ $((INSTALLED + UPDATED)) -gt 0 ]]; then
    log_success "Git hooks successfully installed/updated in $((INSTALLED + UPDATED)) repositories"
    log ""
    log_info "Auto-backup is now enabled with 10-minute debounce"
    log_info "Make a commit in any repository to test"
    log_info "Monitor: tail -f ${HOME}/.cloudsync/logs/hook-sync.log"
else
    log_info "All repositories already have up-to-date hooks"
fi

log ""
log "Configuration:"
log "  Debounce delay: 10 minutes"
log "  Hook log: ${HOME}/.cloudsync/logs/hook-sync.log"
log "  Lock directory: /tmp/cloudsync-hook-locks"
log ""

# Test hook availability
log_info "Testing hook configuration..."
CLOUDSYNC_SCRIPT="${PROJECT_ROOT}/scripts/bundle/git-bundle-sync.sh"
if [[ -x "$CLOUDSYNC_SCRIPT" ]]; then
    log_success "CloudSync script found: ${CLOUDSYNC_SCRIPT}"
else
    log_error "CloudSync script not found or not executable: ${CLOUDSYNC_SCRIPT}"
    log_error "Hooks will fail until this is fixed"
fi

NOTIFY_SCRIPT="${PROJECT_ROOT}/scripts/notify.sh"
if [[ -x "$NOTIFY_SCRIPT" ]]; then
    log_success "Notification script found: ${NOTIFY_SCRIPT}"
else
    log_warning "Notification script not found (optional): ${NOTIFY_SCRIPT}"
fi

log "=========================================="
log "Installation complete!"
log "=========================================="

exit 0
