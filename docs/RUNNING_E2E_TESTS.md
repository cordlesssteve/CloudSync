# Running End-to-End Tests

**Status:** Ready to Execute
**Test User:** csync-tester (already created and configured)
**Repository:** Already cloned to /home/csync-tester/CloudSync

---

## Quick Start: Run the Test

### Step 1: Execute the E2E Test

```bash
sudo -u csync-tester -H bash -c 'cd ~/CloudSync && ./tests/integration/e2e-real-onedrive.test.sh'
```

### Step 2: Monitor Progress

The test will output in real-time to console:
- ✓ Green text = SUCCESS operations
- ✗ Red text = ERROR conditions
- ⚠ Yellow text = WARNING messages
- Blue text = DEBUG information

### Step 3: Review Logs After Completion

Logs are automatically saved to: `~/.cloudsync-test/logs/`

```bash
# View human-readable log
tail -50 ~/.cloudsync-test/logs/test-run-*.log

# View JSON structured logs
jq '.' ~/.cloudsync-test/logs/test-run-*.jsonl | head -50

# View test artifacts
ls -lh ~/.cloudsync-test/logs/test-run-*-artifacts/

# View HTML report (if available)
firefox ~/.cloudsync-test/exports/test-report-*.html
```

---

## What the Test Does

### Full Workflow (7 Steps)

**STEP 1: Create Test Repository**
- Creates fake git repo with 5 text files, binary data, nested directories
- Creates branches (main, develop)
- Multiple commits with varied content
- Logs repository statistics (commits, branches, size)

**STEP 2: Create Bundle**
- Runs `git bundle create --all`
- Logs bundle size and SHA256 checksum
- Verifies bundle integrity with `git bundle verify`

**STEP 3: Upload to OneDrive**
- REAL upload via `rclone sync` to OneDrive
- Path: `CloudSync-Testing/test-YYYY-MM-DD-HHMMSS-PID`
- Logs each file operation
- Verifies OneDrive path creation

**STEP 4: Download as csync-tester**
- csync-tester user downloads from OneDrive
- Logs download size and SHA256 checksum
- **Verifies checksums match** (bit-identical confirmation)
- Confirms size matches original

**STEP 5: Restore Repository**
- csync-tester runs `git clone bundle restored-repo`
- Runs `git fsck --full` to verify integrity
- Logs restored repository statistics

**STEP 6: Verify Integrity**
- Compares original vs restored commit counts
- Compares file structure listings
- Generates diff report (should be empty)

**STEP 7: Final Validation**
- Verifies restored repo is readable (`git log`)
- Compares branch counts
- Validates all git objects are present

### Automatic Cleanup

When test completes (success or failure):
1. **Deletes from OneDrive:** `CloudSync-Testing/test-*` directory
2. **Deletes local temp:** `/tmp/cloudsync-e2e-*` directory
3. **Preserves logs:** All logs and artifacts kept in `~/.cloudsync-test/`

---

## Expected Output

### Successful Test Output

