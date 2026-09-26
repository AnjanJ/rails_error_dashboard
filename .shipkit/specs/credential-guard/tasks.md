# Tasks: Credential guard

Test first for each. Every new example was run against the unfixed code first: 19 of the 26
failed, all for the bug itself.

- [x] **T1** `Configuration#credentials_problem`, `#default_credentials?`,
  `#refuse_default_credentials?`, and the boot error naming the problem → REQ-1..5. Test:
  `configuration_validation_spec.rb`, "credentials taken from the environment", uses real ENV and
  builds a fresh configuration. The old "returns false when username is changed" example encoded
  the bug and now asserts true.
- [x] **T2** The login denies blank credentials, and refused credentials outside development and
  test → REQ-6, REQ-7. Test: `dashboard_authentication_spec.rb`, "with credentials the boot check
  refuses", including a staging login on the defaults with the boot check out of the way.
- [x] **T3** `error_dashboard:verify` uses the same rule → REQ-8. Test: `verify_task_spec.rb`,
  "with credentials the boot check refuses".
- [x] **T4** Verification.
  - Full suite 5,369 examples, 0 failures, on three seeds.
  - A probe of boot and login for every bypass, against this branch and 0.14.1.
  - The same probe against the published 0.5.3, 0.5.5, 0.9.1, 0.13.0 and 0.14.1 gems, to set the
    advisory range: every release before the fix.
- [ ] **T5** The release notes carry a "this can stop an app booting" section, as 0.9.1 did.
- [ ] **T6** New GHSA (range `< 0.14.2`, CVE requested), published once 0.14.2 is on RubyGems.
