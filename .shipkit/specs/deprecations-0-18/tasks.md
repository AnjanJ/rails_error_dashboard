# Tasks: Deprecations for 0.18.0

Test first in every task: the cited test fails before the change and passes after it. Every test
cites `deprecations-0-18/REQ-N`. One commit per task, test and code together.

`R` below stands for `env -u RAILS_VERSION bin/with-ruby bundle exec`. Run one rspec process at a
time. `spec/support/deprecation.rb` resets `RailsErrorDashboard::Deprecation`'s reported keys after
every example, so one example's warning can't hide another's, in any order.

- [x] **T1** One reporter for every deprecation → REQ-1, REQ-2, REQ-3
  - Files: lib/rails_error_dashboard/deprecation.rb, lib/rails_error_dashboard.rb, spec/lib/rails_error_dashboard/deprecation_spec.rb
  - Test: deprecation_spec:
    - the line starts `[Rails Error Dashboard] DEPRECATION:`;
    - two reports with one key → one line;
    - `stderr: true` also writes to `$stderr`;
    - nothing raises when `Rails.logger` is nil or its `warn` raises, or when Active Support
      deprecations are set to `:raise` (`Rails.application.deprecators.behavior` on 7.1+,
      `ActiveSupport::Deprecation.behavior` on 7.0)
  - After: none
  - Done when: `R rspec spec/lib/rails_error_dashboard/deprecation_spec.rb` → 0 failures
- [x] **T2** The two dead options warn and store nothing → REQ-4, REQ-5, REQ-6, REQ-7, REQ-9
  - Files: lib/rails_error_dashboard/configuration.rb, app/views/rails_error_dashboard/errors/settings.html.erb, spec/lib/rails_error_dashboard/deprecated_options_spec.rb, spec/lib/rails_error_dashboard/configuration_spec.rb, spec/lib/rails_error_dashboard/configuration_validation_spec.rb, spec/lib/rails_error_dashboard_spec.rb, spec/lib/rails_error_dashboard/commands/async_logging_spec.rb, spec/lib/rails_error_dashboard/commands/backtrace_limiting_spec.rb, spec/requests/settings_option_count_spec.rb, spec/dummy/config/initializers/rails_error_dashboard.rb
  - Test: deprecated_options_spec:
    - assigning either option logs one deprecation and the reader returns nil;
    - `validate!` passes with `async_adapter = :anything` and async logging on, where it raises
      today;
    - async capture enqueues on the app's Active Job adapter with and without `async_adapter`
      set;
    - the Settings page shows neither option
  - After: T1
  - Done when: `R rspec spec/lib/rails_error_dashboard spec/lib/rails_error_dashboard_spec.rb spec/requests/settings_option_count_spec.rb` → 0 failures
- [x] **T3** The installer stops writing `async_adapter` → REQ-8
  - Files: lib/generators/rails_error_dashboard/install/templates/initializer.rb, lib/generators/rails_error_dashboard/install/install_generator.rb, spec/generators/install_generator_spec.rb
  - Test: install_generator_spec:
    - with and without async logging, the generated initializer contains no `async_adapter` and
      no `llm_observability_content_capture`, live or commented;
    - async logging is still written on
  - After: none
  - Done when: `R rspec spec/generators/install_generator_spec.rb` → 0 failures
- [x] **T4** Every task under `rails_error_dashboard:`, with warning aliases → REQ-10, REQ-11
  - Files: lib/tasks/error_dashboard.rake, lib/tasks/rails_error_dashboard_tasks.rake, spec/lib/rails_error_dashboard/rake_aliases_spec.rb, spec/lib/rails_error_dashboard/verify_task_spec.rb, spec/lib/rails_error_dashboard/cleanup_resolved_task_spec.rb, spec/lib/rails_error_dashboard/db_drop_task_spec.rb
  - Test: rake_aliases_spec:
    - each of the 11 names exists as `rails_error_dashboard:<name>`;
    - invoking `error_dashboard:<name>` prints the deprecation naming the new task on stderr, then
      runs the new task's body once (spied), with ENV inputs intact;
    - an error raised by the new task propagates through the alias;
    - the aliases have no `desc`.

    The existing task specs invoke the new names.
  - After: T1
  - Done when: `R rspec spec/lib/rails_error_dashboard/rake_aliases_spec.rb spec/lib/rails_error_dashboard/verify_task_spec.rb spec/lib/rails_error_dashboard/cleanup_resolved_task_spec.rb spec/lib/rails_error_dashboard/db_drop_task_spec.rb` → 0 failures
