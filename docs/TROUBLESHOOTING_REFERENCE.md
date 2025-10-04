# CloudSync Troubleshooting Reference
**Version:** 2.0 | **Status:** Production Ready | **Date:** 2025-10-04

---

## 🚨 Common Issues & Solutions

### 1. **File Won't Add**

#### Symptoms
- `cloudsync add file.txt` fails or hangs
- "Permission denied" errors
- File appears to add but doesn't show in status

#### Diagnosis
```bash
# Check file permissions
ls -la file.txt

# Analyze decision engine
cloudsync analyze file.txt

# Check with verbose mode
CLOUDSYNC_VERBOSE=true cloudsync add file.txt

# Check if file already exists in system
cloudsync status file.txt
```

#### Solutions
```bash
# Fix permissions
chmod 644 file.txt

# Force to managed storage
cloudsync managed-add file.txt

# Use absolute path
cloudsync add /full/path/to/file.txt

# Check disk space
df -h ~/cloudsync-managed
```

---

### 2. **Sync Failures**

#### Symptoms
- `cloudsync sync` hangs or times out
- "Remote not accessible" errors
- Partial syncs complete but some files missing

#### Diagnosis
```bash
# Test remote connectivity
rclone lsd onedrive:

# Check Git-Annex remote
cd ~/cloudsync-managed
git annex testremote onedrive

# Check rclone config
rclone config show onedrive

# Check network connectivity
ping 8.8.8.8
```

#### Solutions
```bash
# Re-authenticate rclone
rclone config reconnect onedrive

# Manual Git sync
cd ~/cloudsync-managed
git pull --rebase
git push

# Manual Git-Annex sync
git annex sync --content

# Force content retrieval
git annex get . --force

# Check and fix remote path
rclone mkdir onedrive:DevEnvironment/managed
```

---

### 3. **Version History Missing**

#### Symptoms
- `cloudsync status` shows "No history found"
- Git log is empty for file
- Rollback commands fail

#### Diagnosis
```bash
# Check Git repository status
cd ~/cloudsync-managed
git status
git log --oneline

# For Git-Annex files
git annex log filename.bin

# Check if file is tracked
git ls-files filename.txt
git annex find filename.bin
```

#### Solutions
```bash
# Re-add file to create history
cloudsync add filename.txt

# Fix Git repository issues
cd ~/cloudsync-managed
git fsck
git gc

# Reinitialize if corrupted
mv ~/cloudsync-managed ~/cloudsync-managed.backup
cloudsync managed-init
# Then re-add files from backup
```

---

### 4. **Large File Issues**

#### Symptoms
- Large files fail to add
- Git-Annex operations timeout
- "No space left on device" errors

#### Diagnosis
```bash
# Check disk space
df -h ~/cloudsync-managed
df -h ~/.git/annex

# Check Git-Annex status
cd ~/cloudsync-managed
git annex status

# Check content availability
git annex whereis large-file.bin

# Check upload progress
git annex info onedrive
```

#### Solutions
```bash
# Clean up unused content
git annex unused
git annex dropunused all

# Increase timeout
echo 'OPERATION_TIMEOUT="600"' >> config/managed-storage.conf

# Force content transfer
git annex copy large-file.bin --to onedrive --force

# Use chunked transfers
echo 'ANNEX_CHUNK_SIZE="10MiB"' >> config/managed-storage.conf

# Manual cleanup
git annex fsck --fast
```

---

### 5. **Conflict Resolution Issues**

#### Symptoms
- Conflicts detected but resolution fails
- Interactive prompts hang
- Backup verification errors

#### Diagnosis
```bash
# Detect conflicts
./scripts/core/conflict-resolver.sh detect

# List conflicts
./scripts/core/conflict-resolver.sh list

# Check conflict resolver logs
tail -f ~/.cloudsync/conflict-resolver.log

# Test with dry run
./scripts/core/conflict-resolver.sh auto-resolve --strategy newer --dry-run
```

#### Solutions
```bash
# Manual conflict resolution
./scripts/core/conflict-resolver.sh resolve

# Force backup
./scripts/core/conflict-resolver.sh backup

# Use specific strategy
./scripts/core/conflict-resolver.sh auto-resolve --strategy local

# Reset conflict state
rm ~/.cloudsync/conflicts/detected-conflicts.txt
./scripts/core/conflict-resolver.sh detect
```

---

### 6. **Performance Issues**

#### Symptoms
- Operations take very long time
- High CPU or memory usage
- Frequent timeouts

#### Diagnosis
```bash
# Check system resources
top
htop
df -h

# Check operation logs
tail -f ~/.cloudsync/logs/orchestrator.log

# Performance test
time cloudsync analyze test-file.txt

# Check concurrent operations
ps aux | grep -E "(git|rclone|git-annex)"
```

#### Solutions
```bash
# Reduce concurrent operations
echo 'MAX_CONCURRENT_OPS="1"' >> config/managed-storage.conf

# Increase timeouts
echo 'OPERATION_TIMEOUT="600"' >> config/managed-storage.conf

# Enable bandwidth limiting
echo 'BANDWIDTH_LIMIT="10M"' >> config/managed-storage.conf

# Clean up processes
pkill -f "git annex"
pkill -f "rclone"

# Restart operations
cloudsync sync
```

