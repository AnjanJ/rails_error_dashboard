# 0008: Config and ENV names are frozen as they are; `rails_error_dashboard:` is the rake namespace

- **Date:** 2026-10-29. Status: accepted (the maintainer chose both on 2026-10-29; drafted from
  `.shipkit/research/1-0-readiness.md`, blocker 2, re-checked at `6b1dfab`).

## Context

1.0 freezes every public name until 2.0. Two inconsistencies were on the table:
- **Config:** 37 options start with `enable_`, and six booleans don't: `async_logging`,
  `storm_notification`, `filter_sensitive_data`, `detect_swallowed_exceptions`,
  `only_show_app_code_source`, `system_health_queue_stats`.
- **ENV:** 30 names mix `RED_*`, `ERROR_DASHBOARD_*` and third-party conventions such as
  `SLACK_WEBHOOK_URL` and `GIT_SHA`.
- **Rake:** tasks live in two namespaces. `error_dashboard:` has 11 of the 13 and is what the cron
  docs use. `rails_error_dashboard:` matches the gem, the generators and Rails' own
  `rails_error_dashboard:install:migrations`.

Under decision 0007, a renamed public name keeps a warning alias until 2.0.

## Alternatives

1. **Config and ENV:** no renames; every name is documented in PUBLIC_API.md. **Rake:**
   `rails_error_dashboard:` survives, and `error_dashboard:*` stays as warning aliases until 2.0.
2. Rename the six booleans to `enable_*`, with warning aliases; ENV unchanged; same rake choice.
3. Rename config and ENV to one prefix, with warning aliases.

## Case for 1

- **Renames cost more than they give.** Each rename is alias code kept for all of 1.x, plus an edit
  in every initializer the installer wrote: `async_logging` is in all of them. The gain is
  cosmetic.
- **The ENV mix is partly correct.** `SLACK_WEBHOOK_URL` and `GIT_SHA` are names other tools set.
- **Rake is different.** Two namespaces make users guess, and the README already names a task
  that doesn't exist (`rails_error_dashboard:diagnostic_dump`). Merging fixes that, and the
  aliases keep every cron entry running.

## Case against 1

The config stays inconsistent for the life of 1.x: a user has to look up whether an option is
`enable_x` or bare. Option 2 fixes the most visible part for six aliases. And moving the 11 rake
tasks still means warnings in users' cron mail until they edit their crontabs.

## Decision

1. Implemented by spec `deprecations-0-18` (rake) and documented by `public-api-and-policies`
(names).

**I would reverse this if** two or more issues in 1.x report a user setting the wrong option because
of the `enable_` inconsistency. Then 1.x adds `enable_*` aliases for the six; adding a name is not
a breaking change.
**Fired-if.** manual
