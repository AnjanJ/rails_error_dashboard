# 0002: 1.0 is a stability release; the "v1.0 anchor" feature moves to 1.1

- **Date:** 2026-10-29. Status: accepted (the maintainer confirmed on 2026-10-29; drafted from
  `.shipkit/research/1-0-readiness.md`).

## Context

`.shipkit/product.md` commits to "v1.0.0 published on RubyGems with config and public API frozen"
by 2026-12-31. A host app pinned to `~> 1.0` takes every 1.x minor on `bundle update`, so every
1.x minor has to be safe to take blind. The readiness research lists seven blockers for that
promise (a written public API, a cleaned surface, a versioned webhook contract, published
policies, the overhead benchmark, no open host-safety bugs, a tested 0.x to 1.0 upgrade), and
none had started on 2026-10-29. `ROADMAP.md:698` separately names a new feature, the "Full
Context Error Report — unified view" (estimated 3-5 days), as "The v1.0 anchor". About nine
weeks remain, and the plan needs a release candidate in early December with two quiet weeks
after it.

## Alternatives

1. 1.0 is stability-only: the seven blockers, nothing new. The Full Context Error Report ships in
   1.1 as an additive minor.
2. 1.0 is the blockers plus the Full Context Error Report, still by 2026-12-31.
3. 1.0 waits for the Full Context Error Report and moves into Q1 2027.

## Case for 1

The date and the freeze are the goal of record; a new feature is not. The report is a new view
over data RED already stores, so it can land in 1.1 without breaking anything, while every
blocker has to land before the freeze or wait for 2.0. Building a flagship view in the same
weeks as the freeze adds public surface (routes, settings, maybe config) at exactly the moment
that surface becomes permanent. Stability-only also keeps the release candidate quiet: fewer
new code paths for early users to trip on.

## Case against 1

The 1.0 launch has no new headline feature, which weakens it for the adoption goal (200 stars,
100,000 downloads). The launch story becomes "stable, with a published overhead benchmark",
which is less exciting than a flagship view. The roadmap's own promise ("the v1.0 anchor") has
to be rewritten, and anyone who read it will see the change.

## Decision

1. The seven blockers in `.shipkit/research/1-0-readiness.md` define 1.0. The Full Context
Error Report moves to 1.1, and `ROADMAP.md:698` is updated to say so. The benchmark is the
launch's headline.

**I would reverse this if** designing the Full Context Error Report shows it needs a breaking
change to the config, the public API or the schema, because then it has to be designed before
the freeze or wait for 2.0.
**Fired-if.** manual
