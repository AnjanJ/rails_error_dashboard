# Design: Smaller fixes for 0.18.0

## Approach
- **Crash sources leave the platform lists.**
  - **The constant:** `Services::CrashCapture::PLATFORMS` (`[BOOT_PLATFORM, RUNTIME_PLATFORM]`,
    from `crash_capture.rb:39-40`).
  - **The scope:** `ErrorLog.platform_listed`, which excludes those two values and keeps rows whose
    platform is NULL.
  - **Every query that lists or groups by platform uses the scope:**
    - `queries/filter_options.rb:19` (the filter dropdown);
    - `queries/error_correlation.rb:49`, `:268`;
    - `queries/mttr_stats.rb:54-57`;
    - `queries/platform_comparison.rb:61`, `:93`, `:110`, `:243`;
    - `queries/dashboard_stats.rb:40`;
    - `queries/analytics_stats.rb:123`;
    - `queries/baseline_stats.rb:98`, `:120`.
  - **Unchanged:** `queries/boot_errors.rb`, the error list and error pages (REQ-2).
- **Badges.** One helper, `platform_badge(platform)`, matches `ios`, `android` and `web` in any
  case. It replaces the four copies of the same `if/elsif` in `errors/_error_row.html.erb:89-99`,
  `_timeline.html.erb:38-42`, `_similar_errors.html.erb:58-62` and `_sidebar_metadata.html.erb:58-62`.
  Other values keep today's grey badge with their own text.
- **Development 404s: reproduce first (task T4).** Reading the code at `6b1dfab` suggests they
  aren't recorded in either environment:
  - in production, `ShowExceptions` renders a rescue response and doesn't report it;
  - in development, `DebugExceptions` renders it and doesn't report it either;
  - `ErrorCatcher` sees no exception in both cases.

  T4 runs a development app with reloading on, requests an unknown URL, and records the result
  here. If nothing is recorded, REQ-4 and REQ-6 are dropped, and their tests are the evidence.
- **Pattern hours.** `analytics_stats.rb:289-296` plucks `occurred_at`, which Rails returns in
  `Time.zone`, so the hours are already the app's zone. The fix:
  - makes that explicit with `in_time_zone`, as `queries/event_volume.rb:370` does with its
    `reporting_zone`;
  - labels the heatmap and the peak list with the zone (`_pattern_insights.html.erb:98-126`),
    through a new i18n key in every locale.

## Decision: Exclude crash sources with one scope in each platform query, not by moving them out of `platform`   (→ REQ-1, REQ-2)

**Context.** Crash capture stores `boot_crash` or `crash_capture` in `platform`
(`crash_capture.rb:257-259`). Nothing excludes them, so they appear in the filter dropdown, the
analytics charts, MTTR and the platform health cards: at least 12 query sites. `queries/boot_errors.rb`
finds boot crashes through that same column (`:14`, `:58`). `platform` is also NULL on some rows,
and `where.not(platform: [...])` would silently drop those, because SQL's `NOT IN` is never true
for NULL.

**Alternatives.**
1. A scope that excludes the two values and keeps NULLs, used by every platform-listing query.
2. Stop storing crash markers in `platform`: give crash rows their real platform (or NULL) and mark
   them another way, such as `capture_source` or a new column. That needs a migration and a
   backfill, and `boot_errors.rb` changes too.
3. Filter in the views only.

**Case for 1.** No migration and no backfill. The scope is defined once, and NULL rows keep
counting where they count today. `boot_errors.rb` and every error page are untouched, so REQ-2
holds by construction.

**Case against 1.** `platform` keeps meaning two things, so a new platform query added later must
remember the scope, and nothing forces it. Option 2 fixes the data model, but a migration and a
backfill in the release before the freeze is the riskiest kind of change, for a cosmetic gain.
Option 3 leaves wrong numbers in the queries the views total up.

**Decision.** We chose option 1.
**Falsifiability.** We would move to option 2 if a platform list shows a crash source again after
0.18.0, or if a third non-platform value starts being stored in `platform`.
**Fired-if.** `test "$(grep -rEn 'PLATFORM = "' lib/rails_error_dashboard/services | wc -l)" -gt 2` <!-- the two crash markers today, crash_capture.rb:39-40 -->

## Decision: Pattern hours stay in the app's `Time.zone`, labelled   (→ REQ-5)

**Context.** The heatmap groups errors into 24 hourly buckets on the server
(`services/pattern_detector.rb:43-46`) and renders bare integers. Elsewhere, single timestamps go
through the `local_time` helper and are shown in the viewer's browser zone
(`application_helper.rb:295-320`).

**Alternatives.**
1. Keep the server-side buckets in `Time.zone`. Make the conversion explicit, and label the zone.
2. Bucket in the viewer's browser zone: send raw timestamps and bin them in JS.

**Case for 1.** It's what REQ-5 says. It's a small change, and it matches how the analytics pages
already report volume by hour (`event_volume.rb:370`). An operator reading "peak at 14:00
(Europe/Berlin)" knows exactly what it means.

**Case against 1.** A viewer in another zone has to convert in their head, and the heatmap then
disagrees with the browser-local timestamps on the same page. Option 2 matches the browser, but it
sends every timestamp to the page, which is unbounded for a busy error.

**Decision.** We chose option 1.
**Falsifiability.** We would switch to option 2 if an issue reports the heatmap's zone confusing
users of a multi-zone team.
**Fired-if.** manual
