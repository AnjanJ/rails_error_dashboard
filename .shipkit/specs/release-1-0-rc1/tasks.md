# Tasks: 1.0.0.rc1

Six pull requests, in order: T1-T3 (the floors), T4-T9 (capture after the response and the budgets),
T10-T11 (the upgrade matrix), T12-T14 (the docs and the stats partial), T15 (the prerelease flag), then
T16-T17 in the demo's repository. T6-T9 wait for `deploy-shape-benchmark` to finish, because they change
its rows. Code tasks write their test first, and cite `release-1-0-rc1/REQ-N`.
Commands below stand for `env -u RAILS_VERSION mise exec ruby@3.4.5 -- bundle exec rspec`.

- [x] **T1** The gemspec requires Rails 7.2 and Ruby 3.3 → REQ-1
  - Files: rails_error_dashboard.gemspec, Gemfile, spec/lib/rails_error_dashboard/floors_spec.rb
  - Test: spec/lib/rails_error_dashboard/floors_spec.rb reads the gemspec's `required_ruby_version` and its `rails` dependency
  - After: none
  - Done when: `rspec spec/lib/rails_error_dashboard/floors_spec.rb` → 0 failures; the Gemfile no longer selects sqlite3 `~> 1.4` for Rails 7.0
- [x] **T2** CI runs 9 rows, each Ruby named by its series → REQ-2
  - Files: .github/workflows/test.yml, spec/ci/workflows_spec.rb
  - Test: spec/ci/workflows_spec.rb asserts the matrix is Ruby 3.3, 3.4 and 4.0 by Rails 7.2, 8.0 and 8.1, with no patch release named
  - After: T1
  - Done when: `rspec spec/ci/workflows_spec.rb` → 0 failures; the pull request's CI shows 9 test rows, all green
- [x] **T3** Remove every branch for Rails before 7.2 or Ruby before 3.3, and keep the `0004` no-ops → REQ-3, REQ-4
  - Files: Gemfile, lib/rails_error_dashboard/configuration.rb, lib/rails_error_dashboard/middleware/error_catcher.rb, lib/rails_error_dashboard/services/live_stream_token.rb, lib/rails_error_dashboard/services/swallowed_exception_tracker.rb, lib/rails_error_dashboard/services/coverage_tracker.rb, lib/generators/rails_error_dashboard/install/install_generator.rb, app/jobs/rails_error_dashboard/application_job.rb, app/controllers/rails_error_dashboard/application_controller.rb, app/controllers/rails_error_dashboard/errors_controller.rb, spec/lib/rails_error_dashboard/floors_spec.rb, spec/lib/rails_error_dashboard/configuration_validation_spec.rb, spec/lib/rails_error_dashboard/deprecated_options_spec.rb
  - Test: spec/lib/rails_error_dashboard/floors_spec.rb scans lib/ and app/ for a version check below the floors (the Rails 7.0.10 and Rails/Ruby floor warnings, `RUBY_VERSION < "3.3"`); spec/lib/rails_error_dashboard/deprecated_options_spec.rb keeps both setters warning
  - After: T2
  - Done when: `rspec` → 0 failures on Ruby 3.4 with Rails 8.1; the json pin check for Rails 7.2 before 7.2.4 and 8.0 stays, since both are still supported
- [x] **T4** Async capture enqueues from `rack.response_finished` when the env has it → REQ-5, REQ-6, REQ-7
  - Files: lib/rails_error_dashboard/commands/log_error.rb, spec/commands/log_error_after_response_spec.rb
  - Test: spec/commands/log_error_after_response_spec.rb: with the env's array present, no job is enqueued until the callbacks run, then one is; with no env, or no array, the job is enqueued at once; an enqueue that raises or returns false inside the callback logs the error synchronously and raises nothing; a second request on the same thread doesn't reuse the first's env
  - After: none
  - Done when: `rspec spec/commands` → 0 failures; with the deferral reverted, the after-response examples fail
- [x] **T5** A real Puma runs the callback, and the error is recorded → REQ-5
  - Files: test/pre_release/chaos/phase_f_http_error_capture.rb
  - Test: phase F asserts that a failing request's response comes back before its job is enqueued, and that the error's row then appears
  - After: T4
  - Done when: `bin/pre-release-test full_async` and `bin/pre-release-test full_http` pass
- [x] **T6** The "Capture, async" row times the work before the response → REQ-8
  - Files: benchmark/scenarios.rb, spec/benchmark/scenarios_spec.rb
  - Test: spec/benchmark/scenarios_spec.rb asserts the row runs capture under an env with an empty `rack.response_finished` array, and leaves the callbacks unrun inside the timed block
  - After: T4
  - Done when: `rspec spec/benchmark` → 0 failures
- [x] **T7** A reported row times the work after the response → REQ-9
  - Files: benchmark/scenarios.rb, spec/benchmark/scenarios_spec.rb
  - Test: spec/benchmark/scenarios_spec.rb asserts "Capture, async, after the response" exists, has no budget, and times running the callbacks
  - After: T6
  - Done when: `rspec spec/benchmark` → 0 failures; `bin/benchmark` prints both rows
- [x] **T8** The health snapshot is gated at 1.5 ms → REQ-11
  - Files: benchmark/scenarios.rb, spec/benchmark/scenarios_spec.rb
  - Test: spec/benchmark/scenarios_spec.rb asserts the health snapshot row's budget is 1.5 ms
  - After: T7
  - Done when: `rspec spec/benchmark` → 0 failures; CI's `Overhead benchmark` passes
