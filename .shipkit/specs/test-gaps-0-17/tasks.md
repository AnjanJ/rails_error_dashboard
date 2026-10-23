# Tasks: test gaps for 0.17.0

Every guard gets a revert-one proof: break the behaviour it guards, watch it fail, restore. Where
the behaviour already works (most of this spec adds tests for working code), that proof stands in
for "red first". Specs run as `env -u RAILS_VERSION bin/with-ruby bundle exec rspec <files>`, one
process at a time.

- [ ] **T1** Concurrent captures keep one row with the right count → REQ-1
  - Files: spec/commands/find_or_increment_error_spec.rb
  - Test: spec/commands/find_or_increment_error_spec.rb "concurrent captures on separate connections" (replaces the two "locking" examples)
  - After: none
  - Done when: `DATABASE_URL="postgres://localhost/red_verify_test?pool=25" … rspec spec/commands/find_or_increment_error_spec.rb` → all pass; with `.lock` removed from `find_unresolved` the new example fails; on SQLite it is pending with the reason
- [ ] **T2** A raising breadcrumb handler never breaks the instrumented block → REQ-2
  - Files: spec/lib/rails_error_dashboard/subscribers/breadcrumb_subscriber_spec.rb
  - Test: breadcrumb_subscriber_spec.rb "never raises from subscribers, even when a handler raises" (all seven events)
  - After: none
  - Done when: `… rspec spec/lib/rails_error_dashboard/subscribers/breadcrumb_subscriber_spec.rb` → all pass; with one subscriber's `rescue` removed, that event's example fails
- [ ] **T3** Exit and end-of-work drains run in a booted process → REQ-3, REQ-4
  - Files: spec/lib/rails_error_dashboard/engine_drains_spec.rb
  - Test: engine_drains_spec.rb (one child boot; exit drains, end-of-work drains, crash drain last)
  - After: none
  - Done when: `… rspec spec/lib/rails_error_dashboard/engine_drains_spec.rb` → all pass; removing any one drain registration in `engine.rb` (or the boot-time crash hook) makes it fail
- [ ] **T4** Phase F asserts what Rails does → REQ-5, REQ-6, REQ-7
  - Files: test/pre_release/chaos/phase_f_http_error_capture.rb
  - Test: phase_f_http_error_capture.rb: the endpoint checks' controller and action names, the Timeout check, the three mapped-status checks (status + no row), the request-context names
  - After: none
  - Done when: `env -u RAILS_VERSION bin/with-ruby bin/pre-release-test full_http` → FINAL RESULTS all passed, no `assert …, true` left in phase F; with the chaos app's Timeout severity rule changed, the Timeout check fails
- [ ] **T5** The TracePoint features run in the HTTP chaos app → REQ-8, REQ-9, REQ-10, REQ-11
  - Files: test/pre_release/templates/full_http_initializer.rb, bin/pre-release-test, test/pre_release/chaos/phase_f_http_error_capture.rb, test/pre_release/chaos/phase_d_http_endpoints.rb
  - Test: phase F checks for locals, instance variables and the swallowed row; phase D's swallowed-page check
  - After: T4
  - Done when: `… bin/pre-release-test full_http` and `… full_api` → both all passed; with the three features off in the template, the new phase F and phase D checks fail
- [ ] **T6** The second app replays all its migrations, and the first app's rows survive → REQ-12, REQ-13
  - Files: bin/pre-release-test, test/pre_release/chaos/phase_i_multi_app.rb
  - Test: multi-app run's checked migrate steps and version check; phase I's snapshot comparison
  - After: T5
  - Done when: `… bin/pre-release-test full_multi_app` → all passed with all 52 of Beta's versions recorded; a scratch migration that NULLs `environment` makes phase I fail; a migration that raises makes the migrate step fail the run
- [ ] **T7** The upgrade check shows Skipped when there is nothing to test → REQ-14, REQ-15
  - Files: .github/workflows/ci.yml, spec/ci/workflows_spec.rb
  - Test: workflows_spec.rb "the upgrade job runs only when the changes job says so"
  - After: none
  - Done when: `… rspec spec/ci/workflows_spec.rb` → all pass; this PR's CI shows "Upgrade Path" as Skipped (it touches no migration)
- [ ] **T8** Every action is pinned, and today's zizmor and actionlint findings are fixed → REQ-19
  - Files: .github/workflows/ci.yml, .github/workflows/test.yml, .github/workflows/pages.yml, .github/workflows/smoke-test-demo.yml, .github/workflows/release.yml, spec/ci/workflows_spec.rb
  - Test: workflows_spec.rb "pins every action in every workflow to a full commit SHA"
  - After: T7
  - Done when: `… rspec spec/ci/workflows_spec.rb` → all pass; `actionlint` exits 0; `zizmor --min-severity low .github/workflows/` (online, `GH_TOKEN` set) exits 0
- [ ] **T9** The `audit` job fails on an advisory, an actionlint error or a zizmor finding → REQ-16, REQ-17, REQ-18
  - Files: .github/workflows/ci.yml, spec/ci/workflows_spec.rb
  - Test: workflows_spec.rb "the audit job" examples
  - After: T8
  - Done when: `… rspec spec/ci/workflows_spec.rb` → all pass; locally, the job's three commands each exit non-zero on a scratch copy with a vulnerable gem pin, a broken workflow and an unpinned action; the job passes on this PR
- [ ] **T10** The pre-commit hook runs every staged spec → REQ-21
  - Files: lefthook.yml, spec/ci/lefthook_spec.rb
  - Test: spec/ci/lefthook_spec.rb "passes the staged spec files straight to rspec"
  - After: none
  - Done when: `… rspec spec/ci/lefthook_spec.rb` → passes; staging two scratch specs outside `spec/`, one failing, and running `lefthook run pre-commit --command rspec-changed` → exit 1 with both files run

## After the gate
- Full suite once (baseline 6091/0/2), chaos `all`, `full_multi_app`; the shipkit reviewer re-run
  after every fix round until PASS.
- Push over HTTPS, open the PR, CI green, merge with the maintainer's OK.
- REQ-20: after the push run on main passes, add the 13 missing contexts to the "Protect main
  branch" ruleset (names copied from that run's check runs), with the maintainer's OK, and read it
  back.
- Docs: the PR-check count becomes 29.
