# Design: Deprecations for 0.18.0

## Approach
- **The reporter:** a new `RailsErrorDashboard::Deprecation` module, with one method:
  `Deprecation.warn(key, message, stderr: false)`.
  - It writes `[Rails Error Dashboard] DEPRECATION: <message>` once per `key` per process, through
    `Rails.logger.warn`.
  - With `stderr: true` it also writes the line to `$stderr`.
  - A `Mutex`-guarded `Set` records the keys already reported, and a rescue around everything
    means it can't raise.

  Every item below goes through it.
- **The dead options** (`configuration.rb:128`, `:265`): each `attr_accessor` becomes a hand-written
  setter that reports the deprecation and stores nothing, plus a reader that returns nil.
  - The defaults at `:392` and `:536` and the `async_adapter` validation at `:679-683` go.
  - The installer template drops its `async_adapter` lines (`install/templates/initializer.rb:191-202`).
  - Settings drops the two rows (`settings.html.erb:40-41`). `async_logging`'s
    `extra: :async_adapter` key goes too; it has no reader.
- **Rake:** the 11 task bodies move from `namespace :error_dashboard`
  (`lib/tasks/error_dashboard.rake`) to `namespace :rails_error_dashboard`. A loop then defines
  each old name as a task that does two things:
  1. reports the deprecation with `stderr: true`;
  2. invokes the new task.

  The aliases have no `desc`, so `rake -T` lists only the new names.
- **The solid_queue generator:** its directory and spec are deleted. In `verify`'s Solid Queue
  check (`error_dashboard.rake:215-240`):
  - the gate becomes `queue_config.exist?` alone (REQ-20). `SolidQueueConfigCheck` already works
    without Solid Queue loaded: it falls back to the newest rules (`solid_queue_config_check.rb`,
    `processes_for` and `process_keys`);
  - when Solid Queue is loaded and the file is absent, it prints the defaults line (REQ-21).
- **`USE_SEPARATE_ERROR_DB`:** `initialize` still reads it at `:359`, unchanged. `validate!` reports
  the deprecation when `ENV.key?("USE_SEPARATE_ERROR_DB")`.
- **Rails and Ruby floors:** two warnings in `validate!`, beside the existing 7.0.10 one
  (`:745-750`), compared with `Gem::Version`. They go through `Deprecation.warn`, so they're
  logged once even though `verify` runs `validate!` a second time (`error_dashboard.rake:18`).
- **Docs:** every `error_dashboard:<task>` in `docs/`, the Jekyll copies, README, locales, views,
  generators and comments becomes `rails_error_dashboard:<task>`. The old names stay only in
  UPGRADING and CHANGELOG. The README's `rails_error_dashboard:diagnostic_dump` (`README.md:529`),
  which names a task that doesn't exist today, becomes correct.

## Decision: RED's own warn-once reporter on `Rails.logger`, not Active Support's deprecator   (→ REQ-1, REQ-2, REQ-3)

**Context.** The two setters run while the host app's initializer loads, so whatever they call runs
during boot. RED has no deprecation helper today. Its own `RailsErrorDashboard::Logger.warn`
returns early unless `enable_internal_logging` is on (`logger.rb:65-69`), so it would hide every
warning from most apps. `validate!` already writes its warnings with `Rails.logger.warn`
(`configuration.rb:1029-1033`), and `verify` calls `validate!` a second time in the same process.

**Alternatives.**
1. `RailsErrorDashboard::Deprecation.warn(key, message)`: a set of reported keys, `Rails.logger.warn`,
   everything rescued.
2. `ActiveSupport::Deprecation.new("2.0", "rails_error_dashboard")`, registered in
   `Rails.application.deprecators`.
3. `Kernel#warn(message, category: :deprecated)`.

**Case for 1.** It can't raise, whatever the host has configured, which is the paramount rule and
REQ-3. It writes where apps already see RED's other boot warnings. It reports each key once, so
neither a second `validate!` nor a setter called in a loop repeats it.

