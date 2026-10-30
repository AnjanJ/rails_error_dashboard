# Design: Host and dependency hygiene for 0.17.0

## Approach

1. **API-only hosts.** The `rails_error_dashboard.middleware` initializer stops adding middleware to
   the host's stack. Instead it puts one RED middleware, `Middleware::DashboardSession`, on the
   ENGINE's own stack. Rails builds that stack lazily (`Rails::Engine#app`), and only requests routed
   into the dashboard pass through it.
   - The middleware wraps the standard `ActionDispatch::Cookies` → `Session::CookieStore` → `Flash`
     chain, with the cookie named `_rails_error_dashboard_session`.
   - It steps aside when the host already put an ENABLED session in the request
     (`env["rack.session"]`). Rails stores a disabled placeholder there on any earlier session
     read, so presence alone is not enough.
   - It requires `action_dispatch/middleware/flash` itself. `ActionDispatch::Flash` is a lazy
     autoload, and `Request#flash` only exists once that file is loaded. An API app loaded it only
     through the old host-stack `use`.
2. **CDN files.** Every jsDelivr tag in the layout gets `integrity` and `crossorigin="anonymous"`.
   - Three sources move first, each to a file its npm package publishes: chart.js
     `dist/chart.umd.js`, catppuccin `css/catppuccin-mocha.css`, and highlight.js from the `gh/`
     git tag to `@highlightjs/cdn-assets@11.9.0/highlight.min.js` (byte-identical, checked
     2026-10-23).
   - A copy of each file lives in `spec/support/vendor/`, and a spec hashes each copy against the
     rendered layout.
3. **concurrent-ruby.** `"~> 1.3", ">= 1.3.7"`, with the comment rewritten to say what RED really
   uses.
4. **A chaos app for API-only hosts**, `full_api`, in `all`. Its new phase checks both sides over
   HTTP: a host endpoint that writes the session still fails, and the dashboard's session works
   end to end.

## Decision: The dashboard's session lives on the engine's own stack, behind a guard   (→ REQ-1, REQ-2, REQ-3)

**Context.** `ActionController::Base`, which the dashboard's controllers inherit, needs cookies and
a session: for CSRF tokens, the flash, and the language picker. An API-only host's stack has
neither, so 0.1.x added them with `app.middleware.use`. That changes every host endpoint
(verified: a host action writing `session[]` got a `Set-Cookie` instead of
`DisabledSessionError`). The paramount rule forbids process-wide side effects. Some API hosts add
their own session middleware, and a host `authenticate_with` lambda may read that session (Warden).

**Alternatives.**
1. One RED middleware on the engine's stack. It runs Cookies → CookieStore → Flash for the request,
   unless `env["rack.session"]` already holds an enabled session; then it just passes the request
   on.
2. The three Rails middlewares directly on the engine's stack (`config.middleware.use`).
3. Leave the stack alone, and tell API hosts to add session middleware themselves.

**Case for 1.**
- The host's stack is untouched, and a dashboard request gets exactly the session it needs.
- A host that already runs a session keeps using it in the dashboard. With option 2, CookieStore
  would merge the host's session into a second, RED-keyed one: the host's session data would be
  copied into RED's cookie, and whatever the dashboard writes (a Warden sign-in, the CSRF token)
  would miss the host's own session.
- One small class with a spec at the Rack level.

**Case against 1.**
- It is RED code standing in front of Rails' own middleware.
- It decides from `rack.session`. Rails stores a disabled placeholder there on any session read,
  so the guard must check `enabled?`, not presence; a spec pins that case. A host with a session
  but no Cookies middleware would be odd and is not handled.
- A host that has Cookies but no session gets a second cookie jar commit; it writes the same
  cookie twice in one response, which browsers accept.
- Option 3 would break the dashboard out of the box for every API host.

**Decision.** We chose option 1.
**Falsifiability.** We would revisit if an API host reports a dashboard request with no session (a
CSRF failure or a lost flash) while its own session middleware is installed.
**Fired-if.** manual

## Decision: The cookie is `_rails_error_dashboard_session`, on path `/`   (→ REQ-4)

**Context.** `CookieStore` defaults its key to `_session_id`. The mount path is a route, unknown when
the middleware is built.

**Alternatives.**
1. A RED-specific name, path `/`.
2. The default `_session_id`.
3. A RED-specific name scoped to the mount path, set per request.

**Case for 1.** The name says whose cookie it is, and can't collide with a cookie the host or its
front end sets under the default name. Path `/` is CookieStore's default, so nothing per-request
is needed.

**Case against 1.** Browsers send the cookie with every request to the host, API endpoints included.
They ignore it (there is no session middleware to read it), but it is bytes on every request.
Option 3 avoids that at the cost of request-time option juggling.

**Decision.** We chose option 1.
**Falsifiability.** We would scope the path if a host reports the cookie's size or presence on API
requests as a problem.
**Fired-if.** manual

## Decision: Integrity attributes inline in the layout, pinned by vendored copies   (→ REQ-5, REQ-7)

