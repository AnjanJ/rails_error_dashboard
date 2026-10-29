# Intake: the public API document and the release policies

> Intake taken on 2026-10-29.

## Request
The research's blockers 1 and 4:
- write down what 1.0 freezes (`docs/PUBLIC_API.md`), with everything else marked private;
- publish the versioning, deprecation, supported-versions and security policies.

## Serves goal
"Ship 1.0: v1.0.0 published on RubyGems with config and public API frozen" (`.shipkit/product.md`).
"Frozen" means nothing until the frozen set is written down.

## The surface, re-counted at 6b1dfab
- 143 `attr_accessor`s in `configuration.rb`; 30 ENV names read there.
- Module methods in `lib/rails_error_dashboard.rb:194-303`; `ManualErrorReporter.report`.
- 12 plugin hooks in `plugin.rb`: `on_register` plus 11 event hooks (`:41-107`; a thirteenth grep
  match at `:14` is a doc comment). All 12 names appear in `docs/PLUGIN_SYSTEM.md`.
- 28 `class_option`s on the install generator (the handoff said 27).
- 13 rake tasks; 3 generators.
- Routes:
  - `GET /health` (JSON, with a `skipped` status);
  - `POST /webhooks/:provider` (inbound issue-tracker webhooks);
  - the error page `/errors/:id`, which notifications link to;
  - about 40 other dashboard pages.
- The outbound webhook contract (spec `webhook-v1`); OTel span names and attributes
  (`integrations/tracer.rb`).
- 52 migrations and 15 tables.

## Conflicts found
- **Depends on `deprecations-0-18` and `webhook-v1`.** PUBLIC_API.md describes the surface after
  them: one rake namespace, the deprecated names marked, the v1 webhook names. It merges after
  them, or its text describes their merged state.
- **SECURITY.md says only the latest version gets security fixes.** That contradicts the new
  policy and changes with it.

## Answers (2026-10-29)
1. **Names are frozen as they are** (no renames). `rails_error_dashboard:` is the rake namespace.
2. **0.x after 1.0:** security fixes only, on the last 0.x minor, until 2027-06-30.
3. **Ships as its own docs PR,** not tied to a gem release.

## Assumptions made
- **Policies** (the research's, adopted as written):
  - SemVer from 1.0;
  - a deprecation warns for at least two minors and is removed only in a major;
  - the last minor before 2.0 is a bridge that warns about everything 2.0 removes (GoodJob's
    model);
  - minimum Rails and Ruby rise only at a major;
  - migrations in a minor are additive and replay-safe;
  - security fixes for the current major and for the previous major's last minor.
- **What's private:**
  - database tables and columns, models, job classes and their arguments;
  - internal classes and modules that aren't named in PUBLIC_API.md;
  - i18n keys;
  - the dashboard's HTML, CSS and JS;
  - every dashboard URL except the three listed as public.
- **These become a decision record** (`.shipkit/decisions/0007`), so later releases can be checked
  against them.

## Out of scope
- Removing the "Beta" label and the full docs pass (1.0.0.rc1).
- The 0.x to 1.0 upgrade guide (1.0.0.rc1).
