# Tasks: 1.0 hardening (1.0.0-rc.2)

Ten pull requests, in this order:
1. T1-T2: the spikes, research only, with S1 done by 2026-12-04.
2. T3-T6: grouping v2.
3. T7-T8: the grouping window.
4. T9-T13: defaults and release hygiene.
5. T14-T16: notifications.
6. T17-T19: data lifecycle.
7. T20-T21: the audit actor.
8. T22-T27: dashboard and queries.
9. T28-T29: migrations.
10. T30-T31: host conditions. They wait for S1's amendment, which may change T30's file list.

Each pull request merges before the next branch starts from main. Rules for every task:
- Code tasks write their test first, see it fail for the right reason, and cite
  `hardening-1-0-rc2/REQ-N`.
- Capture-path tasks (T3-T5, T7, T11, T13, T30) also run `bin/benchmark`, and their pull request
  records the capture and storm-check medians against rc.1's.

`rspec` below stands for `env -u RAILS_VERSION mise exec ruby@3.4.5 -- bundle exec rspec`.

## Spikes
- [ ] **T1** Spike S1: how a capture survives a host rollback, prevented writes and a starved pool → REQ-17, REQ-18, REQ-19, REQ-20, REQ-21, REQ-22
  - Files: .shipkit/research/host-conditions-spike.md, .shipkit/specs/hardening-1-0-rc2/spec.md, .shipkit/specs/hardening-1-0-rc2/design.md
  - Test: none, it is a spike. Its probes run from a scratch directory outside the repository, against
    copies of the databases, and are deleted afterwards. The research file records each probe's code.
  - After: none
  - Done when:
    - the research file has a table for each option in design.md's host-conditions decision, by SQLite,
      PostgreSQL 16 and MySQL 8, by Rails 7.2, 8.0 and 8.1, by sync and async with Solid Queue;
    - each table gives the extra connections, the capture-time change and the switch;
    - spec.md and design.md are amended: the chosen option as a decision record, the final names in
      place of the provisional ones, T30's file list, and the Goldfish GAPS lines removed;
    - the maintainer has read it.
- [ ] **T2** Spike S2: what making a failed capture visible would cost the host → REQ-19
  - Files: .shipkit/research/silent-failures-spike.md, .shipkit/specs/hardening-1-0-rc2/spec.md, .shipkit/specs/hardening-1-0-rc2/design.md
  - Test: none, it is a spike. It measures:
    - every `Logger.error` call site, and what each prints (personal data included);
    - how many failure lines a storm against a broken schema produces in 60 seconds;
    - one `Rails.logger.error` call's cost on the capture path, to a file and to STDOUT.
  - After: T1
  - Done when:
    - the research file compares the four options in design.md (spike S2);
    - the maintainer has picked one;
    - spec.md gains its requirement and tasks.md its tasks, before any change to `log_level`.

## Grouping v2
- [ ] **T3** `ErrorHashGenerator.identities` and the v2 recipe → REQ-1, REQ-2, REQ-3, REQ-4, REQ-7
  - Files: lib/rails_error_dashboard/services/error_hash_generator.rb, spec/services/error_hash_generator_v2_spec.rb
  - Test: spec/services/error_hash_generator_v2_spec.rb:
    - one file loaded under two release directories, with `Rails.root` set to each, gives one v2
      fingerprint, and a symlinked root gives the same;
    - `<internal:kernel>` and `rubylibdir` frames are skipped;
    - one method at two lines gives one fingerprint, and two methods give two;
    - `NoMethodError` for `nme` and `emial` gives two;
    - a string-only backtrace follows the same rules;
    - `custom_fingerprint` returns the rc.1 value;
    - v1 from `identities` equals rc.1's `ErrorHashGenerator.call` for the same exception.
  - After: none
  - Done when: `rspec spec/services` → 0 failures; with the old frame rule restored, the release-directory and `nme`/`emial` examples fail
