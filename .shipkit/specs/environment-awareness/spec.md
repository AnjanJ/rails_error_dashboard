# Spec: Environment awareness

> Spec accepted at commit `8e51278` on main (2026-08-26). Decisions taken at the Q1 gate:
> release as **0.11.0**; environment is a **match dimension** (separate rows per environment);
> notification rule is an **allowlist**; analytics breakdown **included**.

## Purpose

Record which environment each error came from (production, staging, uat, …), let the dashboard
filter and badge by it, and let notifications be limited to the environments that matter. RED
had this in v0.1.x and removed it in the v1.0-launch refactor (`a69e77b`, no stated reason);
the v0.9.1 advisory (GHSA-qhgm-3pxf-mvc6) showed that "which environment am I in" is a question
this gem has to answer well. Roadmap item 9.

Environment names are **free-form strings**, never an enum — the advisory's lesson was that
teams invent environment names (`uat`, `demo`, `preprod`) and any fixed list is wrong tomorrow.

## User stories

- As a developer with staging and production sharing one RED database, I want to filter the
  errors index to production so that staging noise does not hide real incidents.
- As an on-call engineer, I want Slack and PagerDuty to fire only for production so that a
  staging deploy does not page me at 3am.
- As a developer reading an error, I want to see at a glance which environment it came from,
  in the row, on the detail page, and in the notification.
- As a maintainer, I want the same error in staging and in production to be two rows with
  independent status, so that resolving one does not hide the other.

## Requirements (EARS)

### A. Configuration

- **REQ-1.** The gem shall provide an `environment` configuration option (String), defaulting
  from `ERROR_DASHBOARD_ENVIRONMENT`, and when unset shall resolve to `Rails.env` at capture
  time.
- **REQ-2.** If `environment` is set to a blank string or a string longer than 64 characters,
  then `validate!` shall raise `ConfigurationError`.
- **REQ-3.** The gem shall provide a `notification_environments` option (Array of String or
  nil, default nil), defaulting from `ERROR_DASHBOARD_NOTIFICATION_ENVIRONMENTS` split on
  commas with whitespace stripped.
- **REQ-4.** If `notification_environments` is set to anything other than nil or a non-empty
  array of non-blank strings, then `validate!` shall raise `ConfigurationError`.

### B. Capture and storage

- **REQ-5.** When an error is captured and the `environment` column exists, the gem shall
  store the resolved environment on the error log.
- **REQ-6.** When an error is captured with `context[:environment]` present, the gem shall
  store that value instead of the configured one (seam for the remote transport).
- **REQ-7.** While the `environment` column does not exist (host has not run the migration),
  the gem shall capture errors exactly as today, without raising or logging errors.
- **REQ-8.** The gem shall ship a migration adding a nullable `environment` string column
  (limit 64) and an index on `[environment, occurred_at]`, guarded against the squashed schema.

### C. Deduplication

- **REQ-9.** When matching a new occurrence to an existing error log, the gem shall require
  the existing row's environment to equal the new occurrence's environment **or be NULL**,
  preferring an exact match.
- **REQ-10.** When a NULL-environment row is matched (incremented or reopened), the gem shall
  set its environment to the new occurrence's environment.
- **REQ-11.** The gem shall not change how `error_hash` is computed.
- **REQ-12.** When storm count increments are reconciled, the gem shall apply the same
  environment matching and adoption as REQ-9 and REQ-10.
- **REQ-13.** The gem shall provide a rake task `rails_error_dashboard:backfill_environments`
  that sets `environment` from `environment_info.rails_env` on rows where it is NULL, in
  batches, and reports how many rows were updated.

### D. Dashboard

- **REQ-14.** When more than one distinct environment exists (within the current application
  filter), the errors index shall show an environment select in the advanced filters.
- **REQ-15.** When `environment` is present in the index params, the gem shall filter the list
  to that environment and show an active-filter chip naming it.
- **REQ-16.** When more than one distinct environment exists, each error row shall show an
  environment badge.
- **REQ-17.** The error detail sidebar shall show the environment as a badge linking to the
  index filtered by that environment, when the error has one.
- **REQ-18.** When more than one distinct environment has errors in the analytics window, the
  analytics page shall show an "errors by environment" chart; otherwise it shall not.
- **REQ-19.** The settings page shall display `environment` and `notification_environments`.
- **REQ-20.** All new dashboard strings shall exist in all eleven locales and `bin/i18n-check`
  shall pass; environment names themselves are never translated.
- **REQ-21.** Real-time (Turbo) row broadcasts shall include the environment badge under the
  same condition as REQ-16.

### E. Notifications

- **REQ-22.** While `notification_environments` is nil, the gem shall notify for every
  environment (today's behaviour).
- **REQ-23.** While `notification_environments` is set, if an error's environment is not in
  the list, then the gem shall send no error notification for it — new, reopened, or
  threshold — on any channel.
- **REQ-24.** While `notification_environments` is set and the current process's environment
  is not in the list, the gem shall send no storm notification and no baseline alert.
- **REQ-25.** Every notification payload (Slack, Discord, webhook, PagerDuty, email) shall
  include the error's environment when present.
- **REQ-26.** When the error has an environment, the email subject shall include it alongside
  the application name.

### F. Other surfaces

- **REQ-27.** "Copy for LLM" markdown and issue-tracker bodies shall state the environment
  when present.
- **REQ-28.** The generated initializer shall document `environment` and
  `notification_environments`, and the configuration guide (both copies) shall list them.
- **REQ-29.** The chaos suite shall assert that errors captured in the production-mode test
  apps carry `environment = "production"` and that the index filter honours it.

## Out of scope

- Per-channel allowlists, a `notify_if` lambda, per-environment retention or sampling.
- Backfilling `environment` automatically inside the migration (REQ-13's task is opt-in; the
  lazy adoption in REQ-10 covers live errors without it).
- Changing the navbar badge, which shows the **dashboard host's** `Rails.env` and is unrelated.
- Environment-scoped dashboard credentials or authentication.
