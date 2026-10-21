# What RED 1.0 needs

> Researched 2026-10-21 at `d34cee7` (v0.16.1). Not yet a spec: the decisions below come first,
> then `/shipkit:spec` turns this into requirements. Goal of record: `.shipkit/product.md`
> ("Ship 1.0 … by 2026-12-31").

## What 1.0 should mean

A stability release, not a feature release. A host app pinned to `~> 1.0` takes every 1.x minor
on `bundle update`, so every 1.x minor must be safe to take blind. 1.0 therefore means:

- a written public API, with everything else marked private;
- versioned outbound contracts (webhooks, health JSON);
- a published deprecation and supported-versions policy;
- the host-app overhead budgets proven by a reproducible benchmark;
- no open host-safety bugs.

One contradiction to settle: `ROADMAP.md:698` names a "Full Context Error Report" feature as
"the v1.0 anchor". The recommendation here is to move it to 1.1.

## Blockers (must be true before 1.0)

1. **The public API is written down** (e.g. `docs/PUBLIC_API.md`), naming what is frozen. Today's
   surface:
   - 143 config options and 29 ENV names in `configuration.rb`
   - module methods (`lib/rails_error_dashboard.rb:187-304`) and the
     `ManualErrorReporter.report` signature (`manual_error_reporter.rb:79-93`)
   - 11 plugin hooks; `docs/PLUGIN_SYSTEM.md` matches the code
   - 27 install-generator flags; 13 rake tasks across two namespaces
   - the mount routes; the health JSON (`queries/health_status.rb:60-64`)
   - webhook bodies and headers (`services/webhook_signer.rb:26-28`); OTel span names
     (`integrations/tracer.rb:41-90`)
   - 52 migrations, 15 tables. Recommend declaring the tables private.
2. **Clean the surface before freezing it.** Deprecate in 0.17 with warnings; remove at 1.0.
   - `async_adapter` is a no-op: only validated (`configuration.rb:673-677`) and shown on
     Settings. Its default is `:sidekiq` (`configuration.rb:386`); the template sets `:async`
     (`install/templates/initializer.rb:194`).
   - `llm_observability_content_capture` is read nowhere (`configuration.rb:260,530`); the docs
     call it "Reserved for future use". Do not freeze an inert privacy flag.
   - Two rake namespaces, `error_dashboard:` and `rails_error_dashboard:`. Merge them, keeping
     aliases that warn.
   - The deprecated `rails_error_dashboard:solid_queue` generator still ships.
   - Naming: `enable_x` beside bare names (`async_logging`, `storm_notification`); ENV mixes
     `RED_*`, `ERROR_DASHBOARD_*`, `USE_SEPARATE_ERROR_DB`, `BASELINE_ALERT_THRESHOLD`. Pick one
     convention; keep the old names as warning aliases.
3. **Version the webhook contract now.** Adding a version after 1.0 breaks receivers.
   - The body has no schema version (`services/webhook_payload_builder.rb:31`).
   - Event names use three styles: `error.created`, `error_storm_detected`,
     `new_error_notifications_suppressed`, `baseline_anomaly`.
   - `X-Error-Dashboard-Event` is sent only for `error.created`
     (`webhook_error_notification_job.rb:34`).
   - Add `version: 1`, one naming style, the header on every post. Also document the health
     check's `skipped` status (`queries/health_status.rb:162-171`).