- [ ] **T4** Sync and async capture carry both identities; the lookups match v2 then v1 and move the row to v2 → REQ-5, REQ-6
  - Files: lib/rails_error_dashboard/commands/log_error.rb, lib/rails_error_dashboard/commands/find_or_increment_error.rb, spec/commands/log_error_identity_v2_spec.rb, spec/commands/find_or_increment_error_v1_fallback_spec.rb
  - Test:
    - an open, a resolved and a wont_fix group seeded with only a v1 hash each take a sync and an async
      capture: count +1, no new row, and `error_hash` is now v2;
    - an async job built as rc.1 builds it (`_identity`, no `_identity_version`) counts on the v1 group
      and leaves its hash as v1;
    - a `RecordNotUnique` on the move keeps v1 and still counts.
  - After: T3
  - Done when: `rspec spec/commands` → 0 failures; `bin/benchmark` capture median within 0.2 ms of rc.1's on the same machine
- [ ] **T5** The storm gate, count buffer and flush carry v1 beside v2 → REQ-5, REQ-6
  - Files: lib/rails_error_dashboard/services/storm_protection/gate.rb, lib/rails_error_dashboard/services/storm_protection/count_buffer.rb, lib/rails_error_dashboard/commands/flush_storm_counts.rb, spec/commands/flush_storm_counts_v1_fallback_spec.rb
  - Test: spec/commands/flush_storm_counts_v1_fallback_spec.rb:
    - a flush of a new-style entry counts on a v1-only open group and moves it to v2;
    - a flush of an rc.1-shaped buffer entry (no `opaque_identity_v1`) counts under v1;
    - the gate computes v1 once per new entry, not per hit.
  - After: T3
  - Done when: `rspec spec/commands spec/services` → 0 failures; `bin/benchmark` storm-check median < 15 µs
- [ ] **T6** Document the recipe as stable for 1.x, and record decision 0010 → REQ-8
  - Files: docs/PUBLIC_API.md, .shipkit/decisions/0010-grouping-recipe-stable-for-1x.md
  - Test: none, prose.
  - After: T4, T5
  - Done when: PUBLIC_API.md names the recipe's parts, says it is stable for all of 1.x, and says the v1 fallback goes only in 2.0; 0010 has all five parts and a reversal condition

## Grouping window
- [ ] **T7** Match open groups by last occurrence at all three lookups → REQ-9, REQ-10, REQ-11
  - Files: lib/rails_error_dashboard/commands/find_or_increment_error.rb, lib/rails_error_dashboard/commands/flush_storm_counts.rb, spec/commands/grouping_window_spec.rb
  - Test: spec/commands/grouping_window_spec.rb runs each case through the lookup, the duplicate-create
    retry and the storm flush. Times use `travel_to` relative to now, never a hard-coded date.
    - first seen 30 h ago and last seen 1 h ago: counted on it;
    - last seen 25 h ago: a new group;
    - a legacy row with NULL `last_seen_at` falls back to `occurred_at`.
  - After: T4, T5
  - Done when: `rspec spec/commands` → 0 failures; the existing 24 h specs pass, or were changed only where they asserted the old rollover
- [ ] **T8** Say when a new group starts → REQ-12
  - Files: docs/PLUGIN_SYSTEM.md, docs/GLOSSARY.md
  - Test: none, prose.
  - After: T7
  - Done when: `docs/PLUGIN_SYSTEM.md:54` and the glossary's group entry describe the last-occurrence rule

## Defaults and release hygiene
- [ ] **T9** Name each default correctly, and give sync's measured cost → REQ-13
  - Files: README.md, docs/QUICKSTART.md, docs/PRODUCTION.md, docs/FEATURES.md, docs/guides/CONFIGURATION.md, docs/guides/SOLID_QUEUE_SETUP.md, _getting_started/production.md, _getting_started/quickstart.md, _getting_started/features.md
  - Test: none, prose.
  - After: none
  - Done when: `git grep -n -i "async" -- README.md docs _getting_started` shows no line calling async the library's default; README gives sync's figures from `.shipkit/research/deploy-shape-benchmark.md:224,242`
- [ ] **T10** The gemspec requires MFA → REQ-14
  - Files: rails_error_dashboard.gemspec, spec/gemspec_mfa_spec.rb
  - Test: spec/gemspec_mfa_spec.rb loads the gemspec and asserts `metadata["rubygems_mfa_required"] == "true"`
  - After: none
  - Done when: `rspec spec/gemspec_mfa_spec.rb` → 0 failures
