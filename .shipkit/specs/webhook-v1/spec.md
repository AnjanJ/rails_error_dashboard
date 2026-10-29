# Spec: Webhook contract v1

> Spec accepted at commit `6b1dfab` on spec/0-18-0 (2026-10-29).
> Status: open
> Paths: app/jobs/rails_error_dashboard/,lib/rails_error_dashboard/services/webhook_payload_builder.rb,lib/rails_error_dashboard/services/baseline_alert_payload_builder.rb,lib/rails_error_dashboard/services/webhook_delivery.rb,docs/,_guides/,_getting_started/,spec/

## Purpose
RED posts four events to the generic webhook URLs, and nothing about them is versioned. Event names
come in three styles, and only one event carries the event header. 1.0 freezes this contract, so
0.18.0 fixes it first (decision 0005). After this, a receiver can rely on `version`, `event`,
`timestamp` and the event header for every post, for the life of 1.x.

## User stories
- As a developer with a webhook receiver, I want every post to say which event and which contract
  version it is, so that I can route and validate posts without guessing from the body's shape.
- As a developer upgrading to 0.18, I want one place that lists every event and field, and exactly
  what changed, so that I can update my receiver in one pass.

## Requirements (EARS)

### The envelope
- **REQ-1.** Every JSON body RED posts to `config.webhook_urls` shall include `"version": 1` at the
  top level.
- **REQ-2.** Every such body shall include a top-level `event` and a top-level `timestamp`. The
  timestamp is the ISO 8601 time the body was built, in UTC.
- **REQ-3.** Every such post shall carry the header `X-Error-Dashboard-Event`, equal to the body's
  `event`.
- **REQ-4.** Every post about one error shall also carry `X-Error-Dashboard-ID`, set to that error's
  id. These are `error.created` and `baseline.anomaly_detected`.

### Event names (decision 0005)
- **REQ-5.** The storm notification shall be sent with event `storm.detected`.
- **REQ-6.** The notification-burst summary shall be sent with event `notifications.suppressed`.
- **REQ-7.** The baseline alert shall be sent with event `baseline.anomaly_detected`.
- **REQ-8.** The new-error notification shall keep event `error.created`.

### What doesn't change
- **REQ-9.** Every field present in a 0.17.0 body shall keep its name, type and meaning; the only
  changes are the three renamed `event` values and the added `version` and `timestamp`.
- **REQ-10.** When `webhook_signing_secret` is set, the signature headers shall verify against the
  exact bytes posted, for all four events.
- **REQ-11.** The bodies sent to Slack, Discord, Telegram, PagerDuty and email shall be unchanged.
- **REQ-12.** When a job enqueued by 0.17.0 runs after the upgrade, it shall post the v1 body.

### The contract page
- **REQ-13.** A contract page in `docs/` shall list:
  - every event RED can post, with an example body;
  - every field, with its type and when it can be null;
  - every header;
  - how to verify the signature;
  - the 1.x promise: events and fields may be added, never renamed or removed.
- **REQ-14.** A spec shall fail when an event name that RED can post is missing from the contract
  page.
- **REQ-15.** UPGRADING (`docs/UPGRADING.md` and `_getting_started/upgrading.md`) shall list the
  three renames and the new field and headers in its 0.18.0 section. The notifications guide
  (`docs/guides/NOTIFICATIONS.md` and `_guides/notifications.md`) shall show v1 bodies.

## Out of scope
- New events or fields beyond `version` and `timestamp`.
- Sending the old names as well (decision 0005, unless its reversal condition fires).
