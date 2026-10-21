# Design: Credential guard

## D1. Which credentials count as a deliberate choice

**Context.** The guard has to refuse the published credentials, but the live demo runs in
production on exactly those credentials, on purpose: Render sets both variables to the defaults.
The old rule honoured that with "any env var set means a deliberate choice". That let one
variable vouch for both credentials, and let an explicitly empty value count as a choice.

**Alternatives.**
- (A) Keep the key-presence rule and add a blank check. This still leaves the fallback password
  open when only `ERROR_DASHBOARD_USER` is set.
- (B) Value provenance. The published password is acceptable only when `ERROR_DASHBOARD_PASSWORD`
  itself supplies it, and a blank credential is never acceptable.
- (C) Refuse the published password always, even when set explicitly.

**Case for B.**
- It closes every known bypass: one variable, empty variables, and an initializer that hardcodes or
  blanks a value.
- It keeps the one documented deliberate choice, and the demo.
- It is one method (`Configuration#credentials_problem`). `default_credentials?`, `validate!`, the
  login and the verify task all read it, so there is one rule instead of three.
- (C) would take the public demo offline.

**Case against B.**
- It reads `ENV` when it runs, while the values were captured by `ENV.fetch` when the
  configuration was built. The two only disagree if ENV changes after boot.
- An app that deliberately serves the published password from an initializer or Rails credentials
  is now refused, and has to move the value into `ERROR_DASHBOARD_PASSWORD`.
- An app that uses an empty username with a real password stops booting. The error names the fix.

**Decision.** B.

**I would reverse this if** a real deployment is refused while deliberately serving the published
password through a mechanism other than `ERROR_DASHBOARD_PASSWORD`, and cannot switch to the env
var.

## D2. Guard the login as well as boot

**Context.** The boot check does not run in development, and it is skipped while
`SECRET_KEY_BASE_DUMMY` is set for asset builds. If that variable is left set at runtime, nothing
else stood in the way.

**Alternatives.**
- (A) Boot check only.
- (B) Also deny the login when a credential is blank (every environment), or when
  `refuse_default_credentials?` is true.

**Case for B.** Fail closed at the point of use. It affects only setups the boot check would
refuse anyway, and a blank credential can never authenticate. This matches the existing nil guard
added in 0.13.0.

**Case against B.**
- A second enforcement point has to stay in step with the first. That is why both read
  `refuse_default_credentials?`.
- In development with blank credentials, the dashboard can no longer be opened at all.

**Decision.** B.

**I would reverse this if** a supported deployment needs to log in with a blank credential.