```
================================================================================
CloudSync Test Suite: End-to-End CloudSync Test (Real OneDrive)
Test Run ID: 2025-10-16-130922-12345
Started: 2025-10-16T13:09:22+00:00
User: csync-tester
Host: DESKTOP-OO6C62K
================================================================================

[2025-10-16T13:09:22+00:00] [INFO] [STEP_1] Creating test repository...
[2025-10-16T13:09:22+00:00] [INFO] [STEP_1] Initializing git repository
[2025-10-16T13:09:22+00:00] [INFO] [STEP_1] Creating test files...
[2025-10-16T13:09:23+00:00] [INFO] [STEP_1] Creating binary test data...
[2025-10-16T13:09:25+00:00] [INFO] [STEP_1] Creating git branches...
[2025-10-16T13:09:25+00:00] [INFO] [GIT] Source Repository statistics: commits=7 branches=2 tags=0 size=...
[2025-10-16T13:09:25+00:00] [SUCCESS] [STEP_1] Step completed with status: SUCCESS (2.34s)

[2025-10-16T13:09:25+00:00] [INFO] [STEP_2] Creating git bundle from source repository...
[2025-10-16T13:09:26+00:00] [FILE] [create] /tmp/cloudsync-e2e-12345/test-repo.bundle (2.1 MB) [SHA256: abc123...]
[2025-10-16T13:09:26+00:00] [SUCCESS] [STEP_2] Bundle integrity verified
[2025-10-16T13:09:26+00:00] [SUCCESS] [STEP_2] Step completed with status: SUCCESS (1.15s)

[2025-10-16T13:09:26+00:00] [INFO] [STEP_3] Uploading bundle to OneDrive...
[2025-10-16T13:09:26+00:00] [INFO] [STEP_3] OneDrive path: CloudSync-Testing/test-2025-10-16-130922-12345
[2025-10-16T13:09:45+00:00] [SUCCESS] [STEP_3] Bundle uploaded to OneDrive
[2025-10-16T13:09:46+00:00] [SUCCESS] [STEP_3] Step completed with status: SUCCESS (19.4s)

[2025-10-16T13:09:46+00:00] [INFO] [STEP_4] Downloading bundle as csync-tester user...
[2025-10-16T13:10:05+00:00] [SUCCESS] [STEP_4] Bundle downloaded by csync-tester
[2025-10-16T13:10:05+00:00] [SUCCESS] [STEP_4] Checksum match [BUNDLE_INTEGRITY]: abc123...
[2025-10-16T13:10:05+00:00] [SUCCESS] [STEP_4] Size verification passed: 2.1 MB
[2025-10-16T13:10:05+00:00] [SUCCESS] [STEP_4] Step completed with status: SUCCESS (19.1s)

[2025-10-16T13:10:05+00:00] [INFO] [STEP_5] Restoring repository as csync-tester...
[2025-10-16T13:10:15+00:00] [SUCCESS] [STEP_5] Repository restored
[2025-10-16T13:10:15+00:00] [SUCCESS] [STEP_5] Restored repository integrity verified
[2025-10-16T13:10:15+00:00] [SUCCESS] [STEP_5] Step completed with status: SUCCESS (10.2s)

[2025-10-16T13:10:15+00:00] [INFO] [STEP_6] Verifying repository integrity...
[2025-10-16T13:10:16+00:00] [SUCCESS] [STEP_6] Commit count match: 7 commits
[2025-10-16T13:10:16+00:00] [SUCCESS] [STEP_6] File structures are identical
[2025-10-16T13:10:16+00:00] [SUCCESS] [STEP_6] Step completed with status: SUCCESS (1.1s)

[2025-10-16T13:10:16+00:00] [INFO] [STEP_7] Performing final validation...
[2025-10-16T13:10:17+00:00] [SUCCESS] [STEP_7] Restored repository is readable
[2025-10-16T13:10:17+00:00] [SUCCESS] [STEP_7] Branch count match: 2 branches
[2025-10-16T13:10:17+00:00] [SUCCESS] [STEP_7] Step completed with status: SUCCESS (0.9s)

[2025-10-16T13:10:17+00:00] [SUCCESS] [OVERALL] All test steps completed successfully!
[2025-10-16T13:10:17+00:00] [INFO] [OVERALL] End-to-end workflow verification: PASSED

[2025-10-16T13:10:17+00:00] [INFO] [CLEANUP] Starting cleanup phase...
[2025-10-16T13:10:17+00:00] [INFO] [CLEANUP] Deleting OneDrive test path: CloudSync-Testing/test-2025-10-16-130922-12345
[2025-10-16T13:10:35+00:00] [SUCCESS] [CLEANUP] OneDrive test path deleted
[2025-10-16T13:10:35+00:00] [SUCCESS] [CLEANUP] Test cleanup complete

================================================================================
Test Summary
================================================================================
Status: SUCCESS
Steps: 7/7 passed (100%)
Completed: 2025-10-16T13:10:35+00:00

Logs:
  Human-readable: /home/cordlesssteve/.cloudsync-test/logs/test-run-2025-10-16-130922-12345.log
  JSON structured: /home/cordlesssteve/.cloudsync-test/logs/test-run-2025-10-16-130922-12345.jsonl
  Artifacts: /home/cordlesssteve/.cloudsync-test/logs/test-run-2025-10-16-130922-12345-artifacts
================================================================================
```

---

## Verification Gates (All Must Pass)

✓ **Bundle Creation Gate**
- Bundle file created
- Bundle format is valid
- Bundle integrity verified with `git bundle verify`

✓ **Upload Gate**
- Bundle uploaded to OneDrive
- OneDrive path verified to exist
- File size matches uploaded

✓ **Download Gate**
- Bundle downloaded from OneDrive
- Checksum matches original (bit-identical)
- Size matches original

