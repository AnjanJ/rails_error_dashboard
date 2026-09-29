# Design: Keep RED's hands off Solid Queue (0.14.3)

## D1: Run the real Solid Queue in a child process

- **Context:** RED branches on `defined?(::SolidQueue)` (`SystemHealthSnapshot`, `verify`). Loading
  Solid Queue into the test process would change how other specs behave, depending on run order.
- **Alternatives:** (a) require Solid Queue in the contract spec; (b) run a probe script in a child
  process and compare its JSON.
- **Case for (b):** no leak into other specs; the probe boots a minimal Rails app with Solid Queue's
  engine and an in-memory SQLite database, so `QueueSelector` runs its real queries.
- **Case against (b):** a few seconds per run, and a second Ruby process to debug when it fails.
- **Decision:** (b). **I would reverse this if** the probe takes more than 10 seconds on CI.

## D2: Compare facts, not messages

- **Context:** the check returns sentences; the library returns process lists.
- **Alternatives:** (a) match message text against the library's results; (b) give the check a
  `processes_for` method that returns the same facts the probe does (dispatcher count, worker
  process count, processed queues, error), and build the messages from it.
- **Case for (b):** counts and queue sets compare exactly; message wording can change without
  touching the contract.
- **Case against (b):** a refactor of a check that shipped yesterday, a day before its release.
- **Decision:** (b). **I would reverse this if** the facts and the messages ever disagree in a spec.

## D3: Resolve the newest Solid Queue on every CI run

- **Context:** CI deletes `Gemfile.lock` and resolves fresh.
- **Alternatives:** (a) pin a Solid Queue version; (b) take the newest on every run.
- **Case for (b):** a Solid Queue release that changes its rules turns CI red before users meet it.
- **Case against (b):** an unrelated PR can go red on the day Solid Queue ships a change.
- **Decision:** (b); that red is the point. **I would reverse this if** Solid Queue changes break
  unrelated PRs more than twice in a quarter.

## D4: Link to Solid Queue's README instead of copying its install steps

- **Context:** the guide copied `bundle add` / `solid_queue:install` / `db:prepare`. What that
  installer does has already changed once (it now rewrites `production.rb`).
- **Alternatives:** (a) keep the steps and add warnings; (b) link out, and document only what RED
  needs from the config.
- **Case for (b):** RED's docs can't go stale when Solid Queue's installer changes.
- **Case against (b):** one more click for a new user.
- **Decision:** (b). The warning against re-running the installer names the version it was checked
  on. **I would reverse this if** Solid Queue's README stops covering installation.