- [x] **T5** `verify` covers what the generator checked, and the generator goes → REQ-13, REQ-20, REQ-21
  - Files: lib/tasks/error_dashboard.rake, lib/generators/rails_error_dashboard/solid_queue/solid_queue_generator.rb, spec/generators/solid_queue_generator_spec.rb, spec/generators/generators_hands_off_spec.rb, spec/lib/rails_error_dashboard/verify_task_spec.rb
  - Test: verify_task_spec:
    - with `config/queue.yml` present and `SolidQueue` hidden (`hide_const`), verify still
      reports the file's problems;
    - with Solid Queue loaded and no file, it prints the defaults line;
    - `Rails::Generators.find_by_namespace("rails_error_dashboard:solid_queue")` is nil.

    The generator's own spec is deleted, and generators_hands_off_spec drops it.
  - After: T4
  - Done when: `R rspec spec/lib/rails_error_dashboard/verify_task_spec.rb spec/generators` → 0 failures
- [x] **T6** `USE_SEPARATE_ERROR_DB` warns and behaves as before → REQ-14
  - Files: lib/rails_error_dashboard/configuration.rb, spec/lib/rails_error_dashboard/configuration_validation_spec.rb
  - Test: configuration_validation_spec:
    - with the ENV set to `"true"`, `"false"` or `"1"`: one deprecation each, and
      `use_separate_database` takes 0.17.0's value for each;
    - unset: no warning
  - After: T2
  - Done when: `R rspec spec/lib/rails_error_dashboard/configuration_validation_spec.rb` → 0 failures
- [x] **T7** The Rails and Ruby floor warnings → REQ-16, REQ-17, REQ-18
  - Files: lib/rails_error_dashboard/configuration.rb, spec/lib/rails_error_dashboard/configuration_validation_spec.rb, spec/lib/rails_error_dashboard/configuration_spec.rb, spec/support/deprecation.rb, spec/lib/rails_error_dashboard/deprecated_options_spec.rb, spec/lib/rails_error_dashboard/rake_aliases_spec.rb, spec/lib/rails_error_dashboard/deprecation_spec.rb
  - Test: configuration_validation_spec, with `ActionPack.gem_version` and `RUBY_VERSION` stubbed
    as the 7.0.10 spec does:
    - 7.1.5 → one warning naming Rails 7.2 and the 0.x support page;
    - 7.2.0 → none;
    - Ruby 3.2.9 → one;
    - 3.3.0 → none;
    - `validate!` twice → still one of each;
    - 7.0.8 still gets the 7.0.10 warning too, and `validate!` returns true
  - After: T6, T4
  - Done when: `R rspec spec/lib/rails_error_dashboard/configuration_validation_spec.rb` → 0 failures
- [x] **T8** Code, UI text and docs name only `rails_error_dashboard:` tasks → REQ-12, REQ-15
  - Files: README.md, docs/, _guides/, _reference/, _getting_started/, _features/, config/locales/, app/models/rails_error_dashboard/error_logs_record.rb, app/jobs/rails_error_dashboard/scheduled_digest_job.rb, app/jobs/rails_error_dashboard/retention_cleanup_job.rb, app/views/rails_error_dashboard/errors/diagnostic_dumps.html.erb, app/views/rails_error_dashboard/errors/settings/_value_badge.html.erb, lib/rails_error_dashboard/engine.rb, lib/rails_error_dashboard/configuration.rb, lib/rails_error_dashboard/queries/event_volume.rb, lib/rails_error_dashboard/commands/scrub_invalid_encoding.rb, lib/rails_error_dashboard/commands/backfill_resolved_at.rb, lib/rails_error_dashboard/services/solid_queue_config_check.rb, lib/generators/rails_error_dashboard/install/install_generator.rb, lib/generators/rails_error_dashboard/install/templates/initializer.rb, spec/docs/task_names_spec.rb, spec/requests/summary_pages_i18n_spec.rb
  - Test: task_names_spec:
    - no `error_dashboard:<task>` for any of the 11 names remains under `app/`, `lib/`,
      `config/locales/`, `docs/`, the Jekyll folders or README, except `docs/UPGRADING.md`,
      `_getting_started/upgrading.md`, CHANGELOG and `lib/tasks/`, where the aliases are defined;
    - no docs page offers `USE_SEPARATE_ERROR_DB` in an ENV list;
    - `bin/i18n-check` passes
  - After: T7, T3, T5
  - Done when: `R rspec spec/docs/task_names_spec.rb` → 0 failures, and `bin/i18n-check` exits 0
- [x] **T9** The 0.18.0 upgrade notes → REQ-19
  - Files: docs/UPGRADING.md, _getting_started/upgrading.md, spec/docs/task_names_spec.rb
  - Test: task_names_spec: both copies have a 0.18.0 section that names each deprecation, each
    with its replacement line:
    - `async_adapter` and `llm_observability_content_capture`;
    - the 11 task renames;
    - the generator;
    - `USE_SEPARATE_ERROR_DB`;
    - the Rails and Ruby floors
  - After: T8
  - Done when: `R rspec spec/docs/task_names_spec.rb` → 0 failures