✓ **Restore Gate**
- Repository cloned from bundle
- `git fsck --full` passes
- All commits present

✓ **Integrity Gate**
- Commit counts match
- File structures identical
- Branches present

---

## Troubleshooting

### Test Fails at STEP 3 (Upload)

**Symptom:** `rclone sync` fails to OneDrive

**Causes:**
- rclone not configured for OneDrive
- Authentication token expired
- OneDrive storage quota exceeded
- Network connectivity issue

**Solution:**
```bash
# Test rclone connectivity
rclone listremotes

# Verify OneDrive remote
rclone lsf onedrive: --max-items 5

# Check authentication
rclone authorize onedrive
```

### Test Fails at STEP 4 (Download)

**Symptom:** csync-tester cannot download from OneDrive

**Causes:**
- csync-tester doesn't have rclone config
- OneDrive authentication not shared
- File permissions issue

**Solution:**
```bash
# Verify csync-tester has rclone config
sudo -u csync-tester rclone listremotes

# If missing, copy from your user:
sudo cp ~/.config/rclone/rclone.conf /home/csync-tester/.config/rclone/
sudo chown csync-tester:csync-tester /home/csync-tester/.config/rclone/rclone.conf
```

### Test Fails at STEP 5 (Restore)

**Symptom:** `git clone bundle` fails

**Causes:**
- Bundle corrupted during transfer
- Git not installed in csync-tester environment
- Insufficient disk space

**Solution:**
```bash
# Verify git is available to csync-tester
sudo -u csync-tester which git

# Check disk space
df -h /tmp

# Manually test bundle restore
sudo -u csync-tester bash -c 'cd /tmp && git clone /path/to/bundle.bundle test'
```

### Bundle Checksum Mismatch

**Symptom:** Checksums don't match between original and downloaded

**This indicates data corruption during upload/download**

**Debug:**
```bash
# Check OneDrive file
rclone lsf onedrive:CloudSync-Testing/test-* --checksums

# Compare sizes
ls -lh original.bundle
rclone ls onedrive:CloudSync-Testing/test-2025-10-16-130922-12345
```

---

## Test Performance

**Expected Duration:** 60-90 seconds total
- STEP 1 (Create): 2-3 seconds
- STEP 2 (Bundle): 1-2 seconds
- STEP 3 (Upload): 15-25 seconds (depends on OneDrive speed)
- STEP 4 (Download): 15-25 seconds (depends on OneDrive speed)
- STEP 5 (Restore): 5-10 seconds
- STEP 6 (Verify): 1-2 seconds
- STEP 7 (Final): 1-2 seconds
- Cleanup: 15-20 seconds

---

## Success Criteria

All of these must pass:

- [ ] STEP 1: Repository created with 7+ commits
- [ ] STEP 2: Bundle created and verified
- [ ] STEP 3: Bundle uploaded to OneDrive (verify via rclone ls)
- [ ] STEP 4: Bundle downloaded (checksums match exactly)
- [ ] STEP 5: Repository restored and readable
- [ ] STEP 6: Commit counts match (7 commits before and after)
- [ ] STEP 7: All validation checks pass
- [ ] Cleanup: OneDrive test path deleted

**When ALL steps show SUCCESS:** System is verified production-ready.

---

## What This Proves

✓ **End-to-end workflow works:** Bundle → Upload → Download → Restore
✓ **Data integrity:** Checksums verify bit-identical transfers
✓ **OneDrive interaction:** Real cloud storage works
✓ **User isolation:** csync-tester can independently verify restore
✓ **Git integrity:** Restored repos pass `git fsck`
✓ **Disaster recovery:** Proven ability to recover from bundles

---

## Next Steps After Successful Test

1. **Review logs:** Examine `~/.cloudsync-test/logs/` for any warnings
2. **Update CURRENT_STATUS.md:** Document test success
3. **Run additional tests:** Test with larger repos, different file types
4. **Production validation:** Run test with real production repos
5. **Schedule automated:** Set up cron job for periodic verification

---

## Questions or Issues?

Check the logs first:
```bash
grep ERROR ~/.cloudsync-test/logs/test-run-*.log
grep WARN ~/.cloudsync-test/logs/test-run-*.log
```

Review structured logs:
```bash
jq '.[] | select(.level=="ERROR" or .level=="WARN")' ~/.cloudsync-test/logs/test-run-*.jsonl
```
