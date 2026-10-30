# Intake: smaller fixes for 0.18.0

> Intake taken on 2026-10-29.

## Request
Four smaller bugs from the 1.0 readiness research's "strongly recommended" list, all chosen for 0.18
on 2026-10-29:
1. **Crash platforms.** `boot_crash` and `crash_capture` (`services/crash_capture.rb:39-40`) show up
   as platforms. They're capture sources. Verified: `queries/platform_comparison.rb` never filters
   them.
2. **Row badges.** Error-row platform badges match only the exact strings `iOS`, `Android` and
   `Web` (`errors/_error_row.html.erb:91-95`). Verified.
3. **Development 404s.** With code reloading on, development records 404s, because
   `ignored_exceptions` defaults to `[]` (`configuration.rb:373`). Not yet reproduced.
4. **Pattern hours.** The hours in pattern insights carry no time zone
   (`services/pattern_detector.rb:44` takes `timestamp.hour`). Not yet reproduced.

## Serves goal
"Ship 1.0" (`.shipkit/product.md`). These fixes change behavior that a 1.x minor shouldn't change,
such as a default and what a page lists, so they belong before the freeze.

## Conflicts found
- **Non-goal: no removing a shipped free feature.** Hiding crash sources from platform lists removes
  nothing: crash-captured errors stay in the error list and on the Boot Errors page.
- **Changing a default (item 3) is a behavior change.** If the fix is a new default for
  `ignored_exceptions`, apps that relied on recording these errors notice. UPGRADING must say so.
- **Open specs:** `deprecations-0-18` edits `configuration.rb` too. The tasks order the two.

## Answers (2026-10-29)
1. All four go into 0.18. Items 3 and 4 only after a reproduction. One that doesn't reproduce is
   dropped with the evidence recorded here.

## Assumptions made
- **Item 3 aims for the same result as production:** reloading on or off, RED records a routing
  error the same way. The design picks the mechanism after the reproduction.
- **Item 4 uses the app's `Time.zone`** and labels it.

## Out of scope
- Other platform-detection changes (how `platform` is set at capture).

## Reproduced at T4 (2026-10-30): development doesn't record 404s
REQ-4 is dropped: there is no difference to fix. `spec/requests/development_routing_error_spec.rb`
boots a real app each way, with `ignored_exceptions` cleared (the dummy app ignores `RoutingError`,
which would have proved nothing), and stays as the regression guard:

| Settings | Unknown URL | Recorded | A route that raises | Recorded |
|---|---|---|---|---|
| Reloading on, local requests, `show_exceptions` on | 404 | 0 | 500 | 1 |
| Eager loading, production's settings | 404 | 0 | 500 | 1 |

The route that raises is the control: it shows capture was live, so the zero means something. REQ-6
depended on REQ-4 changing a default, so it's dropped too, and UPGRADING needs no note.
