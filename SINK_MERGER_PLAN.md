# Sink → CloudSync Merger Plan

**Status:** ACTIVE
**Created:** 2025-10-15
**Objective:** Merge Sink quick-transfer repository into CloudSync as a specialized transfer workflow

---

## Current Analysis

### **Sink Project Overview**
- **Purpose:** Quick file transfer between devices via GitHub
- **Size:** ~34MB (mostly environment comparison data + config backups)
- **Activity:** Active (last commit Oct 12, 2025)
- **Key Contents:**
  - Environment comparison reports (14MB)
  - Claude config backups (.tar.gz files, 10MB)
  - Dev environment configs (124KB)
  - Syncthing configurations
  - System documentation

### **Overlap with CloudSync**
❓ **SPECULATION**: Sink and CloudSync have overlapping purposes but different mechanisms:

**Sink:**
- Uses Git as transport
- Manual git add/commit/push workflow
- Ideal for quick ad-hoc transfers
- No automated sync
- Small files only

**CloudSync:**
- Uses rclone + OneDrive
- Automated sync with cron jobs
- Handles large files with git-annex
- Git bundles for repository backups
- Continuous background sync

### **User Behavior Patterns**
🤔 **LIKELY**: Sink serves different use case than CloudSync:
- **Sink** = "I need this file on another device NOW" (manual, immediate)
- **CloudSync** = "Keep these directories synchronized" (automated, background)

---

## Merger Strategy

### **Option A: Full Absorption (Recommended)**

**Merge Sink into CloudSync as `/quick-transfer/` directory**

```
CloudSync/
├── scripts/
│   ├── core/               # Existing sync
│   ├── backup/             # Existing backups
│   ├── bundle/             # Existing git bundles
│   └── quick-transfer/     # NEW: Sink functionality
│       ├── transfer.sh     # Quick transfer CLI
│       ├── sync.sh         # Manual git sync
│       └── cleanup.sh      # Remove transferred files
├── quick-transfer/         # NEW: Active transfer staging area
│   ├── notes/
│   ├── temp/
│   ├── scripts/
│   └── README.md
└── docs/
    └── QUICK_TRANSFER_GUIDE.md  # NEW: Usage documentation
```

**Benefits:**
- ✅ Unified backup/sync/transfer platform
- ✅ Leverages existing CloudSync infrastructure
- ✅ Sink data preserved in CloudSync
- ✅ Maintains quick-transfer workflow
- ✅ Reduces project sprawl

**Drawbacks:**
- ❌ CloudSync becomes larger/more complex
- ❌ User must remember Sink is now in CloudSync

---

### **Option B: Hybrid Integration**

**Keep Sink separate, add CloudSync integration**

```
Sink/  (Independent Git Repository)
├── .cloudsync-integration/
│   ├── auto-backup.sh      # Auto-backup to CloudSync after git push
│   ├── sync-from-cloud.sh  # Pull from OneDrive to Sink
│   └── README.md
└── ... existing Sink structure ...

CloudSync/
├── integrations/
│   └── sink-watcher/       # Watch Sink repo, sync to OneDrive
│       ├── watch.sh
│       └── config.json
```

**Benefits:**
- ✅ Sink remains lightweight and focused
- ✅ CloudSync provides backup layer
- ✅ Best of both worlds (quick Git + persistent cloud)

**Drawbacks:**
- ❌ Two separate projects to maintain
- ❌ Integration complexity
- ❌ Doesn't reduce project count

---

## Recommended Approach: **Option A (Full Absorption)**

### **Rationale:**
1. **Sink's git-based transfer is a workflow, not a platform** - It fits as a feature within CloudSync
2. **Data consolidation** - Environment comparisons, configs belong in CloudSync managed storage
3. **Simpler mental model** - "CloudSync handles all sync/transfer/backup needs"
4. **Reduced maintenance** - One project instead of two

---

## Implementation Plan

### **Phase 1: Data Migration (Week 1)**

#### Step 1.1: Create CloudSync Quick-Transfer Directory
```bash
cd ~/projects/Utility/LOGISTICAL/CloudSync
mkdir -p quick-transfer/{notes,temp,scripts,configs}
mkdir -p scripts/quick-transfer
```

