# Design: Live-updates hardening for 0.17.0

## Approach

The error list stops subscribing through `Turbo::StreamsChannel`. It subscribes through a RED channel
instead, with tokens RED issues and checks itself:

1. `Services::LiveStreamToken` signs `{ s: stream, e: expires_at (epoch seconds), n: nonce }` with an
   `ActiveSupport::MessageVerifier`.
   - The key is derived from `secret_key_base` under a RED salt.
   - The token carries a RED purpose, and expires 10 minutes after it is issued.
2. `RailsErrorDashboard::LiveUpdatesChannel` does three things:
   - verifies the token on subscribe (in a private `subscribed`), and rejects anything else;
   - streams from the name inside the token;
   - drops every message that arrives after the token's expiry.
3. RED broadcasts to new names (`rails_error_dashboard:error_list…`, `…:error_updates…`). No
   `Turbo::StreamsChannel` token RED ever issued names them.
   - Turbo's broadcast methods still build the messages.
   - The browser still uses turbo-rails' `<turbo-cable-stream-source>` element, with the `channel`
     attribute pointing at RED's channel.
4. The page renews before expiry:
   - every 5 minutes it fetches fresh tokens from `GET /errors/live_streams`, behind dashboard auth,
     with the page's own query string;
   - it puts a new source element next to each old one, and removes the old one once the new one
     is connected.
   - If a renewal fails, the Live badge is hidden until a renewal succeeds.
