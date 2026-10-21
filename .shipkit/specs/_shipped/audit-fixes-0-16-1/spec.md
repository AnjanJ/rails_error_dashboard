# Spec: Audit fixes for 0.16.1

> Spec accepted at commit `bd08d75` on spec/0-16-1.
> Status: shipped in 0.16.1 (#298)
> Paths: lib/rails_error_dashboard/queries/platform_comparison.rb,app/views/rails_error_dashboard/errors/,config/locales/,docs/,_features/,_reference/,_getting_started/,spec/,.shipkit/specs/_shipped/audit-fixes-0-16-0/design.md

## Purpose
Fix what 0.16.0's audit left: a platform health score that can't rate an evenly split app
Healthy, punishes the slowest platform and rewards a platform that resolves nothing; health
cards for platforms with no recent errors; business-hours copy that disagrees with the
detector; and platform names shown as "Ios" and "Api". See `intake.md`.

## User stories
- As a developer comparing platforms, I want a platform that is no worse than the others rated
  Healthy, so the ratings point at the platform that actually needs work.

## Requirements (EARS)

"The window" is the period Platform Comparison is showing. "Active platforms" are the platforms
with at least one error in the window.

### Platform health score
- **REQ-1.** When active platforms have equal error counts and equal average resolution times,
  Platform Comparison shall give them equal stability scores high enough to rate Healthy (80 or
  more).
- **REQ-2.** Platform Comparison shall give full volume credit to an active platform whose share
  of the window's errors is at most an even split (1 / the number of active platforms).
- **REQ-3.** If an active platform's share of the window's errors is above an even split, then
  Platform Comparison shall give it less volume credit than a platform with a smaller share.
- **REQ-4.** Platform Comparison shall give full resolution credit to the active platform with
  the fastest average resolution time, and to any platform that is as fast.
- **REQ-5.** If an active platform resolves more slowly than the fastest, then Platform
  Comparison shall reduce its resolution credit by how much slower it is. A platform with an even
  share that takes 12 hours against the fastest's 10 shall still rate Healthy.
- **REQ-6.** If an active platform has no errors resolved in the window, then Platform Comparison
  shall score it on volume alone, on the same 0-100 scale.
- **REQ-7.** If an active platform has no errors resolved in the window, then each card that
  shows its score shall say that no errors were resolved in the window.
- **REQ-8.** Platform Comparison and the Overview shall show no score and no health card for a
  platform with no errors in the window.
- **REQ-9.** The Platform Comparison guide shall explain the score as it is computed, with a
  worked example. [untested: prose, verified by reading]

### Business-hours copy
- **REQ-10.** The business-hours pattern description shall state the hours the pattern detector
  counts, 09:00 to 17:59, in every dashboard locale.

### Platform names
- **REQ-11.** Platform Comparison and Correlation shall show each platform's name as it is stored
  ("iOS", "API"), in chart labels and in card headings.

## Out of scope
- Internal platform values (`boot_crash`, `crash_capture`) appearing as platforms.
- Badge and icon mappings in the error-row partials.
- Labelling the time zone of pattern hours, or changing the business-hours range.

## Release steps
Not requirements:
- The 0.16.1 release notes say that platform scores change again, and why.
