# Tasks: Host and dependency hygiene for 0.17.0

Test first in every task: the cited test fails before the change and passes after it. Every test
cites `host-hygiene-0-17/REQ-N`. One commit per task, test and code together.

`R` below stands for `env -u RAILS_VERSION bin/with-ruby bundle exec`. The shell exports a stale
`RAILS_VERSION` that re-pins the lockfile. Run one rspec process at a time.

- [x] **T1** The dashboard's own session middleware → REQ-2, REQ-3, REQ-4
  - Files: lib/rails_error_dashboard/middleware/dashboard_session.rb, lib/rails_error_dashboard.rb, spec/lib/rails_error_dashboard/middleware/dashboard_session_spec.rb
  - Test: dashboard_session_spec, with an env built from `Rails.application.env_config`:
    - with no session in the request, the app below sees a working session, and the response sets
      `_rails_error_dashboard_session`;
    - with an enabled host session already in the request, the app below sees that same object, and
      no RED cookie is set;
    - with Rails' disabled placeholder in the request (an earlier `request.session` read), RED's
      session is used anyway;
    - `request.flash` works below it
  - After: none
  - Done when: `R rspec spec/lib/rails_error_dashboard/middleware/dashboard_session_spec.rb` → 0 failures
- [x] **T2** Session middleware on the engine's stack, not the host's → REQ-1
  - Files: lib/rails_error_dashboard/engine.rb, spec/lib/rails_error_dashboard/engine_api_host_middleware_spec.rb
  - Test: engine_api_host_middleware_spec, with the initializer run against a stand-in:
    - an API-only app's middleware receives nothing from RED's session code;
    - the engine's stack receives `DashboardSession`;
    - a full-stack app gets neither
  - After: T1
  - Done when: `R rspec spec/lib/rails_error_dashboard/engine_api_host_middleware_spec.rb` → 0 failures
- [ ] **T3** An API-only chaos app → REQ-1, REQ-2
  - Files: bin/pre-release-test, test/pre_release/templates/full_api_initializer.rb, test/pre_release/chaos/phase_p_api_host.rb, lefthook.yml, .claude/skills/release/SKILL.md
  - Test: Phase P in `full_api`:
    - a host endpoint gives no `Set-Cookie`;
    - a session-writing host endpoint answers 500, and RED records `DisabledSessionError`;
    - the dashboard sets `_rails_error_dashboard_session`;
    - a CSRF-protected `update_status` with the page's token redirects, and the next page shows its
      notice;
    - the language picker switches the page's `lang`.

    Red first: run it with T2's engine change reverted, and P1 fails.
  - After: T2
  - Done when: `env -u RAILS_VERSION bin/with-ruby bin/pre-release-test full_api` → FINAL RESULTS: 0 failed
- [ ] **T4** Load only files the npm packages publish, and keep a copy of each → REQ-6, REQ-7
  - Files: app/views/layouts/rails_error_dashboard.html.erb, spec/requests/cdn_integrity_spec.rb, spec/support/vendor/, spec/support/capybara.rb, docs/guides/ERROR_TREND_VISUALIZATIONS.md, _guides/error-trend-visualizations.md
  - Test: cdn_integrity_spec:
    - every jsDelivr URL on a dashboard page is `npm/<package>@<x.y.z>/…`, with no `gh/` and no
      version range;
    - each one has a vendored copy in `spec/support/vendor/`
  - After: none
  - Done when: `R rspec spec/requests/cdn_integrity_spec.rb spec/system/chart_date_locale_spec.rb` → 0 failures
- [ ] **T5** Integrity on every CDN tag, checked against the copies → REQ-5, REQ-7
  - Files: app/views/layouts/rails_error_dashboard.html.erb, spec/requests/cdn_integrity_spec.rb, bin/pre-release-test
  - Test: cdn_integrity_spec:
    - every off-site `<script src>` and stylesheet `<link>` except Google Fonts has `integrity` and
      `crossorigin="anonymous"`;
    - each integrity value equals `sha384-` plus the base64 SHA-384 of its vendored copy.

    `release_audit` compares the same values with the live files.
  - After: T4, T3
  - Done when: `R rspec spec/requests/cdn_integrity_spec.rb` → 0 failures, and `R rspec spec/system/` → 0 failures
- [ ] **T6** A concurrent-ruby floor and a true comment → REQ-8, REQ-9
  - Files: rails_error_dashboard.gemspec, spec/gemspec_dependencies_spec.rb
  - Test: gemspec_dependencies_spec: the concurrent-ruby requirement rejects 1.3.6 and 2.0.0, and
    accepts 1.3.7 and 1.4.0
  - After: none
  - Done when: `R rspec spec/gemspec_dependencies_spec.rb` → 0 failures, then `env -u RAILS_VERSION bin/with-ruby bundle install` and `R bundle-audit check` → no vulnerabilities
- [ ] **T7** `CLAUDE.md` and the FAQ → REQ-9
  - Files: CLAUDE.md, docs/FAQ.md, _reference/faq.md
  - Test: none (prose; REQ-9 is `[untested]`). `CLAUDE.md` goes through `/shipkit:update-rules`.
  - After: T5
  - Done when: CLAUDE.md lists the nine CDN files and the six chaos apps, rule 5 requires pinned
    tags, and both FAQ copies say the dashboard works inside an API-only app

## After the gate
- Full suite, RuboCop on tracked files, and `env -u RAILS_VERSION bin/with-ruby bin/pre-release-test all` (read FINAL RESULTS: 6 apps).
- Runtime proof in the API lab app (gem by path): `/touch_session` answers 500 again, and `/red` logs
  in and sets `_rails_error_dashboard_session`.
- The shipkit reviewer, re-run after every fix round until it passes.
- One PR, public wording, with `BEGIN_COMMIT_OVERRIDE` so each fix is its own changelog line. Merge
  only with the user's OK.
- The 0.17.0 release notes carry the three lines from `design.md`.
