# Spec: Smaller fixes for 0.18.0

> Spec accepted at commit `6b1dfab` on spec/0-18-0 (2026-10-29).
> Status: open
> Paths: lib/rails_error_dashboard/queries/,lib/rails_error_dashboard/services/pattern_detector.rb,lib/rails_error_dashboard/services/crash_capture.rb,lib/rails_error_dashboard/services/error_broadcaster.rb,app/models/rails_error_dashboard/error_log.rb,app/helpers/rails_error_dashboard/application_helper.rb,app/views/rails_error_dashboard/errors/,config/locales/,docs/UPGRADING.md,_getting_started/upgrading.md,spec/

## Purpose
Four small things are wrong in what the dashboard shows or records:
- crash sources appear as platforms;
- badges miss platforms written in other cases;
- development may record 404s that production doesn't;
- pattern hours don't say which time zone they're in.

Each one is a behavior a 1.x minor shouldn't change later, so 0.18.0 fixes them before the freeze.

## User stories
- As a developer comparing platforms, I want to see only the platforms my app actually runs on, so
  that the comparison means something.
- As a developer in development, I want a mistyped URL not to fill my dashboard, so that the errors
  shown are real ones.
- As a developer reading "errors peak at 14:00", I want to know which time zone that is.

## Requirements (EARS)

### Crash sources are not platforms
- **REQ-1.** Wherever the dashboard lists or compares platforms, it shall not list `boot_crash` or
  `crash_capture` as a platform. That covers the platform comparison page, the platform filter,
  correlation and resolution-time breakdowns.
- **REQ-2.** Errors recorded by crash capture shall still appear in the error list and on the Boot
  Errors page, as in 0.17.0.

### Badges
- **REQ-3.** Every platform badge shall match `ios`, `android` and `web` in any letter case: the
  error row, the timeline, similar errors and the error page's sidebar. (Widened at the design gate,
  2026-10-29, from the error row alone; the other three views carry the same branch.)

### Development 404s (reproduce first)
- **REQ-4.** While code reloading is enabled, RED shall record a routing error (an unknown URL)
  exactly when it would with reloading disabled and the same configuration. If the reproduction
  shows no difference, this requirement is dropped, and the evidence goes in `intake.md`.
  (Dropped at T4, 2026-10-30: no difference. The spec stays as the guard.)

### Pattern hours (reproduce first)
- **REQ-5.** Pattern insights shall compute and show hours in the app's `Time.zone`, and name that
  zone next to them. If the reproduction shows they already use `Time.zone`, only the label is
  added.

### Upgrade notes
- **REQ-6.** If REQ-4 changes a default, the 0.18.0 section of UPGRADING shall say what changed and
  how to restore the old behavior. [untested: dropped with REQ-4, which changed no default]

## Out of scope
- How `platform` is set at capture time.
