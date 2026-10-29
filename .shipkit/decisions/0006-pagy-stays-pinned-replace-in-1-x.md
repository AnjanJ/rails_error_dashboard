# 0006: Keep Pagy pinned at `~> 43.0` through 1.0; replace it with built-in pagination in 1.x

- **Date:** 2026-10-29. Status: accepted (the maintainer confirmed on 2026-10-29; drafted from
  `.shipkit/research/1-0-readiness.md`, which recommended widening; corrected after re-checking
  RubyGems the same day).

## Context

The gemspec requires `pagy ~> 43.0` (`rails_error_dashboard.gemspec:114`), and RED uses it in 82
places across 21 files. Two pressures:

- **Pagy's next major.** No Pagy 44 exists yet; the latest is 43.8.1 (2026-10-18). When it ships,
  apps can't take it while RED holds `~> 43.0`.
- **Apps on older Pagy can't install RED at all.** bullet_train 1.45.1 requires `pagy ~> 9`, and
  govuk-components 6.6.0 requires `pagy >= 6, < 10`.

The research doc recommended widening to `>= 43.0`, as Avo 4.3.9 does. That only addresses the
first pressure: bullet_train and govuk-components need a Pagy *below* 43, and Pagy 43 was an API
rewrite, so supporting 9.x as well would mean two code paths. Madmin removed Pagy entirely in
3.0 (Madmin 3.3.0 has no Pagy dependency).

## Alternatives

1. Keep `~> 43.0` through 1.0; when Pagy 44 ships, test it and widen in a minor if it works.
   Replace Pagy with built-in pagination in a 1.x minor.
2. Widen to `>= 43.0` now (the research doc's choice).
3. Replace Pagy with built-in pagination before 1.0.

## Case for 1

A bounded pin is what "safe to take blind" needs: with `>= 43.0`, a breaking Pagy 44 would reach
dashboards through a routine `bundle update`, which is the failure 1.0 exists to prevent. The
upper bound costs nothing until Pagy 44 exists. Replacing Pagy is the only fix for bullet_train
and govuk-components apps, but it touches 21 files during the weeks the freeze needs, and
removing a dependency doesn't break anyone, so it can land in 1.1 without waiting for 2.0.

## Case against 1

bullet_train and govuk-components apps stay unable to install RED through 1.0, which costs
adoption. When Pagy 44 ships, RED's users wait for a RED release before they can update Pagy.
And the 82 references grow with every new paginated page until the replacement lands.

## Decision

1. `pagy ~> 43.0` stays for 1.0. Pagy 44's release triggers a test-and-widen minor. Built-in
pagination replaces Pagy in a 1.x minor, and also drops the Pagy locale handling behind #148.

**I would reverse this if** Pagy 44 ships before 1.0 (then widen or replace before the freeze),
or if any issue reports that RED can't be installed next to an app's own Pagy (then the
replacement moves ahead of other 1.x work).
**Fired-if.** `curl -fsS https://rubygems.org/api/v1/versions/pagy/latest.json | grep -qv '"version":"43\.'` <!-- exits 0 once the latest Pagy is not 43.x; the issue half is manual -->
