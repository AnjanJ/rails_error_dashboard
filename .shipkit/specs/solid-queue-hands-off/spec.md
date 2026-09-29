# Spec: Keep RED's hands off Solid Queue (0.14.3)

> Spec accepted at commit `d953f2d` on main (2026-09-29). Plan approved by the user the same day:
> the message and guide fixes plus the two test-only guards go into 0.14.3; the dashboard warning
> waits for 0.14.4.

## Purpose

RED 0.14.3 retires the generator that wrote a broken `config/queue.yml`, but its own output still
tells apps to run `bin/rails solid_queue:install`. On an app that already uses Solid Queue, that
installer (1.7.0) rewrites `config/environments/production.rb` to use a separate `queue` database,
which breaks apps running Solid Queue on their primary database, and offers to overwrite
`config/recurring.yml`. The people who see that advice are exactly the ones the old generator broke.

The config check copies Solid Queue 1.7.0's rules by hand, and CI never loads Solid Queue, so a
change in Solid Queue would go unnoticed. Running the real parser on sample configs shows the copy
is already wrong for three configs: `processes: 0`, `workers:` written as a map, and an empty
`workers:` or `dispatchers:` key.

## Requirements (EARS)

Advice:
- **REQ-1:** When `error_dashboard:verify` reports a Solid Queue config problem, the fix it prints
  shall not tell the user to run `solid_queue:install`.
- **REQ-2:** When `rails g rails_error_dashboard:solid_queue` runs, its output shall not tell the
  user to run `solid_queue:install`.
- **REQ-3:** If the app has no Solid Queue config file, then the generator shall say that Solid Queue
  runs its defaults, which process RED's queues.
- **REQ-4:** The Solid Queue guide shall link to Solid Queue's README for installing Solid Queue,
  instead of listing Solid Queue's install steps.
- **REQ-5:** The Solid Queue guide shall say what RED needs from a Solid Queue config: a dispatcher
  in every environment, a worker for RED's queues, and a running worker process.

Agreement with Solid Queue (for every sample config and environment, compared with the real
library):
- **REQ-6:** The config check shall count the dispatchers Solid Queue would start.
- **REQ-7:** The config check shall count the worker processes Solid Queue would start.
- **REQ-8:** The config check shall list the RED queues whose ready jobs a started worker would pick
  up.
- **REQ-9:** If Solid Queue would raise on the config, then the config check shall report that
  Solid Queue can't start with it.

Hands off:
- **REQ-10:** When the install generator runs (fresh or again), the uninstall generator runs, or the
  deprecated Solid Queue generator runs, it shall leave every file byte-for-byte unchanged except
  RED's initializer, RED's migrations and `config/routes.rb`.

## Out of scope

- The dashboard warning and boot log line (0.14.4).
- The guide's other Solid Queue errors (invented `max_retries`, `log/solid_queue.log`): docs PR B.
- `scheduler:` shape errors: Solid Queue's handling differs across 1.x releases.