**Context.** The layout is self-contained by rule (`CLAUDE.md`, rules 4 to 6), and its nine CDN tags
are unconditional. #308 pinned its one helper-rendered tag with constants and a vendored copy.

**Alternatives.**
1. `integrity="sha384-…" crossorigin="anonymous"` written on each tag in the layout. Every file is
   copied to `spec/support/vendor/`. A request spec renders a dashboard page and checks two things:
   that every off-site `<script src>` and stylesheet `<link>` except Google Fonts carries both
   attributes, and that each hash equals the SHA-384 of its vendored copy.
2. A URL-and-hash table in a helper, with helper calls in the layout.
3. Vendoring the files into the gem and serving them from a RED controller.

**Case for 1.**
- The tags stay readable where they are.
- The spec fails on a missing attribute, on a hash that doesn't match its pinned bytes, and on a new
  CDN tag added without one. A version bump therefore can't half-happen.
- System specs already serve vendored copies to the browser, so integrity is checked in a real
  browser for the scripts they run.

**Case against 1.**
- Nine more vendored files, about 0.5 MB, in the repository. They stay out of the gem: the gemspec
  has no `spec/` in `files`.
- If jsDelivr ever served different bytes, the browser would block that file and the dashboard
  would lose that library: charts, icons, highlighting, or Bootstrap's modals. That is the same
  degradation as a CDN outage, and it is the point of the hash.
- Option 3 removes the CDN, but it touches serving and caching, which is outside a hardening
  release.

**Decision.** We chose option 1.
**Falsifiability.** We would move to a helper table if the layout loads more than 15 files from
jsDelivr.
**Fired-if.** `test "$(grep -c 'cdn.jsdelivr.net' app/views/layouts/rails_error_dashboard.html.erb)" -gt 15`

## Decision: Load only files the npm packages publish   (→ REQ-6)

**Context.** jsDelivr generates a file when asked for one a package doesn't ship (verified with its
data API, 2026-10-23):
- chart.js@4.4.0 ships `dist/chart.umd.js` (already minified, 204,948 bytes), not `.min.js`;
- @catppuccin/highlightjs@1.0.0 ships `css/catppuccin-mocha.css`, not `.min.css`.

Generated bytes can change without a version bump, which would make a hash on them fail. The `gh/`
path serves a git tag, which the upstream can move.

**Alternatives.**
1. Switch to the files the packages ship. That means `chart.umd.js`, `catppuccin-mocha.css`, and
   highlight.js from `npm/@highlightjs/cdn-assets@11.9.0/highlight.min.js`, which is byte-identical
   to the `gh/` file.
2. Hash the generated files as they are.

**Case for 1.** Package files are immutable at a version on npm, so a hash on them holds. The
switches change nothing on the page: chart.js and catppuccin serve the same code (only jsDelivr's
banner differs), and highlight.js is the same bytes.

**Case against 1.** Two files lose jsDelivr's minification banner, and one is 300 bytes larger. The
system spec that serves Chart.js from `spec/support/vendor/` must follow the new file name.

**Decision.** We chose option 1.
**Falsifiability.** We would revisit if a pinned package file changes its hash, which would mean
jsDelivr's npm files are not immutable after all.
**Fired-if.** manual

## Decision: An API-only chaos app, in every `all` run   (→ REQ-1, REQ-2)

**Context.** The dummy app is a full-stack app. No spec can show what an API host's stack does with
RED installed, and no chaos app is API-only.

**Alternatives.**
1. `full_api`, built with `rails new --api` (plus the harness's usual skips, Action Cable among
   them), installed like `full_http`, and run in `all` and `release_audit`. Its server runs Phase D
   (the dashboard pages) and a new Phase P over HTTP:
   - a host endpoint that does not touch the session answers with no `Set-Cookie`;
   - one that writes the session answers 500, captured as `DisabledSessionError`;
   - the dashboard sets `_rails_error_dashboard_session`, takes a CSRF-protected `update_status`,
     shows the flash notice after it, and switches language through the picker.

   The host endpoints live in their own `ApiProbeController < ActionController::API`.
   `inject_test_fixtures` can't be reused: its controller calls `skip_forgery_protection`, which
   API controllers don't have. Phase D runs unchanged, and its 422-without-token checks pass only
   with a working session.
2. The same app in `release_audit` only.
3. Unit specs on the initializer only.

**Case for 1.**
- It runs the real stack in production mode, eager loading on, the way a host does.
- It is the only place REQ-1 and REQ-2 can fail for real.
- Running it in `all` catches a regression on the commit that causes it, through lefthook, and in
  every release audit. PR CI runs only `full_upgrade` and `bin/full-integration-test`, not `all`.

**Case against 1.**
- About a minute more on every chaos run, which also runs from lefthook.
- Phase P parses a CSRF token out of HTML, which a layout change can break.
- Option 3 is fast, but it can't see the stack a real `rails new --api` app builds.