**Case against 1.** Hosts can't use Rails' standard deprecator controls on RED's warnings:
`config.active_support.deprecation = :raise` in their test suite won't surface them, and
`deprecators.silenced` won't hide them. Option 2 gives them that, but in exactly the apps that set
`:raise` (common in test environments), the initializer line would raise during boot. And Rails
7.0, still supported in 0.18, has no `Rails.application.deprecators`. Option 3 is hidden by default:
Ruby suppresses the `:deprecated` category unless `-W:deprecated` is passed.

**Decision.** We chose option 1.
**Falsifiability.** We would add an opt-in route to an Active Support deprecator if two or more
users ask to have RED's deprecations raise in their test suites.
**Fired-if.** manual

## Decision: The old option names become setters that warn and store nothing   (→ REQ-4, REQ-5, REQ-6, REQ-7)

**Context.** Decision 0004 settled the policy: warning no-ops from 0.18, deleted in 2.0. This
record covers the shape. Both are plain `attr_accessor`s today, and no custom setter exists in
`configuration.rb` to copy. The Settings view reads every row through `@config.send(name)`
(`settings.html.erb:213`), and specs read `config.async_adapter`.

**Alternatives.**
1. A setter that reports and ignores the value; a reader that returns nil.
2. A setter that reports but still stores the value; the reader returns it.
3. `method_missing` for removed names.

**Case for 1.** A nil reader says truthfully that the option does nothing, matching 0004 ("the
getters return nil"). Code that reads it gets nothing, not a value that pretends to mean
something. The setter's existence keeps every initializer booting, with no `NoMethodError` (0004's
case).

**Case against 1.** Code that read `async_adapter` (a host's own initializer logic, say) now gets
nil where it used to get `:sidekiq` or `:async`. RED itself reads it nowhere except the validation
and the Settings page, both going. Option 2 keeps that code working, but it freezes a meaningless
value into 1.x.

**Decision.** We chose option 1.
**Falsifiability.** We would switch the reader to return the stored value (option 2) if an issue
reports host code broken by `async_adapter` returning nil.
**Fired-if.** manual

## Decision: Old rake names are hidden tasks that warn, then invoke the new task   (→ REQ-10, REQ-11, REQ-12)

**Context.** The 11 `error_dashboard:*` tasks read their inputs from ENV (`PERIOD`, `APP_ID`,
`DAYS`, …), never from rake arguments. None calls `exit`. Nothing in RED invokes them; cron
entries in users' crontabs do, and that output usually goes to mail. The specs load tasks with
`Rails.application.load_tasks` and call `Rake::Task[...].invoke` (`verify_task_spec.rb:9-11`).

**Alternatives.**
1. Move each body to `rails_error_dashboard:`. Define each old name as a task with no `desc` whose
   body reports the deprecation (stderr and log) and then calls
   `Rake::Task["rails_error_dashboard:<name>"].invoke`.
2. Old name as a prerequisite-only alias: `task "error_dashboard:x" => "rails_error_dashboard:x"`.
3. Keep both bodies, one per namespace.

**Case for 1.** One body per task. The warning prints before the work, on stderr, where a cron run
shows it, as REQ-11 asks. ENV inputs pass through untouched, and so does a raised error, so the
exit status is the new task's. With no `desc`, the old names leave `rake -T` but still run.

**Case against 1.** `rake -T` no longer shows the old names, so someone looking for one finds
nothing listed. UPGRADING is where the mapping lives. `invoke` runs a task once per rake process,
so a script that runs both names in one `rake` call gets one run, not two. Option 2 is one line per
task, but a prerequisite has no body to print the warning from, and Rake has no hook to add one.

**Decision.** We chose option 1.
**Falsifiability.** We would add `desc` lines to the aliases if an issue reports a user unable to
find a task they used before 0.18.0.
**Fired-if.** manual
