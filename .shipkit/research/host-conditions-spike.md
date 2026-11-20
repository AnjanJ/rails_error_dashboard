# Spike S1: how a capture survives the host's transaction, write prevention and a starved pool

> Researched 2026-11-20 for the spec `hardening-1-0-rc2` (T1, REQ-17 to REQ-22), on branch
> `spec/hardening-1-0-rc2` at `7d055cad`. Every probe ran on one MacBook (Apple silicon, macOS 27.2), Ruby 3.4.5,
> against rc.1's code with each option patched in memory. No product code was changed. The probe code is in
> Appendix B; the scratch folder was `/tmp/red-s1`.

## The answer

- **Option 2 is the only option that kept every case on every database and Rails version.** Option 2 means that
  inside a host transaction the capture waits for the transaction to end, and the write itself allows writes and
  takes a bounded wait for a connection. It kept all 7 transaction and write-prevention cases in all 36 of its runs
  (3 modes × 12 cells), 252 captures. With a held pool it gave up after one 0.1 s wait. It adds no database connection and about 2 µs per capture.
- **Option 1 (RED's own pool) is ruled out.** On SQLite, every capture inside a host write transaction fails,
  including one that commits, which rc.1 stores. On Rails 8.0 and 8.1 the caller also waits 5 s first. Option 1
  doesn't help async capture, adds 2 database connections per process, and on its own doesn't get past
  `while_preventing_writes`.
- **Option 3 (a background thread) is ruled out.** It kept every case in the main matrix, but:
  - on SQLite under Rails 7.2 it lost captures, and in one case stalled the host's own thread for 5.4 s;
  - with every pool connection in use by request threads (Rails' default sizing) it dropped 2 of 5 captures;
  - its in-memory queue is lost when the process exits.
- **rc.1 loses more than the review found.** The review found three losses: a rollback, a prevented write and a
  starved pool. The probes also show:
  - a rolled-back **savepoint** loses the capture even when the outer transaction commits;
  - **async capture outside a request loses all of these cases too**, with no log line for a rollback;
  - with a held pool, async capture blocks for **6 s**, and a separate error database blocks for **10 s**.
- **Names.** Option 2 fits both provisional settings: `isolate_capture_writes` (default `true`) and
  `capture_connection_timeout` (default `0.1`). The maintainer accepted option 2, both names, the reading-role
  write and the private-lease fallback on 2026-11-20.

## What was run

- **Databases.** SQLite 3.54.1 (in the sqlite3 2.10.2 gem). PostgreSQL 16.16 (Homebrew). MySQL 8.4.13 (Homebrew
  `mysql@8.4`, the series CI runs, `test.yml:93`). MySQL 26.10.0 (Homebrew `mysql`, what `brew install mysql` gives
  today). PostgreSQL and MySQL went through the `pg` 1.7.0 and `trilogy` 2.13.3 adapters, as in CI. Every
  database was a throwaway created for this spike.
- **Rails.** 7.2.4, 8.0.5.2 and 8.1.4.1, each from its own bundle outside the repository (a Gemfile that
  `eval_gemfile`s the repo's, with `RAILS_VERSION` set), so the repo's `Gemfile.lock` was never touched. Solid Queue
  1.7.2. `spec/dummy` runs `load_defaults` for its own Rails version, so each version's defaults applied
  (`enqueue_after_transaction_commit` included).
- **Modes.**
  - `sync`: `async_logging = false`.
  - `async, no request`: `async_logging = true` with Solid Queue on the same database, and no request env. This
    is a job, a console, a rake task, or a server without `rack.response_finished`.
  - `async, in a request`: the same, inside a request whose server offers `rack.response_finished`. That's Puma
    8.0.2 and later, and Rails 8.1's executor (decision 0009). The probe runs the callbacks after the case's
    block, as Puma does after the response.

  Queued jobs were then run inline, like a worker.
- **Cells.** 4 databases × 3 Rails versions = 12 cells. Each cell ran every mode and every option in its own
  process, so 180 runs in the main matrix. Each capture was a `Rails.error.report(error, handled: true,
  severity: :error)`. RED skips handled warnings by design (`error_reporter.rb:25`), and `severity: :error` is how
  a host reports an error it rescues.
- **"Kept"** means the group's `occurrence_count` sum went up by exactly one. No run counted two.
- **What is reproduced and what is only read.** Every table is reproduced, by the probe named in Appendix B. The
  Rails facts under "Read in the Rails source" were read, not run, unless a probe is cited next to them.

## The cases

| Case | What the host does around the report |
|---|---|
| `commit` | `transaction { create a row; report }` (the control) |
| `rollback` | `transaction { create a row; report; raise ActiveRecord::Rollback }` |
| `nested_rollback` | `transaction { create a row; transaction(requires_new: true) { report; rollback } }`: the outer commits |
| `nested_then_outer_rollback` | as above, then the outer transaction rolls back too |
| `savepoint_commit_outer_rollback` | the savepoint commits with the report in it, then the outer rolls back |
| `prevent_writes` | `ActiveRecord::Base.while_preventing_writes { report }` |
| `reading_role` | `ActiveRecord::Base.connected_to(role: :reading, prevent_writes: true) { report }`, as `DatabaseSelector` does. The reading role points at a replica that is read-only in the database too: `default_transaction_read_only` on PostgreSQL, `transaction_read_only` on MySQL. SQLite has no such setting, so its replica relies on `prevent_writes` alone |
| `held_pool` | Every connection of the pool RED writes through is checked out by other threads, the reporting thread holds none, and the reported error is an `ActiveRecord::ConnectionTimeoutError`: the host's own pool has run dry. `checkout_timeout` is 2 s (Rails' default is 5 s), and the pool is held for 3 s |
| `host_pool_held` | Option 1 only: the host's pool is held and RED's own pool is free |

## Results at a glance

Kept cells out of 12 (4 databases × 3 Rails versions). For `held_pool`, every option that bounds the wait
gives up by design (REQ-20), so 0/12 is the expected result there. What matters is how long the caller waits,
in the next sections.

| Option | Mode | `commit` | `rollback` | `nested_rollback` | `nested_then_outer_rollback` | `savepoint_commit_outer_rollback` | `prevent_writes` | `reading_role` | `held_pool` |
|---|---|---|---|---|---|---|---|---|---|
| rc.1 | sync | 12/12 | 0/12 | 0/12 | 0/12 | 0/12 | 0/12 | 0/12 | 0/12 |
| rc.1 | async, no request | 12/12 | 0/12 | 0/12 | 0/12 | 0/12 | 0/12 | 0/12 | 0/12 |
| rc.1 | async, in a request | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 0/12 |
| Option 1 | sync | 9/12 | 9/12 | 9/12 | 9/12 | 9/12 | 0/12 | 0/12 | 0/12 |
| Option 1 | async, no request | 12/12 | 0/12 | 0/12 | 0/12 | 0/12 | 0/12 | 0/12 | 12/12 |
| Option 1 | async, in a request | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 |
| Option 1 + role wrapper | sync | 9/12 | 9/12 | 9/12 | 9/12 | 9/12 | 12/12 | 12/12 | 0/12 |
| Option 1 + role wrapper | async, no request | 12/12 | 0/12 | 0/12 | 0/12 | 0/12 | 12/12 | 12/12 | 12/12 |
| Option 1 + role wrapper | async, in a request | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 |
| Option 2 | sync | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 0/12 |
| Option 2 | async, no request | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 0/12 |
| Option 2 | async, in a request | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 0/12 |
| Option 3 | sync | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 0/12 |
| Option 3 | async, no request | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 0/12 |
| Option 3 | async, in a request | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | 0/12 |

## rc.1 today (reproduced)

- **A rollback loses the capture, and so does a rolled-back savepoint whose outer transaction commits.** This
  held in all 12 cells, sync and async without a request. No line is logged: the INSERT, or the job's row, simply
  rolls back.
- **Write prevention and the reading role lose it, with a log line**, in all 12 cells:
  - sync: `ActiveRecord::ReadOnlyError - Lock query attempted while in readonly mode`, from the `FOR UPDATE` in
    `FindOrIncrementError`, on SQLite as well as PostgreSQL and MySQL;
  - async: `Async enqueue failed (SolidQueue::Job::EnqueueError …)`, then the sync fallback fails the same way.
- **Async enqueue inside a transaction is silent on every Rails version, by two routes.**
  - Rails 7.2 with Solid Queue defers the enqueue to the commit (`load_defaults "7.2"` sets
    `enqueue_after_transaction_commit = :default`, and Solid Queue's adapter answers `true`). A rollback drops the
    job, but `successfully_enqueued` was already set to `true` (activejob 7.2.4
    `enqueue_after_transaction_commit.rb:16-20`), so RED's enqueue check (`ApplicationJob.enqueued?`) passes.
  - Rails 8.0 and 8.1 enqueue inside the transaction (the default is `false`), and the rollback removes the row.
- **Async capture in a request already survives every transaction and role case.** The enqueue runs after the
  response (decision 0009), outside the host's transaction, role and write prevention. It still loses a held-pool
  capture, and Puma's thread spends the waits after the response.
- **A held pool blocks the caller in every cell:**

| Mode | Caller blocked | Waits |
|---|---|---|
| sync | 4.02 to 4.04 s | 2 × `checkout_timeout`: `find_or_create_application`, then its `Application.first` fallback (`log_error.rb:899-904`) |
| async, no request | 6.03 to 6.06 s | the enqueue's checkout, then the sync fallback's two |
| async, in a request | 1.0 to 1.6 ms, then 6.04 to 6.06 s after the response | the same three, on Puma's thread |
| sync, separate error database | 10.03 to 10.05 s | 5 × `checkout_timeout`: the reporting thread holds no lease on RED's pool, so each query checks out on its own |

At Rails' default `checkout_timeout` of 5 s, those figures are 10 s, 15 s and 25 s.

## Option 1: RED's own small pool through `connects_to` (reproduced)

What was probed:
- `ErrorLogsRecord.connects_to` the host's database configuration, with a pool of 2 and `checkout_timeout`
  0.1 s;
- the same with each capture wrapped in `ErrorLogsRecord.connected_to(role: :writing, prevent_writes: false)`
  ("role wrapper").

Results:
- **SQLite: every capture inside a host write transaction fails, even one that commits.** The host's connection
  holds SQLite's write lock, and RED's second connection can't write until it's released.
  - Rails 8.0 and 8.1 wait out the 5 s busy timeout first (`StatementTimeout`).
  - Rails 7.2 fails in 19 to 40 ms (`BusyException`). 7.2 opens transactions DEFERRED (`conn.transaction`),
    while 8.0 and 8.1 open them IMMEDIATE (`default_transaction_mode: :immediate`, `sqlite3_adapter.rb:162` in
    8.1). The difference was read, and fits the times measured.
  - rc.1 stores the `commit` case. Option 1 loses it.
- **PostgreSQL and MySQL: rollbacks and savepoints are kept**, because RED's write is on its own connection.
- **`while_preventing_writes` still reaches RED's own class.** The `prevent_writes` flag set by Base applies to
  every class (`core.rb:197` in 7.2: `hash[:klasses].include?(Base)`). Without the role wrapper, write prevention
  and the reading role lose the capture in all 12 cells. With it, they're kept in all 12.
- **Async capture is not helped.** The enqueue still goes through the host's connection, inside its transaction,
  so a rollback is lost exactly as in rc.1.
- **Held pool (RED's pool held):** the caller gives up after 0.21 to 0.23 s, which is 2 waits of 0.1 s. REQ-21
  (T13) would make it one. With the host's pool held instead, RED's free pool stores the capture in 7 to 63 ms.
- **Connections:** +2 per process on PostgreSQL and MySQL (5 → 7, counted by the server), and +1 on SQLite in
  this test. Every Puma worker and every Solid Queue process that loads RED gets its own pool.

## Option 2: wait for the host's transaction, on the shared connection (reproduced)

What was probed (`options.rb`, `install_o2`), at three points:
1. **The entry** (`LogError.call`): if `ActiveRecord::Base.current_transaction.open?`, the capture is
   registered with that transaction's `after_commit` and `after_rollback`. When either runs, the check is made
   again, so a savepoint waits for its parent.
2. **The sync write** (`LogError#call`) runs inside `ActiveRecord::Base.connected_to(role: :writing,
   prevent_writes: false)`. It leases RED's pool and the host's pool with a wait of at most 0.1 s each; with a
   shared database these are one pool.
3. **The async enqueue** (`LogError.enqueue_async`) gets the same treatment, leasing only the host's pool, where
   Solid Queue lives. The enqueue can run after the response, so no connection is leased on the request thread
   for work that happens later.

Results:
- **All 7 transaction and write-prevention cases were kept in all 36 runs** (12 cells × 3 modes), each exactly
  once.
- **Held pool:**
  - sync: the caller gives up after 101 to 111 ms, one wait, logged;
  - async, no request: 103 to 114 ms;
  - async, in a request: 1.0 to 1.6 ms on the request, then 104 to 114 ms after the response.
- **Separate error database:** every case kept on SQLite and PostgreSQL under 7.2 and 8.1, sync and async. With
  RED's pool held, a sync capture gives up after 106 to 113 ms, against 10 s in rc.1.
- **The public API is enough.** Rails 7.2's `ActiveRecord::Base.current_transaction` returns an
  `ActiveRecord::Transaction` with `open?`, `after_commit` and `after_rollback` (activerecord 7.2.4
  `transaction.rb:85-119`), and it checks out no connection (`transactions.rb:245-247`). The gemspec requires
  Rails 7.2 or later (`rails_error_dashboard.gemspec:111`). Inside a savepoint's `after_rollback` it already
  returns the enclosing open transaction, on 7.2, 8.0 and 8.1 (`txn_api.rb`).
- **The bounded lease uses a private method.** Rails has no public "lease a connection, waiting at most N
  seconds". The probe calls the public `ConnectionPool#checkout(timeout)` and then puts the connection in the
  private `connection_lease`, which exists in 7.2, 8.0 and 8.1. See "Open points for T30".
- **Capture time:** about 2 µs per capture for the entry check and the write guard together (`guard_cost.rb`;
  2.00 to 2.19 µs on every Rails version, SQLite and PostgreSQL). Inside a transaction, the caller's time drops
  to about 0.01 ms and the capture's cost moves to the transaction's end.

## Option 3: a bounded background thread (reproduced)

What was probed (`options.rb`, `install_o3`):
- the caller builds the same payload as async capture (`LogError.call_async`), so every thread-local is read on
  the caller's thread;
- one worker thread per process, with a queue of at most 100, writes the payload (sync) or enqueues it (async),
  leasing with a 0.1 s wait.

Results:
- **The main matrix: every transaction and write-prevention case kept.** The caller took 0.08 to 0.2 ms in
  the matrix. In `bench.rb` its median was 0.02 to 0.05 ms, except SQLite async at 0.34 to 0.37 ms.
- **SQLite under Rails 7.2, with the host's write lock held 0.5 s after the report** (`rollback_hold`,
  `commit_hold`):
  - sync: the worker's write fails at once (`BusyException`), so the capture is lost, even when the host commits;
  - async: the host's own transaction block took 5.44 s instead of 0.5 s. The worker's Solid Queue INSERT waits in
    7.2's C-level `busy_timeout` (`sqlite3_adapter.rb:786`, read), which fits Ruby's global lock being held for
    the wait (inferred, not traced).
  - 8.0 and 8.1 use `busy_handler_timeout` and passed both cases.
- **A busy pool drops captures.** With 5 request threads each holding one of the pool's 5 connections, the
  worker got none within 0.1 s and dropped 2 of 5 captures (`conns.rb`; SQLite, PostgreSQL and MySQL 8.4).
  Option 2 uses the connection the request thread already holds, and dropped none.
- **A feedback loop.** The first worker ran each job in `Rails.application.executor.wrap`. That reports a
  raised error to `Rails.error`, RED captured it, and the capture queued another write, 30 checkouts in 3 s
  while the pool was held. The probe now sets RED's own recursion guard (`error_reporter.rb:31`). Any thread RED
  starts must do the same.
- **Durability.** The in-memory queue is lost when the process exits, and the thread must be restarted after
  `fork`.

## SQLite with the host's write lock held (reproduced)

`CASES=rollback_hold,commit_hold`: the host keeps its write transaction open for 0.5 s after the report.
"Block" is the host's whole transaction block, so 0.5 s is the floor.

| Rails | Mode | rc.1 | Option 2 | Option 3 |
|---|---|---|---|---|
| 7.2 | sync | rollback lost; commit kept (block 0.64 / 0.55 s) | both kept (0.67 / 0.60 s) | **both lost** (0.53 / 0.52 s) |
| 7.2 | async | rollback lost; commit kept (0.58 / 0.62 s) | both kept (0.64 / 0.57 s) | both kept, **block 5.44 s** |
| 8.0 | sync | rollback lost; commit kept (0.64 / 0.55 s) | both kept (0.67 / 0.60 s) | both kept (0.53 / 0.52 s) |
| 8.0 | async | rollback lost; commit kept (0.59 / 0.58 s) | both kept (0.63 / 0.54 s) | both kept (0.53 / 0.52 s) |
| 8.1 | sync | rollback lost; commit kept (0.64 / 0.55 s) | both kept (0.67 / 0.55 s) | both kept (0.53 / 0.51 s) |
| 8.1 | async | rollback lost; commit kept (0.60 / 0.56 s) | both kept (0.62 / 0.57 s) | both kept (0.54 / 0.51 s) |

## Separate error database (reproduced)

RED's tables in their own database, connected as `use_separate_database` does (`engine.rb:29-31`), with Solid
Queue on the host's database. "Held" is RED's pool held.

| Database | Rails | Mode | rc.1 | Option 2 | Option 3 |
|---|---|---|---|---|---|
| SQLite | 7.2, 8.1 | sync | rollbacks kept; `prevent_writes` and `reading_role` lost; held: blocked 10.04 to 10.05 s | all kept; held: gave up at 0.11 s | all kept; held: dropped, caller 0 ms |
| SQLite | 7.2, 8.1 | async | rollbacks, `prevent_writes`, `reading_role` lost; held: kept | all kept, held included | all kept, held included |
| PostgreSQL 16 | 7.2, 8.1 | sync | rollbacks kept; `prevent_writes` and `reading_role` lost; held: blocked 10.03 to 10.05 s | all kept; held: gave up at 0.11 s | all kept; held: dropped, caller 0 ms |
| PostgreSQL 16 | 7.2, 8.1 | async | rollbacks, `prevent_writes`, `reading_role` lost; held: kept | all kept, held included | all kept, held included |

## Capture time (reproduced; median / p95 in ms, the reporting thread only)

`bench.rb`: 300 reports of one error (the increment path), after 5 to warm up. Run one at a time on an
otherwise idle machine.

How to read this:
- **These are laptop figures.** Compare columns within a row, never against the 5 ms budget, which
  `bin/benchmark` measures (T30's done-when).
- **PostgreSQL and MySQL 26.10 sync are noisy.** The same code gave 5.93 ms in one batch and 9.63 ms in the
  next (option 2, PostgreSQL 16, Rails 8.1), most likely because each commit syncs to disk. Their rows can't
  show a 0.2 ms change. SQLite and MySQL 8.4 repeat within about 0.1 ms.
- **Option 2's own cost is measured directly** by `guard_cost.rb`: 2.0 to 2.2 µs per capture.
- **Option 1 with the role wrapper timed out on SQLite under Rails 8.0 and 8.1.** Each of the 100 in-transaction
  reports waited 5 s.

Reports of one error, repeated (median / p95):

| Database | Rails | Mode | rc.1 (baseline) | Option 1 + role wrap | Option 2 | Option 3 |
|---|---|---|---|---|---|---|
| SQLite | 7.2 | sync | 0.714 / 3.532 | 0.74 / 2.837 | 0.775 / 2.366 | 0.049 / 1.906 |
| SQLite | 7.2 | async | 0.339 / 1.884 | 0.342 / 1.879 | 0.358 / 1.978 | 0.362 / 2.513 |
| SQLite | 8.0 | sync | 0.723 / 3.648 | timed out (5 s per capture in a transaction) | 0.763 / 2.483 | 0.053 / 2.541 |
| SQLite | 8.0 | async | 0.344 / 1.759 | 0.377 / 2.003 | 0.38 / 2.198 | 0.367 / 2.432 |
| SQLite | 8.1 | sync | 0.767 / 4.272 | timed out (5 s per capture in a transaction) | 0.817 / 2.174 | 0.054 / 2.687 |
| SQLite | 8.1 | async | 0.314 / 1.634 | 0.327 / 1.713 | 0.333 / 1.926 | 0.341 / 2.083 |
| PostgreSQL 16 | 7.2 | sync | 7.378 / 13.24 | 8.141 / 14.464 | 2.715 / 7.023 | 0.02 / 0.502 |
| PostgreSQL 16 | 7.2 | async | 0.939 / 2.835 | 0.999 / 2.823 | 0.965 / 2.498 | 0.022 / 0.84 |
| PostgreSQL 16 | 8.0 | sync | 9.45 / 13.733 | 8.561 / 13.675 | 6.831 / 13.006 | 0.025 / 0.615 |
| PostgreSQL 16 | 8.0 | async | 0.818 / 2.195 | 0.836 / 2.331 | 0.824 / 2.252 | 0.027 / 0.839 |
| PostgreSQL 16 | 8.1 | sync | 5.957 / 12.231 | 8.841 / 13.316 | 9.629 / 13.895 | 0.024 / 0.485 |
| PostgreSQL 16 | 8.1 | async | 0.834 / 2.2 | 1.006 / 2.288 | 0.829 / 2.297 | 0.03 / 1.444 |
| MySQL 8.4 | 7.2 | sync | 1.394 / 5.296 | 1.249 / 3.676 | 1.344 / 2.808 | 0.027 / 0.957 |
| MySQL 8.4 | 7.2 | async | 0.72 / 2.285 | 0.713 / 2.265 | 0.714 / 2.233 | 0.028 / 1.23 |
| MySQL 8.4 | 8.0 | sync | 1.315 / 4.891 | 1.245 / 3.58 | 1.226 / 2.473 | 0.033 / 1.159 |
| MySQL 8.4 | 8.0 | async | 0.698 / 2.324 | 0.73 / 2.207 | 0.737 / 2.304 | 0.038 / 1.406 |
| MySQL 8.4 | 8.1 | sync | 1.221 / 5.668 | 1.328 / 3.77 | 1.217 / 2.721 | 0.032 / 1.127 |
| MySQL 8.4 | 8.1 | async | 0.684 / 2.207 | 0.714 / 2.018 | 0.685 / 1.853 | 0.034 / 1.292 |
| MySQL 26.10 | 8.1 | sync | 5.27 / 15.963 | 2.816 / 6.018 | 3.125 / 11.242 | 0.024 / 0.613 |
| MySQL 26.10 | 8.1 | async | 1.249 / 3.101 | 1.884 / 3.304 | 2.412 / 5.776 | 0.024 / 0.595 |

Inside an open host transaction (caller median, then the transaction end's median):

| Database | Rails | Mode | rc.1 caller / end | Option 1 + wrap caller / end | Option 2 caller / end | Option 3 caller / end |
|---|---|---|---|---|---|---|
| SQLite | 7.2 | sync | 0.622 / 0.061 | 0.654 / 0.02 | 0.006 / 0.75 | 0.049 / 0.021 |
| SQLite | 7.2 | async | 0.059 / 0.289 | 0.06 / 0.285 | 0.006 / 0.351 | 0.341 / 0.139 |
| SQLite | 8.0 | sync | 0.647 / 0.061 | timed out | 0.016 / 0.816 | 0.031 / 0.016 |
| SQLite | 8.0 | async | 0.296 / 0.07 | 0.29 / 0.068 | 0.014 / 0.402 | 0.029 / 0.016 |
| SQLite | 8.1 | sync | 0.742 / 0.067 | timed out | 0.016 / 0.829 | 0.031 / 0.016 |
| SQLite | 8.1 | async | 0.251 / 0.068 | 0.266 / 0.071 | 0.015 / 0.36 | 0.03 / 0.016 |
| PostgreSQL 16 | 7.2 | sync | 5.39 / 0.584 | 8.515 / 0.471 | 0.055 / 12.686 | 0.057 / 0.371 |
| PostgreSQL 16 | 7.2 | async | 0.071 / 0.835 | 0.065 / 0.804 | 0.006 / 0.938 | 0.033 / 0.198 |
| PostgreSQL 16 | 8.0 | sync | 7.717 / 0.879 | 10.419 / 0.781 | 0.076 / 8.892 | 0.048 / 0.24 |
| PostgreSQL 16 | 8.0 | async | 0.677 / 0.144 | 0.666 / 0.15 | 0.015 / 1.03 | 0.069 / 0.162 |
| PostgreSQL 16 | 8.1 | sync | 6.549 / 0.827 | 12.122 / 0.753 | 0.117 / 12.74 | 0.086 / 0.42 |
| PostgreSQL 16 | 8.1 | async | 0.702 / 0.198 | 0.749 / 0.188 | 0.019 / 0.767 | 0.059 / 0.144 |
| MySQL 8.4 | 7.2 | sync | 0.856 / 0.13 | 1.207 / 0.093 | 0.008 / 1.257 | 0.039 / 0.136 |
| MySQL 8.4 | 7.2 | async | 0.071 / 0.781 | 0.072 / 0.779 | 0.006 / 0.837 | 0.051 / 0.172 |
| MySQL 8.4 | 8.0 | sync | 0.906 / 0.135 | 1.221 / 0.091 | 0.019 / 1.34 | 0.046 / 0.15 |
| MySQL 8.4 | 8.0 | async | 0.576 / 0.169 | 0.566 / 0.166 | 0.015 / 0.933 | 0.068 / 0.189 |
| MySQL 8.4 | 8.1 | sync | 0.914 / 0.136 | 1.255 / 0.088 | 0.019 / 1.319 | 0.045 / 0.151 |
| MySQL 8.4 | 8.1 | async | 0.539 / 0.185 | 0.53 / 0.164 | 0.017 / 0.908 | 0.062 / 0.183 |
| MySQL 26.10 | 8.1 | sync | 5.265 / 1.212 | 10.15 / 1.144 | 0.108 / 10.641 | 0.107 / 0.623 |
| MySQL 26.10 | 8.1 | async | 0.677 / 0.3 | 1.222 / 0.559 | 0.039 / 3.263 | 0.074 / 0.261 |

Option 2's guard alone (`guard_cost.rb`, 20,000 calls, best of 3, the thread already holding a connection):

| Rails | Database | transaction check | entry, no transaction | write guard | entry + write guard |
|---|---|---|---|---|---|
| 7.2.4 | SQLite | 0.33 µs | 0.37 µs | 1.65 µs | 2.15 µs |
| 8.0.5.2 | SQLite | 0.34 µs | 0.37 µs | 1.68 µs | 2.19 µs |
| 8.1.4.1 | SQLite | 0.31 µs | 0.32 µs | 1.63 µs | 2.04 µs |
| 8.1.4.1 | PostgreSQL 16 | 0.30 µs | 0.31 µs | 1.61 µs | 2.00 µs |

## Database connections (reproduced)

`conns.rb`, Rails 8.1: connections open from one process. "Peak" is while 5 threads each hold a host connection
and capture at once, as busy Puma threads would. The server's own count (`pg_stat_activity`,
`information_schema.processlist`) matched the process's count in every PostgreSQL and MySQL run.

| Database | rc.1 peak | Option 1 + role wrapper | Option 2 | Option 3 |
|---|---|---|---|---|
| PostgreSQL 16 | 5 | 7 (+2) | 5 (+0) | 5 (+0), 2 of 5 captures dropped |
| MySQL 8.4 | 5 | 7 (+2) | 5 (+0) | 5 (+0), 2 of 5 captures dropped |
| MySQL 26.10 | 5 | 7 (+2) | 5 (+0) | 5 (+0), 2 of 5 captures dropped |
| SQLite | 5 | 6 (+1) | 5 (+0) | 5 (+0), 2 of 5 captures dropped |

Option 1's +2 is per process that loads RED. For example, 4 Puma workers and 2 Solid Queue processes come to
+12 on PostgreSQL. This is arithmetic, not measured.

## The options side by side

| | Option 1: own pool (+ role wrapper) | Option 2: wait for the transaction | Option 3: background thread |
|---|---|---|---|
| Rollback, savepoints | lost on SQLite, sync; lost in async, no request | kept everywhere | kept, except SQLite on Rails 7.2 |
| `while_preventing_writes`, reading role | only with the role wrapper | kept everywhere | kept everywhere |
| Held pool, caller's wait | 0.21 s (0.1 s once T13 lands) | 0.10 to 0.11 s, once | about 0.1 ms; the capture is dropped |
| Extra connections per process | +2 (pool size) | 0 | 0 in use, but takes one from the host's pool |
| Capture-time change | on SQLite inside a write transaction: up to +5 s; elsewhere within noise | +2 µs (`guard_cost.rb`) | the caller drops to about 0.05 ms; the work moves off-thread |
| New host risk | SQLite lock waits on the request | the write moves to the transaction's end | SQLite 7.2 stall; busy-pool drops; queue lost on exit |
| Switch | `isolate_capture_writes = false` drops the `connects_to` | `isolate_capture_writes = false`: no deferral, no write-allowance, no bounded lease, which is rc.1 | `isolate_capture_writes = false`: no thread |

## Recommendation

**Option 2**, behind `isolate_capture_writes` (default `true`), with `capture_connection_timeout` (default
`0.1`) as the bounded wait. Both provisional names fit:
- "isolate" names the effect, a capture's write kept apart from the host's transaction outcome, role and write
  prevention;
- the timeout is exactly the bounded lease.

The amendment to spec.md and design.md writes this up as a decision record, and T30's file list follows it.

## Open points for T30 (all accepted by the maintainer on 2026-11-20)

1. **Where the deferral sits.**
   - **Placement:** after the ignore filter and the storm gate, not at the very top of `LogError.call`.
     Otherwise every count-only storm event inside a long transaction would hold a closure until the
     transaction ends.
   - **A cap:** at most 100 deferred captures per transaction, the bound option 3's queue used and Honeybadger
     uses. The rest are dropped and counted.
2. **The report time.** A deferred capture is stamped when it is reported, not when the transaction ends. The
   async path already does this with `_captured_at` (`log_error.rb:170`).
3. **The private lease.**
   - **The proposal:** use `checkout(timeout)` plus the private `connection_lease`, behind
     `respond_to?(:connection_lease, true)`. Where it is missing, fall back to the pool's own wait (rc.1's
     behaviour) and log once at debug.
   - **Coverage:** `host_conditions_spec.rb` pins it on 7.2, 8.0 and 8.1, and T31's chaos rows catch a Rails
     release that changes it.
4. **The reading role writes to the writing database.**
   - **What changes:** in a reading-role request, option 2 moves the capture onto the writing role.
   - **The cost:** in a multi-region setup whose writing database is far away, the write pays that round trip on
     the request (sync capture). This is read, not measured: no remote database was available here.
   - **Today:** rc.1 drops the capture instead.
   - **Why the proposal stands:** REQ-18 says to store it, and async capture in a request already pays the trip
     after the response.
   - **Accepted by the maintainer** on 2026-11-20, as a new cost on the request path that
     `CONFIGURATION.md` states (T30).
5. **Which pools are leased.** The sync write leases RED's pool and the host's. The async enqueue leases only the
   host's. With a separate error database, leasing RED's pool for the enqueue dropped captures rc.1 keeps (first
   run of the separate-database async rows). Those four runs were re-run with the code in Appendix B.

## Limits

- **One machine, one Ruby (3.4.5).** CI also runs Ruby 3.3 and 4.0. Nothing here depends on the Ruby version
  that I know of, but none of it ran there.
- **Not tested:**
  - Puma in cluster mode;
  - fiber isolation (`config.active_support.isolation_level = :fiber`, as under Falcon);
  - Sidekiq, or any queue that isn't Solid Queue;
  - Solid Queue in its own database (Rails 8's production default);
  - a real replica server;
  - MySQL 8.0 itself. MySQL 8.4 stands in for "MySQL 8", as in CI.
- **The request is simulated.** The "in a request" rows set the env RED reads and run its callbacks; no Puma
  process was started.
- **`checkout_timeout` was 2 s**, to keep runs short. rc.1's waits scale with it (5 s is Rails' default).

## Appendix A: every table

Rows are database × Rails. "kept" or "LOST", with the caller's time where it was 50 ms or more, or for a held
pool.


#### rc.1 / sync

| Database | Rails | commit | rollback | nested_rollback | nested_then_outer_rollback | savepoint_commit_outer_rollback | prevent_writes | reading_role | held_pool |
|---|---|---|---|---|---|---|---|---|---|
| SQLite 3.54 | 7.2 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 4.0 s |
| SQLite 3.54 | 8.0 | kept | LOST | LOST | LOST, 53.0 ms | LOST | LOST | LOST | LOST, 4.0 s |
| SQLite 3.54 | 8.1 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 4.0 s |
| PostgreSQL 16 | 7.2 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 4.0 s |
| PostgreSQL 16 | 8.0 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 4.0 s |
| PostgreSQL 16 | 8.1 | kept | LOST | LOST | LOST, 60.2 ms | LOST | LOST | LOST | LOST, 4.0 s |
| MySQL 8.4 | 7.2 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 4.0 s |
| MySQL 8.4 | 8.0 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 4.0 s |
| MySQL 8.4 | 8.1 | kept | LOST | LOST | LOST, 53.4 ms | LOST | LOST | LOST | LOST, 4.0 s |
| MySQL 26.10 | 7.2 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 4.0 s |
| MySQL 26.10 | 8.0 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 4.0 s |
| MySQL 26.10 | 8.1 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 4.0 s |

#### rc.1 / async, no request

| Database | Rails | commit | rollback | nested_rollback | nested_then_outer_rollback | savepoint_commit_outer_rollback | prevent_writes | reading_role | held_pool |
|---|---|---|---|---|---|---|---|---|---|
| SQLite 3.54 | 7.2 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 6.0 s |
| SQLite 3.54 | 8.0 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 6.0 s |
| SQLite 3.54 | 8.1 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 6.0 s |
| PostgreSQL 16 | 7.2 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 6.1 s |
| PostgreSQL 16 | 8.0 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 6.0 s |
| PostgreSQL 16 | 8.1 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 6.0 s |
| MySQL 8.4 | 7.2 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 6.0 s |
| MySQL 8.4 | 8.0 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 6.0 s |
| MySQL 8.4 | 8.1 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 6.0 s |
| MySQL 26.10 | 7.2 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 6.0 s |
| MySQL 26.10 | 8.0 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 6.1 s |
| MySQL 26.10 | 8.1 | kept | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 6.0 s |

#### rc.1 / async, in a request

| Database | Rails | commit | rollback | nested_rollback | nested_then_outer_rollback | savepoint_commit_outer_rollback | prevent_writes | reading_role | held_pool |
|---|---|---|---|---|---|---|---|---|---|
| SQLite 3.54 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.6 ms |
| SQLite 3.54 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.2 ms |
| SQLite 3.54 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.2 ms |
| PostgreSQL 16 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.3 ms |
| PostgreSQL 16 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.0 ms |
| PostgreSQL 16 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.1 ms |
| MySQL 8.4 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.5 ms |
| MySQL 8.4 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.2 ms |
| MySQL 8.4 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.2 ms |
| MySQL 26.10 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.5 ms |
| MySQL 26.10 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.2 ms |
| MySQL 26.10 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.1 ms |

#### Option 1 / sync

| Database | Rails | commit | rollback | nested_rollback | nested_then_outer_rollback | savepoint_commit_outer_rollback | prevent_writes | reading_role | held_pool | host_pool_held |
|---|---|---|---|---|---|---|---|---|---|---|
| SQLite 3.54 | 7.2 | LOST | LOST | LOST | LOST | LOST | LOST | LOST | LOST, 223.0 ms | kept, 18.5 ms |
| SQLite 3.54 | 8.0 | LOST, 5.0 s | LOST, 5.0 s | LOST, 5.0 s | LOST, 5.0 s | LOST, 5.0 s | LOST | LOST | LOST, 220.3 ms | kept, 8.1 ms |
| SQLite 3.54 | 8.1 | LOST, 5.0 s | LOST, 5.0 s | LOST, 5.0 s | LOST, 5.0 s | LOST, 5.0 s | LOST | LOST | LOST, 223.7 ms | kept, 48.0 ms |
| PostgreSQL 16 | 7.2 | kept | kept | kept | kept | kept | LOST | LOST | LOST, 231.5 ms | kept, 30.3 ms |
| PostgreSQL 16 | 8.0 | kept | kept | kept | kept, 53.4 ms | kept | LOST | LOST | LOST, 221.7 ms | kept, 63.0 ms |
| PostgreSQL 16 | 8.1 | kept | kept | kept | kept | kept | LOST | LOST | LOST, 220.8 ms | kept, 21.3 ms |
| MySQL 8.4 | 7.2 | kept | kept | kept | kept | kept | LOST | LOST | LOST, 220.0 ms | kept, 19.8 ms |
| MySQL 8.4 | 8.0 | kept | kept | kept | kept, 52.1 ms | kept | LOST | LOST | LOST, 208.1 ms | kept, 24.4 ms |
| MySQL 8.4 | 8.1 | kept | kept | kept | kept, 59.6 ms | kept | LOST | LOST | LOST, 216.7 ms | kept, 25.6 ms |
| MySQL 26.10 | 7.2 | kept | kept | kept | kept | kept | LOST | LOST | LOST, 219.7 ms | kept, 15.2 ms |
| MySQL 26.10 | 8.0 | kept | kept | kept | kept | kept | LOST | LOST | LOST, 217.3 ms | kept, 21.8 ms |
| MySQL 26.10 | 8.1 | kept | kept | kept | kept | kept | LOST | LOST | LOST, 225.7 ms | kept, 12.4 ms |

#### Option 1 / async, no request

| Database | Rails | commit | rollback | nested_rollback | nested_then_outer_rollback | savepoint_commit_outer_rollback | prevent_writes | reading_role | held_pool | host_pool_held |
|---|---|---|---|---|---|---|---|---|---|---|
| SQLite 3.54 | 7.2 | kept | LOST | LOST | LOST | LOST | LOST | LOST | kept, 6.5 ms | kept, 2.1 s |
| SQLite 3.54 | 8.0 | kept | LOST | LOST | LOST | LOST | LOST | LOST | kept, 2.2 ms | kept, 2.1 s |
| SQLite 3.54 | 8.1 | kept | LOST | LOST | LOST | LOST | LOST | LOST | kept, 5.5 ms | kept, 2.0 s |
| PostgreSQL 16 | 7.2 | kept | LOST | LOST | LOST | LOST | LOST | LOST | kept, 10.1 ms | kept, 2.1 s |
| PostgreSQL 16 | 8.0 | kept | LOST | LOST | LOST | LOST | LOST | LOST | kept, 3.5 ms | kept, 2.0 s |
| PostgreSQL 16 | 8.1 | kept | LOST | LOST | LOST | LOST | LOST | LOST | kept, 6.7 ms | kept, 2.1 s |
| MySQL 8.4 | 7.2 | kept | LOST | LOST | LOST | LOST | LOST | LOST | kept, 7.8 ms | kept, 2.1 s |
| MySQL 8.4 | 8.0 | kept | LOST | LOST | LOST | LOST | LOST | LOST | kept, 2.8 ms | kept, 2.1 s |
| MySQL 8.4 | 8.1 | kept | LOST | LOST | LOST | LOST | LOST | LOST | kept, 6.7 ms | kept, 2.0 s |
| MySQL 26.10 | 7.2 | kept | LOST | LOST | LOST | LOST | LOST | LOST | kept, 8.0 ms | kept, 2.1 s |
| MySQL 26.10 | 8.0 | kept | LOST | LOST | LOST | LOST | LOST | LOST | kept, 3.6 ms | kept, 2.1 s |
| MySQL 26.10 | 8.1 | kept | LOST | LOST | LOST | LOST | LOST | LOST | kept, 7.2 ms | kept, 2.0 s |

#### Option 1 / async, in a request

| Database | Rails | commit | rollback | nested_rollback | nested_then_outer_rollback | savepoint_commit_outer_rollback | prevent_writes | reading_role | held_pool | host_pool_held |
|---|---|---|---|---|---|---|---|---|---|---|
| SQLite 3.54 | 7.2 | kept | kept | kept | kept | kept | kept | kept | kept, 1.6 ms | kept, 0.4 ms |
| SQLite 3.54 | 8.0 | kept | kept | kept | kept | kept | kept | kept | kept, 1.3 ms | kept, 0.4 ms |
| SQLite 3.54 | 8.1 | kept | kept | kept | kept | kept | kept | kept | kept, 1.2 ms | kept, 0.5 ms |
| PostgreSQL 16 | 7.2 | kept | kept | kept | kept | kept | kept | kept | kept, 1.3 ms | kept, 0.5 ms |
| PostgreSQL 16 | 8.0 | kept | kept | kept | kept | kept | kept | kept | kept, 1.0 ms | kept, 0.4 ms |
| PostgreSQL 16 | 8.1 | kept | kept | kept | kept | kept | kept | kept | kept, 1.0 ms | kept, 0.6 ms |
| MySQL 8.4 | 7.2 | kept | kept | kept | kept | kept | kept | kept | kept, 1.6 ms | kept, 0.3 ms |
| MySQL 8.4 | 8.0 | kept | kept | kept | kept | kept | kept | kept | kept, 1.2 ms | kept, 0.3 ms |
| MySQL 8.4 | 8.1 | kept | kept | kept | kept | kept | kept | kept | kept, 1.2 ms | kept, 0.4 ms |
| MySQL 26.10 | 7.2 | kept | kept | kept | kept | kept | kept | kept | kept, 1.5 ms | kept, 0.3 ms |
| MySQL 26.10 | 8.0 | kept | kept | kept | kept | kept | kept | kept | kept, 1.1 ms | kept, 0.3 ms |
| MySQL 26.10 | 8.1 | kept | kept | kept | kept | kept | kept | kept | kept, 1.1 ms | kept, 0.3 ms |

#### Option 1 with the role wrapper / sync

| Database | Rails | commit | rollback | nested_rollback | nested_then_outer_rollback | savepoint_commit_outer_rollback | prevent_writes | reading_role | held_pool | host_pool_held |
|---|---|---|---|---|---|---|---|---|---|---|
| SQLite 3.54 | 7.2 | LOST | LOST | LOST | LOST | LOST | kept | kept | LOST, 216.2 ms | kept, 31.6 ms |
| SQLite 3.54 | 8.0 | LOST, 5.0 s | LOST, 5.0 s | LOST, 5.0 s | LOST, 5.0 s | LOST, 5.0 s | kept | kept | LOST, 215.8 ms | kept, 16.8 ms |
| SQLite 3.54 | 8.1 | LOST, 5.0 s | LOST, 5.0 s | LOST, 5.0 s | LOST, 5.0 s | LOST, 5.0 s | kept | kept | LOST, 218.2 ms | kept, 7.7 ms |
| PostgreSQL 16 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 229.1 ms | kept, 31.7 ms |
| PostgreSQL 16 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 228.1 ms | kept, 43.7 ms |
| PostgreSQL 16 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 224.4 ms | kept, 38.6 ms |
| MySQL 8.4 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 221.5 ms | kept, 13.1 ms |
| MySQL 8.4 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 211.9 ms | kept, 19.6 ms |
| MySQL 8.4 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 223.5 ms | kept, 7.4 ms |
| MySQL 26.10 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 220.4 ms | kept, 14.6 ms |
| MySQL 26.10 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 227.5 ms | kept, 38.5 ms |
| MySQL 26.10 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 229.5 ms | kept, 9.3 ms |

#### Option 1 with the role wrapper / async, no request

| Database | Rails | commit | rollback | nested_rollback | nested_then_outer_rollback | savepoint_commit_outer_rollback | prevent_writes | reading_role | held_pool | host_pool_held |
|---|---|---|---|---|---|---|---|---|---|---|
| SQLite 3.54 | 7.2 | kept | LOST | LOST | LOST | LOST | kept | kept | kept, 4.9 ms | kept, 2.0 s |
| SQLite 3.54 | 8.0 | kept | LOST | LOST | LOST | LOST | kept | kept | kept, 1.7 ms | kept, 2.0 s |
| SQLite 3.54 | 8.1 | kept | LOST | LOST | LOST | LOST | kept | kept | kept, 4.4 ms | kept, 2.0 s |
| PostgreSQL 16 | 7.2 | kept | LOST | LOST | LOST | LOST | kept | kept | kept, 5.7 ms | kept, 2.1 s |
| PostgreSQL 16 | 8.0 | kept | LOST | LOST | LOST | LOST | kept | kept | kept, 2.6 ms | kept, 2.0 s |
| PostgreSQL 16 | 8.1 | kept | LOST | LOST | LOST | LOST | kept | kept | kept, 4.6 ms | kept, 2.1 s |
| MySQL 8.4 | 7.2 | kept | LOST | LOST | LOST | LOST | kept | kept | kept, 5.6 ms | kept, 2.0 s |
| MySQL 8.4 | 8.0 | kept | LOST | LOST | LOST | LOST | kept | kept | kept, 2.3 ms | kept, 2.1 s |
| MySQL 8.4 | 8.1 | kept | LOST | LOST | LOST | LOST | kept | kept | kept, 4.6 ms | kept, 2.0 s |
| MySQL 26.10 | 7.2 | kept | LOST | LOST | LOST | LOST | kept | kept | kept, 6.3 ms | kept, 2.1 s |
| MySQL 26.10 | 8.0 | kept | LOST | LOST | LOST | LOST | kept | kept | kept, 3.7 ms | kept, 2.1 s |
| MySQL 26.10 | 8.1 | kept | LOST | LOST | LOST | LOST | kept | kept | kept, 5.1 ms | kept, 2.0 s |

#### Option 1 with the role wrapper / async, in a request

| Database | Rails | commit | rollback | nested_rollback | nested_then_outer_rollback | savepoint_commit_outer_rollback | prevent_writes | reading_role | held_pool | host_pool_held |
|---|---|---|---|---|---|---|---|---|---|---|
| SQLite 3.54 | 7.2 | kept | kept | kept | kept | kept | kept | kept | kept, 1.7 ms | kept, 0.4 ms |
| SQLite 3.54 | 8.0 | kept | kept | kept | kept | kept | kept | kept | kept, 1.2 ms | kept, 0.4 ms |
| SQLite 3.54 | 8.1 | kept | kept | kept | kept | kept | kept | kept | kept, 1.3 ms | kept, 0.4 ms |
| PostgreSQL 16 | 7.2 | kept | kept | kept | kept | kept | kept | kept | kept, 1.3 ms | kept, 0.5 ms |
| PostgreSQL 16 | 8.0 | kept | kept | kept | kept | kept | kept | kept | kept, 1.2 ms | kept, 0.5 ms |
| PostgreSQL 16 | 8.1 | kept | kept | kept | kept | kept | kept | kept | kept, 1.1 ms | kept, 0.8 ms |
| MySQL 8.4 | 7.2 | kept | kept | kept | kept | kept | kept | kept | kept, 1.6 ms | kept, 0.3 ms |
| MySQL 8.4 | 8.0 | kept | kept | kept | kept | kept | kept | kept | kept, 1.3 ms | kept, 0.4 ms |
| MySQL 8.4 | 8.1 | kept | kept | kept | kept | kept | kept | kept | kept, 1.3 ms | kept, 0.4 ms |
| MySQL 26.10 | 7.2 | kept | kept | kept | kept | kept | kept | kept | kept, 1.5 ms | kept, 0.3 ms |
| MySQL 26.10 | 8.0 | kept | kept | kept | kept | kept | kept | kept | kept, 1.1 ms | kept, 0.5 ms |
| MySQL 26.10 | 8.1 | kept | kept | kept | kept | kept | kept | kept | kept, 1.1 ms | kept, 0.4 ms |

#### Option 2 / sync

| Database | Rails | commit | rollback | nested_rollback | nested_then_outer_rollback | savepoint_commit_outer_rollback | prevent_writes | reading_role | held_pool |
|---|---|---|---|---|---|---|---|---|---|
| SQLite 3.54 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 108.0 ms |
| SQLite 3.54 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 110.9 ms |
| SQLite 3.54 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 103.0 ms |
| PostgreSQL 16 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 111.4 ms |
| PostgreSQL 16 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 107.3 ms |
| PostgreSQL 16 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 101.4 ms |
| MySQL 8.4 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 108.0 ms |
| MySQL 8.4 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 108.8 ms |
| MySQL 8.4 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 110.7 ms |
| MySQL 26.10 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 110.6 ms |
| MySQL 26.10 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 108.7 ms |
| MySQL 26.10 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 110.3 ms |

#### Option 2 / async, no request

| Database | Rails | commit | rollback | nested_rollback | nested_then_outer_rollback | savepoint_commit_outer_rollback | prevent_writes | reading_role | held_pool |
|---|---|---|---|---|---|---|---|---|---|
| SQLite 3.54 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 109.2 ms |
| SQLite 3.54 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 112.8 ms |
| SQLite 3.54 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 103.6 ms |
| PostgreSQL 16 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 103.9 ms |
| PostgreSQL 16 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 114.0 ms |
| PostgreSQL 16 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 103.0 ms |
| MySQL 8.4 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 111.5 ms |
| MySQL 8.4 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 109.6 ms |
| MySQL 8.4 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 108.2 ms |
| MySQL 26.10 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 108.0 ms |
| MySQL 26.10 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 112.8 ms |
| MySQL 26.10 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 111.8 ms |

#### Option 2 / async, in a request

| Database | Rails | commit | rollback | nested_rollback | nested_then_outer_rollback | savepoint_commit_outer_rollback | prevent_writes | reading_role | held_pool |
|---|---|---|---|---|---|---|---|---|---|
| SQLite 3.54 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.6 ms |
| SQLite 3.54 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.2 ms |
| SQLite 3.54 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.2 ms |
| PostgreSQL 16 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.4 ms |
| PostgreSQL 16 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.0 ms |
| PostgreSQL 16 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.0 ms |
| MySQL 8.4 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.5 ms |
| MySQL 8.4 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.2 ms |
| MySQL 8.4 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.2 ms |
| MySQL 26.10 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.5 ms |
| MySQL 26.10 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.1 ms |
| MySQL 26.10 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.2 ms |

#### Option 3 / sync

| Database | Rails | commit | rollback | nested_rollback | nested_then_outer_rollback | savepoint_commit_outer_rollback | prevent_writes | reading_role | held_pool |
|---|---|---|---|---|---|---|---|---|---|
| SQLite 3.54 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| SQLite 3.54 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| SQLite 3.54 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| PostgreSQL 16 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| PostgreSQL 16 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| PostgreSQL 16 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| MySQL 8.4 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| MySQL 8.4 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| MySQL 8.4 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| MySQL 26.10 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| MySQL 26.10 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| MySQL 26.10 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |

#### Option 3 / async, no request

| Database | Rails | commit | rollback | nested_rollback | nested_then_outer_rollback | savepoint_commit_outer_rollback | prevent_writes | reading_role | held_pool |
|---|---|---|---|---|---|---|---|---|---|
| SQLite 3.54 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| SQLite 3.54 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| SQLite 3.54 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| PostgreSQL 16 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| PostgreSQL 16 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| PostgreSQL 16 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| MySQL 8.4 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.2 ms |
| MySQL 8.4 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| MySQL 8.4 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| MySQL 26.10 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| MySQL 26.10 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |
| MySQL 26.10 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 0.1 ms |

#### Option 3 / async, in a request

| Database | Rails | commit | rollback | nested_rollback | nested_then_outer_rollback | savepoint_commit_outer_rollback | prevent_writes | reading_role | held_pool |
|---|---|---|---|---|---|---|---|---|---|
| SQLite 3.54 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.4 ms |
| SQLite 3.54 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.4 ms |
| SQLite 3.54 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.2 ms |
| PostgreSQL 16 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.3 ms |
| PostgreSQL 16 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.2 ms |
| PostgreSQL 16 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.1 ms |
| MySQL 8.4 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.5 ms |
| MySQL 8.4 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.2 ms |
| MySQL 8.4 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.2 ms |
| MySQL 26.10 | 7.2 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.4 ms |
| MySQL 26.10 | 8.0 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.2 ms |
| MySQL 26.10 | 8.1 | kept | kept | kept | kept | kept | kept | kept | LOST, 1.1 ms |

## Appendix B: the probe code

Run from `/tmp/red-s1`. `run.sh` picks the bundle and the database; `matrix.sh`, `bench.sh` and `final.sh` ran the batches; `summarize.rb` built Appendix A.

### `run.sh`

```bash
#!/usr/bin/env bash
# usage: run.sh <rails 7.2|8.0|8.1> <db sqlite|pg|mysql84|mysql26> <script> [args...]
set -u
v=$1; db=$2; shift 2
vv=${v/./}
case $db in
  sqlite)  url="sqlite3:/tmp/red-s1/sqlite/probe_${vv}.sqlite3" ;;
  pg)      url="postgres://localhost/red_s1_${vv}" ;;
  mysql84) url="trilogy://root@127.0.0.1:3307/red_s1_${vv}" ;;
  mysql26) url="trilogy://root@127.0.0.1:3306/red_s1_${vv}" ;;
esac
export PROBE_DB=$db PROBE_RAILS=$v RAILS_ENV=test RED_TEST_SCHEMA=migrations
url=${PROBE_URL:-$url}
export DATABASE_URL="${url}?pool=${PROBE_POOL:-5}&checkout_timeout=${PROBE_CHECKOUT:-2}&timeout=5000"
export BUNDLE_GEMFILE=/tmp/red-s1/gemfiles/$v/Gemfile RAILS_VERSION=$v
cd /tmp/red-s1/probe
exec mise exec ruby@3.4.5 -- bundle exec ruby "$@"
```

### `matrix.sh`

```bash
#!/usr/bin/env bash
# One stream per database, in parallel; inside a stream, runs are sequential.
stream() {
  db=$1
  for v in 7.2 8.0 8.1; do for mode in ${MODES:-sync async async_req}; do for o in ${OPTS:-baseline o1 o1w o2 o3}; do
    f=/tmp/red-s1/out/runs/${db}_${v}_${mode}_${o}
    OPTION=$o MODE=$mode PROBE_LOG=$f.log timeout 240 /tmp/red-s1/run.sh $v $db cases.rb > $f.jsonl 2> $f.err
    echo "$db $v $mode $o exit=$?" >> /tmp/red-s1/out/runs/progress.txt
  done; done; done
}
: > /tmp/red-s1/out/runs/progress.txt
for db in ${DBS:-sqlite pg mysql84 mysql26}; do stream $db & done
wait
echo ALL DONE >> /tmp/red-s1/out/runs/progress.txt
```

### `bench.sh`

```bash
#!/usr/bin/env bash
# Sequential on purpose: timings need a quiet machine.
cd /tmp/red-s1/probe
for spec in "8.1 sqlite" "8.1 pg" "8.1 mysql84" "8.1 mysql26" "7.2 sqlite" "7.2 pg" "7.2 mysql84" "8.0 sqlite" "8.0 pg" "8.0 mysql84"; do
  set -- $spec
  for mode in sync async; do for o in baseline o1w o2 o3; do
    f=/tmp/red-s1/out/bench/$2_$1_${mode}_$o
    OPTION=$o MODE=$mode N=300 PROBE_LOG=$f.log timeout 300 /tmp/red-s1/run.sh $1 $2 bench.rb > $f.json 2> $f.err
    echo "$2 $1 $mode $o exit=$?" >> /tmp/red-s1/out/bench/progress.txt
  done; done
done
for db in sqlite pg mysql84 mysql26; do for o in baseline o1w o2 o3; do
  f=/tmp/red-s1/out/bench/conns_${db}_$o
  OPTION=$o THREADS=5 PROBE_LOG=$f.log timeout 120 /tmp/red-s1/run.sh 8.1 $db conns.rb > $f.json 2> $f.err
  echo "conns $db $o exit=$?" >> /tmp/red-s1/out/bench/progress.txt
done; done
echo ALL DONE >> /tmp/red-s1/out/bench/progress.txt
```

### `final.sh`

```bash
#!/usr/bin/env bash
cd /tmp/red-s1/probe
MODES=async_req /tmp/red-s1/matrix.sh; cp /tmp/red-s1/out/runs/progress.txt /tmp/red-s1/out/progress_asyncreq.txt
OPTS=o2 MODES="sync async" /tmp/red-s1/matrix.sh; cp /tmp/red-s1/out/runs/progress.txt /tmp/red-s1/out/progress_o2.txt
for v in 7.2 8.0 8.1; do for mode in sync async; do f=/tmp/red-s1/out/hold2/sqlite_${v}_${mode}_o2; OPTION=o2 MODE=$mode CASES=rollback_hold,commit_hold PROBE_LOG=$f.log /tmp/red-s1/run.sh $v sqlite cases.rb > $f.jsonl 2>$f.err; done; done
for spec in "8.1 sqlite" "8.1 pg" "8.1 mysql84" "8.1 mysql26" "7.2 sqlite" "7.2 pg" "7.2 mysql84" "8.0 sqlite" "8.0 pg" "8.0 mysql84"; do set -- $spec
  for mode in sync async; do f=/tmp/red-s1/out/bench/$2_$1_${mode}_o2; OPTION=o2 MODE=$mode N=300 PROBE_LOG=$f.log timeout 300 /tmp/red-s1/run.sh $1 $2 bench.rb > $f.json 2> $f.err; done; done
mkdir -p /tmp/red-s1/out/sepdb
for v in 7.2 8.1; do vv=${v/./}; for db in sqlite pg; do
  if [ $db = pg ]; then red="postgres://localhost/red_s1_err_$vv"; else red="sqlite3:/tmp/red-s1/sqlite/errors_$vv.sqlite3"; fi
  for mode in sync async; do for o in baseline o2 o3; do f=/tmp/red-s1/out/sepdb/${db}_${v}_${mode}_$o
    OPTION=$o MODE=$mode RED_DB_URL="$red" PROBE_LOG=$f.log timeout 240 /tmp/red-s1/run.sh $v $db cases.rb > $f.jsonl 2> $f.err
    echo "sepdb $db $v $mode $o exit=$?" >> /tmp/red-s1/out/sepdb/progress.txt
  done; done; done; done
echo FINAL DONE
```

### `boot.rb`

```ruby
# Boots spec/dummy against the throwaway DATABASE_URL, migrates RED, loads
# Solid Queue's schema into the same database, and adds a host table.
$stdout.sync = true
require "json"
REPO = ENV.fetch("RED_REPO") # the repository checkout (an absolute path in the run)
require "rails/all"
require "solid_queue"
require "#{REPO}/spec/dummy/config/environment"
require "#{REPO}/spec/support/test_schema"

PROBE_LOG = ENV.fetch("PROBE_LOG", "/tmp/red-s1/out/last.log")
Rails.logger = ActiveSupport::Logger.new(PROBE_LOG)
Rails.logger.level = :info
ActiveRecord::Base.logger = nil

RailsErrorDashboard::TestSchema.build!
conn = ActiveRecord::Base.connection
unless conn.table_exists?("solid_queue_jobs")
  ActiveRecord::Schema.verbose = false
  load File.join(Gem.loaded_specs["solid_queue"].full_gem_path,
                 "lib/generators/solid_queue/install/templates/db/queue_schema.rb")
end
conn.create_table(:probe_widgets, force: true) { |t| t.string :name } unless conn.table_exists?(:probe_widgets)
class ProbeWidget < ActiveRecord::Base; end

cfg = RailsErrorDashboard.configuration
cfg.async_logging = false
cfg.log_level = :error
cfg.enable_internal_logging = true
cfg.enable_storm_protection = false

def red_log_lines
  File.exist?(PROBE_LOG) ? File.readlines(PROBE_LOG).grep(/RailsErrorDashboard|Failed to/).map(&:strip) : []
end

def probe_versions
  { rails: Rails.version, adapter: ActiveRecord::Base.connection_db_config.adapter,
    server: (ActiveRecord::Base.connection.select_value(ActiveRecord::Base.connection.adapter_name =~ /sqlite/i ? "select sqlite_version()" : "select version()") rescue "?") }
end
```

### `options.rb`

```ruby
# Spike S1: the three mechanisms from design.md, applied to rc.1's code in memory.
# OPTION = baseline | o1 | o1w | o2 | o3
#   o1  : RED's own pool via ErrorLogsRecord.connects_to, nothing else
#   o1w : o1, plus ErrorLogsRecord.connected_to(role: :writing, prevent_writes: false) around a capture
#   o2  : shared connection; inside an open host transaction, defer the capture to its
#         after_commit/after_rollback; writes allowed via Base.connected_to; bounded checkout
#   o3  : a bounded in-process worker thread; the caller builds the async payload
#         (LogError.call_async) and the worker writes it (sync) or enqueues it (async)
module S1
  OPTION = ENV.fetch("OPTION", "baseline")
  CAPTURE_TIMEOUT = Float(ENV.fetch("CAPTURE_TIMEOUT", "0.1"))
  RED_POOL_SIZE = Integer(ENV.fetch("RED_POOL_SIZE", "2"))

  # Count every checkout and the time spent waiting in it, per pool.
  module CheckoutCounter
    def checkout(*args)
      S1.checkouts[S1.pool_key(self)] += 1
      t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      super
    ensure
      S1.checkout_wait[S1.pool_key(self)] += Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
    end
  end
  ActiveRecord::ConnectionAdapters::ConnectionPool.prepend(CheckoutCounter)

  class << self
    def checkouts = (@checkouts ||= Hash.new(0))
    def checkout_wait = (@checkout_wait ||= Hash.new(0.0))
    def reset_counters! = (@checkouts = nil; @checkout_wait = nil)

    def red_pool = RailsErrorDashboard::ErrorLogsRecord.connection_pool

    def pool_key(pool)
      pc = pool.pool_config
      owner = pc.respond_to?(:connection_descriptor) ? pc.connection_descriptor.name : pc.connection_class.name
      "#{owner.split("::").last}/#{pool.role}"
    rescue StandardError
      "?"
    end

    # Leases a connection for this thread, waiting at most `timeout`. Uses the
    # pool's private lease (7.2-8.1): there is no public checkout-with-timeout lease.
    def with_bounded_connection(pool, timeout)
      return yield if pool.active_connection?

      conn = pool.checkout(timeout)
      pool.send(:connection_lease).connection = conn
      begin
        yield
      ensure
        pool.release_connection
      end
    end
  end

  # ---------------------------------------------------------------- option 1
  def self.install_o1(wrap:)
    base = ActiveRecord::Base.connection_db_config.configuration_hash
    red = base.merge(pool: RED_POOL_SIZE, max_connections: RED_POOL_SIZE, checkout_timeout: CAPTURE_TIMEOUT)
    red.delete(:min_connections)
    RailsErrorDashboard::ErrorLogsRecord.connects_to(database: { writing: red, reading: red })
    return unless wrap

    RailsErrorDashboard::Commands::LogError.prepend(Module.new do
      def call
        RailsErrorDashboard::ErrorLogsRecord.connected_to(role: :writing, prevent_writes: false) { super }
      rescue ActiveRecord::ConnectionTimeoutError, ActiveRecord::ConnectionNotEstablished => e
        RailsErrorDashboard::Logger.error("[RailsErrorDashboard] S1 o1w gave up: #{e.class}")
        nil
      end
    end)
  end

  # ---------------------------------------------------------------- option 2
  # Allows writes and leases, with a bounded wait, the pools a step writes
  # through. The sync write uses RED's pool (its rows) and the host's (the
  # notification jobs it enqueues); the async enqueue uses only the host's, where
  # a database-backed queue such as Solid Queue lives. With a shared database the
  # two are one pool.
  def self.red_and_host_pools = [ RailsErrorDashboard::ErrorLogsRecord.connection_pool, ActiveRecord::Base.connection_pool ].uniq
  def self.host_pool = [ ActiveRecord::Base.connection_pool ]

  def self.writes_allowed(pools = red_and_host_pools, &blk)
    ActiveRecord::Base.connected_to(role: :writing, prevent_writes: false) do
      pools.reverse.inject(blk) { |inner, pool| -> { with_bounded_connection(pool, CAPTURE_TIMEOUT, &inner) } }.call
    end
  rescue ActiveRecord::ConnectionTimeoutError => e
    RailsErrorDashboard::Logger.error("[RailsErrorDashboard] S1 o2 gave up: #{e.class}")
    nil
  end

  # The innermost open host transaction, or nil. Public API (Rails 7.2+), and it
  # checks out no connection. While a savepoint's after_rollback runs it already
  # returns the enclosing transaction (txn_api.rb), so that one is waited for too.
  def self.open_host_transaction
    t = ActiveRecord::Base.current_transaction
    t.open? ? t : nil
  end

  # Writes now, or once every enclosing host transaction has ended (committed
  # or rolled back), re-checking after each one ends.
  def self.defer_or_write(&write)
    txn = open_host_transaction
    return write.call unless txn

    done = false
    run = lambda do
      next if done
      done = true
      deferred << :ran
      defer_or_write(&write)
    end
    txn.after_commit(&run)
    txn.after_rollback(&run)
    deferred << :deferred
    nil
  end

  # Three points: the entry waits for the host's transaction; the sync write and
  # the async enqueue each get writes allowed and a bounded lease. The enqueue
  # may run after the response (rack.response_finished), so no lease is taken
  # on the request thread for work that happens later.
  def self.install_o2
    le = RailsErrorDashboard::Commands::LogError
    le.singleton_class.prepend(Module.new do
      def call(exception, context = {})
        S1.defer_or_write { super(exception, context) }
      end

      def enqueue_async(exception, exception_data, context)
        S1.writes_allowed(S1.host_pool) { super }
      end
    end)
    le.prepend(Module.new do
      def call
        S1.writes_allowed { super }
      end
    end)
  end

  def self.deferred = (@deferred ||= [])

  # ---------------------------------------------------------------- option 3
  module Worker
    MAX = 100
    @queue = Thread::Queue.new
    @mutex = Mutex.new
    @busy = 0
    @dropped = 0

    class << self
      attr_reader :dropped

      def push(job)
        ensure_thread
        if @queue.size >= MAX
          @dropped += 1
          return false
        end
        @mutex.synchronize { @busy += 1 }
        @queue << job
        true
      end

      def ensure_thread
        return if @pid == Process.pid && @thread&.alive?

        @mutex.synchronize do
          return if @pid == Process.pid && @thread&.alive?

          @pid = Process.pid
          @thread = Thread.new do
            Thread.current.name = "red-capture-writer"
            loop do
              job = @queue.pop
              begin
                S1::Worker.run_guarded(job)
              rescue Exception => e # rubocop:disable Lint/RescueException
                RailsErrorDashboard::Logger.error("[RailsErrorDashboard] S1 o3 worker: #{e.class}: #{e.message}")
              ensure
                @mutex.synchronize { @busy -= 1 }
              end
            end
          end
        end
      end

      # No executor.wrap: it reports a raised error to Rails.error, which RED
      # captures, which queues another write -- a loop while the pool is held.
      # The recursion guard is ErrorReporter's own (error_reporter.rb:31).
      def run_guarded(job)
        Thread.current[:rails_error_dashboard_logging] = true
        job.call
      ensure
        Thread.current[:rails_error_dashboard_logging] = nil
        ActiveRecord::Base.connection_handler.clear_active_connections!(:all)
      end

      def drain(timeout = 15)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        sleep 0.005 while @mutex.synchronize { @busy } > 0 && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      end
    end
  end

  def self.install_o3
    lec = RailsErrorDashboard::Commands::LogError
    # Sync mode goes through call_async's payload builder too, so every
    # thread-local is read on the caller's thread.
    lec.singleton_class.prepend(Module.new do
      # S1.o3_sync_mode is set once from MODE by cases.rb: a deferred enqueue
      # (rack.response_finished) runs after this method has returned.
      def call(exception, context = {})
        cfg = RailsErrorDashboard.configuration
        was = cfg.async_logging
        cfg.async_logging = true
        super
      ensure
        cfg.async_logging = was
      end

      def enqueue_async(exception, exception_data, context)
        if S1.o3_sync_mode
          Worker.push(-> {
            S1.with_bounded_connection(RailsErrorDashboard::ErrorLogsRecord.connection_pool, S1::CAPTURE_TIMEOUT) do
              RailsErrorDashboard::AsyncErrorLoggingJob.new.perform(exception_data, context)
            end
          })
        else
          Worker.push(-> {
            S1.with_bounded_connection(ActiveRecord::Base.connection_pool, S1::CAPTURE_TIMEOUT) { super(exception, exception_data, context) }
          })
        end
        nil
      end
    end)
  end

  class << self
    attr_accessor :o3_sync_mode
  end

  def self.install!
    case OPTION
    when "baseline" then nil
    when "o1" then install_o1(wrap: false)
    when "o1w" then install_o1(wrap: true)
    when "o2" then install_o2
    when "o3" then install_o3
    else raise "unknown OPTION #{OPTION}"
    end
  end

  def self.drain_worker! = (Worker.drain if OPTION == "o3")
end
```

### `cases.rb`

```ruby
# Spike S1 case runner. One process per (Rails, database, OPTION, MODE).
# MODE = sync | async | async_req
#   async     : async_logging on, Solid Queue on the same database, no request env
#               (a job, a console, a rake task, or a server without rack.response_finished)
#   async_req : async_logging on, inside a request whose server offers rack.response_finished
#               (the callbacks run after the case's block, as Puma runs them after the response)
# Prints one JSON line per case.
require_relative "boot"
require_relative "options"

MODE = ENV.fetch("MODE", "sync")
CASES = ENV["CASES"]&.split(",")
DB = ENV.fetch("PROBE_DB")
HOLD_SECONDS = 3.0

cfg = RailsErrorDashboard.configuration
cfg.async_logging = MODE != "sync"
S1.o3_sync_mode = MODE == "sync"
ActiveJob::Base.queue_adapter = :solid_queue if MODE != "sync"

# A reading role on ActiveRecord::Base, pointing at the same database but
# read-only at the database level where the adapter allows it, as a replica is.
primary = ActiveRecord::Base.connection_db_config
replica = primary.configuration_hash.merge(replica: true)
case DB
when "pg" then replica[:variables] = { default_transaction_read_only: "on" }
when /mysql/ then replica[:variables] = { transaction_read_only: 1 }
end
ActiveRecord::Base.configurations = ActiveRecord::DatabaseConfigurations.new(
  ActiveRecord::Base.configurations.configurations +
  [ ActiveRecord::DatabaseConfigurations::HashConfig.new(primary.env_name, "primary_replica", replica) ]
)
ActiveRecord::Base.connects_to(database: { writing: primary.name.to_sym, reading: :primary_replica })

# RED_DB_URL: RED's tables in their own database, as use_separate_database
# does (engine.rb:29-31: connects_to with writing and reading on one entry).
if (red_url = ENV["RED_DB_URL"])
  red_cfg = ActiveRecord::DatabaseConfigurations::UrlConfig.new(
    primary.env_name, "error_dashboard", red_url,
    { migrations_paths: RailsErrorDashboard::TestSchema::GEM_MIGRATIONS }
  )
  ActiveRecord::Base.configurations = ActiveRecord::DatabaseConfigurations.new(
    ActiveRecord::Base.configurations.configurations + [ red_cfg ]
  )
  # The error database is migrated beforehand by booting with it as the main
  # database (run.sh with PROBE_URL), as a host runs db:migrate:error_dashboard.
  RailsErrorDashboard::ErrorLogsRecord.connects_to(database: { writing: :error_dashboard, reading: :error_dashboard })
  ActiveRecord::Base.descendants.each(&:reset_column_information)
end

S1.install!

def mono = Process.clock_gettime(Process::CLOCK_MONOTONIC)
LE = RailsErrorDashboard::ErrorLog
OCC = RailsErrorDashboard::ErrorOccurrence

def recorded_total
  ActiveRecord::Base.connected_to(role: :writing) do
    RailsErrorDashboard::ErrorLogsRecord.connected_to(role: :writing) { [ LE.sum(:occurrence_count).to_i, OCC.count ] }
  rescue NotImplementedError
    [ LE.sum(:occurrence_count).to_i, OCC.count ]
  end
end

def queued_capture_jobs
  SolidQueue::Job.where(class_name: "RailsErrorDashboard::AsyncErrorLoggingJob", finished_at: nil).to_a
end

# Runs queued capture jobs inline, like a worker would.
def drain_queue!
  return 0 if MODE == "sync"

  jobs = queued_capture_jobs
  jobs.each do |j|
    ActiveJob::Base.execute(j.arguments)
    j.update_columns(finished_at: Time.current)
  end
  jobs.size
end

def report(tag, klass = RuntimeError)
  t = mono
  Rails.error.report(klass.new("S1 probe #{tag}"), handled: true, severity: :error)
  ((mono - t) * 1000).round(2)
end

# Wraps a case in a fake request env, then runs its rack.response_finished
# callbacks afterwards, outside the case's transaction and role.
def in_request
  return yield unless MODE == "async_req"

  callbacks = []
  Thread.current[:rails_error_dashboard_request_env] = { "rack.response_finished" => callbacks }
  begin
    result = yield
  ensure
    Thread.current[:rails_error_dashboard_request_env] = nil
  end
  t = mono
  callbacks.each { |cb| cb.call({}, 500, {}, nil) }
  Thread.current[:s1_after_response_ms] = ((mono - t) * 1000).round(2)
  result
end

def holder_threads(pool, n)
  ready = Queue.new
  release = Queue.new
  threads = n.times.map do
    Thread.new do
      c = pool.checkout
      ready << true
      release.pop
      pool.checkin(c)
    end
  end
  n.times { ready.pop }
  S1.reset_counters!
  [ threads, release ]
end

CASE_DEFS = {
  "plain" => -> { in_request { report("plain") } },
  "commit" => lambda {
    in_request { ActiveRecord::Base.transaction { ProbeWidget.create!(name: "c"); report("commit") } }
  },
  "rollback" => lambda {
    in_request do
      ActiveRecord::Base.transaction do
        ProbeWidget.create!(name: "r")
        ms = report("rollback")
        raise ActiveRecord::Rollback
      ensure
        Thread.current[:s1_ms] = ms
      end
    end
    Thread.current[:s1_ms]
  },
  "nested_rollback" => lambda {
    in_request do
      ActiveRecord::Base.transaction do
        ProbeWidget.create!(name: "n")
        ActiveRecord::Base.transaction(requires_new: true) do
          Thread.current[:s1_ms] = report("nested")
          raise ActiveRecord::Rollback
        end
      end
    end
    Thread.current[:s1_ms]
  },
  "prevent_writes" => -> { in_request { ActiveRecord::Base.while_preventing_writes { report("prevent") } } },
  "reading_role" => lambda {
    in_request { ActiveRecord::Base.connected_to(role: :reading, prevent_writes: true) { report("reading") } }
  },
  # Every connection of the pool RED writes through is held by other threads,
  # and this thread has none. The reported error is the host's own pool timeout.
  "held_pool" => lambda {
    ActiveRecord::Base.connection_handler.clear_active_connections!(:all)
    pool = S1.red_pool
    threads, release = holder_threads(pool, pool.size)
    ms = in_request { report("held", ActiveRecord::ConnectionTimeoutError) }
    Thread.new { sleep HOLD_SECONDS; pool.size.times { release << true } }
    threads.each(&:join)
    ms
  },
  # Option 1 only: the HOST's pool is held, RED's own pool is free.
  "host_pool_held" => lambda {
    ActiveRecord::Base.connection_handler.clear_active_connections!(:all)
    pool = ActiveRecord::Base.connection_pool
    threads, release = holder_threads(pool, pool.size)
    ms = in_request { report("hostheld", ActiveRecord::ConnectionTimeoutError) }
    Thread.new { sleep HOLD_SECONDS; pool.size.times { release << true } }
    threads.each(&:join)
    ms
  },
  # A savepoint rolls back with the report in it, then the outer transaction
  # rolls back too: a write made when the savepoint ended is lost with the outer.
  "nested_then_outer_rollback" => lambda {
    in_request do
      ActiveRecord::Base.transaction do
        ProbeWidget.create!(name: "no")
        ActiveRecord::Base.transaction(requires_new: true) do
          Thread.current[:s1_ms] = report("nestedouter")
          raise ActiveRecord::Rollback
        end
        raise ActiveRecord::Rollback
      end
    end
    Thread.current[:s1_ms]
  },
  # The savepoint commits, the outer transaction rolls back.
  "savepoint_commit_outer_rollback" => lambda {
    in_request do
      ActiveRecord::Base.transaction do
        ProbeWidget.create!(name: "so")
        ActiveRecord::Base.transaction(requires_new: true) { Thread.current[:s1_ms] = report("spcommit") }
        raise ActiveRecord::Rollback
      end
    end
    Thread.current[:s1_ms]
  },
  # Opt-in (CASES=...): the host keeps its write transaction, and on SQLite its
  # write lock, open for LOCK_HOLD seconds after the report. Shows whether a
  # second connection's write (option 3's worker) stalls the host's thread.
  "rollback_hold" => lambda {
    ActiveRecord::Base.transaction do
      ProbeWidget.create!(name: "h")
      Thread.current[:s1_ms] = report("rollbackhold")
      sleep LOCK_HOLD
      raise ActiveRecord::Rollback
    end
    Thread.current[:s1_ms]
  },
  "commit_hold" => lambda {
    ActiveRecord::Base.transaction do
      ProbeWidget.create!(name: "h")
      Thread.current[:s1_ms] = report("commithold")
      sleep LOCK_HOLD
    end
    Thread.current[:s1_ms]
  }
}
OPT_IN = %w[rollback_hold commit_hold].freeze
LOCK_HOLD = 0.5

def log_offset = File.exist?(PROBE_LOG) ? File.size(PROBE_LOG) : 0

def new_log_lines(from)
  return [] unless File.exist?(PROBE_LOG)

  File.open(PROBE_LOG) { |f| f.seek(from); f.read }.lines
      .grep(/RailsErrorDashboard|Failed to|S1 o/).map { |l| l.strip.sub(/^.*?\] /, "")[0, 220] }.uniq.first(4)
end

# Jobs left unfinished by an earlier process (bench.rb does not drain) must not
# be counted as this run's captures.
SolidQueue::Job.where(class_name: "RailsErrorDashboard::AsyncErrorLoggingJob", finished_at: nil).update_all(finished_at: Time.current)

names = CASES || (CASE_DEFS.keys - OPT_IN)
names -= [ "host_pool_held" ] unless S1::OPTION.start_with?("o1") || CASES
puts({ meta: probe_versions.merge(option: S1::OPTION, mode: MODE,
  eatc: (ActiveJob::Base.enqueue_after_transaction_commit rescue "n/a"),
  pool: ActiveRecord::Base.connection_pool.size, red_pool: S1.red_pool.size,
  checkout_timeout: ActiveRecord::Base.connection_pool.checkout_timeout) }.to_json)

names.each do |name|
  before = recorded_total
  widgets_before = ProbeWidget.count
  lo = log_offset
  S1.reset_counters!
  S1.deferred.clear
  queued_before = MODE == "sync" ? 0 : queued_capture_jobs.size
  t = mono
  caller_ms = begin
    CASE_DEFS.fetch(name).call
  rescue Exception => e # rubocop:disable Lint/RescueException
    "RAISED #{e.class}: #{e.message[0, 120]}"
  end
  block_ms = ((mono - t) * 1000).round(1)
  S1.drain_worker!
  enqueued = MODE == "sync" ? nil : queued_capture_jobs.size - queued_before
  drained = drain_queue!
  S1.drain_worker!
  after = recorded_total
  puts({ case: name, stored: after[0] - before[0], occurrences: after[1] - before[1],
         enqueued: enqueued, drained: drained, caller_ms: caller_ms, block_ms: block_ms,
         widgets: ProbeWidget.count - widgets_before,
         checkouts: S1.checkouts.dup, wait_s: S1.checkout_wait.transform_values { _1.round(3) },
         after_response_ms: Thread.current[:s1_after_response_ms], deferred: S1.deferred.dup, log: new_log_lines(lo) }.to_json)
  Thread.current[:s1_after_response_ms] = nil
end
```

### `bench.rb`

```ruby
# Spike S1: caller-thread capture time per option. Run alone (no other probe
# running), sync and async. Reports median and p95 in ms of the time the
# reporting thread spends in Rails.error.report.
#   repeat : the same error N times (the increment path, what a burst does)
#   fresh  : a new group each time
#   in_txn : the same error inside an open transaction (caller time, then the
#            time the transaction's end takes, which is where option 2's write lands)
require_relative "boot"
require_relative "options"

MODE = ENV.fetch("MODE", "sync")
N = Integer(ENV.fetch("N", "300"))
RailsErrorDashboard.configuration.async_logging = MODE != "sync"
S1.o3_sync_mode = MODE == "sync"
ActiveJob::Base.queue_adapter = :solid_queue if MODE != "sync"
S1.install!

def mono = Process.clock_gettime(Process::CLOCK_MONOTONIC)

def stats(xs)
  s = xs.sort
  { median: s[s.size / 2].round(3), p95: s[(s.size * 0.95).floor].round(3) }
end

def time_report(msg)
  t = mono
  Rails.error.report(RuntimeError.new(msg), handled: true, severity: :error)
  (mono - t) * 1000
end

# warm up: first capture creates the application row, caches columns
5.times { time_report("S1 bench warmup") }
S1.drain_worker!

out = { meta: probe_versions.merge(option: S1::OPTION, mode: MODE, n: N) }
out[:repeat] = stats(N.times.map { time_report("S1 bench repeat") })
S1.drain_worker!
salt = SecureRandom.alphanumeric(6).tr("0-9", "a-j")
out[:fresh] = stats((N / 3).times.map { |i| time_report("S1 bench fresh #{salt} #{('a'.ord + i % 26).chr * (1 + i / 26)}") })
S1.drain_worker!

callers = []
ends = []
(N / 3).times do
  ActiveRecord::Base.transaction do
    ProbeWidget.create!(name: "b")
    callers << time_report("S1 bench in txn")
    Thread.current[:t_end] = mono
  end
  ends << (mono - Thread.current[:t_end]) * 1000
end
S1.drain_worker!
out[:in_txn_caller] = stats(callers)
out[:in_txn_end] = stats(ends)
puts out.to_json
```

### `conns.rb`

```ruby
# Spike S1: database connections one process holds, per option.
# idle : after boot and one capture on the main thread
# peak : while THREADS threads each capture at once (as Puma threads would)
# Server-side counts come from the database itself (psql / mysql CLI), so they
# include every connection the process opened, whatever pool it belongs to.
require_relative "boot"
require_relative "options"

THREADS = Integer(ENV.fetch("THREADS", "5"))
DB = ENV.fetch("PROBE_DB")
RailsErrorDashboard.configuration.async_logging = false
S1.o3_sync_mode = true
S1.install!

DBNAME = ActiveRecord::Base.connection_db_config.database

def server_count
  case DB
  when "pg"
    `psql -d postgres -Atc "select count(*) from pg_stat_activity where datname = '#{DBNAME}'"`.to_i
  when "mysql84", "mysql26"
    port = DB == "mysql84" ? 3307 : 3306
    `mysql -h127.0.0.1 -P#{port} -uroot -N -e "select count(*) from information_schema.processlist where db = '#{DBNAME}'" 2>/dev/null`.to_i
  end
end

def in_process
  ActiveRecord::Base.connection_handler.connection_pool_list(:all).sum { |p| p.connections.size }
rescue ArgumentError
  ActiveRecord::Base.connection_handler.connection_pool_list.sum { |p| p.connections.size }
end

ActiveRecord::Base.connection_handler.clear_all_connections!(:all) rescue ActiveRecord::Base.connection_handler.clear_all_connections!
before = { in_process: in_process, server: server_count }
Rails.error.report(RuntimeError.new("S1 conns warm"), handled: true, severity: :error)
S1.drain_worker!
idle = { in_process: in_process, server: server_count }

peak = { in_process: 0, server: 0 }
go = Queue.new
threads = THREADS.times.map do |i|
  Thread.new do
    go.pop
    ActiveRecord::Base.connection_pool.with_connection do
      ProbeWidget.count # the request thread already holds a host connection, as in a request
      Rails.error.report(RuntimeError.new("S1 conns #{i}"), handled: true, severity: :error)
      sleep 0.3
    end
  end
end
THREADS.times { go << true }
sleep 0.15
peak = { in_process: in_process, server: server_count }
threads.each(&:join)
S1.drain_worker!

puts({ meta: probe_versions.merge(option: S1::OPTION, threads: THREADS),
       before: before, after_one_capture: idle, during_concurrent: peak }.to_json)
```

### `guard_cost.rb`

```ruby
# Option 2's per-capture overhead without any capture work: the transaction
# check, then writes allowed and the bounded lease around an empty block.
# The thread already holds a connection, as a request thread does.
require_relative "boot"
require_relative "options"
def mono = Process.clock_gettime(Process::CLOCK_MONOTONIC)
N = 20_000
ActiveRecord::Base.connection_pool.lease_connection rescue ActiveRecord::Base.connection
def per_call_us
  3.times.map {
    t = mono
    N.times { yield }
    (mono - t) * 1_000_000 / N
  }.min.round(2)
end
out = { rails: Rails.version }
out[:empty_block_us] = per_call_us { nil }
out[:txn_check_us] = per_call_us { S1.open_host_transaction }
out[:defer_or_write_no_txn_us] = per_call_us { S1.defer_or_write { nil } }
out[:writes_allowed_us] = per_call_us { S1.writes_allowed { nil } }
out[:entry_plus_write_guard_us] = per_call_us { S1.defer_or_write { S1.writes_allowed { nil } } }
puts out.to_json
```

### `txn_api.rb`

```ruby
# Which API sees the enclosing transaction while a savepoint's after_rollback runs?
require_relative "boot"
out = {}
ActiveRecord::Base.transaction do
  ProbeWidget.create!(name: "t")
  ActiveRecord::Base.transaction(requires_new: true) do
    ActiveRecord::Base.current_transaction.after_rollback do
      t = ActiveRecord::Base.current_transaction
      conn = ActiveRecord::Base.connection_pool.active_connection
      out[:public_current_transaction_open] = t.open?
      out[:public_same_object_as_outer] = t.equal?(Thread.current[:outer])
      out[:connection_transaction_open] = conn.transaction_open?
      out[:internal_current_class] = conn.current_transaction.class.name
    end
    raise ActiveRecord::Rollback
  end
  raise ActiveRecord::Rollback
ensure
  nil
end
puts out.merge(rails: Rails.version).to_json
```

### `smoke.rb`

```ruby
require_relative "boot"
puts probe_versions.to_json
n0 = RailsErrorDashboard::ErrorLog.count
Rails.error.report(RuntimeError.new("s1 smoke capture"), handled: true, severity: :error)
puts({ stored: RailsErrorDashboard::ErrorLog.count - n0, sq_tables: ActiveRecord::Base.connection.table_exists?("solid_queue_jobs"),
       subscriber: RailsErrorDashboard.configuration.enable_error_subscriber, log: red_log_lines.last(3) }.to_json)
```

### `summarize.rb`

```ruby
# Reads out/runs/*.jsonl and prints markdown tables: one per (option, mode),
# rows = database x Rails, cells = was the capture kept, plus the caller's time
# where it matters. Plain Ruby, no bundle.
require "json"

DIR = "/tmp/red-s1/out/runs"
DBS = %w[sqlite pg mysql84 mysql26]
DBN = { "sqlite" => "SQLite 3.54", "pg" => "PostgreSQL 16", "mysql84" => "MySQL 8.4", "mysql26" => "MySQL 26.10" }
RAILS = %w[7.2 8.0 8.1]
MODES = %w[sync async async_req]
OPTS = %w[baseline o1 o1w o2 o3]
CASES = %w[commit rollback nested_rollback nested_then_outer_rollback savepoint_commit_outer_rollback prevent_writes reading_role held_pool host_pool_held]

def load(db, v, mode, o)
  f = "#{DIR}/#{db}_#{v}_#{mode}_#{o}.jsonl"
  return nil unless File.exist?(f)

  rows = File.readlines(f).filter_map { |l| JSON.parse(l) rescue nil }
  rows.to_h { |r| [ r["case"] || "meta", r ] }
end

def cell(r, name)
  return "n/a" unless r
  c = r[name]
  return "-" unless c
  return "RAISED" if c["caller_ms"].is_a?(String)

  kept = c["stored"].to_i >= 1 ? "kept" : "LOST"
  ms = c["caller_ms"].to_f
  t = ms >= 1000 ? format("%.1f s", ms / 1000) : format("%.1f ms", ms)
  slow = ms >= 50
  name.include?("held") || slow ? "#{kept}, #{t}" : kept
end

only = ARGV[0]
OPTS.each do |o|
  next if only && o != only
  MODES.each do |mode|
    puts "\n#### #{o} / #{mode}\n\n"
    cols = CASES.dup
    cols.delete("host_pool_held") unless o.start_with?("o1")
    puts "| Database | Rails | #{cols.join(' | ')} |"
    puts "|---|---|#{cols.map { '---' }.join('|')}|"
    DBS.each do |db|
      RAILS.each do |v|
        r = load(db, v, mode, o)
        puts "| #{DBN[db]} | #{v} | #{cols.map { cell(r, _1) }.join(' | ')} |"
      end
    end
  end
end
```
