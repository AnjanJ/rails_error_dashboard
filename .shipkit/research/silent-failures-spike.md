# Spike S2: what changes for the host if a failed capture becomes visible

> Researched 2026-11-20 for the spec `hardening-1-0-rc2` (T2, decision 8 in `intake.md`), on branch
> `spec/hardening-1-0-rc2` at `14550b01`. Every probe ran on one MacBook (Apple silicon, macOS 27.2), Ruby 3.4.5,
> against rc.1's code. No product code was changed, and nothing in the repository was written except this file.
> The probe code is in Appendix B; the scratch folder was `/tmp/red-s2`.

## The answer

- **A failed capture isn't silent everywhere today, and where it's loud it's loud in the wrong way.**
  - **Sync capture** (the library default): a failed capture leaves nothing in the host's log at RED's default
    settings.
  - **Async capture** (what the installer writes): when the store raises a database error, every lost capture
    already writes **8 RED lines (about 15 KB)** plus **11 Active Job lines (about 61 KB)**. No RED setting stops
    them. They carry the user id, IP address, user agent, exception message and backtrace. Params and the URL are
    filtered.
  - **A payload error on the worker** (for example `ActiveModel::UnknownAttributeError` from a column a migration
    didn't add) is dropped without a word from RED, and the job reports success.
  - **`GET /health`** already answers `down` when RED's tables are missing or its database is unreachable. It
    can't see a write that fails for any other reason.
- **Turning on `log_level :error` as it is would print passwords.**
  - The capture-failure Context line (`log_error.rb:785`) prints the raw request params:
    `"password":"hunter2-secret"`, the card number, the email and the reset token, all in clear. Rails' own
    `Parameters:` line for the same request filters every one of them. Reproduced on Rails 7.2, 8.0 and 8.1.
  - On PostgreSQL, a rejected row's error message quotes the row: `DETAIL: Failing row contains (…, 4711, …,
    203.0.113.77, …)`.
  - Anyone who follows the installer's "production troubleshooting" comment (`log_level = :error`,
    `templates/initializer.rb:499-500`) gets this today.
- **`enable_internal_logging` doesn't gate errors.** `Logger.error` checks only `log_level` (`logger.rb:77-80`).
  `debug`, `info` and `warn` check both switches (`logger.rb:41`, `:53`, `:65`). Reproduced: with
  `enable_internal_logging = false` and `log_level = :error`, every failure line printed. None of the four options
  needs to touch `enable_internal_logging`.
- **Volume.** A 60 s storm against a broken schema, at 200 reports a second on 3 threads (12,003 reports), the same
  on Rails 7.2, 8.0 and 8.1. Sync capture:

  | Storm protection | Captures reaching the failing write | `:error` adds |
  |---|---|---|
  | on (the default), 1 error class | 77 | 308 writes, about 165 KB |
  | on, 20 error classes | 499 | 1,996 writes, about 1 MB |
  | off | all 12,003 | 48,008 writes, 108,018 lines, 25.1 MB |

  At RED's default `:silent`, the sync path adds nothing.

  Async capture with storm protection off is already the loudest case at `:silent`. One minute of storm made the
  worker run 36,009 attempts, which wrote:
  - 96,024 ungated RED writes (54 MB);
  - 132,033 Active Job writes (95 MB);
  - and at `:error`, another 144,036 writes (80 MB).
- **Cost.** One `Rails.logger.error` through the logger a new Rails app gets (STDOUT, tagged, synchronous) costs
  about 3.3 µs median on Rails 8.x, and 4.7 µs on 7.2. The whole 4-line failure block costs 17-28 µs, and a
  failing capture about 20 µs more than at `:silent`, far inside the 5 ms budget. The cost isn't the risk:
  - a log write blocks when the log's reader stalls, and while it's blocked every other thread that logs waits too
    (reproduced: 61,754 bytes went through, then a second thread couldn't write a line for 3.5 s);
  - Rails' own request lines already carry that risk, so what RED adds is volume.
- **Recommendation: option 2, the trimmed, rate-limited line, under four safety conditions.** It is the only option
  that makes a failure visible on every path, the async worker included, with bounded volume and no new setting.
  It is safe only if:
  - the trimmed line drops the messages as well as the context;
  - it covers all 32 capture-path call sites and the 4 flush-job sites;
  - it is keyed by call site and failure class;
  - the detail stays reachable at `debug`.

  Option 3 (a count on `/health`) is a cheap add-on, but it can't see a worker process.
  Two fixes are needed whichever option is chosen: the Context lines must stop printing raw params, and RED's
  capture job should stop Active Job from logging its arguments (`log_arguments = false`). The maintainer picks;
  see "Recommendation".

## What was run

- **Databases.** SQLite 3.54.1 (in the sqlite3 2.10.2 gem). PostgreSQL 16.16 (Homebrew). MySQL 8.4.13 (Homebrew
  `mysql@8.4`, the series CI runs, `test.yml:93`), a throwaway server on port 3307. Adapters: `pg` 1.7.0 and
  `trilogy` 2.13.3, as in CI. Every database was a throwaway created for this spike, and each print run got a
  fresh one.
- **Rails.** 7.2.4, 8.0.5.2 and 8.1.4.1, each from its own bundle outside the repository (a Gemfile that
  `eval_gemfile`s the repo's, with `RAILS_VERSION` set). Solid Queue 1.7.2, Puma 8.1.2 (read, not run).
- **The host's logger, as a new app gets it.** The probe boot builds `config.logger` the way each version's
  `production.rb` template does, before the app initialises:
  - 7.2: `ActiveSupport::Logger.new(STDOUT)` with `::Logger::Formatter`, wrapped in `TaggedLogging`
    (`railties-7.2.4 …/production.rb.tt:66-68`);
  - 8.0 and 8.1: `ActiveSupport::TaggedLogging.logger(STDOUT)` (`railties-8.0.5.2 …/production.rb.tt:42`,
    `railties-8.1.4.1 …/production.rb.tt:50`).

  It also sets `config.log_level = "info"` and `config.log_tags = [ :request_id ]` (all three templates), and the
  template's `filter_parameter_logging.rb` list (`:passw, :email, :secret, :token, :_key, :crypt, :salt,
  :certificate, :otp, :ssn`, plus `:cvv, :cvc` from 8.0). Rails wraps that logger in a `BroadcastLogger`, as it
  does in a real app.
- **RED's settings, as a host gets them.** Storm protection on (`configuration.rb:376`). `async_logging` true (the
  installer, `templates/initializer.rb:194`) or false (the library default, `configuration.rb:389`), run both
  ways. `enable_internal_logging = false` (installer `:487`). `log_level` is `:silent` (installer `:492`) or
  `:error`, the change under study, run both ways where it matters.
- **Captures.** A host controller raises inside a real request through the full middleware stack
  (`Rails.application.call`). The request is a `POST` with `user[email]`, `user[password]`, `card_number`, and a
  query string carrying `email` and `reset_token`, from `203.0.113.77` with a browser user agent. The controller
  sets `Rails.error.set_context(user_id: 4711)`, a common way hosts attach the user. The storm probe skips the
  host's own request lines: it leaves the request env in `Thread.current`, as `ErrorCatcher` does, and calls
  `Rails.error.report(…, source: "application.action_dispatch")`, as `ActionDispatch::Executor` does.
- **The worker.** A real Solid Queue `Worker` (3 threads) and `Dispatcher` in their own process. Retries, the
  `retry_on` exhaustion block and any re-report therefore ran as they do on a host. It runs until nothing is
  ready, scheduled or claimed.
- **Schema breaks.** Each break happens after a warm-up capture, so the application row exists and the schema is
  cached, as in a process that has been running:

  | Break | What it stands for | What RED gets |
  |---|---|---|
  | `no_table` | RED's table is gone (an unmigrated or dropped error database) | `ActiveRecord::StatementInvalid` |
  | `no_column_live` | a column RED writes vanishes under a running process | `ActiveRecord::StatementInvalid` |
  | `no_column_boot` | the column was already missing when the process booted (gem upgraded, migration not run) | `ActiveModel::UnknownAttributeError` |
  | `not_null` | the database rejects the row (PostgreSQL and MySQL; SQLite can't drop a default in place) | `ActiveRecord::NotNullViolation` |

- **Counting.** A probe-only hook on `Logger::LogDevice#write` attributes every write to the code that made it,
  by its first recognisable caller frame: a RED file and line, Active Job's log subscriber, Solid Queue, or Rails'
  request logging. "Writes" are log calls; "lines" are physical lines, which is what a log shipper counts. The
  hook was off for every timing run.
- **What is reproduced and what is only read.** Every table is reproduced by the probe named in Appendix B. Facts
  marked "read" come from source or documentation and were not run.

## What reaches the host's log today, path by path (reproduced)

Per failed capture, RED's lines only. "Gated" means `log_level` controls it. Rails 8.1, all three databases; the
Rails 7.2 and 8.0 rows match (Appendix A2).

| Path | Break | `log_level :silent` (default) | `log_level :error` |
|---|---|---|---|
| sync, in a request | any of the four | nothing | 4 writes, 8-11 lines, 1.4-3.1 KB (`log_error.rb:783-786`) |
| sync, outside a request (job, console, rake) | any | nothing | 4 writes, 8-11 lines |
| async, enqueue fails too (falls back to sync) | any | nothing | 5 writes (`log_error.rb:294` + 783-786) |
| async, worker | `no_table` | **8 ungated writes, about 15 KB** | 20 writes: 12 gated + 8 ungated |
| async, worker | `no_column_boot` | **nothing: the job reports success** | 4 gated writes |

On top of RED's lines, Active Job's own log subscriber writes at `info`, the production default:

| Path | Active Job lines per capture | Size |
|---|---|---|
| any async capture, **healthy or not** (`Enqueued … with arguments`) | 1 | about 12 KB |
| async capture lost to a store error, on the worker (3 attempts: performing, retrying, performed, then retry stopped) | 11, plus the request's `Enqueued` line | about 61 KB |
| async capture lost to a payload error (`no_column_boot`) | 2 | about 12 KB |

What the ungated worker lines are:
- `async_error_logging_job.rb:53`, once per attempt: "AsyncErrorLoggingJob: error storage unavailable (…) — will
  retry".
- `application_job.rb:21-25`, `retry_on`'s exhaustion block, once after the third attempt. It writes 5 lines,
  among them `Job arguments: #{job.arguments.inspect}` (about 12 KB) and a 10-frame backtrace.

The worker didn't re-report its own failure: in the 20 worker-path runs, no capture job ever spawned another (each
run's 3 captures made exactly 3 job rows, or 9 with their retries).
`retry_on` with a block yields on exhaustion instead of re-raising, so Rails reports nothing (read:
`activejob-8.1.4.1 exceptions.rb:72-73`, `activejob-7.2.4 exceptions.rb:69-70`). 8.1's `report:` option defaults
to false. The comment at `async_error_logging_job.rb:49-52` says otherwise and is stale.

## Every `Logger.error` call site (counted with Prism, reproduced)