#### Step 1.2: Migrate Sink Contents
```bash
# Move active transfer directories
cp -r ~/projects/Utility/LOGISTICAL/Sink/notes/* \
      ~/projects/Utility/LOGISTICAL/CloudSync/quick-transfer/notes/

cp -r ~/projects/Utility/LOGISTICAL/Sink/temp/* \
      ~/projects/Utility/LOGISTICAL/CloudSync/quick-transfer/temp/

# Move environment comparison data to managed storage
cp -r ~/projects/Utility/LOGISTICAL/Sink/environment-comparison \
      ~/cloudsync-managed/environment-analysis/

cp -r ~/projects/Utility/LOGISTICAL/Sink/env-audit \
      ~/cloudsync-managed/environment-analysis/

# Move config backups to CloudSync backup directory
mv ~/projects/Utility/LOGISTICAL/Sink/*.tar.gz \
   ~/cloudsync-managed/config-backups/
```

#### Step 1.3: Preserve Sink Git History
```bash
cd ~/projects/Utility/LOGISTICAL/Sink
git log --pretty=format:"%h - %an, %ar : %s" > ~/projects/Utility/LOGISTICAL/CloudSync/SINK_MIGRATION_HISTORY.md
```

---

### **Phase 2: Quick-Transfer CLI Tool (Week 1-2)**

#### Create `scripts/quick-transfer/transfer.sh`

```bash
#!/bin/bash
# CloudSync Quick Transfer CLI
# Quick file transfer between devices using Git

set -euo pipefail

CLOUDSYNC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TRANSFER_DIR="$CLOUDSYNC_ROOT/quick-transfer"
TRANSFER_REPO="https://github.com/cordlesssteve/CloudSync.git"

usage() {
    cat <<EOF
CloudSync Quick Transfer

Usage:
  transfer add <file|dir>     Add files to transfer queue
  transfer send               Commit and push transfer queue
  transfer receive            Pull transferred files
  transfer list               Show pending transfers
  transfer clean              Remove transferred files from temp/

Examples:
  transfer add ~/important-note.md
  transfer add ~/scripts/useful-script.sh
  transfer send
  # On another device:
  transfer receive
  transfer clean
EOF
}

add_files() {
    local source="$1"
    local dest_dir="$TRANSFER_DIR/temp"

    if [[ ! -e "$source" ]]; then
        echo "ERROR: File not found: $source" >&2
        exit 1
    fi

    cp -r "$source" "$dest_dir/"
    echo "✓ Added to transfer queue: $(basename "$source")"
    echo "  Staged in: $dest_dir/"
}

send_transfer() {
    cd "$CLOUDSYNC_ROOT"

    if [[ -z $(git status --porcelain quick-transfer/) ]]; then
        echo "No files to transfer (queue is empty)"
        exit 0
    fi

    git add quick-transfer/
    git commit -m "Transfer: $(date --iso-8601=seconds)

Files staged for cross-device transfer.

Auto-generated by CloudSync Quick Transfer"
    git push

    echo "✓ Files transferred via Git"
    echo "  Receive on other device with: transfer receive"
}

receive_transfer() {
    cd "$CLOUDSYNC_ROOT"
    git pull

    local transfer_count=$(find "$TRANSFER_DIR/temp" -type f | wc -l)

    if [[ $transfer_count -eq 0 ]]; then
        echo "No transferred files waiting"
    else
        echo "✓ Received $transfer_count transferred file(s)"
        echo "  Location: $TRANSFER_DIR/temp/"
        echo "  Clean up with: transfer clean"
    fi
}

list_transfers() {
    echo "Pending Transfers:"
    find "$TRANSFER_DIR/temp" -type f -exec ls -lh {} \; 2>/dev/null || echo "  (none)"
}

clean_transfers() {
    rm -rf "$TRANSFER_DIR/temp"/*
    git add "$TRANSFER_DIR/temp"
    git commit -m "Clean: Removed transferred files" || true
    git push
    echo "✓ Transfer queue cleaned"
}

# Main command routing
case "${1:-}" in
    add)
        [[ $# -eq 2 ]] || { usage; exit 1; }
        add_files "$2"
        ;;
    send)
        send_transfer
        ;;
    receive)
        receive_transfer
        ;;
    list)
        list_transfers
        ;;
    clean)
        clean_transfers
        ;;
    *)
        usage
        exit 1
        ;;
esac
```

