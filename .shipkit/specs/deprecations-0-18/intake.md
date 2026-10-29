# Intake: deprecations for 0.18.0

> Intake taken on 2026-10-29.

## Request
Clean the public surface before the 1.0 freeze, without breaking an installed app:
- two options that do nothing (decision 0004);
- two rake namespaces;
- a generator that writes nothing;
- an ENV switch that works only for hand-written initializers;
- the Rails and Ruby versions that 1.0 drops (decision 0003).

Every one of these warns. None of them raises.

## Serves goal
"Ship 1.0: v1.0.0 published on RubyGems with config and public API frozen" (`.shipkit/product.md`).
The research's blocker 2 (`.shipkit/research/1-0-readiness.md`).

## Conflicts found
- **Paramount: nothing may raise into the host app.** Deleting the options would raise
  `NoMethodError` while the initializer loads (decision 0004), so they become setters that warn. A
  deprecation routed through Active Support's deprecator raises in any app that sets
  `config.active_support.deprecation = :raise`, which is common in test environments. The warning
  path must log, never raise.
- **Non-goal: no removing a shipped free feature.** The `solid_queue` generator has written nothing
  since 0.14.3 and only prints a check that `rails_error_dashboard:verify` also runs, so removing it
  removes no capability.
- **Decisions:** 0001 (the generator writes no Solid Queue files) is unaffected; 0003 and 0004
  are implemented here.
- **Open specs:** none touch these files.

## Answers (2026-10-29)
1. Config and ENV naming: **freeze as they are, no renames.** The six booleans without `enable_`
   keep their names. Every name gets documented in PUBLIC_API.md (separate spec).
2. Rake: **`rails_error_dashboard:` survives.** Every `error_dashboard:*` task stays as an alias
   that warns and runs the same code, until 2.0.
3. `USE_SEPARATE_ERROR_DB`: **deprecate.** Same behavior, one warning at boot, out of the docs'
   ENV lists, deleted in 2.0.
4. 0.x security support after 1.0: fixes on the last 0.x minor until 2027-06-30. The floor
   warnings point at this.

5. The solid_queue generator: **remove it in 0.18.0, and make `verify` cover the two cases only
   the generator checked** (Solid Queue not loaded; no `config/queue.yml`). Asked at the
   requirements gate, after the trade-off was laid out: it writes nothing; its check also runs at
   boot, in `verify`, on `/health` and on the dashboard; its setup hints are already in
   `docs/guides/SOLID_QUEUE_SETUP.md`. Once 1.0 ships it couldn't be removed until 2.0.

## Assumptions made
- **Removals happen only in 2.0,** with warnings from 0.18 through all of 1.x (decision 0004 and the
  policy spec).
- **The floor warnings are boot-time log lines,** like the existing Rails 7.0.10 warning
  (`configuration.rb:747`), and not gemspec changes. The gemspec changes at 1.0.

## Out of scope
- Renaming any config option or ENV name.
- Raising the gemspec minimums and dropping CI rows (1.0.0.rc1 work).
- The webhook renames (`webhook-v1`).