5. The stats broadcast, its throttle and the stats stream are removed (the maintainer's choice).

## Decision: A RED channel that checks RED-issued, expiring tokens   (→ REQ-1, REQ-2, REQ-5)

**Context.** A subscription token must stop working soon after the viewer's dashboard access ends.
`Turbo::StreamsChannel` accepts any name signed by `Turbo.signed_stream_verifier`, which carries no
expiry. The host's `ApplicationCable::Connection` is the host's code, and it can't be relied on to see
RED's dashboard login: a browser may or may not send cached Basic credentials on a WebSocket
handshake, and a host `authenticate_with` lambda runs on controller requests only. RED must not patch either class (the paramount rule against process-wide
side effects).

**Alternatives.**
1. A RED channel verifying a RED-signed token with an expiry and a purpose.
2. Keep `Turbo::StreamsChannel`, and add a rotating suffix to the names (for example the UTC hour).
   Broadcasts go to the current name only.
3. Keep `Turbo::StreamsChannel`, and sign new names with Turbo's verifier plus `expires_in`.
   `MessageVerifier#verified` honours the expiry.
4. Check dashboard auth on subscribe, through the connection.

**Case for 1.** A token works for 10 minutes and no longer, whatever else changes. Only RED issues
the tokens, under its own purpose, so nothing the host or turbo-rails signs can stand in for one.
The channel also knows when its token expires, which is what lets it end an open subscription on
time (next decision). It touches no host class, and turbo-rails' element and broadcast methods are
used unchanged.

**Case against 1.** RED now owns an Action Cable channel. Its class must load only where Action Cable
does (a later decision), and a host that writes a custom view must use RED's helper rather than
`turbo_stream_from`.
- Option 2 needs no channel. But it is coarse: a token lives up to a whole rotation period.
  Broadcasts at a boundary need both names, or a page loses rows. Old tokens still subscribe; they
  just hear nothing.
- Option 3 needs no channel either. But Turbo's channel can't end an open subscription, and
  Turbo's verifier key is the host's (`config.turbo.signed_stream_verifier_key`).
- Option 4 can't work reliably: the connection may not see Basic auth, and never runs the host's
  `authenticate_with` lambda.

**Decision.** We chose option 1.
**Falsifiability.** We would revisit option 4 if RED's dashboard login becomes a session cookie that
an Action Cable connection could read on its own.
**Fired-if.** manual

## Decision: Rename the streams   (→ REQ-4)

**Context.** Pages served by 0.16.x and earlier carry `Turbo::StreamsChannel` tokens for the old names
(`error_list`, `error_updates`, `error_stats`, and their `_app_<id>` variants). Those tokens never
expire, and the host's Turbo channel will keep accepting them. Whatever a page did with them, a
broadcast to an old name reaches any holder.

**Alternatives.**
1. Broadcast to new names, `rails_error_dashboard:error_list` and `rails_error_dashboard:error_updates`,
   each with the same `_app_<id>` suffix. Never sign them with Turbo's verifier.
2. Keep the old names, and rely on the RED channel alone.
3. Make the new names secret, by deriving a part from `secret_key_base`.

**Case for 1.** It is the only option that closes the old tokens: they keep subscribing to names
nothing broadcasts to. A spec can prove it (REQ-4): subscribe to every old name, broadcast, receive
nothing. The namespace also keeps RED out of the host's own stream names.

**Case against 1.**
- A custom view that subscribed to the old names with `turbo_stream_from` silently stops updating.
  The upgrade note says so, and names the helper to use.
- A host could still Turbo-sign a new name by writing `turbo_stream_from
  "rails_error_dashboard:error_list"`. That takes host code written to do it on purpose.
- Option 3 would not help much against that: the name is readable inside RED's own token, which is
  signed, not encrypted.

**Decision.** We chose option 1.
**Falsifiability.** We would add a secret part to the names (option 3) if any host code path that
Turbo-signs a name taken from a request is reported against RED.
**Fired-if.** manual

## Decision: Check expiry on every delivered message   (→ REQ-3)

**Context.** A subscription that was valid when it opened stays open as long as its socket. The token
expiry has to end it, or "short-lived" covers only the subscribe step.

**Alternatives.**
1. Pass `stream_from` a private callback that compares now with the token's `expires_at` for each
   message. Once a message arrives late, the callback drops it and calls `stop_all_streams`.
2. A `periodically` timer per subscription that calls `stop_all_streams` at expiry.
3. Check only on subscribe.

**Case for 1.**
- It is exact: nothing reaches a subscription after its expiry, with no window of up to one timer
  period.
- It costs one integer comparison per message, and no timer thread work per open page.
- The callback must stay private, because Action Cable lets a client call any public channel
  method as an action.

**Case against 1.**
- An expired subscription stays registered until its next message, or until the socket closes.
  It holds a pubsub subscription, but no data reaches it.
- Action Cable's channel test stub records `stream_from` without running the callback, so the spec
  calls the private callback directly. The real path is checked end to end with a raw WebSocket
  client before release.
- AnyCable doesn't run Ruby stream callbacks: its compatibility table lists custom stream callbacks
  as unsupported (docs.anycable.io/rails/compatibility, checked 2026-10-23). There the token is
  checked when a subscription opens, but an open subscription isn't cut at expiry. The guide says
  so.
- Option 2 would show up in a channel spec, but it costs a timer per subscription and leaves a
  window.
- Option 3 leaves the gap this spec exists to close.

**Decision.** We chose option 1.
**Falsifiability.** We would switch to option 2 if a raw WebSocket client receives a row on a
subscription whose token has expired, in the pre-release check or in any report.
**Fired-if.** manual

## Decision: Renew through a dashboard-authenticated endpoint, make-before-break   (→ REQ-6, REQ-7, REQ-8, REQ-9)

**Context.** A list left open must keep updating past one token lifetime (REQ-8). Renewal is also
where access is checked again: a viewer who can no longer pass dashboard auth must not get a fresh
token.

**Alternatives.**
1. `GET /errors/live_streams`, behind the normal dashboard auth. It is called with the page's own
   query string, unchanged, and returns `{ tokens: { list:, updates: } }` for exactly the streams
   `streams_for_view` gives that page. The page inserts a new source element next to each old one,
   then removes the old one once the new one is `connected`.
2. The same endpoint, but the page changes the old element's `signed-stream-name` attribute instead.
   turbo-rails re-subscribes it, unsubscribing first.
3. A renew action on the channel itself.
4. No renewal: the page reloads itself, or says it is stale.

**Case for 1.**
- Renewal goes through exactly the check that guards every dashboard page, Basic auth or the
  host's `authenticate_with` lambda, so revoked access stops renewals at once.
- Computing the streams from the same raw query string with the same method keeps the page and the
  renewal in step by construction (REQ-6), including `page` and array params, which a renew URL
  rebuilt from the filter list would lose.
- Make-before-break leaves no gap: a row broadcast during the swap reaches the old subscription or
  the new one. Turbo 8 removes a duplicate child by id before a `prepend`, and a `replace` is
  idempotent, so the overlap can't double a row.
- No gap also makes the browser spec deterministic.

**Case against 1.**
- It is a new endpoint, and about 60 lines of layout JavaScript. The JavaScript has to cope with
  failure: a new source that never connects (a rejected subscription has no callback in turbo-rails'
  element) is dropped after 15 s, and a failed renewal is retried after 30 s, not 5 minutes.
- Each open list makes one small authenticated request every 5 minutes.
- During the overlap a page holds two subscriptions per stream, for as long as a subscribe takes.
- Option 2 is fewer lines, but break-before-make drops any row broadcast while it re-subscribes.
- Option 3 would let a token holder renew forever over a socket nobody authenticated.
- Option 4 loses the page's state, or the feature.

**Decision.** We chose option 1.
**Falsifiability.** We would reconsider if renewal requests exceed 1% of a host's dashboard requests in
the 1.0 overhead benchmark, or if an issue reports a duplicated row on an open list.
**Fired-if.** manual

## Decision: Ten-minute tokens, renewed every five   (→ REQ-1, REQ-8)

**Context.** The lifetime bounds how long revoked access keeps a feed. The renewal period (half the
lifetime) sets how many requests an open list makes. A constant, not a setting: the 1.0 config
freeze.

**Alternatives.**
1. 10 minutes, renewed every 5.
2. 1 minute, renewed every 30 seconds.
3. 1 hour, renewed every 30 minutes.

**Case for 1.**
- Revocation takes effect within 10 minutes. That is the same order as how long a dashboard tab
  stays in use.
- An open list makes 12 renewals an hour.
- A page that misses one renewal, for example when a background tab's timers are throttled to once
  a minute, still has 5 minutes of margin.

**Case against 1.**
- 10 minutes is longer than option 2's minute: for that long, a former viewer still gets rows over
  a subscription they opened before losing access.
- After a laptop sleeps longer than the lifetime, the list catches up only at the next renewal tick,
  up to 5 minutes later.

**Decision.** We chose option 1.
**Falsifiability.** We would shorten it if a user asks for revocation faster than 10 minutes, and
lengthen it if renewal requests exceed 1% of dashboard requests in the 1.0 benchmark.
**Fired-if.** manual

## Decision: Remove the stats broadcast, keep the stats partial   (→ REQ-10, REQ-11)

**Context.** The user chose to stop the stats broadcast entirely (intake, question 1). That removes
four things:
- `broadcast_stats`;
- the stats stream kind;
- the per-stream throttle (`claim_stats_window!`, `STATS_BROADCAST_INTERVAL`,
  `MAX_THROTTLED_STREAMS`, `throttled_stream_count`, `reset_throttle!`);
- the chaos check that calls it.

That leaves `_stats.html.erb`, which nothing built in renders any more.

**Alternatives.**
1. Keep the partial and its five locale keys, and say in its header that only a custom view renders
   it now.
2. Delete the partial, its view spec, and its keys in all eleven locales.

**Case for 1.** A custom index override may render `rails_error_dashboard/errors/stats` by name.
Deleting the partial would turn that page into a `MissingTemplate` error, in a release that is
otherwise a hardening one. It costs nothing at run time.

**Case against 1.** A partial that no built-in page renders is dead code in the gem. The unused-keys
scan in `bin/i18n-check` will warn about its keys as soon as a scan can no longer find a caller.

**Decision.** We chose option 1.
**Falsifiability.** We would delete it if 1.0.0.rc1 is tagged and no issue has mentioned rendering the
stats partial from a custom view.
**Fired-if.** `git tag -l 'v1.0.0*' | grep -q .`

## Decision: Load the channel from `lib/`, only when Action Cable is loaded   (→ REQ-12)

**Context.** The channel subclasses `ActionCable::Channel::Base`. Production eager loading loads every
file under an engine's autoload paths, `app/channels` included. In a host without Action Cable, the
superclass would be a `NameError` at boot. Today the gem has no `app/channels`.

**Alternatives.**
1. `lib/rails_error_dashboard/live_updates_channel.rb`, required by an engine initializer only when
   `defined?(::ActionCable::Channel::Base)`. `engine.rb` already makes the same `defined?(ActionCable)`
   check before it subscribes the Action Cable breadcrumb subscriber.
2. `app/channels/rails_error_dashboard/live_updates_channel.rb`, excluded from eager loading when
   Action Cable is absent.

**Case for 1.** A host without Action Cable never loads the file, and no autoloader knows about it.
That is already how the gem treats optional libraries ("detect a library before calling it").
`ErrorBroadcaster.available?`, the single gate for both ends since #308, also requires the class to be
defined, so RED renders no subscriptions and broadcasts nothing when the class isn't loaded.

**Case against 1.** The class is not reloaded in development, like the rest of `lib/`. Option 2 is
the conventional place for a channel, and reloads, but its exclusion would be autoloader
configuration that is easy to get wrong across Rails 7.0–8.1.

**Decision.** We chose option 1.
**Falsifiability.** We would move it to `app/channels` if RED makes Action Cable a hard dependency.
**Fired-if.** `grep -q 'add_dependency "actioncable"' rails_error_dashboard.gemspec`

## Data / interface changes

- **Streams (→ REQ-4, REQ-11).** `ErrorBroadcaster::STREAMS` becomes
  `{ list: "rails_error_dashboard:error_list", updates: "rails_error_dashboard:error_updates" }`.
  `stream_name` is unchanged. `streams_for_view` returns `{ kind => name }` (`:updates` always,
  `:list` unless filtered).
- **Removed from `ErrorBroadcaster` (→ REQ-10):** `broadcast_stats`, `claim_stats_window!`,
  `throttled_stream_count`, `reset_throttle!`, `monotonic_now`, `STATS_BROADCAST_INTERVAL`,
  `MAX_THROTTLED_STREAMS`, `THROTTLE_MUTEX`. `available?` also requires
  `RailsErrorDashboard::LiveUpdatesChannel` to be defined (→ REQ-12). The `reset_throttle!` calls in
  `spec/rails_helper.rb` and the specs go.
- **New `Services::LiveStreamToken` (→ REQ-1, REQ-2).**
  - `issue(stream)` returns a String, or nil on any error. The helper then renders no subscription
    and no Live badge, so a token failure never turns the index into an error page.
  - The payload is `{ "s" => stream, "e" => expires_at (Integer epoch), "n" => random nonce }`. The
    nonce keeps two tokens issued in the same second (frozen time in specs) from being
    byte-identical, which Action Cable would ignore as a duplicate subscription.
  - `verify(token)` returns `{ stream:, expires_at: }` or nil. It never raises. It returns nil for a
    non-String (a Hash param raises inside `MessageVerifier#verified`), an over-long string,
    tampered, expired or wrong-purpose input, or a stream that doesn't match RED's name pattern.
  - `LIFETIME = 10.minutes`. `MessageVerifier.new` gets only `digest:` and `serializer:`, the
    options Rails 7.0 accepts.
- **New `RailsErrorDashboard::LiveUpdatesChannel` (→ REQ-2, REQ-3, REQ-5),** in
  `lib/rails_error_dashboard/live_updates_channel.rb`.
  - It reads `params[:signed_stream_name]`, the key turbo-rails' element sends.
  - It has no public methods. Action Cable treats a subclass's own public methods as client actions,
    so `subscribed` stays private, as in `ActionCable::Channel::Base`.
  - Its specs set the `test` adapter in `before(:context)`, because Action Cable's test helper reads
    `server.pubsub` before any example code, and the dummy app has no `cable.yml`.
- **New route `GET /errors/live_streams` → `ErrorsController#live_streams` (→ REQ-6, REQ-7).**
  - JSON `{ "tokens": { "list": "…", "updates": "…" } }`, with a `Cache-Control: no-store` header
    set directly.
  - 404 while live updates are unavailable; 503 if a token can't be issued (rescued in the action,
    so a failed renewal never renders the HTML error page).
  - It skips `load_storm_banner`. Authentication is the controller's usual
    `prepend_before_action`.
