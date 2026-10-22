# Intake: live updates reach the browser

> Intake taken on 2026-10-22.

## Request
Live updates never reach the browser: the engine layout loads no
Turbo client, so the `<turbo-cable-stream-source>` tags on the error index never connect, while the
server still renders and broadcasts partials on every capture. Decide between loading the client and
removing the feature, then fix it.

## Serves goal
"Ship 1.0 — metric: v1.0.0 published on RubyGems with config and public API frozen". A new config
option has to land before the freeze.

## Conflicts found
- **Non-goal "No removing a shipped free feature"** (`.shipkit/product.md:24`) conflicts with the
  "remove the feature" option. The user chose to fix it instead, so the conflict does not arise.
- **Paramount non-goal "no feature on the request path that cannot be switched off by config"**
  (`.shipkit/product.md:20`). Broadcasting runs in the capturing thread (`ErrorLog`
  `after_create_commit` / `after_update_commit` → `Services::ErrorBroadcaster`). No RED setting turns
  it off: `ErrorBroadcaster.available?` only checks that Turbo and ActionCable are loaded. The user
  chose to add a switch, off by default.
- Open specs: none cover it (`async-job-reconstruct` is the only other folder, and it is unrelated).
- Decisions: `.shipkit/decisions/0001` (never write other gems' files) is not touched; reading a CDN
  file is not writing.

## Answers
1. Fix or remove? **Fix: load the turbo-rails client.** (user, 2026-10-22)
2. Add a config switch for the request-path work? **Yes: `enable_live_updates`, default `false`.**
   (user, 2026-10-22) The feature has never worked since v0.1.4, so turning it off by default takes no
   visible behaviour from anyone, and every host stops paying for broadcasts nobody receives.

## Assumptions made
- **Client source:** the client loads from jsDelivr, pinned by version and SRI hash. That is the
  layout's existing convention (CLAUDE.md rule 5: external JS via CDN only).
- **Which file:** the unminified `app/assets/javascripts/turbo.js` from `@hotwired/turbo-rails`,
  because the package ships no `turbo.min.js`. A jsDelivr-generated minified file can change bytes
  and break an SRI hash. Unminified, it is 189 KB raw and 41 KB brotli.
- **Bundle contents:** the bundle includes the ActionCable consumer and defines
  `turbo-cable-stream-source`. Checked on 8.0.23, which is byte-identical to the `turbo.js` in the
  turbo-rails 2.0.23 gem.
- **Turbo Drive stays off.** `<body data-turbo="false">` is kept, because streams work without
  Drive.
- **Proven by the lab spike, 2026-10-22, a fresh Rails 8.1.4 app (gem 0.16.1, async cable).** With the
  client loaded:
  - the new row arrived without a reload;
  - clicking a local time stopped toggling, because `turbo:load` re-runs `convertToLocalTime` and
    stacks a second click listener. The same pattern initialises tooltips;
  - streamed rows contain no local times and no tooltips.

## Out of scope
- Turning live updates on in the demo app. That is a separate repo, and needs `action_cable/engine`
  plus solid_cable there.
- Reducing what an enabled broadcast costs on the capture path. The `DashboardStats` work belongs to
  the overhead-benchmark goal.
- A polling fallback.