4. **Publish the policies** (SemVer requires at least one minor carrying a deprecation before
   removal):
   - deprecations warn for at least two minors and are removed only in 2.0, with a 1.99 bridge
     release that warns about everything 2.0 removes (GoodJob's model);
   - Rails and Ruby minimums rise only at a major;
   - migrations in a minor are additive and replay-safe;
   - security fixes for the previous major.
5. **The overhead benchmark ships** (product goal 2): a committed script, run in CI, replacing the
   README's single-machine figures (`README.md:128,161`).
6. **No open host-safety bugs.**
   - E2: git blame wraps `Open3.capture3` in `Timeout.timeout`
     (`services/git_blame_reader.rb:97`); on timeout the child `git` keeps running in the host
     app's process tree.
   - E1: a path outside `Rails.root` is cut to its basename, so View Source can show the wrong
     file (`services/source_code_reader.rb:104-108`).
7. **The upgrade path is tested** from every 0.x minor to 1.0 in the release scenarios, and
   UPGRADING gets a "0.x to 1.0" section.

## Strongly recommended

- **Minimums at 1.0: Rails 7.2, Ruby 3.3.** Rails 7.0, 7.1 and 7.2 and Ruby 3.2 are EOL; Rails
  8.0's security support ends 2026-11-07. Pagy 43.5 and groupdate 6.8 already require Ruby 3.3
  (groupdate 6.8 also needs Active Record 7.2), so the lower CI rows test old dependency versions.
  The CI matrix would shrink from 20 rows to 9. Against: Honeybadger still floors at Rails 5.2,
  and 0.16.1 was spent helping Rails 7.0 users.
- **Pagy.** `pagy ~> 43.0` keeps users off any Pagy 44, and apps on bullet_train (`~> 9`) or
  govuk-components (`< 10`) cannot install RED at all. Cheapest: widen to `>= 43.0` (Avo's
  choice). Fuller: replace it with built-in pagination (Madmin 3.0.0 did, 2026-09-30); it is used
  in 82 places across 21 files. Neither change breaks users, so it need not gate 1.0.
- **groupdate** is used at two call sites (`queries/error_correlation.rb:190`,
  `services/baseline_calculator.rb:161`) but drops support in minors and is why MySQL needs time
  zone tables. A later, non-breaking replacement candidate.
- **`USE_SEPARATE_ERROR_DB`** does nothing on generator installs
  (`install/templates/initializer.rb:241,257`): fix or remove before the freeze.
- **Turn on Dependabot alerts and code scanning** (both off today).
- **Docs pass:** ROADMAP's header still says v0.14.0, lists C3 as open, and counts 3 advisories
  (5 published); `docs/CUSTOMIZATION.md:72` calls a nonexistent `severity_calculator` "planned";
  remove the "Beta" label (`README.md:26`, `docs/FAQ.md:16`).
- **Smaller real bugs:** `boot_crash`/`crash_capture` show as platforms (`services/crash_capture.rb:39-40`,
  unfiltered in `queries/platform_comparison.rb:54-93`); with reloading on, development records
  404s (`ignored_exceptions` defaults to `[]`, `configuration.rb:367`); error-row badges know only
  exact `iOS`/`Android`/`Web` (`_error_row.html.erb:91-99`); pattern hours carry no time zone.

## Decisions for the maintainer

1. Is 1.0 stability-only, with the roadmap's "v1.0 anchor" moved to 1.1?
2. Minimum Rails and Ruby at 1.0.
3. `async_adapter` and `llm_observability_content_capture`: remove or implement?
4. Webhook v1: change in 0.17 with a loud upgrade note, or send both formats for a while?
5. Pagy: widen or replace?

## Suggested path to 2026-12-31

| Release | Contents | When |
|---|---|---|
| 0.17.0 | deprecations, webhook v1, public API list, policies, benchmark in CI, E1/E2, Pagy | mid-November |
| 1.0.0.rc1 | removals, raised minimums, docs pass, upgrade scenarios; ask early users to try it | early December |
| 1.0.0 | after about two quiet weeks on the RC | by 2026-12-31 |

Not 1.0 work: RED Pro, the community translations, and the roadmap's open feature ideas
(merge/split, access roles, AI summaries).

## How this was checked

The public-surface inventory and the open-items audit were each done by a read-only agent against
`29ca15a`, with file:line evidence. Re-checked by hand: the `async_adapter` and
`content_capture` no-ops, the webhook event names, E2, Pagy and groupdate usage, and the Ruby
floors of Pagy 43.5.0 and groupdate 6.8.0 (RubyGems API). One agent claim proved false and is
excluded: `on_critical_error` does fire (`commands/log_error.rb:830-835`).

Sources for support windows and comparable gems: https://rubyonrails.org/maintenance,
https://endoflife.date/rails, https://endoflife.date/ruby,
https://www.ruby-lang.org/en/downloads/branches/, https://semver.org/,
https://guides.rubygems.org/versioning/, https://github.com/bensheldon/good_job,
https://github.com/rails/solid_queue/blob/main/UPGRADING.md,
https://docs.honeybadger.io/lib/ruby/gem-reference/supported-versions/,
https://ddnexus.github.io/pagy/changelog, https://github.com/excid3/madmin/blob/main/CHANGELOG.md,
https://github.com/ankane/groupdate/blob/master/CHANGELOG.md.