**Decision.** We chose option 1 (the user accepted the assumption at intake).
**Falsifiability.** We would move it to `release_audit` if `bin/pre-release-test all` takes longer
than 6 minutes on the maintainer's machine.
**Fired-if.** manual

## Decision: A concurrent-ruby floor, not a ceiling   (→ REQ-8)

**Context.** `CountBuffer` uses `Concurrent::ReadWriteLock` in its block forms only, which can't
release from the wrong thread, so CVE-2026-54906 isn't reachable through RED. The other two CVEs
fixed in 1.3.7 are in classes RED doesn't use that way. The floor is about the host's other gems,
and about bundle-audit noise. Decided by the user on 2026-10-22.

**Alternatives.**
1. `"~> 1.3", ">= 1.3.7"`.
2. Keep `"~> 1.3"`, with a corrected comment.

**Case for 1.** New bundles can't resolve to a vulnerable version. Rails asks only for `>= 1.3.1`, so
the floor conflicts with nothing current.

**Case against 1.** A host locked below 1.3.7 must move concurrent-ruby to upgrade RED.

**Decision.** We chose option 1.
**Falsifiability.** We would relax it if a supported Rails version (7.0 to 8.1) turns out to conflict
with concurrent-ruby 1.3.7 or later in a fresh bundle.
**Fired-if.** manual

## Data / interface changes

- **New `RailsErrorDashboard::Middleware::DashboardSession`** in
  `lib/rails_error_dashboard/middleware/dashboard_session.rb`, required from
  `lib/rails_error_dashboard.rb` (→ REQ-1 to REQ-4).
  - `COOKIE_KEY = "_rails_error_dashboard_session"`. The file requires
    `action_dispatch/middleware/flash`.
  - `call(env)` passes the request straight on when `env["rack.session"]` holds a session that is
    enabled (`!s.respond_to?(:enabled?) || s.enabled?`). Otherwise it runs
    `ActionDispatch::Cookies` → `ActionDispatch::Session::CookieStore` (`key: COOKIE_KEY`) →
    `ActionDispatch::Flash`, built once.
  - Its spec builds the env from `Rails.application.env_config`, because the cookie jar needs
    `key_generator`. The initializer spec runs the initializer against a stand-in and never
    changes the real, memoised engine stack.
- **`engine.rb`, the `rails_error_dashboard.middleware` initializer:** under `app.config.api_only`,
  `config.middleware.use RailsErrorDashboard::Middleware::DashboardSession` on the engine, and
  nothing on `app.middleware`. The comment now says what really happens (→ REQ-1).
- **Layout:** nine tags gain `integrity` and `crossorigin="anonymous"`. Three URLs change as
  described above (→ REQ-5, REQ-6).
- **Specs:**
  - `spec/support/vendor/` gains the five files no spec executed, plus `chart.umd.js`, which
    replaces `chart.umd.min.js`. The README lists all nine.
  - In `spec/support/capybara.rb`, Chart.js is matched by its new file name, and
    `VENDORED_SCRIPT_BODIES` reads with `File.binread` (→ REQ-7).
  - `bin/pre-release-test release_audit` downloads each layout URL and compares its SHA-384 with
    the layout's attribute. This is the one check against the live CDN; it needs the network.
- **Gemspec:** `"~> 1.3", ">= 1.3.7"`, plus a rewritten comment (→ REQ-8, REQ-9).
- **Chaos:**
  - `test_full_api` in `bin/pre-release-test`, in `all` and `release_audit`;
  - `test/pre_release/templates/full_api_initializer.rb`;
  - `test/pre_release/chaos/phase_p_api_host.rb`;
  - a host `ApiProbeController` and its routes, injected into the app.
- **Docs (→ REQ-9):**
  - `CLAUDE.md`, through `/shipkit:update-rules`: the CDN list, rule 5 (every CDN tag pinned with
    integrity, crossorigin and a vendored copy), and the chaos app count;
  - the "4 apps" counts in `lefthook.yml`, `bin/pre-release-test` and the release skill;
  - `chart.umd.min.js` in `docs/guides/ERROR_TREND_VISUALIZATIONS.md` and its `_guides/` mirror;
  - the gemspec comment, which says "the single AtomicReference", while a second one, at
    `system_health_snapshot.rb:147`, holds a Hash;
  - the FAQ answer "Does it work with API-only Rails apps?", in `docs/FAQ.md` and
    `_reference/faq.md`. It still says the dashboard needs a separate admin app; after this change
    it works in the API app itself, with its own session.
- **Release notes:**
  - "API-only hosts no longer get app-wide sessions or cookies from RED. An endpoint that writes the
    session raises `DisabledSessionError` again, and cookies that a host's own API controllers set
    are no longer sent, as without RED. The dashboard keeps its own session.";
  - "In API-only hosts, the dashboard's cookie is now `_rails_error_dashboard_session`: pick the
    language again once, and a tab left open gets one rejected form post.";
  - "concurrent-ruby >= 1.3.7".
