# Spec: Credential guard (partial and blank credentials)

> Spec accepted at commit `ed31388` on main (2026-09-26). Decisions taken at the Q1 gate: refuse
> **any** blank credential; guard the **login** as well as boot; disclose through a **new GHSA**
> with a CVE requested, published once the fix is on RubyGems.

## Purpose

GHSA-qhgm-3pxf-mvc6 (fixed in 0.9.1) makes RED refuse to boot outside development and test while
the dashboard runs on its published credentials. The guard could still be bypassed:

- `default_credentials?` stood down as soon as EITHER env var existed. Setting only
  `ERROR_DASHBOARD_USER` left the password on the published default.
- Since 0.5.3 the check required the default username AND the default password, so a custom
  username in an initializer did the same.
- An explicitly empty variable (a compose file passing an unset variable through) counted as a
  deliberate choice, and `""` then matched an empty Basic login.
- A `SECRET_KEY_BASE_DUMMY` left set at runtime skipped the boot check entirely.
- `error_dashboard:verify` reported blank credentials as "custom" and only checked `production?`.
- `authenticate_with = false` (what `Rails.env.production? && -> { ... }` gives in staging) made
  the check stand down, while the login fell back to Basic auth on the published credentials.
  Found while writing the review brief.
- The independent review (2026-09-27) found two more:
  - the published password held as a Symbol passed the check but logged in, because the login
    compares with `to_s`;
  - a password of only Unicode whitespace (e.g. a no-break space) was not blank to
    `String#strip`, so it passed and logged in.

Every release was affected: before 0.5.3 there was no check at all.

## Requirements (EARS)

- **REQ-1:** If the effective dashboard password, compared as the login compares it (`to_s`),
  equals the built-in default and
  `ENV["ERROR_DASHBOARD_PASSWORD"]` does not itself equal it, then `default_credentials?` shall be
  true.
- **REQ-2:** If the effective username or password is blank (nil, empty, or only whitespace,
  including Unicode whitespace), then
  `default_credentials?` shall be true, whatever the environment variables say.
- **REQ-3:** Where `ERROR_DASHBOARD_PASSWORD` supplies a non-blank effective password,
  `default_credentials?` shall be false, even when that password is the default (the live demo).
- **REQ-4:** Where `authenticate_with` is truthy, `default_credentials?` shall be false. A falsy
  value (`nil` or `false`) means Basic auth is active, exactly as the login treats it.
- **REQ-5:** When `validate!` runs outside development and test and REQ-1 or REQ-2 holds, it shall
  raise `ConfigurationError` naming the environment, the specific problem and the fix.
- **REQ-6:** If a configured Basic credential is blank, then the dashboard shall deny every login
  with a 401, in every environment.
- **REQ-7:** While `refuse_default_credentials?` is true, the dashboard shall deny every Basic login
  with a 401, even when the boot check was skipped (`SECRET_KEY_BASE_DUMMY`).
- **REQ-8:** `error_dashboard:verify` shall report default or blank credentials with the same rule
  and environment allowlist as `validate!`, and never as "custom credentials".

## Out of scope

- Password strength. An explicitly chosen weak password is still a choice.
- The banner copy in the 11 locales. It already calls `default_credentials?`, so it now also shows
  for the partial case in development.
