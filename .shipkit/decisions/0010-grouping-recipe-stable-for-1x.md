# 0010: The default grouping recipe is stable for all of 1.x, and the v1 fallback goes only in 2.0

- **Date:** 2026-11-21. Status: accepted (the maintainer accepted the v2 recipe and the v1 fallback on
  2026-11-20, in `.shipkit/specs/hardening-1-0-rc2/design.md`, and the amendment that skips C-method
  frames the same day; this record makes the 1.x promise project-wide).

## Context

A group is identified by its fingerprint, so the recipe that computes it decides what a host's
dashboard shows as one error. Changing the recipe re-groups every live error: each one opens a new
group and sends a fresh "new error" alert on its next capture, and triage on the old groups stops
applying. Decision 0002 makes 1.0 a stability release, and a host pinned to `~> 1.0` takes every 1.x
minor without reading it.

The independent review of 1.0.0-rc.1 found the rc.1 recipe (v1) wrong in ways that hosts see:
- one file under two release directories gave two groups, so every Capistrano deploy reset triage;
- two methods in one file merged, and one method raising at two lines split;
- `NoMethodError` for two different names merged;
- a C method (`Hash#fetch`, `Integer()` on Ruby 4.0) was taken as the app frame.

rc.2 replaces it with v2 (`hardening-1-0-rc2`, REQ-1 to REQ-4). Groups that hosts already have carry v1
hashes, which can't be recomputed: the full message and the backtrace locations aren't stored.

## Alternatives

1. Freeze v2 for all of 1.x. Keep the v1 fallback (dual lookup, the row moves to v2) for all of 1.x,
   and remove both only in 2.0.
2. Allow the recipe to change in a 1.x minor, each time with a fallback to the previous recipe.
3. Version the recipe behind a setting (`fingerprint_version`), so a host opts into each new recipe.

## Case for 1

- A host can take any 1.x release blind, which is decision 0002's promise.
- One fallback, for one old recipe, removed at one known point.
- `custom_fingerprint` stays the escape hatch for a host whose errors v2 groups badly, as it is today.
- `docs/PUBLIC_API.md` names the recipe's parts, so the promise is checkable.

## Case against 1

- A grouping bug found in v2 during 1.x can't be fixed in the default recipe until 2.0. A host can work
  around it only with `custom_fingerprint`.
- Known v2 limits are frozen with it: two bugs in one method that raise the same class with the same
  normalised message merge; a method calling itself on one line is reported as its caller; renaming a
  method starts a new group.
- Every capture computes both v2 and v1 until 2.0. On the benchmark's 63-frame stack the v2 identity costs
  about 2.4 µs and v1 about 0.9 µs; the storm check stays under its 15 µs budget (4.7 to 6.2 µs, against
  3.2 to 4.4 µs on rc.1).
- 1.x carries the fallback code: `with_hash` and `move_to_current_hash` in `FindOrIncrementError`, their
  twins in `FlushStormCounts`, and `opaque_identity_v1` on queue and buffer payloads.

## Decision

1. The default recipe is v2 as `docs/PUBLIC_API.md` describes it, and stays so for all of 1.x. The v1
fallback stays for all of 1.x and is removed in 2.0, with v1 itself.

**I would reverse this if** two or more issues in 1.x report a grouping defect in the default recipe that
`custom_fingerprint` can't work around (then change the recipe in a minor, with a fallback as rc.2 did,
and say so in the upgrade notes).
**Fired-if.** manual
