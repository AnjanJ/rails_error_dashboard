# Design: The public API document and the release policies

## Approach
- **`docs/PUBLIC_API.md` is the index of what's frozen, not a second reference.**
  - It lists each public surface by name, grouped as in REQ-1. For each group it links the page
    that already documents it in detail:
    - config: `docs/guides/CONFIGURATION.md`, which documents 132 of the 143 options today; the 11
      coverage and LLM options are added there;
    - routes and health: `docs/API_REFERENCE.md`;
    - webhooks: `docs/WEBHOOKS.md`, from spec `webhook-v1`;
    - hooks: `docs/PLUGIN_SYSTEM.md`.
  - The names appear in one fenced list per group, so a spec can read them.
- **`docs/VERSIONING.md` holds the policies** (REQ-4). SECURITY.md's table changes to match
  (REQ-5).
- **The drift spec** (`spec/docs/public_api_spec.rb`, REQ-3) reads each group's list and compares it
  with the code:

| Surface | How the code is enumerated |
|---|---|
| Config options | `Configuration.public_instance_methods(false).grep(/=\z/)`, less `reset!` |
| ENV names | literal `ENV[...]`, `ENV.fetch(...)`, `ENV.key?(...)` reads in the `.rb`, `.rake` and `.erb` files under `app/`, `config/`, `db/` and `lib/`, skipping comment lines; one known-internal list, e.g. `SECRET_KEY_BASE_DUMMY` |
| Rake tasks | `Rake::Task.tasks` after `Rails.application.load_tasks`, RED's namespaces only, aliases included |
| Generators and their options | each `lib/generators/rails_error_dashboard/*/*_generator.rb`, and its own `class_options` |
| Plugin hooks | `RailsErrorDashboard::Plugin.public_instance_methods(false)` named `on_*` (12 today) |
| Module methods | `RailsErrorDashboard.singleton_methods(false)`, less `reset_configuration!` and `reset_detected_git_sha!` (test helpers) |

  The spec also compares these, which aren't in REQ-3 but are in REQ-1:
  - plugin hooks' arguments, with `Plugin.instance_method(hook).parameters`;
  - `GET /health`'s fields, read from `queries/health_status.rb` with Prism, so a branch that doesn't
    run in the test still counts;
  - OTel span names and attributes, read from `lib/`.

  And every live config option must have a table row in CONFIGURATION.md and in its Jekyll copy. A
  mention isn't enough: a sentence saying the option wasn't documented once passed that check. The
  two deprecated options have no row, because `deprecations-0-18` removed them from the guide and
  they do nothing. This page marks them instead, with the version that removes them.
- **README** links both pages (REQ-6).
- **Decision record 0007** records the policies (REQ-7).
- **Order:** the PR merges after `deprecations-0-18` and `webhook-v1`, or its lists describe the
  state they leave. The drift spec is what catches a mismatch.

## Decision: PUBLIC_API.md lists names and links details; types and defaults stay in CONFIGURATION.md   (→ REQ-1, REQ-3)

**Context.** REQ-1 as accepted says the page lists "every option, with its type and default".
`docs/guides/CONFIGURATION.md` already has a table with type, default and ENV for 132 of the 143
options. Two copies of 143 rows would drift, which is the problem this spec exists to stop.

**Alternatives.**
1. PUBLIC_API.md lists every option by name, linked to its CONFIGURATION.md row. The drift spec
   checks both pages contain every option.
2. PUBLIC_API.md repeats the full table (type and default).
3. Generate the table into PUBLIC_API.md from the code, with a spec that fails when it's stale.

**Case for 1.** One place for each fact. The frozen set is still complete and checkable by name,
and the details live where users already look them up. The 11 missing options get documented as a
side effect.

**Case against 1.** A reader has to follow a link to see a type, and "frozen" is then spread over
two pages. It also rewords REQ-1: "with its type and default" becomes "linked to its type and
default". That needs the maintainer's yes at the design gate. Option 3 keeps one source and a full
table, but defaults read from `Configuration.new` vary with ENV, and types can't be read from Ruby
at all.

**Decision.** We chose option 1, with REQ-1's config bullet reworded to: "every option, by name,
linked to its type and default in the configuration reference; the deprecated ones marked with the
version that removes them".
**Falsifiability.** We would move to option 3 if the CONFIGURATION.md check fails on main because an
option was documented in PUBLIC_API.md but not in CONFIGURATION.md, twice in 1.x.
**Fired-if.** manual

## Decision: Three URLs are public; every other dashboard URL is private   (→ REQ-1, REQ-2)

**Context.** The engine has about 45 routes (`config/routes.rb`). Things outside RED depend on
three of them:
- `GET /health`: uptime monitors;
- `POST /webhooks/:provider`: GitHub, GitLab and Linear deliver issue events there, configured in
  their UIs;
- `GET /errors/:id`: every notification links to it (`dashboard_url`).

Every other page is reached by clicking through the dashboard.

**Alternatives.**
1. Freeze those three, with the health JSON's fields; declare the rest private.
2. Freeze every route.
3. Freeze none, and document routes as informational.

**Case for 1.** It freezes exactly what other systems store or call, so pages can still be renamed
or merged in 1.x minors. That's the dashboard work 1.1 (the Full Context Error Report) needs.

**Case against 1.** A user who bookmarked or scripted another page, such as `/errors/analytics`,
loses it without a major version. And the health JSON's shape becomes permanent, including the
`skipped` status, so a better health format would have to wait for 2.0 or be added alongside.

**Decision.** We chose option 1.
**Falsifiability.** We would promote a URL to public if two or more issues report an integration
broken by a change to it.
**Fired-if.** manual
