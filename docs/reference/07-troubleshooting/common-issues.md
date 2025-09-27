# CloudSync Troubleshooting Guide

**Last Updated:** 2025-09-27

## Quick Diagnosis

**Symptom Checklist:**
- [ ] Scripts fail to execute
- [ ] rclone connectivity issues
- [ ] Sync operations hanging
- [ ] Conflict detection problems
- [ ] Performance degradation
- [ ] Configuration errors

## Common Issues

### Issue: Scripts Not Executing

**Symptoms:**
- `Permission denied` errors
- `command not found` errors
- Scripts exit immediately

**Likely Causes:**
- Scripts not executable
- Wrong working directory
- Missing dependencies

**Solution Steps:**
1. **Make scripts executable:**
   ```bash
   chmod +x scripts/core/*.sh
   chmod +x scripts/monitoring/*.sh
   ```

2. **Verify working directory:**
   ```bash
   cd /path/to/CloudSync
   pwd  # Should show CloudSync directory
   ```

3. **Check dependencies:**
   ```bash
   which rclone  # Should return path
   which jq      # Should return path
   bash --version  # Should be 4.0+
   ```

**Verification:** `./scripts/core/smart-dedupe.sh --help` should show help output

**Prevention:** Always run from CloudSync project root

---

### Issue: rclone Connectivity Problems

**Symptoms:**
- `Failed to create file system` errors
- `403 Forbidden` or `401 Unauthorized` errors
- Timeouts during remote operations

**Likely Causes:**
- Invalid credentials
- Expired authentication tokens
- Network connectivity issues
- Remote path doesn't exist

**Solution Steps:**
1. **Test basic connectivity:**
   ```bash
   rclone lsd onedrive:
   rclone about onedrive:
   ```

2. **Reconfigure if needed:**
   ```bash
   rclone config reconnect onedrive:
   # Or full reconfiguration:
   rclone config
   ```

3. **Check network:**
   ```bash
   ping 8.8.8.8
   curl -I https://graph.microsoft.com  # For OneDrive
   ```

4. **Verify remote path:**
   ```bash
   rclone lsd onedrive:DevEnvironment
   # Create if missing:
   rclone mkdir onedrive:DevEnvironment
   ```

**Verification:** `rclone ls onedrive:DevEnvironment` should list files or return empty

**Prevention:** Set up credential refresh automation

---

### Issue: Bidirectional Sync Hanging

**Symptoms:**
- `rclone bisync` operations never complete
- High CPU usage with no progress
- Scripts timeout after configured limits

**Likely Causes:**
- Large file transfers without progress updates
- Network interruptions
- Insufficient disk space
- rclone bisync state corruption

**Solution Steps:**
1. **Check available space:**
   ```bash
   df -h $HOME
   df -h ~/.cloudsync
   ```

2. **Reset bisync state:**
   ```bash
   ./scripts/core/bidirectional-sync.sh --resync --dry-run
   # If dry-run looks good:
   ./scripts/core/bidirectional-sync.sh --resync
   ```

3. **Test with smaller dataset:**
   ```bash
   ./scripts/core/bidirectional-sync.sh --local ~/test-small --dry-run
   ```

4. **Check for network issues:**
   ```bash
   # Monitor network during operation
   iftop  # or nethogs
   ```

**Verification:** Successful small-scale sync completion

**Prevention:** Regular bisync state maintenance, monitor disk space

---

### Issue: Conflicts Not Resolving

**Symptoms:**
- Conflict files remain after resolution attempts
- Auto-resolution strategies not working
- Interactive resolution failing

**Likely Causes:**
- File permission issues
- Incomplete conflict detection
- Strategy misconfiguration
- Remote file locks

**Solution Steps:**
1. **List all conflicts:**
   ```bash
   ./scripts/core/conflict-resolver.sh detect
   ./scripts/core/conflict-resolver.sh list
   ```

2. **Backup conflicts first:**
   ```bash
   ./scripts/core/conflict-resolver.sh backup --dry-run
   ./scripts/core/conflict-resolver.sh backup
   ```

3. **Try manual resolution:**
   ```bash
   # Find conflict files manually
   find $HOME -name "*.conflict" -o -name "*.sync-conflict*"

   # Resolve individually
   mv file.txt.conflict file.txt  # Keep conflict version
   # OR
   rm file.txt.conflict          # Keep original
   ```

4. **Check file permissions:**
   ```bash
   ls -la conflicted-file.txt*
   chmod 644 conflicted-file.txt  # Fix if needed
   ```

**Verification:** No conflicts in detection scan

**Prevention:** Regular conflict monitoring, proper file permissions

---

### Issue: Performance Degradation

**Symptoms:**
- Sync operations much slower than usual
- High resource usage (CPU/memory/network)
- Operations timing out

**Likely Causes:**
- Large number of small files
- Network bandwidth limitations
- Insufficient system resources
- Inefficient sync patterns

**Solution Steps:**
1. **Check system resources:**
   ```bash
   top
   df -h
   free -h
   iotop  # If available
   ```

