# Setting Up Automated Releases - Quick Start

This is a quick setup guide for enabling automated releases. For comprehensive details, see [AUTOMATED_RELEASES.md](AUTOMATED_RELEASES.md).

## Current Status

✅ **Completed:**
- Release Please configuration files added
- GitHub Actions workflow created
- Conventional commit format documented
- v0.1.1 released manually

⏳ **Needs Setup:**
- Trusted Publishing on RubyGems.org (one-time, 5 minutes)
- GitHub Actions permissions (one-time, 2 minutes)

## Step 1: Enable Trusted Publishing on RubyGems.org

This is the most important step. It enables secure, token-less gem publishing.

### Instructions

1. **Login to RubyGems.org**: https://rubygems.org/sign_in

2. **Go to your gem settings**:
   - Visit: https://rubygems.org/gems/rails_error_dashboard
   - Click "Settings" or "Edit Gem"

3. **Navigate to "Trusted Publishers"**:
   - Look for "Trusted Publishers" in the sidebar
   - Click "Add" or "New Publisher"

4. **Fill in the form**:
   ```
   Publisher Type: GitHub Actions
   Repository owner: AnjanJ
   Repository name: rails_error_dashboard
   Workflow filename: release.yml
   Environment name: (leave blank)
   ```

5. **Save** the trusted publisher

**That's it!** No API keys needed. The workflow will authenticate automatically via OIDC.

### Verification

After setup, you should see:
```
Trusted Publishers
✓ GitHub Actions: AnjanJ/rails_error_dashboard (workflow: release.yml)
```

## Step 2: Grant GitHub Actions Permissions

1. **Go to repository settings**:
   - Visit: https://github.com/AnjanJ/rails_error_dashboard/settings/actions

2. **Under "Workflow permissions"**:
   - ✅ Select "Read and write permissions"
   - ✅ Check "Allow GitHub Actions to create and approve pull requests"

3. **Click "Save"**

## Step 3: Test Automated Release (Optional)

Let's verify the setup works:

1. **Make a small change** (like updating README):
   ```bash
   git checkout -b test-release
   echo "# Testing automated releases" >> docs/TEST.md
   git add docs/TEST.md
   git commit -m "docs: test automated release workflow"
   git push origin test-release
   ```

2. **Create and merge PR** to `main`

3. **Check for Release PR**:
   ```bash
   gh pr list --label "autorelease: pending"
   ```

   You should see a new PR like: "chore(main): release 0.1.2"

4. **Review the Release PR**:
   - Check version bump
   - Review CHANGELOG updates
   - Verify changes are correct

5. **Merge the Release PR**:
   ```bash
   gh pr merge <PR_NUMBER> --merge
   ```

6. **Monitor publishing**:
   ```bash
   gh run watch
   ```

7. **Verify on RubyGems**:
   - Check: https://rubygems.org/gems/rails_error_dashboard
   - Should show v0.1.2

**If all steps succeed, automation is working!**

## Using Automated Releases

Once setup is complete, releasing is simple:

### 1. Use Conventional Commits

```bash
# Bug fix (patch: 0.1.1 → 0.1.2)
git commit -m "fix: resolve notification timing issue"

# New feature (minor: 0.1.1 → 0.2.0)
git commit -m "feat: add Telegram notification support"

# Breaking change (major: 0.1.1 → 1.0.0)
git commit -m "feat!: redesign configuration API

BREAKING CHANGE: Configuration format has changed.
See docs/MIGRATION_v2.md for upgrade guide."
```

### 2. Merge to Main

Create PR and merge to `main`:
```bash
git checkout -b my-feature
git commit -m "feat: add cool new feature"
git push origin my-feature
gh pr create --fill
gh pr merge --merge
```

### 3. Review Release PR

Release Please automatically creates a Release PR:
```bash
gh pr list --label "autorelease: pending"
gh pr view <PR_NUMBER>
```

Review:
- Version bump is correct
- CHANGELOG entries are accurate
- All changes are included

### 4. Merge Release PR

When ready to publish:
```bash
gh pr merge <PR_NUMBER> --merge
```

**Done!** Gem publishes automatically to RubyGems.org.

## Troubleshooting

### "Trusted publishing is not configured for this gem"

**Problem:** Gem push failed with trusted publishing error.

**Solution:** Complete Step 1 above (set up trusted publisher on RubyGems.org).

### "Permission denied" in GitHub Actions

**Problem:** Workflow can't create Release PR.

**Solution:** Complete Step 2 above (grant GitHub Actions write permissions).

### Release PR not created

**Problem:** Commits merged but no Release PR appeared.

**Check:**
1. Commits use conventional format (`feat:`, `fix:`, etc.)
2. GitHub Actions workflow ran: `gh run list --workflow=release.yml`
3. Check workflow logs: `gh run view <RUN_ID>`

### Version bump is wrong

**Problem:** Release Please bumped wrong version.

**Solution:** Edit the Release PR manually:
- Update `lib/rails_error_dashboard/version.rb`
- Update `CHANGELOG.md`
- Commit and push to Release PR branch

## Quick Reference

### Commit Types

| Type | Version Bump | Example |
|------|-------------|---------|
| `fix:` | Patch (0.1.1 → 0.1.2) | Bug fixes |
| `feat:` | Minor (0.1.1 → 0.2.0) | New features |
| `feat!:` | Major (0.1.1 → 1.0.0) | Breaking changes |
| `docs:` | None | Documentation only |
| `test:` | None | Test changes |
| `chore:` | None | Maintenance |

### Useful Commands

```bash
# List Release PRs
gh pr list --label "autorelease: pending"

# View Release PR
gh pr view <PR_NUMBER>

# Merge Release PR (triggers publishing)
gh pr merge <PR_NUMBER> --merge

# Watch workflow run
gh run watch

# View workflow logs
gh run view <RUN_ID>

# Verify gem published
gem list -r rails_error_dashboard
```

## Support

For detailed documentation:
- [Full Automated Release Guide](AUTOMATED_RELEASES.md)
- [Release Please Documentation](https://github.com/googleapis/release-please)
- [Trusted Publishing Guide](https://guides.rubygems.org/trusted-publishing/)

For issues:
- [GitHub Issues](https://github.com/AnjanJ/rails_error_dashboard/issues)

---

**Note:** After completing Steps 1 and 2, all future releases are fully automated!
