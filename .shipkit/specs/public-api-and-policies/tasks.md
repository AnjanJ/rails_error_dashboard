# Tasks: The public API document and the release policies

Test first in every task: the cited test fails before the change and passes after it. Every test
cites `public-api-and-policies/REQ-N`. One commit per task, test and code together.

`R` below stands for `env -u RAILS_VERSION bin/with-ruby bundle exec`. Run one rspec process at a
time. This spec's PR merges after `deprecations-0-18` and `webhook-v1`; its lists describe the
surface they leave.

- [ ] **T1** The public API page, and the spec that keeps it in step with the code → REQ-1, REQ-2, REQ-3
  - Files: docs/PUBLIC_API.md, docs/guides/CONFIGURATION.md, _guides/configuration.md, spec/docs/public_api_spec.rb
  - Test: public_api_spec. Written first, against a page that names only the groups, so it fails
    listing every missing name.
    - **What it enumerates from the code,** as the design's table says:
      - config setters, less `reset!`;
      - literal ENV reads under `lib/`, less a named internal list;
      - RED's rake tasks;
      - the install generator's `class_options`;
      - the 12 plugin `on_*` hooks;
      - the module's singleton methods, less the two `reset_*` helpers.
    - **How it compares:** each group's fenced list must equal its code set, in both directions.
    - **What else it checks:**
      - every config option is in CONFIGURATION.md, including the 11 coverage and LLM options;
      - deprecated names carry their removal version;
      - the public URLs are exactly `GET /health` (with every health JSON field and status,
        including `skipped`), `POST /webhooks/:provider` and `/errors/:id`;
      - the private section exists;
      - the page links CONFIGURATION.md, API_REFERENCE.md, WEBHOOKS.md and PLUGIN_SYSTEM.md
  - After: none
  - Done when: `R rspec spec/docs/public_api_spec.rb` → 0 failures
- [ ] **T2** The policy page and SECURITY.md → REQ-4, REQ-5, REQ-6, REQ-7
  - Files: docs/VERSIONING.md, SECURITY.md, README.md, spec/docs/versioning_policy_spec.rb
  - Test: versioning_policy_spec:
    - VERSIONING.md states each rule in decision 0007, including the 0.x window ending
      2027-06-30;
    - SECURITY.md's supported-versions table matches it (no "latest only");
    - README links PUBLIC_API.md and VERSIONING.md;
    - decision 0007 is marked accepted
  - After: T1
  - Done when: `R rspec spec/docs/versioning_policy_spec.rb` → 0 failures
