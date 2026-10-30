# Spec: Deprecations for 0.18.0

> Spec accepted at commit `6b1dfab` on spec/0-18-0 (2026-10-29).
> Status: open
> Paths: lib/rails_error_dashboard/configuration.rb,lib/rails_error_dashboard/deprecation.rb,lib/rails_error_dashboard/engine.rb,lib/tasks/,lib/generators/rails_error_dashboard/,app/views/rails_error_dashboard/errors/settings.html.erb,config/locales/,docs/,_guides/,_getting_started/,_reference/,_features/,README.md,spec/

## Purpose
1.0 freezes RED's public surface, and some of it shouldn't be frozen as it stands:
- two options that do nothing;
- a second rake namespace;
- a generator that writes nothing;
- an ENV switch the generated initializer overrides;
- support for Rails and Ruby versions 1.0 will drop.

0.18.0 marks each one, and every app keeps booting and working exactly as before. Each mark is a
warning that's logged once. Nothing raises.

## User stories
- As a developer upgrading to 0.18, I want my app to boot unchanged, so that I can upgrade without
  editing anything first.
- As a developer, I want one clear log line for each deprecated thing I use, saying what to do
  instead, so that I can get ready for 1.0 at my own pace.
- As a developer whose cron calls `error_dashboard:retention_cleanup`, I want the job to keep
  running, so that a rename doesn't silently stop my cleanup.

## Requirements (EARS)

### How deprecations are reported
- **REQ-1.** RED shall report each deprecation as one line starting with
  `[Rails Error Dashboard] DEPRECATION:`. The line names the deprecated thing, what to use instead
  (or that nothing is needed), and the version that removes it.
- **REQ-2.** RED shall report each distinct deprecation at most once per process, however often
  the deprecated thing is used.
- **REQ-3.** A deprecation report shall never raise into the host app, even when:
  - `Rails.logger` is nil or raises;
  - the host app sets Active Support deprecations to raise.

### Options that do nothing (decision 0004)
- **REQ-4.** When an initializer assigns `config.async_adapter`, RED shall report the deprecation
  and ignore the value. `config.async_adapter` returns nil.
- **REQ-5.** `Configuration#validate!` shall accept any value assigned to `async_adapter`. Today an
  unknown value fails validation when async logging is on.
- **REQ-6.** When an initializer assigns `config.llm_observability_content_capture`, RED shall
  report the deprecation and ignore the value. The getter returns nil.
- **REQ-7.** Async capture shall run the same way, on the host app's Active Job adapter, whether or
  not `async_adapter` is set.
- **REQ-8.** The install generator shall write neither option into a new initializer, as a live
  line or as a comment.
- **REQ-9.** The Settings page shall show neither option.

### One rake namespace
- **REQ-10.** Each of the 11 `error_dashboard:*` tasks shall also exist as
  `rails_error_dashboard:<same name>`, with the same arguments, behavior and exit status.
- **REQ-11.** When an `error_dashboard:<name>` task is invoked, RED shall:
  1. print the deprecation to standard error, naming `rails_error_dashboard:<name>`;
  2. run the same task with the same arguments.
- **REQ-12.** RED's own code, UI text in every locale and docs shall name only
  `rails_error_dashboard:*` tasks. The old names appear only in UPGRADING and CHANGELOG.

### The solid_queue generator
- **REQ-13.** 0.18.0 shall not ship the `rails_error_dashboard:solid_queue` generator. The Solid
  Queue check it printed stays available through `rails_error_dashboard:verify`.
- **REQ-20.** When `config/queue.yml` exists, `rails_error_dashboard:verify` shall check it whether
  or not Solid Queue is loaded in that process. Today it checks only when `SolidQueue` is defined,
  and the generator checked either way.
- **REQ-21.** When the app uses Solid Queue and has no `config/queue.yml`,
  `rails_error_dashboard:verify` shall report that Solid Queue's defaults process RED's queues. The
  generator said this, and `verify` says nothing today.

(REQ-20 and REQ-21 were added at the requirements gate on 2026-10-29, so that removing the generator
loses nothing. They're numbered last so the accepted numbers don't shift.)

### USE_SEPARATE_ERROR_DB
- **REQ-14.** When `USE_SEPARATE_ERROR_DB` is set at boot, RED shall report the deprecation, and
  `use_separate_database` shall take the same value it would in 0.17.0.
- **REQ-15.** The docs' ENV lists shall no longer offer `USE_SEPARATE_ERROR_DB`.

### Rails and Ruby versions that 1.0 drops (decision 0003)
- **REQ-16.** When the app boots on Rails earlier than 7.2, RED shall log one warning. It says:
  - RED 1.0 requires Rails 7.2 or later;
  - this RED version keeps working;
  - where the 0.x support dates are documented.
- **REQ-17.** When the app boots on Ruby earlier than 3.3, RED shall log the same warning for Ruby.
- **REQ-18.** Neither warning shall change what RED does: capture, the dashboard, and the existing
  warning for Rails before 7.0.10 all behave as in 0.17.0.

### Upgrade notes
- **REQ-19.** UPGRADING (`docs/UPGRADING.md` and its Jekyll copy `_getting_started/upgrading.md`)
  shall gain a 0.18.0 section listing every deprecation above, each with the line to change or
  delete.

## Out of scope
- Renaming config options or ENV names (frozen as they are, answer of 2026-10-29).
- Removing anything: removals happen in 2.0.
- Raising the gemspec minimums (1.0.0.rc1).
