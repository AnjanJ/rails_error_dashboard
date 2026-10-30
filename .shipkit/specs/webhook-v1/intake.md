# Intake: webhook contract v1

> Intake taken on 2026-10-29.

## Request
Implement decision 0005 in 0.18.0:
- every body sent to `config.webhook_urls` carries `version: 1`;
- every post carries `X-Error-Dashboard-Event`;
- three events are renamed;
- a contract page in `docs/` names every event, field and header.

## Serves goal
"Ship 1.0 … with config and public API frozen" (`.shipkit/product.md`). The research's blocker 3:
adding a version after 1.0 would break every receiver that validates the body.

## Conflicts found
- **Decision 0005** is the scope. Its reversal: two or more broken-receiver reports within a month
  of 0.18 means 0.18.x also sends the old names.
- **Paramount rules:** none touched. Every webhook post is already async, in a job.
- **Open specs:** `deprecations-0-18` also edits UPGRADING. The two specs add separate subsections
  under the same 0.18.0 heading.

## Answers (2026-10-29)
1. Event names: **0005's names**: `storm.detected`, `notifications.suppressed`,
   `baseline.anomaly_detected`. `error.created` is unchanged.

## Assumptions made
- **Every body gets a `timestamp` too.** `error.created` and the baseline body have one; the storm
  and burst bodies don't, and a common envelope (`version`, `event`, `timestamp`) is what receivers
  can rely on. Adding a field breaks no receiver.
- **`X-Error-Dashboard-ID` goes on every post that is about one error:** `error.created` (as
  today) and `baseline.anomaly_detected`. Storm and burst posts aren't about one error.
- **Slack, Discord, Telegram, PagerDuty and email are not part of this contract.** Their bodies are
  set by the receiving service and stay as they are.
- **No compatibility mode.** Decision 0005 rejected sending both names.

## Out of scope
- New events or new fields beyond `version` and `timestamp`.
- Changing how bodies are signed: the same headers and algorithm, over the bytes actually sent.
