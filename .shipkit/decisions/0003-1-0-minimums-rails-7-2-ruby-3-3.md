# 0003: RED 1.0 requires Rails 7.2+ and Ruby 3.3+

- **Date:** 2026-10-29. Status: accepted (the maintainer confirmed on 2026-10-29; drafted from
  `.shipkit/research/1-0-readiness.md`, dates re-checked on endoflife.date the same day).

## Context

RED 0.x supports Rails 7.0-8.1 and Ruby 3.2-4.0, and CI runs all 20 combinations. Upstream
support on 2026-10-29: Rails 7.0 (security ended 2025-04-01), 7.1 (2025-10-01) and 7.2
(2026-08-09) are past end of life, and Rails 8.0's security support ends 2026-11-07. On the
planned 1.0 date only Rails 8.1 is supported upstream. Ruby 3.2 ended 2026-03-31; Ruby 3.3 runs
to 2027-03-31.

RED's own dependencies have already moved: Pagy 43.x (latest 43.8.1) and groupdate 6.8.0
require Ruby >= 3.3, and groupdate 6.8.0 requires Active Support >= 7.2. So the Ruby 3.2 and
Rails 7.0/7.1 CI rows test older versions of RED's dependencies than new installs get. The
Rails 7.0 row is also the only one still on sqlite3 1.x, which has two open advisories and no
patched 1.x release (#331). The proposed policy says minimums rise only at a major, so whatever
1.0 requires is fixed until 2.0.

## Alternatives

1. Keep Rails 7.0+ and Ruby 3.2+ at 1.0.
2. Rails 7.2+ and Ruby 3.3+ (the oldest versions RED's dependencies support).
3. Rails 8.0+ (or 8.1+) and Ruby 3.3+, closer to what upstream still supports.

## Case for 2

It is the floor RED's dependencies have already chosen, so CI stops testing a dependency set no
new install gets. Rails 7.2 is the last 7.x series and the most common landing point for apps
that haven't reached 8.x yet, so it keeps most of the realistic user base. The CI matrix drops
from 20 rows to 9 (Ruby 3.3, 3.4 and 4.0 against Rails 7.2, 8.0 and 8.1). The Rails 7.0 work
(the boot warning before 7.0.10, the 1.x sqlite3 pin and its open alerts) goes away. Users on
7.0 or 7.1 keep 0.x, which still installs and works.

## Case against 2

It drops supported users: anyone on Rails 7.0 or 7.1 is stuck on 0.x, and 0.16.1 was spent
helping exactly those Rails 7.0 users. Honeybadger still supports Rails 5.2, so RED will look
narrower than an established competitor. Rails 7.2 is already past upstream security support,
and Ruby 3.3 ends in March 2027, so with "minimums rise only at a major" RED 1.x will support
both after their end of life, until 2.0. Whether the 0.x line gets security fixes after 1.0 has
to be settled with the policies.

## Decision

2. In 0.18, a deprecation warning at boot on Rails < 7.2 or Ruby < 3.3. At 1.0, the gemspec
requires Rails >= 7.2 and Ruby >= 3.3, CI drops to 9 rows, and the Rails 7.0 code paths and the
1.x sqlite3 pin go.

**I would reverse this if** three or more issues from users blocked by the Rails 7.2 floor are
opened within three months of 1.0. Then 1.x adds Rails 7.1 back in a minor, which is allowed
(widening is not a breaking change).
**Fired-if.** manual
