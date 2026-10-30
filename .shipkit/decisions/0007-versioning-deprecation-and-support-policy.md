# 0007: Versioning, deprecation and support policy from 1.0

- **Date:** 2026-10-29. Status: accepted.
  - Drafted from `.shipkit/research/1-0-readiness.md` (blocker 4).
  - The maintainer chose the 0.x support window on 2026-10-29 and accepted the other rules at the
    0.18 design gate the same day.
  - To be published as `docs/VERSIONING.md` by spec `public-api-and-policies`.

## Context

A host app pinned to `~> 1.0` takes every 1.x minor on `bundle update`, so users need written rules
for what a minor may change. RED's maintainer is mostly one person, so every promise to support an
older line is a real cost.
- **Today:** SECURITY.md says only the latest version gets security fixes.
- **Who's affected:** decision 0003 moves the 1.0 floor to Rails 7.2 and Ruby 3.3. Apps on Rails
  7.0 or 7.1, or Ruby 3.2, can only stay on 0.x.
- **What comparable gems do:** GoodJob ships a bridge release before each major that warns about
  everything the major removes. Rails gives security fixes to the previous series.

## Alternatives

1. SemVer from 1.0, with these rules:
   - **deprecations:** warn for at least two minors, and are removed only in a major;
   - **the bridge:** the last minor before a major warns about everything it removes;
   - **minimums:** Rails and Ruby minimums rise only at a major;
   - **migrations:** in a minor, additive and replay-safe;
   - **security fixes:** for the current major and the previous major's last minor;
   - **0.x after 1.0:** security fixes only, on the last 0.x minor, until 2027-06-30.
2. The same rules, but security fixes for 0.x until 2.0 ships.
3. The same rules, with no 0.x support after 1.0.

## Case for 1

Each rule is one a user can act on.
- **Taking minors:** a minor never removes or renames, so taking one is safe.
- **Preparing for a major:** the bridge release lists everything that's going.
- **Choosing a version:** the minimums can't move under a pinned app.
- **Deploying:** a migration in a minor can't break a deploy or a shared database.

The 0.x window gives Rails 7.0/7.1 apps eight months to plan an upgrade, with a fixed end date. A
single maintainer can backport to one old branch for that long, but not indefinitely.

## Case against 1

- **Old Rails apps:** they lose security fixes on 2027-06-30. That's a hard stop for apps that
  can't upgrade, and option 2 is kinder to them.
- **The maintainer:** "two minors" and "the previous major's last minor" mean keeping an old
  branch building and tested.
- **Old Ruby and Rails:** decision 0003 noted that with minimums fixed until 2.0, RED 1.x will
  support Rails 7.2 and Ruby 3.3 after their own end of life.
- **Speed of change:** "removed only in a major" means mistakes in the 1.0 surface stay until 2.0.
  Decision 0004's warning no-ops are the first example.

## Decision

1. `docs/VERSIONING.md` publishes these rules, and SECURITY.md's table matches them.

**I would reverse this if** keeping the 0.x branch releasable costs more than one maintainer day a
month, averaged over the first three months after 1.0 (then 0.x support ends early, announced 60
days ahead), or if three or more users ask for 0.x fixes past 2027-06-30 (then extend it).
**Fired-if.** manual
