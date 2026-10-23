# Design: test gaps for 0.17.0

## Approach
Each gap gets the cheapest check that can actually fail. That means a spec where the behaviour
lives in RED's process, a chaos assertion where only a real production app shows it, and a CI job
where the behaviour is CI itself. No product code changes: every fix is in specs, chaos scripts,
workflows or the pre-commit config. Each new check gets a revert-one proof: break the behaviour
it guards, watch it fail, restore.

## Decision: Real threads on committed rows, run where the database honours row locks   (→ REQ-1)

**Context.** The two locking examples run inside the example's transaction, so they pass with or
without the lock. `notification_throttler_race_spec.rb` already shows the honest shape:
`:non_transactional`, committed rows, threads on their own connections, a latch. SQLite ignores
`FOR UPDATE`. Before Rails 8.0 it also opens transactions deferred, so two read-then-write
transactions deadlock with `SQLITE_BUSY` instead of queueing (the 8.0 and 8.1 adapters default to
`default_transaction_mode: :immediate`; 7.2 has no such setting).

**Alternatives.**
1. Threads on committed rows on every adapter.
2. Threads on committed rows, skipped on SQLite with the reason; the PostgreSQL and MySQL CI
   rows run it. The race window is widened by wrapping the increment in a short sleep, so a
   missing lock loses an update every time instead of now and then.
3. Separate processes instead of threads.

**Case for 2.** It fails exactly when the lock is missing, on the two databases where the lock
does anything, and it is deterministic. Threads with their own connections are separate database
sessions, which is all the lock cares about, and the suite already uses that pattern.

**Case against 2.** The default SQLite rows (20 of them) skip it. The sleep wrapper reaches into a
private method of the command. On MySQL, `find_wont_fix` also reads `FOR UPDATE`, and under
InnoDB's repeatable read that locking read may lock the unresolved row too, depending on the
plan. So a missing lock on `find_unresolved` alone is proven on PostgreSQL, not MySQL.

**Decision.** Option 2. The old examples are replaced, since neither can fail. Every capture
passes the row's `application_id` and environment, so each thread takes the
`find_unresolved` → `increment_existing` path and none falls through to a new group or an
environment adoption. The revert-one proof runs on PostgreSQL.
**Falsifiability.** We would reverse this if the PostgreSQL or MySQL CI row is removed from
`test.yml`, leaving no row that runs the example.
**Fired-if.** `! grep -qE 'postgresql|mysql' .github/workflows/test.yml`

## Decision: Prove the drains in a booted child process   (→ REQ-3, REQ-4)

**Context.** The engine registers its exit and end-of-work drains once, at boot, inside
`config.after_initialize`, and only for enabled features. The dummy app enables none of them
(storm protection is off), and `gate_drain_spec.rb` says it tests the entry points "rather than
the registration". Re-running the boot block in the suite would subscribe everything twice.

**Alternatives.**
1. A spec that starts a child Ruby process: it loads the dummy app, adds an initializer after the
   host's initializers that switches the five features on, boots, replaces each drain entry point
   (`flush_all_threads!`, `drain!`, `capture!`, `flush_if_due!`) with a recorder that prints a
   line, runs one `Rails.application.executor.wrap {}`, and exits normally. The parent asserts on
   the lines: the end-of-work drains print during the wrap, and the exit drains print as the child
   exits, through the real `at_exit` hooks.
2. Move the wiring into a named method and unit-test it with `at_exit` stubbed.
3. Chaos assertions in a production app.

**Case for 1.** It checks the real registration through the real boot path and the real process
exit, with no change to product code and no global state left in the suite. A missing or
misplaced `at_exit` line fails it.

**Case against 1.** It adds about 3-5 s for one boot, and four details have to be right or the
spec passes for the wrong reason:
- The dummy app has no `Bundler.require`, so the child must `require "rack/attack"` itself, or
  the engine skips the Rack::Attack wiring.
- The child's initializer must run `before: "rails_error_dashboard.crash_capture"`. Otherwise the
  boot-time crash hook sees the feature off, and the later fallback `enable!` registers the hook
  instead, which would hide that hook's removal. `at_exit` hooks run last-registered-first, so
  the crash drain printing last proves the boot-time registration.
- Boot imports crash files from `crash_capture_path`, which defaults to the shared temp dir. The
  child points it at a fresh directory, so boot writes nothing to the test database.
- Swallowed-exception detection needs Ruby 3.3+. On the 3.2 CI rows its exit drain is never
  registered, so those expectations are gated on the Ruby version.

The child is plain `ruby`, not `rails runner`: the runner's own executor would make the inner
`wrap` a no-op.

