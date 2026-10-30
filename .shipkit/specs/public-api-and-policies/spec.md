# Spec: The public API document and the release policies

> Spec accepted at commit `6b1dfab` on spec/0-18-0 (2026-10-29).
> Status: open
> Paths: docs/PUBLIC_API.md,docs/VERSIONING.md,SECURITY.md,README.md,.shipkit/decisions/,spec/docs/

## Purpose
1.0 promises that every 1.x minor is safe to take on `bundle update`. A promise like that needs two
written things. One is the list of what's covered, so users know what they can rely on and the
maintainer knows what can't change. The other is the rules for how it changes: deprecations,
supported versions, security fixes. This spec writes both and keeps the list in sync with the code.

## User stories
- As a developer pinning `~> 1.0`, I want to know which config, tasks, hooks, URLs and payloads are
  covered by SemVer, so that I build only on those.
- As a developer on Rails 7.1, I want to know how long 0.x gets security fixes, so that I can plan
  my upgrade.
- As the maintainer, I want CI to tell me when I add public surface without documenting it, so that
  the list never falls behind.

## Requirements (EARS)

### The public API page
- **REQ-1.** `docs/PUBLIC_API.md` shall list every public surface with its stable form:
  - **config:** every option, by name, linked to its type and default in the configuration
    reference (`docs/guides/CONFIGURATION.md`), with the deprecated ones marked with the version
    that removes them (reworded at the design gate, 2026-10-29, so there's one table, not two);
  - **ENV:** every name RED reads;
  - **Ruby API:** the module methods; `ManualErrorReporter.report` and its arguments; every plugin
    hook and its arguments;
  - **command line:** every generator and its options; every rake task, with the deprecated aliases
    marked;
  - **URLs:** `GET /health` and its JSON (every field and status, including `skipped`);
    `POST /webhooks/:provider`; the error page URL;
  - **integrations:** the outbound webhook contract (linking the contract page); OTel span names and
    attributes.
- **REQ-2.** `docs/PUBLIC_API.md` shall name what's private and can change in any release:
  - database tables, columns and models;
  - job classes and their arguments;
  - classes and modules not listed on the page;
  - i18n keys;
  - the dashboard's HTML, CSS and JS;
  - every dashboard URL not listed as public.
- **REQ-3.** A spec shall fail when any of these, as found in the code, is missing from
  `docs/PUBLIC_API.md`, or when the page lists one the code doesn't have:
  - a config option or an ENV name;
  - a rake task or a generator option;
  - a plugin hook or a module method.

### The policies
- **REQ-4.** A policy page in `docs/` shall state:
  - **versioning:** SemVer from 1.0.0;
  - **deprecations:** a deprecation warns for at least two minor releases and is removed only in a
    major; the last minor before a major warns about everything that major removes;
  - **minimums:** Rails and Ruby minimums rise only at a major;
  - **migrations:** migrations in a minor are additive and safe to run twice;
  - **security fixes:** for the current major, and for the previous major's last minor;
  - **0.x after 1.0:** security fixes only, on the last 0.x minor, until 2027-06-30.
- **REQ-5.** SECURITY.md's supported-versions table shall match the policy page.
- **REQ-6.** The README shall link the public API page and the policy page.

### The record
- **REQ-7.** The policies shall be recorded as decision record `.shipkit/decisions/0007` [untested:
  a record, checked by `decision-check.sh`, not by a spec].

## Out of scope
- Removing the "Beta" label and the full docs pass (1.0.0.rc1).
- The 0.x to 1.0 upgrade guide (1.0.0.rc1).
