# CLAUDE.md — Project Instructions for Claude Code

## What This Is

rails_error_dashboard is a self-hosted error tracking gem for Rails. It's a Rails Engine using CQRS architecture (Commands/Queries/Services). It runs inside the host app's process — no external services.

## Architecture Rules

1. **HOST APP SAFETY FIRST** — Never raise in capture path, never block requests, budget every operation, clean up Thread.current, always re-raise original exceptions
2. **CQRS** — Commands for writes (`app/commands/`), Queries for reads (`app/queries/`), Services for algorithms (`app/services/`)
3. **NEVER depend on Rails asset pipeline** — no Sprockets, no Propshaft, no `app/assets/`, no `public/` directory serving
4. All CSS is inline in the layout `<style>` block, all JS is inline in `<script>` blocks
5. External dependencies (Bootstrap, Chart.js, Highlight.js) loaded via CDN only
6. Layout must be fully self-contained — works with any proxy (Thruster, Nginx, etc.)

## Testing

### RSpec (unit/integration)
```bash
bundle exec rspec                          # full suite (~1895 specs, ~37s)
bundle exec rspec spec/system/             # system tests (Capybara + Cuprite)
HEADLESS=false bundle exec rspec spec/system/  # visible browser
```

### Pre-Release Chaos Tests (integration, production mode)
```bash
bin/pre-release-test all            # all 4 apps (~4-5 min, 1000+ assertions)
bin/pre-release-test full_sync      # sync + shared DB
bin/pre-release-test full_async     # async (Sidekiq inline) + shared DB
bin/pre-release-test full_http      # HTTP middleware capture + dashboard
bin/pre-release-test full_separate_db  # separate DB
```

Chaos tests create real Rails apps in `/tmp`, install the gem, and run in production mode. They test:
- Phase A: data integrity
- Phase B: edge cases
- Phase C: query layer
- Phase D: dashboard HTTP endpoints
- Phase E: subscriber capture via `Rails.error.report()`
- Phase F: real HTTP middleware error capture (starts Puma, hits endpoints)

### Lefthook Pre-Commit
Runs automatically on `git commit`:
- Stage 1 (parallel): RuboCop, changed specs, bundle-audit, debugger check, whitespace
- Stage 2 (sequential): chaos tests (`bin/pre-release-test all`)

Skip chaos tests: `LEFTHOOK_EXCLUDE=chaos-tests git commit -m "msg"`
Skip all hooks: `LEFTHOOK=0 git commit -m "msg"`

## Key Paths

| Path | Purpose |
|------|---------|
| `lib/rails_error_dashboard/` | Core gem code |
| `lib/rails_error_dashboard/engine.rb` | Engine setup, middleware, subscriber |
| `lib/rails_error_dashboard/configuration.rb` | 100+ config options |
| `app/commands/rails_error_dashboard/` | CQRS commands (writes) |
| `app/queries/rails_error_dashboard/` | CQRS queries (reads) |
| `app/services/rails_error_dashboard/` | Services (algorithms) |
| `app/views/rails_error_dashboard/` | Dashboard views (ERB) |
| `spec/` | RSpec tests |
| `test/pre_release/` | Chaos test scripts + templates |
| `bin/pre-release-test` | Chaos test orchestrator |

## Style

- RuboCop with rails-omakase style
- Array brackets with inner spaces: `[ "a", "b" ]`
- No emojis in code unless user asks
- Commit messages: conventional commits style (feat/fix/chore/etc.)

## Common Gotchas

- **Thor colors**: Only `:black`, `:red`, `:green`, `:yellow`, `:blue`, `:magenta`, `:cyan`, `:white`, `:bold` — no `:gray` or `:light_*`
- **Ruby 4.0.1**: `ostruct` removed from default gems; sqlite3 2.8.1 doesn't compile on macOS
- **Puma in test scripts**: Always `lsof -ti :$port | xargs kill -9` before starting. Never use `-d` (daemonize) — use `&` instead
- **SQLite pragmas**: `pragmas:` (plural) not `pragma:` in database.yml
- **Separate DB**: Installer puts migrations in `db/migrate/` — must manually move to `db/error_dashboard_migrate/`
