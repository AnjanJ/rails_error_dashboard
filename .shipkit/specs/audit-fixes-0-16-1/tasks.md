# Tasks: Audit fixes for 0.16.1

Every new example cites `audit-fixes-0-16-1/REQ-N` in its name. Commands run in the normal
checkout as `env -u RAILS_VERSION mise exec ruby@3.4.5 -- bundle exec rspec …`. Score tests keep
velocity at or below 10 (all events in the window's first half), so the Healthy threshold is the
only thing under test.

- [ ] **T1** Score and card only active platforms → REQ-8
  - Files: lib/rails_error_dashboard/queries/platform_comparison.rb, spec/lib/rails_error_dashboard/queries/platform_comparison_spec.rb, spec/requests/platform_health_cards_spec.rb
  - Test: platform_comparison_spec "audit-fixes-0-16-1/REQ-8 scores no platform without errors in the window", and platform_health_cards_spec "…/REQ-8 shows no card for it on the Overview or Platform Comparison".
  - After: none
  - Done when: both fail before the change (a 100/Healthy card for the inactive platform) and pass after.
- [ ] **T2** Volume credit against an even split → REQ-1, REQ-2, REQ-3
  - Files: lib/rails_error_dashboard/queries/platform_comparison.rb, spec/lib/rails_error_dashboard/queries/platform_comparison_spec.rb
  - Test: "audit-fixes-0-16-1/REQ-1 rates equal platforms Healthy with equal scores", "…/REQ-2 gives full volume credit at or below an even split", "…/REQ-3 gives a larger share less credit" (60/40 → 86 and 90/10 → 44 at full resolution credit).
  - After: T1
  - Done when: `bundle exec rspec spec/lib/rails_error_dashboard/queries/platform_comparison_spec.rb` → 0 failures; the REQ-1 example scored 65 before.
- [ ] **T3** Resolution credit against the fastest, floored at one hour → REQ-4, REQ-5
  - Files: lib/rails_error_dashboard/queries/platform_comparison.rb, spec/lib/rails_error_dashboard/queries/platform_comparison_spec.rb
  - Test: "audit-fixes-0-16-1/REQ-4 gives the fastest and any as fast full credit", "…/REQ-5 rates 12h against 10h Healthy at an even share" (95), and a floor example where one platform averages 0.0 h.
  - After: T2
  - Done when: `bundle exec rspec spec/lib/rails_error_dashboard/queries/platform_comparison_spec.rb` → 0 failures; the REQ-5 platform scored at most 70 before.
- [ ] **T4** Nothing resolved: volume alone, labelled → REQ-6, REQ-7
  - Files: lib/rails_error_dashboard/queries/platform_comparison.rb, spec/lib/rails_error_dashboard/queries/platform_comparison_spec.rb, app/views/rails_error_dashboard/errors/overview.html.erb, app/views/rails_error_dashboard/errors/platform_comparison.html.erb, config/locales/en.yml, config/locales/de.yml, config/locales/es.yml, config/locales/fr.yml, config/locales/it.yml, config/locales/ja.yml, config/locales/pl.yml, config/locales/pt-BR.yml, config/locales/ru.yml, config/locales/uk.yml, config/locales/zh-CN.yml, spec/requests/platform_health_cards_spec.rb
  - Test: platform_comparison_spec "audit-fixes-0-16-1/REQ-6 scores a platform with nothing resolved on volume alone" (it got the full 30 points before), and platform_health_cards_spec "…/REQ-7 says no errors from this period were resolved, on both pages".
  - After: T3
  - Done when: both specs → 0 failures; `bin/i18n-check` (lefthook's i18n-check) passes for the new key in all eleven locales.
- [ ] **T5** Business-hours copy matches the detector → REQ-10
  - Files: config/locales/en.yml, config/locales/de.yml, config/locales/es.yml, config/locales/fr.yml, config/locales/it.yml, config/locales/ja.yml, config/locales/pl.yml, config/locales/pt-BR.yml, config/locales/ru.yml, config/locales/uk.yml, config/locales/zh-CN.yml, spec/lib/rails_error_dashboard/business_hours_copy_spec.rb
  - Test: business_hours_copy_spec "audit-fixes-0-16-1/REQ-10 states 9:00-17:59 in every locale" (reads each locale's `red.errors.patterns.types.business_hours.description` and the detector's range).
  - After: T4
  - Done when: the spec fails on all eleven locales before and passes after; `bin/i18n-check` passes.
- [ ] **T6** Platform names as stored → REQ-11
  - Files: app/views/rails_error_dashboard/errors/platform_comparison.html.erb, app/views/rails_error_dashboard/errors/correlation.html.erb, spec/requests/platform_names_display_spec.rb
  - Test: platform_names_display_spec "audit-fixes-0-16-1/REQ-11 shows iOS and API as stored on Platform Comparison and Correlation" (no "Ios", "Api" or `text-capitalize` on a platform name).
  - After: T4
  - Done when: `bundle exec rspec spec/requests/platform_names_display_spec.rb` → 0 failures; it fails before.
- [ ] **T7** Docs and the 0.16.0 amendment → REQ-9
  - Files: docs/features/PLATFORM_COMPARISON.md, _features/platform-comparison.md, docs/GLOSSARY.md, _reference/glossary.md, docs/FEATURES.md, _getting_started/features.md, .shipkit/specs/audit-fixes-0-16-0/design.md, spec/requests/analytics_reports_i18n_spec.rb
  - Test: none, REQ-9 is prose (`[untested]`). The worked example is checked against T2–T4's specs by recomputing it, and `spec/docs/links_spec.rb` stays green.
  - After: T4
  - Done when: `bundle exec rspec spec/docs/links_spec.rb --example "Documentation links"` → 0 failures; the full suite → 0 failures, RuboCop clean.

## After the gate
- The 0.16.1 release notes say the platform scores change again, and why.
- A manual look at Platform Comparison and the Overview with three seeded platforms.