#### Install CLI Tool
```bash
chmod +x ~/projects/Utility/LOGISTICAL/CloudSync/scripts/quick-transfer/transfer.sh

# Create alias in ~/.bash_aliases
echo "alias transfer='~/projects/Utility/LOGISTICAL/CloudSync/scripts/quick-transfer/transfer.sh'" >> ~/.bash_aliases
```

---

### **Phase 3: Documentation & Integration (Week 2)**

#### Step 3.1: Update CloudSync README

**Add section:**
```markdown
## Quick File Transfer

Fast cross-device file transfer using Git (formerly "Sink" project):

### Usage
```bash
# Device 1: Add files to transfer
transfer add ~/important-note.md
transfer add ~/scripts/useful-tool.sh
transfer send

# Device 2: Receive files
transfer receive
# Files available in: CloudSync/quick-transfer/temp/
transfer clean
```

### When to Use Quick Transfer vs Background Sync
- **Quick Transfer**: Ad-hoc file sharing, manual control, immediate needs
- **Background Sync**: Continuous directory sync, automated, scheduled backups
```

#### Step 3.2: Create Migration Documentation

**File:** `CloudSync/docs/SINK_MIGRATION.md`

**Contents:**
- Why Sink was merged into CloudSync
- Where Sink data was moved
- How to use new quick-transfer CLI
- Migration timeline and history

#### Step 3.3: Update Global Documentation

**Files to update:**
- `~/.bash_aliases` - Add `transfer` alias
- `~/docs/CORE/FILE_ORGANIZATION.md` - Remove Sink reference, add CloudSync/quick-transfer

---

### **Phase 4: Cleanup & Archive (Week 2-3)**

#### Step 4.1: Archive Original Sink Repository
```bash
# Verify migration successful
transfer list  # Should work from CloudSync

# Archive Sink
mv ~/projects/Utility/LOGISTICAL/Sink ~/projects/Archive/Sink-pre-merger-backup
```

#### Step 4.2: Update GitHub Remote

**Option A: Archive Sink repo on GitHub**
- Go to GitHub → Sink repository → Settings
- Scroll to "Danger Zone" → Archive repository

**Option B: Redirect to CloudSync**
- Update Sink README to say "Merged into CloudSync"
- Add link to CloudSync repository
- Keep repository active but frozen

---

## Rollback Plan

**If merger causes issues:**
```bash
# Restore original Sink
mv ~/projects/Archive/Sink-pre-merger-backup ~/projects/Utility/LOGISTICAL/Sink

# Remove quick-transfer from CloudSync
cd ~/projects/Utility/LOGISTICAL/CloudSync
git rm -r quick-transfer/
git rm scripts/quick-transfer/
git commit -m "Rollback Sink merger"
```

---

## Success Criteria

✅ **Migration Complete When:**
1. All Sink data accessible in CloudSync
2. `transfer` CLI command works from any directory
3. Quick-transfer workflow functions identically to Sink
4. Environment comparison data in cloudsync-managed/
5. Config backups integrated into CloudSync backup system
6. Original Sink repository archived
7. Documentation updated (CloudSync README, global docs)

---

## Alternative: Keep Sink Separate

**If user prefers to keep Sink independent:**

### **Reasons to Keep Separate:**
- Different mental model (Git-based vs rclone-based)
- Sink is intentionally minimal/lightweight
- Merging makes CloudSync too complex
- Prefer separate tools for separate workflows

### **If Keeping Separate:**
1. Add `.cloudsync-backup` integration to Sink
2. Sink auto-backs up to OneDrive via CloudSync hooks
3. Best of both worlds: lightweight Sink + persistent CloudSync backup

---

## Recommendation

🟢 **MERGE Sink into CloudSync** (Option A)

**Reasons:**
1. **Consolidation** - Reduces project count from 5 LOGISTICAL tools to 4
2. **Data belongs together** - Environment comparisons, configs = CloudSync managed data
3. **Simpler workflow** - One command (`transfer`) instead of cd + git add/commit/push
4. **Better backup** - Quick-transfer files automatically included in CloudSync backups
5. **Clearer purpose** - CloudSync = "All sync/transfer/backup needs"

---

**Next Steps:**
1. Review and approve merger plan
2. Begin Phase 1 (data migration)
3. Implement quick-transfer CLI
4. Test workflow on two devices
5. Archive original Sink repository