---

## 🛠️ Diagnostic Commands

### System Health Check
```bash
# Comprehensive system check
./scripts/health-check.sh

# Test all components
./test-orchestrator.sh

# Check dependencies
command -v git && echo "✅ Git installed"
command -v rclone && echo "✅ rclone installed"  
command -v git-annex && echo "✅ git-annex installed"
```

### Configuration Validation
```bash
# Check configuration
cloudsync managed-status

# Validate config file
bash -n config/managed-storage.conf

# Show effective configuration
set | grep -E "^(REMOTE_|GIT_|LARGE_|CLOUDSYNC_)"
```

### Log Analysis
```bash
# View recent operations
tail -50 ~/.cloudsync/logs/orchestrator.log

# Search for errors
grep -i error ~/.cloudsync/logs/*.log

# Monitor real-time
tail -f ~/.cloudsync/logs/orchestrator.log

# Log rotation check
find ~/.cloudsync/logs -name "*.log" -mtime +30
```

---

## 🔧 Advanced Troubleshooting

### Git Repository Issues
```bash
# Check repository integrity
cd ~/cloudsync-managed
git fsck --full

# Fix common Git issues
git gc --aggressive
git repack -ad

# Reset to last known good state
git reflog
git reset --hard <commit-hash>

# Rebuild index if corrupted
rm .git/index
git reset
```

### Git-Annex Specific Issues
```bash
# Check Git-Annex integrity
git annex fsck

# Repair Git-Annex
git annex repair

# Fix location tracking
git annex fsck --fast

# Reinitialize remote
git annex initremote onedrive

# Check remote availability
git annex testremote onedrive --fast
```

### Network and Remote Issues
```bash
# Test rclone operations
rclone ls onedrive:DevEnvironment/managed --max-depth 1

# Check authentication
rclone config show onedrive

# Test transfer speed
rclone test speed onedrive:DevEnvironment/test --download

# Refresh authentication
rclone config reconnect onedrive
```

---

## 🚨 Emergency Recovery Procedures

### 1. **Complete System Reset**
```bash
# Backup current state
cp -r ~/cloudsync-managed ~/cloudsync-managed.emergency-backup
tar -czf ~/cloudsync-backup-$(date +%Y%m%d).tar.gz ~/cloudsync-managed

# Reinitialize system
rm -rf ~/cloudsync-managed
cloudsync managed-init

# Restore files (without history)
cp -r ~/cloudsync-managed.emergency-backup/* ~/cloudsync-managed/
cloudsync add ~/cloudsync-managed/*/*
```

### 2. **Remote Storage Corruption**
```bash
# Create new remote location
rclone mkdir onedrive:DevEnvironment/managed-new

# Update configuration
sed -i 's|DevEnvironment/managed|DevEnvironment/managed-new|' config/managed-storage.conf

# Force full sync
cloudsync sync . push
```

### 3. **Lost Version History**
```bash
# Check Git reflog
cd ~/cloudsync-managed
git reflog

# Recover from reflog
git checkout <commit-hash>
git branch recovery-$(date +%Y%m%d)

# Import from remote if available
git pull origin main --allow-unrelated-histories
```

---

## 📋 Prevention Checklist

### Daily Operations
- [ ] Run `cloudsync sync` at least once
- [ ] Check `cloudsync managed-status` for warnings
- [ ] Monitor disk space usage

### Weekly Maintenance
- [ ] Run `./scripts/core/conflict-resolver.sh detect`
- [ ] Check logs for errors: `grep -i error ~/.cloudsync/logs/*.log`
- [ ] Verify remote connectivity: `rclone lsd onedrive:`

### Monthly Maintenance
- [ ] Run `git annex fsck` for integrity check
- [ ] Clean old logs: `find ~/.cloudsync/logs -name "*.log" -mtime +30 -delete`
- [ ] Update configuration if needed
- [ ] Test recovery procedures

### Before Major Changes
- [ ] Create backup: `tar -czf ~/cloudsync-backup-$(date +%Y%m%d).tar.gz ~/cloudsync-managed`
- [ ] Test with `CLOUDSYNC_DRY_RUN=true`
- [ ] Verify remote authentication
- [ ] Document configuration changes

---

## 📞 Getting Help

### Support Resources
- **Full Guide**: `docs/CLOUDSYNC_USAGE_GUIDE.md`
- **Quick Reference**: `docs/QUICK_REFERENCE.md`
- **Log Files**: `~/.cloudsync/logs/`
- **Configuration**: `config/managed-storage.conf`

### Debug Information to Collect
```bash
# System information
uname -a
df -h
git --version
rclone version
git annex version

# CloudSync status
cloudsync managed-status
CLOUDSYNC_VERBOSE=true cloudsync analyze problematic-file.txt

# Recent logs
tail -100 ~/.cloudsync/logs/orchestrator.log
```

### Contact Points
- Check configuration with `cloudsync managed-status`
- Review logs in `~/.cloudsync/logs/`
- Test components with `./test-orchestrator.sh`

---

**🎯 Most issues are resolved by checking permissions, connectivity, and using verbose mode for detailed diagnostics.**