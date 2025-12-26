# Documentation Cleanup Plan

**Date:** December 26, 2025
**Purpose:** Move internal/research documents to knowledge base, keep only user-facing docs in repository

---

## Files to Move to Knowledge Base

### 1. USER_RESEARCH_ERROR_DASHBOARDS.md ✅ MOVE
**Location:** `/Users/aj/code/rails_error_dashboard/docs/USER_RESEARCH_ERROR_DASHBOARDS.md`
**Destination:** `/Users/aj/code/Knowledge/rails_logger_dashboard_knowledge/USER_RESEARCH_ERROR_DASHBOARDS.md`

**Reason:** This is internal research, not user documentation
- Competitive analysis (Sentry, Rollbar, Bugsnag)
- User pain points research
- Market research findings
- Design decisions and rationale

**User Value:** ❌ None - this is internal product development research

---

### 2. SETUP_AUTOMATED_RELEASES.md ✅ MOVE
**Location:** `/Users/aj/code/rails_error_dashboard/docs/SETUP_AUTOMATED_RELEASES.md`
**Destination:** `/Users/aj/code/Knowledge/rails_logger_dashboard_knowledge/SETUP_AUTOMATED_RELEASES.md`

**Reason:** This is maintainer-specific setup, not user documentation
- One-time setup for repository maintainer
- RubyGems trusted publishing setup
- GitHub Actions permissions setup
- Not relevant to gem users

**User Value:** ❌ None - only useful for gem maintainer (you)

---

### 3. AUTOMATED_RELEASES.md ⚠️ KEEP (But Consider Moving)
**Location:** `/Users/aj/code/rails_error_dashboard/docs/AUTOMATED_RELEASES.md`

**Reason to Keep:**
- Documents how releases work (transparency)
- Explains conventional commits for contributors
- Shows release process for potential contributors

**Reason to Move:**
- Primarily maintainer-focused
- Most gem users don't need this info
- Contributors can check CONTRIBUTING.md instead

**Recommendation:** ⚠️ **MOVE to knowledge base**
- This is more for maintainers than users
- Can add brief note in CONTRIBUTING.md about conventional commits

---

### 4. development/CI_SETUP.md ⚠️ MOVE
**Location:** `/Users/aj/code/rails_error_dashboard/docs/development/CI_SETUP.md`
**Destination:** `/Users/aj/code/Knowledge/rails_logger_dashboard_knowledge/development/CI_SETUP.md`

**Reason:** This is CI troubleshooting for gem development
- Multi-version testing setup issues
- Ruby/Rails compatibility fixes
- Bundler configuration problems
- Only useful if you're developing the gem itself

**User Value:** ❌ Low - only for contributors/maintainers

**Recommendation:** ✅ **MOVE** - This is internal development knowledge

---

### 5. development/TESTING.md ✅ KEEP
**Location:** `/Users/aj/code/rails_error_dashboard/docs/development/TESTING.md`

**Reason to Keep:**
- Useful for contributors
- Documents how to run tests
- Shows multi-version testing setup
- Important for open-source contribution

**User Value:** ✅ Medium - Contributors need this

**Recommendation:** ✅ **KEEP** - Valuable for contributors

---

### 6. API_REFERENCE.md ✅ KEEP
**Location:** `/Users/aj/code/rails_error_dashboard/docs/API_REFERENCE.md`

**Reason to Keep:**
- Documents public API methods
- Useful for advanced users
- Mobile app integration needs this
- Frontend developers need API docs

**User Value:** ✅ High - Essential for API users

**Recommendation:** ✅ **KEEP** - Critical user documentation

---

## Summary

### Files to Move (4 files):
1. ✅ `USER_RESEARCH_ERROR_DASHBOARDS.md` → Knowledge base
2. ✅ `SETUP_AUTOMATED_RELEASES.md` → Knowledge base
3. ✅ `AUTOMATED_RELEASES.md` → Knowledge base
4. ✅ `development/CI_SETUP.md` → Knowledge base

### Files to Keep (2 files):
1. ✅ `development/TESTING.md` - For contributors
2. ✅ `API_REFERENCE.md` - For users

### Empty Directories After Cleanup:
- `docs/api/` - Already empty, can be removed
- `docs/development/` - Will only have TESTING.md

---

## Before vs After

### Before (Current Structure)
```
docs/
├── api/                          # Empty
├── development/
│   ├── CI_SETUP.md              # Internal
│   └── TESTING.md               # Keep
├── features/                     # Keep all
├── guides/                       # Keep all
├── API_REFERENCE.md             # Keep
├── AUTOMATED_RELEASES.md        # Internal
├── CUSTOMIZATION.md             # Keep
├── FEATURES.md                  # Keep
├── PLUGIN_SYSTEM.md             # Keep
├── QUICKSTART.md                # Keep
├── README.md                    # Keep
├── SETUP_AUTOMATED_RELEASES.md  # Internal
└── USER_RESEARCH_ERROR_DASHBOARDS.md  # Internal
```