- [ ] **T11** A `user_id` out of the column's range is stored as nil → REQ-15
  - Files: app/models/rails_error_dashboard/error_log.rb, lib/rails_error_dashboard/commands/log_error.rb, spec/models/storable_user_id_spec.rb
  - Test: spec/models/storable_user_id_spec.rb covers both the error log and the occurrence:
    - `2**40` on a 4-byte column gives nil;
    - `2**31 - 1` is kept;
    - a UUID column passes strings through.
  - After: T4
  - Done when: `rspec spec/models spec/commands` → 0 failures, and on the PostgreSQL adapter job in CI
- [ ] **T12** Fresh installs create `user_id` as bigint → REQ-16
  - Files: db/migrate/20251223000000_create_rails_error_dashboard_complete_schema.rb, spec/dummy/db/schema.rb, spec/migrations/create_rails_error_dashboard_complete_schema_spec.rb, docs/UPGRADING.md
  - Test: spec/migrations/create_rails_error_dashboard_complete_schema_spec.rb: with no `primary_key_type` both `user_id` columns are bigint; with `:uuid` they are uuid
  - After: none
  - Done when: `rspec spec/migrations` → 0 failures; `bin/check-schema-parity` passes; UPGRADING.md says how to widen an existing column
- [ ] **T13** A connection timeout in the application lookup doesn't wait a second time → REQ-21
  - Files: lib/rails_error_dashboard/commands/log_error.rb, spec/commands/log_error_application_lookup_spec.rb
  - Test: spec/commands/log_error_application_lookup_spec.rb:
    - `find_or_create_by_name` raising `ActiveRecord::ConnectionTimeoutError` means `Application.first`
      is never called, and the capture returns nil without raising;
    - another error still takes the fallback.
  - After: T11
  - Done when: `rspec spec/commands` → 0 failures

## Notifications
- [ ] **T14** Channel jobs retry transient failures, and release the claim when retries run out → REQ-29, REQ-30, REQ-31
  - Files: app/jobs/rails_error_dashboard/concerns/transient_delivery.rb, app/jobs/rails_error_dashboard/concerns/plain_channel_message.rb, app/jobs/rails_error_dashboard/slack_error_notification_job.rb, app/jobs/rails_error_dashboard/email_error_notification_job.rb, app/jobs/rails_error_dashboard/discord_error_notification_job.rb, app/jobs/rails_error_dashboard/telegram_error_notification_job.rb, app/jobs/rails_error_dashboard/pagerduty_error_notification_job.rb, app/jobs/rails_error_dashboard/webhook_error_notification_job.rb, lib/rails_error_dashboard/services/notification_throttler.rb, lib/rails_error_dashboard/services/error_notification_dispatcher.rb, spec/jobs/notification_retry_spec.rb
  - Test: spec/jobs/notification_retry_spec.rb, for each channel:
    - a timeout, a refused connection, a 429 and a 503 each schedule a retry, asserted by the scheduled
      delay, not by a raise (lesson 2026-09-15);
    - a 400 and an unexpected error log and finish;
    - after 3 failed attempts `last_notified_at` is cleared when it still equals `claimed_at`, and kept
      when a newer claim replaced it;
    - a job enqueued without `claimed_at` releases nothing.
  - After: none
  - Done when: `rspec spec/jobs` → 0 failures; `klass.rescue_handlers` shows `TransientDeliveryError` checked before `StandardError`
- [ ] **T15** One webhook job per URL, with a delivery id that survives retries → REQ-32, REQ-33
  - Files: lib/rails_error_dashboard/services/error_notification_dispatcher.rb, app/jobs/rails_error_dashboard/webhook_error_notification_job.rb, lib/rails_error_dashboard/services/webhook_delivery.rb, docs/WEBHOOKS.md, spec/jobs/webhook_delivery_id_spec.rb
  - Test: spec/jobs/webhook_delivery_id_spec.rb:
    - two URLs enqueue two jobs;
    - a post that fails then succeeds sends the same `X-Error-Dashboard-Delivery` both times;
    - two jobs send different ids;
    - a job enqueued by rc.1 (all URLs in one) still posts each URL.
  - After: T14
  - Done when: `rspec spec/jobs spec/services` → 0 failures; WEBHOOKS.md says at-least-once and how to drop duplicates by the header
