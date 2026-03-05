---
description: Audit staged changes against the 10 host app safety rules
user-invocable: true
---

# /safety-check — Host App Safety Audit

Audit staged or recent changes against the 10 host app safety rules. This skill is also auto-invocable — Claude should run it automatically when making changes to the capture path.

## Usage

- `/safety-check` — audit staged changes (`git diff --cached`)
- `/safety-check HEAD~3` — audit last 3 commits
- `/safety-check <file>` — audit a specific file

## The 10 Safety Rules

Audit each changed file against these rules:

1. **Never raise in capture path** — Look for `raise` statements in middleware, subscriber, or capture commands without surrounding `rescue`
2. **Never block request path** — Look for HTTP calls, file I/O, or slow operations in synchronous capture code
3. **Budget every operation** — Check timing: breadcrumb callback <0.01ms, health snapshot <1ms, capture total <5ms
4. **Clean up Thread.current** — Any `Thread.current[]=` must have a matching `ensure` cleanup
5. **Always re-raise original exceptions** — Middleware/subscriber must re-raise after capture (Sentry #1173)
6. **Feature-detect** — Any call to `Puma`, `Sidekiq`, etc. must be guarded with `defined?()` or `respond_to?()`
7. **Make everything disableable** — New request-path features need a config flag
8. **Never use ObjectSpace.each_object** — Freezes all threads, grows heap
9. **Never use Signal.trap** — Breaks Puma/Sidekiq signal handling
10. **Never store Binding objects** — Prevents GC of entire call stack

## Capture Path Files (Highest Scrutiny)

These files run on EVERY request or error — any bug here affects the host app:

- `lib/rails_error_dashboard/middleware/error_catcher.rb`
- `lib/rails_error_dashboard/error_subscriber.rb`
- `lib/rails_error_dashboard/commands/log_error.rb`
- `lib/rails_error_dashboard/commands/find_or_increment_error.rb`
- `lib/rails_error_dashboard/commands/find_or_create_application.rb`
- `lib/rails_error_dashboard/services/error_normalizer.rb`
- `lib/rails_error_dashboard/services/breadcrumb_collector.rb`
- `lib/rails_error_dashboard/services/system_health_snapshot.rb`

## Audit Process

1. **Get the diff**:
   ```bash
   git diff --cached  # or git diff HEAD~N, or read the specified file
   ```

2. **Classify each changed file**:
   - **Capture path** (listed above) — audit ALL 10 rules
   - **Dashboard path** (controllers, views, queries) — audit rules 1, 7, 8, 9
   - **Background path** (jobs, notifications) — audit rules 1, 5, 6
   - **Other** — audit rules 8, 9, 10

3. **Report findings** in a table:

   | File | Rule | Status | Details |
   |------|------|--------|---------|
   | `error_catcher.rb` | #1 No raise | PASS | All paths wrapped in rescue |
   | `error_catcher.rb` | #5 Re-raise | PASS | Line 42: `raise error` after capture |
   | `breadcrumb_collector.rb` | #3 Budget | WARN | No timing measurement found |

4. **Verdict**: PASS (all clear), WARN (potential issues), or FAIL (definite violation)

## Workflow Orchestration

- **Verification Before Done**: Never report PASS without reading the actual code. Diff lines alone are insufficient — read the full file to understand rescue/ensure context.
- **Autonomous Bug Fixing**: If a safety violation is found (FAIL), fix it immediately rather than just reporting it. Then re-run the check to verify the fix.
- **Self-Improvement Loop**: If a safety violation was caused by a pattern not yet in the 10 rules, add it to `tasks/lessons.md`.

## Auto-Invocation

Claude should automatically run this check when:
- Editing any file in the capture path (listed above)
- Adding new middleware or subscriber code
- Modifying `engine.rb` initialization hooks
- Adding Thread.current usage anywhere
