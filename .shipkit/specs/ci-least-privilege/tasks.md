# Tasks: CI least privilege

Run specs as `env -u RAILS_VERSION bin/with-ruby bundle exec rspec <files>`, one rspec process at a
time. Each test is written first and watched fail for the right reason.

- [x] **T1** Put every gem not needed to build and release the gem into the development and test groups → REQ-7
  - Files: spec/ci/workflows_spec.rb, Gemfile
  - Test: spec/ci/workflows_spec.rb "keeps only the gem, rails and the json constraint in the Gemfile's default group"
  - After: none
  - Done when: `env -u RAILS_VERSION bin/with-ruby bundle exec rspec spec/ci/workflows_spec.rb` → 0 failures, and the example was red before the Gemfile change
- [x] **T2** Read-only permissions, no persisted credentials and no expanded refs in ci.yml and test.yml → REQ-1, REQ-2, REQ-11, REQ-12
  - Files: spec/ci/workflows_spec.rb, .github/workflows/ci.yml, .github/workflows/test.yml
  - Test: spec/ci/workflows_spec.rb examples for REQ-1, REQ-2, REQ-11 and REQ-12 on ci.yml and test.yml
  - After: T1
  - Done when: `env -u RAILS_VERSION bin/with-ruby bundle exec rspec spec/ci/workflows_spec.rb` → 0 failures; `actionlint .github/workflows/ci.yml .github/workflows/test.yml` → only the two existing SC2209 notes in test.yml
- [ ] **T3** The smoke-test workflow declares the two secrets it reads, and its checkout persists no credentials → REQ-1, REQ-11, REQ-17
  - Files: spec/ci/workflows_spec.rb, .github/workflows/smoke-test-demo.yml
  - Test: spec/ci/workflows_spec.rb examples for REQ-1, REQ-11 and REQ-17 on smoke-test-demo.yml
  - After: T2
  - Done when: `env -u RAILS_VERSION bin/with-ruby bundle exec rspec spec/ci/workflows_spec.rb` → 0 failures; `actionlint .github/workflows/smoke-test-demo.yml` → no output
- [ ] **T4** Split release.yml into release, test, publish and smoke-test jobs with per-job permissions and pinned actions → REQ-1, REQ-3, REQ-4, REQ-5, REQ-6, REQ-8, REQ-9, REQ-11, REQ-12, REQ-13, REQ-14, REQ-15, REQ-17
  - Files: spec/ci/workflows_spec.rb, .github/workflows/release.yml
  - Test: spec/ci/workflows_spec.rb examples for each listed requirement on release.yml; the REQ-15 example runs the version-check script with a matching and a mismatched INPUT_VERSION
  - After: T3
  - Done when: `env -u RAILS_VERSION bin/with-ruby bundle exec rspec spec/ci/workflows_spec.rb` → 0 failures; `actionlint` → only the two SC2209 notes in test.yml; `zizmor --offline .github/workflows` → no template-injection, excessive-permissions, artipacked, cache-poisoning or secrets-inherit finding in the four workflows
- [ ] **T5** Create the rubygems environment, deployable from main only → REQ-10
  - Files: none (repository setting)
  - Test: none; checked with `gh api repos/AnjanJ/rails_error_dashboard/environments/rubygems/deployment-branch-policies`
  - After: none
  - Done when: that call lists exactly one policy, `main` of type `branch`, and the environment has no protection rule other than the branch policy
- [ ] **T6** Gate: the whole suite, chaos, linters and the spec checks → REQ-1, REQ-6
  - Files: none
  - Test: the publish-bundle dry run: in a scratch worktree with a scratch BUNDLE_PATH, `BUNDLE_WITHOUT=development:test bundle install` then `bundle exec rake build`
  - After: T4, T5
  - Done when: the dry run builds the gem and installs none of the moved gems; full suite 0 failures; chaos FINAL RESULTS all pass; `spec-check.sh . ci-least-privilege` and `decision-check.sh . --run` report no gaps and nothing fired

## After the gate

- Push over HTTPS, open the PR (hardening wording, `Refs` only), wait for CI.
- Merge only with the maintainer's OK. Then confirm the push to main started `release.yml` and ran
  release-please (REQ-16), and switch the repository's default workflow token to read-only.
- Optional, the maintainer's call: dispatch `release.yml` with `version` = the current version from
  main, to exercise the publish path up to RubyGems refusing the repush.
