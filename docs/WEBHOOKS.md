---
layout: default
title: "Webhook Contract"
permalink: /docs/WEBHOOKS
---

# Webhook Contract

What RED posts to `config.webhook_urls`, and what you can rely on for the life of 1.x.

## The promise

`version` stays 1 for all of 1.x. Events and fields may be added, never renamed or removed, so ignore
anything you don't recognize. A new event or field is not a breaking change.

This page covers `webhook_urls` only. Messages to Slack, Discord, Telegram, PagerDuty and email are
written for people, so they aren't part of this contract and can change in any release.

## Every body

| Field | Type | Can be null? | Meaning |
|---|---|---|---|
| `version` | integer | No | The contract version: `1` |
| `event` | string | No | One of the events below |
| `timestamp` | string | No | When RED built this body: ISO 8601, always UTC, ending in `Z` |

Other time fields, such as `occurred_at`, use the app's `config.time_zone`. Compare them as instants,
not as strings.

## Events

| Event | Sent when | Names one error? |
|---|---|---|
| `error.created` | An error passes your notification rules | Yes |
| `baseline.anomaly_detected` | An error type goes above its baseline, at most once per cooldown | Yes |
| `storm.detected` | An error storm starts, once per storm | No |
| `notifications.suppressed` | The burst limit is first passed, once per burst | No |

## Headers

| Header | Sent with | Value |
|---|---|---|
| `Content-Type` | Every post | `application/json` |
| `User-Agent` | Every post | Starts with `RailsErrorDashboard/` |
| `X-Error-Dashboard-Event` | Every post | The same as the body's `event` |
| `X-Error-Dashboard-ID` | Events that name one error | The error's `id` |
| `X-Error-Dashboard-Timestamp` | Every post, once a signing secret is set | Unix seconds when RED sent it |
| `X-Error-Dashboard-Signature-256` | Every post, once a signing secret is set | `sha256=` and the hex digest |

## Verifying a signature

Set `config.webhook_signing_secret`, and RED signs every post with HMAC-SHA256 over
`"<timestamp>.<raw body>"`. The timestamp comes from `X-Error-Dashboard-Timestamp`. Hash the bytes you
received: parsing the JSON and serializing it again gives a different result.

In Ruby, the gem ships the check, which also refuses a timestamp more than 300 seconds off:

```ruby
RailsErrorDashboard::Services::WebhookSigner.valid?(
  request.raw_post,
  timestamp: request.headers["X-Error-Dashboard-Timestamp"],
  signature: request.headers["X-Error-Dashboard-Signature-256"],
  secret: ENV.fetch("WEBHOOK_SIGNING_SECRET")
)
```

For other languages, see [Signing](guides/NOTIFICATIONS.md#signing-hmac-sha256).

## error.created

```json
{
  "version": 1,
  "event": "error.created",
  "timestamp": "2026-11-20T10:30:00Z",
  "error": {
    "id": 123,
    "application": "Shop",
    "type": "NoMethodError",
    "message": "undefined method 'name' for nil",
    "severity": "high",
    "platform": "Web",
    "environment": "production",
    "controller": "orders",
    "action": "create",
    "occurrence_count": 5,
    "first_seen_at": "2026-11-20T09:00:00Z",
    "last_seen_at": "2026-11-20T10:30:00Z",
    "occurred_at": "2026-11-20T10:30:00Z",
    "resolved": false,
    "request": {
      "url": "https://shop.example.com/orders",
      "params": { "id": "1" },
      "user_agent": "Mozilla/5.0",
      "ip_address": "203.0.113.7"
    },
    "user": { "id": 7 },
    "backtrace": [ "app/controllers/orders_controller.rb:12:in 'create'" ],
    "metadata": {
      "error_hash": "a1b2c3d4e5f60718",
      "dashboard_url": "https://shop.example.com/red/errors/123"
    }
  }
}
```

| Field | Type | Can be null? | Meaning |
|---|---|---|---|
| `error` | object | No | The error |
| `id` | integer | No | The error's id |
| `application` | string | No | The application's name, or `Unknown` |
| `type` | string | No | The exception class |
| `message` | string | No | The exception message |
| `severity` | string | No | `critical`, `high`, `medium` or `low` |
| `platform` | string | Yes | Where it happened, such as `Web` or `iOS` |
| `environment` | string | Yes | Such as `production`. Null if it wasn't recorded |
| `controller`, `action` | string | Yes | Null outside a request |
| `occurrence_count` | integer | No | How many times it has happened |
| `first_seen_at`, `last_seen_at` | string | Yes | ISO 8601, in the app's time zone |
| `occurred_at` | string | No | ISO 8601, in the app's time zone |
| `resolved` | boolean | No | Whether it's marked resolved |
| `request` | object | No | The request. Its fields can be null outside a request |
| `url`, `user_agent`, `ip_address` | string | Yes | From the request |
| `params` | object | No | The request parameters, or `{}` |
| `user` | object | No | Who it happened to |
| `user`'s `id` | integer | Yes | Null without a signed-in user |
| `backtrace` | array of strings | No | Up to 20 lines, or `[]` |
| `metadata` | object | No | Links back to RED |
| `error_hash` | string | Yes | The error's fingerprint |
| `dashboard_url` | string | No | The error's page in RED |

## baseline.anomaly_detected

```json
{
  "version": 1,
  "event": "baseline.anomaly_detected",
  "timestamp": "2026-11-20T10:30:00Z",
  "error": {
    "id": 123,
    "application": "Shop",
    "type": "NoMethodError",
    "message": "undefined method 'name' for nil",
    "platform": "Web",
    "severity": "high",
    "occurred_at": "2026-11-20T10:30:00Z"
  },
  "anomaly": {
    "level": "high",
    "std_devs_above": 3.2,
    "threshold": 10.5,
    "baseline_type": "hourly"
  },
  "dashboard_url": "https://shop.example.com/red/errors/123"
}
```

`error` has the fields of the same name above, and `dashboard_url` is the error's page in RED.

| Field | Type | Can be null? | Meaning |
|---|---|---|---|
| `anomaly` | object | No | How far above its baseline it is |
| `level` | string | No | `elevated`, `high` or `critical` |
| `std_devs_above` | number | No | Standard deviations above the baseline's mean |
| `threshold` | number | No | The count this alert was measured against |
| `baseline_type` | string | No | `hourly`, `daily` or `weekly` |

## storm.detected

```json
{
  "version": 1,
  "event": "storm.detected",
  "timestamp": "2026-11-20T10:30:00Z",
  "started_at": "2026-11-20T10:29:58Z",
  "state": "shedding",
  "application": "Shop"
}
```

| Field | Type | Can be null? | Meaning |
|---|---|---|---|
| `started_at` | string | No | When the storm started, ISO 8601 |
| `state` | string | No | `shedding` or `open` |
| `application` | string | No | The application's name |

## notifications.suppressed

```json
{
  "version": 1,
  "event": "notifications.suppressed",
  "timestamp": "2026-11-20T10:30:00Z",
  "limit": 20,
  "window_seconds": 300,
  "application": "Shop"
}
```

Sent when suppression starts, so it states the limit, not a count. Every error is still recorded.

| Field | Type | Can be null? | Meaning |
|---|---|---|---|
| `limit` | integer | No | `config.notification_burst_limit` |
| `window_seconds` | integer | No | `config.notification_burst_window_seconds` |
| `application` | string | No | The application's name |