2. **Use size-only checking:**
   ```bash
   ./scripts/core/checksum-verify.sh --size-only --local ~/large-dir
   ./scripts/core/bidirectional-sync.sh --compare size --local ~/large-dir
   ```

3. **Optimize exclusion patterns:**
   ```bash
   # Edit config/cloudsync.conf
   EXCLUDE_PATTERNS+=(
       "*.cache"
       ".git/objects/*"
       "node_modules/*"
       # Add more exclusions
   )
   ```

4. **Run deduplication:**
   ```bash
   ./scripts/core/smart-dedupe.sh --by-hash --stats
   ```

**Verification:** Operations complete within reasonable timeframes

**Prevention:** Regular deduplication, optimized exclude patterns

---

### Issue: Configuration Errors

**Symptoms:**
- `Configuration file not found` errors
- Scripts using wrong paths or remotes
- Inconsistent behavior across scripts

**Likely Causes:**
- Missing or corrupted configuration file
- Wrong working directory
- Configuration syntax errors

**Solution Steps:**
1. **Verify configuration file:**
   ```bash
   ls -la config/cloudsync.conf
   head -20 config/cloudsync.conf
   ```

2. **Test configuration loading:**
   ```bash
   source config/cloudsync.conf
   echo "Remote: $DEFAULT_REMOTE"
   echo "Path: $SYNC_BASE_PATH"
   ```

3. **Reset to defaults if needed:**
   ```bash
   cp config/cloudsync.conf.template config/cloudsync.conf
   # Edit with your settings
   ```

4. **Check syntax:**
   ```bash
   bash -n config/cloudsync.conf  # Check for syntax errors
   ```

**Verification:** All scripts load configuration without errors

**Prevention:** Version control configuration, regular backups

---

### Issue: Log File Analysis

**Symptoms:**
- Operations failing silently
- Need to understand what happened
- Debugging intermittent issues

**Solution Steps:**
1. **Check recent logs:**
   ```bash
   ls -la ~/.cloudsync/*.log
   tail -50 ~/.cloudsync/sync-health-check.log
   ```

2. **Monitor live operations:**
   ```bash
   tail -f ~/.cloudsync/bidirectional-sync.log &
   ./scripts/core/bidirectional-sync.sh --dry-run
   ```

3. **Search for specific errors:**
   ```bash
   grep -i error ~/.cloudsync/*.log
   grep -i fail ~/.cloudsync/*.log
   grep -i conflict ~/.cloudsync/*.log
   ```

4. **Check operation statistics:**
   ```bash
   cat ~/.cloudsync/last-bisync-stats.json | jq .
   ```

**Log Locations:**
- `~/.cloudsync/health-check.log` - Health monitoring
- `~/.cloudsync/bisync.log` - Bidirectional sync operations
- `~/.cloudsync/dedupe.log` - Deduplication operations
- `~/.cloudsync/checksum-verify.log` - Integrity verification
- `~/.cloudsync/conflict-resolver.log` - Conflict resolution

---

## Escalation Procedures

### When to Escalate
- Data loss or corruption suspected
- Security vulnerabilities discovered
- System-wide failures affecting multiple components
- Performance issues that can't be resolved with standard troubleshooting

### Information to Gather
1. **System Information:**
   ```bash
   uname -a
   rclone version
   bash --version
   ```

2. **Error Logs:**
   ```bash
   # Collect all relevant logs
   tar -czf cloudsync-logs-$(date +%Y%m%d).tar.gz ~/.cloudsync/*.log
   ```

3. **Configuration (sanitized):**
   ```bash
   # Remove sensitive data before sharing
   grep -v PASSWORD config/cloudsync.conf > config-sanitized.conf
   ```

4. **Operation Details:**
   - What operation was being performed
   - Expected vs actual behavior
   - Steps to reproduce
   - Any recent changes to configuration

### Emergency Contact Information
- **Data Recovery**: Restore from restic backup
- **System Recovery**: Restore configuration from git
- **Documentation**: Check project README and documentation

## Prevention Best Practices

### Regular Maintenance
1. **Weekly Health Checks:**
   ```bash
   ./scripts/monitoring/sync-health-check.sh
   ```

2. **Monthly Deduplication:**
   ```bash
   ./scripts/core/smart-dedupe.sh --by-hash
   ```

3. **Quarterly Verification:**
   ```bash
   ./scripts/core/checksum-verify.sh --combined
   ```

### Monitoring Setup
1. **Log Rotation:**
   ```bash
   # Add to crontab
   0 0 * * 0 find ~/.cloudsync -name "*.log" -mtime +30 -delete
   ```

2. **Health Monitoring:**
   ```bash
   # Add to crontab
   0 */6 * * * /path/to/CloudSync/scripts/monitoring/sync-health-check.sh
   ```

### Backup Strategy
1. **Configuration Backup:**
   ```bash
   cp config/cloudsync.conf config/cloudsync.conf.backup
   ```

2. **State Backup:**
   ```bash
   tar -czf ~/.cloudsync-backup-$(date +%Y%m%d).tar.gz ~/.cloudsync/
   ```

Remember: Always test solutions in a safe environment before applying to production data.