**Decision.** Option 1, one spec file, one child, both requirements.
**Falsifiability.** We would reverse this if the child boot makes the spec take longer than 15
seconds on a CI row, or if it fails intermittently twice in a month.
**Fired-if.** manual

## Decision: Phase F asserts what Rails actually does   (→ REQ-5, REQ-6, REQ-7)

**Context.** Seven checks in `phase_f_http_error_capture.rb` assert `true` on both branches. A run
on 2026-10-23 (Rails 8.1, production) took one branch every time: controller and action names
captured, Timeout captured, and the three `rescue_responses` exceptions never recorded. RED's
middleware sits at the top of the stack, above `ShowExceptions`, so request errors reach RED
through Rails' executor report, and Rails 7.1+ leaves `rescue_responses` exceptions out of it.

**Alternatives.**
1. Assert the observed outcome: names present (and the action equal to the endpoint's), Timeout
   captured as medium, and for the three mapped exceptions the mapped status plus no row. On a
   chaos app older than Rails 7.1, print an explicit skip for REQ-7's checks.
2. Keep the tolerance but print which branch ran.
3. Delete the tolerant checks.

**Case for 1.** Every check can now fail, and the "Rails didn't report it" cases become a pinned
fact: if RED or Rails starts recording a 404, someone has to look.

**Case against 1.** Chaos apps use whatever Rails the local `rails new` installs, so a Rails
change in reporting turns chaos red before anyone has decided whether it is a bug. The version gate
on REQ-7 is a branch, though one that says SKIP rather than passing.

**Decision.** Option 1.
**Falsifiability.** We would reverse this if REQ-7's assertions fail twice because of a Rails
change rather than a RED one.
**Fired-if.** manual

## Decision: Turn the TracePoint features on in the HTTP chaos app   (→ REQ-8, REQ-9, REQ-10, REQ-11)

**Context.** No chaos template enables local variables, instance variables or swallowed-exception
detection. The swallowed-exceptions page redirects when the feature is off, and Phase D accepts
200..399, so the page has never rendered in chaos. The flush interval's minimum is 1 second
(`configuration.rb` validation), and the flush runs at the end of a request on the thread whose
buffer is due. Swallowed detection needs Ruby 3.3+.

**Alternatives.**
1. `full_http`: enable the three features in its template, add two endpoints to the injected test
   controller (one sets locals and an instance variable, then raises; one rescues without
   re-raising), set the flush interval to 1 second, and poll for the swallowed row while sending
   requests that drive the end-of-request flush. Phase D then expects exactly 200 from the page.
2. `full_kitchen_sink`, which claims to enable every option.
3. A new chaos app.

**Case for 1.** `full_http` runs in `all`, the pre-commit set, so the features are exercised on
every chaos run. It already has the HTTP server and the injected controller.

**Case against 1.** The features add TracePoint overhead to every request in that app, and the
swallowed check depends on timing (a poll with a deadline, not a fixed sleep). The kitchen sink's
name stays a promise it doesn't keep. The details that decide whether the checks mean anything:
- Variables are stored as `{name => {"type", "value", "truncated"}}`, instance variables keyed
  `"@name"`, so the checks read `dig(name, "value")`.
- Names pass through a substring filter (RED's sensitive names plus the new app's
  `filter_parameters`), so the endpoint uses names and values none of them match.
- The swallowed tracker skips raises from paths under gems or Ruby, and flow-control classes,
  so the endpoint raises and rescues a custom class in the controller itself.
- Only a request on the same Puma thread flushes a buffer, and a new app runs 3 threads, so each
  poll round sends several requests. Buffers on worker threads die with the server, so the
  swallowed row must appear during Phase F's own server run.
- Phase D also runs in the API-only app, where the feature is off, so the exact-200 check is
  gated on the app's `detect_swallowed_exceptions`. The page shows 25 rows sorted by rescue
  count and the tracker also counts framework pairs, so the check asks for `per_page=100`.

**Decision.** Option 1. On Ruby below 3.3 the swallowed checks print an explicit skip.
**Falsifiability.** We would reverse this if the swallowed-exception poll times out on a run whose
other phase F checks pass, twice in a month.
**Fired-if.** manual

## Decision: The second app's migrations get versions after the first app's, and the first app's rows are compared   (→ REQ-12, REQ-13)

**Context.** The installer stamps each app's 52 migrations from the clock. The second app is
generated seconds after the first, so 43 of its versions are already in the shared
`schema_migrations` and never run (seen on 2026-10-23: Alpha 121146 onwards, Beta 121155 onwards).
That includes the migration whose replay used to wipe every error's environment. A real second
app installs on another day and replays all 52. The plain `db:migrate` already migrates both
databases, unchecked.

**Alternatives.**
1. After Beta's generator runs, renumber its files in `db/error_dashboard_migrate/` (where the
   installer copies them with `--separate-database`) so that, in order, file i gets
   `alpha_max + 1 + i`. Plain integers, because the installer's own versions are a clock reading
   plus one per file, so their "seconds" run past 59 and date arithmetic rejects them. Snapshot
   Alpha's error IDs and environments to a file BEFORE Beta's first `db:migrate` (it migrates
   the shared database too). Then run a checked `db:migrate` and a checked
   `db:migrate:error_dashboard` (each step's `PIPESTATUS`, since the script has no `set -e`) and
   assert each of Beta's versions is recorded. Phase I compares the snapshot.
2. Sleep until the clock passes Alpha's last version (52 s or more).
3. Leave the timestamps and compare the snapshot only.

**Case for 1.** It reproduces the real-world case on every run, deterministically, and it would
have caught the environment wipe. Every migration step's exit status is checked.

**Case against 1.** The harness rewrites migration filenames, which no user does. A future
installer that names migrations differently breaks the rename step. That break is loud, but it
breaks. And the two halves catch different failures. On SQLite, reverting the replay fix makes
the replay abort: the table rebuild re-creates the `COALESCE(environment, '')` index on a table
without the column. REQ-12's exit check catches that. REQ-13's revert-one proof therefore uses a
migration that NULLs `environment` without failing, which is the PostgreSQL-shaped damage.

**Decision.** Option 1.
**Falsifiability.** We would reverse this if the installer gains its own way to choose migration
timestamps, making the rename unnecessary.
**Fired-if.** manual

## Decision: A `changes` job decides, and the upgrade job is skipped at the job level   (→ REQ-14, REQ-15)

**Context.** A job-level `if` can't see changed files, so the decision lives in a step today, and
the job reports success after skipping every step. GitHub counts a job skipped by its `if` as
passing for a required check, and shows it as Skipped.

**Alternatives.**
1. A small `changes` job runs today's decide script and outputs `upgrade`. The upgrade job
   `needs: changes` with `if: needs.changes.outputs.upgrade == 'true'`.
2. Fold the decision into `lint`.

**Case for 1.** One purpose per job, and the upgrade check shows as Skipped. The maintainer chose
it at intake, and made `changes` required: unrequired, a failing `changes` job would skip the
upgrade test and let a release PR merge untested.

**Case against 1.** One more job (29 checks), and the upgrade test waits for it (seconds).

**Decision.** Option 1, with `changes` required.
**Falsifiability.** We would reverse this if GitHub stops counting a job skipped by `if` as
passing for a required check.
**Fired-if.** manual

## Decision: The `audit` job, its tools and its gates   (→ REQ-16, REQ-17, REQ-18)

**Context.** bundle-audit runs only in lefthook. `Gemfile.lock` is gitignored, so CI resolves
dependencies fresh. The matrix rows resolve older Rails versions, and Rails 7.0 is past end of
life with published advisories. actionlint and zizmor (1.7.12 and 1.31.1 locally) are not in CI.
GitHub release assets can be replaced. PyPI files can't: a version's files are immutable once
uploaded.

**Alternatives.**
1. One `audit` job in `ci.yml`, read-only token. bundle-audit from the Gemfile's development group
   with `--update` on the default resolution. actionlint from its pinned release tarball, checked
   against a SHA-256 written in the workflow. zizmor pinned by version from PyPI through `pipx`,
   on `.github/workflows/`, run online with the job's read-only token passed as `GH_TOKEN`
   (without it zizmor silently skips its online audits), at `--min-severity low`. Its online
   audits (impostor commits, known-vulnerable actions, version comments that don't match the
   pinned SHA) then check the new pins.
2. The official zizmor and actionlint actions, pinned by SHA.
3. bundle-audit in `lint`, and the workflow linters in a separate job.

**Case for 1.** One required check whose name says what it guards, and no third-party actions
beyond the ones every job already uses. PyPI never lets a file be replaced once uploaded, so the
version pin holds the wheel we tested, though a new wheel can still be added to the release. The
checksum makes the tarball a content pin. Auditing only the default resolution means the job fails on news about
the gems a fresh install gets, not every day on Rails 7.0's known advisories.

**Case against 1.** The older-Rails resolutions are never audited. Online zizmor depends on the
GitHub API (a rate limit or outage fails the job). Bumping actionlint means editing a checksum by
hand, and Dependabot won't do it.

**Decision.** Option 1.
**Falsifiability.** We would reverse this if the `audit` job fails for a reason outside the PR
(the GitHub API or the advisory database fetch) more than twice in a month.
**Fired-if.** manual

## Decision: Fix today's findings and pin every action   (→ REQ-18, REQ-19)

**Context.** At low severity and above, zizmor reports 22 unpinned action references (`ci.yml`,
`test.yml`, `pages.yml`, `smoke-test-demo.yml`), workflow-level `pages: write` and
`id-token: write` in `pages.yml`, a pages checkout that persists credentials, three ad-hoc
`gem install` lines (`rails` twice for `rails new`, `jekyll bundler` for Pages), and one
`./.github/workflows/...` call that it would rather see as `$/...`. actionlint reports two shellcheck SC2209 warnings
(`RAILS_ENV=test bundle ...` in `test.yml`). `release.yml` is already SHA-pinned (ci-least-privilege
REQ-13), and Dependabot's `github-actions` updates run weekly.

**Alternatives.**
1. Fix them: pin every action to the commit SHA of the release it names, with the version in a
   comment naming the exact tag, since an online audit checks the comment against the SHA
   (reusing `release.yml`'s pins where versions match). Move the Pages permissions to the jobs
   that use them. Set `persist-credentials: false`. Quote the two assignments. Extend the SHA-pin
   guard in `workflows_spec.rb` from `release.yml` to every file in `.github/workflows/`. The
   four low findings that are deliberate get an inline `# zizmor: ignore[...]` with the reason:
   the `gem install` lines install tools, not app dependencies, and the `$/` syntax would break
   the guard that checks the smoke-test call.
2. A zizmor config that ignores the existing findings.

**Case for 1.** The gate means something on day one, Dependabot keeps the pins current, and
every suppression sits on the line it excuses, with its reason.

**Case against 1.** `pages.yml` runs only on pushes to main, so its job-level permissions are
first exercised after the merge. If `configure-pages` needs a permission the build job lacks, the
docs deploy fails once and needs a follow-up.

**Decision.** Option 1. The build job gets `contents: read` and `pages: read`; the deploy job
`pages: write` and `id-token: write`.
**Falsifiability.** We would reverse the Pages part if the first docs deploy after the merge fails
on a permission.
**Fired-if.** manual

## Decision: Drop the hook's guard; test the command, prove the hook at runtime   (→ REQ-21)

**Context.** Lefthook 2.1.14 substitutes `{staged_files}` so that `"{staged_files}"` becomes
`"a_spec.rb" "b_spec.rb"`: `[` then fails with "binary operator expected", the `if` is false, and
the hook passes. Seen on 2026-10-23 with two staged specs, one failing. With one staged spec, the
hook ran it and failed. Lefthook's `glob` already skips the command when nothing matches, so the
guard does nothing useful. Lefthook isn't installed in CI, and a nested rspec run inside the suite
would share the SQLite test database.

**Alternatives.**
1. `run: bin/with-ruby bundle exec rspec {staged_files}`. A spec reads `lefthook.yml` and asserts
   the command passes the staged files straight to rspec with no shell test around them, and the
   runtime proof (two staged specs, one failing, the hook fails) is a task's done-when.
2. Keep a guard written to survive the quoting (`[ -n "$(echo {staged_files})" ]`).

**Case for 1.** The smallest command that can't misparse, and the runtime proof uses the real
tool.

**Case against 1.** The spec checks the command's shape, not lefthook's behaviour. A lefthook
change in substitution would be caught only by the next commit with two specs staged.

**Decision.** Option 1.
**Falsifiability.** We would reverse this if a commit with two or more staged specs passes the hook
while one of them fails.
**Fired-if.** manual

## Decision: Widen the ruleset after the merge, through the API   (→ REQ-20)

**Context.** The "Protect main branch" ruleset (strict) requires 16 checks. A required check whose
name doesn't match a check run blocks merges for good, and the new jobs' names exist only once
they've run.

**Alternatives.**
1. After the PR merges and the push run passes, add the 13 missing contexts with
   `gh api -X PUT repos/.../rulesets/<id>` from the current ruleset JSON, then read it back.
2. Widen it before merging the PR.

**Case for 1.** The names are copied from real check runs, so they match exactly, and no open PR
is blocked by a check it can't produce. Release PR #310 regenerates on the next push to main.

**Case against 1.** For the time between the merge and the change, the new checks don't block.
The ruleset lives outside the repository, so only reading it back proves it.

**Decision.** Option 1, with the maintainer's OK at the time.
**Falsifiability.** We would reverse this if GitHub adds a way to require checks from the workflow
file itself.
**Fired-if.** manual

## Data / interface changes
None in the gem. New CI check names: `audit`, `changes`. The upgrade check keeps its name, so
the ruleset entry stays valid.
