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
- [x] **T7** A falsy `authenticate_with` counts as Basic auth → REQ-4. Test: `false` makes
  `default_credentials?` true, is refused at boot in staging, and a staging login on the defaults
  gets a 401. All three were red first. Full suite 5372 examples, 0 failures.
- [x] **T8** Independent review fixes → REQ-1, REQ-2, REQ-5.
  - One shared `Configuration.blank_credential?` (`to_s.blank?`, which is Unicode-aware) for boot
    and login.
  - The published-password comparison uses `to_s`.
  - The boot error tells the operator to make sure the initializer does not overwrite the
    variables.
  - Test: 11 new examples (5372 → 5383), all red before the fix. The message example first passed
    spuriously, because it matched the ConfigurationError footer, and was tightened until it
    failed.
  - The reviewer's 8 reproductions pass. Full suite 5383, 0 failures. Re-review of `3b54927`:
    no remaining blockers.
- [ ] **T5** The release notes carry a "this can stop an app booting" section, as 0.9.1 did.
- [ ] **T6** New GHSA (range `< 0.14.2`, CVE requested), published once 0.14.2 is on RubyGems.
