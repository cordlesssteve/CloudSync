#!/bin/bash
# Claude Conversation Sync Script (DEPRECATED with symlink setup)
# Originally managed conversation sync between local and shared storage
# NOTE: With symlink setup, most functions are redundant as files are already in Sync/

CLAUDE_DIR="$HOME/.claude"
SYNC_DIR="$HOME/Sync/claude-conversations"
ARCHIVE_DAYS=7  # Archive conversations older than 7 days

# Ensure directories exist
mkdir -p "$SYNC_DIR/archive"

# Function to archive old conversations
archive_old_conversations() {
    echo "Archiving conversations older than $ARCHIVE_DAYS days..."
    
    find "$CLAUDE_DIR/projects" -name "*.jsonl" -mtime +$ARCHIVE_DAYS -print0 | while IFS= read -r -d '' file; do
        # Create relative path for archive
        rel_path="${file#$CLAUDE_DIR/}"
        archive_path="$SYNC_DIR/archive/$rel_path"
        
        # Ensure archive directory exists
        mkdir -p "$(dirname "$archive_path")"
        
        # Move to archive
        mv "$file" "$archive_path"
        echo "Archived: $rel_path"
    done
}

# Function to restore conversation by session ID
restore_conversation() {
    local session_id="$1"
    if [[ -z "$session_id" ]]; then
        echo "Usage: $0 restore <session-id>"
        return 1
    fi
    
    # Find conversation in archive
    find "$SYNC_DIR/archive" -name "*${session_id}*.jsonl" -exec cp {} "$CLAUDE_DIR/projects/" \;
    echo "Restored conversation: $session_id"
}

# Main command handling
case "$1" in
    "archive")
        archive_old_conversations
        ;;
    "restore")
        restore_conversation "$2"
        ;;
    "sync-db")
        # Force sync the database (if needed)
        echo "Database now stored directly in Sync location: ${HOME}/Sync/conversations.db"
        ;;
    *)
        echo "Usage: $0 {archive|restore <session-id>|sync-db}"
        echo "  archive: Move old conversations to shared archive (DEPRECATED with symlinks)"
        echo "  restore: Restore specific conversation from archive (DEPRECATED with symlinks)"
        echo "  sync-db: Manually sync conversation database (still useful)"
        echo ""
        echo "NOTE: With symlink setup, conversation files are automatically synced."
        echo "Only sync-db function remains relevant for search database synchronization."
        ;;
esac