### After (Clean Structure)
```
docs/
├── development/
│   └── TESTING.md               # For contributors
├── features/                     # User features
│   ├── ADVANCED_ERROR_GROUPING.md
│   ├── BASELINE_MONITORING.md
│   ├── ERROR_CORRELATION.md
│   ├── OCCURRENCE_PATTERNS.md
│   └── PLATFORM_COMPARISON.md
├── guides/                       # User guides
│   ├── BACKTRACE_LIMITING.md
│   ├── BATCH_OPERATIONS.md
│   ├── CONFIGURATION.md
│   ├── DATABASE_OPTIMIZATION.md
│   ├── DATABASE_OPTIONS.md
│   ├── ERROR_SAMPLING_AND_FILTERING.md
│   ├── ERROR_TREND_VISUALIZATIONS.md
│   ├── MOBILE_APP_INTEGRATION.md
│   ├── NOTIFICATIONS.md
│   ├── REAL_TIME_UPDATES.md
│   └── SOLID_QUEUE_SETUP.md
├── API_REFERENCE.md             # API docs
├── CUSTOMIZATION.md             # User customization
├── FEATURES.md                  # Feature list
├── PLUGIN_SYSTEM.md             # Plugin development
├── QUICKSTART.md                # Getting started
└── README.md                    # Index
```

**Cleaner:** 17 user-facing files (down from 21)

---

## Knowledge Base Structure

```
/Users/aj/code/Knowledge/rails_logger_dashboard_knowledge/
├── internal/
│   ├── USER_RESEARCH_ERROR_DASHBOARDS.md    # Moved
│   ├── SETUP_AUTOMATED_RELEASES.md          # Moved
│   ├── AUTOMATED_RELEASES.md                # Moved
│   └── development/
│       └── CI_SETUP.md                       # Moved
└── (existing knowledge base files)
```

---

## Migration Commands

```bash
# Create knowledge base directory structure
mkdir -p /Users/aj/code/Knowledge/rails_logger_dashboard_knowledge/internal/development

# Move files to knowledge base
mv /Users/aj/code/rails_error_dashboard/docs/USER_RESEARCH_ERROR_DASHBOARDS.md \
   /Users/aj/code/Knowledge/rails_logger_dashboard_knowledge/internal/

mv /Users/aj/code/rails_error_dashboard/docs/SETUP_AUTOMATED_RELEASES.md \
   /Users/aj/code/Knowledge/rails_logger_dashboard_knowledge/internal/

mv /Users/aj/code/rails_error_dashboard/docs/AUTOMATED_RELEASES.md \
   /Users/aj/code/Knowledge/rails_logger_dashboard_knowledge/internal/

mv /Users/aj/code/rails_error_dashboard/docs/development/CI_SETUP.md \
   /Users/aj/code/Knowledge/rails_logger_dashboard_knowledge/internal/development/

# Remove empty api directory
rmdir /Users/aj/code/rails_error_dashboard/docs/api

# Verify cleanup
ls -R /Users/aj/code/rails_error_dashboard/docs/
```

---

## Documentation Index Updates

After moving files, update `docs/README.md`:

### Remove These Sections:
```markdown
# REMOVE - No longer in repo
- [Automated Releases](AUTOMATED_RELEASES.md)
- [Setup Automated Releases](SETUP_AUTOMATED_RELEASES.md)
```

### Update Development Section:
```markdown
### Development
- [Testing](development/TESTING.md) - Running and writing tests
- [Contributing](../CONTRIBUTING.md) - How to contribute to the project
- [Changelog](../CHANGELOG.md) - Version history and updates
```

---

## Benefits of Cleanup

### For Users:
✅ **Clearer documentation** - Only user-relevant files
✅ **Easier navigation** - Less clutter
✅ **Faster onboarding** - Focus on what matters
✅ **Better first impression** - Professional, focused docs

### For Maintainers:
✅ **Organized knowledge** - Internal docs in one place
✅ **Separation of concerns** - User docs vs internal docs
✅ **Privacy** - Research/strategy not public
✅ **Flexibility** - Can expand knowledge base without cluttering repo

---

## Validation Checklist

After moving files:

- [ ] All moved files exist in knowledge base
- [ ] Original files removed from repository
- [ ] `docs/README.md` updated with correct links
- [ ] No broken links in remaining documentation
- [ ] `docs/api/` empty directory removed
- [ ] Git status shows only intended deletions
- [ ] Documentation still renders correctly in GitHub

---

## Open Questions

1. **Should CI_SETUP.md be public?**
   - ❌ No - It's troubleshooting for CI setup, not useful to users
   - ✅ Move to knowledge base

2. **Should AUTOMATED_RELEASES.md be public?**
   - ⚠️ Arguable - Shows transparency in release process
   - ✅ Move to knowledge base (brief note in CONTRIBUTING.md is enough)

3. **Should we keep docs/development/ directory?**
   - ✅ Yes - TESTING.md is valuable for contributors
   - Keep the directory with just TESTING.md

---

## Recommendation

**Execute the cleanup plan:**
1. ✅ Move 4 files to knowledge base
2. ✅ Remove empty `docs/api/` directory
3. ✅ Update `docs/README.md` to remove references
4. ✅ Commit with message: `docs: move internal docs to knowledge base`

**Result:** Cleaner repository with focused, user-centric documentation

---

**Approved:** Pending your review
**Ready to Execute:** Yes
