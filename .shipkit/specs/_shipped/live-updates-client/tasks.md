# Tasks: Live updates reach the browser

Test first in every task: the cited example fails before the change and passes after it. Every
example cites `live-updates-client/REQ-N`.

`R` below stands for `env -u RAILS_VERSION bin/with-ruby bundle exec`. The shell exports a stale
`RAILS_VERSION` that re-pins the lockfile. Run one rspec process at a time.

- [x] **T1** Add the switch and the boot warning → REQ-1, REQ-10
  - Files: lib/rails_error_dashboard/configuration.rb, spec/lib/rails_error_dashboard/configuration_spec.rb, spec/lib/rails_error_dashboard/configuration_validation_spec.rb
  - Test: configuration_spec "enable_live_updates defaults to false"; configuration_validation_spec "warns when live updates are on but Turbo or ActionCable is missing" (one example per missing piece, plus no warning when the switch is off)
  - After: none
  - Done when: `R rspec spec/lib/rails_error_dashboard/configuration_spec.rb spec/lib/rails_error_dashboard/configuration_validation_spec.rb` → 0 failures
- [x] **T2** Gate every broadcast on the switch; specs that assert real broadcasts opt in → REQ-2
  - Files: lib/rails_error_dashboard/services/error_broadcaster.rb, spec/lib/rails_error_dashboard/services/error_broadcaster_spec.rb, spec/requests/live_stream_delivery_spec.rb, spec/requests/live_stream_scoping_spec.rb
  - Test: error_broadcaster_spec "while enable_live_updates is false: available? is false and broadcast_new / broadcast_update / broadcast_stats send nothing" (with a reachable pubsub, so only the switch can explain the silence)
  - After: T1
  - Done when: `R rspec spec/lib/rails_error_dashboard/services/error_broadcaster_spec.rb spec/requests/live_stream_delivery_spec.rb spec/requests/live_stream_scoping_spec.rb` → 0 failures
- [x] **T3** Load the pinned client in `<head>` from the index only, with the cable meta tag → REQ-3, REQ-4, REQ-6, REQ-9
  - Files: app/helpers/rails_error_dashboard/application_helper.rb, app/views/layouts/rails_error_dashboard.html.erb, app/views/rails_error_dashboard/errors/index.html.erb, spec/requests/live_updates_client_spec.rb
  - Test: spec/requests/live_updates_client_spec.rb:
    - switch off: no `turbo-cable-stream-source`, no client script, no Live badge;
    - switch on and available: the client `<script type="module">` is in `<head>` with the pinned URL, `integrity` and `crossorigin="anonymous"`, and the cable meta tag is present;
    - the show page loads no client;
    - a custom `action_cable.url` appears in the meta tag
  - After: T2
  - Done when: `R rspec spec/requests/live_updates_client_spec.rb spec/requests/csp_compatibility_spec.rb spec/requests/errors_index_i18n_spec.rb` → 0 failures
- [x] **T4** Page scripts survive Turbo, and the browser half is proven → REQ-5, REQ-7, REQ-8, REQ-13
  - Files: app/views/layouts/rails_error_dashboard.html.erb, spec/support/capybara.rb, spec/support/vendor/turbo.js, spec/support/vendor/README.md, spec/system/live_updates_spec.rb, spec/helpers/application_helper_spec.rb
  - Test:
    - spec/system/live_updates_spec.rb, with the async adapter and the vendored client served under SRI:
      - a captured error's row appears without a reload;
      - clicking a local time switches to UTC;
      - a link does a full page load;
      - the streamed row's relative time is reformatted and toggles on click;
    - application_helper_spec "the vendored turbo.js hashes to the pinned integrity value"
  - After: T3
  - Done when: `R rspec spec/system/live_updates_spec.rb spec/helpers/application_helper_spec.rb` → 0 failures, and `R rspec spec/system/` → 0 failures
- [x] **T5** Installer template documents the switch → REQ-11
  - Files: lib/generators/rails_error_dashboard/install/templates/initializer.rb, spec/generators/install_generator_spec.rb
  - Test: install_generator_spec "the initializer sets enable_live_updates = false and names what live updates need"
  - After: none
  - Done when: `R rspec spec/generators/install_generator_spec.rb` → 0 failures
- [x] **T6** Docs and mirrors describe live updates as opt-in → REQ-12
  - Files: docs/guides/REAL_TIME_UPDATES.md, docs/guides/CONFIGURATION.md, docs/FEATURES.md, docs/FAQ.md, docs/README.md, docs/GLOSSARY.md, docs/guides/ERROR_TREND_VISUALIZATIONS.md, README.md, _guides/real-time-updates.md, _guides/configuration.md, _guides/error-trend-visualizations.md, _getting_started/features.md, _getting_started/documentation.md, _reference/faq.md, _reference/glossary.md, rails_error_dashboard.gemspec
  - Test: none (REQ-12 is prose). Checked by the grep below and by reading each changed passage.
  - After: none
  - Done when: `grep -rniE 'out[- ]of[- ]the[- ]box|no configuration needed' docs/guides/REAL_TIME_UPDATES.md _guides/real-time-updates.md` → no output, and `grep -lr enable_live_updates docs/guides/REAL_TIME_UPDATES.md docs/guides/CONFIGURATION.md _guides/real-time-updates.md _guides/configuration.md docs/FEATURES.md _getting_started/features.md README.md` → all seven files listed
- [x] **T7** Verify the whole change → REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, REQ-10, REQ-11, REQ-12, REQ-13
  - Files: none
  - Test: the full suite plus the real-app browser check
  - After: T4, T5, T6
  - Done when:
    - `R rspec` → 0 failures (≈ 5,990 examples);
    - chaos 1,507/1,507 through the commit hook;
    - a fresh Rails 8.1.4 app with this checkout as a `path:` gem, in headless Chrome:
      - switch on: the new row appears without a reload, and the browser opens `/cable`;
      - switch off: no stream tags, no client and no "Broadcasting to" lines

## After the gate

- Push the branch, open the PR (no `Closes`: there is no GitHub issue for this bug), and wait for CI.
- The release, and whether this goes in 0.16.3 or 0.17.0, is the user's call. The release notes
  carry the "Release steps" line from spec.md.
