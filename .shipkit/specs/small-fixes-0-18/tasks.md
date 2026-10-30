# Tasks: Smaller fixes for 0.18.0

Test first in every task: the cited test fails before the change and passes after it. Every test
cites `small-fixes-0-18/REQ-N`. One commit per task, test and code together.

`R` below stands for `env -u RAILS_VERSION bin/with-ruby bundle exec`. Run one rspec process at a
time. This spec's PR comes after `deprecations-0-18`: both touch UPGRADING.

- [x] **T1** Crash sources leave every platform list → REQ-1, REQ-2
  - Files: app/models/rails_error_dashboard/error_log.rb, lib/rails_error_dashboard/services/crash_capture.rb, lib/rails_error_dashboard/queries/filter_options.rb, lib/rails_error_dashboard/queries/error_correlation.rb, lib/rails_error_dashboard/queries/mttr_stats.rb, lib/rails_error_dashboard/queries/platform_comparison.rb, lib/rails_error_dashboard/queries/dashboard_stats.rb, lib/rails_error_dashboard/queries/analytics_stats.rb, lib/rails_error_dashboard/queries/baseline_stats.rb, spec/lib/rails_error_dashboard/queries/crash_platforms_spec.rb
  - Test: crash_platforms_spec, with errors on `iOS`, `API`, a NULL platform, `boot_crash` and
    `crash_capture`:
    - none of the seven queries returns either crash value as a platform;
    - the NULL-platform error still counts where it counts today;
    - `Queries::BootErrors` and the error list still return both crash errors
  - After: none
  - Done when: `R rspec spec/lib/rails_error_dashboard/queries` → 0 failures
- [x] **T2** Platform badges match in any case, from one helper → REQ-3
  - Files: app/helpers/rails_error_dashboard/application_helper.rb, app/views/rails_error_dashboard/errors/_error_row.html.erb, app/views/rails_error_dashboard/errors/_timeline.html.erb, app/views/rails_error_dashboard/errors/_similar_errors.html.erb, app/views/rails_error_dashboard/errors/_sidebar_metadata.html.erb, spec/helpers/platform_badge_spec.rb
  - Test: platform_badge_spec:
    - `ios`, `IOS`, `iOS` → the iOS badge;
    - the same for `android` and `web`;
    - `API` and `Mobile` keep the grey badge with their own text;
    - each of the four partials renders through the helper
  - After: none
  - Done when: `R rspec spec/helpers/platform_badge_spec.rb` → 0 failures
- [x] **T3** Pattern hours in `Time.zone`, labelled → REQ-5
  - Files: lib/rails_error_dashboard/queries/analytics_stats.rb, lib/rails_error_dashboard/services/pattern_detector.rb, app/views/rails_error_dashboard/errors/_pattern_insights.html.erb, config/locales/, spec/lib/rails_error_dashboard/services/pattern_detector_spec.rb, spec/views/rails_error_dashboard/errors/_pattern_insights.html.erb_spec.rb
  - Test: pattern_detector_spec, with `Time.zone = "Asia/Kolkata"`:
    - an error at 08:00 UTC lands in hour 13;
    - the rendered insights name the zone next to the heatmap and the peak hours;
    - the new key exists in all 11 locales (`bin/i18n-check`)
  - After: T1
  - Done when: `R rspec spec/lib/rails_error_dashboard/services/pattern_detector_spec.rb` → 0 failures, and `bin/i18n-check` exits 0
- [ ] **T4** Reproduce development 404s; fix only if real → REQ-4, REQ-6
  - Files: spec/requests/development_routing_error_spec.rb, .shipkit/specs/small-fixes-0-18/intake.md
  - Test: development_routing_error_spec runs the dummy app with reloading on and
    `show_exceptions = :all`, and again with production's settings. In each, a request for an
    unknown URL is made, and the spec asserts RED records it in neither.
    - **If it passes on today's code,** REQ-4 and REQ-6 are dropped, and `intake.md` records the
      evidence: this spec stays as the regression guard.
    - **If it fails,** a follow-up task is added here, with its design record, before any fix.
  - After: none
  - Done when: `R rspec spec/requests/development_routing_error_spec.rb` → 0 failures, and `intake.md` records the outcome
