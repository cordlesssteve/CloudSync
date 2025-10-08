# CloudSync Notifications and Monitoring Guide

**Last Updated:** 2025-10-07
**CloudSync Version:** 2.0+

## Overview

CloudSync includes a comprehensive notification and monitoring system to keep you informed about sync operations, backup status, and disaster recovery readiness.

## Table of Contents

- [Notification System](#notification-system)
- [Restore Verification](#restore-verification)
- [Configuration](#configuration)
- [Monitoring Commands](#monitoring-commands)
- [Troubleshooting](#troubleshooting)

---

## Notification System

### Features

The notification system provides multi-backend support for:
- **ntfy.sh** - Free push notifications to your phone (no account needed)
- **Webhooks** - Integration with Slack, Discord, or custom endpoints
- **Email** - Traditional email notifications

### Quick Start

1. **Configure notification backends:**
   ```bash
   nano ~/projects/Utility/LOGISTICAL/CloudSync/config/notifications.conf
   ```

2. **Enable your preferred backend(s):**
   - Set `ENABLE_NTFY=true` for push notifications
   - Set `ENABLE_WEBHOOK=true` for webhook integration
   - Set `ENABLE_EMAIL=true` for email notifications

3. **Test notifications:**
   ```bash
   ~/projects/Utility/LOGISTICAL/CloudSync/scripts/notify.sh success "Test" "It works!"
   ```

### ntfy.sh Setup (Recommended)

**Why ntfy.sh?**
- No account required
- Free push notifications to your phone
- Works with iOS and Android
- Simple HTTP-based API

**Setup Steps:**

1. **Choose a unique topic name:**
   ```
   cloudsync_$(hostname)_$(whoami)
   ```
   Example: `cloudsync_myserver_steve`

2. **Install ntfy app on your phone:**
   - iOS: Download from App Store
   - Android: Download from Google Play or F-Droid

3. **Subscribe to your topic in the app:**
   - Open ntfy app
   - Tap "+" to add subscription
   - Enter your topic name

4. **Configure CloudSync:**
   Edit `config/notifications.conf`:
   ```bash
   ENABLE_NTFY=true
   NTFY_TOPIC=cloudsync_myserver_steve
   ```

5. **Test it:**
   ```bash
   ~/projects/Utility/LOGISTICAL/CloudSync/scripts/notify.sh success "Setup Complete" "CloudSync notifications are working!"
   ```

You should receive a push notification on your phone!

### Webhook Setup (Slack/Discord)

**For Slack:**

1. Create an Incoming Webhook in your Slack workspace:
   - Go to https://api.slack.com/apps
   - Create a new app
   - Enable Incoming Webhooks
   - Create a webhook URL

2. Configure CloudSync:
   ```bash
   ENABLE_WEBHOOK=true
   WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
   ```

**Note:** Slack expects a specific JSON format. You may need to create a proxy endpoint to transform the CloudSync payload.

**For Discord:**

1. Create a webhook in Discord:
   - Server Settings → Integrations → Webhooks
   - Create webhook and copy URL

2. Configure CloudSync:
   ```bash
   ENABLE_WEBHOOK=true
   WEBHOOK_URL=https://discord.com/api/webhooks/YOUR/WEBHOOK/URL
   ```

**Note:** Discord also expects a specific JSON format. Consider creating a proxy endpoint.

### Email Setup

**Requirements:**
- `mail` or `mailx` command must be installed and configured
- Common packages: `mailutils` (Debian/Ubuntu), `mailx` (RHEL/CentOS)

**Configuration:**
```bash
ENABLE_EMAIL=true
EMAIL_TO=your-email@example.com
EMAIL_FROM=cloudsync@$(hostname)
```

### Notification Severity Levels

CloudSync uses four severity levels:

| Severity | Icon | Usage | Priority |
|----------|------|-------|----------|
| `info` | ℹ️ | Informational messages | Low |
| `success` | ✅ | Successful operations | Default |
| `warning` | ⚠️ | Warning conditions | High |
| `error` | ❌ | Error conditions | Urgent |

**Configure minimum severity:**
```bash
# Only send success, warning, and error notifications (skip info)
MIN_SEVERITY=success

# Only send warning and error notifications
MIN_SEVERITY=warning

# Only send error notifications
MIN_SEVERITY=error
```

### Manual Notification Usage

Send notifications from scripts or command line:

```bash
# Success notification
./scripts/notify.sh success "Sync Complete" "All 51 repositories synced successfully"

# Error notification
./scripts/notify.sh error "Sync Failed" "Bundle creation failed for repo XYZ"

# Warning notification
./scripts/notify.sh warning "Large Repo" "Repository size exceeds 500MB"

# Info notification (may be filtered by MIN_SEVERITY)
./scripts/notify.sh info "Starting Sync" "Beginning daily bundle sync"
```

### Automated Notifications

CloudSync automatically sends notifications for:

1. **Daily Bundle Sync (1 AM)**
   - ✅ Success: "CloudSync: Bundle Sync Complete"
   - ❌ Error: "CloudSync: Bundle Sync Failed"

2. **Weekly Restore Verification (Sundays 4:30 AM)**
   - ✅ Success: "CloudSync: Restore Verification Passed"
   - ❌ Error: "CloudSync: Restore Verification Failed"

---

## Restore Verification

### Overview

The restore verification system automatically tests your disaster recovery capability by restoring repositories from bundles to a temporary directory and validating the restoration.

### What It Tests

1. **Small Repository Restore**
   - Full bundle restoration
   - Git repository validity
   - Commit history integrity

2. **Medium/Large Repository Restore**
   - Incremental bundle chain verification
   - All bundle files present
   - Proper bundle sequencing

3. **Critical Ignored Files**
   - Restoration of .gitignored sensitive files
   - Archive integrity

### Running Restore Verification

**Automated (Recommended):**
- Runs automatically every Sunday at 4:30 AM
- Tests up to 5 repositories
- Sends notifications on completion/failure
- Results logged to `~/.cloudsync/logs/restore-verification.log`

**Manual Testing:**

```bash
# Run full verification suite
~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/verify-restore.sh

# Test limited number of repos
~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/verify-restore.sh --max-repos 3

# Skip large repos (faster testing)
~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/verify-restore.sh --no-large

# Keep test directory for inspection
~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/verify-restore.sh --no-cleanup

# Get help
~/projects/Utility/LOGISTICAL/CloudSync/scripts/bundle/verify-restore.sh --help
```

### Understanding Test Results

**Sample Output:**
```
[2025-10-07 21:42:16] ==========================================
[2025-10-07 21:42:16] CloudSync Restore Verification Test Suite
[2025-10-07 21:42:16] ==========================================
[2025-10-07 21:42:16] Start time: Tue Oct  7 21:42:16 CDT 2025
[2025-10-07 21:42:16] Test directory: /tmp/cloudsync-restore-test-964248

ℹ === Test Suite 1: Small Repository Restore ===
ℹ Testing restore: Archive/meiosis-crewai-js (small repo)
✓ Archive/meiosis-crewai-js: Restored successfully in 0s (11 commits)
ℹ Testing critical ignored files: Archive/meiosis-crewai-js
ℹ Archive/meiosis-crewai-js: No critical ignored files to test

[2025-10-07 21:42:16] ==========================================
[2025-10-07 21:42:16] Restore Verification Summary
[2025-10-07 21:42:16] ==========================================
[2025-10-07 21:42:16] Total tests run: 6
[2025-10-07 21:42:16] Passed: 3
[2025-10-07 21:42:16] Failed: 0
[2025-10-07 21:42:16] Warnings: 0
```

**Test Result Indicators:**
- ✓ (Green) - Test passed
- ✗ (Red) - Test failed
- ⚠ (Yellow) - Warning (partial success or non-critical issue)
- ℹ (Blue) - Information

### Restore Verification Schedule

**Weekly Schedule:**
- Runs every Sunday at 4:30 AM
- After weekly backup suite (2:30 AM)
- Tests 5 random repositories
- Sends success/failure notification
- Logs results to `~/.cloudsync/logs/restore-verification.log`

**Modify schedule:**
```bash
crontab -e

# Change from:
30 4 * * 0 .../verify-restore.sh --max-repos 5

# To run daily at 5 AM:
0 5 * * * .../verify-restore.sh --max-repos 3
```

---

## Configuration

### Notification Configuration File

**Location:** `~/projects/Utility/LOGISTICAL/CloudSync/config/notifications.conf`

**Key Settings:**

```bash
# Global enable/disable
ENABLE_NOTIFICATIONS=true

# Minimum severity (info, success, warning, error)
MIN_SEVERITY=success

# ntfy.sh
ENABLE_NTFY=false
NTFY_URL=https://ntfy.sh
NTFY_TOPIC=

# Webhooks
ENABLE_WEBHOOK=false
WEBHOOK_URL=

# Email
ENABLE_EMAIL=false
EMAIL_TO=
EMAIL_FROM=cloudsync@$(hostname)
```

### Environment Variables

You can override configuration via environment variables:

```bash
# Temporarily disable notifications
ENABLE_NOTIFICATIONS=false ./scripts/bundle/cron-wrapper.sh

# Change severity threshold for one run
MIN_SEVERITY=error ./scripts/bundle/verify-restore.sh
```

---

## Monitoring Commands

### Check Sync Status

```bash
# View recent sync logs
tail -50 ~/.cloudsync/logs/cron-sync.log

# View errors only
cat ~/.cloudsync/logs/cron-errors.log

# View detailed bundle sync log
tail -100 ~/.cloudsync/logs/bundle-sync.log
```

### Check Restore Verification Status

```bash
# View latest restore verification results
tail -50 ~/.cloudsync/logs/restore-verification.log

# Check when last verification ran
ls -lh ~/.cloudsync/logs/restore-verification.log
```

### Check Notification Status

```bash
# Test all enabled notification backends
./scripts/notify.sh success "Test" "Testing all backends"

# Check if notify script is executable
ls -lh ./scripts/notify.sh
```

### Monitor Cron Jobs

```bash
# List all CloudSync cron jobs
crontab -l | grep -i cloudsync

# Check cron execution logs
grep -i cloudsync /var/log/syslog
```

---

## Troubleshooting

### Notifications Not Received

**Check 1: Notifications enabled?**
```bash
grep ENABLE_NOTIFICATIONS config/notifications.conf
# Should show: ENABLE_NOTIFICATIONS=true
```

**Check 2: Backend configured?**
```bash
grep ENABLE_NTFY config/notifications.conf
# At least one backend should be enabled
```

**Check 3: Severity threshold?**
```bash
grep MIN_SEVERITY config/notifications.conf
# Check if messages are below threshold
```

**Check 4: Test manually**
```bash
./scripts/notify.sh success "Test" "Manual test"
# Should see colored output in terminal
```

### ntfy.sh Not Working

**Check topic configuration:**
```bash
grep NTFY_TOPIC config/notifications.conf
# Should have a value, not empty
```

**Test with curl directly:**
```bash
curl -d "Test from curl" https://ntfy.sh/YOUR_TOPIC
```

**Check phone app:**
- Is app installed?
- Are you subscribed to the correct topic?
- Are notifications enabled for the app?

### Webhook Not Working

**Test webhook manually:**
```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"title":"Test","message":"Test from curl"}' \
  YOUR_WEBHOOK_URL
```

**Common issues:**
- Webhook URL incorrect
- Payload format not compatible with service
- Service requires authentication headers

**Solution:** Create a proxy endpoint to transform CloudSync JSON to service-specific format.

### Email Not Working

**Check mail command:**
```bash
which mail
# Should return a path
```

**Install if missing:**
```bash
# Debian/Ubuntu
sudo apt install mailutils

# RHEL/CentOS
sudo yum install mailx
```

**Test mail directly:**
```bash
echo "Test" | mail -s "Test Subject" your-email@example.com
```

### Restore Verification Failures

**Check logs:**
```bash
tail -100 ~/.cloudsync/logs/restore-verification.log
```

**Common issues:**

1. **Missing bundles:**
   ```
   ✗ repo-name: Missing bundle in chain
   ```
   Solution: Run sync to create missing bundles

2. **Invalid bundles:**
   ```
   ✗ repo-name: Git repository is invalid
   ```
   Solution: Re-create bundles for that repository

3. **Permission errors:**
   ```
   ✗ repo-name: Permission denied
   ```
   Solution: Check file permissions on bundle directory

**Manual restore test:**
```bash
# Test specific repo restore
./scripts/bundle/restore-from-bundle.sh test Archive/meiosis-crewai-js

# Check test output
ls -la /tmp/restore-test-*/
```

---

## Integration Examples

### Custom Script Integration

```bash
#!/bin/bash
# Your custom script

# Source notification function
NOTIFY_SCRIPT="/path/to/CloudSync/scripts/notify.sh"

# Do your work
if do_important_work; then
    "${NOTIFY_SCRIPT}" success "Task Complete" "Work finished successfully"
else
    "${NOTIFY_SCRIPT}" error "Task Failed" "Something went wrong"
fi
```

### Webhook Proxy Example (Node.js)

Transform CloudSync notifications for Slack:

```javascript
const express = require('express');
const axios = require('axios');

const app = express();
app.use(express.json());

app.post('/webhook/slack', async (req, res) => {
    const { title, message, severity } = req.body;

    // Transform to Slack format
    const slackPayload = {
        text: title,
        blocks: [{
            type: "section",
            text: {
                type: "mrkdwn",
                text: `*${title}*\n${message}`
            }
        }]
    };

    // Send to Slack
    await axios.post(process.env.SLACK_WEBHOOK_URL, slackPayload);
    res.json({ success: true });
});

app.listen(3000);
```

---

## Best Practices

1. **Start with ntfy.sh** - Easiest to set up, works immediately
2. **Set appropriate MIN_SEVERITY** - Avoid notification fatigue
3. **Test regularly** - Run manual restore verification monthly
4. **Monitor logs** - Check logs weekly for issues
5. **Multiple backends** - Enable 2+ backends for redundancy
6. **Document your setup** - Note your topic names and webhook URLs

---

## Summary

**Notification System Provides:**
- ✅ Multi-backend support (ntfy, webhook, email)
- ✅ Severity filtering
- ✅ Automatic notifications for sync and restore events
- ✅ Easy manual notification capability

**Restore Verification Provides:**
- ✅ Weekly automatic disaster recovery testing
- ✅ Validation of bundle integrity
- ✅ Confidence in backup restoration
- ✅ Early detection of backup issues

**Next Steps:**
1. Configure at least one notification backend
2. Test notifications manually
3. Wait for automated sync to verify notifications work
4. Review restore verification logs after first Sunday run

For more information, see:
- [BACKUP_SYSTEMS_OVERVIEW.md](./BACKUP_SYSTEMS_OVERVIEW.md) - Complete backup system documentation
- [QUICK_REFERENCE.md](./QUICK_REFERENCE.md) - Essential commands
- [TROUBLESHOOTING_REFERENCE.md](./TROUBLESHOOTING_REFERENCE.md) - Common issues and solutions
