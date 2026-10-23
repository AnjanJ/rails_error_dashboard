---
layout: default
title: "Real-Time Updates with Turbo Streams"
permalink: /docs/guides/REAL_TIME_UPDATES
---

# Real-Time Updates with Turbo Streams

With live updates on, an open error list shows newly captured errors without a reload. Rows already on the page also update in place when their errors recur or change. Live updates are **off by default**, and they need Turbo Streams and Action Cable in the host app.

Each subscription is short-lived: it lasts 10 minutes, and an open list renews it through the dashboard itself. Someone who can no longer sign in to the dashboard stops getting live updates within 10 minutes.

## Table of Contents

- [Turning them on](#turning-them-on)
- [What updates](#what-updates)
- [Short-lived subscriptions](#short-lived-subscriptions)
- [What it costs](#what-it-costs)
- [Streams](#streams)
- [Content Security Policy](#content-security-policy)
- [Troubleshooting](#troubleshooting)
- [How it is tested](#how-it-is-tested)
- [Upgrading to 0.17.0](#upgrading-to-0170)
- [Upgrading from 0.16.2 or earlier](#upgrading-from-0162-or-earlier)

---

## Turning them on

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.enable_live_updates = true
end
```

The host app also needs four things:

1. **turbo-rails in its Gemfile.** RED does not depend on it, and the dashboard works without it.
2. **Action Cable, loaded and mounted.** It is loaded by `require "rails/all"`, or by `require "action_cable/engine"` in `config/application.rb`. Rails mounts it at `/cable` by default, and the dashboard also honours a custom `config.action_cable.url` or `mount_path`.
3. **A `config/cable.yml` adapter that reaches every process that captures errors.** In production, use a cross-process adapter such as Solid Cable or Redis. The `async` adapter only delivers within one process, so errors captured by a job worker or another Puma worker would never reach the browser.
4. **A cable connection the dashboard viewer can open.** The error list subscribes through your app's `ApplicationCable::Connection`, to the dashboard's own channel. If that connection rejects visitors who are not signed in to your app, a person who has only the dashboard login gets no live updates.

When the switch is on but turbo-rails or Action Cable is missing, RED logs a warning at boot that names the missing piece. The error list then behaves as if the switch were off.

## What updates

- **New errors** go to the top of the error list. This happens on the first page of a list that is unfiltered, or filtered only to one application. A list with any other filter or a sort, or a later page, does not take new rows, because a new error may not belong at its top.
- **Rows already on the page** are replaced in place when their error recurs, is resolved, or changes in any other way.
- **A Live badge** next to "Last updated" shows that the page has subscribed.
- **Relative times in new rows** ("2 minutes ago") are formatted in the dashboard's language, like the rest of the page.

Without live updates the dashboard works the same, and a reload shows new errors. There is no polling fallback.

The error list's stat counts are not live. They refresh when the page loads.

## Short-lived subscriptions

The error list subscribes through the dashboard's own Action Cable channel, `RailsErrorDashboard::LiveUpdatesChannel`, not through Turbo's `Turbo::StreamsChannel`:

- **Each subscription carries a token that expires 10 minutes after it is issued.** The dashboard issues the tokens, signed with a key derived from your app's `secret_key_base`. The channel refuses a subscription whose token has expired or was not issued for this purpose. It also stops sending to an open subscription once its token has expired.
- **An open error list renews its tokens every 5 minutes,** with a small request to the dashboard (`GET /errors/live_streams`). That request needs the same dashboard login as every page, so once someone can no longer sign in, their list can no longer renew, and its live updates end within 10 minutes. The list swaps each subscription for a renewed one without a gap, so no row is missed or shown twice.
- **The Live badge hides while renewal fails,** and comes back once a renewal succeeds. A failed renewal is retried after 30 seconds. A refused one (the dashboard no longer accepts the login, for example after a password change) is not retried on a timer, because each attempt could raise the browser's login prompt: the list tries again when you come back to the tab. A tab that wakes from sleep renews at once.
- **With the switch off, the channel refuses every subscription.**

With [AnyCable](https://docs.anycable.io/rails/compatibility), the token is checked when a subscription opens, but an open subscription is not cut at expiry, because AnyCable does not run Ruby stream callbacks.

## What it costs

With the switch off, capturing an error does no live-update work.

With it on, every capture that creates or updates an error row renders that row's partial in the thread that committed the row. When async logging is off, that thread is the request thread. The partial is rendered once per stream, so twice when the error belongs to an application.

Broadcasts carry rows only. No dashboard stats are computed for them.

The cost is bounded in four ways:

- each open error list makes one small renewal request to the dashboard every 5 minutes;
- while storm protection's circuit breaker is open, nothing is broadcast, and the page catches up on its next load;
- if the cable adapter cannot be reached (for example, Redis is down), broadcasting pauses for 60 seconds instead of retrying on every error;
- the turbo-rails client (about 41 KB compressed) loads only on the error list, and only when live updates are on.

## Streams

Broadcasts go out on two kinds of stream. Each exists once globally and once per application. `RailsErrorDashboard::Services::ErrorBroadcaster.stream_name` is the single source for the names, used by both the built-in views and the broadcaster.

| Stream | Per application | Carries |
|---|---|---|
| `rails_error_dashboard:error_list` | `rails_error_dashboard:error_list_app_<id>` | New rows (`prepend` into `#error_list`) |
| `rails_error_dashboard:error_updates` | `rails_error_dashboard:error_updates_app_<id>` | Changed rows (`replace` of `#error_<id>`) |

The error list subscribes according to what it is showing:

- Filtered to an application, it listens to that application's streams only, so another application's errors never appear in it.
- With any other filter, a sort, or on a page after the first, it does not listen to the new-row stream. Rows already on the page still update in place.

### In a custom index view

A custom index view (see [Custom Views](../CUSTOMIZATION.md#custom-views)) subscribes the way the built-in one does, with the dashboard's helper. Render it near the top of your `app/views/rails_error_dashboard/errors/index.html.erb`:

```erb
<% if red_live_updates? %>
  <% live = red_live_updates_tags(@live_streams, renew_url: @live_renew_url) %>
  <% if live %>
    <% content_for :red_head, red_live_updates_client_tags %>
    <%= live %>
  <% end %>
<% end %>
```

Keep an element with `id="error_list"` holding the rows, so that new rows have somewhere to go. Don't use `turbo_stream_from` for these streams: it subscribes through `Turbo::StreamsChannel`, which receives nothing from the dashboard.

## Content Security Policy

The error list loads the turbo-rails client (`@hotwired/turbo-rails`, at a pinned version) from `cdn.jsdelivr.net`. It is a module script with a Subresource Integrity hash, and it carries your CSP nonce when you have one. Under a strict policy:

- `script-src` must allow `https://cdn.jsdelivr.net`. The dashboard's other scripts already need this.
- `connect-src` must allow the WebSocket connection to your cable URL.

## Troubleshooting

### No Live badge on the error list

The page did not subscribe. Check these in order:

1. `config.enable_live_updates` is `true`.
2. The boot log has no `enable_live_updates is on but …` warning.
3. `ActionCable.server.pubsub` works in a Rails console. That means `config/cable.yml` has an entry for this environment, and its adapter is reachable. After a failure, RED waits 60 seconds before trying again.

### The Live badge disappears while the list is open

Renewal is failing. In the browser's network tab, look at the requests to `/errors/live_streams`:

- **401 or 403:** the dashboard no longer accepts this browser's login. Reload the page and sign in again.
- **404:** live updates were switched off, or the cable adapter stopped answering.
- **503:** the dashboard could not issue a token. Tokens are signed with a key derived from your app's `secret_key_base`, so check that it is set in this environment.

### The badge shows, but new errors never appear

- **Check the WebSocket.** In the browser's developer tools, filter the network tab by WS. There should be one connection to `/cable` (or to your cable URL). If it closes straight away, your `ApplicationCable::Connection` probably rejected it.
- **Check where errors are captured.** If they are captured in another process, such as a job worker or a second Puma worker, the `async` adapter cannot reach the browser. Use Solid Cable or Redis.
- **Check the list's filters.** A filtered, sorted or later page does not receive new rows, by design (see [Streams](#streams)).
- **Check for an error storm.** During one, nothing is broadcast until the breaker closes.

## How it is tested

- `spec/requests/live_stream_delivery_spec.rb`: broadcasts reach real subscribers through the async adapter, scoped per application, and nothing reaches the stream names of earlier versions.
- `spec/requests/live_stream_scoping_spec.rb`: which streams each list subscribes to, and through which channel.
- `spec/requests/live_streams_renewal_spec.rb`: renewal returns the list's own streams, and only to a viewer the dashboard lets in.
- `spec/services/live_stream_token_spec.rb` and `spec/channels/live_updates_channel_spec.rb`: tokens expire, and the channel refuses or stops anything else.
- `spec/requests/live_updates_client_spec.rb`: the switch, the client tag with its integrity hash, and the cable URL.
- `spec/system/live_updates_spec.rb`: a real browser opens the list, an error is captured, and its row appears without a reload. With short-lived tokens, the list renews and keeps updating past the first tokens' expiry, and the Live badge hides while renewal fails.

## Upgrading to 0.17.0

- **Subscriptions are short-lived, and renewed through the dashboard** (see [Short-lived subscriptions](#short-lived-subscriptions)). Nothing to change in your app.
- **The streams have new names, and go through the dashboard's channel.** A custom index view that subscribed with `turbo_stream_from "error_list"` (or another of the old names) stops receiving updates. Render the dashboard's helper instead, as in [In a custom index view](#in-a-custom-index-view).
- **The stats stream is gone.** No built-in page used it. A custom view with a `#dashboard_stats` element now shows the stats as of its last page load. The `rails_error_dashboard/errors/stats` partial is still there for such views to render.

## Upgrading from 0.16.2 or earlier

Up to 0.16.2, live updates never reached the browser:

- the error list rendered stream subscriptions;
- RED broadcast on every capture whenever turbo-rails and Action Cable were loaded;
- but the dashboard's layout loaded no Turbo client.

Live updates now work, and they are opt-in: set `config.enable_live_updates = true`. If you leave the switch off, captures stop doing the broadcast work they did before.

---

## See also

- [Turbo Streams handbook](https://turbo.hotwired.dev/handbook/streams)
- [Action Cable overview](https://guides.rubyonrails.org/action_cable_overview.html)
- [Configuration Guide](CONFIGURATION.md)
- [Error Sampling & Filtering](ERROR_SAMPLING_AND_FILTERING.md)
- [Main README](../README.md)
