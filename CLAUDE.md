# CLAUDE.md — Project Instructions for Claude Code

## What This Is

rails_error_dashboard is a self-hosted error tracking gem for Rails. It's a Rails Engine using CQRS architecture (Commands/Queries/Services). It runs inside the host app's process — no external services.

> **See memory files for detailed notes:** architecture, testing, roadmap, safety, demo-deployment, codebase-history, release-process, common-pitfalls, solidqueue-integration, deep-introspection, pickme.

## Architecture Rules

1. **HOST APP SAFETY FIRST** — Never raise in capture path, never block requests, budget every operation, clean up Thread.current, always re-raise original exceptions
2. **CQRS** — Commands for writes (`app/commands/`), Queries for reads (`app/queries/`), Services for algorithms (`app/services/`)
3. **NEVER depend on Rails asset pipeline** — no Sprockets, no Propshaft, no `app/assets/`, no `public/` directory serving
4. All CSS is inline in the layout `<style>` block, all JS is inline in `<script>` blocks
5. External dependencies (Bootstrap JS for tooltips/modals, Chart.js, Highlight.js) loaded via CDN only — Bootstrap CSS was removed in v0.6.0 in favor of a custom design token system
6. Layout must be fully self-contained — works with any proxy (Thruster, Nginx, etc.)

## Testing

### RSpec (unit/integration)
```bash
bundle exec rspec                          # full suite (~2636 specs, ~49s)
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

## Workflow Orchestration

These principles govern HOW work is done. Follow them when the path forward is clear and there are concrete steps. **When the path is unclear — when you don't know the how, why, or what — ask the user questions instead of guessing. It is always better to ask than to push forward blindly.**

### 1. Plan Mode Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately — don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Subagent Strategy
- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

### 3. Self-Improvement Loop
- After ANY correction from the user: update `tasks/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for this project

### 4. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 5. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes — don't over-engineer
- Challenge your own work before presenting it

### 6. Autonomous Bug Fixing
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests — then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

### 7. Task Management
1. **Plan First**: Write plan to `tasks/todo.md` with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review section to `tasks/todo.md`
6. **Capture Lessons**: Update `tasks/lessons.md` after corrections

### 8. Core Principles
- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Changes should only touch what's necessary. Avoid introducing bugs.

## Common Gotchas

- **Thor colors**: Only `:black`, `:red`, `:green`, `:yellow`, `:blue`, `:magenta`, `:cyan`, `:white`, `:bold` — no `:gray` or `:light_*`
- **Ruby 4.0.1**: `ostruct` removed from default gems; sqlite3 2.8.1 doesn't compile on macOS
- **Puma in test scripts**: Always `lsof -ti :$port | xargs kill -9` before starting. Never use `-d` (daemonize) — use `&` instead
- **SQLite pragmas**: `pragmas:` (plural) not `pragma:` in database.yml
- **Separate DB**: Installer puts migrations in `db/migrate/` — must manually move to `db/error_dashboard_migrate/`
