# Tasks: Rails 7.0 request capture

Every new example cites `rails-70-request-capture/REQ-N` in its name. The 7.0 examples are
skipped unless `ActionPack.gem_version < 7.1`; REQ-9's are skipped on 7.0. Run them locally
both ways:
- **7.0 bundle:** a worktree with its own lockfile and a scratch `BUNDLE_PATH`, with
  `RAILS_VERSION=7.0`. Write it below as `<7.0 bundle> bundle exec rspec …`.
- **8.1 bundle:** the normal checkout, `env -u RAILS_VERSION mise exec ruby@3.4.5 -- bundle exec rspec …`.

- [ ] **T1** A raising route in the dummy app, and the 7.1+ guard → REQ-9
  - Files: spec/dummy/app/controllers/request_capture_test_controller.rb, spec/dummy/config/routes.rb, spec/requests/rails_70_request_capture_spec.rb
  - Test: spec/requests/rails_70_request_capture_spec.rb "rails-70-request-capture/REQ-9 records an unhandled request exception exactly once on Rails 7.1+". This guard holds today, so instead of failing first it is proven not vacuous: with the subscriber's dedup stubbed out it must fail.
  - After: none
  - Done when: `bundle exec rspec spec/requests/rails_70_request_capture_spec.rb` on the 8.1 bundle → 0 failures; the full suite stays green (the new route breaks no route or locale spec).
- [ ] **T2** Record what Rails 7.0 renders, with the request on the record → REQ-1, REQ-2, REQ-6
  - Files: lib/rails_error_dashboard/middleware/rendered_exception_reporter.rb, lib/rails_error_dashboard.rb, lib/rails_error_dashboard/engine.rb, spec/requests/rails_70_request_capture_spec.rb
  - Test: "rails-70-request-capture/REQ-1 records once with production settings", "…/REQ-2 records once with development settings", "…/REQ-6 records the URL, method, controller and action as a server capture", and "…/REQ-9 registers no interceptor on Rails 7.1+".
  - After: T1
  - Done when: on the 7.0 bundle, those examples fail before the change and pass after; on the 8.1 bundle the REQ-9 examples pass and the 7.0 ones are skipped.
- [ ] **T3** Never twice when show_exceptions is off → REQ-3
  - Files: lib/rails_error_dashboard/middleware/rendered_exception_reporter.rb, spec/requests/rails_70_request_capture_spec.rb
  - Test: "rails-70-request-capture/REQ-3 records once with show_exceptions off" (records 2 before the guard).
  - After: T2
  - Done when: `<7.0 bundle> bundle exec rspec spec/requests/rails_70_request_capture_spec.rb` → 0 failures.
- [ ] **T4** Skip rescue responses → REQ-4
  - Files: lib/rails_error_dashboard/middleware/rendered_exception_reporter.rb, spec/requests/rails_70_request_capture_spec.rb
  - Test: "rails-70-request-capture/REQ-4 records no RecordNotFound or RoutingError with show_exceptions on".
  - After: T3
  - Done when: `<7.0 bundle> bundle exec rspec spec/requests/rails_70_request_capture_spec.rb` → 0 failures.
- [ ] **T5** Nothing a rescue_from handles → REQ-5
  - Files: spec/dummy/app/controllers/request_capture_test_controller.rb, spec/requests/rails_70_request_capture_spec.rb
  - Test: "rails-70-request-capture/REQ-5 records nothing a rescue_from handles". Expected to pass on T2's code; proven not vacuous by its sibling action without rescue_from, which records.
  - After: T4
  - Done when: `<7.0 bundle> bundle exec rspec spec/requests/rails_70_request_capture_spec.rb` → 0 failures.
- [ ] **T6** The host's response is untouched, even when RED fails → REQ-7, REQ-8
  - Files: lib/rails_error_dashboard/middleware/rendered_exception_reporter.rb, spec/requests/rails_70_request_capture_spec.rb
  - Test: "rails-70-request-capture/REQ-7 sends the same status and body as without RED" (the response with the interceptor removed is the baseline) and "…/REQ-8 still sends Rails' error page when recording raises" (LogError stubbed to raise).
  - After: T5
  - Done when: `<7.0 bundle> bundle exec rspec spec/requests/rails_70_request_capture_spec.rb` → 0 failures; then the full suite on the 8.1 bundle → 0 failures, RuboCop clean.

## After the gate
Not tasks with tick boxes; they run once the reviewer passes the branch.
- A real Rails 7.0.8.7 production app via a new 7.0 row in the local
  `tasks/docs-audit/release_scenarios.sh` (`json < 3`, Rails in a scratch gem path): a raising
  route records once, a 404 and a `rescue_from` record nothing, and the page Rails renders is
  unchanged. The result goes in the 0.16.1 scenarios record.
- The 0.16.1 release notes say the 0.16.0 "Known limitation: Rails 7.0" is fixed.
