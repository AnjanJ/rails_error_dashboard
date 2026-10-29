# 0005: Webhook contract v1 ships in 0.18 as one clean change

- **Date:** 2026-10-29. Status: accepted (the maintainer confirmed on 2026-10-29; drafted from
  `.shipkit/research/1-0-readiness.md`, re-checked on `main` at ccc28e9).

## Context

Four events reach the generic webhook URLs (`config.webhook_urls`), and the contract has no
version.

- Bodies carry no schema version (`services/webhook_payload_builder.rb:31`).
- Event names use three styles:
  - `error.created` (`webhook_payload_builder.rb:31`);
  - `error_storm_detected` (`storm_notification_job.rb:23`);
  - `new_error_notifications_suppressed` (`notification_burst_summary_job.rb:29`);
  - `baseline_anomaly` (`baseline_alert_payload_builder.rb:179`).

  The storm and burst events go through `concerns/plain_channel_message.rb:37-38`.
- The `X-Error-Dashboard-Event` header is sent only for `error.created`
  (`webhook_error_notification_job.rb:34`).

Adding a version after 1.0 breaks every receiver that validates the body, so the contract has
to be fixed before the freeze. `error.created` fires on every new error; the other three are
rare (storms, notification bursts, baseline anomalies).

## Alternatives

1. One clean change in 0.18: add `version: 1` to every body, put the event header on every post,
   rename the three odd events to one style, and write a loud UPGRADING note.
2. Send both formats for a while: old and new names side by side through 0.18 and 0.19, then
   drop the old ones at 1.0.
3. Additive only: add `version: 1` and the header everywhere, and freeze today's names as they
   are.

## Case for 1

`error.created`, the event nearly every receiver handles, already has the target style and
doesn't change, so the break is limited to three rare events. Pre-1.0 is the last time a rename
is cheap. "Both formats" has no clean shape: a receiver matches on `event`, so a second field
doesn't save it, and sending every event twice doubles the traffic and confuses receivers. A
receiver can then rely on `version` and the header for the life of 1.x.

## Case against 1

Receivers that handle storm, burst or baseline events break on upgrade to 0.18 until their owner
renames three strings, and RED has no list of who they are. Option 3 breaks nobody, at the price
of three inconsistent names frozen until 2.0.

## Decision

1. In 0.18 every webhook body gets `version: 1` and every post gets `X-Error-Dashboard-Event`.
The three odd events are renamed to `resource.event` style:

| Today | 0.18 |
|---|---|
| `error_storm_detected` | `storm.detected` |
| `new_error_notifications_suppressed` | `notifications.suppressed` |
| `baseline_anomaly` | `baseline.anomaly_detected` |

The new names can still change in review before 0.18 ships. `docs/` gets a webhook contract page
naming every event and field, and UPGRADING lists the renames. At 1.0 the contract is frozen;
new events and new fields may be added in 1.x minors.

**I would reverse this if** two or more users report a broken webhook receiver within one month
of 0.18. Then 0.18.x sends the old names as well until 1.0.
**Fired-if.** manual
