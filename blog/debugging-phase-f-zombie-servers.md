# The Zombie Server That Wasted My Entire Afternoon: Debugging Cross-Process SQLite Visibility in Integration Tests

> I spent hours chasing SQLite WAL mode, cross-process visibility, and absolute vs relative database paths — only to discover the real problem was a ghost server from a previous test run that never died.

---

When you build an error tracking gem that runs inside Rails, you need to prove that it actually catches errors. Not unit-test "call this method and check the return value" prove — I mean **start a real Rails server, hit a real endpoint that raises a real exception, and verify that your gem automatically captured it in the database**.

That's what Phase F of my pre-release test suite does. And getting it to work nearly drove me insane.

## What I Was Building

[rails_error_dashboard](https://github.com/AnjanJ/rails_error_dashboard) is a self-hosted error tracking gem for Rails. It captures exceptions via two mechanisms:

1. **Rack middleware** (ErrorCatcher) — wraps every request, catches exceptions, logs them
2. **Rails.error subscriber** (ErrorReporter) — hooks into Rails 7+ error reporting API

My pre-release test suite creates temporary Rails apps from scratch, installs the gem, and runs chaos tests against them. The existing tests were solid — 800+ assertions across 5 apps — but they had a fundamental gap: **Phase A tested `LogError.call()` directly. It never verified that errors were automatically captured by the middleware.**

Phase F would fix that:

1. Generate a fresh Rails app in `/tmp`
2. Inject a controller with 11 actions, each raising a different exception type (NoMethodError, ZeroDivisionError, TypeError, etc.)
3. Start a Puma server in production mode
4. Hit each endpoint via `Net::HTTP`
5. Verify the gem automatically captured each error with the correct type, severity, message, and backtrace

Simple, right?

## The First Run: 0 Errors Captured

```
F1: Error endpoints trigger middleware capture
  FAIL: NoMethodError from nil.method: ErrorLog record created
    count unchanged: 0 -> 0
  FAIL: ZeroDivisionError from 1/0: ErrorLog record created
    count unchanged: 0 -> 0
  FAIL: TypeError from Integer(nil): ErrorLog record created
    count unchanged: 0 -> 0
```

Every single error type showed `count unchanged: 0 -> 0`. The HTTP requests returned 500 (meaning the errors *were* raising), but no records appeared in the database.

## Red Herring #1: SQLite WAL Mode

My first theory was reasonable: the Puma server and the `rails runner` test script are **separate processes** accessing the same SQLite database. SQLite's WAL (Write-Ahead Logging) mode can cause readers in other processes to not see recent writes until a checkpoint occurs.

I spent a while configuring `journal_mode=delete` in `database.yml`:

```yaml
production:
  adapter: sqlite3
  database: storage/production.sqlite3
  pragmas:
    journal_mode: delete
```

(I also discovered that it's `pragmas:` plural, not `pragma:` — a fun typo that silently does nothing.)

Still 0 errors. I strengthened the `refresh_db_connection!` helper:

```ruby
def refresh_db_connection!
  RailsErrorDashboard::ErrorLog.connection.clear_query_cache
end
```

Still 0 errors.

## Red Herring #2: Relative vs Absolute Database Paths

Next theory: when Puma daemonizes with `-d`, it changes its working directory to `/`. So `storage/production.sqlite3` in the Puma server resolves to `/storage/production.sqlite3`, while the `rails runner` process (running from the app directory) resolves it to `/tmp/pre_release_test_12345/full_http_app/storage/production.sqlite3`.

Two different files. Two different databases. That would explain why the runner sees 0 records!

I switched to absolute paths in `database.yml`:

```yaml
production:
  adapter: sqlite3
  database: /tmp/pre_release_test_12345/full_http_app/storage/production.sqlite3
```

Still 0 errors. But this theory felt so right that I kept tweaking it — adding logging, checking file sizes, verifying paths.

## Red Herring #3: ActionDispatch::Executor vs Middleware

Maybe the middleware wasn't catching errors at all? I dug into how Rails handles exceptions in production mode:

```
Request → Executor → ShowExceptions → DebugExceptions → Controller
                                          ↓
                                   rescue exception
                                   set env["action_dispatch.report_exception"]
                                   render 500 page (WITHOUT re-raising)
                                          ↓
                              ← Executor checks flag
                              ← calls Rails.error.report()
```

In production, `ShowExceptions` catches the exception and renders a 500 page *without re-raising*. This means our middleware at position 0 never sees the exception — it only sees the 500 response. The error gets reported by the Executor via `Rails.error.report()`.

This was actually correct and important to understand, but it wasn't the bug.

## The Breakthrough: Reading the Server Log

After hours of trying every possible database, middleware, and SQLite configuration, I added `>> "$app_dir/log/server.log" 2>&1` to capture the server's output. What I found was illuminating:

```
=> Booting Puma
=> Rails 8.1.2 application starting in production
Puma starting in single mode...
* Puma version: 7.2.0
* Ruby version: ruby 4.0.1
*  Min threads: 3
*  Environment: production
*          PID: 23263
Exiting
.../puma/binder.rb:344:in 'TCPServer#initialize':
  Address already in use - bind(2) for "0.0.0.0" port 3098 (Errno::EADDRINUSE)
```

**Address already in use.** The new server never started.

## The Real Bug: A Zombie Server

Here's what happened:

1. A previous test run started Puma on port 3098 with `bin/rails server -d` (daemonized)
2. The test finished, tried to kill it via `kill "$(cat tmp/pids/server.pid)"`, but the pidfile path was wrong (temp directories get new PIDs each run)
3. The daemonized Puma process survived, still listening on port 3098
4. Every subsequent test run tried to start a new server, got `EADDRINUSE`, and silently exited
5. The HTTP requests hit the **old** zombie server, which had a completely different database in a different temp directory
6. The runner process queried the **new** database — which was empty because errors went to the old one

The symptom — `count unchanged: 0 -> 0` — was 100% consistent with SQLite visibility issues, database path problems, or middleware misconfiguration. Every red herring was plausible. But the real cause was a zombie process from a previous run.

## The Fix

Three lines of bash:

```bash
# Kill any stale server on this port from previous test runs
lsof -ti :"$port" | xargs kill -9 2>/dev/null || true
sleep 1
```

Plus: don't use `-d` (daemonize). Run in background with `&` instead, which keeps the process as a child so you can reliably `kill $server_pid`:

```bash
(cd "$app_dir" && bin/rails server -p "$port" \
  >> "$app_dir/log/server.log" 2>&1) &
local server_pid=$!
```

After these changes: **78/78 Phase F assertions passed.** Including deduplication, request context, severity classification, all 11 error types.

Well, almost. There was one more papercut.

## Bonus Bug: The Case-Sensitive Controller Name

77/78 passed on the first run after fixing the zombie. The one failure:

```
FAIL: context: controller_name captured
  got "TestErrorsController"
  expected to include "test_error"
```

When errors are reported by the Executor (not our middleware), Rails stores the full class name `"TestErrorsController"` rather than the underscored `"test_errors"`. My assertion was:

```ruby
nm_error.controller_name.include?("test_error")
```

First fix attempt: `.downcase.include?("test_error")`. Still failed — because `"testerrorscontroller".downcase` doesn't contain `"test_error"` (with the underscore). The downcased class name smooshes everything together.

Final fix:

```ruby
nm_error.controller_name.downcase.include?("testerror")
```

78/78. 150/150 total with Phase D dashboard tests. All green.

## Why It Took So Many Tries

Looking back, this bug was hard to find because:

1. **The symptom matched multiple plausible theories.** Zero records in the database could be caused by WAL mode, wrong file paths, middleware not firing, or subscriber not registered. Each theory required investigation and code changes.

2. **The zombie was invisible.** There was no error message. The new server quietly failed and exited. The HTTP requests succeeded (because they hit the old server). Everything *looked* like it was working except the database counts.

3. **The debugging tools were broken.** My shell environment had a corrupted working directory from a previous test run (stuck on a deleted temp directory). Every `bash` command silently failed. I couldn't run `lsof`, `sqlite3`, `ls`, or any diagnostic commands.

4. **Production mode hides errors.** In production, Rails shows a generic 500 page and logs errors to `production.log`. The actual exception details are buried. In development mode, you'd see a nice error page with a backtrace. But the whole point of Phase F is testing production behavior.

5. **Daemonization is deceptive.** `bin/rails server -d` detaches the process, changes CWD, and manages its own pidfile. When the pidfile path doesn't match between runs (because temp directories have different PIDs), you lose the ability to clean up.

## Lessons Learned

**1. Always capture server output to a log file.** The `EADDRINUSE` error was immediately obvious once I looked at `server.log`. I should have done this from the start.

**2. Kill by port, not by pidfile.** `lsof -ti :3098 | xargs kill -9` is far more reliable than `kill "$(cat tmp/pids/server.pid)"`. Pidfiles can be stale, wrong, or missing.

**3. Don't daemonize in test scripts.** Background processes (`&`) give you a real PID you can track. Daemonized processes are harder to manage and can become zombies.

**4. When debugging cross-process issues, verify the processes first.** Before debugging the database, the middleware, or the subscriber — check that the server you're talking to is the server you think it is.

**5. SQLite WAL mode is real, but not your first suspect.** Cross-process SQLite visibility issues are a real thing, but in practice `clear_query_cache` is usually sufficient. If your counts are stuck at exactly 0 (not "sometimes stale"), look for a process-level problem first.

## The Final Numbers

```
FINAL RESULTS
  Apps tested: 4
  Apps passed: 4

  Total assertions: 1025+
  Passed: 1025+
  Failed: 0

  ALL TESTS PASSED
```

Four temporary Rails apps. Production mode. Real HTTP requests. Real exceptions. Middleware capture, subscriber capture, deduplication, severity classification, request context, custom error types, dashboard rendering.

All from a gem that has zero external dependencies, runs entirely inside your Rails process, and installs with one command.

If you're looking for self-hosted error tracking that doesn't phone home to a SaaS, check out [rails_error_dashboard](https://github.com/AnjanJ/rails_error_dashboard).

---

*This post is part of a series about building rails_error_dashboard. Previously: [Setting Up Self-Hosted Error Tracking with Rails 8.1 + SolidQueue](https://medium.com/@anjan.jagirdar).*
