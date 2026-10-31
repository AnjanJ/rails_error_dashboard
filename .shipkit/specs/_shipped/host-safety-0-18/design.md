# Design: Host-safety fixes for 0.18.0

## Approach
Two contained changes, each inside one service. Their callers in
`app/helpers/rails_error_dashboard/backtrace_helper.rb` don't change.
- **`Services::GitBlameReader#execute_git_blame`:**
  - starts `git` in its own process group, through `Open3.popen3`;
  - reads its output against a monotonic deadline;
  - on the deadline, ends that group and reaps the child.

  `Timeout.timeout` goes.
- **`Services::SourceCodeReader#resolve_absolute_path`:**
  - maps an absolute path outside `Rails.root` to the longest trailing part of it that names an
    existing file under `Rails.root`, starting at one of `Rails.root`'s top-level directories;
  - with no match, returns nil, and the reader shows its existing "source not available" state.

  `validate_path!` runs on the result unchanged.

The source cache key already includes `RailsErrorDashboard::VERSION`
(`backtrace_helper.rb:209-210`), so a wrong file cached by 0.17 isn't served after the upgrade.

## Decision: Spawn git in its own process group, and end the group at the deadline   (→ REQ-1, REQ-2, REQ-3, REQ-4)

**Context.** `execute_git_blame` (`git_blame_reader.rb:97-99`) wraps `Open3.capture3` in
`Timeout.timeout(COMMAND_TIMEOUT)`. On timeout, `Timeout` raises inside the calling thread, but
`capture3` has already spawned `git`. Nothing kills it, so the process outlives the request and
stays in the host app's process tree. `Timeout` can also interrupt the thread at any point,
including inside `capture3`'s own cleanup. This runs on a dashboard request in the host process,
where the paramount rule allows no process-wide side effects (rules 9 and 11 of the host-app-safety
skill).

**Alternatives.**
1. `Open3.popen3(*cmd, chdir: Rails.root, pgroup: true)`. Read stdout and stderr with `IO.select`
   against a monotonic deadline. Past the deadline:
   - send `TERM` to the child's group (`-pid`);
   - wait up to one second, then send `KILL`;
   - reap it through the wait thread.
2. The same, without `pgroup`: signal only the child's pid.
3. Prefix the command with coreutils `timeout 5`.

**Case for 1.** The child ends, and is reaped, on every path. The group is the one `git` leads, so
the signal reaches `git` and anything it started, and nothing else. No signal handler is installed
in the host. `IO.select` on both pipes avoids the classic deadlock where one full pipe blocks the
child while Ruby waits on the other. The deadline is read from `CLOCK_MONOTONIC`, as the
host-app-safety skill requires for budgets.