54 calls in 21 files (the raw grep's "about 55 in 23" counted comments). Appendix A lists every one.

| Where it runs | Sites | Fires |
|---|---|---|
| capture path, during the capture | 32 | per failed capture; the gate's 3 flush sites at most once per flush interval |
| storm flush job (worker) | 4 | per failed flush attempt |
| process exit (`Gate.drain!` from `at_exit`, `engine.rb:222`) | 1 | once |
| plugin registration (boot) | 1 | once per failing plugin |
| dashboard actions (batch actions, queries, source and blame readers) | 16 | per failing dashboard action, never during a capture |

Logging that bypasses `RailsErrorDashboard::Logger`, so no RED setting gates it, counted the same way
(`census_bypass.rb`): 122 direct `Rails.logger` calls, 90 of them at `error`.
- 59 are in `app/jobs`: the capture job, `ApplicationJob`'s `retry_on` block, the flush job and the notification
  jobs.
- 35 are in queries and services, 13 in the dashboard's controllers and 4 in its helpers.
- The other 11:
  - `engine.rb` (4), `configuration.rb` and `deprecation.rb`, all at boot;
  - the batch commands (3) and `helpers/user_model_detector.rb`;
  - `value_objects/error_context.rb:199`, which is on the capture path but logs at `debug`, below the production
    level.

On the capture path, only two of these files fire per capture: `async_error_logging_job.rb` (lines 53, 59-60) and
`application_job.rb` (21-25). `storm_flush_job.rb:36` fires per failed flush.

## What the capture-path lines print (reproduced)

Rails 8.1. Each line carries the request's tag and, on 8.x, nothing else. 7.2's formatter adds
`E, [time #pid] ERROR -- : `.

| Site | Prints | Personal data seen |
|---|---|---|
| `log_error.rb:783` | the failure's class and message | SQL text with placeholders, no values. **PostgreSQL `not_null`: the whole row**, 64 bytes a column: user id, filtered URL and params, user agent, IP, message, backtrace |
| `log_error.rb:784` | the reported exception's class and message | whatever the host's exception message holds |
| `log_error.rb:785` | `@context.inspect.truncate(500)` | **sync: raw params (password, card number, email, token), raw URL query, user id, user agent, IP.** Worker: the same keys, params and URL filtered, because `redact_async_payload` runs before the enqueue |
| `log_error.rb:786` | 5 backtrace frames | file paths |
| `error_reporter.rb:73` | `context.inspect.truncate(500)` before RED builds its context | the request's URL with its **raw query string**, the IP, and the `inspect` of every object the host passed |
| `error_hash_generator.rb:187` | a host `custom_fingerprint` lambda's failure | the host's exception message; fires on **every** capture while the lambda is broken, and the capture is still stored |
| `plugin.rb:127-129` | a host plugin's failure, its version, 10 frames | the plugin's exception message (the probe's included a user id); fires on every capture |

The two Context lines are the defect. `log_error.rb:785` prints `@context`, which holds the raw
`request.params` from `ErrorContext#extract_params` (`error_context.rb:119-125`). Filtering happens later, into
`attributes` (`log_error.rb:603`), so the failure line sees what the database never does.

Messages by database, `no_table` (reproduced):
- SQLite: `SQLite3::SQLException: no such table: rails_error_dashboard_error_logs:` and the SQL.
- PostgreSQL: `PG::UndefinedTable: ERROR: relation "rails_error_dashboard_error_logs" does not exist`, `LINE 1:
  SELECT …`.
- MySQL: `Trilogy::ProtocolError: 1146: Table 'red_s2_81.rails_error_dashboard_error_logs' doesn't exist`.
- MySQL `not_null`: `1364: Field 'probe_required' doesn't have a default value`, no values.

Every first line carries a double prefix, `[RailsErrorDashboard] [RailsErrorDashboard]`. The message has one and
`formatted_message` adds another (`logger.rb`). Cosmetic.

## A 60 s storm against a broken schema (reproduced)

`storm.rb` then `worker.rb`, SQLite, one process with 3 request threads at 200 reports a second for 60 s. RED's
table is gone (`no_table`), `log_level :error`, and each report is one unhandled request error with the probe's
request context. "`:error` adds" counts only the gated lines, so at the default `:silent` that column is zero.
"Ungated RED" and "Active Job" are written at `:silent` too. After each storm a real worker ran everything it
queued: capture jobs, flush jobs and the storm notification.

| Rails | Mode | Storm protection | Classes | Reports | Reached the write | Request process: `:error` adds | Request process: Active Job | Worker: jobs run | Worker: `:error` adds | Worker: ungated RED | Worker: Active Job |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 7.2 | sync | on | 1 | 12003 | 77 | 308 writes, 693 lines, 182 KB | 3 writes, 2 KB | 7 rows, 3 pending at 420s | see note | see note | see note |
| 8.0 | sync | on | 1 | 12003 | 77 | 308 writes, 693 lines, 165 KB | 3 writes, 2 KB | 7 | 12 writes, 3 KB | 11 writes, 7 KB | 24 writes, 13 KB |
| 8.1 | sync | on | 1 | 12003 | 77 | 308 writes, 693 lines, 165 KB | 3 writes, 2 KB | 7 | 12 writes, 3 KB | 11 writes, 7 KB | 24 writes, 13 KB |
| 7.2 | sync | on | 20 | 12003 | 499 | 1996 writes, 4491 lines, 1.2 MB | 3 writes, 19 KB | 7 | 12 writes, 4 KB | 11 writes, 25 KB | 24 writes, 101 KB |
| 8.0 | sync | on | 20 | 12003 | 499 | 1996 writes, 4491 lines, 1.0 MB | 3 writes, 19 KB | 7 | 12 writes, 3 KB | 11 writes, 24 KB | 24 writes, 100 KB |
| 8.1 | sync | on | 20 | 12002 | 499 | 1996 writes, 4491 lines, 1.0 MB | 3 writes, 19 KB | 7 | 12 writes, 3 KB | 11 writes, 24 KB | 24 writes, 100 KB |
| 7.2 | sync | off | 1 | 12003 | 12003 | 48012 writes, 108027 lines, 27.7 MB | 0 writes, 0 KB | 0 | 0 writes, 0 KB | 0 writes, 0 KB | 0 writes, 0 KB |
| 8.0 | sync | off | 1 | 12002 | 12002 | 48008 writes, 108018 lines, 25.1 MB | 0 writes, 0 KB | 0 | 0 writes, 0 KB | 0 writes, 0 KB | 0 writes, 0 KB |
| 8.1 | sync | off | 1 | 12003 | 12003 | 48012 writes, 108027 lines, 25.1 MB | 0 writes, 0 KB | 0 | 0 writes, 0 KB | 0 writes, 0 KB | 0 writes, 0 KB |
| 7.2 | sync | off | 20 | 12003 | 12003 | 48012 writes, 108027 lines, 27.7 MB | 0 writes, 0 KB | 0 | 0 writes, 0 KB | 0 writes, 0 KB | 0 writes, 0 KB |
| 8.0 | sync | off | 20 | 12003 | 12003 | 48012 writes, 108027 lines, 25.1 MB | 0 writes, 0 KB | 0 | 0 writes, 0 KB | 0 writes, 0 KB | 0 writes, 0 KB |
| 8.1 | sync | off | 20 | 12002 | 12002 | 48008 writes, 108018 lines, 25.1 MB | 0 writes, 0 KB | 0 | 0 writes, 0 KB | 0 writes, 0 KB | 0 writes, 0 KB |
| 7.2 | async | on | 1 | 12003 | 77 | 0 writes, 0 lines, 0 KB | 80 writes, 97 KB | 161 rows, 80 pending at 420s | see note | see note | see note |
| 8.0 | async | on | 1 | 12002 | 77 | 0 writes, 0 lines, 0 KB | 80 writes, 94 KB | 238 | 936 writes, 528 KB | 627 writes, 363 KB | 871 writes, 643 KB |
| 8.1 | async | on | 1 | 12003 | 77 | 0 writes, 0 lines, 0 KB | 80 writes, 94 KB | 238 | 936 writes, 528 KB | 627 writes, 363 KB | 871 writes, 643 KB |
| 7.2 | async | on | 20 | 12003 | 499 | 0 writes, 0 lines, 0 KB | 502 writes, 631 KB | 1504 rows, 31 pending at 420s | see note | see note | see note |
| 8.0 | async | on | 20 | 12002 | 499 | 0 writes, 0 lines, 0 KB | 502 writes, 606 KB | 1504 | 6000 writes, 3.3 MB | 4003 writes, 2.3 MB | 5513 writes, 4.0 MB |
| 8.1 | async | on | 20 | 12003 | 499 | 0 writes, 0 lines, 0 KB | 502 writes, 606 KB | 1504 | 6000 writes, 3.3 MB | 4003 writes, 2.3 MB | 5513 writes, 4.0 MB |
| 7.2 | async | off | 1 | 12003 | 12003 | 0 writes, 0 lines, 0 KB | 12003 writes, 14.4 MB | 36009 | 144036 writes, 86.4 MB | 96024 writes, 58.4 MB | 132033 writes, 101.3 MB |
| 8.0 | async | off | 1 | 12003 | 12003 | 0 writes, 0 lines, 0 KB | 12003 writes, 13.8 MB | 36009 | 144036 writes, 79.9 MB | 96024 writes, 54.1 MB | 132033 writes, 95.0 MB |
| 8.1 | async | off | 1 | 12003 | 12003 | 0 writes, 0 lines, 0 KB | 12003 writes, 13.8 MB | 36009 | 144036 writes, 79.9 MB | 96024 writes, 54.1 MB | 132033 writes, 95.0 MB |
| 7.2 | async | off | 20 | 12002 | 12002 | 0 writes, 0 lines, 0 KB | 12002 writes, 14.4 MB | 36006 | 144024 writes, 86.4 MB | 96016 writes, 58.4 MB | 132022 writes, 101.3 MB |
| 8.0 | async | off | 20 | 12003 | 12003 | 0 writes, 0 lines, 0 KB | 12003 writes, 13.8 MB | 36009 | 144036 writes, 79.9 MB | 96024 writes, 54.1 MB | 132033 writes, 95.0 MB |
| 8.1 | async | off | 20 | 12003 | 12003 | 0 writes, 0 lines, 0 KB | 12003 writes, 13.8 MB | 36009 | 144036 writes, 79.9 MB | 96024 writes, 54.1 MB | 132033 writes, 95.0 MB |

Notes:
- **Storm protection decides the volume.** With it on, the breaker opens within the first second and stays open
  through its 60 s cooldown. Only the captures admitted before it opens reach the write: 77 for one fingerprint,
  499 for 20 (`storm_fingerprint_full_per_minute`, `storm_open_threshold_per_second`, `configuration.rb:377-381`).
  With it off, every report reaches the write, so the line count is the report rate times 4.
- **Sync: `:error` costs 4 writes per failed capture**, the same on every Rails version, error class count and
  database (the print matrix).
- **Async: the request process writes no RED lines**, because the enqueue works. Active Job's `Enqueued … with
  arguments` line is written for every admitted capture. Here it was about 1.2 KB, because the storm probe's
  exceptions have short backtraces. A real request's backtrace makes it about 12 KB (the print matrix).
- **The worker multiplies.** Each lost capture is tried 3 times. At `:silent` that makes 8 ungated RED writes and 11
  Active Job writes; `:error` adds 12. The gate's flush jobs fail on the same broken schema, and add 12 gated
  writes (`flush_storm_counts.rb:79`, `:136`) and 11 ungated ones per minute.
- **Rails 7.2, storm protection on.** In three runs (marked "pending"), Solid Queue's dispatcher thread died on
  `SQLite3::BusyException: database is locked`. That left retries scheduled and never run, so those rows show
  only the request process. Reproduced alone: it's SQLite locking with a dispatcher and a worker in one process on
  7.2, not RED's logging. Run alone, it happened in 1 of 2 runs, so it is intermittent. The same 7.2 worker passed
  every run of the worker-path matrix, with the same per-capture counts as 8.0 and 8.1.
- **Rails 7.2 writes the same lines, about 10% bigger**: its template's `::Logger::Formatter` prefixes each one with
  a timestamp, pid and severity.

## What one log call costs on the capture path (reproduced)

`logcost.rb`, one run at a time on an idle machine. It used the logger each version's template builds, at level
`info`, inside a request's tag, against a fresh SQLite database. µs, median / p95 / p99. Per call: 20,000 calls,
and 5,000 for the block. End to end: 1,500 failing captures, alternating `:silent` and `:error` in blocks of 50.

| Rails | Log target | One `Rails.logger.error` | The same, below the host's level | Failure block, `:silent` | Failure block, `:error` | Failing capture, `:silent` | Failing capture, `:error` |
|---|---|---|---|---|---|---|---|
| 8.1 | Logger opened by path | 3.38 / 5.17 / 6.29 | 0.29 / 0.33 / 0.38 | 6.67 / 8.29 / 14.0 | 22.29 / 25.83 / 70.75 | 151.92 / 325.5 / 440.21 | 173.46 / 347.67 / 511.25 |
| 8.1 | STDOUT into a file | 3.29 / 3.88 / 8.87 | 0.29 / 0.33 / 0.42 | 6.67 / 7.79 / 13.37 | 22.21 / 28.71 / 100.42 | 152.62 / 328.08 / 657.58 | 173.04 / 348.96 / 517.37 |
| 8.1 | STDOUT into a drained pipe | 1.67 / 2.21 / 7.42 | 0.29 / 0.33 / 0.37 | 6.62 / 7.79 / 14.33 | 17.04 / 18.83 / 48.04 | 151.12 / 304.12 / 433.63 | 166.29 / 320.92 / 385.75 |
| 8.0 | Logger opened by path | 3.42 / 5.38 / 9.46 | 0.33 / 0.42 / 0.46 | 6.71 / 8.33 / 12.79 | 23.5 / 28.5 / 49.08 | 146.96 / 310.5 / 546.46 | 167.58 / 350.37 / 515.67 |
| 8.0 | STDOUT into a file | 3.33 / 4.63 / 8.79 | 0.29 / 0.33 / 0.42 | 6.67 / 7.92 / 13.5 | 22.08 / 26.75 / 60.29 | 147.46 / 296.12 / 425.75 | 168.42 / 333.17 / 455.92 |
| 8.0 | STDOUT into a drained pipe | 1.71 / 2.33 / 7.0 | 0.33 / 0.37 / 0.42 | 6.62 / 7.79 / 12.29 | 17.5 / 21.96 / 54.58 | 146.79 / 299.71 / 436.67 | 161.79 / 317.25 / 474.38 |
| 7.2 | Logger opened by path | 4.79 / 6.79 / 10.21 | 0.29 / 0.33 / 0.37 | 6.71 / 8.21 / 14.75 | 28.29 / 32.88 / 94.42 | 144.0 / 246.38 / 316.21 | 173.62 / 335.54 / 508.63 |
| 7.2 | STDOUT into a file | 4.67 / 5.96 / 8.75 | 0.29 / 0.33 / 0.42 | 6.71 / 8.54 / 16.58 | 27.71 / 32.0 / 112.33 | 144.63 / 243.96 / 442.0 | 171.96 / 322.62 / 490.5 |
| 7.2 | STDOUT into a drained pipe | 3.33 / 4.21 / 5.33 | 0.29 / 0.33 / 0.42 | 6.67 / 7.96 / 13.17 | 24.63 / 26.79 / 101.58 | 146.5 / 279.63 / 479.83 | 169.33 / 315.38 / 508.63 |

- **"One call"** is a line the size of the first failure line. The amortised figures agree: 3.6 µs for 8.1's
  file targets, 2.1 µs for the pipe, 4.9-5.2 µs for 7.2. Rails 7.2 costs more because its template adds
  `::Logger::Formatter`, which prints a timestamp, pid and severity on every line.
- **The failure block** is `log_error.rb:783-786` with a real failure, a real request's context and 5 frames.
  - At `:silent` it still costs about 6.7 µs: Ruby builds the interpolated strings, `@context.inspect` included,
    before `Logger.error` checks the level. RED's own silent `Logger.error` costs 0.13 µs.
  - At `:error` it costs 17-28 µs median, with a p99 of 48-112 µs.
- **End to end**, a failing sync capture costs about 150 µs at `:silent`; `:error` adds about 15-30 µs to the
  median. Both are far inside the 5 ms capture budget. Most of the 150 µs is building the context and the failing
  query, not logging.
- **Options 2 and 3, prototyped** (`proto_cost.rb`, Rails 8.1, 200,000 calls, best of 3; an empty block costs
  18 ns):

  | Prototype | One thread | 3 threads at once |
  |---|---|---|
  | Option 2: a mutex-guarded hash of call site and failure class to last time, suppressing | 0.19 µs | 0.23 µs |
  | Option 3: an atomic increment plus the last failure's class and time | 0.20 µs | 0.22 µs |

  Option 2 also writes one line per key per minute, about 2-5 µs once a minute.
- **So cost doesn't decide this.** Every option is within budget. What decides it is what gets printed, how much,
  and what happens when the log's reader stalls (next section).

## A stalled log reader (reproduced, and read)

- **Read.** Puma sets `STDOUT.sync = true` by default (`mutate_stdout_and_stderr_to_sync_on_write: true`,
  `puma-8.1.2 configuration.rb:162`, `runner.rb:151-153`), and so does Solid Queue's supervisor
  (`supervisor.rb:159`). A logger opened by path sets `sync = true` too (`logger-1.7.0 log_device.rb:126`). Every
  log call is therefore one `write(2)`, made while holding the `LogDevice`'s monitor (`log_device.rb:27-35`).
- **Reproduced** (`stall.rb`). The host's logger writes to STDOUT, and STDOUT is a pipe nobody reads. One thread
  logs failure lines; a second logs one Rails-style `Completed 200 OK` line every 100 ms.
  - After 61,754 bytes (138 calls, the macOS pipe buffer), the first thread blocked.
  - The second thread never wrote its first line in 3.5 s: it waits for the same monitor.
- **Read** (Docker, "Configure logging drivers"). `blocking` is the default delivery mode from container to log
  driver. The page warns that "applications are likely to fail in unexpected ways when STDERR or STDOUT streams
  block". `non-blocking` drops messages when its buffer (1 MB by default) is full. Rails 8.0 and 8.1 generate a Kamal
  deploy, which runs the app in Docker, unless `--skip-kamal` is given (read: `config/deploy.yml.tt`, `app_base.rb:111`
  and `:115`); 7.2 doesn't.
- **So:** a stalled log reader already stalls a Rails app through its own per-request lines; RED doesn't create
  that risk. What RED changes is how fast a slow reader's buffer fills. That is a matter of volume, which the
  storm table measures.

## The four options side by side

What each option means here:
1. **`log_level :error` as it is.** The default becomes `:error`; nothing else changes.
2. **`:error`, with the context removed and one line per class per minute.** The default becomes `:error`, and every
   capture-path failure line is trimmed and rate-limited per process.
3. **A per-process failure count on `/health`, with no log I/O.** The default stays `:silent`.
4. **No change.**

None of the four changes what existing installs do on its own. The installer writes `config.log_level = :silent`
uncommented (`templates/initializer.rb:492`), so every existing host keeps `:silent` until it edits that line. A new
default reaches new installs (if the template changes too), and hosts that removed the line.

| | 1. `:error` as is | 2. `:error`, trimmed, rate-limited | 3. count on `/health` | 4. no change |
|---|---|---|---|---|
| Sync storm, 60 s, storm protection on (the default), 1 / 20 error classes | 308 / 1,996 writes; 165 KB / 1.07 MB | 1 write per failure class per minute (the failure class, not the reported class, so 1 here either way) | 0 | 0 |
| The same with storm protection off | 48,008 writes, 108,018 lines, 25.1 MB | still 1 a minute | 0 | 0 |
| Async worker, per capture lost to a store error | +12 gated writes, on top of today's 8 ungated | +1 a minute, on top of today's 8 ungated | 0 added | 8 ungated writes (about 15 KB) and 11 Active Job writes (about 61 KB) |
| Async worker, payload error (`no_column_boot`) | 4 writes per capture | 1 a minute | not visible (the worker process never answers `/health`) | nothing: lost without a trace |
| A host `custom_fingerprint` or plugin that raises, storage healthy | 1 or 3 writes on **every** capture | 1 a minute | 0 | 0 |
| Personal data in the host's log | **passwords, card numbers, tokens and emails in clear** (sync Context line); the URL's query; user id, IP, user agent; on PostgreSQL the rejected row | none, if the line carries classes and RED's call site only (see below) | none | today's worker lines: user id, IP, user agent, message and backtrace (params and URL filtered) |
| Added cost per failed capture | about 15-30 µs median (the 4-line block) | 0.19 µs suppressed; one 2-5 µs line a minute per key | 0.20 µs | 0 |
| Switch | `log_level :silent` (exists) | `log_level :silent` (exists) | needs one (rule 7), so a new public name frozen at 1.0 | n/a |
| `enable_internal_logging` | irrelevant: `Logger.error` doesn't read it | irrelevant; the detailed lines could move to `debug`, which needs it | irrelevant | irrelevant |
| Who sees it | anyone reading the host's log | anyone reading the host's log | only a caller of `GET /health` that reaches the process that failed | n/a |

What option 2 must include to be safe (each is a measured failure of a narrower version):
- **No messages, not only no context.** The failure's message carries PostgreSQL's quoted row, and the reported
  exception's message is the host's own text. A safe line names the failure class, the reported exception's class,
  RED's call site, and how many were suppressed since the last line.
- **All 32 capture-path sites and the 4 flush-job sites, not only `log_error.rb:783-786`.** Otherwise a broken
  plugin still prints 3 writes with a 10-line backtrace on every capture.
- **Keyed by call site and failure class.** That bounds it at a handful of lines a minute per process, whatever
  the storm.
- **The detail stays available on purpose.** The current lines, with the context filtered, could move to `debug`,
  so a host troubleshooting with `enable_internal_logging` and `log_level :debug` still gets them.

What option 3 can't do:
- `GET /health` reaches one process: one Puma worker in cluster mode, and never a job worker. With the installer's
  `async_logging = true`, captures fail in the job worker, so for the installer's default the count shows nothing.
- It resets on every deploy, and someone has to poll it. Making `/health` answer `degraded` when the count has
  risen recently would let an uptime monitor notice, as the storm check does now (`health_status.rb:140-151`).

## Recommendation

**Option 2, with its four safety conditions (see "The four options side by side"), and two fixes that apply
whichever option is chosen.**

Why option 2:
- It is the only option that makes a failed capture visible on every path: sync, the async enqueue, and the
  worker, including the payload errors that are lost without a trace today.
- Its volume is bounded by its design, not by storm protection: a handful of lines per process per minute, whatever
  the rate. Option 1 measured 48,008 writes (25.1 MB) a minute with storm protection off.
- It prints no personal data, provided it prints classes and RED's call site, not messages.
- It needs no new setting: `log_level :silent` is the switch, so rule 7 is met with a name that already exists.
- It costs 0.19 µs per suppressed failure, and one 2-5 µs line per key per minute.

Why not the others:
- **Option 1** prints passwords, card numbers, tokens and emails in clear (sync Context line), and PostgreSQL's
  quoted row. Its volume grows with the storm. Every broken host plugin or fingerprint lambda logs on every capture.
- **Option 3 alone** can't see a job worker, which is where captures fail under the installer's
  `async_logging = true`. It sees one Puma worker at a time, resets on deploy, and needs a new public name to switch
  it off. It's a reasonable add-on to option 2 for uptime monitors, not a replacement.
- **Option 4** leaves sync losses and payload losses invisible. It keeps the password trap for anyone who follows
  the installer's troubleshooting comment, and it keeps the unswitchable worker flood: 150 MB a minute in the
  storm-off measurement.

Two fixes, whichever option is chosen:
1. **The Context lines stop printing raw params and the raw URL.** These are `log_error.rb:785` and
   `error_reporter.rb:73`. Today any host at `log_level :error` gets passwords in its log; this is a defect, not a
   preference.
2. **RED's own jobs stop putting the capture payload in the host's log.**
   - `log_arguments = false` on `AsyncErrorLoggingJob` and `StormFlushJob`. The setting exists on Rails 7.2, 8.0
     and 8.1, and Active Job's own docs describe it as for jobs whose arguments "may be sensitive".
   - `application_job.rb:22` prints the job id instead of `job.arguments.inspect`.

   Today every async capture, healthy or not, writes about 12 KB with the user id, IP and user agent at `info`.

What option 2 changes for whom:
- **Existing installs: nothing.** Their initializer says `config.log_level = :silent` (`templates/initializer.rb:492`).
  The release notes would point them at it.
- **New installs** get the trimmed line by default once the template says `:error`.
- **Hosts already at `:error`** stop getting the detailed lines at `:error`. If the detail moves to `debug` (with
  the context filtered), they'd need `enable_internal_logging = true` and `log_level :debug` to see it.
- **The installer's comment and `CONFIGURATION.md`** must say that error lines need only `log_level`, not
  `enable_internal_logging`.

Decided separately, because the evidence supports more than one answer:
- whether the ungated worker lines (`async_error_logging_job.rb:53`, `:59-60`, `application_job.rb:21-25`,
  `storm_flush_job.rb:36`) go through the same limiter. That would make them switchable (rule 7), and stop them
  scaling with the storm;
- whether option 3 is added for `/health`, and if so under which name, and whether a recent failure makes `/health`
  answer `degraded`;
- whether the 16 dashboard-only sites, which never run during a capture, keep printing their messages at `:error`.

I would reverse this recommendation if:
- `bin/benchmark` shows option 2's failure path adding more than 5 µs to a failed capture's median (the prototype
  measured 0.19 µs suppressed); or
- a host shows option 2 printing more than 10 lines a minute per process in a storm (by design it should print
  about one per call site and failure class).

## Limits

- **One laptop.** Timings are macOS on Apple silicon, so they show orders of magnitude, not budgets;
  `bin/benchmark` judges budgets. macOS's `CLOCK_MONOTONIC` resolves 1 µs, so per-call timings use
  `CLOCK_MONOTONIC_RAW` (42 ns).
- **Storms ran on SQLite only, three at a time** (one per Rails version). The line counts don't depend on the
  adapter: the print matrix shows the same 4 writes per failed capture on all three databases, with byte sizes
  that differ by message. Capture times inside the storm runs aren't used anywhere, because three storms shared
  the machine.
- **The rate is chosen, not measured from a host.** 200 reports a second on 3 threads stands for one busy process
  with a broken endpoint. Lines scale linearly with the rate when storm protection is off; with it on, the gate's
  thresholds bound them (`configuration.rb:377-381`).
- **Option 2 and option 3 are prototypes in the probe**, not product code. Their line counts follow from their
  design, and their costs are the prototypes' (`proto_cost.rb`). A real implementation must be measured again by
  `bin/benchmark`.
- **The stall was reproduced with a macOS pipe**, whose buffer took 61,754 bytes. Linux's pipe buffer size was not checked. Docker's blocking mode is read
  from its documentation, not run.
- **The host's own request lines are not representative.** The probe's controller lives outside `Rails.root`, so
  Rails logged the whole framework backtrace (72 lines per request). That's why this file compares RED's lines
  with each other, and never with the host's.
- **A database that is down** (`ConnectionNotEstablished`) wasn't stormed. On the worker it goes through the same
  `RETRYABLE_STORE_ERRORS` path as `no_table` (`log_error.rb:15-20`, read), and `/health` already reports it.
- **Other queue adapters weren't run.** Active Job's argument lines come from Active Job's log subscriber, so they
  don't depend on the adapter (read: `log_subscriber.rb:205`). Sidekiq's own failure logging is not covered.

## Appendix A: every table

### A1. Every `Logger.error` call site (`census.rb`, then `appendix_a.rb`)

| # | Site | Method | Path | Prints |
|---|---|---|---|---|
| 1 | `app/jobs/rails_error_dashboard/retention_cleanup_job.rb:100` | `perform` | dashboard or maintenance (never during a capture) | the failure's message |
| 2 | `commands/batch_delete_errors.rb:38` | `call` | dashboard or maintenance (never during a capture) | the failure's message |
| 3 | `commands/batch_mute_errors.rb:65` | `call` | dashboard or maintenance (never during a capture) | the failure's message |
| 4 | `commands/batch_resolve_errors.rb:73` | `call` | dashboard or maintenance (never during a capture) | the failure's message |
| 5 | `commands/batch_unmute_errors.rb:59` | `call` | dashboard or maintenance (never during a capture) | the failure's message |
| 6 | `commands/flush_storm_counts.rb:79` | `call` | worker (StormFlushJob) | the failure's message |
| 7 | `commands/flush_storm_counts.rb:89` | `call` | worker (StormFlushJob) | the failure's message |
| 8 | `commands/flush_storm_counts.rb:136` | `call` | worker (StormFlushJob) | the failure's message |
| 9 | `commands/flush_storm_counts.rb:571` | `upsert_storm_event` | worker (StormFlushJob) | the failure's message |
| 10 | `commands/log_error.rb:59` | `call` | capture | the failure's message |
| 11 | `commands/log_error.rb:73` | `call` | capture | the failure's message |
| 12 | `commands/log_error.rb:258` | `enqueue_after_response` | capture | the failure's message |
| 13 | `commands/log_error.rb:294` | `enqueue_async` | capture | the failure's message |
| 14 | `commands/log_error.rb:400` | `redact_async_payload` | capture | the failure's message |
| 15 | `commands/log_error.rb:754` | `call` | capture | the failure's message |
| 16 | `commands/log_error.rb:783` | `call` | capture | the failure's message |
| 17 | `commands/log_error.rb:784` | `call` | capture | the reported exception's message |
| 18 | `commands/log_error.rb:785` | `call` | capture | the capture's context (`inspect`, 500 chars) |
| 19 | `commands/log_error.rb:786` | `call` | capture | backtrace (5 frames) |
| 20 | `commands/log_error.rb:832` | `maybe_notify` | capture | the failure's message; an error id |
| 21 | `commands/log_error.rb:902` | `find_or_create_application` | capture | the failure's message |
| 22 | `commands/log_error.rb:913` | `trigger_callbacks` | capture | the failure's message |
| 23 | `commands/log_error.rb:921` | `trigger_callbacks` | capture | the failure's message |
| 24 | `commands/log_error.rb:951` | `emit_instrumentation_events` | capture | the failure's message; an error id |
| 25 | `commands/log_error.rb:989` | `check_baseline_anomaly` | capture | the failure's message |
| 26 | `commands/record_occurrence_context.rb:44` | `call` | capture | the failure's message |
| 27 | `error_reporter.rb:71` | `report` | capture | the failure's message |
| 28 | `error_reporter.rb:72` | `report` | capture | the reported exception's message |
| 29 | `error_reporter.rb:73` | `report` | capture | the capture's context (`inspect`, 500 chars) |
| 30 | `error_reporter.rb:74` | `report` | capture | backtrace (5 frames) |
| 31 | `middleware/error_catcher.rb:52` | `call` | capture | the failure's message |
| 32 | `middleware/error_catcher.rb:53` | `call` | capture | backtrace (5 frames) |
| 33 | `plugin.rb:127` | `safe_execute` | capture | the failure's message |
| 34 | `plugin.rb:128` | `safe_execute` | capture | fixed text |
| 35 | `plugin.rb:129` | `safe_execute` | capture | backtrace (10 frames) |
| 36 | `plugin_registry.rb:42` | `register` | boot (plugin registration) | the failure's message |
| 37 | `plugin_registry.rb:130` | `enabled?` | capture (each plugin dispatch) | the failure's message |
| 38 | `queries/dashboard_stats.rb:74` | `call` | dashboard or maintenance (never during a capture) | the failure's message |
| 39 | `queries/storm_history.rb:20` | `call` | dashboard or maintenance (never during a capture) | the failure's message |
| 40 | `services/analytics_cache_manager.rb:51` | `clear` | dashboard or maintenance (never during a capture) | the failure's message |
| 41 | `services/error_hash_generator.rb:187` | `try_custom_fingerprint` | capture | the failure's message |
| 42 | `services/git_blame_reader.rb:65` | `read_blame` | dashboard or maintenance (never during a capture) | the failure's message; a file path |
| 43 | `services/git_blame_reader.rb:114` | `execute_git_blame` | dashboard or maintenance (never during a capture) | the failure's message; a file path |
| 44 | `services/git_blame_reader.rb:261` | `parse_blame_output` | dashboard or maintenance (never during a capture) | the failure's message |
| 45 | `services/github_link_generator.rb:74` | `generate_link` | dashboard or maintenance (never during a capture) | the failure's message; a URL |
| 46 | `services/resolution_callbacks.rb:27` | `call` | dashboard or maintenance (never during a capture) | the failure's message |
| 47 | `services/resolution_callbacks.rb:39` | `call` | dashboard or maintenance (never during a capture) | the failure's message; an error id |
| 48 | `services/source_code_reader.rb:80` | `read_lines` | dashboard or maintenance (never during a capture) | the failure's message; a file path |
| 49 | `services/source_code_reader.rb:228` | `read_specific_lines` | dashboard or maintenance (never during a capture) | the failure's message; a file path |
| 50 | `services/storm_protection/gate.rb:40` | `admit!` | capture (every report: storm gate) | the failure's message |
| 51 | `services/storm_protection/gate.rb:155` | `drain!` | capture (at exit: `Gate.drain!` from `at_exit`, engine.rb:222) | the failure's message |
| 52 | `services/storm_protection/gate.rb:380` | `maybe_flush!` | capture (at most once per flush interval) | the failure's message |
| 53 | `services/storm_protection/gate.rb:388` | `maybe_flush!` | capture (at most once per flush interval) | the failure's message |
| 54 | `services/storm_protection/gate.rb:423` | `maybe_storm_notification` | capture (at most once per flush interval) | the failure's message |

### A2. The print matrix (`prints.rb`, `log_level :error`), per capture

Captures 2 and 3 matched capture 1 in every run. "Active Job" is its log subscriber's lines in the request process.

| Database | Rails | Path | Break | RED writes | Lines | Bytes | RED sites | Active Job |
|---|---|---|---|---|---|---|---|---|
| mysql84 | 8.1 | after_response | no_column_boot | 0 | 0 | 0 |  | 1 (11.8 KB) |
| mysql84 | 8.1 | after_response | no_column_live | 0 | 0 | 0 |  | 1 (11.8 KB) |
| mysql84 | 8.1 | after_response | no_table | 0 | 0 | 0 |  | 1 (11.8 KB) |
| mysql84 | 8.1 | after_response | none | 0 | 0 | 0 |  | 1 (11.8 KB) |
| mysql84 | 8.1 | after_response | not_null | 0 | 0 | 0 |  | 1 (11.8 KB) |
| mysql84 | 8.1 | enqueue_fail | no_column_boot | 5 | 9 | 2228 | `log_error.rb:294`, `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 1 (0.3 KB) |
| mysql84 | 8.1 | enqueue_fail | no_column_live | 5 | 9 | 2004 | `log_error.rb:294`, `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 1 (0.3 KB) |
| mysql84 | 8.1 | enqueue_fail | no_table | 5 | 9 | 2025 | `log_error.rb:294`, `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 1 (0.3 KB) |
| mysql84 | 8.1 | enqueue_fail | none | 1 | 1 | 299 | `log_error.rb:294` | 1 (0.3 KB) |
| mysql84 | 8.1 | enqueue_fail | not_null | 5 | 9 | 2012 | `log_error.rb:294`, `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 1 (0.3 KB) |
| mysql84 | 8.1 | report | no_column_boot | 4 | 8 | 1671 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| mysql84 | 8.1 | report | no_column_live | 4 | 8 | 1447 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| mysql84 | 8.1 | report | no_table | 4 | 8 | 1468 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| mysql84 | 8.1 | report | none | 0 | 0 | 0 |  | 0 |
| mysql84 | 8.1 | report | not_null | 4 | 8 | 1455 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| mysql84 | 8.1 | request | no_column_boot | 4 | 8 | 1929 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| mysql84 | 8.1 | request | no_column_live | 4 | 8 | 1705 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| mysql84 | 8.1 | request | no_table | 4 | 8 | 1726 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| mysql84 | 8.1 | request | none | 0 | 0 | 0 |  | 0 |
| mysql84 | 8.1 | request | not_null | 4 | 8 | 1713 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| pg | 8.1 | after_response | no_column_boot | 0 | 0 | 0 |  | 1 (11.8 KB) |
| pg | 8.1 | after_response | no_column_live | 0 | 0 | 0 |  | 1 (11.8 KB) |
| pg | 8.1 | after_response | no_table | 0 | 0 | 0 |  | 1 (11.8 KB) |
| pg | 8.1 | after_response | none | 0 | 0 | 0 |  | 1 (11.8 KB) |
| pg | 8.1 | after_response | not_null | 0 | 0 | 0 |  | 1 (11.8 KB) |
| pg | 8.1 | enqueue_fail | no_column_boot | 5 | 12 | 2294 | `log_error.rb:294`, `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 1 (0.4 KB) |
| pg | 8.1 | enqueue_fail | no_column_live | 5 | 15 | 2676 | `log_error.rb:294`, `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 1 (0.4 KB) |
| pg | 8.1 | enqueue_fail | no_table | 5 | 15 | 2645 | `log_error.rb:294`, `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 1 (0.4 KB) |
| pg | 8.1 | enqueue_fail | none | 1 | 4 | 365 | `log_error.rb:294` | 1 (0.4 KB) |
| pg | 8.1 | enqueue_fail | not_null | 5 | 15 | 3483 | `log_error.rb:294`, `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 1 (0.4 KB) |
| pg | 8.1 | report | no_column_boot | 4 | 8 | 1671 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| pg | 8.1 | report | no_column_live | 4 | 11 | 2053 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| pg | 8.1 | report | no_table | 4 | 11 | 2022 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| pg | 8.1 | report | none | 0 | 0 | 0 |  | 0 |
| pg | 8.1 | report | not_null | 4 | 11 | 2675 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| pg | 8.1 | request | no_column_boot | 4 | 8 | 1929 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| pg | 8.1 | request | no_column_live | 4 | 11 | 2311 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| pg | 8.1 | request | no_table | 4 | 11 | 2280 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| pg | 8.1 | request | none | 0 | 0 | 0 |  | 0 |
| pg | 8.1 | request | not_null | 4 | 11 | 3118 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| sqlite | 7.2 | report | no_column_boot | 4 | 8 | 1854 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| sqlite | 7.2 | report | no_table | 4 | 9 | 2320 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| sqlite | 7.2 | request | no_column_boot | 4 | 8 | 2112 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| sqlite | 7.2 | request | no_table | 4 | 9 | 2578 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| sqlite | 8.0 | report | no_column_boot | 4 | 8 | 1671 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| sqlite | 8.0 | report | no_table | 4 | 9 | 2096 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| sqlite | 8.0 | request | no_column_boot | 4 | 8 | 1929 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| sqlite | 8.0 | request | no_table | 4 | 9 | 2354 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| sqlite | 8.1 | after_response | no_column_boot | 0 | 0 | 0 |  | 1 (11.8 KB) |
| sqlite | 8.1 | after_response | no_column_live | 0 | 0 | 0 |  | 1 (11.8 KB) |
| sqlite | 8.1 | after_response | no_table | 0 | 0 | 0 |  | 1 (11.8 KB) |
| sqlite | 8.1 | after_response | none | 0 | 0 | 0 |  | 1 (11.8 KB) |
| sqlite | 8.1 | enqueue_fail | no_column_boot | 5 | 10 | 2432 | `log_error.rb:294`, `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 1 (0.5 KB) |
| sqlite | 8.1 | enqueue_fail | no_column_live | 5 | 11 | 3624 | `log_error.rb:294`, `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 1 (0.5 KB) |
| sqlite | 8.1 | enqueue_fail | no_table | 5 | 11 | 2857 | `log_error.rb:294`, `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 1 (0.5 KB) |
| sqlite | 8.1 | enqueue_fail | none | 1 | 2 | 503 | `log_error.rb:294` | 1 (0.5 KB) |
| sqlite | 8.1 | report | no_column_boot | 4 | 8 | 1671 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| sqlite | 8.1 | report | no_column_live | 4 | 9 | 2863 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| sqlite | 8.1 | report | no_table | 4 | 9 | 2096 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| sqlite | 8.1 | report | none | 0 | 0 | 0 |  | 0 |
| sqlite | 8.1 | request | no_column_boot | 4 | 8 | 1929 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| sqlite | 8.1 | request | no_column_live | 4 | 9 | 3121 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| sqlite | 8.1 | request | no_table | 4 | 9 | 2354 | `log_error.rb:783`, `log_error.rb:784`, `log_error.rb:785`, `log_error.rb:786` | 0 |
| sqlite | 8.1 | request | none | 0 | 0 | 0 |  | 0 |

### A3. The worker matrix (`prints.rb` with `PATH_KIND=enqueue`, then `worker.rb`), 3 captures per run

| Database | Rails | Break | `log_level` | Job rows | Seconds | Gated RED writes | Ungated RED writes | Active Job writes | Total bytes |
|---|---|---|---|---|---|---|---|---|---|
| mysql84 | 8.1 | no_column_boot | `:error` | 3 | 3.0 | 12 | 0 | 6 | 44849 |
| mysql84 | 8.1 | no_column_boot | `:silent` | 3 | 3.3 | 0 | 0 | 6 | 38392 |
| mysql84 | 8.1 | no_table | `:error` | 9 | 25.0 | 36 | 24 | 33 | 253856 |
| mysql84 | 8.1 | no_table | `:silent` | 9 | 26.0 | 0 | 24 | 33 | 236303 |
| pg | 8.1 | no_column_boot | `:error` | 3 | 2.9 | 12 | 0 | 6 | 44848 |
| pg | 8.1 | no_column_boot | `:silent` | 3 | 3.0 | 0 | 0 | 6 | 38390 |
| pg | 8.1 | no_table | `:error` | 9 | 26.6 | 36 | 24 | 33 | 261816 |
| pg | 8.1 | no_table | `:silent` | 9 | 26.1 | 0 | 24 | 33 | 239578 |
| sqlite | 7.2 | no_column_boot | `:error` | 3 | 3.0 | 12 | 0 | 6 | 45777 |
| sqlite | 7.2 | no_column_boot | `:silent` | 3 | 3.0 | 0 | 0 | 6 | 38768 |
| sqlite | 7.2 | no_table | `:error` | 9 | 26.1 | 36 | 24 | 33 | 260968 |
| sqlite | 7.2 | no_table | `:silent` | 9 | 26.5 | 0 | 24 | 33 | 238281 |
| sqlite | 8.0 | no_column_boot | `:error` | 3 | 3.0 | 12 | 0 | 6 | 45483 |
| sqlite | 8.0 | no_column_boot | `:silent` | 3 | 2.9 | 0 | 0 | 6 | 39023 |
| sqlite | 8.0 | no_table | `:error` | 9 | 26.0 | 36 | 24 | 33 | 261051 |
| sqlite | 8.0 | no_table | `:silent` | 9 | 25.8 | 0 | 24 | 33 | 240064 |
| sqlite | 8.1 | no_column_boot | `:error` | 3 | 3.2 | 12 | 0 | 6 | 44848 |
| sqlite | 8.1 | no_column_boot | `:silent` | 3 | 3.2 | 0 | 0 | 6 | 38389 |
| sqlite | 8.1 | no_table | `:error` | 9 | 26.0 | 36 | 24 | 33 | 257246 |
| sqlite | 8.1 | no_table | `:silent` | 9 | 25.2 | 0 | 24 | 33 | 236263 |

## Appendix B: the probe code

Run from `/tmp/red-s2`. `run.sh` picks the bundle and the database; `fresh.sh` makes a throwaway database
for each run; the `*_matrix.sh` scripts and `cost.sh` ran the batches; the `sum_*.rb` scripts built the tables.
`<repo>` is the repository checkout and `~` the home folder.

### `run.sh`

```bash
#!/usr/bin/env bash
# usage: run.sh <rails 7.2|8.0|8.1> <db sqlite|pg|mysql84> <script> [args...]
set -u
v=$1; db=$2; shift 2
vv=${v/./}
case $db in
  sqlite)  url="sqlite3:/tmp/red-s2/sqlite/probe_${vv}${PROBE_DB_SUFFIX:-}.sqlite3" ;;
  pg)      url="postgres://localhost/red_s2_${vv}${PROBE_DB_SUFFIX:-}" ;;
  mysql84) url="trilogy://root@127.0.0.1:3307/red_s2_${vv}${PROBE_DB_SUFFIX:-}" ;;
esac
export PROBE_DB=$db PROBE_RAILS=$v RAILS_ENV=test RED_TEST_SCHEMA=migrations
export RED_REPO=<repo>
export DATABASE_URL="${url}?pool=${PROBE_POOL:-10}&checkout_timeout=${PROBE_CHECKOUT:-5}&timeout=5000"
export BUNDLE_GEMFILE=/tmp/red-s2/gemfiles/$v/Gemfile RAILS_VERSION=$v
cd /tmp/red-s2/probe
exec mise exec ruby@3.4.5 -- bundle exec ruby "$@"
```

### `fresh.sh`

```bash
#!/usr/bin/env bash
# usage: fresh.sh <rails> <db>: a fresh throwaway database for one run
v=${1/./}; db=$2
case $db in
  sqlite)  rm -f /tmp/red-s2/sqlite/probe_${v}${PROBE_DB_SUFFIX:-}.sqlite3* ;;
  pg)      dropdb --if-exists red_s2_${v}${PROBE_DB_SUFFIX:-} && createdb red_s2_${v}${PROBE_DB_SUFFIX:-} ;;
  mysql84) /opt/homebrew/opt/mysql@8.4/bin/mysql -h127.0.0.1 -P3307 -uroot -e "drop database if exists red_s2_${v}${PROBE_DB_SUFFIX:-}; create database red_s2_${v}${PROBE_DB_SUFFIX:-}" ;;
esac
```

### `prints_matrix.sh`

```bash
#!/usr/bin/env bash
# One stream per database in parallel; runs inside a stream are sequential, each on a fresh database.
cd /tmp/red-s2
stream() {
  db=$1
  for v in ${VERSIONS:-8.1}; do
    for p in ${PATHS:-request report after_response enqueue_fail}; do
      for b in ${BREAKS:-none no_table no_column_live no_column_boot not_null}; do
        [ $db = sqlite ] && [ $b = not_null ] && continue
        f=out/prints/${db}_${v}_${p}_${b}
        ./fresh.sh $v $db
        LEVEL=${LEVEL:-error} PATH_KIND=$p BREAK=$b timeout 180 ./run.sh $v $db prints.rb > $f.json 2> $f.err
        echo "$db $v $p $b exit=$?" >> out/prints/progress.txt
      done
    done
  done
}
for db in ${DBS:-sqlite pg mysql84}; do stream $db & done
wait
echo ALL DONE >> out/prints/progress.txt
```

### `worker_matrix.sh`

```bash
#!/usr/bin/env bash
# Async capture in a request (the enqueue), then a real Solid Queue worker in its own process.
cd /tmp/red-s2
stream() {
  db=$1; shift
  for v in $VERSIONS; do for b in $BREAKS; do for lvl in ${LEVELS:-silent error}; do
    f=out/worker/${db}_${v}_${b}_${lvl}
    ./fresh.sh $v $db
    LEVEL=$lvl PATH_KIND=enqueue BREAK=$b timeout 180 ./run.sh $v $db prints.rb > $f.enq.json 2> $f.enq.err
    LEVEL=$lvl WORKER_KEEP_TEXT=1 timeout 240 ./run.sh $v $db worker.rb > $f.json 2> $f.err
    echo "$db $v $b $lvl exit=$?" >> out/worker/progress.txt
  done; done; done
}
: > out/worker/progress.txt
VERSIONS=8.1 BREAKS="no_table no_column_boot" stream pg &
VERSIONS=8.1 BREAKS="no_table no_column_boot" stream mysql84 &
VERSIONS="8.1 8.0 7.2" BREAKS="no_table no_column_boot" stream sqlite &
wait
echo ALL DONE >> out/worker/progress.txt
```

### `storm_matrix.sh`

```bash
#!/usr/bin/env bash
# 60 s storms on SQLite (RED's table gone), one stream per Rails version, then a
# real worker to run whatever the storm queued (captures, flush and notification jobs).
cd /tmp/red-s2
stream() {
  v=$1
  for mode in sync async; do for st in on off; do for cl in 1 20; do
    f=out/storm/${v}_${mode}_storm-${st}_classes-${cl}
    PROBE_DB_SUFFIX=_storm ./fresh.sh $v sqlite
    PROBE_DB_SUFFIX=_storm LEVEL=error MODE=$mode STORM=$st CLASSES=$cl RATE=${RATE:-200} timeout 200 ./run.sh $v sqlite storm.rb > $f.json 2> $f.err
    PROBE_DB_SUFFIX=_storm LEVEL=error STORM=$st WORKER_ASYNC=$([ $mode = async ] && echo true || echo false) WORKER_KEEP_TEXT=0 TIMEOUT=420 timeout 480 ./run.sh $v sqlite worker.rb > $f.worker.json 2> $f.worker.err
    echo "$v $mode $st $cl exit=$?" >> out/storm/progress.txt
  done; done; done
}
: > out/storm/progress.txt
for v in ${VERSIONS:-8.1 8.0 7.2}; do stream $v & done
wait
echo ALL DONE >> out/storm/progress.txt
```

### `cost.sh`

```bash
#!/usr/bin/env bash
# Timings, one run at a time on an otherwise idle machine. Three log targets per Rails version:
#   file        : Logger opened by path (sync = true)
#   stdout_file : STDOUT (sync = true, as Puma leaves it) redirected to a file
#   stdout_pipe : STDOUT (sync = true) into a pipe drained by cat, as a container runtime or journald reads it
cd /tmp/red-s2
for v in ${VERSIONS:-8.1 8.0 7.2}; do
  for t in file stdout_file stdout_pipe; do
    f=out/cost/${v}_$t
    PROBE_DB_SUFFIX=_cost ./fresh.sh $v sqlite
    rm -f out/cost/app_$v.log out/cost/stdout_$v.log
    case $t in
      file)        PROBE_DB_SUFFIX=_cost LOG_TARGET=file PROBE_LOG=/tmp/red-s2/out/cost/app_$v.log RESULT=/tmp/red-s2/$f.json ./run.sh $v sqlite logcost.rb > /dev/null 2> $f.err ;;
      stdout_file) PROBE_DB_SUFFIX=_cost LOG_TARGET=stdout STDOUT_KIND=file RESULT=/tmp/red-s2/$f.json ./run.sh $v sqlite logcost.rb > out/cost/stdout_$v.log 2> $f.err ;;
      stdout_pipe) PROBE_DB_SUFFIX=_cost LOG_TARGET=stdout STDOUT_KIND=pipe RESULT=/tmp/red-s2/$f.json ./run.sh $v sqlite logcost.rb 2> $f.err | cat > /dev/null ;;
    esac
    echo "$v $t exit=$?" >> out/cost/progress.txt
  done
done
./run.sh 8.1 sqlite proto_cost.rb > out/cost/proto_8.1.json 2> out/cost/proto.err
echo ALL DONE >> out/cost/progress.txt
```

### `census.rb`

```ruby
# Counts every RailsErrorDashboard::Logger.<level> call under lib/ and app/ with Prism
# (comments never match), and prints file:line, level, enclosing method and the message source.
require "prism"
require "json"
REPO = ENV.fetch("RED_REPO")
rows = []
Dir.glob("#{REPO}/{lib,app}/**/*.{rb,erb}").sort.each do |path|
  next unless path.end_with?(".rb")
  src = File.read(path)
  res = Prism.parse(src)
  stack = []
  walk = lambda do |node, defs|
    return unless node
    defs = defs + [ node.name.to_s ] if node.is_a?(Prism::DefNode)
    if node.is_a?(Prism::CallNode) && %i[error warn info debug].include?(node.name) && node.receiver
      recv = node.receiver.slice
      if recv =~ /\A(::)?(RailsErrorDashboard::)?Logger\z/
        rows << { file: path.sub("#{REPO}/", ""), line: node.location.start_line, level: node.name,
                  receiver: recv, method: defs.last, arg: node.arguments&.slice.to_s.gsub(/\s+/, " ")[0, 220] }
      end
    end
    node.compact_child_nodes.each { |c| walk.call(c, defs) }
  end
  walk.call(res.value, [])
end
puts JSON.pretty_generate(rows) if ENV["JSON"]
by = rows.group_by { _1[:level] }.transform_values(&:size)
warn "counts by level: #{by}"
warn "error calls: #{rows.count { _1[:level] == :error }} in #{rows.select { _1[:level] == :error }.map { _1[:file] }.uniq.size} files"
rows.select { _1[:level] == :error }.each { |r| puts "#{r[:file]}:#{r[:line]}\t#{r[:method]}\t#{r[:receiver]}\t#{r[:arg]}" }
```

### `census_bypass.rb`

```ruby
# Counts direct Rails.logger.<level> calls (and $stderr writes) under lib/ and app/, outside RED's Logger and generators.
require "prism"
REPO = ENV.fetch("RED_REPO")
rows = []
Dir.glob("#{REPO}/{lib,app}/**/*.rb").sort.each do |path|
  next if path.end_with?("lib/rails_error_dashboard/logger.rb") || path.include?("/generators/")
  walk = lambda do |node|
    return unless node
    if node.is_a?(Prism::CallNode) && %i[error warn info debug fatal].include?(node.name) && node.receiver&.slice == "Rails.logger"
      rows << [ path.sub("#{REPO}/", ""), node.location.start_line, node.name ]
    end
    node.compact_child_nodes.each { walk.call(_1) }
  end
  walk.call(Prism.parse(File.read(path)).value)
end
by_level = rows.group_by { _1[2] }.transform_values(&:size)
by_dir = rows.group_by { r = _1[0]; r.start_with?("app/jobs") ? "app/jobs" : r.start_with?("app/controllers") ? "app/controllers" : r.start_with?("app/helpers") ? "app/helpers" : r[%r{lib/rails_error_dashboard/[^/]+}] || r }.transform_values(&:size)
puts({ total: rows.size, by_level: by_level, by_dir: by_dir }.inspect)
```

### `boot.rb`

```ruby
# Boots spec/dummy with the production logger a new app of this Rails version
# gets from railties' production.rb template, at the template's level (info)
# and log tags ([:request_id]). Then migrates RED, loads Solid Queue's schema,
# and adds a controller that raises, so captures run through the real stack.
#
# LOG_TARGET = file (default; a path opened by Logger, so sync = true)
#            | stdout (STDOUT with sync = true, as Puma and Solid Queue leave it)
$stdout.sync = true
require "json"
REPO = ENV.fetch("RED_REPO")
require "rails/all"
require "solid_queue"
require "#{REPO}/spec/dummy/config/application"

PROBE_LOG = ENV.fetch("PROBE_LOG", "/tmp/red-s2/out/last.log")
LOG_TARGET = ENV.fetch("LOG_TARGET", "file")
log_dev = LOG_TARGET == "stdout" ? STDOUT.tap { |io| io.sync = true } : PROBE_LOG
host_logger =
  if Rails::VERSION::MAJOR < 8
    # railties-7.2.4 production.rb.tt:66-68
    ActiveSupport::Logger.new(log_dev)
      .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
      .then { |logger| ActiveSupport::TaggedLogging.new(logger) }
  else
    # railties-8.0.5.2 production.rb.tt:42, railties-8.1.4.1 production.rb.tt:50
    ActiveSupport::TaggedLogging.logger(log_dev)
  end
Rails.application.config.logger = host_logger
Rails.application.config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
Rails.application.config.log_tags = [ :request_id ]
# config/initializers/filter_parameter_logging.rb as each version's template writes it
Rails.application.config.filter_parameters += (
  [ :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn ] +
  (Rails::VERSION::MAJOR >= 8 ? [ :cvv, :cvc ] : [])
)
require "#{REPO}/spec/dummy/config/environment"
require "#{REPO}/spec/support/test_schema"

RailsErrorDashboard::TestSchema.build!
conn = ActiveRecord::Base.connection
unless conn.table_exists?("solid_queue_jobs")
  ActiveRecord::Schema.verbose = false
  load File.join(Gem.loaded_specs["solid_queue"].full_gem_path,
                 "lib/generators/solid_queue/install/templates/db/queue_schema.rb")
end

# A host controller. The user id goes in through Rails.error.set_context, a
# common way hosts attach the user; the request carries a query string, a
# password field and a browser user agent, as a real sign-in or checkout does.
class ProbeController < ActionController::Base
  skip_forgery_protection
  before_action { Rails.error.set_context(user_id: 4711) }
  def boom = raise(ArgumentError, "probe boom for order 9001")
end
Rails.application.routes.disable_clear_and_finalize = true
Rails.application.routes.draw { post "/probe/boom" => "probe#boom" }

PROBE_ENV = {
  "REMOTE_ADDR" => "203.0.113.77",
  "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) ProbeBrowser/1.0",
  "CONTENT_TYPE" => "application/x-www-form-urlencoded",
  :input => "user[email]=jane.doe%40example.com&user[password]=hunter2-secret&card_number=4111111111111111"
}.freeze
PROBE_PATH = "/probe/boom?email=jane.doe%40example.com&reset_token=tok_ABC123".freeze

def probe_request
  env = Rack::MockRequest.env_for(PROBE_PATH, method: "POST", **PROBE_ENV.transform_keys { |k| k.is_a?(String) ? k : k })
  status, _headers, body = Rails.application.call(env)
  body.close if body.respond_to?(:close)
  status
end

# Settings a host gets: library defaults plus what the installer writes
# (templates/initializer.rb:194 async_logging = true; :487 and :492 logging off).
CFG = cfg = RailsErrorDashboard.configuration
cfg.async_logging = ENV.fetch("MODE", "sync") != "sync"
cfg.enable_storm_protection = ENV.fetch("STORM", "on") == "on"
cfg.enable_internal_logging = ENV.fetch("INTERNAL_LOGGING", "false") == "true"
cfg.log_level = ENV.fetch("LEVEL", "error").to_sym
ActiveJob::Base.queue_adapter = :solid_queue

def probe_versions
  c = ActiveRecord::Base.connection
  { rails: Rails.version, adapter: ActiveRecord::Base.connection_db_config.adapter,
    server: (c.select_value(c.adapter_name =~ /sqlite/i ? "select sqlite_version()" : "select version()") rescue "?"),
    logger: Rails.logger.class.name, log_level: Rails.logger.level,
    red: { async_logging: CFG.async_logging, storm: CFG.enable_storm_protection,
           internal_logging: CFG.enable_internal_logging, log_level: CFG.log_level } }
end

def clear_queue!
  SolidQueue::Job.where(finished_at: nil).update_all(finished_at: Time.current)
end

# Probe-only: attributes every write to the host's log device to the code that
# made it, by the first recognisable frame. Used for counting, never for timing.
module OriginTap
  RED_PATH = %r{#{Regexp.escape(REPO)}/(lib|app)/}
  def write(message)
    if (sink = $s2_sink)
      origin = nil
      caller_locations(1, 120).each do |l|
        path = l.path.to_s
        if path.include?("/active_job/log_subscriber") || path.include?("/active_job/logging")
          origin = "active_job"; break
        elsif path.match?(RED_PATH) && !path.end_with?("lib/rails_error_dashboard/logger.rb")
          origin = "red #{path.sub(RED_PATH, '\1/').sub(%r{\A(lib|app)/rails_error_dashboard/}, '')}:#{l.lineno}"; break
        elsif path.include?("/solid_queue")
          origin = "solid_queue"; break
        elsif path.match?(%r{/(action_dispatch|action_controller|rails/rack|railties)})
          origin = "rails_request"; break
        end
      end
      sink << { origin: origin || "other", bytes: message.bytesize, lines: message.count("\n"), text: (ENV["KEEP_TEXT"] ? message : nil) }
    end
    super
  end
end
Logger::LogDevice.prepend(OriginTap)

def summarize_sink(sink)
  sink.group_by { _1[:origin] }.transform_values { |ws| { writes: ws.size, lines: ws.sum { _1[:lines] }, bytes: ws.sum { _1[:bytes] } } }
end

RED_TABLE = "rails_error_dashboard_error_logs"
def apply_break!(kind)
  c = ActiveRecord::Base.connection
  case kind
  when "none" then nil
  when "no_table" # the table is gone; the process booted with it (a dropped or unmigrated error database)
    c.rename_table(RED_TABLE, "probe_hidden_error_logs")
  when "no_column_live" # a column RED writes vanished under a running process (cached schema)
    c.remove_column(RED_TABLE, :user_agent)
  when "no_column_boot" # the same column was missing when the process booted (gem upgraded, migration not run)
    c.remove_column(RED_TABLE, :user_agent)
    RailsErrorDashboard::ErrorLog.reset_column_information
  when "not_null" # the database rejects the row and quotes it (PostgreSQL's "Failing row contains")
    raise "not_null needs PostgreSQL or MySQL" if c.adapter_name =~ /sqlite/i
    c.add_column(RED_TABLE, :probe_required, :string, null: false, default: "x")
    c.change_column_default(RED_TABLE, :probe_required, from: "x", to: nil)
  else raise "unknown break #{kind}"
  end
end
```

### `prints.rb`

```ruby
# What reaches the host's log when a capture fails, path by path.
# BREAK = none | no_table | no_column_live | no_column_boot | not_null
# PATH  = request         sync capture of an unhandled request error (ErrorCatcher + executor)
#       | report          sync Rails.error.report outside a request (a job, console or rake task)
#       | enqueue         async capture in a request without rack.response_finished: the enqueue
#                         runs on the request thread; the job is left for worker.rb
#       | after_response  async capture in a request whose server offers rack.response_finished
#       | enqueue_fail    async capture whose enqueue fails too (the queue table is broken as well)
# Each path reports 3 times (a first occurrence, then two repeats).
require_relative "boot"
PATH_KIND = ENV.fetch("PATH_KIND")
BREAK = ENV.fetch("BREAK")
CFG.async_logging = %w[enqueue after_response enqueue_fail].include?(PATH_KIND)
CFG.enable_storm_protection = ENV.fetch("STORM", "on") == "on"
clear_queue!

# Warm up with one healthy capture of a different error, so the application row
# exists and the schema is cached, as in a process that has been running.
begin; raise IOError, "warm-up"; rescue => e
  Thread.current[:rails_error_dashboard_logging] = nil
  was = CFG.async_logging; CFG.async_logging = false
  Rails.error.report(e, handled: true, severity: :error); CFG.async_logging = was
end
RailsErrorDashboard::Services::StormProtection::Gate.respond_to?(:reset!) && RailsErrorDashboard::Services::StormProtection::Gate.reset!

apply_break!(BREAK)
ActiveRecord::Base.connection.rename_table("solid_queue_jobs", "probe_hidden_sq_jobs") if PATH_KIND == "enqueue_fail"

ENV["KEEP_TEXT"] = "1"
results = []
3.times do |i|
  $s2_sink = []
  case PATH_KIND
  when "request", "enqueue", "enqueue_fail"
    probe_request
  when "after_response"
    env = Rack::MockRequest.env_for(PROBE_PATH, method: "POST", **PROBE_ENV)
    env["rack.response_finished"] = []
    status, headers, body = Rails.application.call(env)
    body.close if body.respond_to?(:close)
    env["rack.response_finished"].each { |cb| cb.call(env, status, headers, nil) }
  when "report"
    Rails.error.set_context(user_id: 4711)
    begin; raise ArgumentError, "probe boom for order 9001"; rescue => e
      Rails.error.report(e, handled: true, severity: :error, context: { order_id: 9001, customer_email: "jane.doe@example.com" })
    end
    ActiveSupport::ExecutionContext.clear
  end
  sink = $s2_sink; $s2_sink = nil
  results << { capture: i + 1, origins: summarize_sink(sink),
               red_text: sink.select { _1[:origin].start_with?("red") }.map { "#{_1[:origin]} | #{_1[:text]}" } }
end

puts({ versions: probe_versions, path: PATH_KIND, break: BREAK,
       queued_jobs: (SolidQueue::Job.where(finished_at: nil).count rescue "n/a"),
       results: results }.to_json)
```

### `worker.rb`

```ruby
# A real Solid Queue worker (3 threads) and dispatcher, in their own process,
# running whatever prints.rb or storm.rb queued. Runs until no job is ready,
# scheduled or claimed for 2 s (retries included), or TIMEOUT seconds.
require_relative "boot"
TIMEOUT = Float(ENV.fetch("TIMEOUT", "120"))
ENV["KEEP_TEXT"] = ENV.fetch("WORKER_KEEP_TEXT", "1")
CFG.async_logging = ENV.fetch("WORKER_ASYNC", "true") == "true"  # the worker's own captures, as the host configured
$s2_sink = []
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
dispatcher = SolidQueue::Dispatcher.new(polling_interval: 0.1, batch_size: 500)
worker = SolidQueue::Worker.new(queues: "*", threads: 3, polling_interval: 0.1)
dispatcher.start
worker.start
def pending = SolidQueue::ReadyExecution.count + SolidQueue::ScheduledExecution.count + SolidQueue::ClaimedExecution.count
idle_since = nil
loop do
  sleep 0.25
  now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  if pending.zero? then idle_since ||= now else idle_since = nil end
  break if (idle_since && now - idle_since > 2) || now - started > TIMEOUT
end
worker.stop; dispatcher.stop
sink = $s2_sink; $s2_sink = nil
jobs = SolidQueue::Job.group(:class_name).count
failed = SolidQueue::FailedExecution.count
by_class_exec = SolidQueue::Job.where(class_name: "RailsErrorDashboard::AsyncErrorLoggingJob").count
puts({ versions: probe_versions, seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1),
       jobs_by_class: jobs, failed_executions: failed, capture_job_rows: by_class_exec,
       still_pending: pending, origins: summarize_sink(sink),
       text: ENV["KEEP_TEXT"] == "1" ? sink.map { "#{_1[:origin]} | #{_1[:text]}" } : nil }.to_json)
```

### `reporter_fail.rb`

```ruby
# error_reporter.rb:71-74: what prints when building the context fails. The
# host passes a current_user whose #id raises (a lazily loaded user whose
# session lookup fails), during a request.
require_relative "boot"
ENV["KEEP_TEXT"] = "1"
class ProbeBrokenUser; def id = raise(ActiveRecord::ConnectionNotEstablished, "user lookup failed"); end
env = Rack::MockRequest.env_for(PROBE_PATH, method: "POST", **PROBE_ENV)
ActionDispatch::Request.new(env).request_parameters # parsed, as a controller would have
$s2_sink = []
begin; raise ArgumentError, "probe boom for order 9001"; rescue => e
  Thread.current[:rails_error_dashboard_request_env] = env
  Rails.error.report(e, handled: false, severity: :error, context: { current_user: ProbeBrokenUser.new }, source: "application.action_dispatch")
  Thread.current[:rails_error_dashboard_request_env] = nil
end
sink = $s2_sink; $s2_sink = nil
puts({ origins: summarize_sink(sink), text: sink.map { "#{_1[:origin]} | #{_1[:text]}" } }.to_json)
```

### `host_code_fail.rb`

```ruby
# Capture-path sites that fire on every capture while storage is healthy:
# a host's custom_fingerprint lambda that raises (error_hash_generator.rb:187)
# and a host plugin whose hook raises (plugin.rb:127-129). Sync, 3 captures.
require_relative "boot"
ENV["KEEP_TEXT"] = "1"
KIND = ENV.fetch("KIND")
case KIND
when "fingerprint"
  CFG.custom_fingerprint = ->(exception, context) { context.fetch(:tenant_id) } # KeyError: the host's own bug
when "plugin"
  plugin = Class.new(RailsErrorDashboard::Plugin) do
    def name = "ProbeAuditPlugin"
    def version = "1.0"
    def on_error_logged(error_log) = raise(NoMethodError, "undefined method 'email' for nil (user #{error_log.user_id})")
    def on_error_recurred(error_log) = raise(NoMethodError, "undefined method 'email' for nil (user #{error_log.user_id})")
  end
  RailsErrorDashboard.register_plugin(plugin.new)
end
results = 3.times.map do
  $s2_sink = []
  probe_request
  sink = $s2_sink; $s2_sink = nil
  { origins: summarize_sink(sink).select { |k, _| k.start_with?("red") }, text: sink.select { _1[:origin].start_with?("red") }.map { "#{_1[:origin]} | #{_1[:text][0, 300]}" } }
end
puts({ kind: KIND, rows: RailsErrorDashboard::ErrorLog.sum(:occurrence_count), results: results }.to_json)
```

### `storm.rb`

```ruby
# A 60 s error storm against a broken schema, in one process with THREADS
# request threads (Puma 8's default is 3). Each report goes the way an
# unhandled request error does: the request env in Thread.current, as
# ErrorCatcher leaves it, then Rails.error.report as ActionDispatch::Executor
# sends it. It counts every write to the host's log by origin.
# MODE sync|async, STORM on|off, RATE reports/s (all threads), CLASSES 1|20, BREAK.
require_relative "boot"
SECONDS_RUN = Float(ENV.fetch("SECONDS_RUN", "60"))
RATE = Float(ENV.fetch("RATE", "200"))   # 0 = as fast as the threads go
THREADS = Integer(ENV.fetch("THREADS", "3"))
CLASSES = Integer(ENV.fetch("CLASSES", "1"))
BREAK = ENV.fetch("BREAK", "no_table")
clear_queue!
ERRORS = Array.new(CLASSES) { |i| Object.const_set("ProbeStormError#{i}", Class.new(StandardError)) }

def raise_storm_error(klass) = raise(klass, "storm for order 9001")

# Warm up with one healthy capture, so the application row exists and the
# schema is cached, as in a process that has been running.
begin; raise IOError, "warm-up"; rescue => e
  was = CFG.async_logging; CFG.async_logging = false
  Rails.error.report(e, handled: true, severity: :error); CFG.async_logging = was
end
RailsErrorDashboard::Services::StormProtection::Gate.reset! if RailsErrorDashboard::Services::StormProtection::Gate.respond_to?(:reset!)
clear_queue!

apply_break!(BREAK)
$s2_sink = []
mono = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
t0 = mono.call
durations = Queue.new
threads = Array.new(THREADS) do |ti|
  Thread.new do
    per_thread = RATE / THREADS
    next_at = t0 + ti * (1.0 / RATE)
    n = 0
    mine = []
    while (now = mono.call) - t0 < SECONDS_RUN
      if RATE > 0
        sleep(next_at - now) if next_at > now
        next_at += 1.0 / per_thread
      end
      klass = ERRORS[(n + ti) % CLASSES]
      env = Rack::MockRequest.env_for(PROBE_PATH, method: "POST", **PROBE_ENV)
      ActionDispatch::Request.new(env).request_id = SecureRandom.uuid
      begin
        raise_storm_error(klass)
      rescue => e
        Thread.current[:rails_error_dashboard_request_env] = env
        s = mono.call
        Rails.error.report(e, handled: false, severity: :error, source: "application.action_dispatch")
        mine << (mono.call - s) * 1000
      ensure
        Thread.current[:rails_error_dashboard_request_env] = nil
        Thread.current[:rails_error_dashboard_reported_errors] = nil
      end
      n += 1
    end
    durations << mine
  end
end
threads.each(&:join)
elapsed = mono.call - t0
sink = $s2_sink; $s2_sink = nil
all = []; all.concat(durations.pop) until durations.empty?
all.sort!
pct = ->(p) { all.empty? ? nil : all[[ (all.size * p).ceil - 1, 0 ].max].round(3) }
red = sink.select { _1[:origin].start_with?("red") }
puts({ versions: probe_versions, mode: (CFG.async_logging ? "async" : "sync"), storm: CFG.enable_storm_protection,
       rate: RATE, threads: THREADS, classes: CLASSES, break: BREAK, seconds: elapsed.round(2),
       reports: all.size, capture_ms: { p50: pct.(0.5), p95: pct.(0.95), p99: pct.(0.99), max: all.last&.round(3) },
       red_writes: red.size, red_lines: red.sum { _1[:lines] }, red_bytes: red.sum { _1[:bytes] },
       all_writes: sink.size, all_lines: sink.sum { _1[:lines] }, all_bytes: sink.sum { _1[:bytes] },
       origins: summarize_sink(sink),
       queued: SolidQueue::Job.where(finished_at: nil).group(:class_name).count }.to_json)
```

### `logcost.rb`

```ruby
# What one log call costs the capture path, with the logger a new app gets.
# Run alone on an idle machine. Clock: CLOCK_MONOTONIC_RAW (42 ns on macOS;
# CLOCK_MONOTONIC there resolves only 1 us). Results go to RESULT (STDOUT may be the log).
#   LOG_TARGET=file   : Logger opened by path (sync = true), as a host that logs to log/production.log
#   LOG_TARGET=stdout : STDOUT, sync = true as Puma leaves it; the runner points STDOUT at a file or a drained pipe
require_relative "boot"
RESULT = ENV.fetch("RESULT")
N = Integer(ENV.fetch("N", "20000"))
E2E_N = Integer(ENV.fetch("E2E_N", "1500"))
mono = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC_RAW) }
CFG.enable_storm_protection = false
CFG.async_logging = false
CFG.log_level = :silent

def stats(us)
  s = us.sort
  at = ->(p) { s[[ (s.size * p).ceil - 1, 0 ].max].round(2) }
  { n: s.size, p50: at.(0.5), p95: at.(0.95), p99: at.(0.99), max: s.last.round(1) }
end

def timed(n)
  mono = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC_RAW) }
  Array.new(n) { s = mono.call; yield; (mono.call - s) * 1_000_000 }
end

out = { versions: probe_versions, target: LOG_TARGET, stdout_kind: ENV["STDOUT_KIND"] }

# 1. One line, the size of the first failure line, inside a request's tag.
line = "[RailsErrorDashboard] [RailsErrorDashboard] LogError command failed: ActiveRecord::StatementInvalid - " \
       "SQLite3::SQLException: no such table: rails_error_dashboard_error_logs"
Rails.logger.tagged(SecureRandom.uuid) do
  timed(2000) { Rails.logger.error(line) } # warm-up
  out[:one_call_us] = stats(timed(N) { Rails.logger.error(line) })
  t = mono.call; N.times { Rails.logger.error(line) }
  out[:one_call_amortised_us] = ((mono.call - t) * 1_000_000 / N).round(2)
  out[:one_call_below_level_us] = stats(timed(N) { Rails.logger.debug(line) }) # filtered by the host's level: no I/O
  out[:red_logger_silent_us] = stats(timed(N) { RailsErrorDashboard::Logger.error(line) }) # log_level :silent
end

# 2. The whole failure block of LogError#call (log_error.rb:783-786), with a
# real failure's exception and the context a request capture carries.
env = Rack::MockRequest.env_for(PROBE_PATH, method: "POST", **PROBE_ENV)
context = RailsErrorDashboard::ValueObjects::ErrorContext.new({ request: ActionDispatch::Request.new(env), user_id: 4711 }, "application.action_dispatch").to_h
failure = begin
  ActiveRecord::Base.connection.select_all("select * from probe_missing_table")
rescue => e
  e
end
original = ArgumentError.new("probe boom for order 9001")
block = lambda do
  RailsErrorDashboard::Logger.error("[RailsErrorDashboard] LogError command failed: #{failure.class} - #{failure.message}")
  RailsErrorDashboard::Logger.error("Original exception: #{original.class} - #{original.message}")
  RailsErrorDashboard::Logger.error("Context: #{context.inspect.truncate(500)}")
  RailsErrorDashboard::Logger.error(failure.backtrace&.first(5)&.join("\n"))
end
Rails.logger.tagged(SecureRandom.uuid) do
  CFG.log_level = :silent
  out[:failure_block_silent_us] = stats(timed(N / 4, &block))
  CFG.log_level = :error
  timed(500, &block)
  out[:failure_block_error_us] = stats(timed(N / 4, &block))
end

# 3. End to end: a sync capture that fails (RED's table is gone), as the
# executor reports an unhandled request error. log_level :silent and :error
# alternate in blocks of 50 so drift hits both equally.
apply_break!("no_table")
def failing_capture
  env = Rack::MockRequest.env_for(PROBE_PATH, method: "POST", **PROBE_ENV)
  raise ArgumentError, "probe boom for order 9001"
rescue => e
  Thread.current[:rails_error_dashboard_request_env] = env
  s = Process.clock_gettime(Process::CLOCK_MONOTONIC_RAW)
  Rails.error.report(e, handled: false, severity: :error, source: "application.action_dispatch")
  (Process.clock_gettime(Process::CLOCK_MONOTONIC_RAW) - s) * 1_000_000
ensure
  Thread.current[:rails_error_dashboard_request_env] = nil
  Thread.current[:rails_error_dashboard_reported_errors] = nil
end
silent = []; error = []
Rails.logger.tagged(SecureRandom.uuid) do
  CFG.log_level = :error; 100.times { failing_capture }
  (E2E_N / 50).times do
    CFG.log_level = :silent; 50.times { silent << failing_capture }
    CFG.log_level = :error;  50.times { error << failing_capture }
  end
end
out[:e2e_failing_capture_silent_us] = stats(silent)
out[:e2e_failing_capture_error_us] = stats(error)
File.write(RESULT, out.to_json + "\n")
```

### `proto_cost.rb`

```ruby
# Prototypes (probe only, not product code) of what options B and C add per
# failed capture, timed in isolation like S1's guard_cost.rb.
#   B: one line per failure class per minute per process: a Mutex-guarded Hash
#      of class name => last monotonic time; the common storm case is "suppressed".
#   C: a per-process failure count for /health: an atomic increment plus the
#      last failure's class and time.
require "concurrent"
require "json"
mono = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
N = 200_000
def per_call_ns(n)
  3.times.map { t = Process.clock_gettime(Process::CLOCK_MONOTONIC); n.times { yield }; (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t) * 1e9 / n }.min.round(1)
end
class ProtoLimiter
  def initialize(window) = (@window = window; @last = {}; @lock = Mutex.new)
  def allow?(key)
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @lock.synchronize do
      last = @last[key]
      return false if last && now - last < @window
      @last.shift if @last.size >= 100 # bounded, like storm_max_tracked_fingerprints
      @last[key] = now
      true
    end
  end
end
class ProtoCounter
  def initialize = (@count = Concurrent::AtomicFixnum.new(0); @last = Concurrent::AtomicReference.new(nil))
  def record!(failure) = (@count.increment; @last.set([ failure.class.name, Process.clock_gettime(Process::CLOCK_MONOTONIC) ]))
end
failure = StandardError.new("x")
lim = ProtoLimiter.new(60.0); lim.allow?("StandardError")
ctr = ProtoCounter.new
out = { ruby: RUBY_VERSION, concurrent_ruby: Gem.loaded_specs["concurrent-ruby"]&.version.to_s }
out[:empty_block_ns] = per_call_ns(N) { nil }
out[:b_limiter_suppressed_ns] = per_call_ns(N) { lim.allow?("StandardError") }
out[:c_counter_ns] = per_call_ns(N) { ctr.record!(failure) }
# Contended: 3 threads (Puma 8's default) hammering both at once.
[ [ :b_limiter_suppressed_3threads_ns, -> { lim.allow?("StandardError") } ], [ :c_counter_3threads_ns, -> { ctr.record!(failure) } ] ].each do |name, fn|
  t = mono.call
  3.times.map { Thread.new { (N / 3).times { fn.call } } }.each(&:join)
  out[name] = ((mono.call - t) * 1e9 / N).round(1)
end
puts out.to_json
```

### `stall.rb`

```ruby
# STDOUT into a pipe nobody reads (a log collector that has stalled). One
# thread logs a failed capture's 4 lines in a loop; a second thread, standing
# in for another request, logs one line every 100 ms. Records how many bytes
# went through before the first call stalled for 2 s, and whether the second
# thread stalled with it (the logger's lock is held during the blocked write).
require_relative "boot"
RESULT = ENV.fetch("RESULT")
mono = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
state = { bytes: 0, calls: 0, other_calls: 0, other_last_at: nil }
fail_lines = [ "x" * 160, "y" * 120, "z" * 570, ("w" * 190 + "\n") * 4 + "w" * 190 ]
t0 = mono.call
a = Thread.new { loop { fail_lines.each { |l| Rails.logger.error(l); state[:calls] += 1; state[:bytes] += l.bytesize + 1 } } }
b = Thread.new { loop { Rails.logger.info("Completed 200 OK in 3ms"); state[:other_calls] += 1; state[:other_last_at] = mono.call - t0; sleep 0.1 } }
last = nil; stalled_for = 0
loop do
  sleep 0.2
  if last == state[:calls] then stalled_for += 0.2 else stalled_for = 0; last = state[:calls] end
  break if stalled_for >= 2.0 || mono.call - t0 > 20
end
sleep 1.0 # does the other thread still get its lines out?
File.write(RESULT, state.merge(stalled: stalled_for >= 2.0, at: (mono.call - t0).round(2),
  other_thread_silent_for: (mono.call - t0 - state[:other_last_at].to_f).round(2)).to_json + "\n")
exit!(0)
```

### `sum_prints.rb`

```ruby
require "json"
Dir.glob("/tmp/red-s2/out/prints/*.json").sort.each do |f|
  line = File.readlines(f).last or next
  j = JSON.parse(line) rescue (puts "#{File.basename(f)}: unparsable"; next)
  name = File.basename(f, ".json")
  per = j["results"].map do |r|
    red = r["origins"].select { |k, _| k.start_with?("red") }
    aj = r["origins"]["active_job"]
    "#{red.values.sum { _1["writes"] }}w/#{red.values.sum { _1["lines"] }}l/#{red.values.sum { _1["bytes"] }}B" + (aj ? " aj:#{aj["writes"]}w/#{aj["bytes"]}B" : "") +
      " [" + red.keys.map { _1.sub("red ", "").sub("commands/", "") }.join(" ") + "]"
  end
  puts "#{name.ljust(42)} q=#{j["queued_jobs"]} | " + per.join(" || ")
end
```

### `sum_worker.rb`

```ruby
require "json"
Dir.glob("/tmp/red-s2/out/worker/*_{silent,error}.json").sort.each do |f|
  j = JSON.parse(File.readlines(f).last) rescue (puts "#{File.basename(f)} unparsable"; next)
  enq = JSON.parse(File.readlines(f.sub(".json", ".enq.json")).last) rescue nil
  o = j["origins"]
  red = o.select { |k, _| k.start_with?("red") }
  gated = red.select { |k, _| k.include?("log_error.rb") }
  ungated = red.reject { |k, _| k.include?("log_error.rb") }
  aj = o["active_job"] || { "writes" => 0, "bytes" => 0 }
  caps = 3
  fmt = ->(h) { "#{h.values.sum { _1["writes"] } / caps}w #{(h.values.sum { _1["bytes"] } / caps / 1024.0).round(1)}KB" }
  puts "#{File.basename(f, ".json").ljust(32)} jobs=#{j["capture_job_rows"]} failed=#{j["failed_executions"]} pend=#{j["still_pending"]} #{j["seconds"]}s | per capture: RED gated #{fmt.(gated)}, RED ungated #{fmt.(ungated)}, ActiveJob #{aj["writes"] / caps}w #{(aj["bytes"] / caps / 1024.0).round(1)}KB | other jobs=#{j["jobs_by_class"].reject { |k,_| k.end_with?("AsyncErrorLoggingJob") }}"
  puts "   ungated sites: #{ungated.map { |k, v| "#{k.sub("red app/jobs/rails_error_dashboard/", "")}x#{v["writes"]}" }.join(" ")}"
end
```

### `sum_storm.rb`

```ruby
require "json"
puts "run | reports | captures reaching the write (gated 783 count) | RED gated w/l/KB | RED ungated w/KB | AJ w/KB | capture p50/p99/max ms | queued | worker: jobs, RED gated w, RED ungated w, AJ w, KB total, pending"
Dir.glob("/tmp/red-s2/out/storm/*.json").reject { _1.end_with?(".worker.json") }.sort.each do |f|
  j = JSON.parse(File.readlines(f).last) rescue next
  w = JSON.parse(File.readlines(f.sub(".json", ".worker.json")).last) rescue nil
  o = j["origins"]
  g = o.select { |k, _| k.start_with?("red") && !k.include?("app/jobs") }
  u = o.select { |k, _| k.include?("app/jobs") }
  aj = o["active_job"] || { "writes" => 0, "bytes" => 0 }
  sum = ->(h, k) { h.values.sum { _1[k] } }
  ws = if w
    wo = w["origins"]; wg = wo.select { |k, _| k.start_with?("red") && !k.include?("app/jobs") }; wu = wo.select { |k, _| k.include?("app/jobs") }
    "#{w["jobs_by_class"]} g=#{sum.(wg, "writes")} u=#{sum.(wu, "writes")} aj=#{wo.dig("active_job", "writes").to_i} #{(wo.values.sum { _1["bytes"] } / 1024.0).round} KB pend=#{w["still_pending"]} #{w["seconds"]}s"
  end
  puts "#{File.basename(f, ".json")} | #{j["reports"]} | #{o.dig("red commands/log_error.rb:783", "writes").to_i} | #{sum.(g, "writes")}/#{sum.(g, "lines")}/#{(sum.(g, "bytes") / 1024.0).round} | #{sum.(u, "writes")}/#{(sum.(u, "bytes") / 1024.0).round} | #{aj["writes"]}/#{(aj["bytes"] / 1024.0).round} | #{j["capture_ms"].values_at("p50", "p99", "max").join("/")} | #{j["queued"]} | #{ws}"
  puts "   sites: #{g.map { |k, v| "#{k.sub("red ", "").sub("commands/", "")}x#{v["writes"]}" }.join(" ")}"
end
```

### `storm_table.rb`

```ruby
# Builds the storm tables: request process and worker, gated vs ungated vs Active Job.
require "json"
def load(f) = (JSON.parse(File.readlines(f).last) rescue nil)
def part(o, &sel) = o.select { |k, _| sel.call(k) }.values.then { |v| [ v.sum { _1["writes"] }, v.sum { _1["lines"] }, v.sum { _1["bytes"] } ] }
def kb(b) = b >= 1_048_576 ? "#{(b / 1_048_576.0).round(1)} MB" : "#{(b / 1024.0).round} KB"
gated = ->(k) { k.start_with?("red") && !k.include?("app/jobs") }
ungated = ->(k) { k.include?("app/jobs") }
aj = ->(k) { k == "active_job" }
puts "| Rails | Mode | Storm protection | Classes | Reports | Reached the write | Request process: `:error` adds | Request process: Active Job | Worker: jobs run | Worker: `:error` adds | Worker: ungated RED | Worker: Active Job |"
puts "|---|---|---|---|---|---|---|---|---|---|---|---|"
Dir.glob("/tmp/red-s2/out/storm/*.json").reject { _1.end_with?(".worker.json") }.sort_by { f = File.basename(f = _1); [ f[/sync|async/] == "sync" ? 0 : 1, f.include?("storm-on") ? 0 : 1, f[/classes-(\d+)/, 1].to_i, f[/\A[\d.]+/] ] }.each do |f|
  j = load(f) or next
  w = load(f.sub(".json", ".worker.json"))
  o = j["origins"]
  g = part(o, &gated); a = part(o, &aj)
  reached = j["mode"] == "sync" ? o.dig("red commands/log_error.rb:783", "writes").to_i : j.dig("queued", "RailsErrorDashboard::AsyncErrorLoggingJob").to_i
  wcols = if w && w["still_pending"].to_i.zero? && !File.basename(f).start_with?("7.2_sync_storm-on_classes-1")
    wo = w["origins"]; wg = part(wo, &gated); wu = part(wo, &ungated); wa = part(wo, &aj)
    [ w["jobs_by_class"].values.sum, "#{wg[0]} writes, #{kb(wg[2])}", "#{wu[0]} writes, #{kb(wu[2])}", "#{wa[0]} writes, #{kb(wa[2])}" ]
  elsif w
    [ "#{w["jobs_by_class"].values.sum} rows, #{w["still_pending"]} pending at #{w["seconds"].round}s", "see note", "see note", "see note" ]
  else
    [ "n/a" ] * 4
  end
  puts "| #{j.dig("versions", "rails")[0, 3]} | #{j["mode"]} | #{j["storm"] ? "on" : "off"} | #{j["classes"]} | #{j["reports"]} | #{reached} | " \
       "#{g[0]} writes, #{g[1]} lines, #{kb(g[2])} | #{a[0]} writes, #{kb(a[2])} | #{wcols.join(" | ")} |"
end
```

### `cost_table.rb`

```ruby
require "json"
rows = %w[8.1 8.0 7.2].product(%w[file stdout_file stdout_pipe])
label = { "file" => "Logger opened by path", "stdout_file" => "STDOUT into a file", "stdout_pipe" => "STDOUT into a drained pipe" }
f = ->(s) { "#{s["p50"]} / #{s["p95"]} / #{s["p99"]}" }
puts "| Rails | Log target | One `Rails.logger.error` | The same, below the host's level | Failure block, `:silent` | Failure block, `:error` | Failing capture, `:silent` | Failing capture, `:error` |"
puts "|---|---|---|---|---|---|---|---|"
rows.each do |v, t|
  j = JSON.parse(File.read("/tmp/red-s2/out/cost/#{v}_#{t}.json"))
  puts "| #{v} | #{label[t]} | #{f.(j["one_call_us"])} | #{f.(j["one_call_below_level_us"])} | #{f.(j["failure_block_silent_us"])} | #{f.(j["failure_block_error_us"])} | #{f.(j["e2e_failing_capture_silent_us"])} | #{f.(j["e2e_failing_capture_error_us"])} |"
end
```

### `appendix_a.rb`

```ruby
# Builds Appendix A: every Logger.error call site, its path and what it prints.
require "open3"
rows = File.readlines("/tmp/red-s2/out/census_error.tsv").map { _1.chomp.split("\t") }
CAPTURE = %w[commands/log_error.rb error_reporter.rb middleware/error_catcher.rb commands/record_occurrence_context.rb
             services/error_hash_generator.rb plugin.rb]
def where(file, line, meth)
  f = file.sub("lib/rails_error_dashboard/", "")
  return "capture (at exit: `Gate.drain!` from `at_exit`, engine.rb:222)" if f.end_with?("gate.rb") && meth == "drain!"
  return "capture (every report: storm gate)" if f.end_with?("gate.rb") && meth == "admit!"
  return "capture (at most once per flush interval)" if f.end_with?("gate.rb")
  return "boot (plugin registration)" if f == "plugin_registry.rb" && meth == "register"
  return "capture (each plugin dispatch)" if f == "plugin_registry.rb"
  return "worker (StormFlushJob)" if f.include?("flush_storm_counts")
  return "capture" if CAPTURE.include?(f)
  "dashboard or maintenance (never during a capture)"
end
def prints(arg)
  out = []
  out << "the failure's message" if arg =~ /\be\.message\b/
  out << "the reported exception's message" if arg =~ /(@exception|error)\.message/
  out << "the capture's context (`inspect`, 500 chars)" if arg.include?("inspect.truncate")
  out << "backtrace (#{arg[/first\((\d+)\)/, 1]} frames)" if arg.include?("backtrace")
  out << "a file path" if arg.include?("file_path")
  out << "an error id" if arg.include?("error_log&.id")
  out << "a URL" if arg.include?("repository_url")
  out << "an error class only" if out.empty? && arg.include?("e.class")
  out.empty? ? "fixed text" : out.join("; ")
end
puts "| # | Site | Method | Path | Prints |"
puts "|---|---|---|---|---|"
rows.each_with_index do |(loc, meth, _recv, arg), i|
  file, line = loc.split(":")
  puts "| #{i + 1} | `#{file.sub("lib/rails_error_dashboard/", "")}:#{line}` | `#{meth}` | #{where(file, line, meth)} | #{prints(arg)} |"
end
```

### `appendix_tables.rb`

```ruby
# Appendix A2 (print matrix) and A3 (worker matrix) as markdown tables.
require "json"
def j(f) = (JSON.parse(File.readlines(f).last) rescue nil)
kb = ->(b) { "#{(b / 1024.0).round(1)} KB" }
puts "### A2. The print matrix (`prints.rb`, `log_level :error`), per capture\n\n"
puts "Captures 2 and 3 matched capture 1 in every run. \"Active Job\" is its log subscriber's lines in the request process.\n\n"
puts "| Database | Rails | Path | Break | RED writes | Lines | Bytes | RED sites | Active Job |"
puts "|---|---|---|---|---|---|---|---|---|"
Dir.glob("/tmp/red-s2/out/prints/*.json").sort.each do |f|
  r = j(f) or next
  db, v, *rest = File.basename(f, ".json").split("_")
  brk = %w[none no_table no_column_live no_column_boot not_null].find { |b| File.basename(f, ".json").end_with?("_#{b}") }
  path = File.basename(f, ".json").sub("#{db}_#{v}_", "").sub("_#{brk}", "")
  o = r["results"][0]["origins"]
  red = o.select { |k, _| k.start_with?("red") }
  a = o["active_job"]
  same = r["results"].map { _1["origins"].select { |k, _| k.start_with?("red") }.transform_values { |x| x["writes"] } }.uniq.size == 1
  puts "| #{db} | #{v} | #{path} | #{brk} | #{red.values.sum { _1["writes"] }} | #{red.values.sum { _1["lines"] }} | #{red.values.sum { _1["bytes"] }} | #{red.keys.map { "`#{_1.sub("red ", "").sub("commands/", "")}`" }.join(", ")}#{same ? "" : " (varied)"} | #{a ? "#{a["writes"]} (#{kb.(a["bytes"])})" : "0"} |"
end
puts "\n### A3. The worker matrix (`prints.rb` with `PATH_KIND=enqueue`, then `worker.rb`), 3 captures per run\n\n"
puts "| Database | Rails | Break | `log_level` | Job rows | Seconds | Gated RED writes | Ungated RED writes | Active Job writes | Total bytes |"
puts "|---|---|---|---|---|---|---|---|---|---|"
Dir.glob("/tmp/red-s2/out/worker/*_{silent,error}.json").sort.each do |f|
  w = j(f) or next
  n = File.basename(f, ".json")
  db, v = n.split("_")
  lvl = n.split("_").last
  brk = n.sub("#{db}_#{v}_", "").sub("_#{lvl}", "")
  o = w["origins"]
  g = o.select { |k, _| k.start_with?("red") && !k.include?("app/jobs") }.values.sum { _1["writes"] }
  u = o.select { |k, _| k.include?("app/jobs") }.values.sum { _1["writes"] }
  puts "| #{db} | #{v} | #{brk} | `:#{lvl}` | #{w["capture_job_rows"]} | #{w["seconds"]} | #{g} | #{u} | #{o.dig("active_job", "writes").to_i} | #{o.values.sum { _1["bytes"] }} |"
end
```

### `appendix_b.rb`

```ruby
# Assembles Appendix B from the scratch folder, replacing absolute home and repo paths.
home = Dir.home
files = %w[run.sh fresh.sh prints_matrix.sh worker_matrix.sh storm_matrix.sh cost.sh] .map { "/tmp/red-s2/#{_1}" } +
        %w[census.rb census_bypass.rb boot.rb prints.rb worker.rb reporter_fail.rb host_code_fail.rb storm.rb
           logcost.rb proto_cost.rb stall.rb sum_prints.rb sum_worker.rb sum_storm.rb storm_table.rb cost_table.rb appendix_a.rb appendix_tables.rb appendix_b.rb].map { "/tmp/red-s2/probe/#{_1}" }
out = +"Run from `/tmp/red-s2`. `run.sh` picks the bundle and the database; `fresh.sh` makes a throwaway database\n" \
       "for each run; the `*_matrix.sh` scripts and `cost.sh` ran the batches; the `sum_*.rb` scripts built the tables.\n" \
       "`<repo>` is the repository checkout and `~` the home folder.\n"
files.each do |f|
  next unless File.exist?(f)
  lang = f.end_with?(".sh") ? "bash" : "ruby"
  body = File.read(f).gsub("<repo>", "<repo>").gsub(home, "~")
  out << "\n### `#{File.basename(f)}`\n\n```#{lang}\n#{body.rstrip}\n```\n"
end
File.write("/tmp/red-s2/out/appendix_b.md", out)
puts out.lines.size
```
