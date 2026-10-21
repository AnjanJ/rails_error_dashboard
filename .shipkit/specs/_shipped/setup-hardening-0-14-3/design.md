# Design: Setup hardening (0.14.3)

## D1: Retire the Solid Queue generator instead of fixing its template

- **Context:** the template had no dispatcher, which stopped every delayed job in the host app. Solid
  Queue's own `solid_queue:install` already writes a `queue.yml` with `queues: "*"` and a dispatcher,
  which processes RED's queues. The chaos "full_solid_queue" app runs jobs inline, so it never
  exercised this file.
- **Alternatives:** (a) fix the template (add dispatchers, never overwrite an existing file);
  (b) retire it: write nothing, check an existing file, and point to Solid Queue's installer.
- **Case for (b):** nothing is left to drift from Solid Queue's config format, which is how the bug
  happened. The generator's only extra was a per-queue thread split that nobody showed was needed.
  The check still reaches people who ran the old generator.
- **Case against (b):** a patch release removes behaviour. Anyone scripting the generator no longer
  gets a file, and the per-queue split is gone.
- **Decision:** (b), chosen by the user. The generator prints a deprecation, and removal follows in a
  later minor. **I would reverse this if** someone reports needing RED-specific worker tuning that
  `queues: "*"` can't express.

## D2: Discover the tables and order them by their foreign keys

- **Context:** a hand-kept list of 5 tables fell 8 tables behind, and its "reverse order" comment
  was wrong.
- **Alternatives:** (a) a constant listing all 13 in drop order, plus a spec; (b) discover every
  `rails_error_dashboard_*` table on the connection and sort by `foreign_keys`.
- **Case for (b):** future tables are covered without anyone remembering, and older installs that
  lack some tables need no special case. The order comes from the real schema, not from a comment.
- **Case against (b):** a host table that happens to use the `rails_error_dashboard_` prefix would be
  dropped. A foreign-key cycle needs handling (none exists today).
- **Decision:** (b), with a cycle raising a clear error. The confirmation screen lists every table
  before anything is dropped. **I would reverse this if** a user reports a non-RED table with the
  prefix.

## D3: Accept `log_level = :fatal` rather than reject it

- **Context:** `validate!` accepted `:fatal` and the logger didn't define it.
- **Alternatives:** (a) remove `:fatal` from the accepted list; (b) define it as a real level above
  `:error`.
- **Case for (b):** apps that set `:fatal` keep booting and get what the name promises: RED logs
  nothing below fatal, and it has no fatal messages. Deriving the accepted list from
  `LOG_LEVELS` removes the two-list drift that caused the bug.
- **Case against (b):** `:fatal` and `:silent` now behave the same, which is redundant.
- **Decision:** (b). **I would reverse this if** RED ever needs a real fatal-level message that must
  differ from `:silent`.

## D4: `USE_SEPARATE_ERROR_DB` is a docs fix, not a code fix

- **Context:** the generated initializer always sets `use_separate_database`, so the variable
  never takes effect on generator installs.
- **Alternatives:** (a) make the template leave the option unset, so the variable applies; (b) leave
  the code and document the variable accurately.
- **Case for (b):** the variable alone can't work anyway: `config.database` has no env default, so
  `validate!` refuses to boot. Moving to a separate database also needs database.yml entries and
  migrations. A one-variable switch would silently split data.
- **Case against (b):** the variable stays half a feature.
- **Decision:** (b), in docs PR A. **I would reverse this if** we add an env default for
  `config.database` and a supported one-step migration between databases.

## D5: One PR with five commits and a changelog override

- **Context:** `main` requires branches to be up to date, with 16 checks, and allows only squash
  merges.
- **Alternatives:** (a) five PRs; (b) one PR with atomic commits and release-please's
  `BEGIN_COMMIT_OVERRIDE` in the PR body.
- **Case for (b):** one CI cycle instead of five sequential ones. It can be reviewed commit by
  commit, and the changelog still gets one line per fix.
- **Case against (b):** one contested fix holds up the rest, and the override is a manual step that
  can be mistyped.
- **Decision:** (b). The fallback is to put the same lines in the squash body at merge time.
  **I would reverse this if** the release PR's changelog shows fewer entries than fixes after both
  mechanisms.
