---
layout: default
title: "Batch Operations Guide"
permalink: /docs/guides/BATCH_OPERATIONS
---

# Batch Operations Guide

The error list can resolve or delete several errors at once. Muting and unmuting several errors is
also possible, from a script or the Rails console.

---

## In the dashboard

1. Open the error list, `/red/errors`.
2. Tick the checkbox at the start of each error's row, or the checkbox in the table header to select
   every error on the page. A toolbar appears above the table with the number selected and two
   buttons, **Resolve** and **Delete**.
3. Click **Resolve** or **Delete**.

You land on the first page of the error list with a message such as "Successfully resolved 3
errors". The filters you had set are cleared, except the application.

To clear the selection, untick the checkbox at the start of the toolbar, or the one in the table
header.

> **Delete doesn't ask for confirmation.** It deletes the selected errors straight away, together
> with their occurrences and comments, and they can't be recovered.

### What each action does

| Action | Effect |
|---|---|
| Resolve | Marks the errors resolved, with status `resolved`. It doesn't run your `on_error_resolved` callbacks, so linked issues in your issue tracker stay open. Plugins get `on_errors_batch_resolved` |
| Delete | Deletes the errors with everything recorded about them: occurrences, comments, cascade records and event counts. Plugins get `on_errors_batch_deleted` with the IDs |
| Mute (no button) | Mutes the errors, storing who and why. Unlike muting one error with a reason, no comment is added. Plugins get `on_errors_batch_muted` |
| Unmute (no button) | Unmutes them. Plugins get `on_errors_batch_unmuted` |

Every batch action needs the dashboard login, and anyone who can log in can use all of them.

### Limits

- **One page at a time.** The header checkbox selects the errors on the current page, and the
  selection doesn't survive changing pages. The list shows 25 errors a page. To act on more at once,
  add `per_page=100` to the URL (100 is the most), or use the console.
- **No transaction.** Each error is saved on its own. If one fails partway through, the ones before
  it stay changed.

---

## From a script

The toolbar posts to `POST /red/errors/batch_action` with `error_ids[]` and `action_type`
(`resolve`, `mute`, `unmute` or `delete`). The [API Reference](../API_REFERENCE.md#other-actions)
lists the extra fields, and [Posting from a script](../API_REFERENCE.md#posting-from-a-script) shows
how to get past the CSRF check.

---

## From the Rails console

These commands are what the toolbar calls. They are internal classes and can change between
releases.

```ruby
ids = RailsErrorDashboard::ErrorLog
  .unresolved
  .where(error_type: "NoMethodError", controller_name: "UsersController")
  .ids

RailsErrorDashboard::Commands::BatchResolveErrors.call(
  ids,
  resolved_by_name: "Deploy Bot",
  resolution_comment: "Fixed in release v2.3.1"
)
# => { success: true, count: 12, total: 12, failed_ids: [], errors: [] }
```

The others:

```ruby
RailsErrorDashboard::Commands::BatchMuteErrors.call(ids, muted_by: "ops", reason: "Known issue")
RailsErrorDashboard::Commands::BatchUnmuteErrors.call(ids)
RailsErrorDashboard::Commands::BatchDeleteErrors.call(ids)
```

What the result means:

- `count` is how many errors were saved, including any already in that state, and `total` is how
  many IDs you passed.
- IDs that don't exist are skipped without complaint: `count` is lower than `total`, and `success`
  is still `true`.
- `success` is `false` when saving an error raised. Then `errors` has a message. For resolve, mute
  and unmute, `failed_ids` lists the errors that weren't changed; it is missing when an exception
  stopped the whole batch.
- With an empty list, the result is `{ success: false, count: 0, errors: ["No error IDs provided"] }`.

To delete old errors, select by `last_seen_at`, which is when the error last happened.
`occurred_at` is when RED first recorded it:

```ruby
old_ids = RailsErrorDashboard::ErrorLog
  .where(environment: "development")
  .where("last_seen_at < ?", 1.week.ago)
  .ids

old_ids.each_slice(100) do |batch|
  result = RailsErrorDashboard::Commands::BatchDeleteErrors.call(batch)
  puts "Deleted #{result[:count]} of #{result[:total]}"
end
```

For deleting old errors on a schedule, use `RetentionCleanupJob` instead. See
[Schedule the periodic jobs](../PRODUCTION.md#2-schedule-the-periodic-jobs).

---

## Troubleshooting

### The toolbar doesn't appear

- It appears only once you tick an error, and only when the list has errors.
- It needs JavaScript. Look for errors in the browser console.
- A Content Security Policy that blocks inline scripts stops it. RED adds your app's CSP nonce to its
  scripts, so a policy with a nonce generator (`content_security_policy_nonce_generator`) works.

### "Batch operation failed"

The message after "Batch operation failed:" says why:

- **No error IDs provided**: nothing was selected.
- **Invalid action type**: `action_type` wasn't `resolve`, `mute`, `unmute` or `delete`.
- **Failed to resolve N errors** (or mute, unmute): saving those errors raised.
- Anything else is the message of an exception that stopped the whole batch.

RED logs the details only when `config.log_level` is `:error` or lower. The default is `:silent`.

---

## Related Documentation

- [Documentation index](../README.md) - All the guides
- [Notifications](NOTIFICATIONS.md) - Notification setup
- [Plugin System](../PLUGIN_SYSTEM.md) - The batch plugin hooks