- **Helper (→ REQ-1, REQ-8).** `red_live_updates_tags(streams, renew_url:)` renders a hidden
  `#red-live-streams` container (`data-renew-url`, `data-renew-every` in ms) holding one
  `<turbo-cable-stream-source channel="RailsErrorDashboard::LiveUpdatesChannel"
  signed-stream-name="…" red-live-kind="…">` per stream.
  - It never calls `turbo_stream_from`.
  - The index uses it, and so can a custom index view.
  - The Live badge gets `id="red-live-badge"`.
  - `renew_url` is the engine's `live_streams_errors_path` plus `request.query_string`, unchanged.
- **Layout JS (→ REQ-8, REQ-9).** When `#red-live-streams` is present:
  - a timer renews every `data-renew-every` ms. It fetches `new URL(renewUrl, location.origin)`, so
    credentials embedded in the page URL never reach `fetch`;
  - it swaps the sources make-before-break, and shows `#red-live-badge` only once every new source
    is `[connected]`;
  - it hides the badge on a failed fetch, or on a swap not connected within 15 s (the new sources
    are dropped), and then retries after 30 s. A 401 or 403 is not retried on a timer: with Basic
    auth each refused fetch can raise the browser's login prompt, so the page waits until the tab
    is shown again;
  - it renews at once on `visibilitychange` (to visible), `pageshow` or `online`, when the last
    success is more than 4 minutes old.
- **Kept:** `_stats.html.erb` and its keys. Its header comment and the `en.yml` comment are corrected.
- **Docs (→ REQ-13):** `docs/guides/REAL_TIME_UPDATES.md` and `_guides/real-time-updates.md`.
- **Unchanged:** an array `application_id` still maps to `_app_0` streams (`stream_name`'s `to_i`), as
  before this work.
