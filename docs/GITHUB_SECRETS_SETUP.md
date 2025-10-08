# GitHub Secrets Setup Guide

This guide explains how to use GitHub Secrets for sensitive configuration instead of storing passwords in files.

## Why GitHub Secrets?

- ✅ Encrypted at rest and in transit
- ✅ Not visible in repository files or logs
- ✅ Can be used in GitHub Actions workflows
- ✅ Centralized credential management
- ✅ Easy rotation without code changes

## Setting Up GitHub Secrets

### 1. Navigate to Repository Settings

1. Go to your repository: `https://github.com/cordlesssteve/CloudSync`
2. Click **Settings** tab
3. Click **Secrets and variables** → **Actions**
4. Click **New repository secret**

### 2. Add Your Secrets

Add the following secrets:

#### RESTIC_PASSWORD
- **Name**: `RESTIC_PASSWORD`
- **Value**: Your Restic repository password
- Click **Add secret**

#### Optional: RCLONE_CONFIG
- **Name**: `RCLONE_CONFIG`
- **Value**: Your complete rclone.conf file contents
- Click **Add secret**

## Using Secrets in GitHub Actions

### Example: Automated Backup Workflow

Create `.github/workflows/backup.yml`:

```yaml
name: Automated Backup

on:
  schedule:
    - cron: '0 1 * * *'  # Daily at 1 AM
  workflow_dispatch:  # Manual trigger

jobs:
  backup:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Setup Restic
        run: |
          wget https://github.com/restic/restic/releases/download/v0.16.0/restic_0.16.0_linux_amd64.bz2
          bunzip2 restic_0.16.0_linux_amd64.bz2
          chmod +x restic_0.16.0_linux_amd64
          sudo mv restic_0.16.0_linux_amd64 /usr/local/bin/restic

      - name: Run Git Bundle Sync
        env:
          RESTIC_PASSWORD: ${{ secrets.RESTIC_PASSWORD }}
        run: |
          ./scripts/bundle/git-bundle-sync.sh sync
```

### Example: Manual Restore Verification

Create `.github/workflows/verify-restore.yml`:

```yaml
name: Verify Restore

on:
  workflow_dispatch:  # Manual trigger only

jobs:
  verify:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Run Restore Verification
        env:
          RESTIC_PASSWORD: ${{ secrets.RESTIC_PASSWORD }}
        run: |
          ./scripts/bundle/verify-restore.sh --max-repos 3
```

## Using Secrets in Local Scripts

For local development, you still need a config file. Here's the hybrid approach:

### 1. Local Config (Not in Git)

`config/cloudsync.conf` - Created from template, never committed:
```bash
RESTIC_PASSWORD="your-local-password"
```

### 2. GitHub Actions Uses Secrets

The workflow files above automatically use GitHub Secrets when running in CI/CD.

### 3. Script Compatibility

Your scripts can check for both:

```bash
# Load password from config or environment
if [[ -n "$RESTIC_PASSWORD" ]]; then
    # Use environment variable (GitHub Actions)
    PASSWORD="$RESTIC_PASSWORD"
elif [[ -f "$CLOUDSYNC_CONFIG" ]]; then
    # Use local config file
    source "$CLOUDSYNC_CONFIG"
    PASSWORD="$RESTIC_PASSWORD"
else
    echo "ERROR: No password source found"
    exit 1
fi
```

## Security Best Practices

### ✅ DO:
- Use GitHub Secrets for all sensitive data in workflows
- Use local config files (gitignored) for development
- Rotate secrets regularly
- Use environment-specific secrets (dev, staging, prod)
- Enable secret scanning in repository settings

### ❌ DON'T:
- Never echo secrets in workflow logs
- Don't use secrets in pull requests from forks
- Don't store secrets in environment variables permanently
- Avoid hardcoding secrets in scripts

## Rotating Secrets

When you need to change a secret:

1. **Change the actual credential**:
   ```bash
   restic -r /path/to/repo key passwd
   ```

2. **Update GitHub Secret**:
   - Go to Settings → Secrets → Actions
   - Click on the secret name
   - Click **Update secret**
   - Enter new value

3. **Update local config**:
   ```bash
   nano config/cloudsync.conf
   # Change RESTIC_PASSWORD value
   ```

## Secret Access Logs

GitHub provides audit logs for secret access:

1. Go to Settings → Security → Audit log
2. Filter by "secret" to see when secrets were accessed
3. Review for unauthorized access

## Environment-Specific Secrets

For multiple environments:

```yaml
# Production
RESTIC_PASSWORD_PROD

# Staging
RESTIC_PASSWORD_STAGING

# Development
RESTIC_PASSWORD_DEV
```

Use in workflow:
```yaml
env:
  RESTIC_PASSWORD: ${{ secrets[format('RESTIC_PASSWORD_{0}', github.ref_name)] }}
```

## Troubleshooting

### Secret Not Available
- Check secret name spelling (case-sensitive)
- Verify secret is set in repository settings
- Ensure workflow has permission to access secrets

### Secret Not Working
- Secrets are only available in GitHub Actions
- Local development requires config file
- Check for typos in secret references

## Additional Resources

- [GitHub Secrets Documentation](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Secret Scanning](https://docs.github.com/en/code-security/secret-scanning)
- [Workflow Security Best Practices](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)
