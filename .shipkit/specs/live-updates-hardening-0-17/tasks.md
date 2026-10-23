# Tasks: Live-updates hardening for 0.17.0

Test first in every task: the cited test fails before the change and passes after it. Every test
cites `live-updates-hardening-0-17/REQ-N`. One commit per task, test and code together.

`R` below stands for `env -u RAILS_VERSION bin/with-ruby bundle exec`. The shell exports a stale
`RAILS_VERSION` that re-pins the lockfile. Run one rspec process at a time.

- [ ] **T1** Issue and verify short-lived stream tokens → REQ-1, REQ-2
  - Files: lib/rails_error_dashboard/services/live_stream_token.rb, lib/rails_error_dashboard.rb, spec/services/live_stream_token_spec.rb
  - Test: live_stream_token_spec:
    - a token issued for a RED stream verifies to that stream, with `expires_at` 10 minutes after issue;
    - two tokens issued in the same second differ;
    - nil for an expired token, a tampered one, a Turbo-signed one, one signed with RED's key for
      another purpose, a Hash, an over-long string, and a stream that isn't RED's;
    - `issue` returns nil, and `verify` never raises, when the key can't be built
  - After: none
  - Done when: `R rspec spec/services/live_stream_token_spec.rb` → 0 failures
- [ ] **T2** RED's live-updates channel, loaded only with Action Cable → REQ-2, REQ-3, REQ-5, REQ-12
  - Files: lib/rails_error_dashboard/live_updates_channel.rb, lib/rails_error_dashboard/engine.rb, spec/channels/live_updates_channel_spec.rb, spec/lib/rails_error_dashboard/live_updates_channel_loading_spec.rb
  - Test:
    - live_updates_channel_spec (test adapter set in `before(:context)`):
      - a valid token streams from its name;
      - expired, tampered, missing and Turbo-signed tokens are rejected with no streams;
      - with live updates off, a valid token is rejected;
      - a message reaching the subscription after expiry is not transmitted, and its streams are
        stopped;
      - the channel has no action methods;
    - live_updates_channel_loading_spec: the loader returns false and requires nothing with Action
      Cable hidden; the channel file is on no autoload or eager-load path
  - After: T1
  - Done when: `R rspec spec/channels/live_updates_channel_spec.rb spec/lib/rails_error_dashboard/live_updates_channel_loading_spec.rb` → 0 failures
- [ ] **T3** Stop the stats broadcast → REQ-10, REQ-11
  - Files: lib/rails_error_dashboard/services/error_broadcaster.rb, spec/lib/rails_error_dashboard/services/error_broadcaster_spec.rb, spec/requests/live_stream_delivery_spec.rb, spec/requests/live_stream_scoping_spec.rb, spec/system/live_updates_spec.rb, spec/rails_helper.rb, spec/integration/capture_query_budget_spec.rb, test/pre_release/chaos/phase_b_edge_cases.rb, app/views/rails_error_dashboard/errors/_stats.html.erb, spec/views/rails_error_dashboard/errors/_stats.html.erb_spec.rb, config/locales/en.yml
  - Test:
    - error_broadcaster_spec: `broadcast_new` and `broadcast_update` never call `Queries::DashboardStats`
      and broadcast to no stats stream;
    - live_stream_scoping_spec: no list subscribes to a stats stream
  - After: none
  - Done when: `R rspec spec/lib/rails_error_dashboard/services/error_broadcaster_spec.rb spec/requests/live_stream_scoping_spec.rb spec/requests/live_stream_delivery_spec.rb spec/integration/capture_query_budget_spec.rb spec/views/rails_error_dashboard/errors/_stats.html.erb_spec.rb spec/system/live_updates_spec.rb` → 0 failures
- [ ] **T4** Subscribe through RED's channel, on renamed streams → REQ-1, REQ-4
  - Files: lib/rails_error_dashboard/services/error_broadcaster.rb, app/helpers/rails_error_dashboard/application_helper.rb, app/views/rails_error_dashboard/errors/index.html.erb, app/controllers/rails_error_dashboard/errors_controller.rb, spec/lib/rails_error_dashboard/services/error_broadcaster_spec.rb, spec/requests/live_stream_scoping_spec.rb, spec/requests/live_stream_delivery_spec.rb, spec/requests/live_updates_client_spec.rb, spec/system/live_updates_spec.rb
  - Test:
    - live_stream_scoping_spec:
      - every source names `RailsErrorDashboard::LiveUpdatesChannel`;
      - every token verifies through `LiveStreamToken` and expires 10 minutes after the render;
      - no token verifies through Turbo's verifier;
      - the index still renders when a token can't be issued, with no source and no badge;
    - live_stream_delivery_spec: subscribers on every pre-0.17 name (`error_list`, `error_updates`,
      `error_stats`, and their `_app_<id>` forms) receive nothing from `broadcast_new` and
      `broadcast_update`, while the new names receive the row
  - After: T2, T3
  - Done when: `R rspec spec/lib/rails_error_dashboard/services/error_broadcaster_spec.rb spec/requests/live_stream_scoping_spec.rb spec/requests/live_stream_delivery_spec.rb spec/requests/live_updates_client_spec.rb spec/system/live_updates_spec.rb` → 0 failures
- [ ] **T5** Renew a list's subscriptions → REQ-6, REQ-7
  - Files: config/routes.rb, app/controllers/rails_error_dashboard/errors_controller.rb, app/helpers/rails_error_dashboard/application_helper.rb, spec/requests/live_streams_renewal_spec.rb
  - Test: live_streams_renewal_spec:
    - authenticated: the renewal returns exactly the page's stream kinds, as fresh tokens. Checked for
      the unfiltered list, one application, another filter, a sort, page 2, and an array filter;
    - the tokens verify; `Cache-Control` is `no-store`;
    - unauthenticated (Basic auth, and a lambda that denies): 401 or 403 with no token in the body;
    - live updates off: 404; a token that can't be issued: 503
  - After: T4
  - Done when: `R rspec spec/requests/live_streams_renewal_spec.rb spec/requests/live_stream_scoping_spec.rb` → 0 failures
- [ ] **T6** The open list renews itself, and says when it can't → REQ-8, REQ-9
  - Files: app/views/layouts/rails_error_dashboard.html.erb, spec/system/live_updates_spec.rb
  - Test: live_updates_spec, with `LiveStreamToken::LIFETIME` stubbed short:
    - after the first tokens have expired, every source carries a new token, and a newly captured
      error still appears without a reload;
    - with live updates switched off mid-page, the Live badge is hidden; switched back on, it
      returns
  - After: T5
  - Done when: `R rspec spec/system/live_updates_spec.rb` → 0 failures
- [ ] **T7** The real-time updates guide and its mirror → REQ-13
  - Files: docs/guides/REAL_TIME_UPDATES.md, _guides/real-time-updates.md
  - Test: none (prose; REQ-13 is `[untested]`). Check AnyCable's docs on stream callbacks first.
  - After: T6
  - Done when: both files describe short-lived subscriptions and renewal, the two streams, the custom-view helper and the two upgrade notes, and `diff` of their bodies shows only the front matter differing

## After the gate
- Full suite, RuboCop on tracked files, and `env -u RAILS_VERSION bin/with-ruby bin/pre-release-test all` (read FINAL RESULTS).
- Runtime proof with a raw WebSocket client against the lab app, with the gem by path:
  - old Turbo tokens subscribe but receive no row;
  - an expired RED token is rejected;
  - a fresh one receives the row;
  - a subscription that outlives its token receives nothing.
- The shipkit reviewer, re-run after every fix round until it passes.