**Case against 1.** More code than one `capture3` call: a read loop and a two-step kill. `pgroup:`
is Unix-only (Windows uses `new_pgroup:`). On a platform without process groups, the reader falls
back to signalling the pid alone (alternative 2's behavior). Option 3 is the least code, but
coreutils `timeout` isn't on macOS by default, and it hides the child's exit status behind its own.

**Decision.** We chose option 1.
**Falsifiability.** We would reverse this if a spec or an issue shows a `git` process still alive
after a blame timeout, or if a blame that finishes within `COMMAND_TIMEOUT` returns a different
result from `capture3` (the REQ-2 spec compares them).
**Fired-if.** manual

## Decision: Map an outside path by its longest existing suffix under `Rails.root`, anchored at a top-level directory   (→ REQ-5, REQ-6, REQ-7)

**Context.** `resolve_absolute_path` (`source_code_reader.rb:101-111`) turns an absolute path that
doesn't start with `Rails.root` into `Rails.root/<basename>`. The common real case is a backtrace
from an earlier deploy. With Capistrano, `Rails.root` is the release directory after symlinks are
resolved: errors recorded before a deploy name `releases/OLD/app/...`, and the app now runs from
`releases/NEW`. The basename rule then looks for `Rails.root/user.rb`. Usually there's no such
file and the frame shows no source. When a file with that name exists at the root, the frame shows
the wrong file.

**Alternatives.**
1. Split the path into segments. For each segment that names a top-level entry of `Rails.root`
   (`app`, `lib`, `config`, …), earliest first, try `Rails.root/<that segment>/<the rest>`. Use the
   first candidate that exists; otherwise return nil. The longest suffix wins because the search
   starts from the left.
2. Return nil for every absolute path outside `Rails.root`.
3. Strip a configured deploy prefix (a new config option).

**Case for 1.** Frames from an earlier release map to the same app-relative file, which is what
View Source showed before that deploy. The match is on whole segments, and must begin at a
directory that really exists at the root. So it never lands on a file that merely shares a name,
which closes REQ-6. `validate_path!` still runs on the result, so the extension, dot-directory,
traversal and sensitive-pattern rules (REQ-7) are untouched. There's no new config, and the 1.0
freeze is weeks away.

**Case against 1.** A path from a gem (`.../gems/foo-1.0/lib/foo/bar.rb`) could map to the app's
own `lib/foo/bar.rb`, if the app happens to have one at that exact path. Gem frames normally get no
View Source (`only_show_app_code_source` defaults to true). And a gem and an app sharing a full
relative path is rare. Option 2 can never pick a wrong file, but Capistrano users would lose View
Source for every error recorded before their latest deploy. Option 3 handles every layout, at the
price of a new public option to freeze.

**Decision.** We chose option 1.
**Falsifiability.** We would switch to option 2 if an issue reports View Source showing a file that
isn't the frame's file after 0.18.0.
**Fired-if.** manual

## Decision: Bound the user count inside the database, per adapter   (→ REQ-8)

**Context.** `UserModelDetector.query_user_count` (`helpers/user_model_detector.rb:92-111`) runs
`model_class.count` under `Timeout.timeout(5)`. The count feeds user-impact percentages on the
Settings and user-impact pages, and the result is cached five minutes
(`configuration.rb:1257-1275`). On a large users table an exact `COUNT(*)` can take seconds.
`Timeout` interrupts the Ruby thread wherever it is, including inside the driver, and can leave the
host's connection mid-protocol in the host's own pool. The count runs on the host's primary
database, not RED's.

**Alternatives.**
1. Let the database end a slow count:
   - **PostgreSQL:** `SET LOCAL statement_timeout` inside a transaction around the count;
   - **MySQL:** a `MAX_EXECUTION_TIME` optimizer hint on the `SELECT`;
   - **SQLite:** a plain count; its database is a local file.

   A cancelled query raises in Ruby, and the count gives nil.
2. Use the database's row estimate (`pg_class.reltuples`, `information_schema.tables.table_rows`),
   falling back to a plain count.
3. Drop the automatic count; show impact only when `total_users_for_impact` is configured.

**Case for 1.** The count stays exact, as today. The database stops its own query and tells the
driver cleanly, so the connection is left in a known state, which REQ-8 asks for. It needs no new
setting and keeps the five-second bound users have today.

**Case against 1.** It's adapter-specific code in a helper. MariaDB ignores the MySQL hint (it reads
it as a comment), so on MariaDB the count is unbounded, though never interrupted. `SET LOCAL` opens
a short transaction on the host's connection. Under PgBouncer's transaction pooling that's still
correct, because `SET LOCAL` ends with the transaction. Option 2 is O(1), but the estimate is -1
on a table never analyzed (new apps), and it changes the number users see. Option 3 removes a free
feature, which the product's non-goals rule out.

**Decision.** We chose option 1. Task T3 checks it on the PostgreSQL and MySQL `adapter-test` rows
before it's relied on.
**Falsifiability.** We would switch to option 2 if a spec or an issue shows the database-side
bound failing to end a slow count on a supported PostgreSQL or MySQL version.
**Fired-if.** manual

## Found while designing (not in this spec)
`services/crash_capture.rb:81` wraps a file write at exit in `Timeout.timeout(1)`. The process is
already ending, and the import tolerates a partial file, so it stays out of this spec.
