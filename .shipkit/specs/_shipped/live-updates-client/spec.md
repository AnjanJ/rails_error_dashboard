# Spec: Live updates reach the browser

> Spec accepted at commit `08c506e` on fix/live-updates-client.
> Status: shipped in 0.17.0 (#308)
> Paths: lib/rails_error_dashboard/configuration.rb,lib/rails_error_dashboard/services/error_broadcaster.rb,app/views/rails_error_dashboard/errors/index.html.erb,app/views/layouts/rails_error_dashboard.html.erb,app/helpers/rails_error_dashboard/application_helper.rb,lib/generators/rails_error_dashboard/install/templates/initializer.rb,docs/,_guides/,_getting_started/,_reference/,README.md,rails_error_dashboard.gemspec

## Purpose

The error index has subscribed to Turbo Streams since v0.1.x, and the server broadcasts a row and a
stats refresh on every capture. But the engine layout loads no Turbo client, so the
`<turbo-cable-stream-source>` elements never connect and nothing reaches the browser. The only
client import ever added (a69e77b) was removed a day later in 1dd1508 (v0.1.4), and it was
`@hotwired/turbo`, which does not define that element. The README, FEATURES and
`docs/guides/REAL_TIME_UPDATES.md` all describe the feature as working.

This spec makes the feature work and puts it behind a config switch. The broadcasting runs in
whichever thread commits the error row, so it is request-path work, and `.shipkit/product.md`
requires every request-path feature to be switchable. It is off by default: it has never worked,
so no one loses visible behaviour, and hosts stop paying for broadcasts that nobody receives.

## User stories

- As a developer watching the dashboard during an incident, I want new errors to appear on the
  index without reloading, so that I see a spike as it happens.
- As a host-app owner, I want to turn the broadcasting off, so that capturing an error does no
  rendering work for a page nobody has open.

## Requirements (EARS)

- **REQ-1.** The configuration shall provide `enable_live_updates`, defaulting to `false`.
- **REQ-2.** While `enable_live_updates` is false, the gem shall broadcast nothing when an error log
  is created or updated.
- **REQ-3.** While `enable_live_updates` is false, the error index shall render no stream
  subscription, no live-updates client script and no "Live" badge.
- **REQ-4.** While `enable_live_updates` is true and Turbo and the ActionCable pubsub are available,
  the error index shall load the turbo-rails client from a version-pinned URL that carries an
  `integrity` hash and `crossorigin="anonymous"`.
- **REQ-5.** While live updates are enabled and available, when an error is captured, an error
  index already open in a browser shall show the new error's row without a reload.
- **REQ-6.** The dashboard shall load the live-updates client only on pages that subscribe to a
  stream.
- **REQ-7.** While the client is loaded, each element the layout's scripts set up (tooltips, local
  times) shall be set up once per page load, so that clicking a local time still switches it
  between local time and UTC. *(Reworded at the design gate, 2026-10-22: it states the observable
  behaviour, not how often an initialiser runs.)*
- **REQ-8.** While the client is loaded, links and forms on the dashboard shall keep doing full page
  loads (Turbo Drive stays off).
- **REQ-9.** Where the host configures an ActionCable URL or mount path, the live-updates client
  shall connect to that URL.
- **REQ-10.** If `enable_live_updates` is true and turbo-rails or ActionCable is not loaded, then the
  gem shall emit a configuration warning that names the missing piece.
- **REQ-11.** The installer's initializer template shall include `enable_live_updates`, set to
  `false`, with a comment naming what the host needs.
- **REQ-12.** The real-time updates guide, the configuration guide, FEATURES, the README and their
  `_guides/`, `_getting_started/` and `_reference/` copies shall describe live updates as opt-in through
  `enable_live_updates`, with the host requirements: turbo-rails, and ActionCable with a
  cross-process adapter in production. [untested: prose, verified by reading and by grepping for
  stale claims]
- **REQ-13.** When a live update inserts or replaces a row, the row's relative time shall be
  formatted by the dashboard's own formatter and switch to the exact time on click, as it does for
  rows rendered with the page. *(Added at the design gate, 2026-10-22: a streamed row otherwise
  keeps the server's `time_ago_in_words`, which is in the host app's I18n locale.)*

## Out of scope

- Turning live updates on in the demo app. That is a separate repository; it needs
  `action_cable/engine` and solid_cable there.
- Reducing what an enabled broadcast costs on the capture path. Stats are already throttled to one
  per 5 s per stream; measuring the rest belongs to the overhead-benchmark goal.
- A polling fallback for hosts without ActionCable.
- Turbo Drive navigation for the dashboard.

## Release steps

- CHANGELOG / release notes: live updates now work, and are opt-in (`config.enable_live_updates =
  true`). Nobody loses behaviour, because the feature never delivered anything before.
