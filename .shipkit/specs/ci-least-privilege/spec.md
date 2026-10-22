> Spec accepted at commit 08c506e on ci/least-privilege (2026-10-22).
> Status: open
> Paths: .github/workflows/, Gemfile, spec/ci/

# Spec: CI least privilege

## Purpose

Give every GitHub Actions job only the token permissions it needs, and keep the RubyGems
publishing credential inside one small job.

Today `release.yml` grants `contents: write`, `pull-requests: write` and `id-token: write` at the
workflow level, so every step of the `release` and `republish` jobs holds all three. That includes
the full test suite and RuboCop, which run with gems Bundler resolves fresh at release time (the
`Gemfile.lock` is not committed). `ci.yml` and `test.yml` declare no permissions, so they get the
repository default, which is `write`. Every checkout leaves the job token in `.git/config`. Two
`run:` scripts expand workflow values (`github.head_ref`, `inputs.version`) straight into the shell
script.

In scope: `release.yml`, `ci.yml`, `test.yml`, `smoke-test-demo.yml` (called by `release.yml`), the
`Gemfile`'s groups, and one repository setting (the `rubygems` environment). Answers and assumptions
behind this spec: `intake.md`.

## Requirements (EARS)

### Permissions

- **REQ-1:** Every job in `release.yml`, `ci.yml`, `test.yml` and `smoke-test-demo.yml` shall run
  with token permissions declared in its own workflow file, at the workflow or the job level.
- **REQ-2:** The jobs in `ci.yml` and `test.yml` shall have `contents: read` and no other token
  permission.
- **REQ-3:** The release workflow shall grant `id-token: write` to exactly one job, the job that
  publishes the gem to RubyGems.
- **REQ-4:** The release workflow's job that runs the test suite and RuboCop shall have
  `contents: read` and no other token permission.
- **REQ-5:** The release workflow's release-please job shall have `contents: write` and
  `pull-requests: write` and no other token permission.

### What the publish job runs

- **REQ-6:** The publish job shall install gems with the `development` and `test` groups excluded.
- **REQ-7:** The `Gemfile`'s default group shall contain only the gem itself (through `gemspec`),
  `rails`, and the `json` constraint; every other gem shall be in the `development` or `test`
  group.
- **REQ-8:** When a release is created, or a republish is dispatched, the release workflow shall
  run the publish job only after the test job has passed in the same run.
- **REQ-9:** The publish job shall run in the `rubygems` GitHub environment.
- **REQ-10:** The `rubygems` environment shall accept deployments only from the `main` branch.
  `[untested: a repository setting, not a file; the task checks it with gh api]`

### Credentials and inputs

- **REQ-11:** Every `actions/checkout` step in the four workflows shall set
  `persist-credentials: false`.
- **REQ-12:** The four workflows shall not expand `github.head_ref`, `github.base_ref`,
  `github.event.*` or `inputs.*` inside a `run:` script; a script that needs one of these values
  shall read it from an environment variable.
- **REQ-13:** Every action that `release.yml` uses, other than a reusable workflow in this
  repository, shall be referenced by a full 40-character commit SHA.

### Behaviour kept

- **REQ-14:** When the gem has been published from a push to `main`, the release workflow shall run
  the demo smoke test, granting it `contents: read` and `issues: write`.
- **REQ-15:** If a republish is dispatched with a `version` input that differs from the version in
  `lib/rails_error_dashboard/version.rb`, then the release workflow shall fail before it runs the
  test suite or publishes.
- **REQ-16:** When a commit is pushed to `main`, the release workflow shall start and run
  release-please.
  `[untested: only GitHub decides whether a workflow starts (the earlier startup_failure came from a
  permission mismatch no file check caught); checked after merge with gh run list]`
- **REQ-17:** The release workflow shall pass the smoke-test workflow only the `DEMO_USER` and
  `DEMO_PASSWORD` secrets. (Added at the design gate, 2026-10-22.)

## Out of scope

- Adding actionlint, zizmor or `bundle audit` to CI, and choosing which PR checks are required.
- `pages.yml`.
- Required reviewers on the `rubygems` environment.
- Any change to the gem's code or to what ships in the gem.

## Release steps (not requirements)

- After merge: confirm the push to `main` started `release.yml` and release-please ran (REQ-16).
- After merge and green runs: switch the repository's default workflow token to read-only (intake
  answer 3).
- After the first release through the `rubygems` environment: the maintainer restricts the RubyGems
  trusted publisher to that environment on rubygems.org (intake answer 1).
