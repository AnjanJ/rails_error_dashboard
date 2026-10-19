# Design: Audit fixes for 0.16.1

## Approach
The score keeps its shape: 70% volume, 30% resolution, 0-100, Healthy at 80 and Warning at 60,
with the velocity limits unchanged (`queries/platform_comparison.rb:276-283`). Each term changes
what it compares against. Volume is compared with an even split instead of the raw share.
Resolution is compared with the fastest platform instead of the slowest. A platform with nothing
resolved is scored on volume alone. Only active platforms are scored or carded, filtered once in
the query so the Overview and Platform Comparison agree. The copy and platform-name fixes are
view and locale changes.

This amends "rate platforms by their share of all errors, and need two to rate" in
`.shipkit/specs/audit-fixes-0-16-0/design.md`: its volume term is superseded here, and its
"need two to rate" half stands. That record gets an amendment line pointing here.

## Decision: volume credit falls linearly from an even split to all errors   (→ REQ-1, REQ-2, REQ-3)

**Context.** Today `volume = 1 − share`. With Healthy at 80, a platform needs a share of 28.6% or
less to be Healthy even with full resolution credit. So no evenly split two- or three-platform app
can be Healthy. The user chose to compare against an even split (intake answer 1).

**Alternatives.**
1. Linear: full credit at or below `1/n`, then
   `1 − (share − 1/n) / (1 − 1/n)`, reaching 0 when one platform has every error.
2. Ratio: `min(1, (1/n) / share)`.
3. Keep `1 − share`. The user rejected this.

**Case for 1.** It's bounded on both ends and easy to explain: an even split scores 1 and every
error on one platform scores 0. Worked numbers, with full resolution credit:
- 50/50 → 1.0 → 100.
- 60/40 → busier 0.8 → 86, Healthy.
- 90/10 → busier 0.2 → 44, Critical.
- 80/10/10 → busier 0.3 → 51, Critical.

**Case against 1.** A 60/40 app rates both platforms Healthy, and someone may want the busier one
flagged. Option 2 is gentler still: 90/10 gives 0.56 → 69, Warning, and the busier side of a
two-platform app never drops below 0.5. That is too lenient for a platform with 90% of the errors.

**Decision.** Option 1.
**Falsifiability.** We would revisit it if a user reports a platform rated Healthy while it has
clearly more errors than its share would suggest, or one rated Critical at a split they consider
normal.
**Fired-if.** manual

## Decision: resolution credit is the fastest average over this platform's, each floored at one hour   (→ REQ-4, REQ-5)

**Context.** Today `resolution = 1 − avg / max`, so the slowest platform always scores 0 and is
capped at 70. Averages are in hours, rounded to 0.01 h per group
(`platform_comparison.rb:102-121`), so an average can be 0.0.

**Alternatives.**
1. `fastest / avg`, with both averages floored at 1 hour.
2. A fixed target, such as full credit within 24 hours, falling to 0 at 7 days.
3. Compare with the median platform instead of the fastest.

**Case for 1.** The fastest platform and any platform as fast get full credit. A platform twice as
slow gets half. 12 h against 10 h gives 0.83 → 95 at an even share (REQ-5). There's no fixed
target, which follows 0.16.0's no-arbitrary-thresholds precedent. The one-hour floor stops a
platform that resolves instantly (an average of 0.0) from zeroing everyone else, and sub-hour
differences don't say anything about platform health.

**Case against 1.** One very fast platform drags the rest down. Against a 1 h platform, a 10 h
platform gets 0.1 → 73 at an even share, which is Warning. The floor is still a constant, though
it is a guard rather than a target, and the docs have to state it.

**Decision.** Option 1.
**Falsifiability.** We would revisit it if a user reports a platform rated Warning or worse only
because another platform resolves far faster.
**Fired-if.** manual

## Decision: nothing resolved → scored on volume alone, and labelled   (→ REQ-6, REQ-7)

**Context.** Today a platform with nothing resolved gets the full 30 points (`:116-117,176,182`).
The user chose volume alone, labelled (intake answer 2), over counting it as the slowest or
averaging the others.

**Alternatives.** 1. Volume alone, scaled to 0-100. 2. No resolution credit at all. 3. The
average of the others' resolution credit.

**Case for 1.** It doesn't invent a resolution number for a platform with none, and doesn't punish
one whose errors are all recent.

**Case against 1.** Two platforms on the same page can be scored on different bases. The label
(REQ-7) is what makes that visible.

**Decision.** Option 1. `platform_health_summary` adds `resolution_measured: false` for such a
platform. The Overview and Platform Comparison cards show a "No errors from this period resolved
yet" line under the score, through a new locale key in all eleven locales.
`platform_stability_scores` keeps returning `{ platform => score }`, so its chart callers don't
change.
**Falsifiability.** We would revisit it if users read volume-only scores as better than
measured ones, for example asking why a platform that resolves nothing outranks one that does.
**Fired-if.** manual

## Active platforms only (→ REQ-8)
No real alternative. `platform_stability_scores` and `platform_health_summary` iterate the
platforms with errors in the window (`error_rate_by_platform`'s keys) instead of every platform
ever seen (`:161`, `:60-61`). Both pages read the summary, so both stop showing the card.

## Copy and names (→ REQ-10, REQ-11)
- `red.errors.patterns.types.business_hours.description` states 9:00–17:59 in all eleven locales,
  written the same way in each (a locale spec checks every file for "17:59").
- The three `.capitalize` calls (`platform_comparison.html.erb:321,348,385`) and the five
  `text-capitalize` classes (`platform_comparison.html.erb:41,142,242`, `correlation.html.erb:112,329`)
  go. Stored names are already in brand case, and the locale file says they stay as written
  (`config/locales/en.yml:88-90`). No display helper: a mapping would have to know every platform
  name a host reports through `context[:platform]`.

## Docs (→ REQ-9)
`docs/features/PLATFORM_COMPARISON.md` and its Jekyll copy `_features/platform-comparison.md` get
the new formula, the one-hour floor, the volume-only rule and a worked example. The score
definitions in `docs/GLOSSARY.md` and `_reference/glossary.md`, and the score mentions in
`docs/FEATURES.md` and `_getting_started/features.md`, are checked and corrected. The stale formula
comment in `spec/requests/analytics_reports_i18n_spec.rb:198-202` is corrected too.

## Data / interface changes
- `platform_health_summary` gains `resolution_measured` (Boolean) per platform, and drops inactive
  platforms.
- `platform_stability_scores` drops inactive platforms. Its shape is unchanged.
- One new locale key, in eleven locales. No migration.