- [x] **T9** Re-run the shapes with the database 1 ms away, and write the budgets down → REQ-10, REQ-12
  - Files: .shipkit/research/deploy-shape-benchmark.md, .shipkit/product.md, .claude/skills/host-app-safety/SKILL.md, .claude/skills/safety-check/SKILL.md, README.md, docs/FEATURES.md, lib/generators/rails_error_dashboard/install/templates/initializer.rb
  - Test: none, prose and dispatches verified by reading
  - After: T8
  - Done when: a dispatch of each shape on main shows "Capture, async" under 5 ms with "1 ms set", its run recorded in the research file; the five files state the same budgets
- [ ] **T10** The upgrade test takes a from-version and a database → REQ-13
  - Files: bin/pre-release-test, test/pre_release/chaos/phase_j0_seed_old_data.rb, test/pre_release/chaos/phase_j_upgrade_verification.rb
  - Test: `bin/pre-release-test full_upgrade` with `UPGRADE_FROM_VERSION=0.1.38` on SQLite, and with the oldest and newest minors on PostgreSQL and MySQL, locally
  - After: none
  - Done when: the runs above pass; with no settings it still starts from the latest release on SQLite, as the PR job expects
- [ ] **T11** A dispatch-only workflow upgrades from every 0.x minor on all three databases → REQ-13, REQ-14
  - Files: .github/workflows/upgrade-matrix.yml, spec/ci/workflows_spec.rb
  - Test: spec/ci/workflows_spec.rb asserts the workflow is dispatch-only with a read-only token and no secrets, joins `hardened_workflows`, and runs three databases
  - After: T3, T10
  - Done when: `rspec spec/ci/workflows_spec.rb` → 0 failures; after it lands, a dispatch on main runs 54 rows, all green
- [ ] **T12** The upgrading guide gets "0.x to 1.0" → REQ-15
  - Files: docs/UPGRADING.md, _getting_started/upgrading.md
  - Test: none, prose verified by reading
  - After: T11
  - Done when: the section names the floors, every removal, the stats partial and the steps, and both copies match
- [ ] **T13** The docs drop "Beta" and state the floors → REQ-20, REQ-21
  - Files: README.md, docs/FAQ.md, docs/CUSTOMIZATION.md, ROADMAP.md, .shipkit/product.md, spec/docs/floors_doc_spec.rb
  - Test: spec/docs/floors_doc_spec.rb asserts no doc calls RED beta, and the README and FAQ state Rails 7.2 to 8.1 and Ruby 3.3 to 4.0
  - After: T9
  - Done when: `rspec spec/docs` → 0 failures; `severity_calculator` is no longer "planned", and ROADMAP's header names the current version
- [ ] **T14** Delete the stats partial, its view spec and its keys → REQ-22
  - Files: app/views/rails_error_dashboard/errors/_stats.html.erb, spec/views/rails_error_dashboard/errors/_stats.html.erb_spec.rb, config/locales/de.yml, config/locales/en.yml, config/locales/es.yml, config/locales/fr.yml, config/locales/it.yml, config/locales/ja.yml, config/locales/pl.yml, config/locales/pt-BR.yml, config/locales/ru.yml, config/locales/uk.yml, config/locales/zh-CN.yml
  - Test: none, a deletion; `bin/i18n-check` and the view specs show it
  - After: none
  - Done when: `bin/i18n-check` reports no orphaned keys; `rspec spec/views` → 0 failures; `git grep -n "errors/stats" -- app lib` prints nothing
- [ ] **T15** Mark a prerelease's GitHub release as a prerelease → REQ-16
  - Files: .release-please-config.json, spec/ci/workflows_spec.rb
  - Test: spec/ci/workflows_spec.rb asserts `"prerelease": true` in the config
  - After: T11
  - Done when: `rspec spec/ci/workflows_spec.rb` → 0 failures; it lands after 0.18.1 is published
- [ ] **T16** The demo's Gemfile accepts every 1.x release → REQ-19
  - Files: demo: Gemfile, demo: Gemfile.lock, demo: script/update_demo_release_test.rb
  - Test: demo: script/update_demo_release_test.rb asserts the requirement accepts 1.0.0 and 1.9.0 and refuses 2.0.0
  - After: none
  - Done when: the demo's CI passes, still on 0.18.x
- [ ] **T17** The demo's update workflow deploys a named prerelease by dispatch only → REQ-17, REQ-18
  - Files: demo: .github/workflows/update-demo-release.yml, demo: script/update_demo_release.rb, demo: script/update_demo_release_test.rb
  - Test: demo: script/update_demo_release_test.rb: a dispatch naming a prerelease writes it into the requirement and maps it to its tag; the schedule with a prerelease on RubyGems changes nothing
  - After: T16
  - Done when: the demo's tests pass; nothing is deployed until the release steps

## After the gate
Release steps, not tasks: each needs the maintainer's yes.

- Run the upgrade workflow on the release commit.
- Merge a commit whose body has `Release-As: 1.0.0-rc.1`, or the spelling the design gate chose, and check
  the release PR's `version.rb`, manifest and changelog.
- Merge the release PR, and check RubyGems, the tag and the GitHub release, marked prerelease.
- Dispatch the demo's update workflow with the version, and check the demo serves it.
- Open a GitHub discussion or issue asking early users to try it.
- After about two quiet weeks, run the upgrade workflow again, then 1.0.0 with `Release-As: 1.0.0`.
