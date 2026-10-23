# Spec: Live-updates hardening for 0.17.0

> Spec accepted at commit `16d2baa` on fix/live-updates-hardening-0-17 (2026-10-23).
> Status: open
> Paths: lib/rails_error_dashboard/services/error_broadcaster.rb,lib/rails_error_dashboard/services/live_stream_token.rb,lib/rails_error_dashboard/live_updates_channel.rb,lib/rails_error_dashboard/engine.rb,lib/rails_error_dashboard.rb,app/controllers/rails_error_dashboard/errors_controller.rb,config/routes.rb,app/helpers/rails_error_dashboard/application_helper.rb,app/views/rails_error_dashboard/errors/index.html.erb,app/views/rails_error_dashboard/errors/_stats.html.erb,app/views/layouts/rails_error_dashboard.html.erb,config/locales/en.yml,test/pre_release/chaos/phase_b_edge_cases.rb,docs/guides/REAL_TIME_UPDATES.md,_guides/real-time-updates.md,spec/services/live_stream_token_spec.rb,spec/channels/,spec/requests/live_streams_renewal_spec.rb,spec/requests/live_stream_scoping_spec.rb,spec/requests/live_stream_delivery_spec.rb,spec/requests/live_updates_client_spec.rb,spec/lib/rails_error_dashboard/services/error_broadcaster_spec.rb,spec/lib/rails_error_dashboard/live_updates_channel_loading_spec.rb,spec/system/live_updates_spec.rb,spec/rails_helper.rb,spec/integration/capture_query_budget_spec.rb,spec/views/rails_error_dashboard/errors/_stats.html.erb_spec.rb

## Purpose
Make live-update subscriptions short-lived, and stop broadcasting work that updates nothing. Both
apply only to hosts that turn live updates on (`config.enable_live_updates`, off by default).
- The error list subscribes with signed stream names that never expire. RED's names are constants,
  so the signed values are identical on every page load, and a subscription made with one keeps
  receiving new error rows after the viewer's dashboard access has ended.
- Every capture can compute the dashboard stats and broadcast them to `#dashboard_stats`, an element
  no built-in page renders.

## User stories
- As a developer who turns live updates on, I want a live-update subscription to stop working soon
  after someone's dashboard access ends, so that only current dashboard users see new errors as
  they happen.
- As a dashboard user, I want an error list I leave open to keep updating without a reload.
- As a developer, I want live updates to cost my app only the work that changes what I see.

## Requirements (EARS)

### Subscriptions are short-lived
- **REQ-1.** While live updates are on, the error list shall subscribe to each of its streams
  through RED's own live-updates channel, with a token that RED issued for that stream and that
  expires 10 minutes after it was issued.
- **REQ-2.** If a subscription request to RED's channel carries a token that has expired, has been
  altered, is missing, or was not issued by RED for live updates, then the channel shall reject the
  subscription.
- **REQ-3.** If a broadcast reaches an open subscription after that subscription's token has expired,
  then the channel shall not deliver it.
- **REQ-4.** When RED broadcasts a new or changed row, a subscription made through
  `Turbo::StreamsChannel` with a token for any stream name RED used before 0.17.0 shall receive
  nothing.
- **REQ-5.** While live updates are off, RED's channel shall reject every subscription.

### An open list renews its subscriptions
- **REQ-6.** When a viewer authenticated to the dashboard asks to renew an error list's
  subscriptions, the dashboard shall return a fresh token for each stream that list subscribes to,
  and for no other stream.
- **REQ-7.** If a viewer not authenticated to the dashboard asks to renew, then the dashboard shall
  refuse the request and return no token.
- **REQ-8.** While the error list is open with live updates on, the page shall renew its
  subscriptions with fresh tokens before the current ones expire, without a reload.
- **REQ-9.** If renewing fails, then the page shall hide its Live badge until a later renewal
  succeeds.

### No stats broadcast
- **REQ-10.** When an error is created or updated, RED shall neither compute dashboard stats nor
  broadcast them for live updates.
- **REQ-11.** The error list shall not subscribe to a stats stream.

### Hosts without Action Cable
- **REQ-12.** Where the host app does not load Action Cable, RED shall not load its live-updates
  channel, and the app shall boot and eager-load as it does today.

### Docs
- **REQ-13.** The real-time updates guide and its `_guides/` mirror shall describe short-lived
  subscriptions and their renewal, the two remaining streams, how a custom index view subscribes,
  and the upgrade note for custom views and for the removed stats stream. [untested: prose,
  verified by reading]

## Out of scope
- Authenticating the host's `ApplicationCable::Connection`. It is the host's code; the guide keeps
  saying what it must admit.
- Turning live updates on by default (revisit for 1.0), and live updates on the demo app.
- A live stats region on any page; a polling fallback; Turbo Drive for the dashboard.
- Making the subscription lifetime configurable (the 1.0 config freeze).
- Changing what a streamed row contains.