- [ ] **T16** CreateIssueJob counts a failure once, and decides on retries by a result code → REQ-34, REQ-35
  - Files: lib/rails_error_dashboard/commands/create_issue.rb, app/jobs/rails_error_dashboard/create_issue_job.rb, spec/jobs/create_issue_job_spec.rb, spec/commands/create_issue_spec.rb
  - Test:
    - a failed result adds one failure to the breaker;
    - under `I18n.with_locale(:de)`, `already_linked` and `not_configured` schedule no retry;
    - `CreateIssue` returns `code:` in each case.
  - After: none
  - Done when: `rspec spec/jobs spec/commands` → 0 failures

## Data lifecycle
- [ ] **T17** Opt-in occurrence retention → REQ-23, REQ-24, REQ-25
  - Files: lib/rails_error_dashboard/configuration.rb, app/jobs/rails_error_dashboard/retention_cleanup_job.rb, lib/tasks/error_dashboard.rake, lib/generators/rails_error_dashboard/install/templates/initializer.rb, docs/guides/CONFIGURATION.md, docs/PUBLIC_API.md, spec/jobs/retention_cleanup_occurrences_spec.rb
  - Test: spec/jobs/retention_cleanup_occurrences_spec.rb:
    - with 30 days, a live group's 31-day occurrences and their contexts go and its 29-day ones stay,
      in batches of 1,000;
    - `occurrence_count`, `first_seen_at` and `last_seen_at` are unchanged;
    - with nil, nothing of a live group goes;
    - the rake preview counts occurrences.
  - After: T6, T9
  - Done when: `rspec spec/jobs spec/lib` → 0 failures; the option is in PUBLIC_API.md and CONFIGURATION.md
- [ ] **T18** A banner while expired errors outlive the grace period → REQ-26
  - Files: app/helpers/rails_error_dashboard/application_helper.rb, app/views/layouts/rails_error_dashboard.html.erb, config/locales/, spec/requests/retention_overdue_banner_spec.rb
  - Test: spec/requests/retention_overdue_banner_spec.rb, with `retention_days` 30:
    - an error last seen 33 days ago shows a banner naming `RetentionCleanupJob`;
    - one last seen 31 days ago doesn't;
    - with `retention_days` nil, no banner;
    - the check is cached for an hour.
  - After: T17
  - Done when: `rspec spec/requests` → 0 failures; the i18n check passes on every locale
- [ ] **T19** Batch delete uses the batched delete → REQ-27, REQ-28
  - Files: lib/rails_error_dashboard/commands/batch_delete_errors.rb, spec/commands/batch_delete_errors_spec.rb
  - Test: spec/commands/batch_delete_errors_spec.rb:
    - the errors, occurrences, contexts, comments, cascade patterns and event counts are gone;
    - no `ErrorLog` is instantiated, checked through `ActiveSupport::Notifications` `instantiation.active_record`;
    - `on_errors_batch_deleted` gets the ids.
  - After: none
  - Done when: `rspec spec/commands` → 0 failures

## Audit actor
- [ ] **T20** `dashboard_actor` records who acted, and marks typed names unverified → REQ-36, REQ-37, REQ-38
  - Files: db/migrate/20261121000001_add_actor_verified_to_error_logs.rb, spec/dummy/db/schema.rb, lib/rails_error_dashboard/configuration.rb, docs/guides/CONFIGURATION.md, docs/PUBLIC_API.md, app/controllers/rails_error_dashboard/errors_controller.rb, app/controllers/rails_error_dashboard/webhooks_controller.rb, lib/rails_error_dashboard/commands/resolve_error.rb, lib/rails_error_dashboard/commands/batch_resolve_errors.rb, lib/rails_error_dashboard/commands/assign_error.rb, lib/rails_error_dashboard/commands/mute_error.rb, lib/rails_error_dashboard/commands/batch_mute_errors.rb, spec/requests/audit_actor_spec.rb
  - Test: spec/requests/audit_actor_spec.rb, for resolve, assign, mute, batch resolve and batch mute:
    - with the setting returning "a@x", "a@x" is recorded and verified;
    - unset or nil, the typed name is recorded unverified;
    - raising, the typed name is recorded unverified and the response is a redirect, not a 500;
    - the issue webhook's "Webhook" is verified.
  - After: T12, T17
  - Done when: `rspec spec/requests spec/commands spec/migrations` → 0 failures; `bin/check-schema-parity` passes; the migration's `down` removes the three columns
