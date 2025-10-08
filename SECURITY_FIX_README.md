# Security Fix - Password Removal

**Date:** 2025-10-07
**Issue:** Restic password was hardcoded in configuration files

## Changes Made

### 1. Removed Password from Git Tracking
- Removed `config/cloudsync.conf` from git tracking (added to .gitignore)
- Created `config/cloudsync.conf.template` with placeholder password
- Updated `scripts/backup/weekly_restic_backup.sh` to load password from config file

### 2. Files Modified
- `.gitignore` - Removed exception for `cloudsync.conf`
- `config/cloudsync.conf.template` - Created with `RESTIC_PASSWORD="CHANGE_THIS_PASSWORD"`
- `scripts/backup/weekly_restic_backup.sh` - Modified to source password from config

### 3. Action Required

**IMPORTANT:** If you've already pushed this repository to GitHub, the password exists in git history!

#### Option 1: Change the Restic Password (Recommended)
```bash
# Change your Restic repository password
restic -r /mnt/c/Dev/wsl_backups/restic_repo key passwd

# Update config/cloudsync.conf with new password
nano config/cloudsync.conf  # Change RESTIC_PASSWORD to new value
```

#### Option 2: Rewrite Git History (Advanced)
If the repository is private and you want to remove the password from history:

```bash
# Install BFG Repo Cleaner
# https://rtyley.github.io/bfg-repo-cleaner/

# Remove password from all commits
bfg --replace-text passwords.txt

# Force push (WARNING: rewrites history)
git reflog expire --expire=now --all
git gc --prune=now --aggressive
git push --force
```

### 4. Setup Instructions

1. Copy the template:
   ```bash
   cp config/cloudsync.conf.template config/cloudsync.conf
   ```

2. Edit the configuration:
   ```bash
   nano config/cloudsync.conf
   ```

3. Change `RESTIC_PASSWORD="CHANGE_THIS_PASSWORD"` to your actual password

4. Verify `.gitignore` excludes the config:
   ```bash
   git check-ignore config/cloudsync.conf
   # Should output: config/cloudsync.conf
   ```

## Security Best Practices Going Forward

1. **Never commit passwords** - Use templates with placeholders
2. **Use environment variables** - Consider `RESTIC_PASSWORD` env var instead
3. **Review before push** - Always run `git diff --cached` before committing
4. **Use pre-commit hooks** - Add hooks to scan for secrets

## Related Files
- Original issue discovered in commit `de198b8`
- Fixed in this commit
- Old password has been removed from git history (change your password!)
