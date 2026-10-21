# Tasks: Environment awareness

Test first for each. Run targeted specs with `--pattern`, RuboCop, and `bin/i18n-check` after
each task; full suite + `bin/pre-release-test all` before the PR.

- [x] **T1** Configuration: `environment`, `notification_environments`, `current_environment`,
  `validate!` → REQ-1..4 (test: ENV defaults; blank/65-char environment raises; `["prod", ""]`
  raises; nil allowed; `current_environment` falls back to `Rails.env`.)
- [x] **T2** Migration + dummy `schema.rb` + `ErrorLog.by_environment` → REQ-8 (test: column
  present with limit 64; index present; migration is a no-op when the column exists.)
- [x] **T3** `LogError` stores environment; `context[:environment]` override; column-absent
  guard → REQ-5, REQ-6, REQ-7 (test: captured error has `environment == "test"`; with
  `config.environment = "uat"` → `"uat"`; with `context[:environment] = "remote-x"` →
  `"remote-x"`; with `ErrorLog.column_names` stubbed to exclude it, capture succeeds and no
  error is logged.)
- [x] **T4** `FindOrIncrementError` match + adoption → REQ-9, REQ-10, REQ-11 (test: same hash
  in "production" and "staging" → two rows; NULL-environment row is incremented by a
  "production" occurrence and gains `environment: "production"`; exact match preferred over
  NULL when both exist; resolved NULL row is reopened and stamped; `error_hash` unchanged —
  existing `ErrorHashGenerator` specs untouched.)
- [x] **T5** `FlushStormCounts` environment match + `COALESCE` adoption → REQ-12 (test: counts
  land on the row for the flushing process's environment; NULL row adopted.)
- [x] **T6** Rake `backfill_environments` → REQ-13 (test: rows with
  `environment_info.rails_env` set get the value; rows without stay NULL; already-set rows
  untouched; returns the count.)
- [x] **T7** Index filter, chip, row badge, `FilterOptions`, `ErrorsList`, `ErrorBroadcaster`
  → REQ-14, REQ-15, REQ-16, REQ-21 (request spec in `errors_index_filter_pills_spec.rb` style:
  select absent with one environment, present with two; `?environment=staging` lists only
  staging rows and renders "Environment: staging" chip; badge cell present only with two
  environments; broadcaster passes `show_environment`.)
- [x] **T8** Sidebar badge + link → REQ-17 (request spec on `show`: link to
  `errors_path(environment: "staging", unresolved: "0")`; absent for NULL.)
- [x] **T9** Analytics chart → REQ-18 (query spec: `errors_by_environment` grouped counts with
  nil mapped to `"unknown"` key; view: chart rendered only when >1.)
- [x] **T10** Settings page rows → REQ-19.
- [x] **T11** i18n: all 11 keys in en.yml, then the other ten locales via
  `bin/i18n-merge <loc> batch.yml --partial`; `bin/i18n-check` exit 0 → REQ-20.
- [x] **T12** `NotificationThrottler.environment_allowed?` wired into `maybe_notify`, storm
  notification, baseline alert → REQ-22, REQ-23, REQ-24 (test: nil list → dispatcher called;
  `%w[production]` with a staging error → dispatcher NOT called for new, reopened, and
  threshold paths; storm notification suppressed when process env not listed.)
- [x] **T13** Payloads: Slack, Discord, webhook, PagerDuty, mailer body + subject → REQ-25,
  REQ-26 (test per builder: field present with value, absent when NULL; subject uses
  `subject_with_environment` when present.)
- [x] **T14** Formatters: markdown + issue body → REQ-27.
- [x] **T15** Initializer template, CONFIGURATION.md ×2, FEATURES.md, README bullet, CHANGELOG
  prose → REQ-28.
- [x] **T16** Chaos: Phase D asserts `environment=production` filter and row badge absence
  (single env) → REQ-29.
- [x] **T17** Full suite, RuboCop, `bin/i18n-check`, `bin/pre-release-test all`; commit as
  `feat(environment): …` with `Refs #…` (no closing keyword); open PR. Post-release:
  `/demo-update` **with the migration and both schema dumps** ([[red-demo-update-migrations]]).
