# Design: Webhook contract v1

## Approach
- **The envelope is applied in one place.** `Services::WebhookDelivery.post` is already the only
  sender to `config.webhook_urls`. Its callers: `webhook_error_notification_job.rb:39`,
  `baseline_alert_job.rb:119` and `concerns/plain_channel_message.rb:63` (storm and burst). It now:
  - adds `version: 1`;
  - derives `X-Error-Dashboard-Event` from the body's `event`;
  - derives `X-Error-Dashboard-ID` from the body's `error.id`, when there is one;
  - then serialises and signs, as today, so the signature still covers the exact bytes sent
    (REQ-10).
- **The event names live in one module,** `RailsErrorDashboard::Webhooks::EVENTS`, with a constant
  per event. The four builders use the constants:
  - `webhook_payload_builder.rb:31`;
  - `storm_notification_job.rb:23`;
  - `notification_burst_summary_job.rb:29`;
  - `baseline_alert_payload_builder.rb:179`.
- **The storm and burst bodies gain `timestamp`.**
- **The contract page** is a new `docs/WEBHOOKS.md`. Two existing pages link to it:
  - the notifications guide's webhook section (`docs/guides/NOTIFICATIONS.md:234`), which also
    shows a v1 body;
  - the API reference's "Webhooks RED sends" section (`docs/API_REFERENCE.md:298`), which keeps the
    signing table.

  Jekyll copies change the same way. A spec reads the page and `EVENTS`.

Nothing changes for Slack, Discord, Telegram, PagerDuty or email. They use `post_json` and their
own senders, never `WebhookDelivery` (REQ-11).

## Decision: Apply version and headers inside `WebhookDelivery`, not in each builder   (→ REQ-1, REQ-3, REQ-4, REQ-10)

**Context.** Three jobs post to `webhook_urls`, and today only one sets the event header
(`webhook_error_notification_job.rb:33-35`). `WebhookDelivery` was introduced so the signature is
computed over the bytes actually sent (its own comment, `webhook_delivery.rb:9-14`), and it's used
for nothing but `webhook_urls`.

**Alternatives.**
1. `WebhookDelivery.post` merges `version: 1` into the body and sets both headers from the body,
   before serialising and signing.
2. Each builder adds `version`, and each caller passes its headers.
3. A new envelope helper, `Webhooks.envelope(event, data)`, that every builder calls.

**Case for 1.** Every post gets the envelope, including one from an event added later in 1.x, and
there's one place to test it. Signing is unchanged because it already happens there, after the
body is final. The headers can't disagree with the body, because they're derived from it.

**Case against 1.** The sender now knows about the contract (`event`, `error.id`), so it's no
longer a pure transport. A caller that passes a body without `event` gets no event header. The
REQ-3 spec covers all four events, and `WebhookDelivery` logs a warning on such a body. Option 3
keeps the transport pure, but four builders could each forget to call it, which is the failure
that left three events without the header today.

**Decision.** We chose option 1.
**Falsifiability.** We would move the envelope into the builders (option 3) if `WebhookDelivery`
gains a second purpose: a caller that posts something other than the webhook contract.
**Fired-if.** `test "$(grep -rln 'WebhookDelivery\.post' lib app | wc -l)" -gt 3` <!-- 3 callers today: the error, baseline and plain-message jobs -->

## Decision: Event names as constants, and a spec that reads the contract page   (→ REQ-5, REQ-6, REQ-7, REQ-8, REQ-13, REQ-14)

**Context.** Event names are string literals in four files, which is how they ended up in three
styles. REQ-14 needs a spec to know every event RED can post.

**Alternatives.**
1. `Webhooks::EVENTS`, a frozen hash of the four names, referenced by each builder. One spec
   checks that every value appears on `docs/WEBHOOKS.md`. A second checks that no `event: "`
   string literal is left in the builders.
2. Build each of the four payloads in the spec, and collect their `event` values.
3. Keep the literals; the spec greps for them.

**Case for 1.** One list is the single source. A new event added to it can't be left off the page
without failing CI. The literal check stops a fifth builder from bypassing the list.

**Case against 1.** One more module to know about. The literal check is a source scan, and a
builder that computes its event name some other way would slip past it. Option 2 exercises real
code, but a new event's builder would have to be added to the spec by hand, which is exactly the
step that gets forgotten.

**Decision.** We chose option 1.
**Falsifiability.** We would switch to option 2 if an event reaches a receiver that isn't in
`Webhooks::EVENTS` (an issue or a spec showing it).
**Fired-if.** manual

## Decision: `timestamp` is UTC for every event   (→ REQ-2, REQ-9)

**Context.** `error.created` and the baseline body build `timestamp` with
`Time.current.iso8601` (`webhook_payload_builder.rb:32`, `baseline_alert_payload_builder.rb:180`).
That's in the app's `Time.zone`: `Z` for the Rails default, and an offset such as `+05:30` for apps
that set `config.time_zone`. Storm and burst bodies have no `timestamp` at all. REQ-2 requires UTC.

**Alternatives.**
1. `Time.now.utc.iso8601` for `timestamp` on all four events. Every other time field
   (`occurred_at`, `first_seen_at`, …) is left as it is.
2. Keep `Time.current.iso8601` (zone-dependent) for all four.

**Case for 1.** A receiver can compare the envelope's `timestamp` across apps without knowing each
app's time zone. For apps on the default zone (UTC) the value doesn't change at all. For the rest,
it's the same instant written with a different offset, which any ISO 8601 parser reads the same
way.

**Case against 1.** An app with a non-UTC `config.time_zone` sees `timestamp` switch from `+05:30`
to `Z`, which breaks a receiver that compares it as a string. And the body then mixes a UTC
`timestamp` with zone-local `occurred_at`. UPGRADING says so.

**Decision.** We chose option 1.
**Falsifiability.** We would revert to option 2 if an issue reports a receiver broken by the UTC
`timestamp` within a month of 0.18.0.
**Fired-if.** manual
