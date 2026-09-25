---
description: Run pre-release chaos tests — real Rails apps in production mode
user-invocable: true
disable-model-invocation: true
---

# /chaos — Pre-Release Chaos Tests

Run integration tests that create real Rails apps in `/tmp`, install the gem, and run in production mode.

## Usage

- `/chaos` or `/chaos all` — all 4 core apps (~4-5 min, ~1,480 assertions; the summary counts 5 runs because the HTTP app records two)
- `/chaos release` — full release audit, 8 apps (~12-15 min, 2100+ assertions)
- `/chaos sync` — sync config only (~1 min)
- `/chaos async` — async (Sidekiq inline) + shared DB
- `/chaos http` — HTTP middleware capture + dashboard
- `/chaos separate` — separate database config

## Commands

### All Core Apps (Lefthook Default)
```bash
bin/pre-release-test all
```

### Full Release Audit
```bash
bin/pre-release-test release_audit
```

### Individual Apps
```bash
bin/pre-release-test full_sync
bin/pre-release-test full_async
bin/pre-release-test full_http
bin/pre-release-test full_separate_db
```

### Additional Release Audit Apps
```bash
bin/pre-release-test full_kitchen_sink
bin/pre-release-test full_multi_app
bin/pre-release-test full_solid_queue
bin/pre-release-test full_upgrade
```

## Test Phases

Each app runs through these phases:

| Phase | What It Tests |
|-------|--------------|
| A | Data integrity — error logging, deduplication, occurrence counts |
| B | Edge cases — nil values, huge payloads, unicode, concurrent writes |
| C | Query layer — filters, sorting, pagination, analytics queries |
| D | Dashboard HTTP — all controller endpoints return 200 |
| E | Subscriber capture — `Rails.error.report()` with 20+ error types |
| F | HTTP middleware — starts Puma, hits endpoints via curl, verifies capture |

## After Running

- Report pass/fail summary and assertion counts
- If failures occur, show the failing phase and assertion details
- Phase F failures often indicate stale Puma processes — check with `lsof -ti :<port>`

## Notes

- Apps are created in `/tmp/pre_release_test_$$` (auto-cleaned)
- ALL apps run in `RAILS_ENV=production`
- ALL features enabled (analytics, source code, git blame, webhooks, rate limiting)
- Phase F starts a real Puma server — always kills stale servers first
- Templates: `test/pre_release/templates/full_*_initializer.rb`
- Test harness: `test/pre_release/lib/test_harness.rb`
