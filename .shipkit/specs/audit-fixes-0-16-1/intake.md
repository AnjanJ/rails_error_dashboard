# Intake: Audit fixes for 0.16.1

> Intake taken on 2026-10-19.

## Request
0.16.1: the four items left from 0.16.0's audit work, plus one found while researching them.
- Platform Comparison: the slowest platform can score at most 70, so it is never Healthy
  (`queries/platform_comparison.rb:172,182`).
- A platform with errors but none resolved gets the full resolution term (`:116-117,176,182`).
- Extra: the platform list is every platform ever seen (`:161`), so a platform with no errors in
  the window gets a score of 100 and a Healthy card.
- The patterns copy says "9am-5pm" (`config/locales/en.yml:521-523`); the code's business hours
  are hour buckets 9..17, i.e. 09:00-17:59 (`services/pattern_detector.rb:129-133`).
- Chart labels call Ruby `capitalize` ("Ios", "Api") at `errors/platform_comparison.html.erb:321,348,385`,
  and CSS `text-capitalize` shows "IOS" at `platform_comparison.html.erb:41,142,242` and
  `correlation.html.erb:112,329`.

## Serves goal
None. There is no `.shipkit/product.md`, so there is no goal list to choose from (not asked).

## Conflicts found
- **Decision.** "rate platforms by their share of all errors, and need two to rate" in
  `.shipkit/specs/audit-fixes-0-16-0/design.md` (reversal condition: users report ratings that
  disagree with their per-platform error rates; Fired-if manual). With score
  `70 × (1 − share) + 30 × resolution` and Healthy at 80, a platform can be Healthy only with
  a share of 28.6% or less, even with a perfect resolution term. So no platform in an evenly
  split app with two or three platforms can be Healthy, and the busier side of a 60/40
  two-platform split scores at most 58, which is Critical. **The user chose to amend it** (answer 1): that
  record is marked amended in its design.md and the new design supersedes its volume term. Its
  "need two to rate" half stands.
- **Open spec.** `audit-fixes-0-16-0` still reads `Status: open` although it shipped in 0.16.0;
  its REQ-4 covers Platform Comparison. This spec builds on it. Marking it shipped is the
  user's call.

## Answers
1. How far should 0.16.1 go on the score? **Compare each platform to an even split**: volume
   against its fair share (1/n of the errors), resolution against the fastest platform. Two equal
   platforms that resolve quickly are Healthy. Scores change for every install again.
2. A platform with errors but none resolved in the window? **Volume only, labelled**: score it on
   volume alone, scaled to 0-100, and the card says no errors were resolved in this window.

## Assumptions made
- Platforms with no errors in the window get no score and no health card. This matches the 0.16.0
  amendment ("two platforms means two with errors in the window").
- The business-hours copy changes to 09:00-17:59 in all eleven locales, matching the code and the
  docs (`docs/features/OCCURRENCE_PATTERNS.md:98,109`, `_features/occurrence-patterns.md:98,109`).
  The code's range stays as it is. Translations are machine-made, like the rest of the locales.
- Platform names are shown as stored ("iOS", "API", "Android", "Web", "Mobile"); no transform.
  The locale file already says brand names stay as written (`config/locales/en.yml:88-90`).
- Every doc page that explains the score is rewritten to the new formula, in both `docs/` and
  its Jekyll copy.

## Out of scope
- Rows stored with internal platform values (`boot_crash`, `crash_capture`:
  `services/crash_capture.rb:39-40,257`, `queries/boot_errors.rb:14`) showing up as platforms.
  Reported by research and not verified here. Worth its own look.
- The badge and icon mappings in the error-row partials (`_error_row.html.erb:90-98` and three
  others), which know only iOS, Android and Web.
- Labelling the time zone of pattern hours, and changing the business-hours range.