- [ ] **T21** The error page marks an unverified name → REQ-39
  - Files: app/views/rails_error_dashboard/errors/_sidebar_metadata.html.erb, config/locales/, spec/requests/audit_actor_display_spec.rb
  - Test: spec/requests/audit_actor_display_spec.rb: an unverified name renders `red-actor-unverified`, and a verified one doesn't
  - After: T18, T20
  - Done when: `rspec spec/requests` → 0 failures; the i18n check passes on every locale

## Dashboard and queries
- [ ] **T22** Shortcuts ignore modifier keys and `<select>` → REQ-40, REQ-41
  - Files: app/views/layouts/rails_error_dashboard.html.erb, spec/system/keyboard_shortcuts_spec.rb
  - Test: spec/system/keyboard_shortcuts_spec.rb:
    - Ctrl+A, Meta+A and Alt+A stay on the page;
    - `a` in a focused `<select>` stays;
    - a plain `a` goes to Analytics.
  - After: T18
  - Done when: `rspec spec/system/keyboard_shortcuts_spec.rb` → 0 failures
- [ ] **T23** A nonce on `<style>`, and a dashboard-only policy for style attributes → REQ-42, REQ-43
  - Files: app/views/layouts/rails_error_dashboard.html.erb, app/controllers/rails_error_dashboard/application_controller.rb, docs/SOURCE_CODE_INTEGRATION.md, spec/requests/csp_compatibility_spec.rb
  - Test: spec/requests/csp_compatibility_spec.rb:
    - with a host policy and a nonce generator, `<style>` carries the nonce and the header has
      `style-src-attr 'unsafe-inline'`;
    - with no host policy, no CSP header is added;
    - a host route outside the engine keeps its header unchanged.
  - After: T22
  - Done when: `rspec spec/requests/csp_compatibility_spec.rb` → 0 failures; `rspec spec/requests/cdn_integrity_spec.rb` → 0 failures
- [ ] **T24** MTTR computed in SQL → REQ-44
  - Files: lib/rails_error_dashboard/queries/mttr_stats.rb, spec/queries/mttr_stats_spec.rb
  - Test: spec/queries/mttr_stats_spec.rb:
    - a fixture with known durations gives the same overall, by-platform, by-severity and weekly values
      as rc.1's code;
    - no `ErrorLog` is instantiated.
  - After: none
  - Done when: `rspec spec/queries` → 0 failures, here and on the PostgreSQL and MySQL adapter jobs in CI
- [ ] **T25** Filter options cached per application → REQ-45
  - Files: lib/rails_error_dashboard/queries/filter_options.rb, spec/queries/filter_options_spec.rb
  - Test: spec/queries/filter_options_spec.rb:
    - a second call inside 5 minutes runs no query;
    - `AnalyticsCacheManager.clear` makes the next call query;
    - a capture does not;
    - a cache store that raises falls back to the query.
  - After: none
  - Done when: `rspec spec/queries` → 0 failures
- [ ] **T26** Local-variable capture skips frames by location → REQ-46
  - Files: lib/rails_error_dashboard/services/local_variable_capturer.rb, spec/services/local_variable_capturer_spec.rb
  - Test: spec/services/local_variable_capturer_spec.rb:
    - `Rails.root/app/ruby/x.rb` and a root path containing `rails_error_dashboard` are captured;
    - a gem path, `Rails.root/vendor/`, RED's `Engine.root` and a path outside the root are skipped.
  - After: none
  - Done when: `rspec spec/services` → 0 failures; `bin/benchmark` capture median within 0.2 ms of rc.1's
- [ ] **T27** The built-in plugins call themselves examples → REQ-47
  - Files: lib/rails_error_dashboard/plugins/audit_log_plugin.rb, lib/rails_error_dashboard/plugins/metrics_plugin.rb, lib/rails_error_dashboard/plugins/jira_integration_plugin.rb, docs/PLUGIN_SYSTEM.md, spec/lib/rails_error_dashboard/example_plugins_spec.rb
  - Test: spec/lib/rails_error_dashboard/example_plugins_spec.rb: each `description` starts with "Example:"
  - After: T8
  - Done when: `rspec spec/lib` → 0 failures; PLUGIN_SYSTEM.md no longer shows the Jira plugin registered in production

