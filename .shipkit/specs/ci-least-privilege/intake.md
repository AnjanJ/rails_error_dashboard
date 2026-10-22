# Intake: CI least privilege

> Intake taken on 2026-10-22.

## Request
Harden the GitHub Actions workflows to least privilege:

1. `release.yml`: split the `release` job so the test suite and RuboCop (which run freshly resolved
   development gems) run in a job without `id-token: write`, and only a minimal publish job can
   request the RubyGems publishing token. Declare permissions per job, and set
   `persist-credentials: false` where nothing pushes. Do the same for the `republish` escape hatch.
   Keep the smoke-test wiring, and keep the file name `release.yml`, which the RubyGems trusted
   publisher is keyed to.
2. `ci.yml` (`upgrade` job) and `release.yml` (`republish` job): pass `github.head_ref` and
   `inputs.version` to the shell through `env:`, quoted, instead of interpolating them into the
   script.
3. `ci.yml` and `test.yml`: a top-level `permissions: contents: read`.

## Serves goal
Ship 1.0: "v1.0.0 published on RubyGems with config and public API frozen". Every release on the
way there (0.17 → rc1 → 1.0) goes through `release.yml`.

## Conflicts found
None. Searched: the non-goals in `.shipkit/product.md`; the one open spec
(`.shipkit/specs/async-job-reconstruct/`, about the async job, not CI); the decision records in
`.shipkit/decisions/` (only 0001, about other gems' files).

## Answers
1. **Should the publish job run in a GitHub environment?** Yes. An environment that only `main`
   can deploy to, with no required reviewers. Once a release has gone through it, the maintainer
   restricts the RubyGems trusted publisher to that environment on rubygems.org.
2. **Pin the actions to commit SHAs?** Yes, in `release.yml` only: checkout, setup-ruby,
   release-please-action and release-gem, each with a version comment. Dependabot already updates
   the `github-actions` ecosystem.
3. **Switch the repo's default workflow token to read-only?** Yes, after the PR merges and the
   next runs are green. "Allow GitHub Actions to create and approve pull requests" stays ON, because
   release-please opens the release PRs with that token.
4. **Install actionlint and zizmor locally?** Yes, both, with Homebrew. Adding them to CI belongs
   to the separate decision about which checks CI runs, not this spec.

## Assumptions made
- **The publish job must keep `contents: write`.** `rubygems/release-gem` runs Bundler's
  `rake release`, which creates and pushes the `vX.Y.Z` tag before it uploads the gem. The 0.16.2
  release log shows "Tagged v0.16.2. Pushed git commits and release tag." before "Pushing gem to
  https://rubygems.org...", and `git ls-remote` shows both `v0.16.2` and
  `rails_error_dashboard/v0.16.2`. If that push failed, the upload would never happen.
- **`persist-credentials: false` is safe on the publish job.** release-gem stores
  `inputs.token` (the job's `github.token`) in its own git credential cache before it pushes
  (release-gem `action.yml`, step "Configure Git using cached credentials").
- **`BUNDLE_WITHOUT=development:test` alone excludes almost nothing today.** The `Gemfile` has no
  groups: pg, trilogy, puma, sqlite3, rubocop-rails-omakase, lefthook, solid_queue and the rest sit
  in the default group. Only the gemspec's `add_development_dependency` gems land in
  `:development`. The design must settle what the publish job installs.
- **Nothing in `ci.yml` or `test.yml` needs more than `contents: read`.** No job comments, uploads
  artifacts, or calls the GitHub API. `actions/cache` authenticates with the runner's cache token,
  not `GITHUB_TOKEN`.
- **The trusted publisher keeps working after the split.** RubyGems keys it to the repository, the
  workflow file name and, optionally, an environment, not to a job name.
- **The `smoke-test` job keeps `contents: read` and `issues: write`.** A calling job must grant
  what its reusable workflow asks for, or GitHub rejects the whole workflow at startup (the comment
  above `smoke-test:` in `release.yml`).
- `base_ref` in the `upgrade` job moves into `env:` too, for consistency, although only
  maintainers control branch names in the base repository.

## Out of scope
- Adding actionlint, zizmor or `bundle audit` to CI, and choosing which PR checks are required.
- `pages.yml`, which already declares its permissions and is not part of the release path.
- Any change to the gem's code or to what ships in the gem.
- Required reviewers on the environment.