## Migrations
- [ ] **T28** Repair an invalid group-identity index on PostgreSQL → REQ-48
  - Files: db/migrate/20261121000002_repair_group_identity_index.rb, spec/migrations/repair_group_identity_index_spec.rb
  - Test: spec/migrations/repair_group_identity_index_spec.rb, PostgreSQL only and skipped elsewhere:
    - an index forced invalid (`UPDATE pg_index SET indisvalid = false`) is rebuilt valid, with
      duplicates merged;
    - a second run changes nothing;
    - on SQLite and MySQL it does nothing.
  - After: T20
  - Done when: `rspec spec/migrations` → 0 failures locally and on CI's PostgreSQL adapter job
- [ ] **T29** New index migrations build concurrently on PostgreSQL → REQ-49
  - Files: spec/migrations/concurrent_index_spec.rb
  - Test: spec/migrations/concurrent_index_spec.rb scans `db/migrate/` for files after `20261015000002`, the last in rc.1:
    each `add_index` on a table the file doesn't create needs `algorithm: :concurrently` and
    `disable_ddl_transaction!`. A fixture string without them fails.
  - After: T28
  - Done when: `rspec spec/migrations/concurrent_index_spec.rb` → 0 failures

## Host conditions (after S1's amendment)
- [ ] **T30** Captures survive a host rollback and prevented writes, and give up on a starved pool → REQ-17, REQ-18, REQ-19, REQ-20, REQ-22
  - Files: lib/rails_error_dashboard/configuration.rb, docs/guides/CONFIGURATION.md, docs/PUBLIC_API.md, app/models/rails_error_dashboard/error_logs_record.rb, lib/rails_error_dashboard/engine.rb, lib/rails_error_dashboard/commands/log_error.rb, spec/integration/host_conditions_spec.rb
  - Test: spec/integration/host_conditions_spec.rb, sync and async:
    - a report inside `transaction { …; raise ActiveRecord::Rollback }` is stored;
    - one inside `while_preventing_writes` is stored;
    - a `StatementInvalid` or `ReadOnlyError` on RED's INSERT drops it without raising;
    - with RED's pool held, the capture returns within `capture_connection_timeout` plus 50 ms, stores
      nothing, and makes one attempt;
    - with `isolate_capture_writes = false`, the rc.1 behaviour comes back.
    The file list and names follow S1's amendment.
  - After: T1, T13, T20
  - Done when:
    - `RAILS_VERSION=7.2`, `8.0` and `8.1` `rspec spec/integration/host_conditions_spec.rb` → 0 failures
      each on SQLite locally;
    - the same against the local PostgreSQL 16 and MySQL services (`DATABASE_URL` as in `test.yml`'s adapter
      job), on all three Rails versions;
    - `bin/benchmark` capture median within 0.2 ms of rc.1's.
    CI proves the 9 combinations in T31. The existing adapter jobs run Rails 8.1 only (`test.yml:104`).
- [ ] **T31** A chaos target for host conditions on every database and Rails version → REQ-50
  - Files: bin/pre-release-test, test/pre_release/chaos/phase_q_host_conditions.rb, .github/workflows/test.yml
  - Test: test/pre_release/chaos/phase_q_host_conditions.rb covers:
    - one error from two release directories gives one group;
    - a report in a rolled-back transaction is kept;
    - a report under `while_preventing_writes` is kept;
    - a report with RED's pool held returns fast.
  - After: T30
  - Done when:
    - `HOST_DATABASE=<db> RAILS_VERSION=<rails> bin/pre-release-test full_host_conditions` passes locally for
      each of `sqlite`, `postgresql` and `mysql` with each of `7.2`, `8.0` and `8.1`;
    - the CI job's 9 rows (database by Rails, with `test.yml`'s `postgres:16` and `mysql:8.4` services) are
      green.

## After the gate
Release steps, not tasks: each needs the maintainer's yes.

- Turn on "required reviewers" for the `rubygems` environment, with the maintainer as reviewer. Read the
  setting back.
- Run `bin/pre-release-test all` and the upgrade matrix on the rc.2 head.
- Merge a commit whose body has `Release-As: 1.0.0-rc.2`. The release PR body notes that a manual
  `gem push` now needs MFA.
- Merge the release PR, approve the `rubygems` deployment, and check RubyGems, the tag and the GitHub
  release, marked prerelease.
- Dispatch the demo's update workflow with `1.0.0.pre.rc.2`.
- If anything missed 2026-12-11, cut rc.3 by 2026-12-17 the same way.
- After about two quiet weeks, 1.0.0 with `Release-As: 1.0.0`, by 2026-12-31.
